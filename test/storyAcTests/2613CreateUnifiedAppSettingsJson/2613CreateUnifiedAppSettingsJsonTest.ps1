#Requires -Version 7.0

<#
.SYNOPSIS
Acceptance Criteria and BDD scenario tests for Story 2613:
<see cref="LoadStateConfiguration"/> and <see cref="LoadFieldConfiguration"/>
using unified appSettings.json.

.DESCRIPTION
Verifies appSettings.json exists and is structured correctly,
LoadStateConfiguration.ps1 reads states from it, falls back to the legacy
config when appSettings.json is absent, and that LoadFieldConfiguration.ps1
returns field definitions correctly.

Run with: Invoke-Pester .\test\storyAcTests\2613CreateUnifiedAppSettingsJson\2613CreateUnifiedAppSettingsJsonTest.ps1

.NOTES
No AzDo work items are created; all tests are local file-based.
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

[string]$REPO_ROOT = Resolve-Path (Join-Path $PSScriptRoot '../../../')
[string]$SRC_DIR = Join-Path $REPO_ROOT 'src'
[string]$APP_SETTINGS_PATH = Join-Path $REPO_ROOT 'appSettings.json'

# Stub ssLogIt.ps1 if not available in this test context
if (-not (Get-Command 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    function global:ssLogIt.ps1 {
        param([string]$Level, [string]$Message, [object]$Exception)
    }
}

Describe 'Story 2613 - appSettings.json field and state definitions' {

    Context 'appSettings.json structure' {

        It 'appSettings.json exists at repo root' {
            (Test-Path -Path $APP_SETTINGS_PATH) | Should Be $true
        }

        It 'appSettings.json is valid JSON' {
            { Get-Content $APP_SETTINGS_PATH -Raw | ConvertFrom-Json } | Should Not Throw
        }

        It 'contains organizations.falco-it.projects.GMD path' {
            $s = Get-Content $APP_SETTINGS_PATH -Raw | ConvertFrom-Json
            $s.organizations.'falco-it'.projects.GMD | Should Not BeNullOrEmpty
        }

        It 'Epic field list has at least 15 entries including System.Id' {
            $s = Get-Content $APP_SETTINGS_PATH -Raw | ConvertFrom-Json
            $epicFields = $s.organizations.'falco-it'.projects.GMD.fields.Epic
            ($epicFields.Count -ge 15) | Should Be $true
            ($epicFields | Where-Object { $_.referenceName -eq 'System.Id' }) | Should Not BeNullOrEmpty
        }

        It 'Feature field list contains all required Custom.* fields' {
            $s = Get-Content $APP_SETTINGS_PATH -Raw | ConvertFrom-Json
            $featureFields = $s.organizations.'falco-it'.projects.GMD.fields.Feature
            $requiredRefs = @(
                'Custom.AIImplemented', 'Custom.CodeReviewed', 'Custom.FunctionallyTested',
                'Custom.DeployedToDev', 'Custom.DeployedToStaging', 'Custom.DeployedToProduction',
                'Custom.ExtraInformation', 'Custom.FeatureAcceptanceTests', 'Custom.FixedIn'
            )
            foreach ($ref in $requiredRefs) {
                ($featureFields | Where-Object { $_.referenceName -eq $ref }) | Should Not BeNullOrEmpty
            }
        }

        It 'User Story field list contains AcceptanceTests, AcceptanceCriteria, StoryAcceptanceTests, OriginalEstimate, RemainingWork, CompletedWork' {
            $s = Get-Content $APP_SETTINGS_PATH -Raw | ConvertFrom-Json
            $storyFields = $s.organizations.'falco-it'.projects.GMD.fields.'User Story'
            $requiredRefs = @(
                'Custom.AcceptanceTests', 'Custom.AcceptanceCriteria', 'Custom.StoryAcceptanceTests',
                'Microsoft.VSTS.Scheduling.OriginalEstimate',
                'Microsoft.VSTS.Scheduling.RemainingWork',
                'Microsoft.VSTS.Scheduling.CompletedWork'
            )
            foreach ($ref in $requiredRefs) {
                ($storyFields | Where-Object { $_.referenceName -eq $ref }) | Should Not BeNullOrEmpty
            }
        }

        It 'Bug field list contains ReproSteps, SystemInfo, FoundIn, Severity' {
            $s = Get-Content $APP_SETTINGS_PATH -Raw | ConvertFrom-Json
            $bugFields = $s.organizations.'falco-it'.projects.GMD.fields.Bug
            $requiredRefs = @(
                'Microsoft.VSTS.TCM.ReproSteps',
                'Microsoft.VSTS.TCM.SystemInfo',
                'Microsoft.VSTS.Build.FoundIn',
                'Microsoft.VSTS.Common.Severity'
            )
            foreach ($ref in $requiredRefs) {
                ($bugFields | Where-Object { $_.referenceName -eq $ref }) | Should Not BeNullOrEmpty
            }
        }

        It 'Task field list contains Activity, OriginalEstimate, RemainingWork, CompletedWork' {
            $s = Get-Content $APP_SETTINGS_PATH -Raw | ConvertFrom-Json
            $taskFields = $s.organizations.'falco-it'.projects.GMD.fields.Task
            $requiredRefs = @(
                'Microsoft.VSTS.Common.Activity',
                'Microsoft.VSTS.Scheduling.OriginalEstimate',
                'Microsoft.VSTS.Scheduling.RemainingWork',
                'Microsoft.VSTS.Scheduling.CompletedWork'
            )
            foreach ($ref in $requiredRefs) {
                ($taskFields | Where-Object { $_.referenceName -eq $ref }) | Should Not BeNullOrEmpty
            }
        }

        It 'every field object has referenceName, label, description, type, and readOnly' {
            $s = Get-Content $APP_SETTINGS_PATH -Raw | ConvertFrom-Json
            $allTypes = @('Epic', 'Feature', 'User Story', 'Bug', 'Task')
            foreach ($wiType in $allTypes) {
                $fields = $s.organizations.'falco-it'.projects.GMD.fields.$wiType
                foreach ($field in $fields) {
                    $field.referenceName | Should Not BeNullOrEmpty
                    $field.label         | Should Not BeNullOrEmpty
                    ($field.PSObject.Properties.Name -contains 'description') | Should Be $true
                    $field.type          | Should Not BeNullOrEmpty
                    ($field.PSObject.Properties.Name -contains 'readOnly') | Should Be $true
                }
            }
        }

        It 'System.Id is readOnly integer with label WorkItemId for every work item type' {
            $s = Get-Content $APP_SETTINGS_PATH -Raw | ConvertFrom-Json
            foreach ($wiType in @('Epic', 'Feature', 'User Story', 'Bug', 'Task')) {
                $fields = $s.organizations.'falco-it'.projects.GMD.fields.$wiType
                $f = $fields | Where-Object { $_.referenceName -eq 'System.Id' }
                $f           | Should Not BeNullOrEmpty
                $f.readOnly  | Should Be $true
                $f.label     | Should Be 'WorkItemId'
                $f.type      | Should Be 'integer'
            }
        }

        It 'state definitions exist for all five work item types' {
            $s = Get-Content $APP_SETTINGS_PATH -Raw | ConvertFrom-Json
            $states = $s.organizations.'falco-it'.projects.GMD.states
            $states.Epic           | Should Not BeNullOrEmpty
            $states.Feature        | Should Not BeNullOrEmpty
            $states.'User Story'   | Should Not BeNullOrEmpty
            $states.Bug            | Should Not BeNullOrEmpty
            $states.Task           | Should Not BeNullOrEmpty
        }

        It 'Feature Released and Removed are readOnly; New is not' {
            $s = Get-Content $APP_SETTINGS_PATH -Raw | ConvertFrom-Json
            $fStates = $s.organizations.'falco-it'.projects.GMD.states.Feature
            ($fStates | Where-Object { $_.name -eq 'Released' }).readOnly | Should Be $true
            ($fStates | Where-Object { $_.name -eq 'Removed' }).readOnly  | Should Be $true
            ($fStates | Where-Object { $_.name -eq 'New' }).readOnly      | Should Be $false
        }

        It 'states in Completed and Removed categories have readOnly true' {
            $s = Get-Content $APP_SETTINGS_PATH -Raw | ConvertFrom-Json
            foreach ($wiType in @('Epic', 'Feature', 'User Story', 'Bug', 'Task')) {
                $typeStates = $s.organizations.'falco-it'.projects.GMD.states.$wiType
                foreach ($state in $typeStates) {
                    if ($state.category -in @('Completed', 'Removed')) {
                        $state.readOnly | Should Be $true
                    }
                }
            }
        }
    }

    Context 'LoadStateConfiguration.ps1 reads from appSettings.json' {

        It 'GivenAppSettingsJson_WhenLoadingStates_ItShouldReturnWritableStatesForAllTypes' {
            $config = & (Join-Path $SRC_DIR 'LoadStateConfiguration.ps1') `
                -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT -Force
            $config | Should Not BeNullOrEmpty
            $config.writableStates | Should Not BeNullOrEmpty
            ($config.writableStates.Keys -contains 'Feature') | Should Be $true
            ($config.writableStates.Keys -contains 'Task')    | Should Be $true
        }

        It 'GivenAppSettingsJson_WhenLoadingFeatureStates_ItShouldNotIncludeReleasedOrRemoved' {
            $config = & (Join-Path $SRC_DIR 'LoadStateConfiguration.ps1') `
                -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT -Force
            ($config.writableStates.Feature -contains 'Released') | Should Be $false
            ($config.writableStates.Feature -contains 'Removed')  | Should Be $false
            ($config.writableStates.Feature -contains 'New')      | Should Be $true
        }

        It 'GivenAppSettingsJson_WhenLoadingUserStoryStates_BothKeyVariantsArePresent' {
            $config = & (Join-Path $SRC_DIR 'LoadStateConfiguration.ps1') `
                -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT -Force
            $config.writableStates.'User Story' | Should Not BeNullOrEmpty
            $config.writableStates.'Story'      | Should Not BeNullOrEmpty
        }
    }

    Context 'LoadStateConfiguration.ps1 falls back to legacy config' {

        It 'GivenNoAppSettingsJson_WhenLegacyFileExists_ItShouldLoadFromLegacyFile' {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('2613test_' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $tempDir | Out-Null
            try {
                $legacyConfig = '{"writableStates":{"Epic":["New"],"Feature":["New","Active"],"Story":["New"],"Task":["New"],"Bug":["New"]}}'
                Set-Content -Path (Join-Path $tempDir 'azdoStateConfig-falco-it-GMD.json') -Value $legacyConfig -Encoding UTF8

                $config = & (Join-Path $SRC_DIR 'LoadStateConfiguration.ps1') `
                    -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $tempDir -Force
                $config.writableStates | Should Not BeNullOrEmpty
                ($config.writableStates.Feature -contains 'Active') | Should Be $true
            }
            finally {
                Remove-Item -Recurse -Force $tempDir
            }
        }
    }

    Context 'LoadFieldConfiguration.ps1 returns field definitions' {

        It 'GivenAppSettingsJson_WhenLoadingUserStoryFields_ItShouldReturnExpectedFields' {
            $fields = & (Join-Path $SRC_DIR 'LoadFieldConfiguration.ps1') `
                -Organization 'falco-it' -Project 'GMD' -WorkItemType 'User Story' `
                -RepositoryRoot $REPO_ROOT -Force
            $fields | Should Not BeNullOrEmpty
            ($fields | Where-Object { $_.referenceName -eq 'System.Id' })                                   | Should Not BeNullOrEmpty
            ($fields | Where-Object { $_.referenceName -eq 'System.Title' })                                | Should Not BeNullOrEmpty
            ($fields | Where-Object { $_.referenceName -eq 'Custom.AcceptanceTests' })                          | Should Not BeNullOrEmpty
            ($fields | Where-Object { $_.referenceName -eq 'Microsoft.VSTS.Scheduling.StoryPoints' })       | Should Not BeNullOrEmpty
            ($fields | Where-Object { $_.referenceName -eq 'Microsoft.VSTS.Scheduling.OriginalEstimate' })  | Should Not BeNullOrEmpty
        }

        It 'GivenAppSettingsJson_WhenLoadingFeatureFields_EachFieldHasRequiredProperties' {
            $fields = & (Join-Path $SRC_DIR 'LoadFieldConfiguration.ps1') `
                -Organization 'falco-it' -Project 'GMD' -WorkItemType 'Feature' `
                -RepositoryRoot $REPO_ROOT -Force
            ($fields.Count -gt 0) | Should Be $true
            foreach ($f in $fields) {
                $f.referenceName | Should Not BeNullOrEmpty
                $f.label         | Should Not BeNullOrEmpty
                $f.type          | Should Not BeNullOrEmpty
                ($f.PSObject.Properties.Name -contains 'readOnly') | Should Be $true
            }
        }

        It 'GivenMissingAppSettingsJson_WhenLoadingFields_ItShouldReturnEmptyArray' {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('2613fld_' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $tempDir | Out-Null
            try {
                $fields = & (Join-Path $SRC_DIR 'LoadFieldConfiguration.ps1') `
                    -Organization 'falco-it' -Project 'GMD' -WorkItemType 'Task' `
                    -RepositoryRoot $tempDir -Force
                ($null -eq $fields -or @($fields).Count -eq 0) | Should Be $true
            }
            finally {
                Remove-Item -Recurse -Force $tempDir
            }
        }
    }
}
