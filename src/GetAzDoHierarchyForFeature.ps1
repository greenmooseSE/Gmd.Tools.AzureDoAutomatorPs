<#
.SYNOPSIS
Retrieve Azure DevOps Feature hierarchy with Stories and Tasks

.DESCRIPTION
Fetches a Feature and builds a complete hierarchy showing:
- Feature with Description and Effort
- All Stories under the Feature with full Story details:
  Id, State, Title, Description, AcceptanceCriteria, ACScenarios, 
  StoryPoints, ExtraInformation, Tags
- All Tasks under each Story

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER FeatureId
The Feature work item ID (required if FeatureTitle not provided)

.PARAMETER FeatureTitle
The Feature title to search for (required if FeatureId not provided)
If both FeatureId and FeatureTitle are provided, FeatureId takes precedence.

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
Structured PSObject representing the Feature hierarchy with nested Stories and Tasks.
Returns $null if Feature not found.

.EXAMPLE
Get hierarchy by Feature ID:
    $hierarchy = .\GetAzDoHierarchyForFeature.ps1 -Organization "myorg" -Project "myproject" -FeatureId 100

Get hierarchy by Feature title:
    $hierarchy = .\GetAzDoHierarchyForFeature.ps1 -Organization "myorg" -Project "myproject" -FeatureTitle "User Authentication"

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read scope
- Returns $null if Feature not found
- Building the hierarchy may take time if there are many items
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$Project,

    [int]$FeatureId,

    [string]$FeatureTitle,

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

# Validate that either FeatureId or FeatureTitle is provided
if (-not $PSBoundParameters.ContainsKey('FeatureId') -and -not $PSBoundParameters.ContainsKey('FeatureTitle')) {
    Write-Error "Either 'FeatureId' or 'FeatureTitle' parameter must be provided."
}

$null = & ssLogIt.ps1 -Level Info -Message "Building Feature hierarchy"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    # Resolve Feature ID if title was provided
    if ($PSBoundParameters.ContainsKey('FeatureTitle') -and -not $PSBoundParameters.ContainsKey('FeatureId')) {
        $null = & ssLogIt.ps1 -Level Debug -Message "Searching for Feature with title: ::FgGreen::$FeatureTitle::FgDefault::"
        
        $feature = Find-AzDoWorkItemByTitle -Organization $Organization -Project $Project -Title $FeatureTitle -WorkItemType $script:WORKITEM_TYPE_FEATURE -PatToken $PatToken
        
        if ($null -eq $feature) {
            $null = & ssLogIt.ps1 -Level Warn -Message "Feature not found with title: $FeatureTitle"
            return $null
        }
        
        $FeatureId = $feature.id
        $null = & ssLogIt.ps1 -Level Debug -Message "Resolved Feature title to ID: $FeatureId"
    }

    # Validate FeatureId is valid
    if (-not (Test-AzDoWorkItemIdValid $FeatureId)) {
        Write-Error "Parameter 'FeatureId' must be a positive integer."
    }

    # Get the Feature work item
    $featureWorkItem = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $FeatureId -PatToken $PatToken

    if ($null -eq $featureWorkItem) {
        $null = & ssLogIt.ps1 -Level Warn -Message "Feature work item not found (ID: $FeatureId)"
        return $null
    }

    # Verify it's actually a Feature
    if ($featureWorkItem.fields.'System.WorkItemType' -ne $script:WORKITEM_TYPE_FEATURE) {
        $null = & ssLogIt.ps1 -Level Error -Message "Work item is not a Feature (Type: $($featureWorkItem.fields.'System.WorkItemType'))"
        Write-Error "Work item with ID $FeatureId is not a Feature."
    }

    $featureTitle = $featureWorkItem.fields.'System.Title'
    $null = & ssLogIt.ps1 -Level Info -Message "Found Feature: ::FgGreen::$featureTitle::FgDefault:: (ID: $FeatureId)"

    # Get all Stories under this Feature from relations (child work items)
    $null = & ssLogIt.ps1 -Level Debug -Message "Fetching Stories for Feature (ID: $FeatureId)"
    
    $storyIds = @()
    
    # Extract child Story IDs from relations array (System.LinkTypes.Hierarchy-Forward links)
    if ($null -ne $featureWorkItem.relations) {
        $childRelations = $featureWorkItem.relations | Where-Object { $_.rel -eq 'System.LinkTypes.Hierarchy-Forward' }
        foreach ($relation in $childRelations) {
            # Extract work item ID from URL (e.g., .../workItems/1322)
            $childId = [int]($relation.url -split '/' | Select-Object -Last 1)
            if ($childId -gt 0 -and $childId -ne $FeatureId) {  # Exclude self-references
                $storyIds += $childId
            }
        }
    }
    
    $null = & ssLogIt.ps1 -Level Debug -Message "Found $($storyIds.Count) child Story IDs from relations"
    
    $stories = @()
    
    # Get each Story work item
    foreach ($storyId in $storyIds) {
        try {
            $story = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $storyId -PatToken $PatToken
            if ($null -ne $story) {
                $stories += $story
            }
        }
        catch {
            $null = & ssLogIt.ps1 -Level Warn -Message "Could not fetch Story $storyId : $_"
        }
    }

    # Build Stories array
    $storiesArray = @()

    if ($null -ne $stories -and @($stories).Count -gt 0) {
        $null = & ssLogIt.ps1 -Level Info -Message "Found $(@($stories).Count) Story(ies)"

        foreach ($story in $stories) {
            $storyId = $story.id
            $storyTitle = $story.fields.'System.Title'
            $null = & ssLogIt.ps1 -Level Debug -Message "Processing Story: ::FgGreen::$storyTitle::FgDefault:: (ID: $storyId)"

            # Get all Tasks under this Story from relations
            $taskIds = @()
            if ($null -ne $story.relations) {
                $taskRelations = $story.relations | Where-Object { $_.rel -eq 'System.LinkTypes.Hierarchy-Forward' }
                foreach ($relation in $taskRelations) {
                    $taskId = [int]($relation.url -split '/' | Select-Object -Last 1)
                    if ($taskId -gt 0) {
                        $taskIds += $taskId
                    }
                }
            }
            
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

            # Get full story details
            $storyDetails = & "$PSScriptRoot/GetAzDoUserStory.ps1" -Organization $Organization -Project $Project -WorkItemId $storyId -PatToken $PatToken

            if ($null -ne $storyDetails) {
                # Add Tasks to story details
                $storyDetails | Add-Member -NotePropertyName Tasks -NotePropertyValue $tasksArray
                $storiesArray += $storyDetails
            }
        }
    }
    else {
        $null = & ssLogIt.ps1 -Level Info -Message "No Stories found for Feature"
    }

    # Build the hierarchy object
    $hierarchyObject = @{
        Id = $featureWorkItem.id
        Title = $featureTitle
        Description = if ($featureWorkItem.fields.PSObject.Properties.Name -contains 'System.Description') { $featureWorkItem.fields.'System.Description' } else { $null }
        Effort = if ($featureWorkItem.fields.PSObject.Properties.Name -contains 'Microsoft.VSTS.Scheduling.Effort') { $featureWorkItem.fields.'Microsoft.VSTS.Scheduling.Effort' } else { $null }
        Tags = if ($featureWorkItem.fields.PSObject.Properties.Name -contains 'System.Tags') { $featureWorkItem.fields.'System.Tags' } else { $null }
        Stories = $storiesArray
    }

    $result = [PSCustomObject]$hierarchyObject
    $null = & ssLogIt.ps1 -Level Info -Message "Successfully built Feature hierarchy with $(@($storiesArray).Count) Story(ies)"

    return $result
}
catch {
    $null = & ssLogIt.ps1 -Level Error -Message "Failed to build Feature hierarchy: $_" -Exception $_
    Write-Error $_
    throw
}
