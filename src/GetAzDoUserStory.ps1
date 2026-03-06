<#
.SYNOPSIS
Retrieve an Azure DevOps User Story by ID

.DESCRIPTION
Fetches a User Story from Azure DevOps by its ID. Returns either the full work item
or a subset of story-specific fields depending on the -Full switch.

With -Full switch, returns the complete work item JSON including all fields and relations.

Without -Full, returns a structured object with key story properties:
- Id, State, Title
- Description, AcceptanceCriteria, ACScenarios, StoryPoints, ExtraInformation
- Tags
- Comments: Array of latest comments (one per comment ID) with id, createdDate, lastModifiedDate, 
  text, and createdBy.displayName

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER WorkItemId
The User Story work item ID to retrieve (required)

.PARAMETER Full
Switch parameter. If specified, returns the complete work item JSON. 
If not specified, returns only key User Story fields.

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
PSObject representing the User Story with all fields (if -Full) or subset of fields (default)

.EXAMPLE
Get a User Story with default subset of fields:
    $story = .\GetAzDoUserStory.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123

Get complete User Story JSON:
    $story = .\GetAzDoUserStory.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123 -Full

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read scope
- Returns $null if work item not found
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [int]$WorkItemId,

    [switch]$Full,

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

# Validate required parameters
if (-not (Test-AzDoWorkItemIdValid $WorkItemId)) {
    Write-Error "Parameter 'WorkItemId' must be a positive integer."
}

$null = & ssLogIt.ps1 -Level Info -Message "Retrieving User Story (ID: $WorkItemId)"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    # Get the work item
    $workItem = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $WorkItemId -PatToken $PatToken

    if ($null -eq $workItem) {
        $null = & ssLogIt.ps1 -Level Error -Message "Work item not found (ID: $WorkItemId)"
        throw [System.InvalidOperationException]"Work item with ID $WorkItemId not found."
    }

    # Verify it's a User Story
    $workItemType = $workItem.fields.'System.WorkItemType'
    if ($workItemType -ne $script:WORKITEM_TYPE_STORY) {
        $null = & ssLogIt.ps1 -Level Error -Message "Work item is not a User Story (Type: $workItemType, ID: $WorkItemId)"
        throw [System.InvalidOperationException]"Work item with ID $WorkItemId is not a User Story (Type: $workItemType)."
    }

    # If -Full switch is used, return complete work item
    if ($Full) {
        $title = $workItem.fields.'System.Title'
        $null = & ssLogIt.ps1 -Level Info -Message "Successfully retrieved full User Story: ::FgGreen::$title::FgDefault:: (ID: $($workItem.id))"
        return $workItem
    }

    # Otherwise, return subset of fields
    $null = & ssLogIt.ps1 -Level Debug -Message "Building User Story subset object"

    # Build the subset object
    $storyObject = @{
        Id = $workItem.id
        State = $workItem.fields.'System.State'
        Title = $workItem.fields.'System.Title'
        Description = $workItem.fields.'System.Description'
        AcceptanceCriteria = $workItem.fields.'Microsoft.VSTS.Common.AcceptanceCriteria'
        ACScenarios = if ($workItem.fields.PSObject.Properties.Name -contains 'Custom.ACScenarios') { $workItem.fields.'Custom.ACScenarios' } else { $null }
        StoryPoints = $workItem.fields.'Microsoft.VSTS.Scheduling.StoryPoints'
        ExtraInformation = if ($workItem.fields.PSObject.Properties.Name -contains 'Custom.ExtraInformation') { $workItem.fields.'Custom.ExtraInformation' } else { $null }
        Tags = $workItem.fields.'System.Tags'
        Comments = @()
    }

    # Fetch comments if work item has any (optional - API may not exist)
    [int]$commentCount = 0
    if ($null -ne $workItem.fields.'System.CommentCount') {
        $commentCount = [int]$workItem.fields.'System.CommentCount'
    }

    if ($commentCount -gt 0) {
        $null = & ssLogIt.ps1 -Level Debug -Message "Fetching comments for User Story (CommentCount: $commentCount)"
        
        try {
            $commentsUrl = "https://dev.azure.com/$Organization/$Project/_apis/wit/workitems/$WorkItemId/comments?api-version=7.1-preview.3"
            $authHeader = New-AzDoAuthHeader -PatToken $PatToken

            $commentsResponse = Invoke-RestMethod -Uri $commentsUrl -Method Get -Headers $authHeader -TimeoutSec 30 -ErrorAction Stop

            # Normalize response to an items array (API may return wrapper with 'value' or different shapes)
            $items = $null
            if ($commentsResponse -is [array]) { $items = $commentsResponse }
            else {
                if ($commentsResponse.PSObject.Properties.Name -contains 'value') { $items = $commentsResponse.value }
                elseif ($commentsResponse.PSObject.Properties.Name -contains 'comments') { $items = $commentsResponse.comments }
                else {
                    foreach ($p in $commentsResponse.PSObject.Properties) {
                        if ($p.Value -is [array]) { $items = $p.Value; break }
                    }
                }
            }

            if ($null -ne $items) {
                # Group by commentId to get only the latest version of each comment
                $latestComments = @{ }
                foreach ($comment in $items) {
                    $commentId = $comment.id
                    # Keep track of the latest version (highest version number)
                    if (-not $latestComments.ContainsKey($commentId) -or $latestComments[$commentId].version -lt $comment.version) {
                        $latestComments[$commentId] = $comment
                    }
                }
                
                # Build comment objects for each latest comment
                foreach ($commentId in $latestComments.Keys) {
                    $comment = $latestComments[$commentId]
                    
                    # Build comment object - text property may have different names (text, content, body, etc.)
                    $commentText = $comment.text
                    if ([string]::IsNullOrWhiteSpace($commentText) -and $null -ne $comment.content) {
                        $commentText = $comment.content
                    }
                    if ([string]::IsNullOrWhiteSpace($commentText) -and $null -ne $comment.body) {
                        $commentText = $comment.body
                    }
                    
                    $commentObject = @{
                        Id = $comment.id
                        CreatedDate = $comment.createdDate
                        LastModifiedDate = $comment.modifiedDate
                        Text = $commentText
                        CreatedBy = $comment.createdBy.displayName
                    }
                    
                    $storyObject.Comments += $commentObject
                }
            }
        }
        catch {
            $errMsg = if ($_.Exception) { $_.Exception.Message } else { $_.ToString() }
            $msg = 'Error fetching comments for work item ' + $WorkItemId + ': ' + $errMsg
            $null = & ssLogIt.ps1 -Level Error -Message $msg
            throw [System.InvalidOperationException]('Failed to fetch comments for work item ' + $WorkItemId + ': ' + $errMsg)
        }
    }

    # Convert to PSObject
    $result = [PSObject]$storyObject
    
    $title = $workItem.fields.'System.Title'
    $null = & ssLogIt.ps1 -Level Info -Message "Successfully retrieved User Story subset: ::FgGreen::$title::FgDefault:: (ID: $($workItem.id))"

    return $result
}
catch {
    $null = & ssLogIt.ps1 -Level Error -Message "Failed to retrieve User Story: $_" -Exception $_
    Write-Error $_
    throw
}
