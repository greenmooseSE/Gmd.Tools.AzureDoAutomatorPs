<#
.SYNOPSIS
Create Azure DevOps work item hierarchy from markdown file

.DESCRIPTION
Parses a markdown file and creates a hierarchy of Epic/Feature/Story or Feature/Story work items.
Performs full validation before creating any items (fail-fast approach).

Markdown format:
    # Epic Title (optional)
    ## Feature 1 Title
    - Story 1 Title
      - AC: Acceptance criteria
      - SP: 5 (story points)
    - Story 2 Title

Pre-validates:
- Valid markdown structure
- No unsupported fields
- Parse errors

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

Create actual hierarchy under Epic:
    .\New-AzDoHierarchyFromMarkdown.ps1 -Organization "myorg" -Project "myproject" -MarkdownFilePath "hierarchy.md" -EpicId 100

.NOTES
- Markdown file must exist and be readable
- Requires Azure DevOps REST API access
- Pre-validates entire structure before creating items
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
. "$PSScriptRoot/AzDoAutomatorConstants.ps1"
. "$PSScriptRoot/AzDoPatTokenHelper.ps1"
. "$PSScriptRoot/AzDoApiWrapper.ps1"
. "$PSScriptRoot/AzDoWorkItemHelper.ps1"

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
    # Read and parse markdown file
    [string[]]$lines = @(Get-Content -LiteralPath $MarkdownFilePath -Raw) -split "`n"

    # Structure to hold parsed data
    [object[]]$epics = @()
    [object[]]$currentEpic = $null
    [object[]]$features = @()
    [object[]]$currentFeature = $null
    [object[]]$stories = @()

    $null = & ssLogIt.ps1 -Level Debug -Message "Pre-validating markdown structure..."

    # First pass: parse and validate structure
    [int]$lineNum = 0
    foreach ($line in $lines) {
        $lineNum++
        $line = $line.TrimEnd()

        # Skip empty lines and comments
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('<!')) {
            continue
        }

        # Check for Epic heading (# )
        if ($line -match $script:REGEX_MARKDOWN_EPIC) {
            [string]$epicTitle = $matches[1].Trim()
            if ([string]::IsNullOrWhiteSpace($epicTitle)) {
                Write-Error "Invalid Epic title at line $lineNum : Title cannot be empty"
            }
            $currentEpic = @{
                Title    = $epicTitle
                Features = @()
            }
            $epics += $currentEpic
            $currentFeature = $null
            $null = & ssLogIt.ps1 -Level Debug -Message "Found Epic: $epicTitle"
            continue
        }

        # Check for Feature heading (## )
        if ($line -match $script:REGEX_MARKDOWN_FEATURE) {
            [string]$featureTitle = $matches[1].Trim()
            if ([string]::IsNullOrWhiteSpace($featureTitle)) {
                Write-Error "Invalid Feature title at line $lineNum : Title cannot be empty"
            }
            $currentFeature = @{
                Title   = $featureTitle
                Stories = @()
            }
            if ($null -ne $currentEpic) {
                $currentEpic.Features += $currentFeature
            }
            else {
                $features += $currentFeature
            }
            $null = & ssLogIt.ps1 -Level Debug -Message "Found Feature: $featureTitle"
            continue
        }

        # Check for Story (- text)
        if ($line -match $script:REGEX_MARKDOWN_STORY) {
            [string]$storyTitle = $matches[1].Trim()
            if ([string]::IsNullOrWhiteSpace($storyTitle)) {
                Write-Error "Invalid Story title at line $lineNum : Title cannot be empty"
            }
            if ($null -eq $currentFeature) {
                Write-Error "Story found at line $lineNum but no parent Feature: $storyTitle"
            }
            $story = @{
                Title              = $storyTitle
                AcceptanceCriteria = $null
                StoryPoints        = $null
            }
            $currentFeature.Stories += $story
            $null = & ssLogIt.ps1 -Level Debug -Message "Found Story: $storyTitle"
            continue
        }

        # Check for Acceptance Criteria (- AC: text)
        if ($line -match $script:REGEX_MARKDOWN_AC) {
            [string]$ac = $matches[1].Trim()
            if ($null -eq $currentFeature -or $currentFeature.Stories.Count -eq 0) {
                Write-Error "Acceptance Criteria found at line $lineNum but no parent Story"
            }
            $currentStory = $currentFeature.Stories[-1]
            $currentStory.AcceptanceCriteria = $ac
            continue
        }

        # Check for Story Points (- SP: number)
        if ($line -match $script:REGEX_MARKDOWN_SP) {
            [int]$sp = $matches[1]
            if ($sp -lt 0) {
                Write-Error "Invalid Story Points at line $lineNum : Must be non-negative. Found: $sp"
            }
            if ($null -eq $currentFeature -or $currentFeature.Stories.Count -eq 0) {
                Write-Error "Story Points found at line $lineNum but no parent Story"
            }
            $currentStory = $currentFeature.Stories[-1]
            $currentStory.StoryPoints = $sp
            continue
        }

        # Any other line is an error
        if (-not [string]::IsNullOrWhiteSpace($line) -and -not $line.StartsWith('#')) {
            Write-Error "Unsupported line format at line $lineNum : $line"
        }
    }

    $null = & ssLogIt.ps1 -Level Debug -Message "Markdown structure validation successful"

    # Build dry-run summary
    [hashtable]$summary = @{
        PlannedEpics            = 0
        PlannedFeatures         = 0
        PlannedStories          = 0
        CreatedItems            = @()
    }

    # Summary message
    $totalFeatures = $epics | ForEach-Object { $_.Features.Count } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
    $totalFeatures += $features.Count
    $totalStories = 0
    foreach ($epic in $epics) {
        foreach ($feature in $epic.Features) {
            $totalStories += $feature.Stories.Count
        }
    }
    foreach ($feature in $features) {
        $totalStories += $feature.Stories.Count
    }

    $epicCount = $epics.Count
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
            Title        = $epic.Title
            PatToken     = $PatToken
        }

        if ($PSBoundParameters.ContainsKey('EpicId')) {
            $epicParams['ParentEpicId'] = $EpicId
        }

        $null = & ssLogIt.ps1 -Level Debug -Message "Creating Epic: $($epic.Title)"
        $createdEpic = & "$PSScriptRoot/NewAzDoEpic.ps1" @epicParams -ErrorAction Stop
        $createdItems[$createdEpic.id] = $createdEpic

        # Verify we got a Feature instead (Azure DevOps might treat them the same)
        # Create Features under this Epic
        foreach ($feature in $epic.Features) {
            $featureParams = @{
                Organization    = $Organization
                Project         = $Project
                Title           = $feature.Title
                ParentEpicId    = $createdEpic.id
                PatToken        = $PatToken
            }

            $null = & ssLogIt.ps1 -Level Debug -Message "Creating Feature: $($feature.Title) under Epic"
            $createdFeature = & "$PSScriptRoot/NewAzDoFeature.ps1" @featureParams -ErrorAction Stop
            $createdItems[$createdFeature.id] = $createdFeature

            # Create Stories under Feature
            foreach ($story in $feature.Stories) {
                $storyParams = @{
                    Organization    = $Organization
                    Project         = $Project
                    Title           = $story.Title
                    ParentFeatureId = $createdFeature.id
                    PatToken        = $PatToken
                }

                if ($null -ne $story.AcceptanceCriteria) {
                    $storyParams['AcceptanceCriteria'] = $story.AcceptanceCriteria
                }

                if ($null -ne $story.StoryPoints) {
                    $storyParams['StoryPoints'] = $story.StoryPoints
                }

                $null = & ssLogIt.ps1 -Level Debug -Message "Creating Story: $($story.Title)"
                $createdStory = & "$PSScriptRoot/NewAzDoStory.ps1" @storyParams -ErrorAction Stop
                $createdItems[$createdStory.id] = $createdStory
            }
        }
    }

    # Create top-level Features
    foreach ($feature in $features) {
        $featureParams = @{
            Organization = $Organization
            Project      = $Project
            Title        = $feature.Title
            PatToken     = $PatToken
        }

        if ($PSBoundParameters.ContainsKey('EpicId')) {
            $featureParams['ParentEpicId'] = $EpicId
        }

        $null = & ssLogIt.ps1 -Level Debug -Message "Creating Feature: $($feature.Title)"
        $createdFeature = & "$PSScriptRoot/NewAzDoFeature.ps1" @featureParams -ErrorAction Stop
        $createdItems[$createdFeature.id] = $createdFeature

        # Create Stories under Feature
        foreach ($story in $feature.Stories) {
            $storyParams = @{
                Organization    = $Organization
                Project         = $Project
                Title           = $story.Title
                ParentFeatureId = $createdFeature.id
                PatToken        = $PatToken
            }

            if ($null -ne $story.AcceptanceCriteria) {
                $storyParams['AcceptanceCriteria'] = $story.AcceptanceCriteria
            }

            if ($null -ne $story.StoryPoints) {
                $storyParams['StoryPoints'] = $story.StoryPoints
            }

            $null = & ssLogIt.ps1 -Level Debug -Message "Creating Story: $($story.Title)"
            $createdStory = & "$PSScriptRoot/NewAzDoStory.ps1" @storyParams -ErrorAction Stop
            $createdItems[$createdStory.id] = $createdStory
        }
    }

    $summary.CreatedItems = $createdItems
    $null = & ssLogIt.ps1 -Level Info -Message "Successfully created $($createdItems.Count) work items from markdown"

    return $summary
}
catch {
    $null = & ssLogIt.ps1 -Level Error -Message "Failed to create hierarchy from markdown: $_"
    Write-Error $_
}
