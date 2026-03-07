<#
.SYNOPSIS
Retrieve Azure DevOps User Story hierarchy with Tasks

.DESCRIPTION
Fetches a User Story and builds a complete hierarchy showing:
- Story with full story details:
  Id, State, Title, Description, AcceptanceCriteria, ACScenarios, 
  StoryPoints, ExtraInformation, Tags
- All Tasks under the Story

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER StoryId
The User Story work item ID (required if StoryTitle not provided)

.PARAMETER StoryTitle
The Story title to search for (required if StoryId not provided)
If both StoryId and StoryTitle are provided, StoryId takes precedence.

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
Structured PSObject representing the Story hierarchy with nested Tasks.
Returns $null if Story not found.

.EXAMPLE
Get hierarchy by Story ID:
    $hierarchy = .\GetAzDoHierarchyForStory.ps1 -Organization "myorg" -Project "myproject" -StoryId 100

Get hierarchy by Story title:
    $hierarchy = .\GetAzDoHierarchyForStory.ps1 -Organization "myorg" -Project "myproject" -StoryTitle "User Login Flow"

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read scope
- Returns $null if Story not found
- Structure matches NewAzDoHierarchyFromMarkdown.ps1 format (no comments/reactions)
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$Project,

    [int]$StoryId,

    [string]$StoryTitle,

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

# Validate that either StoryId or StoryTitle is provided
if (-not $PSBoundParameters.ContainsKey('StoryId') -and -not $PSBoundParameters.ContainsKey('StoryTitle')) {
    Write-Error "Either 'StoryId' or 'StoryTitle' parameter must be provided."
}

$null = & ssLogIt.ps1 -Level Info -Message "Building Story hierarchy"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    # Resolve Story ID if title was provided
    if ($PSBoundParameters.ContainsKey('StoryTitle') -and -not $PSBoundParameters.ContainsKey('StoryId')) {
        $null = & ssLogIt.ps1 -Level Debug -Message "Searching for Story with title: ::FgGreen::$StoryTitle::FgDefault::"
        
        $story = Find-AzDoWorkItemByTitle -Organization $Organization -Project $Project -Title $StoryTitle -WorkItemType $script:WORKITEM_TYPE_STORY -PatToken $PatToken
        
        if ($null -eq $story) {
            $null = & ssLogIt.ps1 -Level Warn -Message "Story not found with title: $StoryTitle"
            return $null
        }
        
        $StoryId = $story.id
        $null = & ssLogIt.ps1 -Level Debug -Message "Resolved Story title to ID: $StoryId"
    }

    # Validate StoryId is valid
    if (-not (Test-AzDoWorkItemIdValid $StoryId)) {
        Write-Error "Parameter 'StoryId' must be a positive integer."
    }

    # Get the Story details
    $storyDetails = & "$PSScriptRoot/GetAzDoUserStory.ps1" -Organization $Organization -Project $Project -WorkItemId $StoryId -PatToken $PatToken

    if ($null -eq $storyDetails) {
        $null = & ssLogIt.ps1 -Level Warn -Message "Story not found (ID: $StoryId)"
        return $null
    }

    $storyTitle = $storyDetails.Title
    $null = & ssLogIt.ps1 -Level Info -Message "Found Story: ::FgGreen::$storyTitle::FgDefault:: (ID: $StoryId)"

    # Get the full work item for relations
    $storyWorkItem = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $StoryId -PatToken $PatToken

    # Get all Tasks under this Story from relations
    $null = & ssLogIt.ps1 -Level Debug -Message "Fetching Tasks for Story (ID: $StoryId)"
    
    $taskIds = @()
    
    # Extract child Task IDs from relations array (System.LinkTypes.Hierarchy-Forward links)
    if ($null -ne $storyWorkItem.relations) {
        $childRelations = $storyWorkItem.relations | Where-Object { $_.rel -eq 'System.LinkTypes.Hierarchy-Forward' }
        foreach ($relation in $childRelations) {
            # Extract work item ID from URL (e.g., .../workItems/1322)
            $childId = [int]($relation.url -split '/' | Select-Object -Last 1)
            if ($childId -gt 0 -and $childId -ne $StoryId) {  # Exclude self-references
                $taskIds += $childId
            }
        }
    }
    
    $null = & ssLogIt.ps1 -Level Debug -Message "Found $($taskIds.Count) child Task IDs from relations"
    
    # Build Tasks array
    $tasksArray = @()

    if ($taskIds.Count -gt 0) {
        foreach ($taskId in $taskIds) {
            try {
                $null = & ssLogIt.ps1 -Level Debug -Message "Processing Task (ID: $taskId)"

                # Get full task details
                $task = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $taskId -PatToken $PatToken

                if ($null -ne $task) {
                    $taskObject = @{
                        Id = $task.id
                        State = $task.fields.'System.State'
                        Title = $task.fields.'System.Title'
                        Description = if ($task.fields.PSObject.Properties.Name -contains 'System.Description') { $task.fields.'System.Description' } else { $null }
                        Tags = if ($task.fields.PSObject.Properties.Name -contains 'System.Tags') { $task.fields.'System.Tags' } else { $null }
                    }
                    $tasksArray += [PSCustomObject]$taskObject
                }
            }
            catch {
                $null = & ssLogIt.ps1 -Level Warn -Message "Could not fetch Task $taskId : $_"
            }
        }
    }
    else {
        $null = & ssLogIt.ps1 -Level Info -Message "No Tasks found for Story"
    }

    # Add Tasks to story details
    $storyDetails | Add-Member -NotePropertyName Tasks -NotePropertyValue $tasksArray

    $null = & ssLogIt.ps1 -Level Info -Message "Successfully built Story hierarchy with $($tasksArray.Count) Task(s)"

    return $storyDetails
}
catch {
    $null = & ssLogIt.ps1 -Level Error -Message "Failed to build Story hierarchy: $_" -Exception $_
    Write-Error $_
    throw
}
