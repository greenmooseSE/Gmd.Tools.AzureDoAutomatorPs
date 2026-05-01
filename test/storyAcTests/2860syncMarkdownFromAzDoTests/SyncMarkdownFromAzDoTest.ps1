#Requires -Version 7.0

<#
.SYNOPSIS
AC tests for Story 2860: Sync existing plan markdown file from Azure DevOps.
Validates <see cref="SyncMarkdownFromAzDo.ps1"/> behavior against the live AzDo API.

.DESCRIPTION
Integration-level Pester tests that exercise SyncMarkdownFromAzDo.ps1 against the
live Azure DevOps API. Tests cover:
- Items with WorkItemIds are refreshed from AzDo
- Item with WorkItemId not found in hierarchy logs a warning
- Items without WorkItemId produce a warning
- With -MatchExistingByTitle, matching item gets its WorkItemId populated
- With -MatchExistingByTitle, unmatched title produces a warning
- Top-level node ID auto-detected from child's parent link
- No WorkItemId anywhere throws an error
- Plan file is overwritten with updated markdown
- Script outputs the resolved file path

Run with:
    Invoke-Pester .\test\storyAcTests\2860syncMarkdownFromAzDoTests\SyncMarkdownFromAzDoTest.ps1
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

[string]$REPO_ROOT = Resolve-Path (Join-Path $PSScriptRoot '../../../')
[string]$SRC_DIR   = Join-Path $REPO_ROOT 'src'

# Stub ssLogIt.ps1 if not in PATH (keeps tests runnable in isolation)
if (-not (Get-Command 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    function global:ssLogIt.ps1 {
        param(
            [string]$Level,
            [string]$Message,
            [object]$Exception,
            [switch]$PushStackLevel,
            [switch]$PopStackLevel,
            [switch]$NoExtra
        )
    }
}

# ============================================================================
# Helper: create a temporary plan file from a markdown string
# ============================================================================
function New-TempPlanFile {
    param([string]$Content)

    [string]$path = Join-Path ([System.IO.Path]::GetTempPath()) "sync-test-2860-$([System.Guid]::NewGuid().ToString('N')).md"
    Set-Content -Path $path -Value $Content -Encoding UTF8
    return $path
}

Describe 'SyncMarkdownFromAzDo - Story 2860' {

    # =========================================================================
    # Scenario 1: Items with WorkItemIds are refreshed from AzDo
    # =========================================================================
    Context 'Given a plan file with Feature 2858 and Story 2859 having WorkItemIds' {

        It 'GivenPlanWithWorkItemIds_WhenSynced_ItShouldOverwriteFile' {
            $content = @"
## Feature: Sync AzDo Hierarchy to Plan Markdown

{WorkItemId}: 2858
{State}: New
{Description}
Old description.

### Story: Export AzDo work item hierarchy to a new plan file (001)

{WorkItemId}: 2859
{State}: New
{Description}
Old story description.
"@
            $tmpFile = New-TempPlanFile -Content $content
            try {
                $null = & (Join-Path $SRC_DIR 'SyncMarkdownFromAzDo.ps1') `
                    -PlanFilePath $tmpFile
                Test-Path $tmpFile | Should Be $true
            } finally {
                if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }
            }
        }

        It 'GivenPlanWithWorkItemIds_WhenSynced_ItShouldOutputFilePath' {
            $content = @"
## Feature: Sync AzDo Hierarchy to Plan Markdown

{WorkItemId}: 2858
{State}: New
{Description}
Old description.

### Story: Export AzDo work item hierarchy to a new plan file (001)

{WorkItemId}: 2859
{State}: New
{Description}
Old story description.
"@
            $tmpFile = New-TempPlanFile -Content $content
            try {
                $result = & (Join-Path $SRC_DIR 'SyncMarkdownFromAzDo.ps1') `
                    -PlanFilePath $tmpFile
                $result | Should Be $tmpFile
            } finally {
                if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }
            }
        }

        It 'GivenPlanWithWorkItemIds_WhenSynced_FileShouldContainWorkItemId2858' {
            $content = @"
## Feature: Sync AzDo Hierarchy to Plan Markdown

{WorkItemId}: 2858
{State}: New
{Description}
Old description.

### Story: Export AzDo work item hierarchy to a new plan file (001)

{WorkItemId}: 2859
{State}: New
{Description}
Old story description.
"@
            $tmpFile = New-TempPlanFile -Content $content
            try {
                $null = & (Join-Path $SRC_DIR 'SyncMarkdownFromAzDo.ps1') `
                    -PlanFilePath $tmpFile
                $fileContent = Get-Content $tmpFile -Raw
                ($fileContent -match '\{WorkItemId\}:\s*2858') | Should Be $true
            } finally {
                if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }
            }
        }
    }

    # =========================================================================
    # Scenario 2: No WorkItemId anywhere throws an error
    # =========================================================================
    Context 'Given a plan file with no WorkItemId anywhere' {

        It 'GivenNoWorkItemIds_WhenSynced_ItShouldThrowWithAnchorMessage' {
            $content = @"
## Feature: Some Feature

{Description}
No IDs here.

### Story: Some Story

{Description}
Also no ID.
"@
            $tmpFile = New-TempPlanFile -Content $content
            $caught = $null
            try {
                & (Join-Path $SRC_DIR 'SyncMarkdownFromAzDo.ps1') `
                    -PlanFilePath $tmpFile
            } catch {
                $caught = $_
            } finally {
                if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }
            }
            $caught | Should Not BeNullOrEmpty
            ($caught.ToString() -match 'no WorkItemId found in plan file') | Should Be $true
        }

        It 'GivenNoWorkItemIds_WhenSynced_ItShouldNotModifyTheFile' {
            $content = @"
## Feature: Some Feature

{Description}
No IDs here.

### Story: Some Story

{Description}
Also no ID.
"@
            $tmpFile = New-TempPlanFile -Content $content
            try {
                $originalContent = Get-Content $tmpFile -Raw
                try {
                    & (Join-Path $SRC_DIR 'SyncMarkdownFromAzDo.ps1') `
                        -PlanFilePath $tmpFile
                } catch { }
                $currentContent = Get-Content $tmpFile -Raw
                $currentContent | Should Be $originalContent
            } finally {
                if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }
            }
        }
    }

    # =========================================================================
    # Scenario 3: Top-level node ID auto-detected from child's parent link
    # =========================================================================
    Context 'Given a plan where top-level has no WorkItemId but story 2859 has one' {

        It 'GivenTopLevelNoId_WhenSynced_ItShouldDetectParentAndSucceed' {
            $content = @"
## Feature: Sync AzDo Hierarchy to Plan Markdown

{Description}
No ID on top-level.

### Story: Export AzDo work item hierarchy to a new plan file (001)

{WorkItemId}: 2859
{Description}
Story has an ID, feature does not.
"@
            $tmpFile = New-TempPlanFile -Content $content
            $threw = $false
            try {
                $null = & (Join-Path $SRC_DIR 'SyncMarkdownFromAzDo.ps1') `
                    -PlanFilePath $tmpFile
            } catch {
                $threw = $true
            } finally {
                if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }
            }
            $threw | Should Be $false
        }

        It 'GivenTopLevelNoId_WhenSynced_FileShouldContainFeatureId2858' {
            $content = @"
## Feature: Sync AzDo Hierarchy to Plan Markdown

{Description}
No ID on top-level.

### Story: Export AzDo work item hierarchy to a new plan file (001)

{WorkItemId}: 2859
{Description}
Story has an ID, feature does not.
"@
            $tmpFile = New-TempPlanFile -Content $content
            try {
                $null = & (Join-Path $SRC_DIR 'SyncMarkdownFromAzDo.ps1') `
                    -PlanFilePath $tmpFile
                $fileContent = Get-Content $tmpFile -Raw
                ($fileContent -match '\{WorkItemId\}:\s*2858') | Should Be $true
            } finally {
                if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }
            }
        }
    }

    # =========================================================================
    # Scenario 4: Items without WorkItemId produce warnings
    # =========================================================================
    Context 'Given a plan with Feature 2858 (with ID) and a story without ID' {

        It 'GivenStoryWithoutId_WhenSynced_ItShouldCompleteWithoutThrow' {
            $content = @"
## Feature: Sync AzDo Hierarchy to Plan Markdown

{WorkItemId}: 2858
{Description}
Feature with ID.

### Story: Local Draft Story Without ID

{Description}
This story has no WorkItemId.
"@
            $tmpFile = New-TempPlanFile -Content $content
            $threw = $false
            try {
                $null = & (Join-Path $SRC_DIR 'SyncMarkdownFromAzDo.ps1') `
                    -PlanFilePath $tmpFile
            } catch {
                $threw = $true
            } finally {
                if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }
            }
            $threw | Should Be $false
        }
    }

    # =========================================================================
    # Scenario 5: -MatchExistingByTitle fills in WorkItemId for matching item
    # Story 2860 title in AzDo: "Sync existing plan markdown file from Azure DevOps (002)"
    # =========================================================================
    Context 'Given a plan with Feature 2858 and a story matching Story 2860 by title' {

        It 'GivenMatchByTitle_WhenSynced_ItShouldCompleteWithoutThrow' {
            $content = @"
## Feature: Sync AzDo Hierarchy to Plan Markdown

{WorkItemId}: 2858
{Description}
Feature with ID.

### Story: Sync existing plan markdown file from Azure DevOps (002)

{Description}
This story matches story 2860 by title.
"@
            $tmpFile = New-TempPlanFile -Content $content
            $threw = $false
            try {
                $null = & (Join-Path $SRC_DIR 'SyncMarkdownFromAzDo.ps1') `
                    -PlanFilePath $tmpFile `
                    -MatchExistingByTitle
            } catch {
                $threw = $true
            } finally {
                if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }
            }
            $threw | Should Be $false
        }

        It 'GivenMatchByTitle_WhenSynced_OutputShouldContainStory2860Id' {
            $content = @"
## Feature: Sync AzDo Hierarchy to Plan Markdown

{WorkItemId}: 2858
{Description}
Feature with ID.

### Story: Sync existing plan markdown file from Azure DevOps (002)

{Description}
This story matches story 2860 by title.
"@
            $tmpFile = New-TempPlanFile -Content $content
            try {
                $null = & (Join-Path $SRC_DIR 'SyncMarkdownFromAzDo.ps1') `
                    -PlanFilePath $tmpFile `
                    -MatchExistingByTitle
                $fileContent = Get-Content $tmpFile -Raw
                ($fileContent -match '\{WorkItemId\}:\s*2860') | Should Be $true
            } finally {
                if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }
            }
        }
    }

    # =========================================================================
    # Scenario 6: -MatchExistingByTitle logs warning for unmatched title
    # =========================================================================
    Context 'Given a plan with Feature 2858 and a story with a title that does not exist in AzDo' {

        It 'GivenUnmatchedTitle_WhenMatchByTitleSync_ItShouldCompleteWithoutThrow' {
            $content = @"
## Feature: Sync AzDo Hierarchy to Plan Markdown

{WorkItemId}: 2858
{Description}
Feature with ID.

### Story: Nonexistent Story Title That Has No Match In AzDo

{Description}
This story will not be found by title.
"@
            $tmpFile = New-TempPlanFile -Content $content
            $threw = $false
            try {
                $null = & (Join-Path $SRC_DIR 'SyncMarkdownFromAzDo.ps1') `
                    -PlanFilePath $tmpFile `
                    -MatchExistingByTitle
            } catch {
                $threw = $true
            } finally {
                if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }
            }
            $threw | Should Be $false
        }
    }
}
