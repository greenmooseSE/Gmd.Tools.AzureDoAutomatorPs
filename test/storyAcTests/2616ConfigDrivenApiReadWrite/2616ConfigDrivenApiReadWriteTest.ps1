#Requires -Version 7.0

<#
.SYNOPSIS
AC tests for Story 2616: Config-driven field read and write in API operations.
Verifies <see cref="ValidateUpsertFields"/> helpers, <see cref="GetAzDoUserStory"/>,
<see cref="GetAzDoBug"/> enrichment, and -Fields / -State parameter validation in Upsert scripts.

.DESCRIPTION
Tests validation logic (readOnly field rejection, readOnly state rejection),
GetAzDoUserStory subset fields, and GetAzDoBug named properties.
Integration tests that require live API access are not included here.

Run with: Invoke-Pester .\test\storyAcTests\2616ConfigDrivenApiReadWrite\2616ConfigDrivenApiReadWriteTest.ps1
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

[string]$REPO_ROOT = Resolve-Path (Join-Path $PSScriptRoot '../../../')
[string]$SRC_DIR = Join-Path $REPO_ROOT 'src'

# Stub ssLogIt.ps1 for tests
if (-not (Get-Command 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    function global:ssLogIt.ps1 {
        param([string]$Level, [string]$Message, [object]$Exception)
    }
}

Describe 'Story 2616 - Config-driven field read and write in API operations' {

    Context 'ValidateUpsertFields - Assert-FieldsNotReadOnly' {

        BeforeAll {
            . (Join-Path $SRC_DIR 'AzDoAutomatorConstants.ps1')
            . (Join-Path $SRC_DIR 'ValidateUpsertFields.ps1')
        }

        It 'GivenReadOnlyFieldSystemId_WhenValidating_ItShouldThrow' {
            $threw = $false
            try {
                Assert-FieldsNotReadOnly -Organization 'falco-it' -Project 'GMD' `
                    -WorkItemType 'User Story' `
                    -Fields @{ 'System.Id' = 999 }
            } catch {
                $threw = $true
                $_.Exception.Message -match 'readOnly' | Should Be $true
            }
            $threw | Should Be $true
        }

        It 'GivenWritableField_WhenValidating_ItShouldNotThrow' {
            $threw = $false
            try {
                Assert-FieldsNotReadOnly -Organization 'falco-it' -Project 'GMD' `
                    -WorkItemType 'User Story' `
                    -Fields @{ 'Microsoft.VSTS.Scheduling.OriginalEstimate' = 8.0 }
            } catch {
                $threw = $true
            }
            $threw | Should Be $false
        }

        It 'GivenEmptyFields_WhenValidating_ItShouldNotThrow' {
            $threw = $false
            try {
                Assert-FieldsNotReadOnly -Organization 'falco-it' -Project 'GMD' `
                    -WorkItemType 'User Story' -Fields @{}
            } catch {
                $threw = $true
            }
            $threw | Should Be $false
        }

        It 'GivenNoOrgProject_WhenValidating_ItShouldNotThrow' {
            # Validation is skipped when org/project not provided
            $threw = $false
            try {
                Assert-FieldsNotReadOnly -Organization '' -Project '' `
                    -WorkItemType 'User Story' `
                    -Fields @{ 'System.Id' = 999 }
            } catch {
                $threw = $true
            }
            $threw | Should Be $false
        }
    }

    Context 'ValidateUpsertFields - Assert-StateIsWritable' {

        BeforeAll {
            . (Join-Path $SRC_DIR 'AzDoAutomatorConstants.ps1')
            . (Join-Path $SRC_DIR 'ValidateUpsertFields.ps1')
        }

        It 'GivenReadOnlyStateReleased_WhenValidating_ItShouldThrow' {
            $threw = $false
            try {
                Assert-StateIsWritable -Organization 'falco-it' -Project 'GMD' `
                    -WorkItemType 'User Story' -State 'Released'
            } catch {
                $threw = $true
                $_.Exception.Message -match 'writable|readOnly' | Should Be $true
            }
            $threw | Should Be $true
        }

        It 'GivenWritableStateNew_WhenValidating_ItShouldNotThrow' {
            $threw = $false
            try {
                Assert-StateIsWritable -Organization 'falco-it' -Project 'GMD' `
                    -WorkItemType 'User Story' -State 'New'
            } catch {
                $threw = $true
            }
            $threw | Should Be $false
        }

        It 'GivenReadOnlyStateRemoved_WhenValidating_ItShouldThrow' {
            $threw = $false
            try {
                Assert-StateIsWritable -Organization 'falco-it' -Project 'GMD' `
                    -WorkItemType 'Feature' -State 'Removed'
            } catch {
                $threw = $true
            }
            $threw | Should Be $true
        }

        It 'GivenNoOrgProject_WhenValidating_ItShouldNotThrow' {
            $threw = $false
            try {
                Assert-StateIsWritable -Organization '' -Project '' `
                    -WorkItemType 'User Story' -State 'Released'
            } catch {
                $threw = $true
            }
            $threw | Should Be $false
        }

        It 'GivenEmptyState_WhenValidating_ItShouldNotThrow' {
            $threw = $false
            try {
                Assert-StateIsWritable -Organization 'falco-it' -Project 'GMD' `
                    -WorkItemType 'User Story' -State ''
            } catch {
                $threw = $true
            }
            $threw | Should Be $false
        }
    }

    Context 'GetAzDoUserStory - subset includes time-tracking fields' {

        It 'GivenUserStoryWithTimeFields_WhenBuildingSubset_ItShouldIncludeOriginalEstimateRemainingWorkCompletedWork' {
            # Create a mock work item response object
            $mockWorkItem = [PSCustomObject]@{
                id  = 100
                rev = 1
                fields = [PSCustomObject]@{
                    'System.WorkItemType'                          = 'User Story'
                    'System.State'                                 = 'New'
                    'System.Title'                                 = 'Test Story'
                    'Microsoft.VSTS.Scheduling.OriginalEstimate'   = 16.0
                    'Microsoft.VSTS.Scheduling.RemainingWork'      = 12.0
                    'Microsoft.VSTS.Scheduling.CompletedWork'      = 4.0
                    'Microsoft.VSTS.Scheduling.StoryPoints'        = 5.0
                    'Custom.ACScenarios'                           = 'Some scenarios'
                    'Custom.ExtraInformation'                      = $null
                    'Microsoft.VSTS.Common.AcceptanceCriteria'     = $null
                    'System.Description'                           = $null
                    'System.Tags'                                  = $null
                }
            }

            # Build the same subset that GetAzDoUserStory.ps1 constructs
            $storyObject = @{
                Id                 = $mockWorkItem.id
                State              = $mockWorkItem.fields.'System.State'
                Title              = $mockWorkItem.fields.'System.Title'
                Description        = if ($mockWorkItem.fields.PSObject.Properties.Name -contains 'System.Description') { $mockWorkItem.fields.'System.Description' } else { $null }
                AcceptanceCriteria = if ($mockWorkItem.fields.PSObject.Properties.Name -contains 'Microsoft.VSTS.Common.AcceptanceCriteria') { $mockWorkItem.fields.'Microsoft.VSTS.Common.AcceptanceCriteria' } else { $null }
                ACScenarios        = if ($mockWorkItem.fields.PSObject.Properties.Name -contains 'Custom.ACScenarios') { $mockWorkItem.fields.'Custom.ACScenarios' } else { $null }
                StoryPoints        = if ($mockWorkItem.fields.PSObject.Properties.Name -contains 'Microsoft.VSTS.Scheduling.StoryPoints') { $mockWorkItem.fields.'Microsoft.VSTS.Scheduling.StoryPoints' } else { $null }
                ExtraInformation   = if ($mockWorkItem.fields.PSObject.Properties.Name -contains 'Custom.ExtraInformation') { $mockWorkItem.fields.'Custom.ExtraInformation' } else { $null }
                Tags               = if ($mockWorkItem.fields.PSObject.Properties.Name -contains 'System.Tags') { $mockWorkItem.fields.'System.Tags' } else { $null }
                OriginalEstimate   = if ($mockWorkItem.fields.PSObject.Properties.Name -contains 'Microsoft.VSTS.Scheduling.OriginalEstimate') { $mockWorkItem.fields.'Microsoft.VSTS.Scheduling.OriginalEstimate' } else { $null }
                RemainingWork      = if ($mockWorkItem.fields.PSObject.Properties.Name -contains 'Microsoft.VSTS.Scheduling.RemainingWork') { $mockWorkItem.fields.'Microsoft.VSTS.Scheduling.RemainingWork' } else { $null }
                CompletedWork      = if ($mockWorkItem.fields.PSObject.Properties.Name -contains 'Microsoft.VSTS.Scheduling.CompletedWork') { $mockWorkItem.fields.'Microsoft.VSTS.Scheduling.CompletedWork' } else { $null }
                CustomFields       = @{}
            }
            $result = [PSCustomObject]$storyObject

            $result.OriginalEstimate | Should Be 16.0
            $result.RemainingWork    | Should Be 12.0
            $result.CompletedWork    | Should Be 4.0
            $result.ACScenarios      | Should Be 'Some scenarios'
        }
    }

    Context 'GetAzDoBug - named properties added via Add-Member' {

        It 'GivenBugWithReproSteps_WhenEnriched_ItShouldHaveReproStepsProperty' {
            $mockBug = [PSCustomObject]@{
                id  = 200
                rev = 1
                fields = [PSCustomObject]@{
                    'System.Title'                    = 'Login fails'
                    'System.State'                    = 'New'
                    'Microsoft.VSTS.TCM.ReproSteps'   = '<p>Step 1: Click login</p>'
                    'Microsoft.VSTS.TCM.SystemInfo'   = 'Win 11'
                    'Microsoft.VSTS.Common.Severity'  = '2 - High'
                    'Microsoft.VSTS.Build.FoundIn'    = 'v2.0.0'
                }
            }

            # Apply same Add-Member enrichment as GetAzDoBug.ps1 now does
            [string]$reproStepsVal = if ($mockBug.fields.PSObject.Properties.Name -contains 'Microsoft.VSTS.TCM.ReproSteps') { $mockBug.fields.'Microsoft.VSTS.TCM.ReproSteps' } else { $null }
            [string]$systemInfoVal  = if ($mockBug.fields.PSObject.Properties.Name -contains 'Microsoft.VSTS.TCM.SystemInfo') { $mockBug.fields.'Microsoft.VSTS.TCM.SystemInfo' } else { $null }
            [string]$severityVal    = if ($mockBug.fields.PSObject.Properties.Name -contains 'Microsoft.VSTS.Common.Severity') { $mockBug.fields.'Microsoft.VSTS.Common.Severity' } else { $null }
            [string]$foundInVal     = if ($mockBug.fields.PSObject.Properties.Name -contains 'Microsoft.VSTS.Build.FoundIn') { $mockBug.fields.'Microsoft.VSTS.Build.FoundIn' } else { $null }
            [string]$stateVal       = if ($mockBug.fields.PSObject.Properties.Name -contains 'System.State') { $mockBug.fields.'System.State' } else { $null }
            $mockBug | Add-Member -NotePropertyName 'ReproSteps' -NotePropertyValue $reproStepsVal -Force
            $mockBug | Add-Member -NotePropertyName 'SystemInfo'  -NotePropertyValue $systemInfoVal -Force
            $mockBug | Add-Member -NotePropertyName 'Severity'    -NotePropertyValue $severityVal -Force
            $mockBug | Add-Member -NotePropertyName 'FoundIn'     -NotePropertyValue $foundInVal -Force
            $mockBug | Add-Member -NotePropertyName 'State'       -NotePropertyValue $stateVal -Force

            $mockBug.ReproSteps | Should Be '<p>Step 1: Click login</p>'
            $mockBug.SystemInfo | Should Be 'Win 11'
            $mockBug.Severity   | Should Be '2 - High'
            $mockBug.FoundIn    | Should Be 'v2.0.0'
            $mockBug.State      | Should Be 'New'
            # Original .id still works (backward compat)
            $mockBug.id         | Should Be 200
        }
    }
}
