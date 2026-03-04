<#
.SYNOPSIS
Find an Azure DevOps work item by title

.DESCRIPTION
Searches Azure DevOps for a work item with the given title and returns the full
work item object if found. Optionally filter by work item type using the
`-Type` parameter (e.g. Epic, Feature, User Story).

.PARAMETER Organization
Azure DevOps organization name (required)

.PARAMETER Project
Azure DevOps project name (required)

.PARAMETER Title
Work item title to search for (required)

.PARAMETER Type
Optional work item type to filter by (e.g. Epic, Feature, Story)

.PARAMETER ParentId
Optional parent work item ID to filter by (e.g. find Feature under specific Epic)

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from
`FALCOIT_AZDO_PAT_WORKITEMSREADWRITE` environment variable (expected to be encrypted).

.OUTPUTS
PSObject representing the found work item, or $null if not found. Throws error on unexpected failures.

.EXAMPLE
    $wi = .\FindAzDoItemByTitle.ps1 -Organization "myorg" -Project "myproj" -Title "My Epic" -Type Epic
    $feature = .\FindAzDoItemByTitle.ps1 -Organization "myorg" -Project "myproj" -Title "My Feature" -Type Feature -ParentId 123
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

    [string]$PatToken
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Import shared helpers/constants
. "$PSScriptRoot/AzDoAutomatorConstants.ps1"
. "$PSScriptRoot/AzDoPatTokenHelper.ps1"
. "$PSScriptRoot/AzDoApiWrapper.ps1"
. "$PSScriptRoot/AzDoWorkItemHelper.ps1"

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
    # Escape single quotes in title for WIQL query (double them)
    [string]$escapedTitle = $Title -replace "'","''"

    # Build WIQL query
    [string]$query = "SELECT [System.Id], [System.Title], [System.WorkItemType] FROM WorkItems WHERE [System.Title] = '$escapedTitle'"

    if ($PSBoundParameters.ContainsKey('Type') -and -not [string]::IsNullOrWhiteSpace($Type)) {
        $query += " AND [System.WorkItemType] = '$Type'"
    }

    if ($PSBoundParameters.ContainsKey('ParentId')) {
        $query += " AND [System.Parent] = '$ParentId'"
    }

    $logMessage = "Executing WIQL query for title ::FgGreen::$Title::FgDefault::"
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
        $null = & ssLogIt.ps1 -Level Debug -Message "Work item not found: $Title"
        return $null
    }

    if (@($workItems.workItems).Count -gt 1) {
        $logMessage = "Multiple work items found with title ::FgGreen::$Title::FgDefault::. Returning first match."
        $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"
    }

    # Retrieve full work item details
    $firstId = $workItems.workItems[0].id
    $workItem = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $firstId -PatToken $PatToken

    if ($null -eq $workItem) {
        $null = & ssLogIt.ps1 -Level Error -Message "Failed to retrieve full work item details for ID: $firstId"
        Write-Error "Could not retrieve full details for work item ID $firstId"
        throw "Work item found in WIQL results but failed to retrieve full details (ID: $firstId)"
    }

    $wiTitle = $workItem.fields.'System.Title'
    $wiType = $workItem.fields.'System.WorkItemType'
    $null = & ssLogIt.ps1 -Level Info -Message "Found work item: ::FgGreen::$wiTitle::FgDefault:: (Type: $wiType, ID: $($workItem.id))"

    return $workItem
}
catch {
    $null = & ssLogIt.ps1 -Level Error -Message "Failed to search for work item: $_" -Exception $_
    Write-Error $_
    throw
}
