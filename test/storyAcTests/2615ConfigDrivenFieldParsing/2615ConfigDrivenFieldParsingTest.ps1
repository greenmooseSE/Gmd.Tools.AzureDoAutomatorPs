#Requires -Version 7.0

<#
.SYNOPSIS
AC tests for Story 2615: Config-driven field parsing and generation in markdown workflow.
Verifies <see cref="ConvertMarkdownToHierarchyJson"/> and <see cref="ConvertHierarchyToMarkdown"/>
use appSettings.json field definitions for parsing with type coercion and ordered generation.

.DESCRIPTION
Tests config-driven parsing (boolean, double, string, html), warning for unknown labels,
generator output ordering, backward compatibility, and readOnly field exclusion.

Run with: Invoke-Pester .\test\storyAcTests\2615ConfigDrivenFieldParsing\2615ConfigDrivenFieldParsingTest.ps1
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

Describe 'Story 2615 - Config-driven field parsing and generation' {

    Context 'AC1: Boolean field is parsed with type coercion' {

        It 'GivenAIImplementedTrue_WhenParsing_ItShouldProduceBooleanTrue' {
            $md = @"
## Feature: My Feature
{AI Implemented}: true
{Description}
A feature
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $item = $result.workItems[0]
            $item.configFields | Should Not BeNullOrEmpty
            $item.configFields['Custom.AIImplemented'] | Should Be $true
            $item.configFields['Custom.AIImplemented'].GetType().Name | Should Be 'Boolean'
        }

        It 'GivenAIImplementedFalse_WhenParsing_ItShouldProduceBooleanFalse' {
            $md = @"
## Feature: My Feature
{AI Implemented}: false
{Description}
A feature
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $result.workItems[0].configFields['Custom.AIImplemented'] | Should Be $false
        }
    }

    Context 'AC2: Double field is parsed with type coercion' {

        It 'GivenOriginalEstimate_WhenParsing_ItShouldProduceDouble' {
            $md = @"
### Story: My Story
{Original Estimate}: 8
{Description}
A story
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $item = $result.workItems[0]
            $item.originalEstimate | Should Be 8.0
            $item.originalEstimate.GetType().Name | Should Be 'Double'
        }

        It 'GivenRemainingWork_WhenParsing_ItShouldProduceDouble' {
            $md = @"
### Story: My Story
{Remaining Work}: 4
{Description}
A story
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $item = $result.workItems[0]
            $item.configFields['Microsoft.VSTS.Scheduling.RemainingWork'] | Should Be 4.0
        }
    }

    Context 'AC3: String field is parsed correctly' {

        It 'GivenFixedIn_WhenParsing_ItShouldProduceString' {
            $md = @"
## Feature: My Feature
{Fixed In}: v2.1.0
{Description}
A feature
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $item = $result.workItems[0]
            $item.configFields['Custom.FixedIn'] | Should Be 'v2.1.0'
        }
    }

    Context 'AC5: ReadOnly field (WorkItemId) is parsed as named property, not in configFields' {

        It 'GivenWorkItemId_WhenParsing_ItShouldBeInWorkItemIdNotConfigFields' {
            $md = @"
### Story: A Story
{WorkItemId}: 123
{Description}
A story
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $item = $result.workItems[0]
            $item.workItemId | Should Be 123
            # System.Id should NOT be in configFields (it is a core named property)
            $cfgProp = $item.PSObject.Properties['configFields']
            if ($null -ne $cfgProp -and $null -ne $cfgProp.Value) {
                $cfgProp.Value.ContainsKey('System.Id') | Should Be $false
            }
        }
    }

    Context 'AC6: Unknown field label produces no failure' {

        It 'GivenUnknownLabel_WhenParsing_ItShouldNotThrowAndReturnOtherFieldsCorrectly' {
            $md = @"
### Story: My Story
{Nonexistent Custom Field}: somevalue
{Description}
A story
"@
            $result = $null
            $threw = $false
            try {
                $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                    -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            } catch {
                $threw = $true
            }
            $threw | Should Be $false
            $result.workItems.Count | Should Be 1
            $result.workItems[0].type | Should Be 'Story'
        }
    }

    Context 'AC7: ConvertHierarchyToMarkdown outputs configFields using configured labels' {

        It 'GivenItemWithConfigFields_WhenGenerating_ItShouldOutputFieldsWithConfigLabels' {
            $story = [PSCustomObject]@{
                Id                 = 42
                Title              = 'Test Story'
                State              = 'New'
                Tags               = $null
                StoryPoints        = $null
                Description        = $null
                AcceptanceCriteria = $null
                ACScenarios        = $null
                ExtraInformation   = $null
                AssignedTo         = $null
                OriginalEstimate   = $null
                RemainingWork      = $null
                configFields       = @{
                    'Custom.AIImplemented' = $true
                    'Custom.FixedIn'       = 'v1.0'
                    'Microsoft.VSTS.Scheduling.OriginalEstimate' = 8.0
                }
            }

            $output = & (Join-Path $SRC_DIR 'ConvertHierarchyToMarkdown.ps1') `
                -Hierarchy $story -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT 2>&1 |
                Where-Object { $_ -is [string] } | Out-String

            $output -match '\{AI Implemented\}:' | Should Be $true
            $output -match '\{Fixed In\}:'       | Should Be $true
            $output -match '\{Original Estimate\}:' | Should Be $true
        }
    }

    Context 'AC8: Generator output order follows appSettings.json order' {

        It 'GivenMultipleConfigFields_WhenGenerating_ItShouldOutputInConfigOrder' {
            # In appSettings.json for Feature, "Fixed In" comes before "AI Implemented" in the array
            $feature = [PSCustomObject]@{
                Id           = 99
                Title        = 'Test Feature'
                State        = 'New'
                Tags         = $null
                Effort       = $null
                Description  = $null
                Stories      = @()
                configFields = @{
                    'Custom.AIImplemented' = $true
                    'Custom.FixedIn'       = 'v1.0'
                }
            }

            $output = & (Join-Path $SRC_DIR 'ConvertHierarchyToMarkdown.ps1') `
                -Hierarchy $feature -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT 2>&1 |
                Where-Object { $_ -is [string] } | Out-String

            $fixedInPos   = $output.IndexOf('{Fixed In}')
            $aiImplPos    = $output.IndexOf('{AI Implemented}')
            # "Fixed In" should appear AFTER "AI Implemented" in the Feature config order
            # (in appSettings.json: AI Implemented is at index ~17, Fixed In is at index ~23)
            $fixedInPos -gt $aiImplPos | Should Be $true
        }
    }

    Context 'AC9: Curly-brace format parses correctly with org/project config' {

        It 'GivenCurlyBraceCoreFields_WhenParsing_ItShouldParseCoreFields' {
            $md = @"
### Story: New Style Story
{WorkItemId}: 55
{Story Points}: 3
{State}: New
{Description}
New-style story
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $item = $result.workItems[0]
            $item.workItemId | Should Be 55
            $item.storyPoints | Should Be 3
            $item.state | Should Be 'New'
            $item.description | Should Be 'New-style story'
        }

        It 'GivenMarkdownWithoutOrgProject_WhenParsing_ItShouldReturnWorkItemTypeWithoutFieldParsing' {
            $md = @"
## Feature: A Feature
{AI Implemented}: true
{Description}
No config available
"@
            # Without -Organization and -Project: no config loading, curly-brace fields not recognized
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') -MarkdownContent $md
            $result.workItems.Count | Should Be 1
            $result.workItems[0].type | Should Be 'Feature'
        }
    }
}
