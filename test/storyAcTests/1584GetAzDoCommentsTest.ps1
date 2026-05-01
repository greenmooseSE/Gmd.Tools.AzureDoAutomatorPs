#Requires -Version 7.0

<#
.SYNOPSIS
ACCEPTANCE TEST verification tests for story 1584: GetAzDoComments functionality
Tests map directly to Acceptance Tests and verify listing all comments on work items.
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$Organization = "falco-it"
$Project = "gmd"
$SRC_DIR = ".\src"

# Test tracking
[System.Collections.ArrayList]$tests = @()
$createdItems = @()

function Record-Test {
    param(
        [string]$Scenario,
        [bool]$Passed,
        [string]$Details
    )
    $null = $tests.Add([PSCustomObject]@{
        Scenario = $Scenario
        Passed   = $Passed
        Details  = $Details
    })
}

function Register-CreatedItem {
    param(
        [int]$ItemId
    )
    $createdItems += $ItemId
}

function Cleanup-CreatedItems {
    Write-Host "`nCleaning up created test items..." -ForegroundColor Cyan
    foreach ($itemId in $createdItems) {
        try {
            & "$SRC_DIR/RemoveAzDoEpic.ps1" -Organization $Organization -Project $Project -EpicId $itemId -Force -ErrorAction SilentlyContinue | Out-Null
            Write-Host "  Cleaned up Epic ID: $itemId" -ForegroundColor Green
        }
        catch {
            Write-Host "  Warning: Failed to clean up Epic ID: $itemId" -ForegroundColor Yellow
        }
    }
}

function Print-Summary {
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║ TEST SUMMARY - Story 1584: GetAzDoComments                       ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    
    $passed = @($tests | Where-Object { $_.Passed }).Count
    $failed = @($tests | Where-Object { -not $_.Passed }).Count
    
    Write-Host "`nResults:" -ForegroundColor Yellow
    $tests | ForEach-Object {
        $status = if ($_.Passed) { "✓ PASS" } else { "✗ FAIL" }
        $color = if ($_.Passed) { "Green" } else { "Red" }
        Write-Host "  [$status] $($_.Scenario)" -ForegroundColor $color
        if ($_.Details) {
            Write-Host "         $($_.Details)" -ForegroundColor DarkGray
        }
    }
    
    Write-Host "`nTotal: $($tests.Count) tests | Passed: $passed | Failed: $failed" -ForegroundColor Cyan
    
    return $failed -eq 0
}

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "ACCEPTANCE TEST VERIFICATION - Story 1584: GetAzDoComments" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

# ============================================================================
# ACCEPTANCE TEST 1: List all comments on a work item
# ============================================================================
Write-Host "`n[ACCEPTANCE TEST 1] List all comments on a work item" -ForegroundColor Yellow

try {
    # Create a test Epic
    $testEpic = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project `
        -Title "TestEpic_1584_$(Get-Date -Format 'yyyyMMddHHmmss')" -ErrorAction Stop
    
    if ($null -eq $testEpic -or $null -eq $testEpic.id) {
        throw "Failed to create test Epic"
    }
    Register-CreatedItem -ItemId $testEpic.id
    
    # Add 3 comments to the Epic
    $comment1 = & "$SRC_DIR/NewAzDoComment.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $testEpic.id -Content "First comment on test work item" -ErrorAction Stop
    
    $comment2 = & "$SRC_DIR/NewAzDoComment.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $testEpic.id -Content "Second comment with **bold** text" -ErrorAction Stop
    
    $comment3 = & "$SRC_DIR/NewAzDoComment.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $testEpic.id -Content "Third comment - testing retrieval" -ErrorAction Stop
    
    # Now retrieve all comments
    $retrievedComments = & "$SRC_DIR/GetAzDoComments.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $testEpic.id -ErrorAction Stop
    
    if ($null -eq $retrievedComments) {
        throw "GetAzDoComments returned null"
    }
    
    # Verify we got 3 comments
    $commentCount = if ($retrievedComments -is [array]) { $retrievedComments.Count } else { 1 }
    
    if ($commentCount -ne 3) {
        throw "Expected 3 comments, but got $commentCount"
    }
    
    # Verify comment structure
    $firstComment = if ($retrievedComments -is [array]) { $retrievedComments[0] } else { $retrievedComments }
    
    if (-not (Test-Path -Path "variable:firstComment") -or $null -eq $firstComment.id) {
        throw "Comment missing 'id' field"
    }
    
    if ($null -eq $firstComment.text) {
        throw "Comment missing 'text' field"
    }
    
    if ($null -eq $firstComment.createdBy) {
        throw "Comment missing 'createdBy' field"
    }
    
    if ($null -eq $firstComment.createdDate) {
        throw "Comment missing 'createdDate' field"
    }
    
    Record-Test -Scenario "ACCEPTANCE TEST 1: List all comments on a work item" -Passed $true -Details "All 3 comments retrieved with complete metadata"
    Write-Host "  ✓ PASSED: All 3 comments retrieved with metadata" -ForegroundColor Green
}
catch {
    Record-Test -Scenario "ACCEPTANCE TEST 1: List all comments on a work item" -Passed $false -Details $_.Exception.Message
    Write-Host "  ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# ACCEPTANCE TEST 2: Empty comment list (no comments on work item)
# ============================================================================
Write-Host "`n[ACCEPTANCE TEST 2] Empty comment list (no comments on work item)" -ForegroundColor Yellow

try {
    # Create a new test Epic with no comments
    $testEpic2 = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project `
        -Title "TestEpic2_NoComments_$(Get-Date -Format 'yyyyMMddHHmmss')" -ErrorAction Stop
    
    if ($null -eq $testEpic2 -or $null -eq $testEpic2.id) {
        throw "Failed to create second test Epic"
    }
    Register-CreatedItem -ItemId $testEpic2.id
    
    # Retrieve comments (should be empty)
    $emptyComments = & "$SRC_DIR/GetAzDoComments.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $testEpic2.id -ErrorAction Stop
    
    # Check if result is empty array
    if ($null -eq $emptyComments) {
        throw "Expected empty array, got null"
    }
    
    $emptyCount = if ($emptyComments -is [array]) { $emptyComments.Count } else { if ($emptyComments) { 1 } else { 0 } }
    
    if ($emptyCount -ne 0) {
        throw "Expected empty array (0 comments), but got $emptyCount items"
    }
    
    Record-Test -Scenario "ACCEPTANCE TEST 2: Empty comment list (work item with no comments)" -Passed $true -Details "Correctly returned empty array"
    Write-Host "  ✓ PASSED: Empty array returned for work item with no comments" -ForegroundColor Green
}
catch {
    Record-Test -Scenario "ACCEPTANCE TEST 2: Empty comment list (work item with no comments)" -Passed $false -Details $_.Exception.Message
    Write-Host "  ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# Additional Test: Verify comment content integrity
# ============================================================================
Write-Host "`n[ADDITIONAL TEST] Verify comment content integrity" -ForegroundColor Yellow

try {
    # Create test Epic with one comment
    $testEpic3 = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project `
        -Title "TestEpic3_ContentTest_$(Get-Date -Format 'yyyyMMddHHmmss')" -ErrorAction Stop
    
    Register-CreatedItem -ItemId $testEpic3.id
    
    $testContent = "Test comment with special chars: !@#$%^&*()"
    
    & "$SRC_DIR/NewAzDoComment.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $testEpic3.id -Content $testContent -ErrorAction Stop | Out-Null
    
    $comments = & "$SRC_DIR/GetAzDoComments.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $testEpic3.id -ErrorAction Stop
    
    if ($null -eq $comments) {
        throw "Failed to retrieve comment"
    }
    
    $retrievedComment = if ($comments -is [array]) { $comments[0] } else { $comments }
    
    if ($retrievedComment.text -ne $testContent) {
        throw "Comment content mismatch. Expected: '$testContent', Got: '$($retrievedComment.text)'"
    }
    
    Record-Test -Scenario "Additional Test: Comment content integrity" -Passed $true -Details "Comment content preserved correctly"
    Write-Host "  ✓ PASSED: Comment content integrity verified" -ForegroundColor Green
}
catch {
    Record-Test -Scenario "Additional Test: Comment content integrity" -Passed $false -Details $_.Exception.Message
    Write-Host "  ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# Cleanup and Summary
# ============================================================================

Cleanup-CreatedItems
$allPassed = Print-Summary

# Exit with appropriate code
exit ($allPassed ? 0 : 1)
