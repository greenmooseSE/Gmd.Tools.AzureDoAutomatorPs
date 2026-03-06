<#
.SYNOPSIS
Find an Azure DevOps work item by title

.DESCRIPTION
Searches Azure DevOps for a work item with the given title and returns the full
work item object if found. Optionally filter by work item type using the
`-Type` parameter (e.g. Epic, Feature, User Story).

When -NormalizeTitle is specified, searches for work items with titles matching
the base title (e.g., "Test story 2 (004)" matches search for "Test story 2"),
and uses WIQL CONTAINS for broader matching.

.PARAMETER Organization
Azure DevOps organization name (required)

.PARAMETER Project
Azure DevOps project name (required)

.PARAMETER Title
Work item title to search for (required)

.PARAMETER Type
Optional work item type to filter by (e.g. Epic, Feature, Story)

.PARAMETER ParentId
Optional parent work item ID to filter by (e.g. find Feature under specific Epic).
When specified with -NormalizeTitle, ensures match is found under the specific parent.

.PARAMETER NormalizeTitle
Switch: If specified, normalizes the title by stripping version suffixes like "(001)"
and uses CONTAINS matching. Useful for finding items that may have been created with
version suffixes.

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from
`GMD_AZDO_MACHINE_WORKITEMSRW` environment variable (expected to be encrypted).

.OUTPUTS
PSObject representing the found work item, or $null if not found. Throws error on unexpected failures.

.EXAMPLE
    $wi = .\FindAzDoItemByTitle.ps1 -Organization "myorg" -Project "myproj" -Title "My Epic" -Type Epic
    $feature = .\FindAzDoItemByTitle.ps1 -Organization "myorg" -Project "myproj" -Title "My Feature" -Type Feature -ParentId 123
    $story = .\FindAzDoItemByTitle.ps1 -Organization "myorg" -Project "myproj" -Title "Test story 2" -NormalizeTitle -Type "User Story" -ParentId 1635
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [string]$Title,

    [string]$Type,

    [int]$ParentId,

    [switch]$NormalizeTitle,

    [string]$PatToken
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Import shared helpers/constants
. "$PSScriptRoot/AzDoAutomatorConstants.ps1"
. "$PSScriptRoot/AzDoPatTokenHelper.ps1"
. "$PSScriptRoot/AzDoApiWrapper.ps1"
. "$PSScriptRoot/AzDoWorkItemHelper.ps1"

# Helper function to normalize title (strip version suffixes)
function Normalize-TitleForMatching {
    param([string]$Title)
    $normalized = $Title -replace '\s*\(\d+\)\s*$', ''
    return $normalized.Trim()
}

# Validate ssLogIt helper
if (-not (Get-Command -Name 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    Write-Error "Required helper script 'ssLogIt.ps1' not found in PATH. Ensure helper scripts are available."
}

# Validate parameters
if ([string]::IsNullOrWhiteSpace($Organization)) {
    Write-Error "Parameter 'Organization' cannot be empty."
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    Write-Error "Parameter 'Project' cannot be empty."
}

if ([string]::IsNullOrWhiteSpace($Title)) {
    Write-Error "Parameter 'Title' cannot be empty."
}

$null = & ssLogIt.ps1 -Level Info -Message "Searching for work item: ::FgGreen::$Title::FgDefault:: in project ::FgGreen::$Project::FgDefault::"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    # Determine normalized vs exact match behavior
    [string]$searchTitle = $Title
    [string]$normalizedSearchTitle = $null
    
    if ($NormalizeTitle) {
        $normalizedSearchTitle = Normalize-TitleForMatching -Title $Title
        $searchTitle = $normalizedSearchTitle
        $null = & ssLogIt.ps1 -Level Debug -Message "Normalized search title: ::FgGreen::$normalizedSearchTitle::FgDefault::"
    }

    # Escape single quotes in title for WIQL query (double them)
    [string]$escapedTitle = $searchTitle -replace "'","''"

    # Build WIQL query - use CONTAINS for normalized search, exact match for regular search
    [string]$query = "SELECT [System.Id], [System.Title], [System.WorkItemType], [System.Parent] FROM WorkItems WHERE [System.Title]"
    
    if ($NormalizeTitle) {
        $query += " CONTAINS '$escapedTitle'"
    } else {
        $query += " = '$escapedTitle'"
    }

    if ($PSBoundParameters.ContainsKey('Type') -and -not [string]::IsNullOrWhiteSpace($Type)) {
        $query += " AND [System.WorkItemType] = '$Type'"
    }

    if ($PSBoundParameters.ContainsKey('ParentId')) {
        $query += " AND [System.Parent] = '$ParentId'"
    }

    $logMessage = "Executing WIQL query for title ::FgGreen::$searchTitle::FgDefault::"
    $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

    # Build auth header directly (matching working command)
    [string]$authString = ":$PatToken"
    [byte[]]$authBytes = [System.Text.Encoding]::ASCII.GetBytes($authString)
    [string]$authBase64 = [System.Convert]::ToBase64String($authBytes)

    $headers = @{
        'Authorization' = "Basic $authBase64"
        'Content-Type'  = 'application/json'
    }

    $uri = "https://dev.azure.com/$Organization/$Project/_apis/wit/wiql?api-version=7.1"

    $body = @{ query = $query } | ConvertTo-Json

    $workItems = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -ErrorAction Stop

    if ($null -eq $workItems.workItems -or @($workItems.workItems).Count -eq 0) {
        $null = & ssLogIt.ps1 -Level Debug -Message "Work item not found: $searchTitle"
        return $null
    }

    # If NormalizeTitle is enabled, filter by normalized title match
    [object]$matchedItem = $null
    if ($NormalizeTitle) {
        $null = & ssLogIt.ps1 -Level Debug -Message "Filtering $(@($workItems.workItems).Count) CONTAINS results by normalized title match..."
        
        foreach ($wiRef in $workItems.workItems) {
            # For each candidate, get full details to check normalized title
            $full = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $wiRef.id -PatToken $PatToken -ErrorAction SilentlyContinue
            if ($null -ne $full -and $full.fields.'System.Title') {
                $candidateNormalized = Normalize-TitleForMatching -Title $full.fields.'System.Title'
                if ($candidateNormalized -eq $normalizedSearchTitle) {
                    # Found a match - check parent if specified
                    if ($PSBoundParameters.ContainsKey('ParentId')) {
                        if ($full.fields.'System.Parent' -eq $ParentId) {
                            $matchedItem = $full
                            $null = & ssLogIt.ps1 -Level Debug -Message "Found matching work item under parent $($ParentId):  ID $($full.id)"
                            break
                        }
                    } else {
                        $matchedItem = $full
                        $null = & ssLogIt.ps1 -Level Debug -Message "Found matching work item by normalized title: ID $($full.id)"
                        break
                    }
                }
            }
        }
    } else {
        # For exact match, just use the first result
        if (@($workItems.workItems).Count -gt 1) {
            $logMessage = "Multiple work items found with title ::FgGreen::$searchTitle::FgDefault::. Returning first match."
            $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"
        }

        # Retrieve full work item details for the first match
        $firstId = $workItems.workItems[0].id
        $matchedItem = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $firstId -PatToken $PatToken
    }

    if ($null -eq $matchedItem) {
        $null = & ssLogIt.ps1 -Level Debug -Message "No work item matched the search criteria: $searchTitle"
        return $null
    }

    $wiTitle = $matchedItem.fields.'System.Title'
    $wiType = $matchedItem.fields.'System.WorkItemType'
    $null = & ssLogIt.ps1 -Level Info -Message "Found work item: ::FgGreen::$wiTitle::FgDefault:: (Type: $wiType, ID: $($matchedItem.id))"

    return $matchedItem
}
catch {
    $null = & ssLogIt.ps1 -Level Error -Message "Failed to search for work item: $_" -Exception $_
    Write-Error $_
    throw
}
