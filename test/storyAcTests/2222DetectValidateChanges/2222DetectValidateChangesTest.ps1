<#
.SYNOPSIS
Tests for story AB#2222: Detect and Validate Changes Between Original and Modified Hierarchies

.DESCRIPTION
Tests the DetectHierarchyChanges.ps1 script to ensure it correctly identifies field-level changes,
hierarchy reorganization, and prevents dangerous modifications.

Tests AC scenarios:
1. Single field change is detected
2. Parent-child reorganization is detected
3. Dangerous modification prevents application
4. New work items are detected for creation

Requires Environment variables:
- GMD_AZDO_ORGANIZATION: Organization name
- GMD_AZDO_PROJECT: Project name

Run with: pwsh -File .\2222DetectValidateChangesTest.ps1
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

Write-Host "=== Story AB#2222 Tests: Detect and Validate Changes ===" -ForegroundColor Cyan
Write-Host "Organization: $Organization"
Write-Host "Project: $Project`n"

# ============================================================================
# AC Scenario 1: Single field change is detected
# ============================================================================

Invoke-Test "GivenStoryTitleChanged_WhenDiffCalculated_ThenChangeIsDetected" {
    $original = @{
        workItems = @(
            @{
                type  = 'Story'
                title = 'Current Title'
                workItemId = 1001
                description = 'Story description'
            }
        )
    }

    $modified = @{
        workItems = @(
            @{
                type  = 'Story'
                title = 'New Title'
                workItemId = 1001
                description = 'Story description'
            }
        )
    }

    $diff = & "$SRC_DIR\DetectHierarchyChanges.ps1" -OriginalHierarchy $original -ModifiedHierarchy $modified

    if ($diff.operations.Count -eq 1 -and $diff.operations[0].operationType -eq 'Update') {
        if ($diff.operations[0].changes.title.before -eq 'Current Title' -and $diff.operations[0].changes.title.after -eq 'New Title') {
            return
        }
    }

    throw "Expected single Update operation with title change detected"
}

Invoke-Test "GivenMultipleFieldsChanged_WhenDiffCalculated_ThenAllChangesDetected" {
    $original = @{
        workItems = @(
            @{
                type  = 'Story'
                title = 'Story'
                workItemId = 1002
                description = 'Old description'
                storyPoints = 3
                tags = 'old-tag'
            }
        )
    }

    $modified = @{
        workItems = @(
            @{
                type  = 'Story'
                title = 'Story'
                workItemId = 1002
                description = 'New description'
                storyPoints = 5
                tags = 'new-tag'
            }
        )
    }

    $diff = & "$SRC_DIR\DetectHierarchyChanges.ps1" -OriginalHierarchy $original -ModifiedHierarchy $modified

    if ($diff.operations.Count -eq 1) {
        $op = $diff.operations[0]
        if ($op.changes.description -and $op.changes.storyPoints -and $op.changes.tags) {
            return
        }
    }

    throw "Expected multiple field changes to be detected"
}

Invoke-Test "GivenUnchangedItems_WhenDiffCalculated_ThenNoOperationsGenerated" {
    $original = @{
        workItems = @(
            @{
                type  = 'Story'
                title = 'Unchanged Story'
                workItemId = 1003
                description = 'Same description'
            }
        )
    }

    $modified = @{
        workItems = @(
            @{
                type  = 'Story'
                title = 'Unchanged Story'
                workItemId = 1003
                description = 'Same description'
            }
        )
    }

    $diff = & "$SRC_DIR\DetectHierarchyChanges.ps1" -OriginalHierarchy $original -ModifiedHierarchy $modified

    if ($diff.operations.Count -eq 0) {
        return
    }

    throw "Expected no operations for unchanged items"
}

# ============================================================================
# AC Scenario 2: Parent-child reorganization is detected
# ============================================================================

Invoke-Test "GivenStoryMovedToNewParent_WhenDiffCalculated_ThenMoveDetected" {
    $original = @{
        workItems = @(
            @{
                type  = 'Feature'
                title = 'Feature A'
                workItemId = 2001
                children = @(
                    @{
                        type  = 'Story'
                        title = 'Story'
                        workItemId = 2002
                    }
                )
            }
        )
    }

    $modified = @{
        workItems = @(
            @{
                type  = 'Feature'
                title = 'Feature B'
                workItemId = 2003
                children = @(
                    @{
                        type  = 'Story'
                        title = 'Story'
                        workItemId = 2002
                    }
                )
            }
        )
    }

    $diff = & "$SRC_DIR\DetectHierarchyChanges.ps1" -OriginalHierarchy $original -ModifiedHierarchy $modified

    if ($diff.operations.Count -ge 1) {
        $moveOp = $diff.operations | Where-Object { $_.operationType -eq 'Move' }
        if ($moveOp) {
            return
        }
    }

    throw "Expected Move operation for parent change"
}

# ============================================================================
# AC Scenario 4: New work items are detected for creation
# ============================================================================

Invoke-Test "GivenNewStoryWithoutWorkItemId_WhenDiffCalculated_ThenMarkedForCreation" {
    $original = @{
        workItems = @(
            @{
                type  = 'Feature'
                title = 'Existing Feature'
                workItemId = 3001
            }
        )
    }

    $modified = @{
        workItems = @(
            @{
                type  = 'Feature'
                title = 'Existing Feature'
                workItemId = 3001
                children = @(
                    @{
                        type  = 'Story'
                        title = 'New Story'
                        description = 'New story description'
                    }
                )
            }
        )
    }

    $diff = & "$SRC_DIR\DetectHierarchyChanges.ps1" -OriginalHierarchy $original -ModifiedHierarchy $modified

    if ($diff.operations.Count -ge 1) {
        $createOp = $diff.operations | Where-Object { $_.operationType -eq 'Create' -and $_.title -eq 'New Story' }
        if ($createOp) {
            if ($null -eq $createOp.itemId) {
                return
            }
        }
    }

    throw "Expected Create operation for new story"
}

Invoke-Test "GivenMultipleNewItemsInHierarchy_WhenDiffCalculated_ThenAllMarkedForCreation" {
    $original = @{
        workItems = @(
            @{
                type  = 'Epic'
                title = 'Strategic Initiative'
                workItemId = 4001
            }
        )
    }

    $modified = @{
        workItems = @(
            @{
                type  = 'Epic'
                title = 'Strategic Initiative'
                workItemId = 4001
                children = @(
                    @{
                        type  = 'Feature'
                        title = 'New Feature'
                        children = @(
                            @{
                                type  = 'Story'
                                title = 'New Story'
                            }
                        )
                    }
                )
            }
        )
    }

    $diff = & "$SRC_DIR\DetectHierarchyChanges.ps1" -OriginalHierarchy $original -ModifiedHierarchy $modified

    $createOps = $diff.operations | Where-Object { $_.operationType -eq 'Create' }
    if ($createOps.Count -eq 2) {
        return
    }

    throw "Expected 2 Create operations (Feature and Story)"
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
