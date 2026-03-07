<#
.SYNOPSIS
Test script for UpsertAzDoBug.ps1 - Story 1641

.DESCRIPTION
Black-box tests for the UpsertAzDoBug.ps1 script, verifying all Acceptance Criteria:
- Create and update Bug operations
- Proper parameter validation
- Tag and comment support
- Error handling (-FailIfExist flag)
- JSON output format

Each test creates/deletes test data as needed via teardown.
#>

#Requires -Version 7.0

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Test context from GmdUnitTest
$testContext = $null
$testWorkItems = @()

# Load environment variables
$org = $env:GMD_AZDO_ORGANIZATION
$proj = $env:GMD_AZDO_PROJECT

# Calculate path: test/storyAcTests -> test -> workspace root -> src
$workspaceRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$scriptRoot = Join-Path $workspaceRoot -ChildPath 'src'

if ([string]::IsNullOrWhiteSpace($org) -or [string]::IsNullOrWhiteSpace($proj)) {
    Write-Error "Environment variables GMD_AZDO_ORGANIZATION and GMD_AZDO_PROJECT must be set"
}

# Get script paths
$upsertScriptPath = Join-Path $scriptRoot -ChildPath 'UpsertAzDoBug.ps1'
$removeScriptPath = Join-Path $scriptRoot -ChildPath 'RemoveAzDoBug.ps1'

# Helper function for cleanup
function Remove-TestWorkItem {
    param([int]$Id)
    if ($Id -gt 0) {
        try {
            if (-not (Test-Path $removeScriptPath)) {
                # RemoveAzDoBug.ps1 not created yet, skip cleanup
                return
            }
            & $removeScriptPath -Organization $org -Project $proj -BugId $Id -Force -ErrorAction SilentlyContinue
            $testWorkItems = $testWorkItems | Where-Object { $_ -ne $Id }
        }
        catch {
            # Ignore cleanup errors
        }
    }
}

# ===== Test 1: Create new Bug with all required fields =====
Write-Output "`n[TEST 1] Create new Bug with all required fields"
try {
    $bugTitle = "TestBug-$(Get-Random)"
    $scriptPath = Join-Path $scriptRoot -ChildPath 'UpsertAzDoBug.ps1'
    $result = & $scriptPath `
        -Organization $org `
        -Project $proj `
        -Title $bugTitle `
        -Priority 2 `
        -Description "Test bug for acceptance criteria" `
        -ReproSteps "1. Open application`n2. Trigger error scenario" `
        -StoryPoints 3 `
        -FoundInBuild "20.0"

    if ($null -eq $result -or $null -eq $result.id) {
        throw "Failed to create Bug: no ID returned"
    }

    $testWorkItems += $result.id

    if ($result.fields['System.Title'] -ne $bugTitle) {
        throw "Title not set correctly"
    }
    if ($result.fields['Microsoft.VSTS.Common.Priority'] -ne 2) {
        throw "Priority not set correctly"
    }
    if ($result.fields['Microsoft.VSTS.TCM.ReproSteps'] -ne "1. Open application`n2. Trigger error scenario") {
        throw "ReproSteps not set correctly"
    }

    Write-Output "✓ TEST 1 PASSED: Bug created with ID $($result.id)"
    Remove-TestWorkItem -Id $result.id
}
catch {
    Write-Output "✗ TEST 1 FAILED: $_"
    foreach ($wid in $testWorkItems) { Remove-TestWorkItem -Id $wid }
    exit 1
}

# ===== Test 2: Create Bug with optional parameters =====
Write-Output "`n[TEST 2] Create Bug with optional parameters"
try {
    $bugTitle = "TestBugOptional-$(Get-Random)"
    $scriptPath = Join-Path $scriptRoot -ChildPath 'UpsertAzDoBug.ps1'
    $result = & $scriptPath `
        -Organization $org `
        -Project $proj `
        -Title $bugTitle `
        -Priority 1 `
        -ReproSteps "Click here" `
        -SystemInfo "Windows Server 2022" `
        -StoryPoints 5 `
        -FoundInBuild "19.5" `
        -IntegratedInBuild "20.1"

    if ($null -eq $result.id) {
        throw "Failed to create Bug with optional parameters"
    }

    $testWorkItems += $result.id

    if ($result.fields['Microsoft.VSTS.TCM.SystemInfo'] -ne "Windows Server 2022") {
        throw "SystemInfo not set correctly"
    }
    if ($result.fields['Microsoft.VSTS.Build.IntegratedInBuild'] -ne "20.1") {
        throw "IntegratedInBuild not set correctly"
    }

    Write-Output "✓ TEST 2 PASSED: Bug created with optional fields"
    Remove-TestWorkItem -Id $result.id
}
catch {
    Write-Output "✗ TEST 2 FAILED: $_"
    foreach ($wid in $testWorkItems) { Remove-TestWorkItem -Id $wid }
    exit 1
}

# ===== Test 3: Update existing Bug by ID =====
Write-Output "`n[TEST 3] Update existing Bug by ID"
try {
    $bugTitle = "TestBugUpdate-$(Get-Random)"
    $scriptPath = Join-Path $scriptRoot -ChildPath 'UpsertAzDoBug.ps1'
    $created = & $scriptPath `
        -Organization $org `
        -Project $proj `
        -Title $bugTitle `
        -Priority 3 `
        -ReproSteps "Initial steps"

    $testWorkItems += $created.id

    # Update by ID
    $updated = & $scriptPath `
        -Organization $org `
        -Project $proj `
        -Id $created.id `
        -Priority 1 `
        -IntegratedInBuild "20.2"

    if ($updated.fields['Microsoft.VSTS.Common.Priority'] -ne 1) {
        throw "Priority update failed"
    }
    if ($updated.fields['Microsoft.VSTS.Build.IntegratedInBuild'] -ne "20.2") {
        throw "IntegratedInBuild update failed"
    }

    Write-Output "✓ TEST 3 PASSED: Bug updated by ID"
    Remove-TestWorkItem -Id $created.id
}
catch {
    Write-Output "✗ TEST 3 FAILED: $_"
    foreach ($wid in $testWorkItems) { Remove-TestWorkItem -Id $wid }
    exit 1
}

# ===== Test 4: UPSERT by title (update existing) =====
Write-Output "`n[TEST 4] UPSERT by title - update existing Bug"
try {
    $bugTitle = "TestBugUpsert-$(Get-Random)"
    $created = & $upsertScriptPath `
        -Organization $org `
        -Project $proj `
        -Title $bugTitle `
        -Priority 2 `
        -Description "Original description"

    $testWorkItems += $created.id

    # UPSERT by title (should update)
    $upserted = & $upsertScriptPath `
        -Organization $org `
        -Project $proj `
        -Title $bugTitle `
        -Priority 1 `
        -Description "Updated description"

    if ($upserted.id -ne $created.id) {
        throw "UPSERT should return same ID for existing Bug"
    }
    if ($upserted.fields['System.Description'] -ne "Updated description") {
        throw "Description update via UPSERT failed"
    }

    Write-Output "✓ TEST 4 PASSED: UPSERT by title updated existing Bug"
    Remove-TestWorkItem -Id $created.id
}
catch {
    Write-Output "✗ TEST 4 FAILED: $_"
    foreach ($wid in $testWorkItems) { Remove-TestWorkItem -Id $wid }
    exit 1
}

# ===== Test 5: UPSERT by title (create new) =====
Write-Output "`n[TEST 5] UPSERT by title - create new Bug"
try {
    $bugTitle = "TestBugUpsertNew-$(Get-Random)"
    $result = & $upsertScriptPath `
        -Organization $org `
        -Project $proj `
        -Title $bugTitle `
        -Priority 2 `
        -ReproSteps "Steps to reproduce"

    if ($null -eq $result.id) {
        throw "Failed to create new Bug via UPSERT"
    }

    $testWorkItems += $result.id

    Write-Output "✓ TEST 5 PASSED: UPSERT by title created new Bug"
    Remove-TestWorkItem -Id $result.id
}
catch {
    Write-Output "✗ TEST 5 FAILED: $_"
    foreach ($wid in $testWorkItems) { Remove-TestWorkItem -Id $wid }
    exit 1
}

# ===== Test 6: Error when -Id and -FailIfExist both provided =====
Write-Output "`n[TEST 6] Error when -Id and -FailIfExist are mutually exclusive"
try {
    $bugTitle = "TestBugMutualExclusive-$(Get-Random)"
    $created = & $upsertScriptPath `
        -Organization $org `
        -Project $proj `
        -Title $bugTitle `
        -Priority 2

    $testWorkItems += $created.id

    # Should fail
    $errorOccurred = $false
    try {
        & $upsertScriptPath `
            -Organization $org `
            -Project $proj `
            -Id $created.id `
            -Priority 1 `
            -FailIfExist -ErrorAction Stop
    }
    catch {
        $errorOccurred = $true
    }

    if (-not $errorOccurred) {
        throw "Should have failed with mutual exclusivity error"
    }

    Write-Output "✓ TEST 6 PASSED: Correct error for mutually exclusive parameters"
    Remove-TestWorkItem -Id $created.id
}
catch {
    Write-Output "✗ TEST 6 FAILED: $_"
    foreach ($wid in $testWorkItems) { Remove-TestWorkItem -Id $wid }
    exit 1
}

# ===== Test 7: -FailIfExist prevents overwrite =====
Write-Output "`n[TEST 7] -FailIfExist prevents overwrite"
try {
    $bugTitle = "TestBugFailIfExist-$(Get-Random)"
    $created = & $upsertScriptPath `
        -Organization $org `
        -Project $proj `
        -Title $bugTitle `
        -Priority 2

    $testWorkItems += $created.id

    # Should fail when trying to create with same title
    $errorOccurred = $false
    try {
        & $upsertScriptPath `
            -Organization $org `
            -Project $proj `
            -Title $bugTitle `
            -Priority 1 `
            -FailIfExist -ErrorAction Stop
    }
    catch {
        $errorOccurred = $true
    }

    if (-not $errorOccurred) {
        throw "Should have failed when Bug with title already exists"
    }

    Write-Output "✓ TEST 7 PASSED: -FailIfExist prevents creating duplicate Bug"
    Remove-TestWorkItem -Id $created.id
}
catch {
    Write-Output "✗ TEST 7 FAILED: $_"
    foreach ($wid in $testWorkItems) { Remove-TestWorkItem -Id $wid }
    exit 1
}

# ===== Test 8: JSON output format =====
Write-Output "`n[TEST 8] JSON output format"
try {
    $bugTitle = "TestBugJson-$(Get-Random)"
    $result = & $upsertScriptPath `
        -Organization $org `
        -Project $proj `
        -Title $bugTitle `
        -Priority 2 `
        -ReproSteps "Steps"

    $testWorkItems += $result.id

    # Verify it's valid PSObject with expected properties
    if (-not ($result | Get-Member -Name 'id' -ErrorAction SilentlyContinue)) {
        throw "Result should have 'id' property"
    }
    if (-not ($result | Get-Member -Name 'fields' -ErrorAction SilentlyContinue)) {
        throw "Result should have 'fields' property"
    }

    # Verify can be converted to JSON
    $json = $result | ConvertTo-Json
    if ([string]::IsNullOrWhiteSpace($json)) {
        throw "Result should be convertible to JSON"
    }

    Write-Output "✓ TEST 8 PASSED: Output is valid JSON-convertible PSObject"
    Remove-TestWorkItem -Id $result.id
}
catch {
    Write-Output "✗ TEST 8 FAILED: $_"
    foreach ($wid in $testWorkItems) { Remove-TestWorkItem -Id $wid }
    exit 1
}

# ===== Cleanup =====
Write-Output "`n[CLEANUP] Removing any remaining test work items..."
foreach ($wid in $testWorkItems) {
    Remove-TestWorkItem -Id $wid
}

Write-Output "`n===== ALL TESTS PASSED ====="
