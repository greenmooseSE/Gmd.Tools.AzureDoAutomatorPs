#Requires -Version 7.0

<#
.SYNOPSIS
AC tests for prompt script generation and data format guideline inclusion.

.DESCRIPTION
Verifies that all promptCreate*.ps1 and promptImplement*.ps1 scripts:
1. Execute without errors
2. Generate non-empty prompts
3. Include data format guidelines (either directly or via cross-reference)
4. Complete all template substitutions (no {{PLACEHOLDER}} remnants)
5. All include files are accessible and readable

Run with: Invoke-Pester .\test\PromptScriptsTests\PromptScriptsExecutionTest.ps1
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

[string]$REPO_ROOT  = Resolve-Path (Join-Path $PSScriptRoot '../../')
[string]$DOCS_DIR   = Join-Path $REPO_ROOT 'docs'

Describe 'Prompt Scripts — Execution and Data Format Guidelines' {
    Context 'promptCreatePlanStoryMarkdown_General.ps1' {
        BeforeAll {
            $scriptPath = Join-Path $DOCS_DIR 'promptCreatePlanStoryMarkdown_General.ps1'
            $testEpicId = 1305
            $testFeatureId = 1590
        }

        It 'should execute without errors with valid parameters' {
            {
                & $scriptPath -EpicId $testEpicId -FeatureId $testFeatureId
            } | Should Not Throw
        }

        It 'should generate non-empty output' {
            $output = & $scriptPath -EpicId $testEpicId -FeatureId $testFeatureId
            $output | Should Not BeNullOrEmpty
            $output.Length | Should BeGreaterThan 100
        }

        It 'should include data format guidelines section' {
            $output = & $scriptPath -EpicId $testEpicId -FeatureId $testFeatureId
            $output | Should Match 'Data format and encoding rules'
            $output | Should Match 'ISO 8601 UTC'
            $output | Should Match 'File encoding'
        }

        It 'should have no unsubstituted placeholders' {
            $output = & $scriptPath -EpicId $testEpicId -FeatureId $testFeatureId
            $output | Should Not Match '\{\{[A-Z_]+\}\}'
        }

        It 'should reference story rules from _General.md' {
            $output = & $scriptPath -EpicId $testEpicId -FeatureId $testFeatureId
            $output | Should Match 'General rules'
            $output | Should Match 'Acceptance Criteria'
        }
    }

    Context 'promptCreatePlanBugMarkdown_General.ps1' {
        BeforeAll {
            $scriptPath = Join-Path $DOCS_DIR 'promptCreatePlanBugMarkdown_General.ps1'
            $testEpicId = 1305
            $testFeatureId = 1590
        }

        It 'should execute without errors with valid parameters' {
            {
                & $scriptPath -EpicId $testEpicId -FeatureId $testFeatureId
            } | Should Not Throw
        }

        It 'should generate non-empty output' {
            $output = & $scriptPath -EpicId $testEpicId -FeatureId $testFeatureId
            $output | Should Not BeNullOrEmpty
            $output.Length | Should BeGreaterThan 100
        }

        It 'should have no unsubstituted placeholders' {
            $output = & $scriptPath -EpicId $testEpicId -FeatureId $testFeatureId
            $output | Should Not Match '\{\{[A-Z_]+\}\}'
        }
    }

    Context 'promptCreatePlanFeatureMarkdown_General.ps1' {
        BeforeAll {
            $scriptPath = Join-Path $DOCS_DIR 'promptCreatePlanFeatureMarkdown_General.ps1'
            $testEpicId = 1305
            $testOrg = 'falco-it'
            $testProject = 'GMD'
        }

        It 'should execute without errors (new feature)' {
            {
                & $scriptPath -EpicId $testEpicId -Organization $testOrg -AzDoProject $testProject
            } | Should Not Throw
        }

        It 'should execute without errors (add to existing feature)' {
            {
                & $scriptPath -EpicId $testEpicId -FeatureId 1590 -Organization $testOrg -AzDoProject $testProject
            } | Should Not Throw
        }

        It 'should execute without errors (multi-feature)' {
            {
                & $scriptPath -EpicId $testEpicId -Organization $testOrg -AzDoProject $testProject -MultipleFeatures
            } | Should Not Throw
        }

        It 'should generate non-empty output' {
            $output = & $scriptPath -EpicId $testEpicId -Organization $testOrg -AzDoProject $testProject
            $output | Should Not BeNullOrEmpty
            $output.Length | Should BeGreaterThan 100
        }

        It 'should include data format guidelines section' {
            $output = & $scriptPath -EpicId $testEpicId -Organization $testOrg -AzDoProject $testProject
            $output | Should Match 'Data format and encoding rules'
            $output | Should Match 'ISO 8601 UTC'
        }

        It 'should have no unsubstituted placeholders' {
            $output = & $scriptPath -EpicId $testEpicId -Organization $testOrg -AzDoProject $testProject
            $output | Should Not Match '\{\{[A-Z_]+\}\}'
        }

        It 'should indicate multi-feature override in output when -MultipleFeatures is set' {
            $output = & $scriptPath -EpicId $testEpicId -Organization $testOrg -AzDoProject $testProject -MultipleFeatures
            $output | Should Match 'Multi-feature plan override'
        }
    }

    Context 'promptCreatePlanFeatureMarkdown_ThisProject.ps1' {
        BeforeAll {
            $scriptPath = Join-Path $DOCS_DIR 'promptCreatePlanFeatureMarkdown_ThisProject.ps1'
            $testEpicId = 1305
        }

        It 'should execute without errors (new feature)' {
            {
                & $scriptPath -EpicId $testEpicId
            } | Should Not Throw
        }

        It 'should execute without errors (add to existing feature)' {
            {
                & $scriptPath -EpicId $testEpicId -FeatureId 1590
            } | Should Not Throw
        }

        It 'should include both general and project-specific story rules' {
            $output = & $scriptPath -EpicId $testEpicId
            $output | Should Match 'Data format and encoding rules'
            $output | Should Match 'Project-Specific Story Rules'
        }

        It 'should have no unsubstituted placeholders' {
            $output = & $scriptPath -EpicId $testEpicId
            $output | Should Not Match '\{\{[A-Z_]+\}\}'
        }
    }

    Context 'promptCreatePlanFeatureMarkdown_WebApiCs.ps1' {
        BeforeAll {
            $scriptPath = Join-Path $DOCS_DIR 'promptCreatePlanFeatureMarkdown_WebApiCs.ps1'
            $testEpicId = 1305
            $testOrg = 'falco-it'
            $testProject = 'GMD'
        }

        It 'should execute without errors' {
            {
                & $scriptPath -EpicId $testEpicId -Organization $testOrg -AzDoProject $testProject
            } | Should Not Throw
        }

        It 'should include data format guidelines and WebApi rules' {
            $output = & $scriptPath -EpicId $testEpicId -Organization $testOrg -AzDoProject $testProject
            $output | Should Match 'Data format and encoding rules'
            $output | Should Match 'WebApi'
        }

        It 'should have no unsubstituted placeholders' {
            $output = & $scriptPath -EpicId $testEpicId -Organization $testOrg -AzDoProject $testProject
            $output | Should Not Match '\{\{[A-Z_]+\}\}'
        }
    }

    Context 'promptCreatePlanFeatureMarkdownPs.ps1' {
        BeforeAll {
            $scriptPath = Join-Path $DOCS_DIR 'promptCreatePlanFeatureMarkdownPs.ps1'
            $testEpicId = 1305
            $testOrg = 'falco-it'
            $testProject = 'GMD'
        }

        It 'should execute without errors' {
            {
                & $scriptPath -EpicId $testEpicId -Organization $testOrg -AzDoProject $testProject
            } | Should Not Throw
        }

        It 'should include data format guidelines' {
            $output = & $scriptPath -EpicId $testEpicId -Organization $testOrg -AzDoProject $testProject
            $output | Should Match 'Data format and encoding rules'
        }

        It 'should have no unsubstituted placeholders' {
            $output = & $scriptPath -EpicId $testEpicId -Organization $testOrg -AzDoProject $testProject
            $output | Should Not Match '\{\{[A-Z_]+\}\}'
        }
    }

    Context 'promptImplementFeature_ThisProject.ps1' {
        BeforeAll {
            $scriptPath = Join-Path $DOCS_DIR 'promptImplementFeature_ThisProject.ps1'
            $testFeatureId = 1590
            $testTitle = 'exportImportHierarchy'
            $testPlanFile = 'docs\plans\plan-1590-exportImportHierarchy.md'
            # Use a temp plan file if it doesn't exist
            if (-not (Test-Path (Join-Path $REPO_ROOT $testPlanFile))) {
                $testPlanFile = 'docs\plans\plan-1577-unambiguousFieldSyntax.md'
            }
        }

        It 'should execute without errors with feature title supplied' {
            {
                & $scriptPath -FeatureId $testFeatureId -FeatureTitle $testTitle -PlanFile $testPlanFile
            } | Should Not Throw
        }

        It 'should generate non-empty output' {
            $output = & $scriptPath -FeatureId $testFeatureId -FeatureTitle $testTitle -PlanFile $testPlanFile
            $output | Should Not BeNullOrEmpty
            $output.Length | Should BeGreaterThan 100
        }

        It 'should include data format guidelines in full (not just cross-reference)' {
            $output = & $scriptPath -FeatureId $testFeatureId -FeatureTitle $testTitle -PlanFile $testPlanFile
            # Should include the full general story rules with data format guidelines
            $output | Should Match 'Data format and encoding rules'
            $output | Should Match 'ISO 8601 UTC'
            $output | Should Match 'File encoding'
        }

        It 'should have no unsubstituted placeholders' {
            $output = & $scriptPath -FeatureId $testFeatureId -FeatureTitle $testTitle -PlanFile $testPlanFile
            $output | Should Not Match '\{\{[A-Z_]+\}\}'
        }

        It 'should include feature branch name' {
            $output = & $scriptPath -FeatureId $testFeatureId -FeatureTitle $testTitle -PlanFile $testPlanFile
            $output | Should Match 'feat/ab#1590'
        }
    }

    Context 'promptImplementFeature_WebApiCs.ps1' {
        BeforeAll {
            $scriptPath = Join-Path $DOCS_DIR 'promptImplementFeature_WebApiCs.ps1'
            $testFeatureId = 2577
            $testTitle = 'aiChatApiMvp'
            $testPlanFile = 'docs\plans\plan-01-feature-01-firstMvp.md'
        }

        It 'should execute without errors' {
            {
                & $scriptPath -FeatureId $testFeatureId -FeatureTitle $testTitle -PlanFile $testPlanFile
            } | Should Not Throw
        }

        It 'should have no unsubstituted placeholders' {
            $output = & $scriptPath -FeatureId $testFeatureId -FeatureTitle $testTitle -PlanFile $testPlanFile
            $output | Should Not Match '\{\{[A-Z_]+\}\}'
        }

        It 'should reference WebApi architecture rules' {
            $output = & $scriptPath -FeatureId $testFeatureId -FeatureTitle $testTitle -PlanFile $testPlanFile
            $output | Should Match 'architecturalRules'
        }
    }

    Context 'promptImplementStory_ThisProject.ps1' {
        BeforeAll {
            $scriptPath = Join-Path $DOCS_DIR 'promptImplementStory_ThisProject.ps1'
            $testStoryId = 2695
            $testFeatureId = 2694
            $testPlanFile = 'docs\plans\plan-1577-unambiguousFieldSyntax.md'
        }

        It 'should execute without errors with story ID only' {
            {
                & $scriptPath -StoryId $testStoryId
            } | Should Not Throw
        }

        It 'should execute without errors with feature ID and plan file' {
            {
                & $scriptPath -StoryId $testStoryId -FeatureId $testFeatureId -PlanFile $testPlanFile
            } | Should Not Throw
        }

        It 'should generate non-empty output' {
            $output = & $scriptPath -StoryId $testStoryId
            $output | Should Not BeNullOrEmpty
            $output.Length | Should BeGreaterThan 100
        }

        It 'should include data format guidelines in full' {
            $output = & $scriptPath -StoryId $testStoryId
            $output | Should Match 'Data format and encoding rules'
            $output | Should Match 'ISO 8601 UTC'
        }

        It 'should have no unsubstituted placeholders' {
            $output = & $scriptPath -StoryId $testStoryId
            $output | Should Not Match '\{\{[A-Z_]+\}\}'
        }

        It 'should derive feature branch when feature ID is supplied' {
            $output = & $scriptPath -StoryId $testStoryId -FeatureId $testFeatureId -PlanFile $testPlanFile
            $output | Should Match 'feat/ab#2694'
        }
    }

    Context 'All Prompt Scripts' {
        BeforeAll {
            $promptScripts = @(
                'promptCreatePlanStoryMarkdown_General.ps1'
                'promptCreatePlanBugMarkdown_General.ps1'
                'promptCreatePlanFeatureMarkdown_General.ps1'
                'promptCreatePlanFeatureMarkdown_ThisProject.ps1'
                'promptCreatePlanFeatureMarkdown_WebApiCs.ps1'
                'promptCreatePlanFeatureMarkdownPs.ps1'
                'promptImplementFeature_ThisProject.ps1'
                'promptImplementFeature_WebApiCs.ps1'
                'promptImplementStory_ThisProject.ps1'
            )
        }

        It 'should all exist as files' {
            foreach ($script in $promptScripts) {
                $scriptPath = Join-Path $DOCS_DIR $script
                Test-Path $scriptPath -PathType Leaf | Should Be $true -Because "$script should exist in $DOCS_DIR"
            }
        }

        It 'should all have proper help sections' {
            foreach ($script in $promptScripts) {
                $scriptPath = Join-Path $DOCS_DIR $script
                $content = Get-Content $scriptPath -Raw
                # Should have .SYNOPSIS and .DESCRIPTION
                $content | Should Match '\.SYNOPSIS' -Because "$script should have a SYNOPSIS"
                $content | Should Match '\.DESCRIPTION' -Because "$script should have a DESCRIPTION"
            }
        }

        It 'should use strict mode and error action preferences' {
            foreach ($script in $promptScripts) {
                $scriptPath = Join-Path $DOCS_DIR $script
                $content = Get-Content $scriptPath -Raw
                $content | Should Match "Set-StrictMode -Version.*Latest" -Because "$script should use Set-StrictMode"
                $content | Should Match '\$ErrorActionPreference = .Stop.' -Because "$script should set error action to Stop"
            }
        }
    }
}

