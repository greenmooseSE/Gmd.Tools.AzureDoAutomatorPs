#Requires -Version 7.0

<#
.SYNOPSIS
AC tests for Story 2690: Replace "Acceptance Tests" references in all markdown example files.
Verifies <see cref="example-hierarchy.md"/>, <see cref="example-hierarchy2.md"/>, and
<see cref="feature-markdown-export-import-plan.md"/> use "Acceptance Tests" instead of
"Acceptance Tests".

.DESCRIPTION
Tests that all root-level markdown example files use "Acceptance Tests" label/field,
that no "Acceptance Tests" occurrences remain in those files, and that the example files
still parse correctly via ConvertMarkdownToHierarchyJson.ps1.

Run with: Invoke-Pester .\test\storyAcTests\2690replaceAcScenariosInMarkdownExamples\2690ReplaceAcScenariosInMarkdownExamplesTest.ps1
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

[string]$REPO_ROOT = Resolve-Path (Join-Path $PSScriptRoot '../../../')
[string]$SRC_DIR   = Join-Path $REPO_ROOT 'src'

if (-not (Get-Command 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    function global:ssLogIt.ps1 {
        param([string]$Level, [string]$Message, [object]$Exception)
    }
}

Describe 'Story 2690 - Replace Acceptance Tests in markdown example files' {

    Context 'example-hierarchy.md' {

        It 'GivenExampleHierarchyMd_ItShouldNotContainAcScenariosLabel' {
            $content = Get-Content (Join-Path $REPO_ROOT 'example-hierarchy.md') -Raw
            ($content -match 'Acceptance Tests') | Should Be $false
        }

        It 'GivenExampleHierarchyMd_ItShouldContainAcceptanceTestsLabel' {
            $content = Get-Content (Join-Path $REPO_ROOT 'example-hierarchy.md') -Raw
            ($content -match '\{Acceptance Tests\}') | Should Be $true
        }
    }

    Context 'example-hierarchy2.md' {

        It 'GivenExampleHierarchy2Md_ItShouldNotContainAcScenariosLabel' {
            $content = Get-Content (Join-Path $REPO_ROOT 'example-hierarchy2.md') -Raw
            ($content -match 'Acceptance Tests') | Should Be $false
        }

        It 'GivenExampleHierarchy2Md_ItShouldContainAcceptanceTestsHeading' {
            $content = Get-Content (Join-Path $REPO_ROOT 'example-hierarchy2.md') -Raw
            ($content -match '#### Acceptance Tests') | Should Be $true
        }
    }

    Context 'feature-markdown-export-import-plan.md' {

        It 'GivenExportImportPlanMd_ItShouldNotContainAcScenariosLabel' {
            $content = Get-Content (Join-Path $REPO_ROOT 'feature-markdown-export-import-plan.md') -Raw
            ($content -match 'Acceptance Tests') | Should Be $false
        }

        It 'GivenExportImportPlanMd_ItShouldContainAcceptanceTestsHeading' {
            $content = Get-Content (Join-Path $REPO_ROOT 'feature-markdown-export-import-plan.md') -Raw
            ($content -match '#### Acceptance Tests') | Should Be $true
        }
    }

    Context 'Parser recognizes Acceptance Tests field from example-hierarchy.md' {

        It 'GivenExampleHierarchyMd_WhenParsed_ItShouldReturnWorkItemsWithoutErrors' {
            # Parsing should succeed without exceptions; field recognition is verified in story 2691
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownFile (Join-Path $REPO_ROOT 'example-hierarchy.md') `
                -ErrorAction Stop

            $result | Should Not BeNullOrEmpty
            $result.workItems | Should Not BeNullOrEmpty
        }
    }
}
