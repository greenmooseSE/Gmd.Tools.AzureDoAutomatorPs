<#
.SYNOPSIS
Generate a synthetic markdown hierarchy file for testing purposes.

.DESCRIPTION
Creates a complete markdown hierarchy file with made-up but realistic data for all
work item types (Epic, Feature, Story, Bug, Task). All writable fields defined in the
markdown template (see src/GenerateAzDoMarkdownHierarchyTemplate.ps1) are populated
with generated values.

Useful for testing ConvertMarkdownToHierarchyJson.ps1, NewAzDoHierarchyFromMarkdown.ps1,
and other tools that consume the markdown hierarchy format without needing to predifine
a hierarchy manually.

Values are differentiated between work items using a timestamp seed so each generated
item has unique yet deterministic values within a single run.

.PARAMETER EpicTitle
Title for the single generated Epic. Required.

.PARAMETER MdOutputFile
Path to the markdown file to write. Required.

.PARAMETER FeatureCount
Number of Features to create under the Epic. Default: 2.

.PARAMETER StoryPerFeatureCount
Number of Stories to create under each Feature. Default: 2.

.PARAMETER BugPerFeatureCount
Number of Bugs to create under each Feature (as siblings to Stories). Default: 2.

.PARAMETER TaskPerStory
Number of Tasks to create under each Story. Default: 2.

.PARAMETER TaskPerBug
Number of Tasks to create under each Bug. Default: 2.

.PARAMETER CreateSomeStoriesAndBugsWithoutTasks
When specified, the last Story and the last Bug in each Feature are created without
any Tasks (applicable only when the respective count is >= 1).

.EXAMPLE
Generate with defaults:
    .\test\CreateTestMarkdown.ps1 -EpicTitle "My Test Epic" -MdOutputFile ".\tmp\test-hierarchy.md"

Generate small hierarchy:
    .\test\CreateTestMarkdown.ps1 -EpicTitle "Test Epic" -MdOutputFile "out.md" -FeatureCount 1 -StoryPerFeatureCount 1 -BugPerFeatureCount 1 -TaskPerStory 1 -TaskPerBug 1

Generate with some items having no tasks:
    .\test\CreateTestMarkdown.ps1 -EpicTitle "Test" -MdOutputFile "out.md" -CreateSomeStoriesAndBugsWithoutTasks

.NOTES
- All generated items receive "testWi" tag for easy identification in Azure DevOps.
- Bugs appear at the same level as Stories (children of Features), so that each Bug
  can have its own Tasks.
- Output format matches exactly what GenerateAzDoMarkdownHierarchyTemplate.ps1 documents.
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [string]$EpicTitle,

    [Parameter(Mandatory = $true)]
    [string]$MdOutputFile,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 50)]
    [int]$FeatureCount = 2,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 50)]
    [int]$StoryPerFeatureCount = 2,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 50)]
    [int]$BugPerFeatureCount = 2,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 50)]
    [int]$TaskPerStory = 2,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 50)]
    [int]$TaskPerBug = 2,

    [Parameter(Mandatory = $false)]
    [switch]$CreateSomeStoriesAndBugsWithoutTasks
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Validate ssLogIt.ps1 is available
if (-not (Get-Command -Name 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    Write-Error "Required helper script 'ssLogIt.ps1' not found in PATH."
}

# ============================================================================
# Value Generators
# ============================================================================

# Seed so each run produces values that differ from other runs
$_seed = Get-Date -Format "yyyyMMddHHmmss"

function zGetSeq {
    param([int]$featureIdx = 0, [int]$itemIdx = 0)
    return "$_seed-f$featureIdx-i$itemIdx"
}

function zGetOrderPad {
    param([int]$n)
    return $n.ToString("000")
}

function zGetTags {
    param([string]$epicTag, [string]$featureTag = '', [string]$extraTag = '')
    $parts = @($epicTag)
    if (-not [string]::IsNullOrEmpty($featureTag)) { $parts += $featureTag }
    if (-not [string]::IsNullOrEmpty($extraTag))   { $parts += $extraTag }
    $parts += 'testWi'
    return $parts -join ', '
}

function zGetEffort {
    param([int]$base, [int]$featureIdx)
    return $base + ($featureIdx % 5)
}

function zGetSP {
    param([int]$base, [int]$featureIdx, [int]$itemIdx)
    return $base + (($featureIdx + $itemIdx) % 4)
}

function zGetPriority {
    param([int]$featureIdx, [int]$itemIdx)
    return (($featureIdx + $itemIdx) % 3) + 1
}

function zGetOriginalEstimate {
    param([int]$featureIdx, [int]$itemIdx)
    return (($featureIdx + $itemIdx) % 4) + 2
}

function zGetPersona {
    param([int]$idx)
    $personas = @('developer', 'end user', 'system administrator', 'team lead', 'QA engineer')
    return $personas[$idx % $personas.Count]
}

function zGetAction {
    param([string]$seq)
    return "perform action $seq"
}

function zGetBenefit {
    param([string]$seq)
    return "the system behaviour is verified for $seq"
}

# ============================================================================
# Block Builders
# ============================================================================

function Build-TaskBlock {
    param(
        [string]$Title,
        [string]$Tags,
        [int]$Priority,
        [int]$OriginalEstimate
    )
    return @"

#### Task: $Title

**tags**: $Tags  
**Priority**: $Priority  
**OriginalEstimate**: $OriginalEstimate  
**Description**  
Implements the concrete work described by the parent item.  
Covers implementation, unit tests, and documentation for this task.  
"@
}

function Build-StoryBlock {
    param(
        [string]$Title,
        [string]$Tags,
        [int]$SP,
        [string]$Persona,
        [string]$Action,
        [string]$Benefit,
        [string]$Seq,
        [string[]]$TaskBlocks
    )
    $tasksContent = $TaskBlocks -join ''
    return @"

### Story: $Title

**tags**: $Tags  
**SP**: $SP  
**Description**  
**As a** $Persona  
**I want** to $Action  
**So that** $Benefit  

Additional context for this story generated at $Seq.  

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ☐ | Feature works correctly for happy path scenario |  |  |
| ☐ | Validation rejects invalid input and surfaces error |  |  |
| ☐ | State is persisted correctly across requests |  |  |

#### AC Scenarios
1. **Scenario**: Happy path - all inputs valid  
   Given the system is in a valid initial state  
   When the user performs the requested action  
   Then the expected outcome is observed  
   And the state is updated correctly  

2. **Scenario**: Validation failure - invalid input rejected  
   Given invalid input is provided  
   When the action is attempted  
   Then an appropriate error is returned  
   And no side effects occur  

#### Extra Information
- Generated seed: $Seq  
- This story is auto-generated for testing purposes  
$tasksContent
"@
}

function Build-BugBlock {
    param(
        [string]$Title,
        [string]$Tags,
        [int]$SP,
        [int]$Priority,
        [string]$Persona,
        [string]$Action,
        [string]$Benefit,
        [string]$Seq,
        [string[]]$TaskBlocks
    )
    $tasksContent = $TaskBlocks -join ''
    return @"

### Bug: $Title

**tags**: $Tags  
**SP**: $SP  
**Priority**: $Priority  
**Description**  
**As a** $Persona  
**I want** $Action to be handled gracefully  
**So that** $Benefit  

Repro steps for bug generated at $($Seq):  
1. Set up the precondition described above.  
2. Trigger the action.  
3. Observe unexpected behaviour.  

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ☐ | Bug condition is detected and handled |  |  |
| ☐ | Error is surfaced to the user with a clear message |  |  |
| ☐ | System recovers without data loss |  |  |

#### AC Scenarios
1. **Scenario**: Bug condition is triggered  
   Given the defective condition exists  
   When the operation is performed  
   Then the error is caught and surfaced  
   And the system remains in a consistent state  
$tasksContent
"@
}

function Build-FeatureBlock {
    param(
        [string]$Title,
        [string]$Tags,
        [int]$Effort,
        [string]$Seq,
        [string[]]$ChildBlocks
    )
    $childContent = $ChildBlocks -join ''
    return @"

## Feature: $Title

**tags**: $Tags  
**Effort**: $Effort  
**Description**  
This feature covers a specific area of functionality generated at $Seq.  
Includes all stories and bugs required to deliver the feature end-to-end.  

#### Design Notes
- Auto-generated feature for test purposes  
- Seed: $Seq  
$childContent
"@
}

function Build-EpicBlock {
    param(
        [string]$Title,
        [string]$Tags,
        [int]$Effort,
        [string]$Seq,
        [string[]]$ChildBlocks
    )
    $childContent = $ChildBlocks -join ''
    return @"
# Epic: $Title

**tags**: $Tags  
**Effort**: $Effort  
**Description**  
Auto-generated test epic created at $Seq.  
Contains all features, stories, bugs, and tasks needed for test coverage.  

### Architecture/Design Overview
This epic is fully generated and covers multiple features across several dimensions of functionality.  
$childContent
"@
}

# ============================================================================
# Build the hierarchy
# ============================================================================

$null = & ssLogIt.ps1 -Level Info -Message "::FgGreen::Creating test markdown hierarchy::FgDefault:: -> ::FgGreen::$MdOutputFile::FgDefault::"
$null = & ssLogIt.ps1 -Level Debug -Message "Features: $FeatureCount | Stories/Feature: $StoryPerFeatureCount | Bugs/Feature: $BugPerFeatureCount | Tasks/Story: $TaskPerStory | Tasks/Bug: $TaskPerBug"

$epicTag      = ($EpicTitle -replace '[^a-zA-Z0-9]', '') | ForEach-Object { $_.Substring(0,1).ToLower() + $_.Substring(1) }
$epicSeq      = zGetSeq -featureIdx 0 -itemIdx 0
$epicEffort   = zGetEffort -base 21 -featureIdx 0
$featureBlocks = @()

for ($fi = 1; $fi -le $FeatureCount; $fi++) {
    $fPad       = zGetOrderPad -n $fi
    $featureTag = "feature$fPad"
    $featureSeq = zGetSeq -featureIdx $fi -itemIdx 0
    $fEffort    = zGetEffort -base 8 -featureIdx $fi

    $childBlocks = @()

    # Stories
    for ($si = 1; $si -le $StoryPerFeatureCount; $si++) {
        $sPad     = zGetOrderPad -n $si
        $storySeq = zGetSeq -featureIdx $fi -itemIdx $si
        $storyTitle = "Story $fPad-$sPad ($storySeq)"

        $isLastStory = ($si -eq $StoryPerFeatureCount)
        $omitTasks   = $CreateSomeStoriesAndBugsWithoutTasks -and $isLastStory

        $taskBlocks = @()
        if (-not $omitTasks) {
            for ($ti = 1; $ti -le $TaskPerStory; $ti++) {
                $tPad       = zGetOrderPad -n $ti
                $taskSeq    = zGetSeq -featureIdx $fi -itemIdx ($si * 100 + $ti)
                $taskTitle  = "Task $fPad-$sPad-$tPad ($taskSeq)"
                $taskBlocks += Build-TaskBlock `
                    -Title $taskTitle `
                    -Tags (zGetTags -epicTag $epicTag -featureTag $featureTag -extraTag 'dev') `
                    -Priority (zGetPriority -featureIdx $fi -itemIdx $ti) `
                    -OriginalEstimate (zGetOriginalEstimate -featureIdx $fi -itemIdx $ti)
            }
        }
        else {
            $null = & ssLogIt.ps1 -Level Debug -Message "Story ::FgYellow::$storyTitle::FgDefault:: created without tasks (CreateSomeStoriesAndBugsWithoutTasks)"
        }

        $childBlocks += Build-StoryBlock `
            -Title $storyTitle `
            -Tags (zGetTags -epicTag $epicTag -featureTag $featureTag -extraTag 'userFacing') `
            -SP (zGetSP -base 3 -featureIdx $fi -itemIdx $si) `
            -Persona (zGetPersona -idx ($fi + $si)) `
            -Action (zGetAction -seq $storySeq) `
            -Benefit (zGetBenefit -seq $storySeq) `
            -Seq $storySeq `
            -TaskBlocks $taskBlocks
    }

    # Bugs
    for ($bi = 1; $bi -le $BugPerFeatureCount; $bi++) {
        $bPad    = zGetOrderPad -n $bi
        $bugSeq  = zGetSeq -featureIdx $fi -itemIdx ($bi + 1000)
        $bugTitle = "Bug $fPad-$bPad ($bugSeq)"

        $isLastBug = ($bi -eq $BugPerFeatureCount)
        $omitTasks  = $CreateSomeStoriesAndBugsWithoutTasks -and $isLastBug

        $taskBlocks = @()
        if (-not $omitTasks) {
            for ($ti = 1; $ti -le $TaskPerBug; $ti++) {
                $tPad     = zGetOrderPad -n $ti
                $taskSeq  = zGetSeq -featureIdx $fi -itemIdx ($bi * 200 + $ti)
                $taskTitle = "Task $fPad-$bPad-$tPad ($taskSeq)"
                $taskBlocks += Build-TaskBlock `
                    -Title $taskTitle `
                    -Tags (zGetTags -epicTag $epicTag -featureTag $featureTag -extraTag 'bugfix') `
                    -Priority (zGetPriority -featureIdx $fi -itemIdx $ti) `
                    -OriginalEstimate (zGetOriginalEstimate -featureIdx $fi -itemIdx $ti)
            }
        }
        else {
            $null = & ssLogIt.ps1 -Level Debug -Message "Bug ::FgYellow::$bugTitle::FgDefault:: created without tasks (CreateSomeStoriesAndBugsWithoutTasks)"
        }

        $childBlocks += Build-BugBlock `
            -Title $bugTitle `
            -Tags (zGetTags -epicTag $epicTag -featureTag $featureTag -extraTag 'bug') `
            -SP (zGetSP -base 2 -featureIdx $fi -itemIdx $bi) `
            -Priority (zGetPriority -featureIdx $fi -itemIdx $bi) `
            -Persona (zGetPersona -idx ($fi + $bi + 10)) `
            -Action (zGetAction -seq $bugSeq) `
            -Benefit (zGetBenefit -seq $bugSeq) `
            -Seq $bugSeq `
            -TaskBlocks $taskBlocks
    }

    $featureBlocks += Build-FeatureBlock `
        -Title "Feature $fPad ($featureSeq)" `
        -Tags (zGetTags -epicTag $epicTag -featureTag $featureTag) `
        -Effort $fEffort `
        -Seq $featureSeq `
        -ChildBlocks $childBlocks
}

$epicBlock = Build-EpicBlock `
    -Title $EpicTitle `
    -Tags (zGetTags -epicTag $epicTag) `
    -Effort $epicEffort `
    -Seq $epicSeq `
    -ChildBlocks $featureBlocks

# ============================================================================
# Write output
# ============================================================================

$outputDir = Split-Path -Parent $MdOutputFile
if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
    $null = New-Item -ItemType Directory -Path $outputDir -Force
    $null = & ssLogIt.ps1 -Level Debug -Message "Created output directory: $outputDir"
}

$epicBlock | Set-Content -LiteralPath $MdOutputFile -Encoding UTF8

# Summary
$totalStories = $FeatureCount * $StoryPerFeatureCount
$totalBugs    = $FeatureCount * $BugPerFeatureCount
$totalTasks   = ($totalStories * $TaskPerStory) + ($totalBugs * $TaskPerBug)
if ($CreateSomeStoriesAndBugsWithoutTasks) {
    # Last story and last bug per feature lose their tasks
    $totalTasks -= $FeatureCount * $TaskPerStory
    $totalTasks -= $FeatureCount * $TaskPerBug
}

$null = & ssLogIt.ps1 -Level Info -Message "::FgGreen::Markdown hierarchy written::FgDefault:: to ::FgGreen::$MdOutputFile::FgDefault::"
$null = & ssLogIt.ps1 -Level Info -Message "Summary: 1 Epic | $FeatureCount Features | $totalStories Stories | $totalBugs Bugs | ~$totalTasks Tasks"
