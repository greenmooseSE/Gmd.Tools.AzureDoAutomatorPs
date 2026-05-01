#Requires -Version 7.0

<#
.SYNOPSIS
AC tests for Story 2723: staleness detection in <see cref="NewAzDoHierarchyFromMarkdown.ps1"/>.

.DESCRIPTION
Verifies that the {LastChangedDate} write-back logic in Update-MarkdownWithWorkItemIds
correctly inserts and replaces {LastChangedDate} lines in markdown files. The function is
loaded from the source script via AST extraction to enable isolated unit testing without
requiring an Azure DevOps connection.

Staleness-check abort and -Force behaviour require a live AzDo connection and are covered
by the integration tests in CreateHierarchyFromMarkdownTest.ps1.

Run with: Invoke-Pester .\test\NewAzDoHierarchyFromMarkdownTests\StalenessDetectionTest.ps1
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

[string]$REPO_ROOT = Resolve-Path (Join-Path $PSScriptRoot '../../')
[string]$SRC_DIR   = Join-Path $REPO_ROOT 'src'

# Minimal stub for ssLogIt.ps1 if not on PATH
if (-not (Get-Command 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    function global:ssLogIt.ps1 {
        param([string]$Level, [string]$Message, [object]$Exception)
    }
}

# Load Update-MarkdownWithWorkItemIds from the source script using PowerShell AST
# extraction so that it can be tested in isolation without a live AzDo connection.
[string]$scriptPath = Join-Path $SRC_DIR 'NewAzDoHierarchyFromMarkdown.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
$funcAst = $ast.FindAll(
    { param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Update-MarkdownWithWorkItemIds' },
    $true
) | Select-Object -First 1
if ($null -eq $funcAst) {
    throw "Could not locate Update-MarkdownWithWorkItemIds in $scriptPath"
}
Invoke-Expression $funcAst.Extent.Text

Describe 'Story 2723 - {LastChangedDate} write-back in Update-MarkdownWithWorkItemIds' {

    [string]$tmpFile = $null

    BeforeEach {
        $script:tmpFile = [System.IO.Path]::GetTempFileName()
    }

    AfterEach {
        if (Test-Path $script:tmpFile) { Remove-Item $script:tmpFile -Force }
    }

    Context 'Scenario 4: New work item has no WorkItemId — write-back inserts both fields' {

        It 'GivenMarkdownWithNewItem_WhenWritingBackWithIdAndDate_ItShouldInsertWorkItemIdAndLastChangedDate' {
            # Scenario 4: new item (no {WorkItemId}) → script inserts {WorkItemId} AND {LastChangedDate}
            [string]$md = @"
### Story: My New Story
{tags}: foo
{Description}
Some description.
"@
            Set-Content -LiteralPath $script:tmpFile -Value $md -NoNewline -Encoding UTF8

            Update-MarkdownWithWorkItemIds `
                -MarkdownFilePath     $script:tmpFile `
                -TitleToIdMap         @{ 'My New Story' = 500 } `
                -TitleToStateMap      $null `
                -TitleToChangedDateMap @{ 'My New Story' = '2026-05-01T10:00:00Z' }

            [string]$result = Get-Content -LiteralPath $script:tmpFile -Raw
            $result | Should Match '\{WorkItemId\}: 500'
            $result | Should Match '\{LastChangedDate\}: 2026-05-01T10:00:00Z'

            # Verify ordering: {LastChangedDate} directly follows {WorkItemId}
            [string[]]$lines = $result -split '\r?\n'
            [int]$idIdx = ($lines | Select-String '^\{WorkItemId\}: 500').LineNumber - 1
            [int]$dtIdx = ($lines | Select-String '^\{LastChangedDate\}: 2026-05-01T10:00:00Z').LineNumber - 1
            $dtIdx | Should BeGreaterThan $idIdx
            $dtIdx - $idIdx | Should Be 1
        }
    }

    Context 'Scenario 5: Existing item has WorkItemId but no LastChangedDate (legacy file)' {

        It 'GivenLegacyMarkdownWithWorkItemIdAndNoLastChangedDate_WhenWritingBack_ItShouldInsertLastChangedDate' {
            # Scenario 5: legacy item with {WorkItemId} but no {LastChangedDate} → insert date after {WorkItemId}
            [string]$md = @"
### Story: My Legacy Story
{WorkItemId}: 200
{tags}: bar
{Description}
Story body.
"@
            Set-Content -LiteralPath $script:tmpFile -Value $md -NoNewline -Encoding UTF8

            Update-MarkdownWithWorkItemIds `
                -MarkdownFilePath     $script:tmpFile `
                -TitleToIdMap         @{} `
                -TitleToStateMap      $null `
                -TitleToChangedDateMap @{ 'My Legacy Story' = '2026-05-01T11:00:00Z' }

            [string]$result = Get-Content -LiteralPath $script:tmpFile -Raw
            $result | Should Match '\{LastChangedDate\}: 2026-05-01T11:00:00Z'

            # Verify ordering: {LastChangedDate} directly follows {WorkItemId}
            [string[]]$lines = $result -split '\r?\n'
            [int]$idIdx = ($lines | Select-String '^\{WorkItemId\}: 200').LineNumber - 1
            [int]$dtIdx = ($lines | Select-String '^\{LastChangedDate\}: 2026-05-01T11:00:00Z').LineNumber - 1
            $dtIdx - $idIdx | Should Be 1
        }
    }

    Context 'Scenario: Update replaces existing {LastChangedDate} value' {

        It 'GivenMarkdownWithExistingLastChangedDate_WhenWritingBackNewDate_ItShouldReplaceOldDate' {
            # After an update, the stale stored date should be replaced with the new API response date
            [string]$md = @"
### Story: My Updated Story
{WorkItemId}: 300
{LastChangedDate}: 2026-04-01T00:00:00Z
{tags}: baz
{Description}
Body.
"@
            Set-Content -LiteralPath $script:tmpFile -Value $md -NoNewline -Encoding UTF8

            Update-MarkdownWithWorkItemIds `
                -MarkdownFilePath     $script:tmpFile `
                -TitleToIdMap         @{} `
                -TitleToStateMap      $null `
                -TitleToChangedDateMap @{ 'My Updated Story' = '2026-05-01T12:00:00Z' }

            [string]$result = Get-Content -LiteralPath $script:tmpFile -Raw
            $result | Should Match '\{LastChangedDate\}: 2026-05-01T12:00:00Z'
            $result | Should Not Match '2026-04-01T00:00:00Z'
        }
    }

    Context 'Scenario: Items without WorkItemId skip staleness check (no date written)' {

        It 'GivenItemWithNoWorkItemIdAndNoEntryInDateMap_WhenWritingBack_ItShouldNotAddLastChangedDate' {
            # Items not in changedDateWritebackMap should not get {LastChangedDate} inserted
            [string]$md = @"
### Story: Untouched Story
{WorkItemId}: 400
{tags}: qux
{Description}
Body.
"@
            Set-Content -LiteralPath $script:tmpFile -Value $md -NoNewline -Encoding UTF8

            # Pass an EMPTY date map — simulates an item that was not created/updated
            Update-MarkdownWithWorkItemIds `
                -MarkdownFilePath     $script:tmpFile `
                -TitleToIdMap         @{} `
                -TitleToStateMap      $null `
                -TitleToChangedDateMap @{}

            [string]$result = Get-Content -LiteralPath $script:tmpFile -Raw
            $result | Should Not Match '\{LastChangedDate\}'
        }
    }

    Context 'Scenario: Multi-item markdown — each item gets its own date' {

        It 'GivenMultipleStories_WhenWritingBack_ItShouldUpdateEachItemIndependently' {
            # Multiple items in the same file each get their own {LastChangedDate}
            [string]$md = @"
### Story: Story Alpha
{WorkItemId}: 501
{LastChangedDate}: 2026-01-01T00:00:00Z
{Description}
Alpha.

### Story: Story Beta
{WorkItemId}: 502
{Description}
Beta.
"@
            Set-Content -LiteralPath $script:tmpFile -Value $md -NoNewline -Encoding UTF8

            Update-MarkdownWithWorkItemIds `
                -MarkdownFilePath     $script:tmpFile `
                -TitleToIdMap         @{} `
                -TitleToStateMap      $null `
                -TitleToChangedDateMap @{
                    'Story Alpha' = '2026-05-01T09:00:00Z'
                    'Story Beta'  = '2026-05-01T09:30:00Z'
                }

            [string]$result = Get-Content -LiteralPath $script:tmpFile -Raw
            $result | Should Match '\{LastChangedDate\}: 2026-05-01T09:00:00Z'
            $result | Should Match '\{LastChangedDate\}: 2026-05-01T09:30:00Z'
            $result | Should Not Match '2026-01-01T00:00:00Z'
        }
    }
}
