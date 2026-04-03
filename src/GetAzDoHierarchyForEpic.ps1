<#
.SYNOPSIS
Retrieve Azure DevOps Epic hierarchy with Features and Stories

.DESCRIPTION
Fetches an Epic and builds a complete hierarchy showing:
- Epic with State, Description and Effort
- All Features under the Epic with State, Description and Effort
- All Stories under each Feature with full User Story details:
  Id, State, Title, Description, AcceptanceCriteria, ACScenarios, 
  StoryPoints, ExtraInformation, Tags

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER EpicId
The Epic work item ID (required if EpicTitle not provided)

.PARAMETER EpicTitle
The Epic title to search for (required if EpicId not provided)
If both EpicId and EpicTitle are provided, EpicId takes precedence.

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
Structured PSObject representing the Epic hierarchy with nested Features and Stories

.EXAMPLE
Get hierarchy by Epic ID:
    $hierarchy = .\GetAzDoHierarchyForEpic.ps1 -Organization "myorg" -Project "myproject" -EpicId 100

Get hierarchy by Epic title:
    $hierarchy = .\GetAzDoHierarchyForEpic.ps1 -Organization "myorg" -Project "myproject" -EpicTitle "Platform Modernization"

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read scope
- Returns $null if Epic not found
- Building the hierarchy may take time if there are many items
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $false)]
    [string]$Organization,

    [Parameter(Mandatory = $false)]
    [string]$Project,

    [int]$EpicId,

    [string]$EpicTitle,

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

# Validate that either EpicId or EpicTitle is provided
if (-not $PSBoundParameters.ContainsKey('EpicId') -and -not $PSBoundParameters.ContainsKey('EpicTitle')) {
    Write-Error "Either 'EpicId' or 'EpicTitle' parameter must be provided."
}

$null = & ssLogIt.ps1 -Level Info -Message "Building Epic hierarchy"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    # Resolve Epic ID if title was provided
    if ($PSBoundParameters.ContainsKey('EpicTitle') -and -not $PSBoundParameters.ContainsKey('EpicId')) {
        $null = & ssLogIt.ps1 -Level Debug -Message "Searching for Epic with title: ::FgGreen::$EpicTitle::FgDefault::"
        
        $epic = Find-AzDoWorkItemByTitle -Organization $Organization -Project $Project -Title $EpicTitle -WorkItemType $script:WORKITEM_TYPE_EPIC -PatToken $PatToken
        
        if ($null -eq $epic) {
            $null = & ssLogIt.ps1 -Level Error -Message "Epic not found with title: $EpicTitle"
            Write-Error "Epic with title '$EpicTitle' not found."
        }
        
        $EpicId = $epic.id
        $null = & ssLogIt.ps1 -Level Debug -Message "Resolved Epic title to ID: $EpicId"
    }

    # Validate EpicId is valid
    if (-not (Test-AzDoWorkItemIdValid $EpicId)) {
        Write-Error "Parameter 'EpicId' must be a positive integer."
    }

    # Get the Epic work item
    $epicWorkItem = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $EpicId -PatToken $PatToken

    if ($null -eq $epicWorkItem) {
        $null = & ssLogIt.ps1 -Level Error -Message "Epic work item not found (ID: $EpicId)"
        Write-Error "Epic with ID $EpicId not found."
    }

    # Verify it's actually an Epic
    if ($epicWorkItem.fields.'System.WorkItemType' -ne $script:WORKITEM_TYPE_EPIC) {
        $null = & ssLogIt.ps1 -Level Error -Message "Work item is not an Epic (Type: $($epicWorkItem.fields.'System.WorkItemType'))"
        Write-Error "Work item with ID $EpicId is not an Epic."
    }

    $epicTitle = $epicWorkItem.fields.'System.Title'
    $null = & ssLogIt.ps1 -Level Info -Message "Found Epic: ::FgGreen::$epicTitle::FgDefault:: (ID: $EpicId)"

    # Get all Features under this Epic from relations (child work items)
    $null = & ssLogIt.ps1 -Level Debug -Message "Fetching Features for Epic (ID: $EpicId)"
    
    $featureIds = @()
    
    # Extract child Feature IDs from relations array (System.LinkTypes.Hierarchy-Forward links)
    if ($null -ne $epicWorkItem.relations) {
        $childRelations = $epicWorkItem.relations | Where-Object { $_.rel -eq 'System.LinkTypes.Hierarchy-Forward' }
        foreach ($relation in $childRelations) {
            # Extract work item ID from URL (e.g., .../workItems/1322)
            $childId = [int]($relation.url -split '/' | Select-Object -Last 1)
            if ($childId -gt 0 -and $childId -ne $EpicId) {  # Exclude self-references
                $featureIds += $childId
            }
        }
    }
    
    $null = & ssLogIt.ps1 -Level Debug -Message "Found $($featureIds.Count) child Feature IDs from relations"
    
    $features = @()
    
    # Get each Feature work item
    foreach ($featureId in $featureIds) {
        try {
            $feature = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $featureId -PatToken $PatToken
            if ($null -ne $feature) {
                $features += $feature
            }
        }
        catch {
            $null = & ssLogIt.ps1 -Level Warn -Message "Could not fetch Feature $featureId : $_"
        }
    }

    # Build Features array
    $featuresArray = @()

    if ($null -ne $features -and @($features).Count -gt 0) {
        $null = & ssLogIt.ps1 -Level Info -Message "Found $(@($features).Count) Feature(s)"

        foreach ($feature in $features) {
            $featureId = $feature.id
            $featureTitle = $feature.fields.'System.Title'
            $null = & ssLogIt.ps1 -Level Debug -Message "Processing Feature: ::FgGreen::$featureTitle::FgDefault:: (ID: $featureId)"

            # Get all Stories under this Feature from relations
            $storyIds = @()
            if ($null -ne $feature.relations) {
                $storyRelations = $feature.relations | Where-Object { $_.rel -eq 'System.LinkTypes.Hierarchy-Forward' }
                foreach ($relation in $storyRelations) {
                    $storyId = [int]($relation.url -split '/' | Select-Object -Last 1)
                    if ($storyId -gt 0) {
                        $storyIds += $storyId
                    }
                }
            }
            
            # Build Stories array
            $storiesArray = @()

            if ($storyIds.Count -gt 0) {
                foreach ($storyId in $storyIds) {
                    try {
                        $null = & ssLogIt.ps1 -Level Debug -Message "Processing Story (ID: $storyId)"

                        # Get full story details
                        $storyDetails = & "$PSScriptRoot/GetAzDoUserStory.ps1" -Organization $Organization -Project $Project -WorkItemId $storyId -PatToken $PatToken

                        if ($null -ne $storyDetails) {
                            $storiesArray += $storyDetails
                        }
                    }
                    catch {
                        $null = & ssLogIt.ps1 -Level Warn -Message "Could not fetch Story $storyId : $_"
                    }
                }
            }

            $featureObject = @{
                Id = $featureId
                State = $feature.fields.'System.State'
                Title = $featureTitle
                Description = if ($feature.fields.PSObject.Properties.Name -contains 'System.Description') { $feature.fields.'System.Description' } else { $null }
                Effort = if ($feature.fields.PSObject.Properties.Name -contains 'Microsoft.VSTS.Scheduling.Effort') { $feature.fields.'Microsoft.VSTS.Scheduling.Effort' } else { $null }
                Tags = if ($feature.fields.PSObject.Properties.Name -contains 'System.Tags') { $feature.fields.'System.Tags' } else { $null }
                Stories = $storiesArray
            }

            $featuresArray += [PSCustomObject]$featureObject
        }
    }
    else {
        $null = & ssLogIt.ps1 -Level Info -Message "No Features found for Epic"
    }

    # Build the hierarchy object
    $hierarchyObject = @{
        Id = $epicWorkItem.id
        State = $epicWorkItem.fields.'System.State'
        Title = $epicTitle
        Description = if ($epicWorkItem.fields.PSObject.Properties.Name -contains 'System.Description') { $epicWorkItem.fields.'System.Description' } else { $null }
        Effort = if ($epicWorkItem.fields.PSObject.Properties.Name -contains 'Microsoft.VSTS.Scheduling.Effort') { $epicWorkItem.fields.'Microsoft.VSTS.Scheduling.Effort' } else { $null }
        Tags = if ($epicWorkItem.fields.PSObject.Properties.Name -contains 'System.Tags') { $epicWorkItem.fields.'System.Tags' } else { $null }
        Features = $featuresArray
    }

    $result = [PSCustomObject]$hierarchyObject
    $null = & ssLogIt.ps1 -Level Info -Message "Successfully built Epic hierarchy with $(@($featuresArray).Count) Feature(s)"

    return $result
}
catch {
    $null = & ssLogIt.ps1 -Level Error -Message "Failed to build Epic hierarchy: $_" -Exception $_
    Write-Error $_
    throw
}
