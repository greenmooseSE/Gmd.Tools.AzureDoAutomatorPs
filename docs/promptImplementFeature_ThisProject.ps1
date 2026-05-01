<#
.SYNOPSIS
    Generates a complete AI agent prompt for implementing an AzureDoAutomatorPs (PowerShell) feature with multiple stories.

.DESCRIPTION
    Produces a dynamically composed prompt for AI agents to implement all stories in a feature plan,
    embedding multi-story branching instructions, story implementation rules, project-specific
    AutomatorPs story rules, and architectural rules from their source markdown files.

    The generated prompt is written to stdout and optionally to a file or the clipboard.

.PARAMETER FeatureId
    The Azure DevOps work item ID of the feature (e.g. 1590).

.PARAMETER FeatureTitle
    Optional. A short camelCase description of the feature used to construct the feature branch name
    (e.g. "exportImportHierarchy"). The feature branch will be named: feat/ab#<FeatureId>-<FeatureTitle>.
    When omitted, the title is derived from the plan file by finding the Feature heading matching FeatureId
    and converting it to camelCase.

.PARAMETER PlanFile
    Relative path from WorkspaceRoot to the plan markdown file that lists all stories
    (e.g. "docs\plans\plan-1590-exportImportHierarchy.md").

.PARAMETER WorkspaceRoot
    Full path to the root of the target project workspace. Defaults to the current directory.

.PARAMETER OutputToClipboard
    When specified, copies the generated prompt to the clipboard in addition to stdout.

.PARAMETER OutputFile
    When specified, writes the generated prompt to this file path in addition to stdout.

.EXAMPLE
    .\docs\promptImplementFeatureThisProject.ps1 -FeatureId 1590 -FeatureTitle "exportImportHierarchy" -PlanFile "docs\plans\plan-1590-exportImportHierarchy.md" -OutputToClipboard

.EXAMPLE
    .\docs\promptImplementFeatureThisProject.ps1 -FeatureId 1590 -FeatureTitle "exportImportHierarchy" -PlanFile "docs\plans\plan-1590-exportImportHierarchy.md" -OutputFile "tmp\generated-prompt.md"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [int]$FeatureId,

    [string]$FeatureTitle = '',

    [Parameter(Mandatory)]
    [string]$PlanFile,

    [string]$WorkspaceRoot = $PWD.Path,

    [switch]$OutputToClipboard,

    [string]$OutputFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Resolve paths ──────────────────────────────────────────────────────────────
$ScriptDir = $PSScriptRoot

function hReadInclude {
    param([string]$RelativePath)
    $fullPath = Join-Path $ScriptDir $RelativePath
    if (-not (Test-Path $fullPath)) {
        throw "Include template not found: $fullPath"
    }
    return Get-Content $fullPath -Raw
}

# ── Load include templates ─────────────────────────────────────────────────────
$multiStoryContent             = hReadInclude 'multiStoryInstructions.md'
$implementRulesContent         = hReadInclude 'implementStoryRules.md'
$implementRulesThisProjectContent = hReadInclude 'implementStoryRules_ThisProject.md'
$generalStoryRulesContent      = hReadInclude 'createStoryRules_General.md'
$projectStoryRulesContent      = hReadInclude 'createStoryRules_ThisProject.md'
$archRulesContent              = hReadInclude 'architecturalRules_General.md'

# ── Resolve FeatureTitle from plan file if not supplied ────────────────────────
if (-not $FeatureTitle) {
    $resolvedPlanForTitle = Join-Path $WorkspaceRoot $PlanFile
    if (-not (Test-Path $resolvedPlanForTitle)) {
        throw "Plan file not found: $resolvedPlanForTitle"
    }
    $planLines = Get-Content $resolvedPlanForTitle
    # Find the Feature heading whose next WorkItemId line matches FeatureId
    $featureRawTitle = $null
    for ($i = 0; $i -lt $planLines.Count; $i++) {
        if ($planLines[$i] -match '^#{1,3}\s+Feature:\s+(.+)$') {
            $candidateTitle = $Matches[1].Trim()
            # Look ahead for WorkItemId within the next ~5 lines
            for ($j = $i + 1; $j -le [Math]::Min($i + 5, $planLines.Count - 1); $j++) {
                if ($planLines[$j] -match '\*\*WorkItemId\*\*\s*:\s*(\d+)') {
                    if ([int]$Matches[1] -eq $FeatureId) {
                        $featureRawTitle = $candidateTitle
                    }
                    break
                }
            }
        }
        if ($featureRawTitle) { break }
    }
    if (-not $featureRawTitle) {
        throw "Could not find Feature with WorkItemId $FeatureId in plan file. Please supply -FeatureTitle explicitly."
    }
    # Convert to camelCase: split on non-alphanumeric, capitalise each word, lowercase first char
    $words = $featureRawTitle -split '[^a-zA-Z0-9]+'
    $words = $words | Where-Object { $_ -ne '' }
    $FeatureTitle = ($words[0].Substring(0,1).ToLower() + $words[0].Substring(1)) +
                    (($words | Select-Object -Skip 1 | ForEach-Object {
                        $_.Substring(0,1).ToUpper() + $_.Substring(1)
                    }) -join '')
}

# ── Derived values ─────────────────────────────────────────────────────────────
$featureBranch    = "feat/ab#$($FeatureId)-$FeatureTitle"
$resolvedPlanFile = Join-Path $WorkspaceRoot $PlanFile

# ── Build prompt ───────────────────────────────────────────────────────────────
$prompt = @"
# Implement Feature AB#FEATURE_ID — All Stories (AzureDoAutomatorPs / PowerShell)

Implement all stories in the plan file one by one, following the rules and branching strategy
described below. Work locally only — skip any deployment steps.

---

## Placeholders

> Update these values before sending this prompt:

| Placeholder       | Value                                      |
|-------------------|--------------------------------------------|
| FEATURE_ID        | $FeatureId                                 |
| FEATURE_BRANCH    | $featureBranch                             |
| PLAN_FILE         | $PlanFile                                  |
| WORKSPACE_ROOT    | $WorkspaceRoot                             |

---

## Plan File

Implement stories in:

    WORKSPACE_ROOT\PLAN_FILE

i.e. ``$resolvedPlanFile``

Mark each story as done in the plan file as you complete it.

---

## Azure DevOps Configuration

- **Organization**: falco-it
- **Project**: GMD
- **PAT Token**: ``(`$env:GMD_AZDO_MACHINE_WORKITEMSRW | ssEncryptDecrypt.ps1 -Decrypt)``
- **Scripts location**: ``$WorkspaceRoot\src``

---

## Branching Strategy

### Feature branch
The feature branch for AB#FEATURE_ID must already exist before starting:

    FEATURE_BRANCH  →  $featureBranch

If it does not exist yet, create it from ``develop``:

    ssNewFeatBranch.ps1 -Ticket FEATURE_ID -Description "FEATURE_TITLE" -NoFetch -BaseBranch develop

### Story branches
For each story, create a branch off the **feature branch** (not ``develop``):

    story/ab#<StoryId>-<camelCaseShortStoryTitle>

Example:

    ssNewFeatBranch.ps1 -Ticket <StoryId> -Description "<story title>" -IsStory -NoFetch -BaseBranch "ab#FEATURE_ID-FEATURE_TITLE"

### Merge strategy
After completing each story:
1. Commit all story changes.
2. Checkout the feature branch (FEATURE_BRANCH).
3. Merge the story branch with ``--no-ff``:

       git checkout FEATURE_BRANCH
       git merge story/ab#<StoryId>-<camelCaseShortStoryTitle> --no-ff

4. Continue to the next story.

---

## Testing Requirements

This project uses **Pester** for integration-level PowerShell tests.

- **Test work item lifecycle:** Any Azure DevOps work items created during tests (epics, features,
  stories, tasks, bugs) **must be deleted during test teardown**, even if the test fails.
  - Prefer using ``AfterAll``/``AfterEach`` Pester blocks to perform cleanup.
  - Track all created work item IDs and remove them via the appropriate Remove script in ``src/``
    (e.g. ``RemoveAzDoStory.ps1``, ``RemoveAzDoFeature.ps1``, ``RemoveAzDoEpic.ps1``).
  - Tag every test-created work item with ``testWi`` to allow easy detection of orphans.
  - If orphan test items are found, attempt cleanup and report status in test output.
- **Integration style:** Prefer integration-level Pester tests that invoke the real scripts against
  the live AzDo API (using a scoped PAT) over mocked unit tests.
- **TDD style:** Write or update tests before or in parallel with the implementation. Every story
  must have automated Pester tests covering its acceptance criteria and BDD scenarios.
- **Test file location:** Group test files in folders by functionality. For story-specific tests,
  include story ID and camelCase title in the file name and place them under ``test/storyAcTests``.
- **No PSScriptAnalyzer warnings** in implemented scripts.
- **Logging:** Use ``ssLogIt.ps1`` for all output messages. Do not use ``Write-Host`` or
  ``Write-Error`` directly.

---

## General Guidelines

- **Chunked work:** Break implementation into small batches to avoid hitting response-length limits.
- **Compact conversation** before starting each new story when possible.
- **No deployment:** skip CI/CD steps entirely.
- **Fail fast:** throw exceptions rather than implementing silent fallbacks.
- **Update the plan file** to mark each story complete as you go.
- **ssInvokeExpr.ps1**: Use this helper when invoking shell expressions or external commands.
- **copilot-instructions.md**: Always read and apply ``.github/copilot-instructions.md`` before
  implementing anything.

---

## Multi-Story Process

$multiStoryContent

---

## Story Implementation Rules

$implementRulesContent

$implementRulesThisProjectContent

---

## General Story Rules

$generalStoryRulesContent

---

## Project-Specific Story Rules (AzureDoAutomatorPs)

$projectStoryRulesContent

---

## Architectural Rules

$archRulesContent

---

*Generated by ``docs\promptImplementFeature_ThisProject.ps1`` — $(Get-Date -Format 'yyyy-MM-dd HH:mm')*
"@

# ── Output ─────────────────────────────────────────────────────────────────────
Write-Output $prompt

if ($OutputToClipboard) {
    $prompt | Set-Clipboard
    Write-Host "`n[Prompt copied to clipboard]" -ForegroundColor Green
}

if ($OutputFile) {
    $prompt | Set-Content -Path $OutputFile -Encoding UTF8
    Write-Host "[Prompt written to: $OutputFile]" -ForegroundColor Green
}
