#Requires -Version 7.0

<#
.SYNOPSIS
ACCEPTANCE TEST verification tests for story 1585: UpdateAzDoComment functionality
Tests map directly to Acceptance Tests and verify updating comment content on work items.
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
    Write-Host "║ TEST SUMMARY - Story 1585: UpdateAzDoComment                    ║" -ForegroundColor Green
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
Write-Host "ACCEPTANCE TEST VERIFICATION - Story 1585: UpdateAzDoComment" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

# ============================================================================
# ACCEPTANCE TEST 1: Update comment successfully
# Given comment exists with original content
# When calling UpdateAzDoComment with new content
# Then comment is updated in Azure DevOps
# And updated comment object is returned
# ============================================================================
Write-Host "`n[ACCEPTANCE TEST 1] Update comment successfully" -ForegroundColor Yellow

try {
    # Create a test Epic
    $testEpic = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project `
        -Title "TestEpic_1585_$(Get-Date -Format 'yyyyMMddHHmmss')" -ErrorAction Stop
    
    if ($null -eq $testEpic -or $null -eq $testEpic.id) {
        throw "Failed to create test Epic"
    }
    Register-CreatedItem -ItemId $testEpic.id
    
    # Add initial comment
    $initialComment = & "$SRC_DIR/NewAzDoComment.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $testEpic.id -Content "Initial comment content" -ErrorAction Stop
    
    if ($null -eq $initialComment -or $null -eq $initialComment.id) {
        throw "Failed to create initial comment"
    }
    
    $commentId = $initialComment.id
    
    # Update the comment with new content
    $newContent = "Updated comment content - typo fixed"
    $updatedComment = & "$SRC_DIR/UpdateAzDoComment.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $testEpic.id -CommentId $commentId -Content $newContent -ErrorAction Stop
    
    if ($null -eq $updatedComment) {
        throw "UpdateAzDoComment returned null"
    }
    
    # Verify the comment was updated
    if ($updatedComment.id -ne $commentId) {
        throw "Comment ID mismatch. Expected: $commentId, Got: $($updatedComment.id)"
    }
    
    if ($updatedComment.text -ne $newContent) {
        throw "Comment content not updated. Expected: '$newContent', Got: '$($updatedComment.text)'"
    }
    
    # Verify version changed
    if ($updatedComment.version -le $initialComment.version) {
        throw "Comment version not incremented after update"
    }
    
    # Verify by retrieving comments again
    $retrievedComments = & "$SRC_DIR/GetAzDoComments.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $testEpic.id -ErrorAction Stop
    
    $retrievedComment = if ($retrievedComments -is [array]) { 
        $retrievedComments | Where-Object { $_.id -eq $commentId } | Select-Object -First 1 
    } else { 
        if ($retrievedComments.id -eq $commentId) { $retrievedComments } else { $null }
    }
    
    if ($null -eq $retrievedComment) {
        throw "Could not find updated comment when retrieving all comments"
    }
    
    if ($retrievedComment.text -ne $newContent) {
        throw "Retrieved comment does not have updated content"
    }
    
    Record-Test -Scenario "ACCEPTANCE TEST 1: Update comment successfully" -Passed $true -Details "Comment updated and verified via retrieval"
    Write-Host "  ✓ PASSED: Comment updated successfully" -ForegroundColor Green
}
catch {
    Record-Test -Scenario "ACCEPTANCE TEST 1: Update comment successfully" -Passed $false -Details $_.Exception.Message
    Write-Host "  ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# ADDITIONAL TEST 1: Update comment with markdown content
# ============================================================================
Write-Host "`n[ADDITIONAL TEST 1] Update comment with markdown content" -ForegroundColor Yellow

try {
    $testEpic = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project `
        -Title "TestEpic_Markdown_$(Get-Date -Format 'yyyyMMddHHmmss')" -ErrorAction Stop
    
    Register-CreatedItem -ItemId $testEpic.id
    
    # Create initial comment
    $comment = & "$SRC_DIR/NewAzDoComment.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $testEpic.id -Content "Original plain text" -ErrorAction Stop
    
    # Update with markdown content
    $markdownContent = @"
**Bold text** with _italic_

- Bullet point 1
- Bullet point 2

\`Code snippet\`
"@
    
    $updatedComment = & "$SRC_DIR/UpdateAzDoComment.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $testEpic.id -CommentId $comment.id -Content $markdownContent -ErrorAction Stop
    
    if ($updatedComment.text -ne $markdownContent) {
        throw "Markdown content not preserved"
    }
    
    Record-Test -Scenario "Additional Test 1: Update comment with markdown" -Passed $true -Details "Markdown formatting preserved"
    Write-Host "  ✓ PASSED: Markdown content updated correctly" -ForegroundColor Green
}
catch {
    Record-Test -Scenario "Additional Test 1: Update comment with markdown" -Passed $false -Details $_.Exception.Message
    Write-Host "  ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# ADDITIONAL TEST 2: Update comment with special characters
# ============================================================================
Write-Host "`n[ADDITIONAL TEST 2] Update comment with special characters" -ForegroundColor Yellow

try {
    $testEpic = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project `
        -Title "TestEpic_SpecialChars_$(Get-Date -Format 'yyyyMMddHHmmss')" -ErrorAction Stop
    
    Register-CreatedItem -ItemId $testEpic.id
    
    # Create initial comment
    $comment = & "$SRC_DIR/NewAzDoComment.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $testEpic.id -Content "Original" -ErrorAction Stop
    
    # Update with special characters
    $specialContent = 'Updated with special chars: !@#$%^&*()_+-=[]{}|;:"<>?,./'
    
    $updatedComment = & "$SRC_DIR/UpdateAzDoComment.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $testEpic.id -CommentId $comment.id -Content $specialContent -ErrorAction Stop
    
    if ($updatedComment.text -ne $specialContent) {
        throw "Special characters not preserved. Expected: '$specialContent', Got: '$($updatedComment.text)'"
    }
    
    Record-Test -Scenario "Additional Test 2: Update comment with special characters" -Passed $true -Details "Special characters preserved"
    Write-Host "  ✓ PASSED: Special characters handled correctly" -ForegroundColor Green
}
catch {
    Record-Test -Scenario "Additional Test 2: Update comment with special characters" -Passed $false -Details $_.Exception.Message
    Write-Host "  ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# ADDITIONAL TEST 3: Error handling - invalid comment ID
# ============================================================================
Write-Host "`n[ADDITIONAL TEST 3] Error handling - invalid comment ID" -ForegroundColor Yellow

try {
    $testEpic = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project `
        -Title "TestEpic_InvalidId_$(Get-Date -Format 'yyyyMMddHHmmss')" -ErrorAction Stop
    
    Register-CreatedItem -ItemId $testEpic.id
    
    # Try to update non-existent comment
    $invalidResult = & "$SRC_DIR/UpdateAzDoComment.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $testEpic.id -CommentId 999999 -Content "New content" -ErrorAction SilentlyContinue
    
    if ($LASTEXITCODE -eq 0) {
        throw "Expected error when updating non-existent comment, but operation succeeded"
    }
    
    Record-Test -Scenario "Additional Test 3: Error handling - invalid comment ID" -Passed $true -Details "Correctly failed on invalid comment"
    Write-Host "  ✓ PASSED: Error handling verified" -ForegroundColor Green
}
catch {
    Record-Test -Scenario "Additional Test 3: Error handling - invalid comment ID" -Passed $false -Details $_.Exception.Message
    Write-Host "  ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# ADDITIONAL TEST 4: Multiple updates to same comment
# ============================================================================
Write-Host "`n[ADDITIONAL TEST 4] Multiple updates to same comment" -ForegroundColor Yellow

try {
    $testEpic = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project `
        -Title "TestEpic_MultiUpdate_$(Get-Date -Format 'yyyyMMddHHmmss')" -ErrorAction Stop
    
    Register-CreatedItem -ItemId $testEpic.id
    
    # Create initial comment
    $comment = & "$SRC_DIR/NewAzDoComment.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $testEpic.id -Content "First version" -ErrorAction Stop
    
    $commentId = $comment.id
    $initialVersion = $comment.version
    
    # First update
    $update1 = & "$SRC_DIR/UpdateAzDoComment.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $testEpic.id -CommentId $commentId -Content "Second version" -ErrorAction Stop
    
    if ($update1.text -ne "Second version") {
        throw "First update failed"
    }
    
    if ($update1.version -le $initialVersion) {
        throw "Version not incremented after first update"
    }
    
    # Second update
    $update2 = & "$SRC_DIR/UpdateAzDoComment.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $testEpic.id -CommentId $commentId -Content "Third version" -ErrorAction Stop
    
    if ($update2.text -ne "Third version") {
        throw "Second update failed"
    }
    
    if ($update2.version -le $update1.version) {
        throw "Version not incremented after second update"
    }
    
    Record-Test -Scenario "Additional Test 4: Multiple updates to same comment" -Passed $true -Details "Multiple updates with version tracking"
    Write-Host "  ✓ PASSED: Multiple updates handled correctly" -ForegroundColor Green
}
catch {
    Record-Test -Scenario "Additional Test 4: Multiple updates to same comment" -Passed $false -Details $_.Exception.Message
    Write-Host "  ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# Cleanup and Summary
# ============================================================================

Cleanup-CreatedItems
$allPassed = Print-Summary

# Exit with appropriate code
exit ($allPassed ? 0 : 1)
