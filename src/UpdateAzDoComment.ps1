<#
.SYNOPSIS
Update an existing comment on an Azure DevOps work item

.DESCRIPTION
Updates the content of an existing comment on a work item in Azure DevOps.
Supports markdown formatting in the comment content.
Returns the updated comment object with metadata.

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER WorkItemId
The work item ID containing the comment (required)

.PARAMETER CommentId
The ID of the comment to update (required)

.PARAMETER Content
The new comment content, supports markdown formatting (required)

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
PSObject representing the updated comment with all metadata

.EXAMPLE
Update a comment with new text:
    $comment = .\UpdateAzDoComment.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123 -CommentId 456 -Content "Fixed typo in previous comment"

Update a comment with markdown:
    $comment = .\UpdateAzDoComment.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123 -CommentId 456 -Content "**Updated note**: Please review again"

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read/write scope
- WorkItemId must be a valid work item ID
- CommentId must be a valid comment ID
- Content cannot be empty
- Comment must exist (will error if not found)
- Original comment author permissions apply
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
    [string]$Content,

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

if ([string]::IsNullOrWhiteSpace($Content)) {
    Write-Error "Parameter 'Content' cannot be empty."
}

# Log script start
$null = & ssLogIt.ps1 -Level Info -Message "Updating comment (ID: ::FgGreen::$CommentId::FgDefault::) on work item (ID: ::FgGreen::$WorkItemId::FgDefault::)"

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

    # Update the comment
    $logMessage = "Updating comment $CommentId with new content..."
    $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

    $updatedComment = Update-AzDoComment -Organization $Organization -Project $Project -WorkItemId $WorkItemId -CommentId $CommentId -Content $Content -PatToken $PatToken

    if ($null -eq $updatedComment) {
        Write-Error "Failed to update comment $CommentId on work item $WorkItemId."
    }

    $null = & ssLogIt.ps1 -Level Info -Message "Comment updated successfully (ID: ::FgGreen::$($updatedComment.id)::FgDefault::, Version: ::FgGreen::$($updatedComment.version)::FgDefault::)"

    return $updatedComment
}
catch {
    $logMessage = "Failed to update comment: $_"
    $null = & ssLogIt.ps1 -Level Error -Message "$logMessage" -Exception $_
    throw
}
