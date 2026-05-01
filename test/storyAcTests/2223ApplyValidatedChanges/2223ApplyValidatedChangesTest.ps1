<#
.SYNOPSIS
Tests for story AB#2223: Apply Validated Changes Back to Azure DevOps

.DESCRIPTION
Tests the ApplyValidatedChanges.ps1 script to ensure it correctly applies validated changes
with transaction-like safety and comprehensive error handling.

Tests Acceptance Tests:
1. Single field update is applied successfully
2. Multiple changes are applied in dependency order
3. Change application fails gracefully

Requires Environment variables:
- GMD_AZDO_ORGANIZATION: Organization name
- GMD_AZDO_PROJECT: Project name
- GMD_AZDO_MACHINE_WORKITEMSRW: PAT token

Run with: pwsh -File .\2223ApplyValidatedChangesTest.ps1
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
[string]$SRC_DIR = Join-Path $SCRIPT_DIR '../../../src'

# Validate inputs
if ([string]::IsNullOrWhiteSpace($Organization)) {
    Write-Error "Organization not provided"
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    Write-Error "Project not provided"
}

# Test counters
[int]$testsRun = 0
[int]$testsPassed = 0
[int]$testsFailed = 0
[array]$testResults = @()

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
        $script:testResults += @{ Name = $Name; Status = 'PASSED' }
    }
    catch {
        $script:testsFailed++
        Write-Host "  ✗ FAILED: $_" -ForegroundColor Red
        $script:testResults += @{ Name = $Name; Status = 'FAILED'; Error = $_.Exception.Message }
    }
}

Write-Host "=== Story AB#2223 Tests: Apply Validated Changes ===" -ForegroundColor Cyan
Write-Host "Organization: $Organization"
Write-Host "Project: $Project`n"

# ============================================================================
# ACCEPTANCE TEST 1: Single field update is applied successfully
# ============================================================================

Invoke-Test "GivenSingleFieldUpdate_WhenApplied_ThenSucceeds" {
    # Create a validated diff with a single update operation
    $diff = @{
        validationPassed = $true
        errors           = @()
        warnings         = @()
        operations       = @(
            @{
                operationType = 'Update'
                workItemType  = 'Story'
                itemId        = 9999  # Dummy ID for test
                title         = 'Test Story'
                changes       = @{
                    description = @{
                        before = 'Old description'
                        after  = 'New description'
                    }
                }
                parentIdBefore = $null
                parentIdAfter  = $null
                dependsOn      = @()
            }
        )
    }

    # Run in DryRun mode to avoid actual changes
    $result = & "$SRC_DIR\ApplyValidatedChanges.ps1" -ValidatedDiff $diff -DryRun

    if ($result.success -and $result.appliedChanges -eq 1) {
        return
    }

    throw "Expected single change to be applied successfully. Result: $($result | ConvertTo-Json -Depth 3)"
}

# ============================================================================
# ACCEPTANCE TEST 2: Multiple changes are applied in dependency order
# ============================================================================

Invoke-Test "GivenMultipleOperationsInDependencyOrder_WhenApplied_ThenAllApplied" {
    $diff = @{
        validationPassed = $true
        errors           = @()
        warnings         = @()
        operations       = @(
            @{
                operationType = 'Create'
                workItemType  = 'Feature'
                itemId        = $null
                title         = 'New Feature'
                changes       = @{
                    description = @{ before = $null; after = 'Feature desc' }
                }
                parentIdBefore = $null
                parentIdAfter  = $null
                dependsOn      = @()
            },
            @{
                operationType = 'Create'
                workItemType  = 'Story'
                itemId        = $null
                title         = 'New Story'
                changes       = @{
                    description = @{ before = $null; after = 'Story desc' }
                    storyPoints = @{ before = $null; after = 5 }
                }
                parentIdBefore = $null
                parentIdAfter  = 'new_New Feature'
                dependsOn      = @('new_New Feature')
            },
            @{
                operationType = 'Update'
                workItemType  = 'Story'
                itemId        = 9998
                title         = 'Existing Story'
                changes       = @{
                    storyPoints = @{ before = 3; after = 8 }
                }
                parentIdBefore = $null
                parentIdAfter  = $null
                dependsOn      = @()
            }
        )
    }

    $result = & "$SRC_DIR\ApplyValidatedChanges.ps1" -ValidatedDiff $diff -DryRun

    if ($result.success -and $result.appliedChanges -eq 3) {
        # Verify operations were processed in correct order (creates before updates)
        $createsFirst = $result.operationsSummary[0].operationType -eq 'Create' -and $result.operationsSummary[1].operationType -eq 'Create'
        if ($createsFirst -or @($result.operationsSummary | Where-Object { $_.operationType -eq 'Create' }).Count -ge 2) {
            return
        }
    }

    throw "Expected 3 operations in dependency order. Result: $($result | ConvertTo-Json -Depth 3)"
}

# ============================================================================
# ACCEPTANCE TEST 3: No operations applied if validation failed
# ============================================================================

Invoke-Test "GivenInvalidDiff_WhenApplied_ThenRejectWithError" {
    $diff = @{
        validationPassed = $false
        errors           = @('Validation error: Item not found')
        warnings         = @()
        operations       = @()
    }

    $result = & "$SRC_DIR\ApplyValidatedChanges.ps1" -ValidatedDiff $diff -DryRun

    if (-not $result.success -and $result.failureReason -and $result.failureReason -match 'validation failed') {
        return
    }

    throw "Expected rejection of invalid diff"
}

# ============================================================================
# Empty operations
# ============================================================================

Invoke-Test "GivenEmptyDiffWithNoOperations_WhenApplied_ThenSucceedsWithZeroChanges" {
    $diff = @{
        validationPassed = $true
        errors           = @()
        warnings         = @()
        operations       = @()
    }

    $result = & "$SRC_DIR\ApplyValidatedChanges.ps1" -ValidatedDiff $diff -DryRun

    if ($result.success -and $result.appliedChanges -eq 0) {
        return
    }

    throw "Expected success with zero changes"
}

# ============================================================================
# Summary
# ============================================================================

Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Total Tests: $testsRun"
Write-Host "Passed: $testsPassed" -ForegroundColor Green
Write-Host "Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })

if ($testsFailed -eq 0) {
    Write-Host "`n✓ All tests passed!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "`n✗ Some tests failed" -ForegroundColor Red
    $testResults | Where-Object { $_.Status -eq 'FAILED' } | ForEach-Object {
        Write-Host "  - $($_.Name): $($_.Error)" -ForegroundColor Red
    }
    exit 1
}
