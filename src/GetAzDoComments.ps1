<#
.SYNOPSIS
Retrieve all comments from an Azure DevOps work item

.DESCRIPTION
Fetches all comments on a work item from Azure DevOps. Returns an array of comment objects
with metadata including Id, Content, Author, CreatedDate, UpdatedDate, and reaction counts.

If no comments exist, returns an empty array.

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER WorkItemId
The work item ID to retrieve comments from (required)

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
Array of PSObject representing comments with fields:
- id: Comment ID
- text: Comment content
- createdDate: When the comment was created
- modifiedDate: When the comment was last modified
- createdBy: Author information (displayName, id)
- modifiedBy: Last modifier information
- reactions: Array of reaction objects (type, count, isCurrentUserEngaged)

Returns empty array if work item has no comments.

.EXAMPLE
Get all comments for a work item:
    $comments = .\GetAzDoComments.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123

Iterate through comments:
    $comments = .\GetAzDoComments.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123
    foreach ($comment in $comments) {
        Write-Host "Comment: $($comment.text)"
        Write-Host "By: $($comment.createdBy.displayName)"
    }

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read scope
- WorkItemId must be a valid work item ID
- Returns empty array for non-existent work items or items with no comments
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $false)]
    [string]$Organization,

    [Parameter(Mandatory = $false)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [int]$WorkItemId,

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
}

# Validate required parameters
if (-not (Test-AzDoWorkItemIdValid $WorkItemId)) {
    $null = & ssLogIt.ps1 -Level Error -Message "Parameter 'WorkItemId' must be a positive integer. Provided: $WorkItemId"
    Write-Error "Parameter 'WorkItemId' must be a positive integer. Provided: $WorkItemId"
}

$null = & ssLogIt.ps1 -Level Info -Message "Retrieving comments for work item ID: $WorkItemId"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    # Fetch work item with comments expansion
    $null = & ssLogIt.ps1 -Level Debug -Message "Fetching work item (ID: $WorkItemId) with comments"

    $workItem = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $WorkItemId -PatToken $PatToken

    if ($null -eq $workItem) {
        $null = & ssLogIt.ps1 -Level Warn -Message "Work item not found (ID: $WorkItemId). Returning empty comment array"
        return @()
    }

    # Get comments for this work item
    $null = & ssLogIt.ps1 -Level Debug -Message "Fetching all comments for work item (ID: $WorkItemId)"

    $commentsUri = "$script:AZDO_API_BASE_URL/wit/workitems/$WorkItemId/comments?api-version=7.1-preview.3"
    $commentsUri = $commentsUri -replace '{organization}', $Organization
    $commentsUri = $commentsUri -replace '{project}', $Project

    $authHeader = New-AzDoAuthHeader -PatToken $PatToken

    $commentsResponse = Invoke-AzDoApiRequest -Uri $commentsUri -Headers $authHeader -Method Get

    # Process comments
    $commentCount = if ($null -ne $commentsResponse.comments) { 
        @($commentsResponse.comments).Count  
    } else { 
        0 
    }
    
    if ($commentCount -gt 0) {
        $null = & ssLogIt.ps1 -Level Info -Message "Found $commentCount comment(s) on work item (ID: $WorkItemId)"

        # Build comment objects with all metadata
        $comments = @()
        foreach ($comment in $commentsResponse.comments) {
            # Safely extract reactions (may not exist in API response)
            $reactionsData = @()
            if ($comment.PSObject.Properties.Name -contains 'reactions') {
                $reactionsData = $comment.reactions
            }
            
            # Decode HTML entities in comment text (API returns HTML-encoded content)
            $decodedText = [System.Net.WebUtility]::HtmlDecode($comment.text)
            
            $commentObj = [PSCustomObject]@{
                id           = $comment.id
                text         = $decodedText
                createdDate  = $comment.createdDate
                modifiedDate = $comment.modifiedDate
                createdBy    = $comment.createdBy
                modifiedBy   = $comment.modifiedBy
                reactions    = $reactionsData
            }
            $comments += $commentObj
        }

        return @($comments)
    }
    else {
        $null = & ssLogIt.ps1 -Level Info -Message "Found $commentCount comment(s) on work item (ID: $WorkItemId)"
        return , @()
    }
}
catch {
    $null = & ssLogIt.ps1 -Level Error -Message "Failed to retrieve comments: $_" -Exception $_
    Write-Error $_
    throw
}
