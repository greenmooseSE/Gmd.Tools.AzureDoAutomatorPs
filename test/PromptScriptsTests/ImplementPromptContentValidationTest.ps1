#Requires -Version 7.0

<#
.SYNOPSIS
AC tests for implementation prompt scripts content validation.

.DESCRIPTION
Verifies that promptImplement*.ps1 scripts contain ONLY implementation rules
and do NOT contain creation/planning rules from createStory* files.

This tests the fix for the issue where promptImplementStory_ThisProject.ps1 and
promptImplementFeature_ThisProject.ps1 were incorrectly including:
- createStoryRules_General.md
- createStoryRules_ThisProject.md

Run with: Invoke-Pester .\test\PromptScriptsTests\ImplementPromptContentValidationTest.ps1
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

[string]$REPO_ROOT = Resolve-Path (Join-Path $PSScriptRoot '../../')
[string]$DOCS_DIR = Join-Path $REPO_ROOT 'docs'

Describe 'Implementation Prompt Scripts — Content Validation' {
    Context 'promptImplementStory_ThisProject.ps1 — No Creation Rules' {
        BeforeAll {
            $scriptPath = Join-Path $DOCS_DIR 'promptImplementStory_ThisProject.ps1'
            $testStoryId = 2695
            $testFeatureId = 2694
            $testPlanFile = 'docs\plans\plan-1577-unambiguousFieldSyntax.md'
        }

        It 'should NOT include "General Story Rules" section header' {
            $output = & $scriptPath -StoryId $testStoryId -FeatureId $testFeatureId -PlanFile $testPlanFile
            # The creation rules should NOT be in implementation prompt
            $output | Should Not Match '## General Story Rules'
        }

        It 'should NOT include "Project-Specific Story Rules" section header' {
            $output = & $scriptPath -StoryId $testStoryId -FeatureId $testFeatureId -PlanFile $testPlanFile
            $output | Should Not Match '## Project-Specific Story Rules \(AzureDoAutomatorPs\)'
        }

        It 'should NOT include content from createStoryRules_General.md' {
            $output = & $scriptPath -StoryId $testStoryId
            # Content unique to createStoryRules_General.md
            $output | Should Not Match 'One story should contain the full scope for a unit of work'
            $output | Should Not Match 'Story fields to set'
            $output | Should Not Match 'Read-only story fields'
        }

        It 'should NOT include content from createStoryRules_ThisProject.md' {
            $output = & $scriptPath -StoryId $testStoryId
            # Content unique to createStoryRules_ThisProject.md
            $output | Should Not Match 'For test work items.*Use `testWi` tag'
            $output | Should Not Match 'Acceptance Criteria.*PowerShell-specific'
        }

        It 'SHOULD include "Story Implementation Rules" section' {
            $output = & $scriptPath -StoryId $testStoryId
            $output | Should Match '## Story Implementation Rules'
        }

        It 'SHOULD include "Architectural Rules" section' {
            $output = & $scriptPath -StoryId $testStoryId
            $output | Should Match '## Architectural Rules'
        }

        It 'SHOULD include implementation rule content (Org/Proj/PAT)' {
            $output = & $scriptPath -StoryId $testStoryId
            $output | Should Match '\$env:GMD_AZDO_ORGANIZATION'
            $output | Should Match '\$env:GMD_AZDO_PROJECT'
            $output | Should Match '\$env:GMD_AZDO_MACHINE_WORKITEMSRW'
        }

        It 'SHOULD include Pester/testing requirements for implementation' {
            $output = & $scriptPath -StoryId $testStoryId
            $output | Should Match 'Testing Requirements'
            $output | Should Match 'Pester'
            $output | Should Match 'Test work item lifecycle'
        }
    }

    Context 'promptImplementFeature_ThisProject.ps1 — No Creation Rules' {
        BeforeAll {
            $scriptPath = Join-Path $DOCS_DIR 'promptImplementFeature_ThisProject.ps1'
            $testFeatureId = 1590
            $testTitle = 'exportImportHierarchy'
            $testPlanFile = 'docs\plans\plan-1577-unambiguousFieldSyntax.md'
        }

        It 'should NOT include "General Story Rules" section header' {
            $output = & $scriptPath -FeatureId $testFeatureId -FeatureTitle $testTitle -PlanFile $testPlanFile
            $output | Should Not Match '## General Story Rules'
        }

        It 'should NOT include "Project-Specific Story Rules" section header' {
            $output = & $scriptPath -FeatureId $testFeatureId -FeatureTitle $testTitle -PlanFile $testPlanFile
            $output | Should Not Match '## Project-Specific Story Rules \(AzureDoAutomatorPs\)'
        }

        It 'should NOT include content from createStoryRules_General.md' {
            $output = & $scriptPath -FeatureId $testFeatureId -FeatureTitle $testTitle -PlanFile $testPlanFile
            $output | Should Not Match 'One story should contain the full scope for a unit of work'
            $output | Should Not Match 'Story fields to set'
        }

        It 'should NOT include content from createStoryRules_ThisProject.md' {
            $output = & $scriptPath -FeatureId $testFeatureId -FeatureTitle $testTitle -PlanFile $testPlanFile
            $output | Should Not Match 'For test work items.*Use `testWi` tag'
        }

        It 'SHOULD include "Story Implementation Rules" section' {
            $output = & $scriptPath -FeatureId $testFeatureId -FeatureTitle $testTitle -PlanFile $testPlanFile
            $output | Should Match '## Story Implementation Rules'
        }

        It 'SHOULD include "Architectural Rules" section' {
            $output = & $scriptPath -FeatureId $testFeatureId -FeatureTitle $testTitle -PlanFile $testPlanFile
            $output | Should Match '## Architectural Rules'
        }

        It 'SHOULD include "Multi-Story Process" section' {
            $output = & $scriptPath -FeatureId $testFeatureId -FeatureTitle $testTitle -PlanFile $testPlanFile
            $output | Should Match '## Multi-Story Process'
        }

        It 'SHOULD include branching strategy for multiple stories' {
            $output = & $scriptPath -FeatureId $testFeatureId -FeatureTitle $testTitle -PlanFile $testPlanFile
            $output | Should Match 'Branching Strategy'
            $output | Should Match 'Feature branch'
            $output | Should Match 'Story branches'
        }

        It 'SHOULD include Pester/testing requirements' {
            $output = & $scriptPath -FeatureId $testFeatureId -FeatureTitle $testTitle -PlanFile $testPlanFile
            $output | Should Match 'Testing Requirements'
            $output | Should Match 'Pester'
        }
    }

    Context 'Implementation vs Creation Script Separation' {
        BeforeAll {
            $implStoryScript = Join-Path $DOCS_DIR 'promptImplementStory_ThisProject.ps1'
            $implFeatureScript = Join-Path $DOCS_DIR 'promptImplementFeature_ThisProject.ps1'
            $createPlanScript = Join-Path $DOCS_DIR 'promptCreatePlanFeatureMarkdown_ThisProject.ps1'
            $testStoryId = 2695
            $testFeatureId = 1590
            $testTitle = 'exportImportHierarchy'
            $testPlanFile = 'docs\plans\plan-1577-unambiguousFieldSyntax.md'
        }

        It 'creation plan script SHOULD include story rules (for planning)' {
            $output = & $createPlanScript -EpicId 1305
            # Creation plan scripts SHOULD include these sections
            $output | Should Match 'Story fields to set'
            $output | Should Match 'One story should contain the full scope'
        }

        It 'implementation story script should NOT include story rules (only impl rules)' {
            $output = & $implStoryScript -StoryId $testStoryId -FeatureId $testFeatureId
            $output | Should Not Match '## General Story Rules'
            $output | Should Match '## Story Implementation Rules'
        }

        It 'implementation feature script should NOT include creation story rules' {
            $output = & $implFeatureScript -FeatureId $testFeatureId -FeatureTitle $testTitle -PlanFile $testPlanFile
            $output | Should Not Match '## General Story Rules'
            $output | Should Match '## Story Implementation Rules'
        }
    }
}
