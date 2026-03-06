<#
.SYNOPSIS
Add a reaction to an Azure DevOps work item comment

.DESCRIPTION
Adds a reaction to an existing comment on a work item in Azure DevOps.
Available reaction types: like, dislike, heart, hooray, smile, confused.
Returns the created reaction object with metadata.

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER WorkItemId
The work item ID containing the comment (required)

.PARAMETER CommentId
The comment ID to add reaction to (required)

.PARAMETER ReactionType
The type of reaction to add (required). Valid values: like, dislike, heart, hooray, smile, confused.

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
PSObject representing the created reaction with metadata

.EXAMPLE
Add a 'like' reaction to a comment:
    $reaction = .\NewAzDoCommentReaction.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123 -CommentId 456 -ReactionType "like"

Add a 'heart' reaction:
    $reaction = .\NewAzDoCommentReaction.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123 -CommentId 456 -ReactionType "heart"

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read/write scope
- WorkItemId and CommentId must be valid IDs
- Only one reaction per user per comment per reaction type is allowed
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
$null = & ssLogIt.ps1 -Level Info -Message "Adding ::FgYellow::$ReactionType::FgDefault:: reaction to comment ID: ::FgGreen::$CommentId::FgDefault:: on work item ID: ::FgGreen::$WorkItemId::FgDefault::"

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

    # Add the reaction
    $logMessage = "Adding $ReactionType reaction to comment..."
    $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

    $authHeader = New-AzDoAuthHeader -PatToken $PatToken
    $authHeader['Content-Type'] = 'application/json'

    # API endpoint: PUT /_apis/wit/workItems/{workItemId}/comments/{commentId}/reactions/{reactionType}?api-version=7.1-preview.1
    $uri = "https://dev.azure.com/$Organization/$Project/_apis/wit/workItems/$WorkItemId/comments/$CommentId/reactions/$ReactionType`?api-version=7.1-preview.1"

    # The reactions API doesn't require a body for PUT requests
    $reaction = Invoke-RestMethod -Uri $uri -Method Put -Headers $authHeader -TimeoutSec 30 -ErrorAction Stop

    if ($null -eq $reaction) {
        Write-Error "Failed to add reaction to comment $CommentId on work item $WorkItemId."
    }

    $null = & ssLogIt.ps1 -Level Info -Message "Reaction added successfully: ::FgGreen::$ReactionType::FgDefault:: (Count: $($reaction.count))"

    return $reaction
}
catch {
    $logMessage = "Failed to add reaction: $_"
    $null = & ssLogIt.ps1 -Level Error -Message "$logMessage" -Exception $_
    throw
}
