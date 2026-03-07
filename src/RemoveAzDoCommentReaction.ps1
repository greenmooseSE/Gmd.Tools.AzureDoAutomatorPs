<#
.SYNOPSIS
Remove a reaction from an Azure DevOps work item comment

.DESCRIPTION
Removes a reaction from an existing comment on a work item in Azure DevOps.
Available reaction types: like, dislike, heart, hooray, smile, confused.
Returns success or error information.

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER WorkItemId
The work item ID containing the comment (required)

.PARAMETER CommentId
The comment ID to remove reaction from (required)

.PARAMETER ReactionType
The type of reaction to remove (required). Valid values: like, dislike, heart, hooray, smile, confused.

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
PSObject with success status and metadata

.EXAMPLE
Remove a 'like' reaction from a comment:
    $result = .\RemoveAzDoCommentReaction.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123 -CommentId 456 -ReactionType "like"

Remove a 'heart' reaction:
    $result = .\RemoveAzDoCommentReaction.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123 -CommentId 456 -ReactionType "heart"

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read/write scope
- WorkItemId and CommentId must be valid IDs
- Returns error if reaction does not exist for the current user
- API version: 7.1-preview.1
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [int]$WorkItemId,

    [Parameter(Mandatory = $true)]
    [int]$CommentId,

    [Parameter(Mandatory = $true)]
    [ValidateSet('like', 'dislike', 'heart', 'hooray', 'smile', 'confused')]
    [string]$ReactionType,

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
$null = & ssLogIt.ps1 -Level Info -Message "Removing ::FgYellow::$ReactionType::FgDefault:: reaction from comment ID: ::FgGreen::$CommentId::FgDefault:: on work item ID: ::FgGreen::$WorkItemId::FgDefault::"

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

    # Remove the reaction
    $logMessage = "Removing $ReactionType reaction from comment..."
    $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

    $authHeader = New-AzDoAuthHeader -PatToken $PatToken

    # API endpoint: DELETE /_apis/wit/workItems/{workItemId}/comments/{commentId}/reactions/{reactionType}?api-version=7.1-preview.1
    $uri = "https://dev.azure.com/$Organization/$Project/_apis/wit/workItems/$WorkItemId/comments/$CommentId/reactions/$ReactionType`?api-version=7.1-preview.1"

    # DELETE request returns 202 Accepted on success or error otherwise
    $response = Invoke-WebRequest -Uri $uri -Method Delete -Headers $authHeader -TimeoutSec 30 -ErrorAction Stop

    if ($response.StatusCode -ne 202) {
        Write-Error "Unexpected response status code: $($response.StatusCode)"
    }

    $result = @{
        success = $true
        reactionType = $ReactionType
        commentId = $CommentId
        workItemId = $WorkItemId
        statusCode = $response.StatusCode
    }

    $null = & ssLogIt.ps1 -Level Info -Message "Reaction removed successfully: ::FgGreen::$ReactionType::FgDefault::"

    return $result
}
catch {
    if ($_.Exception.Response.StatusCode -eq 404) {
        $logMessage = "Reaction not found - may already be removed or never existed"
        $null = & ssLogIt.ps1 -Level Warning -Message "$logMessage"
        Write-Error "Cannot remove $ReactionType reaction from comment $CommentId - reaction does not exist."
    }
    else {
        $logMessage = "Failed to remove reaction: $_"
        $null = & ssLogIt.ps1 -Level Error -Message "$logMessage" -Exception $_
        Write-Error $_
    }
    throw
}
