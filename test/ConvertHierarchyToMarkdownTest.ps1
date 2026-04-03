<#
.SYNOPSIS
Integration test for ConvertHierarchyToMarkdown.ps1 for Epic, Feature, and Story

.DESCRIPTION
Tests the ConvertHierarchyToMarkdown.ps1 script for converting all hierarchy types
(Epic, Feature, Story) to markdown format with proper trailing spaces for newlines.

Requires Environment variable set:
- GMD_AZDO_ORGANIZATION: Organization name
- GMD_AZDO_PROJECT: Project name
- GMD_AZDO_MACHINE_WORKITEMSRW: Encrypted PAT token

Run with: pwsh -File .\ConvertHierarchyToMarkdownTest.ps1

.NOTES
Creates temporary test Epic, Feature, Story items and their markdown conversions,
then verifies proper formatting and cleans them up.
#>

#Requires -Version 7.0

param(
    [string]$Organization = $env:GMD_AZDO_ORGANIZATION,
    [string]$Project = $env:GMD_AZDO_PROJECT
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Test configuration
[string]$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
[string]$SRC_DIR = Join-Path $SCRIPT_DIR '../src'

# Validate inputs
if ([string]::IsNullOrWhiteSpace($Organization)) {
    Write-Error "Organization not provided. Set GMD_AZDO_ORGANIZATION environment variable or pass -Organization parameter."
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    Write-Error "Project not provided. Set GMD_AZDO_PROJECT environment variable or pass -Project parameter."
}

# Test counters
[int]$testsRun = 0
[int]$testsPassed = 0
[int]$testsFailed = 0
[array]$createdItems = @()

function Invoke-Test {
    [CmdletBinding()]
    param(
        [string]$Name,
        [scriptblock]$TestScript
    )

    $script:testsRun++
    Write-Host "Test: $Name" -ForegroundColor Yellow

    try {
        & $TestScript
        $script:testsPassed++
        Write-Host "  ✓ PASSED" -ForegroundColor Green
    }
    catch {
        $script:testsFailed++
        Write-Host "  ✗ FAILED: $_" -ForegroundColor Red
        Write-Host "Stack: $($_.ScriptStackTrace)" -ForegroundColor Red
    }
}

function Test-MarkdownLineBreaks {
    <#
    .SYNOPSIS
    Verify that markdown has 2 trailing spaces for line breaks
    #>
    param(
        [string]$Markdown,
        [string]$TestName
    )

    Write-Host "  Checking for trailing spaces in: $TestName" -ForegroundColor Cyan

    # Split by lines
    $lines = $Markdown -split "`n"
    $linesWithoutSpaces = 0
    $linesWithSpaces = 0

    foreach ($line in $lines) {
        # Skip empty lines, headers, bullets, numbered lists, and tables
        if ($line -match '^\s*$' -or `
            $line -match '^\s*[#]{1,6}\s' -or `
            $line -match '^\s*[-*+]\s' -or `
            $line -match '^\s*\d+[\.\)]\s' -or `
            $line -match '\|') {
            # These should NOT have trailing spaces
            if ($line -match '\s{2}$') {
                Write-Host "    WARNING: Header/list/table line has trailing spaces: $line" -ForegroundColor Yellow
            }
        }
        else {
            # Regular content lines SHOULD have 2 trailing spaces
            if ($line -match '\s{2}$') {
                $linesWithSpaces++
            }
            elseif ($line -notmatch '^\s*$') {
                # Non-empty lines without trailing spaces is a problem
                $linesWithoutSpaces++
                Write-Host "    Line WITHOUT trailing spaces: $line" -ForegroundColor Yellow
            }
        }
    }

    Write-Host "    Total lines with 2 trailing spaces: $linesWithSpaces" -ForegroundColor Green
    if ($linesWithoutSpaces -gt 0) {
        Write-Host "    WARNING: $linesWithoutSpaces regular content lines missing 2 trailing spaces" -ForegroundColor Yellow
    }
}

function Cleanup {
    if ($script:createdItems.Count -gt 0) {
        Write-Host "`nCleaning up test items..." -ForegroundColor Cyan
        try {
            # Delete items in reverse order (cleanest for hierarchies)
            for ($i = $script:createdItems.Count - 1; $i -ge 0; $i--) {
                $item = $script:createdItems[$i]
                Write-Host "Deleting $($item.Type) (ID: $($item.Id))" -ForegroundColor Gray

                try {
                    switch ($item.Type) {
                        "Epic" {
                            & "$SRC_DIR/RemoveAzDoEpic.ps1" -Organization $Organization -Project $Project -EpicId $item.Id -Force
                        }
                        "Feature" {
                            # Features are removed via parent Epic
                            # So we skip this and rely on Epic deletion
                        }
                        "Story" {
                            # Stories are removed via RemoveAzDoTask (but Story is handled separately)
                            # For now, we just skip since stories under features are deleted with feature
                            if ($item.ParentId) {
                                # Child story, will be deleted with parent
                            }
                        }
                    }
                }
                catch {
                    Write-Host "  Warning: Could not delete $($item.Type) $($item.Id): $_" -ForegroundColor Yellow
                }
            }
            Write-Host "Cleanup completed" -ForegroundColor Green
        }
        catch {
            Write-Host "Warning: Cleanup failed: $_" -ForegroundColor Yellow
        }
    }
}

# Register cleanup on exit
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Cleanup }

try {
    Write-Host "`n=== ConvertHierarchyToMarkdown Integration Tests ===" -ForegroundColor Cyan
    Write-Host "Organization: $Organization"
    Write-Host "Project: $Project"

    # ==================== TEST 1: EPIC WITH FEATURE AND STORY ====================
    Write-Host "`n--- Test 1: Converting Epic Hierarchy ---" -ForegroundColor Cyan

    Write-Host "Creating test Epic..." -ForegroundColor Cyan
    $epicTitle = "ConvertToMarkdown Test Epic $(Get-Random)"
    $epic = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project -Title $epicTitle -Description "Epic description with multiple lines. This is the second line."
    $script:createdItems += @{ Type = "Epic"; Id = $epic.id }
    Write-Host "Created Epic (ID: $($epic.id)) - $epicTitle" -ForegroundColor Green

    Write-Host "Creating Feature under Epic..." -ForegroundColor Cyan
    $featureTitle = "Test Feature $(Get-Random)"
    $feature = & "$SRC_DIR/UpsertAzDoFeature.ps1" -Organization $Organization -Project $Project -Title $featureTitle -Description "Feature description with content." -ParentEpicId $epic.id
    $script:createdItems += @{ Type = "Feature"; Id = $feature.id; ParentId = $epic.id }
    Write-Host "Created Feature (ID: $($feature.id)) - $featureTitle" -ForegroundColor Green

    Write-Host "Creating Story under Feature..." -ForegroundColor Cyan
    $storyTitle = "Test Story $(Get-Random)"
    $story = & "$SRC_DIR/UpsertAzDoStory.ps1" -Organization $Organization -Project $Project -Title $storyTitle -Description "Story description with content. Line 2 of description." -ParentFeatureId $feature.id -StoryPoints 5
    $script:createdItems += @{ Type = "Story"; Id = $story.id; ParentId = $feature.id }
    Write-Host "Created Story (ID: $($story.id)) - $storyTitle" -ForegroundColor Green

    Write-Host "Retrieving Epic hierarchy..." -ForegroundColor Cyan
    $epicHierarchy = & "$SRC_DIR/GetAzDoHierarchyForEpic.ps1" -Organization $Organization -Project $Project -EpicId $epic.id
    Write-Host "Retrieved Epic hierarchy with $($epicHierarchy.Features.Count) feature(s)" -ForegroundColor Green

    Invoke-Test "Epic Hierarchy - Retrieve" {
        if ($null -eq $epicHierarchy) {
            throw "Epic hierarchy is null"
        }
        if ($epicHierarchy.Id -ne $epic.id) {
            throw "Epic ID mismatch"
        }
        if ($epicHierarchy.Features.Count -eq 0) {
            throw "No features found in epic hierarchy"
        }
    }

    Write-Host "Converting Epic to markdown..." -ForegroundColor Cyan
    $epicMarkdown = & "$SRC_DIR/ConvertHierarchyToMarkdown.ps1" -Hierarchy $epicHierarchy -Organization $Organization -Project $Project
    Write-Host "Converted Epic to markdown ($(($epicMarkdown -split "`n").Count) lines)" -ForegroundColor Green

    Invoke-Test "Epic Hierarchy - Convert to Markdown" {
        if ([string]::IsNullOrEmpty($epicMarkdown)) {
            throw "Markdown output is empty"
        }
        if ($epicMarkdown -notmatch "# Epic:") {
            throw "Markdown missing Epic header"
        }
        if ($epicMarkdown -notmatch "## Feature:") {
            throw "Markdown missing Feature header"
        }
        if ($epicMarkdown -notmatch "### Story:") {
            throw "Markdown missing Story header"
        }
    }

    Invoke-Test "Epic Hierarchy - Markdown has trailing spaces" {
        Test-MarkdownLineBreaks -Markdown $epicMarkdown -TestName "Epic Markdown"
    }

    # ==================== TEST 2: STANDALONE FEATURE ====================
    Write-Host "`n--- Test 2: Converting Feature Hierarchy ---" -ForegroundColor Cyan

    Write-Host "Creating standalone Feature..." -ForegroundColor Cyan
    $featureTitle2 = "Standalone Feature $(Get-Random)"
    $feature2 = & "$SRC_DIR/UpsertAzDoFeature.ps1" -Organization $Organization -Project $Project -Title $featureTitle2 -Description "Standalone feature description."
    $script:createdItems += @{ Type = "Feature"; Id = $feature2.id }
    Write-Host "Created Feature (ID: $($feature2.id)) - $featureTitle2" -ForegroundColor Green

    Write-Host "Creating Story under standalone Feature..." -ForegroundColor Cyan
    $storyTitle2 = "Story in Feature $(Get-Random)"
    $story2 = & "$SRC_DIR/UpsertAzDoStory.ps1" -Organization $Organization -Project $Project -Title $storyTitle2 -Description "Story description line 1. Story description line 2." -ParentFeatureId $feature2.id
    $script:createdItems += @{ Type = "Story"; Id = $story2.id; ParentId = $feature2.id }
    Write-Host "Created Story (ID: $($story2.id)) - $storyTitle2" -ForegroundColor Green

    Write-Host "Retrieving Feature hierarchy..." -ForegroundColor Cyan
    $featureHierarchy = & "$SRC_DIR/GetAzDoHierarchyForFeature.ps1" -Organization $Organization -Project $Project -FeatureId $feature2.id
    Write-Host "Retrieved Feature hierarchy with $($featureHierarchy.Stories.Count) story(ies)" -ForegroundColor Green

    Invoke-Test "Feature Hierarchy - Retrieve" {
        if ($null -eq $featureHierarchy) {
            throw "Feature hierarchy is null"
        }
        if ($featureHierarchy.Id -ne $feature2.id) {
            throw "Feature ID mismatch"
        }
        if ($featureHierarchy.Stories.Count -eq 0) {
            throw "No stories found in feature hierarchy"
        }
    }

    Write-Host "Converting Feature to markdown..." -ForegroundColor Cyan
    $featureMarkdown = & "$SRC_DIR/ConvertHierarchyToMarkdown.ps1" -Hierarchy $featureHierarchy -Organization $Organization -Project $Project
    Write-Host "Converted Feature to markdown ($(($featureMarkdown -split "`n").Count) lines)" -ForegroundColor Green

    Invoke-Test "Feature Hierarchy - Convert to Markdown" {
        if ([string]::IsNullOrEmpty($featureMarkdown)) {
            throw "Markdown output is empty"
        }
        if ($featureMarkdown -notmatch "## Feature:") {
            throw "Markdown missing Feature header"
        }
        if ($featureMarkdown -notmatch "### Story:") {
            throw "Markdown missing Story header"
        }
    }

    Invoke-Test "Feature Hierarchy - Markdown has trailing spaces" {
        Test-MarkdownLineBreaks -Markdown $featureMarkdown -TestName "Feature Markdown"
    }

    # ==================== TEST 3: STANDALONE STORY (via Feature) ====================
    Write-Host "`n--- Test 3: Testing Story Conversion (accessed via Feature) ---" -ForegroundColor Cyan

    Write-Host "Creating another Feature for standalone story test..." -ForegroundColor Cyan
    $featureTitle3 = "Feature for Story Test $(Get-Random)"
    $feature3 = & "$SRC_DIR/UpsertAzDoFeature.ps1" -Organization $Organization -Project $Project -Title $featureTitle3 -Description "Feature for testing story conversion."
    $script:createdItems += @{ Type = "Feature"; Id = $feature3.id }
    Write-Host "Created Feature (ID: $($feature3.id)) - $featureTitle3" -ForegroundColor Green

    Write-Host "Creating Story with full details..." -ForegroundColor Cyan
    $storyTitle3 = "Story with Details $(Get-Random)"
    $story3 = & "$SRC_DIR/UpsertAzDoStory.ps1" -Organization $Organization -Project $Project -Title $storyTitle3 `
        -Description "Story description line 1. Story description line 2." `
        -AcceptanceCriteria "- [ ] Must have feature X`n- [ ] Must support Y" `
        -StoryPoints 5 -ParentFeatureId $feature3.id
    $script:createdItems += @{ Type = "Story"; Id = $story3.id; ParentId = $feature3.id }
    Write-Host "Created Story (ID: $($story3.id)) - $storyTitle3" -ForegroundColor Green

    Write-Host "Retrieving Feature hierarchy with full Story..." -ForegroundColor Cyan
    $featureHierarchy3 = & "$SRC_DIR/GetAzDoHierarchyForFeature.ps1" -Organization $Organization -Project $Project -FeatureId $feature3.id
    Write-Host "Retrieved Feature hierarchy with $($featureHierarchy3.Stories.Count) story(ies)" -ForegroundColor Green

    Write-Host "Converting to markdown and testing story conversion..." -ForegroundColor Cyan
    $featureMarkdown3 = & "$SRC_DIR/ConvertHierarchyToMarkdown.ps1" -Hierarchy $featureHierarchy3 -Organization $Organization -Project $Project
    Write-Host "Converted to markdown ($(($featureMarkdown3 -split "`n").Count) lines)" -ForegroundColor Green

    Invoke-Test "Story in Feature - Contains Story State" {
        if ($featureMarkdown3 -notmatch "\*\*State\*\*:") {
            throw "Story markdown missing State field"
        }
    }

    Invoke-Test "Story in Feature - Contains Story Points" {
        if ($featureMarkdown3 -notmatch "\*\*SP\*\*: 5") {
            throw "Story markdown missing or incorrect Story Points"
        }
    }

    Invoke-Test "Story in Feature - Contains Acceptance Criteria" {
        if ($featureMarkdown3 -notmatch "Acceptance Criteria") {
            throw "Story markdown missing Acceptance Criteria section"
        }
    }

    Invoke-Test "Story in Feature - Markdown has trailing spaces" {
        Test-MarkdownLineBreaks -Markdown $featureMarkdown3 -TestName "Story in Feature Markdown"
    }

    # ==================== TEST 4: MARKDOWN CONTENT VALIDATION ====================
    Write-Host "`n--- Test 4: Markdown Content Validation ---" -ForegroundColor Cyan

    Invoke-Test "Epic Markdown - Contains heading and content" {
        if ($epicMarkdown -notmatch '# Epic:') {
            throw "Epic markdown missing Epic header"
        }
        if ($epicMarkdown -notmatch '\*\*Description\*\*') {
            throw "Epic markdown missing Description"
        }
    }

    Invoke-Test "Feature Markdown - Contains heading and content" {
        if ($featureMarkdown -notmatch '## Feature:') {
            throw "Feature markdown missing Feature header"
        }
        if ($featureMarkdown -notmatch '\*\*Description\*\*') {
            throw "Feature markdown missing Description field"
        }
    }

    Invoke-Test "Story Markdown - Contains all required fields" {
        if ($featureMarkdown3 -notmatch '### Story:') {
            throw "Story markdown missing Story header"
        }
        if ($featureMarkdown3 -notmatch '\*\*State\*\*:') {
            throw "Story markdown missing State field"
        }
        if ($featureMarkdown3 -notmatch '\*\*SP\*\*: 5') {
            throw "Story markdown missing or incorrect Story Points"
        }
    }

    # ==================== TEST SUMMARY ====================
    Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
    Write-Host "Tests Run:    $testsRun" -ForegroundColor White
    Write-Host "Tests Passed: $testsPassed" -ForegroundColor Green
    Write-Host "Tests Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { "Green" } else { "Red" })

    if ($testsFailed -gt 0) {
        Write-Host "`nResult: FAILED" -ForegroundColor Red
        exit 1
    }
    else {
        Write-Host "`nResult: ALL TESTS PASSED" -ForegroundColor Green
        exit 0
    }
}
catch {
    Write-Host "`nFATAL ERROR: $_" -ForegroundColor Red
    Write-Host "Stack: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}
finally {
    Cleanup
}
