#Requires -Version 7.0

<#
.SYNOPSIS
AC tests for Story 2629: {Field Name} curly-brace syntax support in <see cref="ConvertMarkdownToHierarchyJson.ps1"/>.

.DESCRIPTION
Verifies all three curly-brace forms (bare, bold-wrapped, header-style) are recognised as field
markers. Confirms config-driven label resolution via appSettings.json, unknown labels treated as
literal content, and multi-line html fields terminated at next known marker.

Run with: Invoke-Pester .\test\ConvertMarkdownToHierarchyJsonTests\CurlyFieldSyntaxTest.ps1
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

Describe 'Story 2629 - {Field Name} curly-brace syntax in ConvertMarkdownToHierarchyJson' {

    Context 'Scenario 1: Single-line fields with bare curly-brace syntax' {

        It 'GivenBareTagsAndStoryPoints_WhenParsing_ItShouldParseTagsAndStoryPoints' {
            # Scenario 1: {tags}: foo, bar and {Story Points}: 3 parsed correctly
            $md = @"
### Story: My Story
{tags}: foo, bar
{Story Points}: 3
{Description}
A story
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $item = $result.workItems[0]
            $item.tags | Should Be 'foo, bar'
            $item.storyPoints | Should Be 3.0
        }
    }

    Context 'Scenario 2: Multi-line description terminates at next known field marker' {

        It 'GivenDescriptionFollowedByAcceptanceCriteria_WhenParsing_ItShouldNotCrossContaminate' {
            # Scenario 2: description contains only prose; AC only the table
            $md = @"
### Story: My Story
{Description}
Line one of description.
Line two of description.
Line three of description.
{Acceptance Criteria}
| Column | Value |
| --- | --- |
| Row1 | Data |
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $item = $result.workItems[0]
            $item.description | Should Be "Line one of description.`nLine two of description.`nLine three of description."
            # Custom.AcceptanceCriteria is promoted to the top-level acceptanceCriteria property
            $item.acceptanceCriteria | Should Match '\| Column \| Value \|'
            $item.acceptanceCriteria | Should Not Match 'Line one of description'
        }
    }

    Context 'Scenario 3: Known {Field Name} inside description terminates description collection' {

        It 'GivenDescriptionThenStoryAcceptanceTests_WhenParsing_ItShouldSeparateFields' {
            # Scenario 3: description does not include the SAT content
            $md = @"
### Story: My Story
{Description}
Description prose here.
{Story Acceptance Tests}
- [ ] **Test 1: Some test**
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $item = $result.workItems[0]
            $item.description | Should Not Match '\*\*Test 1'
            $item.configFields['Custom.StoryAcceptanceTests'] | Should Match 'Test 1'
        }
    }

    Context 'Scenario 4: Bold headers inside description are captured as description content' {

        It 'GivenHashHeaderInsideDescription_WhenParsing_ItShouldBeInDescription' {
            # Scenario 4: ### header inside description body is content, not a field boundary
            $md = @"
### Story: My Story
{Description}
### Some Internal Header
More prose after internal header.
{Acceptance Criteria}
The AC content.
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $item = $result.workItems[0]
            $item.description | Should Match '### Some Internal Header'
            $item.description | Should Match 'More prose after internal header'
        }
    }

    Context 'Scenario 5: Unknown {FieldLabel} stops description collection (Bug 2707)' {

        It 'GivenUnknownCurlyLabel_WhenInDescription_ItShouldStopCollectionAndNotAbsorbContent' {
            # Bug 2707: {NonExistentField} not in appSettings.json → stops description collecting;
            # the marker line itself and any subsequent content are NOT added to the description buffer.
            $md = @"
### Story: My Story
{Description}
Normal description text.
{NonExistentField}: value
More description text.
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $item = $result.workItems[0]
            # Description should contain only text before the unknown marker
            $item.description | Should Match 'Normal description text'
            $item.description | Should Not Match '\{NonExistentField\}: value'
            $item.description | Should Not Match 'More description text'
            # No separate field should be created
            $cfgFields = if ($item -is [hashtable]) { $item['configFields'] } else { $item.configFields }
            ($null -eq $cfgFields -or -not $cfgFields.ContainsKey('NonExistentField')) | Should Be $true
        }
    }

    Context 'Scenario 6: Bold-wrapped **{FieldName}** form recognised as field marker' {

        It 'GivenBoldWrappedFieldMarkers_WhenParsing_ItShouldParseCorrectly' {
            # Scenario 6: **{Story Points}**: 5 and **{Description}** prose
            $md = @"
### Story: My Story
**{Story Points}**: 5
**{Description}**
Bold-wrapped description prose.
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $item = $result.workItems[0]
            $item.storyPoints | Should Be 5.0
            $item.description | Should Match 'Bold-wrapped description prose'
        }
    }

    Context 'Scenario 7: Header-style ## {FieldName} form recognised as field marker' {

        It 'GivenHeaderStyleFieldMarker_WhenParsing_ItShouldParseDescription' {
            # Scenario 7: ## {Description} followed by prose
            $md = @"
### Story: My Story
## {Description}
Header-style description prose.
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $item = $result.workItems[0]
            $item.description | Should Match 'Header-style description prose'
        }
    }

    Context 'Scenario 8: All field handling is data-driven from appSettings.json' {

        It 'GivenMultipleCoreFields_WhenParsing_ItShouldResolveAllThroughConfig' {
            # Scenario 8: workItemId, state, tags, storyPoints all resolved via config
            $md = @"
### Story: My Story
{WorkItemId}: 123
{State}: Active
{tags}: foo
{Story Points}: 3
{Description}
Story desc
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $item = $result.workItems[0]
            $item.workItemId | Should Be 123
            $item.state | Should Be 'Active'
            $item.tags | Should Be 'foo'
            $item.storyPoints | Should Be 3.0
        }
    }

    Context 'AC: StoryAcceptanceTests and FeatureAcceptanceTests stored in configFields' {

        It 'GivenStoryAcceptanceTestsAfterDescription_WhenParsing_ItShouldBeInConfigFields' {
            $md = @"
### Story: My Story
{Description}
Story description here.
{Story Acceptance Tests}
- [ ] **Test 1: Some scenario**
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $item = $result.workItems[0]
            $item.configFields['Custom.StoryAcceptanceTests'] | Should Match 'Test 1'
            $item.configFields['Custom.StoryAcceptanceTests'] | Should Not Match 'Story description here'
        }

        It 'GivenFeatureAcceptanceTestsAfterDescription_WhenParsing_ItShouldBeInConfigFields' {
            $md = @"
## Feature: My Feature
{Description}
Feature description here.
{Feature Acceptance Tests}
- [ ] **Test 1: Feature test**
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $item = $result.workItems[0]
            $item.configFields['Custom.FeatureAcceptanceTests'] | Should Match 'Test 1'
            $item.configFields['Custom.FeatureAcceptanceTests'] | Should Not Match 'Feature description here'
        }
    }

    Context 'AC: WorkItemId resolved through appSettings.json, not hardcoded' {

        It 'GivenWorkItemIdField_WhenParsing_ItShouldSetWorkItemIdProperty' {
            $md = @"
### Story: My Story
{WorkItemId}: 123
{Description}
A story
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $item = $result.workItems[0]
            $item.workItemId | Should Be 123
            # System.Id must NOT be duplicated in configFields
            $cfgFields = if ($item -is [hashtable]) { $item['configFields'] } else { $item.configFields }
            ($null -eq $cfgFields -or -not $cfgFields.ContainsKey('System.Id')) | Should Be $true
        }
    }

    Context 'AC: Description-collecting mode terminated by known field marker in custom-field mode' {

        It 'GivenKnownFieldInsideCustomFieldCollection_WhenParsing_ItShouldTerminateCollection' {
            # Collecting inside AC field, then next known field starts
            $md = @"
### Story: My Story
{Description}
Description content.
{Acceptance Criteria}
AC line one.
AC line two.
{Extra Information}
Extra info here.
"@
            $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                -MarkdownContent $md -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
            $item = $result.workItems[0]
            $item.description | Should Match 'Description content'
            # Custom.AcceptanceCriteria and Custom.ExtraInformation are promoted to top-level properties
            $item.acceptanceCriteria | Should Match 'AC line one'
            $item.acceptanceCriteria | Should Not Match 'Extra info'
            $item.extraInformation | Should Match 'Extra info here'
        }
    }
}
