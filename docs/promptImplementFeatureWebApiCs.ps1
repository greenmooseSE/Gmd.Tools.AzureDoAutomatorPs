<#
.SYNOPSIS
    Generates a complete AI agent prompt for implementing a CSharp WebApi feature with multiple stories.

.DESCRIPTION
    Produces a dynamically composed prompt for AI agents to implement all stories in a feature plan,
    embedding multi-story branching instructions, story implementation rules, and architectural rules
    from their source markdown files.

    The generated prompt is written to stdout and optionally to a file or the clipboard.

.PARAMETER FeatureId
    The Azure DevOps work item ID of the feature (e.g. 2577).

.PARAMETER FeatureTitle
    A short camelCase description of the feature used to construct the feature branch name
    (e.g. "aiChatApiMvp"). The feature branch will be named: feat/ab#<FeatureId>-<FeatureTitle>.

.PARAMETER PlanFile
    Relative path from WorkspaceRoot to the plan markdown file that lists all stories
    (e.g. "docs\plans\plan-01-feature-01-firstMvp.md").

.PARAMETER TemplateProjectPath
    Full path to a CSharp WebApi project used as the structural reference/template.
    Defaults to C:\Dev\own\GDrive\Privat\Dev\gh\Gmd.AuthService.WebApi-1.

.PARAMETER WorkspaceRoot
    Full path to the root of the target project workspace. Defaults to the current directory.

.PARAMETER OutputToClipboard
    When specified, copies the generated prompt to the clipboard in addition to stdout.

.PARAMETER OutputFile
    When specified, writes the generated prompt to this file path in addition to stdout.

.EXAMPLE
    .\docs\promptImplementFeatureWebApiCs.ps1 -FeatureId 2577 -FeatureTitle "aiChatApiMvp" -PlanFile "docs\plans\plan-01-feature-01-firstMvp.md" -OutputToClipboard

.EXAMPLE
    .\docs\promptImplementFeatureWebApiCs.ps1 -FeatureId 2577 -FeatureTitle "aiChatApiMvp" -PlanFile "docs\plans\plan-01-feature-01-firstMvp.md" -TemplateProjectPath "C:\Dev\own\GDrive\Privat\Dev\gh\Gmd.AuthService.WebApi-1" -OutputFile "tmp\generated-prompt.md"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [int]$FeatureId,

    [Parameter(Mandatory)]
    [string]$FeatureTitle,

    [Parameter(Mandatory)]
    [string]$PlanFile,

    [string]$TemplateProjectPath = 'C:\Dev\own\GDrive\Privat\Dev\gh\Gmd.AuthService.WebApi-1',

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

# ── Load general include templates ────────────────────────────────────────────
$multiStoryContent    = hReadInclude 'multiStoryInstructions.md'
$implementRulesContent = hReadInclude 'implementStoryRules.md'
$archRulesContent     = (hReadInclude 'architecturalRules_General.md') + "`n`n" + (hReadInclude 'architecturalRules_WebApi.md')

# ── Derived values ─────────────────────────────────────────────────────────────
$featureBranch        = "feat/ab#$($FeatureId)-$FeatureTitle"
$templateMigrScript   = Join-Path $TemplateProjectPath 'src\GmdAuthServiceWebApi\efAddMigration.ps1'
$resolvedPlanFile     = Join-Path $WorkspaceRoot $PlanFile

# ── Build prompt ───────────────────────────────────────────────────────────────
$prompt = @"
# Implement Feature AB#FEATURE_ID — All Stories (CSharp WebApi)

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
| TEMPLATE_PROJECT  | $TemplateProjectPath                       |

---

## Plan File

Implement stories in:

    WORKSPACE_ROOT\PLAN_FILE

i.e. ``$resolvedPlanFile``

Mark each story as done in the plan file as you complete it.

---

## Project Structure Reference

Use TEMPLATE_PROJECT (``$TemplateProjectPath``) as the structural reference for this WebApi project.
The target project should already have a similar structure (multiple DbContexts, SQLite in-memory
for tests, etc.) — you do not need to re-create it from scratch based on AuthService; just follow
the same conventions when adding new code.

---

## Branching Strategy

### Feature branch
The feature branch for AB#FEATURE_ID must already exist before starting:

    FEATURE_BRANCH  →  $featureBranch

If it does not exist yet, create it from ``develop``:

    ssNewFeatBranch.ps1 -Ticket FEATURE_ID -StoryDesc "FEATURE_TITLE" -NoFetch -BaseBranch develop

### Story branches
For each story, create a branch off the **feature branch** (not ``develop``):

    story/ab#<StoryId>-<camelCaseShortStoryTitle>

Example:

    ssNewFeatBranch.ps1 -Ticket <StoryId> -StoryDesc "<story title>" -NoFetch -BaseBranch "ab#FEATURE_ID-FEATURE_TITLE"

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

- **Run tests with dev.runsettings** to avoid hitting SQL Server:

      dotnet test -s dev.runsettings

- **Do NOT skip DbContext registrations.** The project uses multiple DbContexts. Keep all of them
  registered; dev.runsettings ensures SQL-Server-dependent tests are excluded via test categories/filters.
- **Use the coverage helper** to verify coverage after each story:

      Get-Command DotnetRunTestsAndParseCoverage.ps1 | Select-Object -ExpandProperty Source
      # then invoke it, e.g.:
      DotnetRunTestsAndParseCoverage.ps1

  Ensure all added/modified lines have test coverage.
- **TDD style:** write or update tests before or in parallel with implementation. Every story must
  have automated tests covering its acceptance criteria and BDD scenarios.
- Ensure ``dotnet build -c Release`` passes without compiler warnings before merging a story branch.

---

## Database Migrations

When a story requires schema changes, add migrations for **all DbContexts** in the project.
Follow the same pattern as in TEMPLATE_PROJECT:

    # From TEMPLATE_PROJECT:
    $templateMigrScript -Name <MigrationName>

Apply the same script/approach in the target project for each DbContext that has schema changes.

---

## General Guidelines

- **Chunked work:** Break implementation into small batches — both file edits and AI responses —
  to avoid hitting response-length limits.
- **Compact conversation** before starting each new story when possible.
- **No deployment:** skip Docker, cloud, or CI/CD steps entirely.
- **Fail fast:** throw exceptions rather than implementing silent fallbacks.
- **Update the plan file** to mark each story complete as you go.

---

## Multi-Story Process

$multiStoryContent

---

## Story Implementation Rules

$implementRulesContent

---

## Architectural Rules

$archRulesContent

---

*Generated by ``docs\promptImplementFeatureWebApiCs.ps1`` — $(Get-Date -Format 'yyyy-MM-dd HH:mm')*
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
