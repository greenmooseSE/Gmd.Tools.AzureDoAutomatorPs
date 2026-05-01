<#
.SYNOPSIS
    Generates a complete AI agent prompt for creating a feature plan for any PowerShell project.

.DESCRIPTION
    Produces a dynamically composed prompt for AI agents to create a markdown feature plan,
    merging the plan creation rules, story rules, and architectural rules from their source
    markdown files. Unlike promptCreatePlanFeatureMarkdownThisProject.ps1, this script contains
    no project-specific content and can be reused across PowerShell projects.

    The generated prompt references `.github/copilot-instructions.md` so the AI agent does not
    overlook it, but does not include its content in the merged output.

    The generated prompt is written to stdout and optionally to a file or the clipboard.

.PARAMETER EpicId
    The Azure DevOps work item ID of the parent epic (e.g. 1305).

.PARAMETER FeatureId
    Optional. The Azure DevOps work item ID of an existing feature when the new stories should be
    added within it. When omitted, a new feature is expected to be created.

.PARAMETER Organization
    The Azure DevOps organization name (e.g. falco-it).

.PARAMETER AzDoProject
    The Azure DevOps project name (e.g. GMD).

.PARAMETER PatTokenExpression
    The PowerShell expression used to retrieve the PAT token at runtime.
    Defaults to '($env:AZDO_PAT_TOKEN | ssEncryptDecrypt.ps1 -Decrypt)'.

.PARAMETER ScriptsLocation
    Relative path to the scripts folder within the workspace. Defaults to 'src/'.

.PARAMETER OutputToClipboard
    When specified, copies the generated prompt to the clipboard in addition to stdout.

.PARAMETER OutputFile
    When specified, writes the generated prompt to this file path in addition to stdout.

.EXAMPLE
    .\docs\promptCreatePlanFeatureMarkdownPs.ps1 -EpicId 1305 -Organization falco-it -AzDoProject GMD -OutputToClipboard

.EXAMPLE
    .\docs\promptCreatePlanFeatureMarkdownPs.ps1 -EpicId 1305 -FeatureId 1590 -Organization myOrg -AzDoProject MyProject -OutputFile "tmp\plan-prompt.md"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [int]$EpicId,

    [int]$FeatureId = 0,

    [Parameter(Mandatory)]
    [string]$Organization,

    [Parameter(Mandatory)]
    [string]$AzDoProject,

    [string]$PatTokenExpression = '($env:AZDO_PAT_TOKEN | ssEncryptDecrypt.ps1 -Decrypt)',

    [string]$ScriptsLocation = 'src/',

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
$template  = hReadInclude 'createPlanPromptTemplate.md'
$planRules = hReadInclude 'createMarkdownPlan.md'
$storyRules = hReadInclude 'createStoryRules_General.md'
$archRules = hReadInclude 'architecturalRules_General.md'

# ── Build AzDo config block ────────────────────────────────────────────────────
$configLines = @(
    "- **Organization**: $Organization",
    "- **Project**: $AzDoProject",
    "- **PAT Token**: ``$PatTokenExpression``",
    "- **Epic ID**: AB#$EpicId"
)
if ($FeatureId -gt 0) {
    $configLines += "- **Feature ID**: AB#$FeatureId (stories to be added within this existing feature)"
}
$configLines += "- **Scripts location**: ``$ScriptsLocation``"
$azdoConfig = $configLines -join "`n"

# ── Build derived values ───────────────────────────────────────────────────────
$featureContext = if ($FeatureId -gt 0) { " / AB#$FeatureId" } else { '' }
$contextTitle   = " — AB#$EpicId$featureContext"

# ── Apply substitutions ────────────────────────────────────────────────────────
$prompt = $template.Replace('{{CONTEXT_TITLE}}', $contextTitle)
$prompt = $prompt.Replace('{{AZDO_CONFIG}}', $azdoConfig)
$prompt = $prompt.Replace('{{PLAN_CREATION_RULES}}', $planRules.Trim())
$prompt = $prompt.Replace('{{STORY_RULES}}', $storyRules.Trim())
$prompt = $prompt.Replace('{{EXTRA_STORY_RULES_SECTION}}', '')
$prompt = $prompt.Replace('{{EXTRA_OUTPUT_REQUIREMENTS}}', '')
$prompt = $prompt.Replace('{{ARCH_RULES}}', $archRules.Trim())
$prompt = $prompt.Replace('{{GENERATED_BY}}', 'promptCreatePlanFeatureMarkdownPs.ps1')
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
