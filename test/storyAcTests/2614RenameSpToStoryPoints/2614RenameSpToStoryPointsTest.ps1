#Requires -Version 7.0

<#
.SYNOPSIS
AC tests for Story 2614: Rename SP markdown label to Story Points.
Verifies <see cref="ConvertMarkdownToHierarchyJson"/> and
<see cref="ConvertHierarchyToMarkdown"/> use "Story Points" label.

.DESCRIPTION
Tests parsing of new "Story Points" label, generation of "Story Points" in output,
round-trip fidelity, and backward compatibility with legacy "SP" label.

Run with: Invoke-Pester .\test\storyAcTests\2614RenameSpToStoryPoints\2614RenameSpToStoryPointsTest.ps1
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

[string]$REPO_ROOT = Resolve-Path (Join-Path $PSScriptRoot '../../../')
[string]$SRC_DIR = Join-Path $REPO_ROOT 'src'

if (-not (Get-Command 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    function global:ssLogIt.ps1 {
        param([string]$Level, [string]$Message, [object]$Exception)
    }
}

Describe 'Story 2614 - Rename SP markdown label to Story Points' {

    Context 'ConvertMarkdownToHierarchyJson.ps1 parses Story Points label' {

        It 'GivenStoryPointsLabel_WhenParsing_ItShouldProduceStoryPointsValue' {
            $md = @"
### Story: Test Story
**Story Points**: 3
**Description**
Some description
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') -MarkdownContent $md
            $result.workItems[0].storyPoints | Should Be 3
        }

        It 'GivenLegacySpLabel_WhenParsing_ItShouldStillProduceStoryPointsValue' {
            $md = @"
### Story: Legacy Story
**SP**: 5
**Description**
Some description
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') -MarkdownContent $md
            $result.workItems[0].storyPoints | Should Be 5
        }

        It 'GivenStoryPointsLabelOnFeature_WhenParsing_ItShouldProduceStoryPointsValue' {
            $md = @"
## Feature: My Feature
**Story Points**: 8
**Description**
Feature description
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') -MarkdownContent $md
            $result.workItems[0].storyPoints | Should Be 8
        }
    }

    Context 'ConvertHierarchyToMarkdown.ps1 outputs Story Points label' {

        It 'GivenWorkItemWithStoryPoints_WhenGenerating_ItShouldOutputStoryPointsLabel' {
            # Build a Story hierarchy object matching ConvertHierarchyToMarkdown expectations
            $hierarchy = [PSCustomObject]@{
                Id                 = 999
                Title              = 'My Story'
                State              = 'New'
                Tags               = $null
                StoryPoints        = 5.0
                Description        = 'A story'
                AcceptanceCriteria = $null
                AcceptanceTests        = $null
                ExtraInformation   = $null
                Children           = @()
            }

            $result = & (Join-Path $SRC_DIR 'ConvertHierarchyToMarkdown.ps1') `
                -Hierarchy $hierarchy -Organization 'falco-it' -Project 'GMD' 2>&1
            $output = $result | Where-Object { $_ -is [string] } | Out-String
            $output -match '\*\*Story Points\*\*:' | Should Be $true
            $output -match '\*\*SP\*\*:'           | Should Be $false
        }
    }

    Context 'Round-trip preserves Story Points' {

        It 'GivenMarkdownWithStoryPoints_WhenRoundTripped_ItShouldPreserveValue' {
            $md = @"
### Story: Round Trip Story
**Story Points**: 8
**Description**
Story description
"@
            $parsed = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') -MarkdownContent $md
            $parsed.workItems[0].storyPoints | Should Be 8
        }
    }

    Context 'No SP label in generated output' {

        It 'GenerateAzDoMarkdownHierarchyTemplate output does not contain **SP**:' {
            $templateOutput = & (Join-Path $SRC_DIR 'GenerateAzDoMarkdownHierarchyTemplate.ps1') 2>&1 | Out-String
            $templateOutput -match '\*\*SP\*\*:' | Should Be $false
        }

        It 'GenerateAzDoMarkdownHierarchyTemplate output contains **Story Points**:' {
            $templateOutput = & (Join-Path $SRC_DIR 'GenerateAzDoMarkdownHierarchyTemplate.ps1') 2>&1 | Out-String
            $templateOutput -match '\*\*Story Points\*\*:' | Should Be $true
        }
    }
}
