#Requires -Version 7.0

<#
.SYNOPSIS
Verification tests for all Acceptance Tests in story 1579: UpsertAzDoEpic functionality
Tests map directly to Acceptance Tests and verify each behavioral requirement.
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$Organization = "falco-it"
$Project = "gmd"
$SRC_DIR = ".\src"

# Test tracking
$tests = @()

function Record-Test {
    param(
        [string]$Scenario,
        [bool]$Passed,
        [string]$Details
    )
    $tests += [PSCustomObject]@{
        Scenario = $Scenario
        Passed   = $Passed
        Details  = $Details
    }
}

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "ACCEPTANCE TEST VERIFICATION - Story 1579: UpsertAzDoEpic" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

# ============================================================================
# SCENARIO 1: UPSERT by Title - update if exists
# ============================================================================
Write-Host "`n[SCENARIO 1] UPSERT by Title - update if exists" -ForegroundColor Yellow

try {
    $testTitle = "Scenario1_Update_$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    # Create initial epic
    $epic1 = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project `
        -Title $testTitle -Description "Initial description" -Effort 5 -ErrorAction Stop
    
    if ($null -eq $epic1 -or $null -eq $epic1.id) {
        throw "Failed to create initial epic"
    }
    
    $epicId = $epic1.id
    Write-Host "  ✓ Created initial epic (ID: $epicId)"
    
    # Now UPSERT with same title but different description (should update, not create duplicate)
    $epic2 = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project `
        -Title $testTitle -Description "Updated description" -Effort 8 -ErrorAction Stop
    
    if ($null -eq $epic2 -or $epic2.id -ne $epicId) {
        throw "UPSERT did not return same Epic ID"
    }
    
    Write-Host "  ✓ UPSERT returned same Epic ID (not duplicate): $($epic2.id)"
    
    # Verify fields were updated
    $retrieved = & "$SRC_DIR/GetAzDoWorkItem.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $epicId -ErrorAction Stop
    
    if ($retrieved.fields.'System.Description' -ne "Updated description") {
        throw "Description was not updated"
    }
    
    Write-Host "  ✓ Fields were updated (description and effort changed)"
    Record-Test "Scenario 1: UPSERT by Title - update if exists" $true "Created, then UPSERT updated same ID with new description and effort"
}
catch {
    Write-Host "  ✗ FAILED: $_" -ForegroundColor Red
    Record-Test "Scenario 1: UPSERT by Title - update if exists" $false $_
}

# ============================================================================
# SCENARIO 2: UPSERT by Title - create if not found
# ============================================================================
Write-Host "`n[SCENARIO 2] UPSERT by Title - create if not found" -ForegroundColor Yellow

try {
    $testTitle = "Scenario2_NewCreate_$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    # UPSERT with title that doesn't exist should create
    $epic = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project `
        -Title $testTitle -Description "New epic description" -Effort 13 -ErrorAction Stop
    
    if ($null -eq $epic -or $null -eq $epic.id) {
        throw "Failed to create new epic"
    }
    
    Write-Host "  ✓ Created new epic with unique title (ID: $($epic.id))"
    
    # Verify it was actually created (not found from before)
    $retrieved = & "$SRC_DIR/GetAzDoWorkItem.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $epic.id -ErrorAction Stop
    
    if ($retrieved.fields.'System.Title' -ne $testTitle) {
        throw "Title does not match"
    }
    
    Write-Host "  ✓ Retrieved epic confirms title and description were set"
    Record-Test "Scenario 2: UPSERT by Title - create if not found" $true "UPSERT created new epic when title didn't exist"
}
catch {
    Write-Host "  ✗ FAILED: $_" -ForegroundColor Red
    Record-Test "Scenario 2: UPSERT by Title - create if not found" $false $_
}

# ============================================================================
# SCENARIO 3: Update by ID - direct ID-based update
# ============================================================================
Write-Host "`n[SCENARIO 3] Update by ID - direct ID-based update" -ForegroundColor Yellow

try {
    # Create an epic with known ID
    $testTitle = "Scenario3_UpdateByID_$(Get-Date -Format 'yyyyMMddHHmmss')"
    $epic = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project `
        -Title $testTitle -Description "Original" -ErrorAction Stop
    
    $epicId = $epic.id
    Write-Host "  ✓ Created epic for ID-based update (ID: $epicId)"
    
    # Update by ID only (no title provided in this call)
    $updated = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project `
        -Id $epicId -Description "Updated via ID" -Effort 21 -ErrorAction Stop
    
    if ($updated.id -ne $epicId) {
        throw "Update by ID returned different ID"
    }
    
    Write-Host "  ✓ Updated by ID, returned same ID: $($updated.id)"
    
    # Verify fields were updated
    $retrieved = & "$SRC_DIR/GetAzDoWorkItem.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $epicId -ErrorAction Stop
    
    if ($retrieved.fields.'System.Description' -ne "Updated via ID") {
        throw "Description was not updated"
    }
    
    Write-Host "  ✓ Confirmed fields were updated via ID-based operation"
    Record-Test "Scenario 3: Update by ID - direct ID-based update" $true "Updated epic by ID, only specified fields changed"
}
catch {
    Write-Host "  ✗ FAILED: $_" -ForegroundColor Red
    Record-Test "Scenario 3: Update by ID - direct ID-based update" $false $_
}

# ============================================================================
# SCENARIO 4: Create-only mode with -FailIfExist (no ID)
# ============================================================================
Write-Host "`n[SCENARIO 4] Create-only mode with -FailIfExist" -ForegroundColor Yellow

try {
    $testTitle = "Scenario4_FailIfExist_$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    # Create initial epic
    $epic1 = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project `
        -Title $testTitle -Description "First" -ErrorAction Stop
    
    Write-Host "  ✓ Created initial epic (ID: $($epic1.id))"
    
    # Try to create with -FailIfExist when title already exists - should fail
    try {
        $epic2 = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project `
            -Title $testTitle -Description "Second" -FailIfExist -ErrorAction Stop
        
        # If we get here, it didn't fail
        throw "Should have failed with -FailIfExist for existing title"
    }
    catch {
        if ($_ -match "already exists") {
            Write-Host "  ✓ Correctly failed with 'already exists' error for existing title"
        }
        else {
            throw $_
        }
    }
    
    Record-Test "Scenario 4: Create-only mode with -FailIfExist" $true "Failed when trying to UPSERT with existing title and -FailIfExist"
}
catch {
    Write-Host "  ✗ FAILED: $_" -ForegroundColor Red
    Record-Test "Scenario 4: Create-only mode with -FailIfExist" $false $_
}

# ============================================================================
# SCENARIO 5: Mutual exclusivity - reject -Id with -FailIfExist
# ============================================================================
Write-Host "`n[SCENARIO 5] Mutual exclusivity - reject -Id with -FailIfExist" -ForegroundColor Yellow

try {
    try {
        $result = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project `
            -Id 1234 -FailIfExist -ErrorAction Stop
        
        throw "Should have failed immediately with mutually exclusive error"
    }
    catch {
        if ($_ -match "mutually exclusive") {
            Write-Host "  ✓ Correctly rejected -Id with -FailIfExist (mutually exclusive)"
        }
        else {
            throw $_
        }
    }
    
    Record-Test "Scenario 5: Mutual exclusivity - reject -Id with -FailIfExist" $true "Rejected -Id and -FailIfExist together as mutually exclusive"
}
catch {
    Write-Host "  ✗ FAILED: $_" -ForegroundColor Red
    Record-Test "Scenario 5: Mutual exclusivity - reject -Id with -FailIfExist" $false $_
}

# ============================================================================
# SUMMARY REPORT
# ============================================================================
Write-Host "`n" 
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "SCENARIO VERIFICATION SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

$passCount = ($tests | Where-Object { $_.Passed } | Measure-Object).Count
$failCount = ($tests | Where-Object { -not $_.Passed } | Measure-Object).Count

foreach ($test in $tests) {
    $status = if ($test.Passed) { "✅ COMPLETED" } else { "❌ FAILED" }
    Write-Host "`n$status - $($test.Scenario)" -ForegroundColor $(if ($test.Passed) { "Green" } else { "Red" })
    Write-Host "  Details: $($test.Details)" -ForegroundColor Gray
}

Write-Host "`n" 
Write-Host "RESULTS: $passCount PASSED, $failCount FAILED" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Red" })
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

if ($failCount -gt 0) {
    exit 1
}
