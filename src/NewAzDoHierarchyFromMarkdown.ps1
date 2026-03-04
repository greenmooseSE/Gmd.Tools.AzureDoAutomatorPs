<#
.SYNOPSIS
Create Azure DevOps work item hierarchy from markdown file

.DESCRIPTION
Parses a markdown file using hierarchical headers and creates a hierarchy of Epic/Feature/Story work items.
Performs full validation before creating any items (fail-fast approach).

Markdown format:
    # Epic Title
    **tags**: tag1, tag2
    **Description**
    Multi-line description text
    
    ## Feature Title
    **tags**: tag1, tag2
    **Description**
    Feature description
    
    ### Story Title
    **tags**: tag1, tag2
    **SP**: 5
    **Description**
    Story description as a developer...
    
    #### Acceptance Criteria
    - [ ] Criterion 1
    - [ ] Criterion 2
    
    #### AC Scenarios
    1. **Scenario**: First scenario
    Given...
    When...
    Then...
    
    #### Extra Information
    Additional notes and requirements

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER MarkdownFilePath
Path to markdown file to parse (required)

.PARAMETER EpicId
Optional: Parent Epic ID. If not provided, Features become top-level work items.

.PARAMETER DryRun
Switch: If specified, shows planned operations without creating work items

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from FALCOIT_AZDO_PAT_WORKITEMSREADWRITE
environment variable (expected to be encrypted).

.OUTPUTS
PSObject with summary of created/planned work items with hierarchy

.EXAMPLE
Create hierarchy with DryRun first:
    .\New-AzDoHierarchyFromMarkdown.ps1 -Organization "myorg" -Project "myproject" -MarkdownFilePath "hierarchy.md" -DryRun

.NOTES
- Markdown file must exist and be readable
- Requires Azure DevOps REST API access
- Pre-validates entire structure before creating items
- Hierarchy is inferred from header levels: # = Epic, ## = Feature, ### = Story
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [string]$MarkdownFilePath,

    [int]$EpicId,

    [switch]$DryRun,

    [string]$PatToken
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Import modules
. "$PSScriptRoot\AzDoAutomatorConstants.ps1"
. "$PSScriptRoot\AzDoPatTokenHelper.ps1"
. "$PSScriptRoot\AzDoApiWrapper.ps1"
. "$PSScriptRoot\AzDoWorkItemHelper.ps1"

# Validate ssLogIt.ps1 exists
if (-not (Get-Command -Name 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    Write-Error "Required helper script 'ssLogIt.ps1' not found in PATH."
}

# Validate markdown file
if (-not (Test-Path -LiteralPath $MarkdownFilePath -PathType Leaf)) {
    Write-Error "Markdown file not found: $MarkdownFilePath"
}

$null = & ssLogIt.ps1 -Level Info -Message "Parsing markdown file: ::FgGreen::$MarkdownFilePath::FgDefault::"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    # Call adapter to parse markdown to JSON
    $null = & ssLogIt.ps1 -Level Info -Message "Converting markdown to JSON structure..."
    $hierarchy = & "$PSScriptRoot\ConvertMarkdownToHierarchyJson.ps1" -MarkdownFilePath $MarkdownFilePath -ErrorAction Stop

    [object[]]$epics = $hierarchy.epics
    [object[]]$features = $hierarchy.topLevelFeatures

    $null = & ssLogIt.ps1 -Level Debug -Message "Markdown conversion successful"

    # Build dry-run summary
    [hashtable]$summary = @{
        PlannedEpics            = 0
        PlannedFeatures         = 0
        PlannedStories          = 0
        CreatedItems            = @()
    }

    # Count items
    $epicCount = $epics.Count
    $totalFeatures = @()
    if ($epics.Count -gt 0) {
        $totalFeatures = $epics | ForEach-Object { $_.Features.Count } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
    }
    $totalFeatures = if ($null -eq $totalFeatures) { 0 } else { [int]$totalFeatures }
    $totalFeatures += $features.Count
    
    $totalStories = 0
    foreach ($epic in $epics) {
        foreach ($feature in $epic.Features) {
            if ($feature.Stories) {
                $totalStories += @($feature.Stories).Count
            }
        }
    }
    foreach ($feature in $features) {
        if ($feature.Stories) {
            $totalStories += @($feature.Stories).Count
        }
    }

    $summary.PlannedEpics = $epicCount
    $summary.PlannedFeatures = $totalFeatures
    $summary.PlannedStories = $totalStories

    if ($DryRun) {
        $null = & ssLogIt.ps1 -Level Info -Message "DRY RUN: Would create $epicCount epic(s), $totalFeatures feature(s), $totalStories story(ies)"
        $null = & ssLogIt.ps1 -Level Debug -Message "DryRun mode - no work items created"
        return $summary
    }

    # Create work items
    $null = & ssLogIt.ps1 -Level Info -Message "Creating work items from validated markdown..."

    [hashtable]$createdItems = @{}

    # Create Epics and their children
    foreach ($epic in $epics) {
        $epicParams = @{
            Organization = $Organization
            Project      = $Project
            Title        = $epic.title
            PatToken     = $PatToken
        }

        if ($epic.description) {
            $epicParams['Description'] = $epic.description
        }

        if ($PSBoundParameters.ContainsKey('EpicId')) {
            $epicParams['ParentEpicId'] = $EpicId
        }

        $null = & ssLogIt.ps1 -Level Debug -Message "Creating Epic: $($epic.title)"
        $createdEpic = & "$PSScriptRoot\NewAzDoEpic.ps1" @epicParams -ErrorAction Stop
        $createdItems[$createdEpic.id] = $createdEpic

        foreach ($feature in $epic.features) {
            $featureParams = @{
                Organization    = $Organization
                Project         = $Project
                Title           = $feature.title
                ParentEpicId    = $createdEpic.id
                PatToken        = $PatToken
            }

            if ($feature.description) {
                $featureParams['Description'] = $feature.description
            }

            $null = & ssLogIt.ps1 -Level Debug -Message "Creating Feature: $($feature.title) under Epic"
            $createdFeature = & "$PSScriptRoot\NewAzDoFeature.ps1" @featureParams -ErrorAction Stop
            $createdItems[$createdFeature.id] = $createdFeature

            foreach ($story in $feature.stories) {
                $storyParams = @{
                    Organization    = $Organization
                    Project         = $Project
                    Title           = $story.title
                    ParentFeatureId = $createdFeature.id
                    PatToken        = $PatToken
                }

                if ($story.description) {
                    $storyParams['Description'] = $story.description
                }
                if ($story.acceptanceCriteria) {
                    $storyParams['AcceptanceCriteria'] = $story.acceptanceCriteria
                }
                if ($story.acScenarios) {
                    $storyParams['AcScenarios'] = $story.acScenarios
                }
                if ($story.extraInformation) {
                    $storyParams['ExtraInformation'] = $story.extraInformation
                }
                if ($story.storyPoints) {
                    $storyParams['StoryPoints'] = $story.storyPoints
                }

                $null = & ssLogIt.ps1 -Level Debug -Message "Creating Story: $($story.title)"
                $createdStory = & "$PSScriptRoot\NewAzDoStory.ps1" @storyParams -ErrorAction Stop
                $createdItems[$createdStory.id] = $createdStory
            }
        }
    }

    # Create top-level Features
    foreach ($feature in $features) {
        $featureParams = @{
            Organization = $Organization
            Project      = $Project
            Title        = $feature.title
            PatToken     = $PatToken
        }

        if ($feature.description) {
            $featureParams['Description'] = $feature.description
        }

        if ($PSBoundParameters.ContainsKey('EpicId')) {
            $featureParams['ParentEpicId'] = $EpicId
        }

        $null = & ssLogIt.ps1 -Level Debug -Message "Creating Feature: $($feature.title)"
        $createdFeature = & "$PSScriptRoot\NewAzDoFeature.ps1" @featureParams -ErrorAction Stop
        $createdItems[$createdFeature.id] = $createdFeature

        foreach ($story in $feature.stories) {
            $storyParams = @{
                Organization    = $Organization
                Project         = $Project
                Title           = $story.title
                ParentFeatureId = $createdFeature.id
                PatToken        = $PatToken
            }

            if ($story.description) {
                $storyParams['Description'] = $story.description
            }
            if ($story.acceptanceCriteria) {
                $storyParams['AcceptanceCriteria'] = $story.acceptanceCriteria
            }
            if ($story.acScenarios) {
                $storyParams['AcScenarios'] = $story.acScenarios
            }
            if ($story.extraInformation) {
                $storyParams['ExtraInformation'] = $story.extraInformation
            }
            if ($story.storyPoints) {
                $storyParams['StoryPoints'] = $story.storyPoints
            }

            $null = & ssLogIt.ps1 -Level Debug -Message "Creating Story: $($story.title)"
            $createdStory = & "$PSScriptRoot\NewAzDoStory.ps1" @storyParams -ErrorAction Stop
            $createdItems[$createdStory.id] = $createdStory
        }
    }

    $summary.CreatedItems = $createdItems

    # Add "generated" tag to all created items
    $null = & ssLogIt.ps1 -Level Debug -Message "Adding 'generated' tag to all created work items..."
    [int]$taggedCount = 0
    foreach ($itemId in $createdItems.Keys) {
        try {
            $null = & "$PSScriptRoot\SetAzDoWorkItemTags.ps1" `
                -Organization $Organization `
                -Project $Project `
                -WorkItemId $itemId `
                -Tags @("generated") `
                -Mode Add `
                -PatToken $PatToken `
                -ErrorAction Stop
            $taggedCount++
        }
        catch {
            $null = & ssLogIt.ps1 -Level Warn -Message "Failed to tag work item $itemId with 'generated': $_"
        }
    }
    $null = & ssLogIt.ps1 -Level Debug -Message "Tagged $taggedCount items with 'generated' tag"

    $null = & ssLogIt.ps1 -Level Info -Message "Successfully created $($createdItems.Count) work items from markdown"

    return $summary
}
catch {
    $null = & ssLogIt.ps1 -Level Error -Message "Failed to create hierarchy from markdown: $_"
    throw
}
