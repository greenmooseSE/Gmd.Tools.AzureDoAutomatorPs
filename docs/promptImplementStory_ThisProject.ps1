<#
.SYNOPSIS
    Generates a complete AI agent prompt for implementing a single story in the AzureDoAutomatorPs project.

.DESCRIPTION
    Produces a dynamically composed prompt for AI agents to implement a single story,
    embedding the story implementation rules, project-specific AutomatorPs rules, and
    architectural rules from their source markdown files.

    The generated prompt references `.github/copilot-instructions.md` so the AI agent does not
    overlook it, but does not include its content in the merged output.

    The generated prompt is written to stdout and optionally to a file or the clipboard.

.PARAMETER StoryId
    The Azure DevOps work item ID of the story to implement (e.g. 2695).

.PARAMETER FeatureId
    Optional. The Azure DevOps work item ID of the parent feature. Used to derive the feature
    branch name when -FeatureBranch is not supplied.

.PARAMETER FeatureBranch
    Optional. Explicit feature branch name the story branch should be created from
    (e.g. "feat/ab#2694-agentWorkflowPlanProgress"). When omitted, the branch is derived
    from -FeatureId if supplied, otherwise the story is branched from develop.

.PARAMETER PlanFile
    Optional. Workspace-relative path to the plan markdown file
    (e.g. "docs\plans\plan-2694-agentWorkflowPlanProgress.md").
    When supplied, the agent is instructed to update the story state in the plan.

.PARAMETER WorkspaceRoot
    Full path to the root of the workspace. Defaults to the current directory.

.PARAMETER OutputToClipboard
    When specified, copies the generated prompt to the clipboard in addition to stdout.

.PARAMETER OutputFile
    When specified, writes the generated prompt to this file path in addition to stdout.

.EXAMPLE
    .\docs\promptImplementStory_ThisProject.ps1 -StoryId 2695 -FeatureId 2694 -PlanFile "docs\plans\plan-2694-agentWorkflowPlanProgress.md" -OutputToClipboard

.EXAMPLE
    .\docs\promptImplementStory_ThisProject.ps1 -StoryId 2695 -FeatureBranch "feat/ab#2694-agentWorkflowPlanProgress" -OutputFile "tmp\story-prompt.md"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [int]$StoryId,

    [int]$FeatureId = 0,

    [string]$FeatureBranch = '',

    [string]$PlanFile = '',

    [string]$WorkspaceRoot = $PWD.Path,

    [switch]$OutputToClipboard,

    [string]$OutputFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = $PSScriptRoot

function hReadInclude {
    param([string]$RelativePath)
    $fullPath = Join-Path $ScriptDir $RelativePath
    if (-not (Test-Path $fullPath)) {
        throw "Include file not found: $fullPath"
    }
    return Get-Content $fullPath -Raw
}

# ── Load rule files ────────────────────────────────────────────────────────────
$implementRulesContent            = hReadInclude 'implementStoryRules.md'
$implementRulesThisProjectContent = hReadInclude 'implementStoryRules_ThisProject.md'
$projectStoryRulesContent         = hReadInclude 'createStoryRules_ThisProject.md'
$archRulesContent                 = hReadInclude 'architecturalRules_General.md'

# ── Derive branch info ─────────────────────────────────────────────────────────
if (-not $FeatureBranch -and $FeatureId -gt 0) {
    # Try to derive feature branch name from plan file
    if ($PlanFile) {
        $resolvedPlan = Join-Path $WorkspaceRoot $PlanFile
        if (Test-Path $resolvedPlan) {
            $planLines = Get-Content $resolvedPlan
            $featureRawTitle = $null
            for ($i = 0; $i -lt $planLines.Count; $i++) {
                if ($planLines[$i] -match '^#{1,3}\s+Feature:\s+(.+)$') {
                    $candidateTitle = $Matches[1].Trim()
                    for ($j = $i + 1; $j -le [Math]::Min($i + 5, $planLines.Count - 1); $j++) {
                        if ($planLines[$j] -match '\{WorkItemId\}\s*:\s*(\d+)') {
                            if ([int]$Matches[1] -eq $FeatureId) {
                                $featureRawTitle = $candidateTitle
                            }
                            break
                        }
                    }
                }
                if ($featureRawTitle) { break }
            }
            if ($featureRawTitle) {
                $words = $featureRawTitle -split '[^a-zA-Z0-9]+'
                $words = $words | Where-Object { $_ -ne '' }
                $camelTitle = ($words[0].Substring(0,1).ToLower() + $words[0].Substring(1)) +
                              (($words | Select-Object -Skip 1 | ForEach-Object {
                                  $_.Substring(0,1).ToUpper() + $_.Substring(1)
                              }) -join '')
                $FeatureBranch = "feat/ab#$($FeatureId)-$camelTitle"
            }
        }
    }
    if (-not $FeatureBranch) {
        $FeatureBranch = "feat/ab#$FeatureId-<featureTitle>"
    }
}

$baseBranch        = if ($FeatureBranch) { $FeatureBranch } else { 'develop' }
$storyBranchExample = "story/ab#$($StoryId)-<camelCaseStoryTitle>"

# ── Build plan file section ────────────────────────────────────────────────────
$planFileSection = if ($PlanFile) {
    $resolvedPlanFile = Join-Path $WorkspaceRoot $PlanFile
    @"

## Plan File

The story is tracked in the plan file:

    ``$resolvedPlanFile``

After completing the story, update its state to `Resolved` in the plan file.

---
"@
} else {
    ''
}

# ── Build feature branch section ───────────────────────────────────────────────
$featureBranchSection = if ($FeatureBranch) {
    @"

Ensure the feature branch exists before creating the story branch:

    $FeatureBranch

After the story is complete, merge the story branch back to the feature branch with ``--no-ff``:

    git checkout $FeatureBranch
    git merge $storyBranchExample --no-ff
"@
} else {
    ''
}

# ── Build prompt ───────────────────────────────────────────────────────────────
$prompt = @"
# Implement Story AB#$StoryId (AzureDoAutomatorPs / PowerShell)

> **Before proceeding, read the copilot instructions at ``.github/copilot-instructions.md``.**
> This file contains important project-specific rules and coding conventions that must be followed.

**CRITICAL:** Always fetch the latest story details and acceptance criteria from Azure DevOps.
Do NOT use embedded story content or memory — retrieve story AB#$StoryId from AzDo first and
verify the current state before implementing.

---

## Azure DevOps Configuration

- **Organization**: falco-it
- **Project**: GMD
- **PAT Token**: ``(`$env:GMD_AZDO_MACHINE_WORKITEMSRW | ssEncryptDecrypt.ps1 -Decrypt)``
- **Scripts location**: ``$WorkspaceRoot\src``
- **Story ID**: AB#$StoryId

---
$planFileSection
## Required Process

1. **Read story from AzDO** — fetch AB#$StoryId with all fields before doing anything else.
2. **Read and apply rules** — understand the implementation rules, TDD cycle, testing and
   documentation requirements from the sections below.
3. **Create story branch** — branch off ``$baseBranch``:

       ssNewFeatBranch.ps1 -Ticket $StoryId -Description "<story title>" -IsStory -NoFetch -BaseBranch "$baseBranch"

   This creates: ``$storyBranchExample``
$featureBranchSection
4. **Implement** — follow TDD cycle; check off Acceptance Criteria as you go.
5. **Test** — run all Pester tests, ensure they pass and coverage does not decrease.
6. **Verify** — validate each AC item and Acceptance Test scenario, mark them ✅ in AzDO.
7. **Document** — update README.md if applicable; add implementation summary comment to the story.
8. **Validate** — provide a checklist showing ✓/✗ for compliance with each rule below.

---

## Testing Requirements

This project uses **Pester** for integration-level PowerShell tests.

- **Test work item lifecycle:** Any Azure DevOps work items created during tests **must be deleted
  during test teardown**, even if the test fails.
  - Use ``AfterAll``/``AfterEach`` Pester blocks for cleanup.
  - Track all created work item IDs and remove them via the appropriate Remove script in ``src/``.
  - Tag every test-created work item with ``testWi`` to detect orphans.
- **Integration style:** Prefer integration-level Pester tests that invoke real scripts against the
  live AzDo API over mocked unit tests.
- **TDD style:** Write or update tests before or in parallel with implementation.
- **Test file location:** Group test files in folders by functionality. For story-specific tests,
  use the story ID and camelCase title in the file name under ``test/storyAcTests``.
- **No PSScriptAnalyzer warnings** in implemented scripts.
- **Logging:** Use ``ssLogIt.ps1`` for all output. Do not use ``Write-Host`` or ``Write-Error``.
- **External commands:** Use ``ssInvokeExpr.ps1`` when invoking shell expressions or commands.

---

## Story Implementation Rules

$implementRulesContent

$implementRulesThisProjectContent

---

## Project-Specific Story Rules (AzureDoAutomatorPs)

$projectStoryRulesContent

---

## Architectural Rules

$archRulesContent

---

*Generated by ``docs\promptImplementStory_ThisProject.ps1`` — $(Get-Date -Format 'yyyy-MM-dd HH:mm')*
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
