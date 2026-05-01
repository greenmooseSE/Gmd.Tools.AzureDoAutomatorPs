#Requires -Version 7.0

<#
.SYNOPSIS
Tests for ConvertMarkdownToHierarchyJson parsing logic using the {Field Name} curly-brace syntax.
- Parser recognises {Field Name}, **{Field Name}**, and ## {Field Name} markers
- Fields resolved through appSettings.json (config-driven)
- Bold-formatted lines inside collecting fields are treated as content, not field boundaries
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"

[string]$REPO_ROOT = Resolve-Path (Join-Path $PSScriptRoot '../')
[string]$SRC_DIR   = Join-Path $REPO_ROOT 'src'

if (-not (Get-Command "ssLogIt.ps1" -ErrorAction SilentlyContinue)) {
    function global:ssLogIt.ps1 {
        param([string]$Level, [string]$Message, [object]$Exception)
    }
}

Describe "ConvertMarkdownToHierarchyJson parser" {

    Context "Core field parsing via {Field Name} syntax" {

        It "GivenCurlyBraceFields_WhenParsing_ItShouldParseDescriptionTagsAndHierarchy" {
            [string]$markdown = @"
# Epic: Test Epic
{tags}: test
{Description}
This is the epic description

## Feature: Test Feature
{tags}: test
{Description}
This is the feature description

### Story: Test Story
{tags}: test
{Story Points}: 3
{Description}
This is the story description
"@
            $markdownPath = [System.IO.Path]::GetTempFileName() + ".md"
            $markdown | Set-Content -LiteralPath $markdownPath
            try {
                $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                    -MarkdownFilePath $markdownPath -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
                $result.workItems.Count | Should Be 1
                $result.workItems[0].description | Should Be "This is the epic description"
                $result.workItems[0].children.Count | Should Be 1
                $result.workItems[0].children[0].description | Should Be "This is the feature description"
                $result.workItems[0].children[0].children.Count | Should Be 1
                $result.workItems[0].children[0].children[0].description | Should Be "This is the story description"
                $result.workItems[0].children[0].children[0].storyPoints | Should Be 3.0
            }
            finally { Remove-Item -LiteralPath $markdownPath -ErrorAction SilentlyContinue }
        }

        It "GivenCurlyBraceTags_WhenParsing_ItShouldParseTitlesAndTags" {
            [string]$markdown = @"
# Epic: Management System
{tags}: core, platform
{Description}
Main management epic

## Feature: User Authentication
{tags}: security, authentication
{Description}
User login and session management
"@
            $markdownPath = [System.IO.Path]::GetTempFileName() + ".md"
            $markdown | Set-Content -LiteralPath $markdownPath
            try {
                $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                    -MarkdownFilePath $markdownPath -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
                $result.workItems[0].title | Should Be "Management System"
                ($result.workItems[0].tags -match "core") | Should Be $true
                ($result.workItems[0].tags -match "platform") | Should Be $true
                $result.workItems[0].children[0].title | Should Be "User Authentication"
                ($result.workItems[0].children[0].tags -match "security") | Should Be $true
                ($result.workItems[0].children[0].tags -match "authentication") | Should Be $true
            }
            finally { Remove-Item -LiteralPath $markdownPath -ErrorAction SilentlyContinue }
        }

        It "GivenInlineDescriptionValue_WhenParsing_ItShouldParseDescriptionFromInlineValue" {
            [string]$markdown = @"
# Epic: Inline Format
{tags}: test
{Description}: This is an inline description with value

## Feature: Inline Feature
{tags}: test
{Description}: Feature description inline
"@
            $markdownPath = [System.IO.Path]::GetTempFileName() + ".md"
            $markdown | Set-Content -LiteralPath $markdownPath
            try {
                $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                    -MarkdownFilePath $markdownPath -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
                $result.workItems[0].description | Should Be "This is an inline description with value"
                $result.workItems[0].children[0].description | Should Be "Feature description inline"
            }
            finally { Remove-Item -LiteralPath $markdownPath -ErrorAction SilentlyContinue }
        }

        It "GivenMultipleWorkItemTypes_WhenParsing_ItShouldParseAllCoreFields" {
            [string]$markdown = @"
# Epic: Mixed
{tags}: test
{Description}
Epic desc

## Feature: Mixed Feature
{tags}: test
{Description}
Feature desc

### Story: Mixed Story
{tags}: test
{Story Points}: 3
{Description}
Without colon again
"@
            $markdownPath = [System.IO.Path]::GetTempFileName() + ".md"
            $markdown | Set-Content -LiteralPath $markdownPath
            try {
                $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                    -MarkdownFilePath $markdownPath -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
                $result.workItems[0].description | Should Be "Epic desc"
                $result.workItems[0].children[0].description | Should Be "Feature desc"
                $result.workItems[0].children[0].children[0].description | Should Be "Without colon again"
                $result.workItems[0].children[0].children[0].storyPoints | Should Be 3.0
            }
            finally { Remove-Item -LiteralPath $markdownPath -ErrorAction SilentlyContinue }
        }
    }

    Context "Bold-formatted lines inside collecting fields are treated as content" {

        It "GivenBoldLinesInDescription_WhenParsing_ItShouldPreserveBoldAsContent" {
            [string]$markdown = @"
### Story: Story With Bold In Description
{WorkItemId}: 999
{State}: Active
{Description}
Here is a description with bold content.
**Foo**: bar
More text after the bold field.
**Another**: bold line here
Final line.
"@
            $markdownPath = [System.IO.Path]::GetTempFileName() + ".md"
            $markdown | Set-Content -LiteralPath $markdownPath
            try {
                $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                    -MarkdownFilePath $markdownPath -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
                $story = $result.workItems[0]
                $story.workItemId | Should Be 999
                $story.state | Should Be "Active"
                ($story.description -match "Here is a description") | Should Be $true
                ($story.description -match [regex]::Escape("**Foo**: bar")) | Should Be $true
                ($story.description -match "More text after the bold field") | Should Be $true
                ($story.description -match [regex]::Escape("**Another**: bold line here")) | Should Be $true
                ($story.description -match "Final line") | Should Be $true
            }
            finally { Remove-Item -LiteralPath $markdownPath -ErrorAction SilentlyContinue }
        }

        It "GivenBoldLinesInAcceptanceCriteria_WhenParsing_ItShouldPreserveBoldAsContent" {
            [string]$markdown = @"
### Story: Story With Bold In AC
{WorkItemId}: 998
{State}: Active
{Description}
Normal description.

{Acceptance Criteria}
Verify that the system works.
**Given**: a user is logged in
**When**: they click submit
**Then**: the form is saved
"@
            $markdownPath = [System.IO.Path]::GetTempFileName() + ".md"
            $markdown | Set-Content -LiteralPath $markdownPath
            try {
                $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                    -MarkdownFilePath $markdownPath -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
                $story = $result.workItems[0]
                $story.ContainsKey("acceptanceCriteria") | Should Be $true
                ($story.acceptanceCriteria -match "Verify that the system works") | Should Be $true
                ($story.acceptanceCriteria -match [regex]::Escape("**Given**: a user is logged in")) | Should Be $true
                ($story.acceptanceCriteria -match [regex]::Escape("**When**: they click submit")) | Should Be $true
                ($story.acceptanceCriteria -match [regex]::Escape("**Then**: the form is saved")) | Should Be $true
            }
            finally { Remove-Item -LiteralPath $markdownPath -ErrorAction SilentlyContinue }
        }

        It "GivenMetadataFieldsBeforeDescriptionWithBoldInside_WhenParsing_ItShouldParseBothCorrectly" {
            [string]$markdown = @"
### Story: Full Metadata Story
{WorkItemId}: 997
{tags}: tag1; tag2
{Story Points}: 5
{State}: Active
{Description}
This is the description.
**Bold Section**: value in description
More description text.
"@
            $markdownPath = [System.IO.Path]::GetTempFileName() + ".md"
            $markdown | Set-Content -LiteralPath $markdownPath
            try {
                $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                    -MarkdownFilePath $markdownPath -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
                $story = $result.workItems[0]
                $story.workItemId | Should Be 997
                ($story.tags -match "tag1") | Should Be $true
                $story.storyPoints | Should Be 5
                $story.state | Should Be "Active"
                ($story.description -match "This is the description") | Should Be $true
                ($story.description -match [regex]::Escape("**Bold Section**: value in description")) | Should Be $true
                ($story.description -match "More description text") | Should Be $true
            }
            finally { Remove-Item -LiteralPath $markdownPath -ErrorAction SilentlyContinue }
        }

        It "GivenBoldLinesInDescriptionAcrossAllTypes_WhenParsing_ItShouldPreserveInEach" {
            [string]$markdown = @"
# Epic: Bold Epic
{WorkItemId}: 100
{State}: Active
{Description}
Epic desc **Bold**: epic value more

## Feature: Bold Feature
{WorkItemId}: 200
{State}: Active
{Description}
Feature desc **Bold**: feature value more

### Story: Bold Story
{WorkItemId}: 300
{State}: Active
{Description}
Story desc **Bold**: story value more

#### Bug: Bold Bug
{WorkItemId}: 400
{State}: Active
{Description}
Bug desc **Bold**: bug value more

#### Task: Bold Task
{WorkItemId}: 500
{State}: Active
{Description}
Task desc **Bold**: task value more
"@
            $markdownPath = [System.IO.Path]::GetTempFileName() + ".md"
            $markdown | Set-Content -LiteralPath $markdownPath
            try {
                $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                    -MarkdownFilePath $markdownPath -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
                $epic    = $result.workItems[0]
                $feature = $epic.children[0]
                $story   = $feature.children[0]
                $bug     = $story.children[0]
                $task    = $story.children[1]
                ($epic.description    -match [regex]::Escape("**Bold**: epic value")) | Should Be $true
                ($feature.description -match [regex]::Escape("**Bold**: feature value")) | Should Be $true
                ($story.description   -match [regex]::Escape("**Bold**: story value")) | Should Be $true
                ($bug.description     -match [regex]::Escape("**Bold**: bug value")) | Should Be $true
                ($task.description    -match [regex]::Escape("**Bold**: task value")) | Should Be $true
            }
            finally { Remove-Item -LiteralPath $markdownPath -ErrorAction SilentlyContinue }
        }

        It "GivenBoldLinesInAcceptanceTests_WhenParsing_ItShouldPreserveBoldAsContent" {
            [string]$markdown = @"
### Story: Bold In Acceptance Tests
{WorkItemId}: 996
{State}: Active

{Acceptance Tests}
**Scenario 1**: happy path
User opens the app
**Expected**: app loads successfully

**Scenario 2**: error path
Server returns 500
**Expected**: friendly error message
"@
            $markdownPath = [System.IO.Path]::GetTempFileName() + ".md"
            $markdown | Set-Content -LiteralPath $markdownPath
            try {
                $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                    -MarkdownFilePath $markdownPath -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
                $story = $result.workItems[0]
                $story.ContainsKey("acceptanceTests") | Should Be $true
                ($story.acceptanceTests -match [regex]::Escape("**Scenario 1**: happy path")) | Should Be $true
                ($story.acceptanceTests -match [regex]::Escape("**Expected**: app loads successfully")) | Should Be $true
                ($story.acceptanceTests -match [regex]::Escape("**Scenario 2**: error path")) | Should Be $true
                ($story.acceptanceTests -match [regex]::Escape("**Expected**: friendly error message")) | Should Be $true
            }
            finally { Remove-Item -LiteralPath $markdownPath -ErrorAction SilentlyContinue }
        }
    }

    Context "Angle-bracket entity preservation (&lt; stays as &lt; in parsed output)" {

        It "GivenLtEntityInDescription_WhenParsing_ItShouldPreserveLtEntity" {
            # The parser must NOT decode &lt; -> < because AzDo already handles the entity
            # correctly when it receives &lt;StmtsDir> in the HTML description field.
            [string]$markdown = @"
### Story: Path Story
{WorkItemId}: 900
{State}: Active
{Description}
Per-account directory structure under &lt;StmtsDir>/&lt;AccountName>/yyyy-MM.json
"@
            $markdownPath = [System.IO.Path]::GetTempFileName() + ".md"
            $markdown | Set-Content -LiteralPath $markdownPath
            try {
                $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                    -MarkdownFilePath $markdownPath -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
                $story = $result.workItems[0]
                $story.description | Should Be "Per-account directory structure under &lt;StmtsDir>/&lt;AccountName>/yyyy-MM.json"
            }
            finally { Remove-Item -LiteralPath $markdownPath -ErrorAction SilentlyContinue }
        }

        It "GivenLtEntityInAcceptanceCriteria_WhenParsing_ItShouldPreserveLtEntity" {
            [string]$markdown = @"
### Story: AC With Tags
{WorkItemId}: 901
{State}: Active

{Acceptance Criteria}
Path must match &lt;RootDir>/yyyy-MM.json pattern.
"@
            $markdownPath = [System.IO.Path]::GetTempFileName() + ".md"
            $markdown | Set-Content -LiteralPath $markdownPath
            try {
                $result = & (Join-Path $SRC_DIR 'ConvertMarkdownToHierarchyJson.ps1') `
                    -MarkdownFilePath $markdownPath -Organization 'falco-it' -Project 'GMD' -RepositoryRoot $REPO_ROOT
                $story = $result.workItems[0]
                ($story.acceptanceCriteria -match [regex]::Escape("&lt;RootDir>")) | Should Be $true
                ($story.acceptanceCriteria -match [regex]::Escape("<RootDir>")) | Should Be $false
            }
            finally { Remove-Item -LiteralPath $markdownPath -ErrorAction SilentlyContinue }
        }
    }
}
