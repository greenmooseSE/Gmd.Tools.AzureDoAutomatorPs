<#
.SYNOPSIS
    Generates a prompt for adding Bug work items to an existing feature plan.

.DESCRIPTION
    Produces a dynamically composed prompt for AI agents to create one or more `### Bug:`
    items within an existing (or new) feature plan file, merging the plan creation rules,
    Bug-specific rules, and architectural rules from their source markdown files.

    The generated prompt references `.github/copilot-instructions.md` so the AI agent does
    not overlook it, but does not include its content in the merged output.

    The generated prompt is written to stdout and optionally to a file or the clipboard.

.PARAMETER EpicId
    The Azure DevOps work item ID of the parent epic (e.g. 1305).

.PARAMETER FeatureId
    The Azure DevOps work item ID of the parent feature under which the bug(s)
    should be added (e.g. 1590).

.PARAMETER OutputToClipboard
    When specified, copies the generated prompt to the clipboard in addition to stdout.

.PARAMETER OutputFile
    When specified, writes the generated prompt to this file path in addition to stdout.

.EXAMPLE
    .\docs\promptCreatePlanBugMarkdown_General.ps1 -EpicId 1305 -FeatureId 1590 -OutputToClipboard

.EXAMPLE
    .\docs\promptCreatePlanBugMarkdown_General.ps1 -EpicId 1305 -FeatureId 1590 -OutputFile "tmp\bug-prompt.md"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [int]$EpicId,

    [Parameter(Mandatory)]
    [int]$FeatureId,

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

# ── Load template and rule files ───────────────────────────────────────────────
$template  = hReadInclude 'createPlanBugPromptTemplate.md'
$planRules = hReadInclude 'createMarkdownPlan.md'
$archRules = hReadInclude 'architecturalRules_General.md'

# ── Build AzDo config block ────────────────────────────────────────────────────
$azdoConfig = @(
    '- **Organization**: falco-it',
    '- **Project**: GMD',
    "- **PAT Token**: ``(`$env:GMD_AZDO_MACHINE_WORKITEMSRW | ssEncryptDecrypt.ps1 -Decrypt)``",
    "- **Epic ID**: AB#$EpicId",
    "- **Feature ID**: AB#$FeatureId (bug to be added within this existing feature)",
    "- **Scripts location**: ``src/``"
) -join "`n"

# ── Build derived values ───────────────────────────────────────────────────────
$contextTitle = " — AB#$EpicId / AB#$FeatureId"

# ── Apply substitutions ────────────────────────────────────────────────────────
$prompt = $template.Replace('{{CONTEXT_TITLE}}', $contextTitle)
$prompt = $prompt.Replace('{{AZDO_CONFIG}}', $azdoConfig)
$prompt = $prompt.Replace('{{PLAN_CREATION_RULES}}', $planRules.Trim())
$prompt = $prompt.Replace('{{EXTRA_BUG_RULES_SECTION}}', '')
$prompt = $prompt.Replace('{{ARCH_RULES}}', $archRules.Trim())
$prompt = $prompt.Replace('{{GENERATED_BY}}', 'promptCreatePlanBugMarkdown_General.ps1')
$prompt = $prompt.Replace('{{TIMESTAMP}}', (Get-Date -Format 'yyyy-MM-dd HH:mm'))

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
