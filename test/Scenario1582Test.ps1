#Requires -Version 7.0

<#
.SYNOPSIS
Verification tests for all Acceptance Tests in story 1582: UpsertAzDoTask and RemoveAzDoTask functionality
Tests map directly to Acceptance Tests and verify each behavioral requirement.
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$Organization = "falco-it"
$Project = "gmd"
$SRC_DIR = ".\src"

# Test tracking - initialize as array-based list
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
            & "$SRC_DIR/RemoveAzDoTask.ps1" -Organization $Organization -Project $Project -TaskId $itemId -Force -ErrorAction SilentlyContinue | Out-Null
            Write-Host "  Cleaned up Task ID: $itemId" -ForegroundColor Green
        }
        catch {
            Write-Host "  Warning: Failed to clean up Task ID: $itemId" -ForegroundColor Yellow
        }
    }
    
    # Also clean up stories if any were created for testing
    # (These would be parent stories created for task linking tests)
}

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "ACCEPTANCE TEST VERIFICATION - Story 1582: UpsertAzDoTask & RemoveAzDoTask" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

# ============================================================================
# SCENARIO 1: UPSERT by Title - update if exists
# ============================================================================
Write-Host "`n[SCENARIO 1] UPSERT by Title - update if exists" -ForegroundColor Yellow

try {
    $testTitle = "Scenario1_Update_$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    # Create a test story first (parent for task)
    $testStory = & "$SRC_DIR/UpsertAzDoStory.ps1" -Organization $Organization -Project $Project `
        -Title "ParentTestStory_1582_S1_$(Get-Date -Format 'yyyyMMddHHmmss')" -ErrorAction Stop
    
    if ($null -eq $testStory -or $null -eq $testStory.id) {
        throw "Failed to create test story"
    }
    Register-CreatedItem -ItemId $testStory.id
    
    # Create initial task
    $task1 = & "$SRC_DIR/UpsertAzDoTask.ps1" -Organization $Organization -Project $Project `
        -Title $testTitle -Description "Initial description" -ErrorAction Stop
    
    if ($null -eq $task1 -or $null -eq $task1.id) {
        throw "Failed to create initial task"
    }
    Register-CreatedItem -ItemId $task1.id
    
    # Now update the same task by title
    $task1Updated = & "$SRC_DIR/UpsertAzDoTask.ps1" -Organization $Organization -Project $Project `
        -Title $testTitle -Description "Updated description" -Priority 2 -OriginalEstimate 8 -RemainingWork 8 -ErrorAction Stop
    
    if ($task1Updated.id -ne $task1.id) {
        throw "Task ID changed after update - should be same ID"
    }
    
    if ($task1Updated.fields.'System.Description' -ne "Updated description") {
        throw "Description was not updated"
    }
    
    if ($task1Updated.fields.'Microsoft.VSTS.Common.Priority' -ne 2) {
        throw "Priority was not updated"
    }
    
    if ($task1Updated.fields.'Microsoft.VSTS.Scheduling.OriginalEstimate' -ne 8) {
        throw "OriginalEstimate was not updated"
    }
    
    if ($task1Updated.fields.'Microsoft.VSTS.Scheduling.RemainingWork' -ne 8) {
        throw "RemainingWork was not updated"
    }
    
    Record-Test -Scenario "UPSERT by Title - update if exists" -Passed $true -Details "Task correctly updated by title, same ID retained"
    Write-Host "  ✓ PASSED: Task updated correctly by title, same ID" -ForegroundColor Green
}
catch {
    Record-Test -Scenario "UPSERT by Title - update if exists" -Passed $false -Details $_.Exception.Message
    Write-Host "  ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# SCENARIO 2: UPSERT by Title - create if not found
# ============================================================================
Write-Host "`n[SCENARIO 2] UPSERT by Title - create if not found" -ForegroundColor Yellow

try {
    $testTitle2 = "Scenario2_Create_$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    # Create a parent story
    $testStory2 = & "$SRC_DIR/UpsertAzDoStory.ps1" -Organization $Organization -Project $Project `
        -Title "ParentTestStory_1582_S2_$(Get-Date -Format 'yyyyMMddHHmmss')" -ErrorAction Stop
    
    Register-CreatedItem -ItemId $testStory2.id
    
    # Create new task (title does not exist yet)
    $newTask = & "$SRC_DIR/UpsertAzDoTask.ps1" -Organization $Organization -Project $Project `
        -Title $testTitle2 -Description "New task description" -Priority 1 -OriginalEstimate 13 -RemainingWork 13 -ParentStoryId $testStory2.id -ErrorAction Stop
    
    if ($null -eq $newTask -or $null -eq $newTask.id) {
        throw "Failed to create new task"
    }
    Register-CreatedItem -ItemId $newTask.id
    
    if ($newTask.fields.'System.Title' -ne $testTitle2) {
        throw "Task title does not match"
    }
    
    if ($newTask.fields.'System.Description' -ne "New task description") {
        throw "Task description not set correctly"
    }
    
    # Verify parent link was created
    if ($newTask.fields.'System.Parent' -ne $testStory2.id) {
        throw "Parent Story ID not linked correctly"
    }
    
    Record-Test -Scenario "UPSERT by Title - create if not found" -Passed $true -Details "New task created with all fields and parent link"
    Write-Host "  ✓ PASSED: New task created successfully with parent link" -ForegroundColor Green
}
catch {
    Record-Test -Scenario "UPSERT by Title - create if not found" -Passed $false -Details $_.Exception.Message
    Write-Host "  ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# SCENARIO 3: Update by ID - direct ID-based update
# ============================================================================
Write-Host "`n[SCENARIO 3] Update by ID - direct ID-based update" -ForegroundColor Yellow

try {
    $testTitle3 = "Scenario3_IdUpdate_$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    # Create a task
    $task3 = & "$SRC_DIR/UpsertAzDoTask.ps1" -Organization $Organization -Project $Project `
        -Title $testTitle3 -Description "Original description" -ErrorAction Stop
    
    Register-CreatedItem -ItemId $task3.id
    
    # Update by ID with different description and priority
    $task3Updated = & "$SRC_DIR/UpsertAzDoTask.ps1" -Organization $Organization -Project $Project `
        -Id $task3.id -Description "Updated description" -Priority 3 -OriginalEstimate 5 -ErrorAction Stop
    
    if ($task3Updated.id -ne $task3.id) {
        throw "Task ID mismatched"
    }
    
    if ($task3Updated.fields.'System.Description' -ne "Updated description") {
        throw "Description was not updated"
    }
    
    if ($task3Updated.fields.'Microsoft.VSTS.Common.Priority' -ne 3) {
        throw "Priority was not updated to 3"
    }
    
    if ($task3Updated.fields.'Microsoft.VSTS.Scheduling.OriginalEstimate' -ne 5) {
        throw "OriginalEstimate was not updated to 5"
    }
    
    Record-Test -Scenario "Update by ID - direct ID-based update" -Passed $true -Details "Task updated by ID with multiple fields changed"
    Write-Host "  ✓ PASSED: Task updated by ID successfully" -ForegroundColor Green
}
catch {
    Record-Test -Scenario "Update by ID - direct ID-based update" -Passed $false -Details $_.Exception.Message
    Write-Host "  ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# SCENARIO 4: Create-only mode with -FailIfExist (no ID)
# ============================================================================
Write-Host "`n[SCENARIO 4] Create-only mode with -FailIfExist (no ID)" -ForegroundColor Yellow

try {
    $testTitle4 = "Scenario4_FailIfExist_$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    # Create a task first
    $task4a = & "$SRC_DIR/UpsertAzDoTask.ps1" -Organization $Organization -Project $Project `
        -Title $testTitle4 -Description "First task" -ErrorAction Stop
    
    Register-CreatedItem -ItemId $task4a.id
    
    # Try to create again with -FailIfExist (should fail)
    $failedAsExpected = $false
    try {
        $task4b = & "$SRC_DIR/UpsertAzDoTask.ps1" -Organization $Organization -Project $Project `
            -Title $testTitle4 -Description "Second task" -FailIfExist -ErrorAction Stop
    }
    catch {
        if ($_.Exception.Message -like "*already exists*") {
            $failedAsExpected = $true
        }
    }
    
    if (-not $failedAsExpected) {
        throw "Expected operation to fail with 'already exists' error"
    }
    
    Record-Test -Scenario "Create-only mode with -FailIfExist" -Passed $true -Details "Operation correctly failed when title already exists"
    Write-Host "  ✓ PASSED: -FailIfExist correctly prevented duplicate creation" -ForegroundColor Green
}
catch {
    Record-Test -Scenario "Create-only mode with -FailIfExist" -Passed $false -Details $_.Exception.Message
    Write-Host "  ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# SCENARIO 5: Delete Task with confirmation prompt
# ============================================================================
Write-Host "`n[SCENARIO 5] Delete Task with confirmation prompt (using -Force)" -ForegroundColor Yellow

try {
    $testTitle5 = "Scenario5_Delete_$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    # Create a task
    $task5 = & "$SRC_DIR/UpsertAzDoTask.ps1" -Organization $Organization -Project $Project `
        -Title $testTitle5 -Description "Task to delete" -ErrorAction Stop
    
    if ($null -eq $task5 -or $null -eq $task5.id) {
        throw "Failed to create task for deletion test"
    }
    
    # Delete it with -Force (to bypass confirmation prompt in automated test)
    $deleteResult = & "$SRC_DIR/RemoveAzDoTask.ps1" -Organization $Organization -Project $Project `
        -TaskId $task5.id -Force -ErrorAction Stop
    
    if ($deleteResult.Cancelled -eq $true) {
        throw "Deletion was cancelled unexpectedly"
    }
    
    if ($deleteResult.DeletedCount -ne 1) {
        throw "DeletedCount should be 1"
    }
    
    # Verify task no longer exists by trying to retrieve it (should throw 404)
    $deletionVerified = $false
    try {
        & "$SRC_DIR/GetAzDoWorkItem.ps1" -Organization $Organization -Project $Project `
            -WorkItemId $task5.id -ErrorAction Stop | Out-Null
    }
    catch {
        # Expected: 404 not found error means deletion succeeded
        if ($_ -match "404|not found|does not exist") {
            $deletionVerified = $true
        }
    }
    
    if (-not $deletionVerified) {
        throw "Task still exists after deletion or unexpected error"
    }
    
    Record-Test -Scenario "Delete Task with confirmation" -Passed $true -Details "Task deleted successfully"
    Write-Host "  ✓ PASSED: Task deleted successfully with -Force" -ForegroundColor Green
}
catch {
    Record-Test -Scenario "Delete Task with confirmation" -Passed $false -Details $_.Exception.Message
    Write-Host "  ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# SCENARIO 6: Force delete Task without prompt
# ============================================================================
Write-Host "`n[SCENARIO 6] Force delete Task without prompt" -ForegroundColor Yellow

try {
    $testTitle6 = "Scenario6_ForceDelete_$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    # Create a task
    $task6 = & "$SRC_DIR/UpsertAzDoTask.ps1" -Organization $Organization -Project $Project `
        -Title $testTitle6 -Description "Task to force delete" -ErrorAction Stop
    
    if ($null -eq $task6 -or $null -eq $task6.id) {
        throw "Failed to create task for force delete test"
    }
    
    # Force delete (no prompt)
    $deleteResult = & "$SRC_DIR/RemoveAzDoTask.ps1" -Organization $Organization -Project $Project `
        -TaskId $task6.id -Force -ErrorAction Stop
    
    if ($deleteResult.DeletedCount -ne 1) {
        throw "DeletedCount should be 1"
    }
    
    # Verify deletion
    $deletionVerified = $false
    try {
        & "$SRC_DIR/GetAzDoWorkItem.ps1" -Organization $Organization -Project $Project `
            -WorkItemId $task6.id -ErrorAction Stop | Out-Null
    }
    catch {
        # Expected: 404 not found error means deletion succeeded
        if ($_ -match "404|not found|does not exist") {
            $deletionVerified = $true
        }
    }
    
    if (-not $deletionVerified) {
        throw "Task still exists after force delete or unexpected error"
    }
    
    Record-Test -Scenario "Force delete Task without prompt" -Passed $true -Details "Task force deleted successfully"
    Write-Host "  ✓ PASSED: Task force deleted successfully" -ForegroundColor Green
}
catch {
    Record-Test -Scenario "Force delete Task without prompt" -Passed $false -Details $_.Exception.Message
    Write-Host "  ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# Test Summary
# ============================================================================

Cleanup-CreatedItems

Write-Host "`n" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

$passCount = @($tests | Where-Object { $_.Passed -eq $true }).Count
$failCount = @($tests | Where-Object { $_.Passed -eq $false }).Count
$totalCount = @($tests).Count

Write-Host "`nTotal Tests: $totalCount"
Write-Host "Passed: $passCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })

Write-Host "`nTest Results:" -ForegroundColor Cyan
$tests | Format-Table -Property Scenario, Passed, Details -AutoSize

if ($failCount -gt 0) {
    Write-Host "`n✗ Some tests FAILED" -ForegroundColor Red
    exit 1
}
else {
    Write-Host "`n✓ All tests PASSED" -ForegroundColor Green
    exit 0
}
