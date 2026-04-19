#Requires -Version 7.0

<#
.SYNOPSIS
Integration tests for NewAzDoHierarchyFromMarkdown.ps1

.DESCRIPTION
Verifies the full "create from markdown" workflow for NewAzDoHierarchyFromMarkdown.ps1:
- Creates a test hierarchy from a generated markdown file
- Verifies that work item IDs are written back to the markdown file after creation
- Re-runs the script and verifies that existing items are updated (not duplicated)
For cleanup, any created test items are removed via RemoveAzDoEpic.ps1 at the end.
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

[string]$Organization = $env:GMD_AZDO_ORGANIZATION ?? 'falco-it'
[string]$Project = $env:GMD_AZDO_PROJECT ?? 'GMD'
[string]$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
[string]$SRC_DIR = Join-Path $SCRIPT_DIR '../../src'
[string]$TEST_DIR = Join-Path $SCRIPT_DIR '..'

$tests = @()
$createdEpicId = $null
$testMdFile = $null

function Record-Test {
    param([string]$Scenario, [bool]$Passed, [string]$Details)
    $script:tests += [PSCustomObject]@{
        Scenario = $Scenario
        Passed   = $Passed
        Details  = $Details
    }
}

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "INTEGRATION TESTS - NewAzDoHierarchyFromMarkdown.ps1" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

try {
    # ============================================================================
    # SCENARIO 1: Create hierarchy from markdown and verify IDs are written back
    # ============================================================================
    Write-Host "`n[SCENARIO 1] Create hierarchy from markdown - verify ID write-back" -ForegroundColor Yellow

    try {
        [string]$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        [string]$epicTitle = "TEST-$timestamp-NewMarkdownHierarchy"
        $testMdFile = Join-Path ([System.IO.Path]::GetTempPath()) "test-hierarchy-$timestamp.md"

        # Generate test markdown using TestMarkdown helper
        & "$TEST_DIR\CreateTestMarkdown.ps1" `
            -EpicTitle $epicTitle `
            -MdOutputFile $testMdFile `
            -FeatureCount 1 `
            -StoryPerFeatureCount 1 `
            -BugPerFeatureCount 0 `
            -TaskPerStory 1 `
            -ErrorAction Stop

        Write-Host "  ✓ Generated test markdown: $testMdFile"

        # Verify the markdown file exists and has no WorkItemId entries yet
        [string]$contentBefore = Get-Content -LiteralPath $testMdFile -Raw
        if ($contentBefore -match '\*\*WorkItemId\*\*:') {
            throw "Expected no WorkItemId entries in fresh markdown"
        }
        Write-Host "  ✓ Verified: no WorkItemId entries in fresh markdown"

        # Create hierarchy in Azure DevOps
        $result = & "$SRC_DIR\NewAzDoHierarchyFromMarkdown.ps1" `
            -MarkdownFile $testMdFile `
            -ErrorAction Stop

        Write-Host "  ✓ Hierarchy created"

        # Verify markdown was updated with IDs
        [string]$contentAfter = Get-Content -LiteralPath $testMdFile -Raw
        if (-not ($contentAfter -match '\*\*WorkItemId\*\*:\s*\d+')) {
            throw "Expected WorkItemId entries to be written back to markdown after creation"
        }
        Write-Host "  ✓ Verified: WorkItemId entries written back to markdown"

        # Extract the epic ID from the markdown
        if ($contentAfter -match '# Epic:.*\n\*\*WorkItemId\*\*:\s*(\d+)') {
            $script:createdEpicId = [int]$Matches[1]
            Write-Host "  ✓ Epic ID extracted from markdown: $createdEpicId"
        }
        else {
            throw "Could not extract Epic WorkItemId from updated markdown"
        }

        Record-Test -Scenario "Create hierarchy and write back IDs" -Passed $true -Details "Epic ID: $createdEpicId"
    }
    catch {
        Record-Test -Scenario "Create hierarchy and write back IDs" -Passed $false -Details $_.ToString()
        Write-Host "  ✗ FAILED: $_" -ForegroundColor Red
    }

    # ============================================================================
    # SCENARIO 2: Re-run script - verify existing items updated, not duplicated
    # ============================================================================
    Write-Host "`n[SCENARIO 2] Re-run on markdown with IDs - verify update not duplicate" -ForegroundColor Yellow

    if ($null -ne $createdEpicId -and $null -ne $testMdFile) {
        try {
            # Run the script again on the same markdown file (now has WorkItemId entries)
            $result2 = & "$SRC_DIR\NewAzDoHierarchyFromMarkdown.ps1" `
                -MarkdownFile $testMdFile `
                -ErrorAction Stop

            # Get the current hierarchy from AzDo and verify item count hasn't increased
            $hierarchy = & "$SRC_DIR\GetAzDoHierarchyForEpic.ps1" `
                -Organization $Organization `
                -Project $Project `
                -EpicId $createdEpicId `
                -ErrorAction Stop

            # Verify there's still only 1 feature and 1 story (no duplicates)
            if ($hierarchy.Features.Count -ne 1) {
                throw "Expected 1 Feature but found $($hierarchy.Features.Count) - duplicate creation detected"
            }
            if ($hierarchy.Features[0].Stories.Count -ne 1) {
                throw "Expected 1 Story but found $($hierarchy.Features[0].Stories.Count) - duplicate creation detected"
            }

            Write-Host "  ✓ No duplicates created on second run"
            Write-Host "  ✓ Feature count: $($hierarchy.Features.Count), Story count: $($hierarchy.Features[0].Stories.Count)"

            # Verify markdown still has the same IDs (not overwritten with new ones)
            [string]$contentAfterRerun = Get-Content -LiteralPath $testMdFile -Raw
            if (-not ($contentAfterRerun -match "\*\*WorkItemId\*\*:\s*$createdEpicId")) {
                throw "Epic WorkItemId was changed or removed after second run"
            }
            Write-Host "  ✓ Epic WorkItemId preserved in markdown after second run"

            Record-Test -Scenario "Re-run updates existing items without duplication" -Passed $true -Details "Feature count: $($hierarchy.Features.Count)"
        }
        catch {
            Record-Test -Scenario "Re-run updates existing items without duplication" -Passed $false -Details $_.ToString()
            Write-Host "  ✗ FAILED: $_" -ForegroundColor Red
        }
    }
    else {
        Record-Test -Scenario "Re-run updates existing items without duplication" -Passed $false -Details "Skipped - Scenario 1 failed"
        Write-Host "  ⚠ SKIPPED - Scenario 1 must pass first" -ForegroundColor Yellow
    }
}
finally {
    # Cleanup: remove test work items
    if ($null -ne $createdEpicId) {
        Write-Host "`n[CLEANUP] Removing test work items (Epic ID: $createdEpicId)..." -ForegroundColor DarkGray
        try {
            & "$SRC_DIR\RemoveAzDoEpic.ps1" `
                -Organization $Organization `
                -Project $Project `
                -EpicId $createdEpicId `
                -Force `
                -ErrorAction Stop
            Write-Host "  ✓ Test work items removed" -ForegroundColor DarkGray
        }
        catch {
            Write-Host "  ⚠ Cleanup failed: $_" -ForegroundColor Yellow
        }
    }

    # Cleanup: remove temp markdown file
    if ($null -ne $testMdFile -and (Test-Path -LiteralPath $testMdFile)) {
        Remove-Item -LiteralPath $testMdFile -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# RESULTS SUMMARY
# ============================================================================
Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "RESULTS SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

$passCount = @($tests | Where-Object { $_.Passed }).Count
$failCount = @($tests | Where-Object { -not $_.Passed }).Count

foreach ($test in $tests) {
    if ($test.Passed) {
        Write-Host "  ✓ PASS: $($test.Scenario)" -ForegroundColor Green
    }
    else {
        Write-Host "  ✗ FAIL: $($test.Scenario)" -ForegroundColor Red
        Write-Host "         $($test.Details)" -ForegroundColor Red
    }
}

Write-Host "`n  Total: $($tests.Count) | Passed: $passCount | Failed: $failCount" -ForegroundColor $(if ($failCount -eq 0) { 'Green' } else { 'Red' })

if ($failCount -gt 0) {
    exit 1
}
exit 0
