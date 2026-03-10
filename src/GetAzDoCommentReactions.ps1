<#
.SYNOPSIS
Get reactions for an Azure DevOps work item comment

.DESCRIPTION
Retrieves all reactions for an existing comment on a work item in Azure DevOps.
Reactions include type (like, dislike, heart, hooray, smile, confused) and count information.
Returns an array of reaction objects with metadata.

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER WorkItemId
The work item ID containing the comment (required)

.PARAMETER CommentId
The comment ID to retrieve reactions for (required)

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
Array of PSObject representing reactions with metadata (type, count, isCurrentUserEngaged)

.EXAMPLE
Get all reactions for a comment:
    $reactions = .\GetAzDoCommentReactions.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123 -CommentId 456

Get reactions and filter by type:
    $likes = .\GetAzDoCommentReactions.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123 -CommentId 456 | Where-Object { $_.type -eq 'like' }

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read scope
- WorkItemId and CommentId must be valid IDs
- Returns empty array if no reactions found
- API version: 7.1-preview.1
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $false)]
    [string]$Organization,

    [Parameter(Mandatory = $false)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [int]$WorkItemId,

    [Parameter(Mandatory = $true)]
    [int]$CommentId,

    [string]$PatToken
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Import modules
. "$PSScriptRoot/AzDoAutomatorConstants.ps1"
. "$PSScriptRoot/AzDoPatTokenHelper.ps1"
. "$PSScriptRoot/AzDoApiWrapper.ps1"
. "$PSScriptRoot/AzDoWorkItemHelper.ps1"

# Validate ssLogIt.ps1 exists
if (-not (Get-Command -Name 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    Write-Error "Required helper script 'ssLogIt.ps1' not found in PATH."
}

# Apply environment variable defaults if parameters not provided
if ([string]::IsNullOrWhiteSpace($Organization)) {
    $Organization = [Environment]::GetEnvironmentVariable('GMD_AZDO_ORGANIZATION')
    if ([string]::IsNullOrWhiteSpace($Organization)) {
        Write-Error "Parameter 'Organization' is required. Provide via -Organization parameter or set GMD_AZDO_ORGANIZATION environment variable."
    }
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    $Project = [Environment]::GetEnvironmentVariable('GMD_AZDO_PROJECT')
    if ([string]::IsNullOrWhiteSpace($Project)) {
        Write-Error "Parameter 'Project' is required. Provide via -Project parameter or set GMD_AZDO_PROJECT environment variable."
    }
}

# Validate ssLogIt.ps1 exists
if (-not (Get-Command -Name 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    Write-Error "Required helper script 'ssLogIt.ps1' not found in PATH. Ensure helper scripts are available."
}

# Validate required parameters
if ([string]::IsNullOrWhiteSpace($Organization)) {
    Write-Error "Parameter 'Organization' cannot be empty."
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    Write-Error "Parameter 'Project' cannot be empty."
}

if (-not (Test-AzDoWorkItemIdValid $WorkItemId)) {
    Write-Error "Parameter 'WorkItemId' must be a positive integer."
}

if ($CommentId -le 0) {
    Write-Error "Parameter 'CommentId' must be a positive integer."
}

# Log script start
$null = & ssLogIt.ps1 -Level Info -Message "Retrieving reactions for comment ID: ::FgGreen::$CommentId::FgDefault:: on work item ID: ::FgGreen::$WorkItemId::FgDefault::"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    # Validate work item exists
    $logMessage = "Validating work item (ID: $WorkItemId)"
    $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

    $workItem = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $WorkItemId -PatToken $PatToken
    if ($null -eq $workItem) {
        Write-Error "Work item with ID $WorkItemId not found."
    }

    $logMessage = "Work item found: ::FgGreen::$($workItem.fields.'System.Title')::FgDefault::"
    $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

    # Fetch reactions for the comment
    $logMessage = "Fetching reactions for comment..."
    $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

    $authHeader = New-AzDoAuthHeader -PatToken $PatToken

    # API endpoint: GET /_apis/wit/workItems/{workItemId}/comments/{commentId}/reactions?api-version=7.1-preview.1
    $uri = "https://dev.azure.com/$Organization/$Project/_apis/wit/workItems/$WorkItemId/comments/$CommentId/reactions`?api-version=7.1-preview.1"

    $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $authHeader -TimeoutSec 30 -ErrorAction Stop

    # Normalize response to reactions array
    $reactions = @()
    if ($null -ne $response) {
        if ($response -is [System.Collections.IEnumerable] -and $response -isnot [string]) {
            $reactions = @($response)
        }
        elseif ($null -ne $response.value -and $response.value -is [System.Collections.IEnumerable]) {
            $reactions = @($response.value)
        }
        elseif ($null -ne $response -and $response -isnot [System.Collections.Hashtable]) {
            $reactions = @($response)
        }
    }

    if ($reactions.Count -gt 0) {
        $reactionStr = ($reactions | ForEach-Object { "$($_.type):$($_.count)" }) -join ', '
        $null = & ssLogIt.ps1 -Level Info -Message "Found $($reactions.Count) reaction type(s): $reactionStr"
    }
    else {
        $null = & ssLogIt.ps1 -Level Info -Message "No reactions found for comment."
    }

    return $reactions
}
catch {
    $logMessage = "Failed to retrieve reactions: $_"
    $null = & ssLogIt.ps1 -Level Error -Message "$logMessage" -Exception $_
    throw
}
