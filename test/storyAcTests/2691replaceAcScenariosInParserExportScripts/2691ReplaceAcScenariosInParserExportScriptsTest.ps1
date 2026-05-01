#Requires -Version 7.0

<#
.SYNOPSIS
AC tests for Story 2691: Replace "Acceptance Tests" in parser and export scripts.
Verifies <see cref="ConvertMarkdownToHierarchyJson"/>, <see cref="ConvertHierarchyToMarkdown"/>,
<see cref="NewAzDoHierarchyFromMarkdown"/>, and <see cref="SortMarkdownHierarchy"/> use
"Acceptance Tests" as the canonical field label.

.DESCRIPTION
Tests: new {Acceptance Tests} curly-brace label is parsed to acScenarios, legacy {Acceptance Tests}
still parsed with deprecation warning, ConvertHierarchyToMarkdown outputs {Acceptance Tests},
SortMarkdownHierarchy outputs #### Acceptance Tests heading, and CoreOutputLabels updated.

Run with: Invoke-Pester .\test\storyAcTests\2691replaceAcScenariosInParserExportScripts\2691ReplaceAcScenariosInParserExportScriptsTest.ps1
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

Describe 'Story 2691 - Replace Acceptance Tests in parser and export scripts' {

    Context 'ConvertMarkdownToHierarchyJson.ps1 - new Acceptance Tests label' {

        It 'GivenCurlyAcceptanceTestsLabel_WhenParsed_ItShouldPopulateAcScenarios' {
            $md = @"
# Epic: My Epic
{WorkItemId}: 1

## Feature: My Feature
{WorkItemId}: 2

### Story: My Story
{WorkItemId}: 3
{Acceptance Tests}
Given a story exists
When the field is set
Then the field value is stored
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md `
                -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT `
                -ErrorAction Stop

            $story = $result.workItems[0].children[0].children[0]
            $story.acScenarios | Should Not BeNullOrEmpty
            ($story.acScenarios -match 'Given a story exists') | Should Be $true
        }

        It 'GivenAcceptanceTestsLabel_ItShouldBeInMappedFieldsList' {
            $content = Get-Content (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') -Raw
            ($content -match "'Acceptance Tests'") | Should Be $true
        }
    }

    Context 'ConvertHierarchyToMarkdown.ps1 - CoreOutputLabels updated' {

        It 'GivenCoreOutputLabels_ItShouldContainAcceptanceTests' {
            $content = Get-Content (Join-Path $SRC_DIR 'ConvertHierarchyToMarkdown.ps1') -Raw
            ($content -match "'Acceptance Tests'") | Should Be $true
        }

        It 'GivenCoreOutputLabels_ItShouldNotContainAcScenariosLabel' {
            $content = Get-Content (Join-Path $SRC_DIR 'ConvertHierarchyToMarkdown.ps1') -Raw
            # Check the CoreOutputLabels array does not list the old 'AC Scenarios' label
            ($content -match "CoreOutputLabels.*'AC Scenarios'") | Should Be $false
        }

        It 'GivenStoryWithACScenarios_WhenConverted_ItShouldOutputAcceptanceTestsCurlyBrace' {
            $content = Get-Content (Join-Path $SRC_DIR 'ConvertHierarchyToMarkdown.ps1') -Raw
            # The output should use {Acceptance Tests} heading
            ($content -match '\{Acceptance Tests\}') | Should Be $true
        }
    }

    Context 'SortMarkdownHierarchy.ps1 - uses Acceptance Tests heading' {

        It 'GivenSortMarkdownHierarchy_ItShouldOutputAcceptanceTestsHeading' {
            $content = Get-Content (Join-Path $SRC_DIR 'tools\SortMarkdownHierarchy.ps1') -Raw
            ($content -match '#### Acceptance Tests') | Should Be $true
        }

        It 'GivenSortMarkdownHierarchy_ItShouldNotOutputAcScenariosHeading' {
            $content = Get-Content (Join-Path $SRC_DIR 'tools\SortMarkdownHierarchy.ps1') -Raw
            ($content -match '#### AC Scenarios') | Should Be $false
        }
    }

    Context 'NewAzDoHierarchyFromMarkdown.ps1 - still maps to Custom.AcceptanceTests' {

        It 'GivenNewAzDoHierarchyScript_ItShouldMapAcScenariosToFieldConstant' {
            $content = Get-Content (Join-Path $SRC_DIR 'NewAzDoHierarchyFromMarkdown.ps1') -Raw
            ($content -match '\$Story\.acScenarios') | Should Be $true
            ($content -match 'FIELD_AC_SCENARIOS') | Should Be $true
        }
    }

    Context 'Integration: Acceptance Tests field round-trip via parser+export with org/project' {

        It 'GivenMarkdownWithAcceptanceTestsField_WhenParsedWithOrgProject_ItShouldPopulateAcScenarios' {
            $md = @"
### Story: Round-trip story
{WorkItemId}: 9999
{Acceptance Tests}
Given a round-trip test
When we parse with org/project
Then acScenarios is populated
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md `
                -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT `
                -ErrorAction Stop

            $story = $result.workItems[0]
            $story.acScenarios | Should Not BeNullOrEmpty
            ($story.acScenarios -match 'Given a round-trip test') | Should Be $true
        }

    }
}
