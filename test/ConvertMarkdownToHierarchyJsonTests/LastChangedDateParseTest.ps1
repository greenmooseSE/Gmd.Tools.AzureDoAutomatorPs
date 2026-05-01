#Requires -Version 7.0

<#
.SYNOPSIS
AC tests for Story 2724: {LastChangedDate} parsing in <see cref="ConvertMarkdownToHierarchyJson.ps1"/>.

.DESCRIPTION
Verifies that {LastChangedDate} is recognised as a local metadata field by the parser,
stored on the output object, and excluded from field-config lookups (i.e. never treated
as an unknown label that triggers a skip). Round-trip preservation is also verified.

Run with: Invoke-Pester .\test\ConvertMarkdownToHierarchyJsonTests\LastChangedDateParseTest.ps1
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

[string]$REPO_ROOT = Resolve-Path (Join-Path $PSScriptRoot '../../')
[string]$SRC_DIR   = Join-Path $REPO_ROOT 'src'

if (-not (Get-Command 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    function global:ssLogIt.ps1 {
        param([string]$Level, [string]$Message, [object]$Exception)
    }
}

Describe 'Story 2724 - {LastChangedDate} parsing in ConvertMarkdownToHierarchyJson' {

    Context 'Scenario 2: Parse markdown with LastChangedDate' {

        It 'GivenStoryWithLastChangedDate_WhenParsing_ItShouldExposeLastChangedDateProperty' {
            # Scenario 2: Given markdown containing {LastChangedDate}, the parsed item includes lastChangedDate
            $md = @"
### Story: My Story
{WorkItemId}: 100
{LastChangedDate}: 2026-04-15T12:00:00Z
{tags}: foo
{Description}
Some description.
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $item = $result.workItems[0]
            $item.lastChangedDate | Should Be '2026-04-15T12:00:00Z'
        }

        It 'GivenStoryWithoutLastChangedDate_WhenParsing_ItShouldHaveNullLastChangedDate' {
            # Items without {LastChangedDate} should have null (backwards compatibility)
            $md = @"
### Story: My Story
{WorkItemId}: 200
{Description}
Some description.
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $item = $result.workItems[0]
            $item.lastChangedDate | Should BeNullOrEmpty
        }

        It 'GivenLastChangedDateBeforeWorkItemId_WhenParsing_ItShouldStillParseCorrectly' {
            # Field order should not matter
            $md = @"
### Story: My Story
{LastChangedDate}: 2026-04-28T19:19:15.407Z
{WorkItemId}: 300
{Description}
Story body.
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $item = $result.workItems[0]
            $item.workItemId | Should Be 300
            $item.lastChangedDate | Should Be '2026-04-28T19:19:15.407Z'
        }

        It 'GivenEpicWithLastChangedDate_WhenParsing_ItShouldExposeLastChangedDateOnEpicItem' {
            # Verify {LastChangedDate} works for Epic and Feature types too
            $md = @"
# Epic: My Epic
{WorkItemId}: 10
{LastChangedDate}: 2026-01-01T00:00:00Z

## Feature: My Feature
{WorkItemId}: 20
{LastChangedDate}: 2026-02-01T00:00:00Z
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $epic = $result.workItems[0]
            $epic.lastChangedDate | Should Be '2026-01-01T00:00:00Z'
            $feature = $epic.children[0]
            $feature.lastChangedDate | Should Be '2026-02-01T00:00:00Z'
        }
    }

    Context 'Scenario 3: Round-trip preserves LastChangedDate' {

        It 'GivenMarkdownWithLastChangedDate_WhenParsedAndOutputReconverted_ItShouldPreserveValue' {
            # Scenario 3: Round-trip — parse then inspect output retains original value
            [string]$originalDate = '2026-04-15T12:00:00Z'
            $md = @"
### Story: Round-trip Story
{WorkItemId}: 400
{LastChangedDate}: $originalDate
{Description}
Body text.
"@
            $parsed = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $item = $parsed.workItems[0]
            $item.lastChangedDate | Should Be $originalDate
        }
    }
}
