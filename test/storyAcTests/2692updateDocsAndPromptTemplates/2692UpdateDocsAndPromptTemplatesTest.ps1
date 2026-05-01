#Requires -Version 7.0

<#
.SYNOPSIS
AC tests for Story 2692: Update documentation and prompt templates.
Verifies that README.md and all files under docs/ contain no references
to "AC Scenarios" and use "Acceptance Tests" instead.

.DESCRIPTION
Tests: README.md, docs/*.md, and docs/*.ps1 contain no "AC Scenarios" text.
Also verifies "Acceptance Tests" is present in key documentation files.

Run with: Invoke-Pester .\test\storyAcTests\2692updateDocsAndPromptTemplates\2692UpdateDocsAndPromptTemplatesTest.ps1
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

[string]$REPO_ROOT = Resolve-Path (Join-Path $PSScriptRoot '../../../')

Describe 'Story 2692 - Update documentation and prompt templates' {

    Context 'README.md - no AC Scenarios references' {

        It 'GivenReadme_ItShouldNotContainAcScenariosText' {
            $content = Get-Content (Join-Path $REPO_ROOT 'README.md') -Raw
            ($content -match 'AC Scenarios') | Should Be $false
        }

        It 'GivenReadme_ItShouldContainAcceptanceTestsText' {
            $content = Get-Content (Join-Path $REPO_ROOT 'README.md') -Raw
            ($content -match 'Acceptance Tests') | Should Be $true
        }
    }

    Context 'docs/*.md - no AC Scenarios references' {

        $docFiles = Get-ChildItem (Join-Path $REPO_ROOT 'docs') -Filter '*.md' -File |
            Where-Object { $_.DirectoryName -notmatch '\\(plans|legacyPlans)' }

        foreach ($file in $docFiles) {
            $fileName = $file.Name
            It "GivenDocFile_${fileName}_ItShouldNotContainAcScenariosText" {
                $content = Get-Content $file.FullName -Raw
                ($content -match 'AC Scenarios') | Should Be $false
            }
        }
    }

    Context 'docs/*.ps1 - no AC Scenarios references' {

        $ps1Files = Get-ChildItem (Join-Path $REPO_ROOT 'docs') -Filter '*.ps1' -File

        foreach ($file in $ps1Files) {
            $fileName = $file.Name
            It "GivenDocPs1File_${fileName}_ItShouldNotContainAcScenariosText" {
                $content = Get-Content $file.FullName -Raw
                ($content -match 'AC Scenarios') | Should Be $false
            }
        }
    }

    Context 'Key docs files - contain Acceptance Tests references' {

        It 'GivenCreateStoryRulesGeneral_ItShouldContainAcceptanceTests' {
            $content = Get-Content (Join-Path $REPO_ROOT 'docs\createStoryRules_General.md') -Raw
            ($content -match 'Acceptance Tests') | Should Be $true
        }

        It 'GivenImplementStoryRules_ItShouldContainAcceptanceTests' {
            $content = Get-Content (Join-Path $REPO_ROOT 'docs\implementStoryRules.md') -Raw
            ($content -match 'Acceptance Tests') | Should Be $true
        }

        It 'GivenPromptImplementStoryThisProject_ItShouldContainAcceptanceTests' {
            $content = Get-Content (Join-Path $REPO_ROOT 'docs\promptImplementStory_ThisProject.md') -Raw
            ($content -match 'Acceptance Tests') | Should Be $true
        }

        It 'GivenPromptImplementStory_ItShouldContainAcceptanceTests' {
            $content = Get-Content (Join-Path $REPO_ROOT 'docs\promptImplementStory.md') -Raw
            ($content -match 'Acceptance Tests') | Should Be $true
        }
    }
}
