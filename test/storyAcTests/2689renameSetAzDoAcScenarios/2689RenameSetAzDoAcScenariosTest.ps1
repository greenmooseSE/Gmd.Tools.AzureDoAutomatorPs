#Requires -Version 7.0

<#
.SYNOPSIS
AC tests for Story 2689: Rename SetAzDoAcScenarios.ps1 to SetAzDoAcceptanceTests.ps1.
Verifies <see cref="SetAzDoAcceptanceTests"/> exists with updated interface and that
legacy <see cref="SetAzDoAcScenarios"/> no longer exists in the repository.

.DESCRIPTION
Tests file existence/absence, parameter interface, mcpConfig.yaml registration,
and an integration-level scenario setting the Custom.AcceptanceTests field via AzDo API.

Run with: Invoke-Pester .\test\storyAcTests\2689renameSetAzDoAcScenarios\2689RenameSetAzDoAcScenariosTest.ps1
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

[string]$REPO_ROOT  = Resolve-Path (Join-Path $PSScriptRoot '../../../')
[string]$SRC_DIR    = Join-Path $REPO_ROOT 'src'
[string]$MCP_CONFIG = Join-Path $SRC_DIR 'mcpConfig.yaml'

if (-not (Get-Command 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    function global:ssLogIt.ps1 {
        param([string]$Level, [string]$Message, [object]$Exception)
    }
}

Describe 'Story 2689 - Rename SetAzDoAcScenarios to SetAzDoAcceptanceTests' {

    Context 'File rename' {

        It 'GivenRename_OldScriptShouldNotExist' {
            (Test-Path (Join-Path $SRC_DIR 'SetAzDoAcScenarios.ps1')) | Should Be $false
        }

        It 'GivenRename_NewScriptShouldExist' {
            (Test-Path (Join-Path $SRC_DIR 'SetAzDoAcceptanceTests.ps1')) | Should Be $true
        }
    }

    Context 'Script parameter interface' {

        It 'GivenNewScript_ItShouldHaveAcceptanceTestsParameter' {
            $content = Get-Content (Join-Path $SRC_DIR 'SetAzDoAcceptanceTests.ps1') -Raw
            $content -match '\[string\]\$AcceptanceTests' | Should Be $true
        }

        It 'GivenNewScript_ItShouldNotHaveAcScenariosParameter' {
            $content = Get-Content (Join-Path $SRC_DIR 'SetAzDoAcceptanceTests.ps1') -Raw
            $content -match '\$AcScenarios' | Should Be $false
        }

        It 'GivenNewScript_ItShouldReferenceCorrectFieldConstant' {
            $content = Get-Content (Join-Path $SRC_DIR 'SetAzDoAcceptanceTests.ps1') -Raw
            $content -match 'FIELD_ACCEPTANCE_TESTS' | Should Be $true
        }
    }

    Context 'mcpConfig.yaml updated' {

        It 'GivenMcpConfig_ItShouldContainSetAcceptanceTestsId' {
            $content = Get-Content $MCP_CONFIG -Raw
            $content -match 'id: set-acceptance-tests' | Should Be $true
        }

        It 'GivenMcpConfig_ItShouldReferenceNewScript' {
            $content = Get-Content $MCP_CONFIG -Raw
            $content -match 'SetAzDoAcceptanceTests\.ps1' | Should Be $true
        }

        It 'GivenMcpConfig_ItShouldNotContainOldScriptReference' {
            $content = Get-Content $MCP_CONFIG -Raw
            $content -match 'SetAzDoAcScenarios\.ps1' | Should Be $false
        }

        It 'GivenMcpConfig_ItShouldNotContainOldSetAcScenariosId' {
            $content = Get-Content $MCP_CONFIG -Raw
            $content -match 'id: set-ac-scenarios' | Should Be $false
        }

        It 'GivenMcpConfig_SetAcceptanceTestsParamShouldBeAcceptanceTests' {
            $content = Get-Content $MCP_CONFIG -Raw
            # AcceptanceTests param should be mapped under set-acceptance-tests
            $content -match 'mapTo: AcceptanceTests' | Should Be $true
        }
    }

    Context 'Integration: SetAzDoAcceptanceTests.ps1 updates field via API' {

        It 'GivenRenamedScript_WhenSetAcceptanceTests_ItShouldUpdateAzDoField' {
            [string]$org  = $env:GMD_AZDO_ORGANIZATION
            [string]$proj = $env:GMD_AZDO_PROJECT

            if ([string]::IsNullOrWhiteSpace($org) -or [string]::IsNullOrWhiteSpace($proj)) {
                Set-ItResult -Skipped -Because 'Integration environment not available'
                return
            }

            [int]$storyId = 0
            try {
                # Create a temporary story
                $story = & (Join-Path $SRC_DIR 'UpsertAzDoStory.ps1') `
                    -Title 'Test Story 2689 SetAzDoAcceptanceTests' `
                    -ErrorAction Stop
                $storyId = $story.id

                # Tag the story with testWi
                & (Join-Path $SRC_DIR 'SetAzDoWorkItemTags.ps1') `
                    -WorkItemId $storyId -Tags 'testWi' -ErrorAction Stop

                [string]$scenariosText = "Given a story exists`nWhen SetAzDoAcceptanceTests.ps1 is called`nThen Custom.AcceptanceTests is updated"

                $result = & (Join-Path $SRC_DIR 'SetAzDoAcceptanceTests.ps1') `
                    -WorkItemId $storyId `
                    -AcceptanceTests $scenariosText `
                    -ErrorAction Stop

                $result | Should Not BeNullOrEmpty

                # Verify the field was written by reading back the story
                $updated = & (Join-Path $SRC_DIR 'GetAzDoUserStory.ps1') -WorkItemId $storyId -ErrorAction Stop
                $updated.ACScenarios | Should Be $scenariosText
            }
            finally {
                if ($storyId -gt 0) {
                    try {
                        & (Join-Path $SRC_DIR 'RemoveAzDoStory.ps1') -StoryId $storyId -Force -ErrorAction Stop
                        $null = & ssLogIt.ps1 -Level Info -Message "Cleaned up test story ID: $storyId"
                    }
                    catch {
                        $null = & ssLogIt.ps1 -Level Error -Message "Failed to clean up test story $($storyId): $_" -Exception $_
                    }
                }
            }
        }
    }
}
