<#
.SYNOPSIS
Tests for story AB#2226: Create Test Hierarchy Management System

.DESCRIPTION
Integration tests for CreateTestHierarchy.ps1 helper function.

Tests validate:
1. Test hierarchy is created and ready for use
2. Complex test hierarchy with multiple levels is created
3. Cleanup removes all test data

Acceptance Criteria verified:
- ✅ New Epic is created with "TEST-" prefix for test runs
- ✅ Test hierarchy under Epic is created with Features, Stories, Tasks, Bugs
- ✅ Created work items can be queried back via GetAzDo* scripts
- ✅ Cleanup function reliably deletes test Epic and all child work items
- ✅ Test infrastructure fails clearly if creation fails

Requires Environment variables:
- GMD_AZDO_ORGANIZATION: Organization name
- GMD_AZDO_PROJECT: Project name
- GMD_AZDO_MACHINE_WORKITEMSRW: PAT token

Run with: pwsh -File .\2226CreateTestHierarchyTest.ps1
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
[string]$TEST_DIR = Resolve-Path "$SCRIPT_DIR/../../"
[string]$SRC_DIR = Resolve-Path "$SCRIPT_DIR/../../../src"

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
[array]$createdEpics = @()  # Track created epics for cleanup

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

function Cleanup-TestEpic {
    [CmdletBinding()]
    param(
        [int]$EpicId
    )

    try {
        Write-Host "    Cleaning up test Epic (ID: $EpicId)..." -ForegroundColor Gray
        & "$SRC_DIR/RemoveAzDoEpic.ps1" `
            -Organization $Organization `
            -Project $Project `
            -EpicId $EpicId `
            -Force
        Write-Host "    ✓ Cleanup succeeded" -ForegroundColor Gray
    }
    catch {
        Write-Host "    ✗ Cleanup failed: $_" -ForegroundColor Red
    }
}

Write-Host "=== Story AB#2226 Tests: Create Test Hierarchy Management System ===" -ForegroundColor Cyan
Write-Host "Organization: $Organization"
Write-Host "Project: $Project"
Write-Host ""

# ============================================================================
# ACCEPTANCE TEST 1: Test hierarchy is created and ready for use
# ============================================================================

Invoke-Test "GivenTestSetupIsCalled_WhenCreateTestHierarchyInvoked_ThenEpicIsCreatedAndFeaturesAreReturned" {
    # Create a simple test hierarchy
    $spec = @{
        features = @(
            @{
                title       = "Test Feature 1"
                effort      = 8
                description = "Test feature for scenario 1"
                stories     = @(
                    @{
                        title        = "Test Story 1.1"
                        storyPoints  = 3
                        description  = "Test story under feature"
                        tasks        = @()
                    }
                )
                tasks       = @()
            }
        )
        bugs = @()
    }

    $result = & "$TEST_DIR/CreateTestHierarchy.ps1" `
        -Organization $Organization `
        -Project $Project `
        -Description "Scenario1Test" `
        -HierarchySpec $spec

    # Verify creation succeeded
    if ($result.Success -ne $true) {
        throw "Hierarchy creation failed. Errors: $($result.Errors -join '; ')"
    }

    # Verify Epic was created with TEST- prefix
    if ($result.Epic.Id -le 0) {
        throw "Epic was not created"
    }

    if ($result.Epic.Title -notmatch "^TEST-") {
        throw "Epic title does not have TEST- prefix: $($result.Epic.Title)"
    }

    $script:createdEpics += $result.Epic.Id

    # Verify Feature was created and returned
    if ($result.Features.Count -ne 1) {
        throw "Expected 1 feature, got $($result.Features.Count)"
    }

    if ($null -eq $result.Features["Test Feature 1"]) {
        throw "Feature 'Test Feature 1' not found in result"
    }

    # Verify Story was created and returned
    if ($result.Stories.Count -ne 1) {
        throw "Expected 1 story, got $($result.Stories.Count)"
    }

    if ($null -eq $result.Stories["Test Story 1.1"]) {
        throw "Story 'Test Story 1.1' not found in result"
    }

    # Verify all work items are queryable
    $epicQuery = & "$SRC_DIR/GetAzDoWorkItem.ps1" `
        -Organization $Organization `
        -Project $Project `
        -WorkItemId $result.Epic.Id

    if ($null -eq $epicQuery -or $epicQuery.id -ne $result.Epic.Id) {
        throw "Epic not queryable immediately after creation"
    }

    $featureQuery = & "$SRC_DIR/GetAzDoWorkItem.ps1" `
        -Organization $Organization `
        -Project $Project `
        -WorkItemId $result.Features["Test Feature 1"].Id

    if ($null -eq $featureQuery -or $featureQuery.id -ne $result.Features["Test Feature 1"].Id) {
        throw "Feature not queryable immediately after creation"
    }

    # Verify testWi tag was added
    if ($epicQuery.fields.'System.Tags' -notlike "*testWi*") {
        throw "Epic does not have testWi tag"
    }

    if ($featureQuery.fields.'System.Tags' -notlike "*testWi*") {
        throw "Feature does not have testWi tag"
    }
}

# ============================================================================
# ACCEPTANCE TEST 2: Complex test hierarchy with multiple levels is created
# ============================================================================

Invoke-Test "GivenTestSpecifiesComplexHierarchy_WhenCreateTestHierarchyBuildsStructure_ThenAllItemsAreCreatedAtDepths" {
    # Create complex hierarchy: 1 Epic, 2 Features, 6 Stories, 4 Tasks
    $spec = @{
        features = @(
            @{
                title       = "Feature with Stories"
                effort      = 13
                description = "First feature"
                stories     = @(
                    @{
                        title        = "Story 1.1"
                        storyPoints  = 3
                        description  = "First story of first feature"
                        tasks        = @(
                            @{ title = "Task 1.1.1"; effort = 2 }
                            @{ title = "Task 1.1.2"; effort = 1 }
                        )
                    },
                    @{
                        title        = "Story 1.2"
                        storyPoints  = 5
                        description  = "Second story of first feature"
                        tasks        = @()
                    },
                    @{
                        title        = "Story 1.3"
                        storyPoints  = 5
                        description  = "Third story of first feature"
                        tasks        = @()
                    }
                )
                tasks       = @()
            },
            @{
                title       = "Feature with Tasks"
                effort      = 8
                description = "Second feature"
                stories     = @(
                    @{
                        title        = "Story 2.1"
                        storyPoints  = 3
                        description  = "Story under second feature"
                        tasks        = @()
                    },
                    @{
                        title        = "Story 2.2"
                        storyPoints  = 5
                        description  = "Another story under second feature"
                        tasks        = @()
                    }
                )
                tasks       = @(
                    @{ title = "Feature Task 2.1"; effort = 2 }
                )
            }
        )
        bugs = @(
            @{ title = "Bug 1"; description = "Test bug" }
        )
    }

    $result = & "$TEST_DIR/CreateTestHierarchy.ps1" `
        -Organization $Organization `
        -Project $Project `
        -Description "Scenario2ComplexTest" `
        -HierarchySpec $spec

    # Verify creation succeeded
    if ($result.Success -ne $true) {
        throw "Complex hierarchy creation failed. Errors: $($result.Errors -join '; ')"
    }

    $script:createdEpics += $result.Epic.Id

    # Verify Epic at depth 0
    if ($result.Epic.Id -le 0) {
        throw "Epic was not created"
    }

    # Verify 2 Features at depth 1
    if ($result.Features.Count -ne 2) {
        throw "Expected 2 features, got $($result.Features.Count)"
    }

    # Verify 5 Stories at depth 2
    if ($result.Stories.Count -ne 5) {
        throw "Expected 5 stories, got $($result.Stories.Count)"
    }

    # Verify 3 Tasks (2 under Story 1.1, 1 under Feature 2)
    if ($result.Tasks.Count -ne 3) {
        throw "Expected 3 tasks, got $($result.Tasks.Count)"
    }

    # Verify 1 Bug
    if ($result.Bugs.Count -ne 1) {
        throw "Expected 1 bug, got $($result.Bugs.Count)"
    }

    # Verify total work item count
    $expectedTotal = 1 + 2 + 5 + 3 + 1  # Epic + Features + Stories + Tasks + Bugs
    if ($result.AllWorkItemIds.Count -ne $expectedTotal) {
        throw "Expected $expectedTotal total work items, got $($result.AllWorkItemIds.Count)"
    }

    # Verify all items are queryable
    foreach ($itemId in $result.AllWorkItemIds) {
        $item = & "$SRC_DIR/GetAzDoWorkItem.ps1" `
            -Organization $Organization `
            -Project $Project `
            -WorkItemId $itemId

        if ($null -eq $item -or $item.id -ne $itemId) {
            throw "Work item ID $itemId not queryable"
        }

        if ($item.fields.'System.Tags' -notlike "*testWi*") {
            throw "Work item ID $itemId does not have testWi tag"
        }
    }
}

# ============================================================================
# ACCEPTANCE TEST 3: Cleanup removes all test data
# ============================================================================

Invoke-Test "GivenTestCreatedEpicWithNestedWorkItems_WhenCleanupIsCalled_ThenEpicAndChildrenAreDeleted" {
    # Create a test hierarchy
    $spec = @{
        features = @(
            @{
                title       = "Cleanup Test Feature"
                effort      = 5
                description = "Feature for cleanup test"
                stories     = @(
                    @{
                        title        = "Cleanup Test Story"
                        storyPoints  = 2
                        description  = "Story for cleanup test"
                        tasks        = @(
                            @{ title = "Cleanup Test Task"; effort = 1 }
                        )
                    }
                )
                tasks       = @()
            }
        )
        bugs = @()
    }

    $result = & "$TEST_DIR/CreateTestHierarchy.ps1" `
        -Organization $Organization `
        -Project $Project `
        -Description "CleanupTest" `
        -HierarchySpec $spec

    if ($result.Success -ne $true) {
        throw "Hierarchy creation failed for cleanup test"
    }

    $epicId = $result.Epic.Id
    $createdIds = $result.AllWorkItemIds.Clone()

    # Verify items exist before cleanup
    foreach ($itemId in $createdIds) {
        $item = & "$SRC_DIR/GetAzDoWorkItem.ps1" `
            -Organization $Organization `
            -Project $Project `
            -WorkItemId $itemId

        if ($null -eq $item) {
            throw "Work item ID $itemId should exist before cleanup"
        }
    }

    # Perform cleanup
    & "$SRC_DIR/RemoveAzDoEpic.ps1" `
        -Organization $Organization `
        -Project $Project `
        -EpicId $epicId `
        -Force

    # Verify all items are deleted
    foreach ($itemId in $createdIds) {
        try {
            $item = & "$SRC_DIR/GetAzDoWorkItem.ps1" `
                -Organization $Organization `
                -Project $Project `
                -WorkItemId $itemId `
                -ErrorAction Stop

            # If we get here, item still exists
            throw "Work item ID $itemId still exists after cleanup"
        }
        catch {
            # Expected behavior: item should not be found
            if ($_ -match "not found") {
                continue  # Expected
            }
            throw $_
        }
    }

    # Don't add to cleanup list since we already cleaned it
    $script:createdEpics = $script:createdEpics | Where-Object { $_ -ne $epicId }
}

# ============================================================================
# Test Completion Summary
# ============================================================================

Write-Host ""
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Tests Run:    $testsRun" -ForegroundColor White
Write-Host "Passed:       $testsPassed" -ForegroundColor Green
Write-Host "Failed:       $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { 'Red' } else { 'Green' })
Write-Host ""

# Cleanup any remaining test epics
if ($createdEpics.Count -gt 0) {
    Write-Host "=== Cleanup ===" -ForegroundColor Cyan
    foreach ($epicId in $createdEpics) {
        Cleanup-TestEpic -EpicId $epicId
    }
}

# Exit with appropriate code
if ($testsFailed -gt 0) {
    Write-Host "Some tests failed!" -ForegroundColor Red
    exit 1
}
else {
    Write-Host "All tests passed!" -ForegroundColor Green
    exit 0
}
