#Requires -Version 7.0

<#
.SYNOPSIS
AC tests for Story 2617: Update MCP config and template generator for all supported fields.
Verifies <see cref="mcpConfig.yaml"/> upsert commands expose Fields/State params,
and <see cref="GenerateAzDoMarkdownHierarchyTemplate"/> outputs a complete field reference.

.DESCRIPTION
Tests that mcpConfig.yaml contains Fields parameters on all upsert commands,
that command descriptions mention the expected type-specific fields,
and that GenerateAzDoMarkdownHierarchyTemplate.ps1 outputs a SUPPORTED FIELDS REFERENCE
section listing all writable fields from appSettings.json.

Run with: Invoke-Pester .\test\storyAcTests\2617McpConfigTemplateAllFields\2617McpConfigTemplateAllFieldsTest.ps1
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

[string]$REPO_ROOT = Resolve-Path (Join-Path $PSScriptRoot '../../../')
[string]$SRC_DIR   = Join-Path $REPO_ROOT 'src'
[string]$MCP_CONFIG = Join-Path $SRC_DIR 'mcpConfig.yaml'

Describe 'Story 2617 - MCP config and template generator for all supported fields' {

    Context 'mcpConfig.yaml - upsert-story command' {

        It 'GivenMcpConfig_WhenReadUpsertStory_ItShouldHaveFieldsParameter' {
            $content = Get-Content $MCP_CONFIG -Raw
            # Find upsert-story block and check Fields param exists
            $content -match 'id: upsert-story[\s\S]*?id: upsert-task' | Should Be $true
            $storyBlock = ($content -split 'id: upsert-story')[1] -split 'id: upsert-task' | Select-Object -First 1
            $storyBlock -match 'name: Fields' | Should Be $true
        }

        It 'GivenMcpConfig_WhenReadUpsertStory_ItShouldHaveStateParameter' {
            $content = Get-Content $MCP_CONFIG -Raw
            $storyBlock = ($content -split 'id: upsert-story')[1] -split 'id: upsert-task' | Select-Object -First 1
            $storyBlock -match 'name: State' | Should Be $true
        }

        It 'GivenMcpConfig_WhenReadUpsertStoryDescription_ItShouldMentionOriginalEstimate' {
            $content = Get-Content $MCP_CONFIG -Raw
            $storyBlock = ($content -split 'id: upsert-story')[1] -split 'id: upsert-task' | Select-Object -First 1
            $storyBlock -match 'OriginalEstimate' | Should Be $true
        }

        It 'GivenMcpConfig_WhenReadUpsertStoryDescription_ItShouldMentionRemainingWork' {
            $content = Get-Content $MCP_CONFIG -Raw
            $storyBlock = ($content -split 'id: upsert-story')[1] -split 'id: upsert-task' | Select-Object -First 1
            $storyBlock -match 'RemainingWork' | Should Be $true
        }

        It 'GivenMcpConfig_WhenReadUpsertStoryDescription_ItShouldMentionCompletedWork' {
            $content = Get-Content $MCP_CONFIG -Raw
            $storyBlock = ($content -split 'id: upsert-story')[1] -split 'id: upsert-task' | Select-Object -First 1
            $storyBlock -match 'CompletedWork' | Should Be $true
        }
    }

    Context 'mcpConfig.yaml - upsert-feature command' {

        It 'GivenMcpConfig_WhenReadUpsertFeature_ItShouldHaveFieldsParameter' {
            $content = Get-Content $MCP_CONFIG -Raw
            $featureBlock = ($content -split 'id: upsert-feature')[1] -split 'id: upsert-story' | Select-Object -First 1
            $featureBlock -match 'name: Fields' | Should Be $true
        }

        It 'GivenMcpConfig_WhenReadUpsertFeatureDescription_ItShouldMentionAIImplemented' {
            $content = Get-Content $MCP_CONFIG -Raw
            $featureBlock = ($content -split 'id: upsert-feature')[1] -split 'id: upsert-story' | Select-Object -First 1
            $featureBlock -match 'AIImplemented' | Should Be $true
        }

        It 'GivenMcpConfig_WhenReadUpsertFeatureDescription_ItShouldMentionDeployedToDev' {
            $content = Get-Content $MCP_CONFIG -Raw
            $featureBlock = ($content -split 'id: upsert-feature')[1] -split 'id: upsert-story' | Select-Object -First 1
            $featureBlock -match 'DeployedToDev' | Should Be $true
        }

        It 'GivenMcpConfig_WhenReadUpsertFeatureDescription_ItShouldMentionFixedIn' {
            $content = Get-Content $MCP_CONFIG -Raw
            $featureBlock = ($content -split 'id: upsert-feature')[1] -split 'id: upsert-story' | Select-Object -First 1
            $featureBlock -match 'FixedIn' | Should Be $true
        }
    }

    Context 'mcpConfig.yaml - upsert-bug command' {

        It 'GivenMcpConfig_WhenReadUpsertBug_ItShouldHaveFieldsParameter' {
            $content = Get-Content $MCP_CONFIG -Raw
            $bugBlock = ($content -split 'id: upsert-bug')[1] -split 'id: remove-comment' | Select-Object -First 1
            $bugBlock -match 'name: Fields' | Should Be $true
        }

        It 'GivenMcpConfig_WhenReadUpsertBugDescription_ItShouldMentionReproSteps' {
            $content = Get-Content $MCP_CONFIG -Raw
            $bugBlock = ($content -split 'id: upsert-bug')[1] -split 'id: remove-comment' | Select-Object -First 1
            $bugBlock -match 'ReproSteps' | Should Be $true
        }

        It 'GivenMcpConfig_WhenReadUpsertBugDescription_ItShouldMentionSystemInfo' {
            $content = Get-Content $MCP_CONFIG -Raw
            $bugBlock = ($content -split 'id: upsert-bug')[1] -split 'id: remove-comment' | Select-Object -First 1
            $bugBlock -match 'SystemInfo' | Should Be $true
        }

        It 'GivenMcpConfig_WhenReadUpsertBugDescription_ItShouldMentionSeverity' {
            $content = Get-Content $MCP_CONFIG -Raw
            $bugBlock = ($content -split 'id: upsert-bug')[1] -split 'id: remove-comment' | Select-Object -First 1
            $bugBlock -match 'Severity' | Should Be $true
        }
    }

    Context 'mcpConfig.yaml - upsert-task and upsert-epic commands' {

        It 'GivenMcpConfig_WhenReadUpsertTask_ItShouldHaveFieldsParameter' {
            $content = Get-Content $MCP_CONFIG -Raw
            $taskBlock = ($content -split 'id: upsert-task')[1] -split 'id: upsert-bug' | Select-Object -First 1
            $taskBlock -match 'name: Fields' | Should Be $true
        }

        It 'GivenMcpConfig_WhenReadUpsertEpic_ItShouldHaveFieldsParameter' {
            $content = Get-Content $MCP_CONFIG -Raw
            $epicBlock = ($content -split 'id: upsert-epic')[1] -split 'id: upsert-feature' | Select-Object -First 1
            $epicBlock -match 'name: Fields' | Should Be $true
        }

        It 'GivenMcpConfig_WhenReadUpsertEpic_ItShouldHaveStateParameter' {
            $content = Get-Content $MCP_CONFIG -Raw
            $epicBlock = ($content -split 'id: upsert-epic')[1] -split 'id: upsert-feature' | Select-Object -First 1
            $epicBlock -match 'name: State' | Should Be $true
        }
    }

    Context 'GenerateAzDoMarkdownHierarchyTemplate.ps1 - field reference output' {

        BeforeAll {
            $script:templateOutput = & (Join-Path $SRC_DIR 'GenerateAzDoMarkdownHierarchyTemplate.ps1') | Out-String
        }

        It 'GivenTemplate_WhenGenerated_ItShouldContainSupportedFieldsReferenceHeader' {
            $script:templateOutput -match 'SUPPORTED FIELDS REFERENCE' | Should Be $true
        }

        It 'GivenTemplate_WhenGenerated_ItShouldListUserStoryFields' {
            $script:templateOutput -match 'User Story fields' | Should Be $true
        }

        It 'GivenTemplate_WhenGenerated_ItShouldListBugFields' {
            $script:templateOutput -match 'Bug fields' | Should Be $true
        }

        It 'GivenTemplate_WhenGenerated_ItShouldIncludeOriginalEstimateForUserStory' {
            # The field reference should list OriginalEstimate for User Story
            $script:templateOutput -match 'Original Estimate.*Microsoft\.VSTS\.Scheduling\.OriginalEstimate' | Should Be $true
        }

        It 'GivenTemplate_WhenGenerated_ItShouldIncludeReproStepsForBug' {
            $script:templateOutput -match 'Repro Steps.*Microsoft\.VSTS\.TCM\.ReproSteps' | Should Be $true
        }

        It 'GivenTemplate_WhenGenerated_ItShouldIncludeAIImplementedForFeature' {
            $script:templateOutput -match 'AI Implemented.*Custom\.AIImplemented' | Should Be $true
        }

        It 'GivenTemplate_WhenGenerated_ItShouldListAllWritableFieldsForUserStory' {
            # Verify all writable User Story fields from appSettings are mentioned
            [string]$appSettingsPath = Join-Path $REPO_ROOT 'appSettings.json'
            $cfg = Get-Content $appSettingsPath | ConvertFrom-Json
            $storyFields = @($cfg.organizations.'falco-it'.projects.GMD.fields.'User Story' | Where-Object { $_.readOnly -ne $true })
            foreach ($field in $storyFields) {
                $script:templateOutput -match [regex]::Escape($field.referenceName) | Should Be $true
            }
        }
    }
}
