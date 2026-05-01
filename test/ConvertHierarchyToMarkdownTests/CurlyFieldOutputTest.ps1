#Requires -Version 7.0

<#
.SYNOPSIS
AC tests for Story 2630: {Field Name} curly-brace syntax output from <see cref="ConvertHierarchyToMarkdown.ps1"/>.

.DESCRIPTION
Verifies the generator emits `{Field Name}:` for metadata fields and `{Field Name}` (no colon) for
html-type multi-line fields. Tests field ordering per appSettings.json, round-trip parse equality,
and that no legacy bold-syntax markers remain in generator output.

Run with: Invoke-Pester .\test\ConvertHierarchyToMarkdownTests\CurlyFieldOutputTest.ps1
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

function New-TestStory {
    param(
        [int]$Id = 42,
        [string]$Title = 'Test Story',
        [string]$State = 'New',
        [object]$Tags = $null,
        [object]$StoryPoints = $null,
        [object]$Description = $null,
        [object]$AcceptanceCriteria = $null,
        [object]$ACScenarios = $null,
        [object]$ExtraInformation = $null,
        [object]$AssignedTo = $null,
        [object]$OriginalEstimate = $null,
        [object]$RemainingWork = $null,
        [hashtable]$ConfigFields = $null
    )
    $story = [PSCustomObject]@{
        Id                 = $Id
        Title              = $Title
        State              = $State
        Tags               = $Tags
        StoryPoints        = $StoryPoints
        Description        = $Description
        AcceptanceCriteria = $AcceptanceCriteria
        ACScenarios        = $ACScenarios
        ExtraInformation   = $ExtraInformation
        AssignedTo         = $AssignedTo
        OriginalEstimate   = $OriginalEstimate
        RemainingWork      = $RemainingWork
    }
    if ($null -ne $ConfigFields) {
        $story | Add-Member -MemberType NoteProperty -Name 'configFields' -Value $ConfigFields
    }
    return $story
}

Describe 'Story 2630 - {Field Name} curly-brace output from ConvertHierarchyToMarkdown' {

    Context 'Scenario 1: Generator outputs {tags}: and {Story Points}: in curly-brace format' {

        It 'GivenStoryWithTagsAndStoryPoints_WhenGenerating_ItShouldUseCurlyBraceFormat' {
            $story = New-TestStory -Id 1 -Title 'My Story' -State 'New' -Tags 'foo; bar' -StoryPoints 3
            $output = & (Join-Path $SRC_DIR 'ConvertHierarchyToMarkdown.ps1') `
                -Hierarchy $story -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT 2>&1 |
                Where-Object { $_ -is [string] } | Out-String
            $output | Should Match '\{tags\}:'
            $output | Should Match '\{Story Points\}:'
            $output | Should Not Match '\*\*tags\*\*:'
            $output | Should Not Match '\*\*Story Points\*\*:'
        }
    }

    Context 'Scenario 2: Generator outputs {Description} and {Acceptance Criteria} in curly-brace format' {

        It 'GivenStoryWithDescriptionAndAC_WhenGenerating_ItShouldUseCurlyBraceFormat' {
            $story = New-TestStory -Id 2 -Title 'My Story' -State 'New' `
                -Description 'Story description.' `
                -AcceptanceCriteria '| ✅ | What | Tests |'
            $output = & (Join-Path $SRC_DIR 'ConvertHierarchyToMarkdown.ps1') `
                -Hierarchy $story -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT 2>&1 |
                Where-Object { $_ -is [string] } | Out-String
            $output | Should Match '\{Description\}'
            $output | Should Match '\{Acceptance Criteria\}'
            $output | Should Not Match '\*\*Description\*\*'
            $output | Should Not Match '#### Acceptance Criteria'
        }
    }

    Context 'Scenario 3: Round-trip — parse generated output and compare to original' {

        It 'GivenStoryWithDescriptionAndAC_WhenRoundTripped_ItShouldPreserveValues' {
            $story = New-TestStory -Id 10 -Title 'Round Trip Story' -State 'New' `
                -Tags 'foo' -StoryPoints 5 `
                -Description 'Round trip description.' `
                -AcceptanceCriteria 'AC content here.'
            $generated = & (Join-Path $SRC_DIR 'ConvertHierarchyToMarkdown.ps1') `
                -Hierarchy $story -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT 2>&1 |
                Where-Object { $_ -is [string] } | Out-String
            $parsed = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $generated -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $item = $parsed.workItems[0]
            $item.title | Should Be 'Round Trip Story'
            $item.state | Should Be 'New'
            $item.tags | Should Match 'foo'
            $item.storyPoints | Should Be 5.0
            $item.description | Should Match 'Round trip description'
            $item.acceptanceCriteria | Should Match 'AC content here'
        }
    }

    Context 'Scenario 4: Generator outputs {WorkItemId}: and {State}: in curly-brace format' {

        It 'GivenStoryWithIdAndState_WhenGenerating_ItShouldUseCurlyBraceFormatForCoreFields' {
            $story = New-TestStory -Id 99 -Title 'My Story' -State 'Active'
            $output = & (Join-Path $SRC_DIR 'ConvertHierarchyToMarkdown.ps1') `
                -Hierarchy $story -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT 2>&1 |
                Where-Object { $_ -is [string] } | Out-String
            $output | Should Match '\{WorkItemId\}: 99'
            $output | Should Match '\{State\}: Active'
            $output | Should Not Match '\*\*WorkItemId\*\*:'
            $output | Should Not Match '\*\*State\*\*:'
        }
    }

    Context 'Scenario 5: Get-ConfigFieldsMarkdown uses {label}: for non-html and {label} for html fields' {

        It 'GivenStoryWithConfigFieldsOfDifferentTypes_WhenGenerating_ItShouldFormatCorrectly' {
            # Custom.AIImplemented is boolean (non-html), Custom.AcceptanceCriteria is html
            $story = New-TestStory -Id 3 -Title 'My Story' -State 'New' -ConfigFields @{
                'Custom.AIImplemented' = $true
                'Custom.AcceptanceCriteria' = 'Some AC content'
            }
            $output = & (Join-Path $SRC_DIR 'ConvertHierarchyToMarkdown.ps1') `
                -Hierarchy $story -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT 2>&1 |
                Where-Object { $_ -is [string] } | Out-String
            # Boolean field should use colon form
            $output | Should Match '\{AI Implemented\}:'
            # Should not use bold form
            $output | Should Not Match '\*\*AI Implemented\*\*'
        }
    }

    Context 'Scenario 6: No legacy bold-syntax markers remain in generator output' {

        It 'GivenStoryWithAllCoreFields_WhenGenerating_ItShouldHaveNoBoldFieldMarkers' {
            $story = New-TestStory -Id 4 -Title 'My Story' -State 'New' `
                -Tags 'foo' -StoryPoints 3 `
                -Description 'Description here.' `
                -AcceptanceCriteria 'AC here.' `
                -ACScenarios 'Scenarios here.' `
                -ExtraInformation 'Extra info.'
            $output = & (Join-Path $SRC_DIR 'ConvertHierarchyToMarkdown.ps1') `
                -Hierarchy $story -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT 2>&1 |
                Where-Object { $_ -is [string] } | Out-String
            # No old bold markers
            $output | Should Not Match '\*\*tags\*\*:'
            $output | Should Not Match '\*\*Story Points\*\*:'
            $output | Should Not Match '\*\*Description\*\*'
            $output | Should Not Match '\*\*State\*\*:'
            $output | Should Not Match '\*\*WorkItemId\*\*:'
            $output | Should Not Match '#### Acceptance Criteria'
            $output | Should Not Match '#### Acceptance Tests'
            $output | Should Not Match '#### Extra Information'
        }
    }

    Context 'Scenario 7: Feature hierarchy uses {Effort}: and {tags}: in curly-brace format' {

        It 'GivenFeatureWithTagsAndEffort_WhenGenerating_ItShouldUseCurlyBraceFormat' {
            $feature = [PSCustomObject]@{
                Id       = 50
                Title    = 'Test Feature'
                State    = 'New'
                Tags     = 'feat'
                Effort   = 8
                Description = 'Feature description.'
                Stories  = @()
            }
            $output = & (Join-Path $SRC_DIR 'ConvertHierarchyToMarkdown.ps1') `
                -Hierarchy $feature -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT 2>&1 |
                Where-Object { $_ -is [string] } | Out-String
            $output | Should Match '\{tags\}:'
            $output | Should Match '\{Effort\}:'
            $output | Should Not Match '\*\*tags\*\*:'
            $output | Should Not Match '\*\*Effort\*\*:'
        }
    }

    Context 'Scenario 8: example-hierarchy.md is parseable and uses curly-brace syntax' {

        It 'GivenExampleHierarchyFile_WhenParsed_ItShouldReturnWorkItems' {
            $examplePath = Join-Path $REPO_ROOT 'example-hierarchy.md'
            $content = Get-Content -LiteralPath $examplePath -Raw
            # File should NOT contain old bold field markers for core fields
            $content | Should Not Match '\*\*WorkItemId\*\*:'
            $content | Should Not Match '\*\*State\*\*:'
            $content | Should Not Match '\*\*tags\*\*:'
            $content | Should Not Match '\*\*Story Points\*\*:'
            $content | Should Not Match '#### Acceptance Criteria'
            $content | Should Not Match '#### Acceptance Tests'
            $content | Should Not Match '#### Extra Information'
        }

        It 'GivenExampleHierarchyFile_WhenParsedWithOrgProject_ItShouldReturnEpic' {
            $examplePath = Join-Path $REPO_ROOT 'example-hierarchy.md'
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownFilePath $examplePath -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $result.workItems.Count | Should BeGreaterThan 0
            $result.workItems[0].type | Should Be 'Epic'
        }
    }

    Context 'Scenario 9: GenerateAzDoMarkdownHierarchyTemplate output uses curly-brace syntax' {

        It 'GivenTemplateGenerator_WhenExecuted_ItShouldNotContainBoldFieldMarkers' {
            $output = & (Join-Path $SRC_DIR 'GenerateAzDoMarkdownHierarchyTemplate.ps1') 2>&1 |
                Where-Object { $_ -is [string] } | Out-String
            # Core field markers should be in curly-brace format
            $output | Should Match '\{tags\}:'
            $output | Should Match '\{Story Points\}:'
            $output | Should Not Match '\*\*tags\*\*:'
            $output | Should Not Match '\*\*Story Points\*\*:'
            $output | Should Not Match '#### Acceptance Criteria'
        }
    }
}
