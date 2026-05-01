#Requires -Version 7.0

<#
.SYNOPSIS
AC tests for Story 2693: Replace "AC Scenarios" in plan markdown files.
Verifies all plan files under docs/plans/ and docs/legacyPlans/ use
"Acceptance Tests" instead of "AC Scenarios".

.DESCRIPTION
Tests: No plan file contains "AC Scenarios", plans still parse correctly
via ConvertMarkdownToHierarchyJson.ps1.

Run with: Invoke-Pester .\test\storyAcTests\2693replaceAcScenariosInPlanFiles\2693ReplaceAcScenariosInPlanFilesTest.ps1
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

[string]$REPO_ROOT = Resolve-Path (Join-Path $PSScriptRoot '../../../')
[string]$SRC_DIR   = Join-Path $REPO_ROOT 'src'

Describe 'Story 2693 - Replace AC Scenarios in plan markdown files' {

    Context 'docs/plans/*.md - no AC Scenarios references' {

        # Exclude plan-2688 which is the meta-plan describing the rename itself
        $planFiles = Get-ChildItem (Join-Path $REPO_ROOT 'docs\plans') -Filter '*.md' -File |
            Where-Object { $_.Name -ne 'plan-2688-renameAcScenariosToAcceptanceTests.md' }

        foreach ($file in $planFiles) {
            $fileName = $file.Name
            It "GivenPlanFile_${fileName}_ItShouldNotContainAcScenariosText" {
                $content = Get-Content $file.FullName -Raw
                ($content -match 'AC Scenarios') | Should Be $false
            }
        }
    }

    Context 'docs/legacyPlans/*.md - no AC Scenarios references' {

        $legacyDir = Join-Path $REPO_ROOT 'docs\legacyPlans'
        if (Test-Path $legacyDir) {
            $legacyFiles = Get-ChildItem $legacyDir -Filter '*.md' -File
            foreach ($file in $legacyFiles) {
                $fileName = $file.Name
                It "GivenLegacyPlanFile_${fileName}_ItShouldNotContainAcScenariosText" {
                    $content = Get-Content $file.FullName -Raw
                    ($content -match 'AC Scenarios') | Should Be $false
                }
            }
        } else {
            It 'GivenNoLegacyPlansDirectory_ItShouldPass' {
                $true | Should Be $true
            }
        }
    }

    Context 'Plans parse correctly via ConvertMarkdownToHierarchyJson.ps1' {

        It 'GivenPlan2688_WhenParsed_ItShouldNotThrow' {
            $planFile = Join-Path $REPO_ROOT 'docs\plans\plan-2688-renameAcScenariosToAcceptanceTests.md'
            $md = Get-Content $planFile -Raw
            { & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') -MarkdownContent $md -ErrorAction Stop } |
                Should Not Throw
        }
    }
}
