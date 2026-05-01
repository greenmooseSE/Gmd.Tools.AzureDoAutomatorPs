#Requires -Version 7.0

<#
.SYNOPSIS
AC tests for Story 2724: {LastChangedDate} output in <see cref="ConvertHierarchyToMarkdown.ps1"/>.

.DESCRIPTION
Verifies that ConvertHierarchyToMarkdown.ps1 emits {LastChangedDate} after {WorkItemId} for
each work item when System.ChangedDate is present in the hierarchy data, and omits it when absent.

Run with: Invoke-Pester .\test\ConvertHierarchyToMarkdownTests\LastChangedDateOutputTest.ps1
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

[string]$REPO_ROOT  = Resolve-Path (Join-Path $PSScriptRoot '../../')
[string]$SRC_DIR    = Join-Path $REPO_ROOT 'src'

# Minimal stub for ssLogIt.ps1 if not on PATH
if (-not (Get-Command 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    function global:ssLogIt.ps1 {
        param([string]$Level, [string]$Message, [object]$Exception)
    }
}

# Helper: build minimal Story PSObject for ConvertHierarchyToMarkdown
function New-TestStory {
    param(
        [int]$Id = 1001,
        [string]$Title = 'Test Story',
        [string]$State = 'Active',
        [string]$ChangedDate = $null
    )
    $obj = [PSCustomObject]@{
        Id                 = $Id
        Title              = $Title
        State              = $State
        Description        = $null
        AcceptanceCriteria = $null
        AcceptanceTests    = $null
        StoryPoints        = $null
        Tags               = $null
        ExtraInformation   = $null
        Tasks              = @()
        Bugs               = @()
    }
    if ($null -ne $ChangedDate) {
        $obj | Add-Member -NotePropertyName 'ChangedDate' -NotePropertyValue $ChangedDate
    }
    return $obj
}

Describe 'Story 2724 - {LastChangedDate} output in ConvertHierarchyToMarkdown' {

    Context 'Scenario 1: Export hierarchy emits LastChangedDate' {

        It 'GivenStoryWithChangedDate_WhenConverting_ItShouldEmitLastChangedDateAfterWorkItemId' {
            # Scenario 1: item with System.ChangedDate → emits {LastChangedDate} after {WorkItemId}
            $story = New-TestStory -Id 100 -ChangedDate '2026-04-15T12:00:00Z'

            $markdown = & (Join-Path $SRC_DIR 'ConvertHierarchyToMarkdown.ps1') `
                -Hierarchy $story -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT

            $markdown | Should Match '\{WorkItemId\}: 100'
            $markdown | Should Match '\{LastChangedDate\}: 2026-04-15T12:00:00Z'

            # Verify ordering: LastChangedDate line follows WorkItemId line
            $lines = $markdown -split '\r?\n'
            $idIdx  = ($lines | Select-String '\{WorkItemId\}: 100').LineNumber - 1
            $dtIdx  = ($lines | Select-String '\{LastChangedDate\}: 2026-04-15T12:00:00Z').LineNumber - 1
            $dtIdx | Should BeGreaterThan $idIdx
            $dtIdx - $idIdx | Should Be 1
        }

        It 'GivenStoryWithoutChangedDate_WhenConverting_ItShouldNotEmitLastChangedDate' {
            # Scenario 4: item without System.ChangedDate → no {LastChangedDate} line
            $story = New-TestStory -Id 300

            $markdown = & (Join-Path $SRC_DIR 'ConvertHierarchyToMarkdown.ps1') `
                -Hierarchy $story -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT

            $markdown | Should Not Match '\{LastChangedDate\}'
        }
    }
}
