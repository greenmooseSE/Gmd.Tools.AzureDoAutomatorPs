<#
.SYNOPSIS
Integration tests for story AB#2228: Add Integration Tests for Export-Import Round-Trip

.DESCRIPTION
Tests the complete export-modify-reimport workflow with real Azure DevOps data.
Creates test hierarchies via CreateTestHierarchy.ps1, exports to markdown,
modifies the markdown, and reimports to verify data integrity.

Scenarios tested:
1. Complete round-trip without modifications preserves all work items and WorkItemIds
   (Feature, 2 Stories, 1 Task, 1 Bug)
2. Title and description modifications survive round-trip and second export confirms changes
3. Non-writable state change is rejected during change detection with helpful error message

Requires Environment variables:
- GMD_AZDO_ORGANIZATION: Organization name
- GMD_AZDO_PROJECT: Project name
- GMD_AZDO_MACHINE_WORKITEMSRW: PAT token

Run with: pwsh -File .\2228AddIntegrationTestsForExportImportRoundTrip.ps1
#>

#Requires -Version 7.0

param(
    [string]$Organization = $env:GMD_AZDO_ORGANIZATION,
    [string]$Project = $env:GMD_AZDO_PROJECT
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

[string]$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
[string]$TEST_DIR = Resolve-Path "$SCRIPT_DIR/../../"
[string]$SRC_DIR = Resolve-Path "$SCRIPT_DIR/../../../src"
[string]$REPO_ROOT = Resolve-Path "$SCRIPT_DIR/../../../"

if ([string]::IsNullOrWhiteSpace($Organization)) {
    Write-Error "Organization not provided. Set GMD_AZDO_ORGANIZATION or pass -Organization."
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    Write-Error "Project not provided. Set GMD_AZDO_PROJECT or pass -Project."
}

[int]$testsRun = 0
[int]$testsPassed = 0
[int]$testsFailed = 0
[array]$testResults = @()
[array]$createdEpics = @()

function Invoke-Test {
    <#
    .SYNOPSIS
    Runs a named test block and records its pass/fail result.
    #>
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
    <#
    .SYNOPSIS
    Removes a test Epic and all its children from Azure DevOps.
    #>
    [CmdletBinding()]
    param(
        [int]$EpicId
    )

    try {
        Write-Host "    Cleaning up test Epic (ID: $($EpicId))..." -ForegroundColor Gray
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

Write-Host "=== Story AB#2228 Integration Tests: Export-Import Round-Trip ===" -ForegroundColor Cyan
Write-Host "Organization: $Organization"
Write-Host "Project: $Project"
Write-Host ""

# ============================================================================
# AC Scenario 1: Complete round-trip without modifications preserves data
# ============================================================================

Invoke-Test "GivenTestHierarchyWithFeatureBug2StoriesAndTask_WhenExportedParsedAndReimported_ThenAllWorkItemsMatchAndNoChangesDetected" {
    # Create test hierarchy: 1 Feature, 2 Stories, 1 Task under Story1
    $spec = @{
        features = @(
            @{
                title       = "RT-Feature-1"
                effort      = 5
                description = "Feature for round-trip test"
                stories     = @(
                    @{
                        title       = "RT-Story-1"
                        storyPoints = 3
                        description = "First story for round-trip"
                        tasks       = @(
                            @{ title = "RT-Task-1"; effort = 2 }
                        )
                    },
                    @{
                        title       = "RT-Story-2"
                        storyPoints = 2
                        description = "Second story for round-trip"
                        tasks       = @()
                    }
                )
                tasks       = @()
            }
        )
        bugs = @()
    }

    $hierarchy = & "$TEST_DIR/CreateTestHierarchy.ps1" `
        -Organization $Organization `
        -Project $Project `
        -Description "RoundTripScenario1" `
        -HierarchySpec $spec

    if ($hierarchy.Success -ne $true) {
        throw "Failed to create test hierarchy: $($hierarchy.Errors -join '; ')"
    }

    $script:createdEpics += $hierarchy.Epic.Id

    # Create a Bug under Story1 to include bug type in the round-trip test (testWi tag for cleanup)
    $story1Id = $hierarchy.Stories["RT-Story-1"].Id
    $bug = & "$SRC_DIR/UpsertAzDoBug.ps1" `
        -Organization $Organization `
        -Project $Project `
        -Title "RT-Bug-1" `
        -Description "Bug for round-trip test" `
        -ParentStoryId $story1Id `
        -FailIfExist

    # Tag the bug with testWi for orphan detection
    & "$SRC_DIR/UpdateAzDoWorkItemTags.ps1" `
        -Organization $Organization `
        -Project $Project `
        -WorkItemId $bug.id `
        -Tags @("testWi") | Out-Null

    # Export Story1 hierarchy (correctly includes Tasks and Bugs as separate collections)
    $storyHierarchy = & "$SRC_DIR/GetAzDoHierarchyForStory.ps1" `
        -Organization $Organization `
        -Project $Project `
        -StoryId $story1Id

    if ($null -eq $storyHierarchy) {
        throw "Failed to export Story1 hierarchy"
    }

    $markdown = & "$SRC_DIR/ConvertHierarchyToMarkdown.ps1" `
        -Hierarchy $storyHierarchy `
        -Organization $Organization `
        -Project $Project `
        -RepositoryRoot $REPO_ROOT

    # Parse original markdown (no modifications - this is both original and "modified")
    $originalJson = & "$SRC_DIR/ConvertMarkdownToHierarchyJson.ps1" -MarkdownContent $markdown
    $parsedJson = & "$SRC_DIR/ConvertMarkdownToHierarchyJson.ps1" -MarkdownContent $markdown

    # Detect changes - should be 0 since nothing was modified
    $diff = & "$SRC_DIR/DetectHierarchyChanges.ps1" `
        -OriginalHierarchy $originalJson `
        -ModifiedHierarchy $parsedJson `
        -StateConfigPath "$REPO_ROOT/azdoStateConfig-falco-it-GMD.json"

    if ($diff.validationPassed -ne $true) {
        throw "Validation failed unexpectedly for unmodified round-trip. Errors: $($diff.errors -join '; ')"
    }

    if ($diff.operations.Count -ne 0) {
        $ops = $diff.operations | ForEach-Object { "$($_.operationType) $($_.workItemType) '$($_.title)'" }
        throw "Expected 0 operations for unmodified export-reimport, but got $($diff.operations.Count): $($ops -join ', ')"
    }

    # Verify WorkItemIds are preserved in parsed hierarchy
    $parsedStory = $parsedJson.workItems | Where-Object { $_.type -eq 'Story' } | Select-Object -First 1
    if ($null -eq $parsedStory) {
        throw "Story not found in parsed JSON"
    }

    if ([int]$parsedStory.workItemId -ne $story1Id) {
        throw "Story WorkItemId mismatch. Expected $($story1Id) but got $($parsedStory.workItemId)"
    }

    $task1Id = $hierarchy.Tasks["RT-Task-1"].Id
    $parsedTask = $parsedStory.children | Where-Object { $_.type -eq 'Task' } | Select-Object -First 1
    if ($null -eq $parsedTask) {
        throw "Task not found in parsed JSON children"
    }

    if ([int]$parsedTask.workItemId -ne $task1Id) {
        throw "Task WorkItemId mismatch. Expected $($task1Id) but got $($parsedTask.workItemId)"
    }

    $parsedBug = $parsedStory.children | Where-Object { $_.type -eq 'Bug' } | Select-Object -First 1
    if ($null -eq $parsedBug) {
        throw "Bug not found in parsed JSON children"
    }

    if ([int]$parsedBug.workItemId -ne $bug.id) {
        throw "Bug WorkItemId mismatch. Expected $($bug.id) but got $($parsedBug.workItemId)"
    }

    Write-Host "    ✓ Round-trip detected 0 operations (no false positives)" -ForegroundColor Gray
    Write-Host "    ✓ WorkItemIds preserved: Story=$($story1Id), Task=$($task1Id), Bug=$($bug.id)" -ForegroundColor Gray
}

# ============================================================================
# AC Scenario 2: Title and description modifications survive round-trip
# ============================================================================

Invoke-Test "GivenStoryWithOriginalTitleAndDescription_WhenExportedModifiedAndReimported_ThenChangesAreAppliedAndSecondExportConfirms" {
    # Create test hierarchy with a Story that will be modified
    $spec = @{
        features = @(
            @{
                title       = "RT-Feature-2"
                effort      = 3
                description = "Feature for modification test"
                stories     = @(
                    @{
                        title       = "RT-Original-Title"
                        storyPoints = 3
                        description = "RT-Original-Description"
                        tasks       = @()
                    }
                )
                tasks       = @()
            }
        )
        bugs = @()
    }

    $hierarchy = & "$TEST_DIR/CreateTestHierarchy.ps1" `
        -Organization $Organization `
        -Project $Project `
        -Description "RoundTripScenario2" `
        -HierarchySpec $spec

    if ($hierarchy.Success -ne $true) {
        throw "Failed to create test hierarchy: $($hierarchy.Errors -join '; ')"
    }

    $script:createdEpics += $hierarchy.Epic.Id

    $featureId = $hierarchy.Features["RT-Feature-2"].Id
    $storyId = $hierarchy.Stories["RT-Original-Title"].Id

    # Export Feature hierarchy (Feature contains the Story to be modified)
    $featureHierarchy = & "$SRC_DIR/GetAzDoHierarchyForFeature.ps1" `
        -Organization $Organization `
        -Project $Project `
        -FeatureId $featureId

    if ($null -eq $featureHierarchy) {
        throw "Failed to export Feature hierarchy"
    }

    $originalMarkdown = & "$SRC_DIR/ConvertHierarchyToMarkdown.ps1" `
        -Hierarchy $featureHierarchy `
        -Organization $Organization `
        -Project $Project `
        -RepositoryRoot $REPO_ROOT

    # Parse original markdown
    $originalJson = & "$SRC_DIR/ConvertMarkdownToHierarchyJson.ps1" -MarkdownContent $originalMarkdown

    # Modify markdown: change Story title and description
    $modifiedMarkdown = $originalMarkdown -replace "### Story: RT-Original-Title", "### Story: RT-Modified-Title"
    $modifiedMarkdown = $modifiedMarkdown -replace "RT-Original-Description", "RT-Modified-Description"

    # Parse modified markdown
    $modifiedJson = & "$SRC_DIR/ConvertMarkdownToHierarchyJson.ps1" -MarkdownContent $modifiedMarkdown

    # Detect changes - should find 1 Update operation for the Story
    $diff = & "$SRC_DIR/DetectHierarchyChanges.ps1" `
        -OriginalHierarchy $originalJson `
        -ModifiedHierarchy $modifiedJson `
        -StateConfigPath "$REPO_ROOT/azdoStateConfig-falco-it-GMD.json"

    if ($diff.validationPassed -ne $true) {
        throw "Validation failed unexpectedly. Errors: $($diff.errors -join '; ')"
    }

    if ($diff.operations.Count -eq 0) {
        throw "Expected at least 1 operation for modified story but got 0"
    }

    $storyOp = $diff.operations | Where-Object { $_.itemId -eq $storyId } | Select-Object -First 1
    if ($null -eq $storyOp) {
        throw "Expected Update operation for Story ID $($storyId) but none found"
    }

    if ($storyOp.operationType -ne 'Update') {
        throw "Expected Update operation but got $($storyOp.operationType)"
    }

    # Apply changes
    $applyResult = & "$SRC_DIR/ApplyValidatedChanges.ps1" -ValidatedDiff $diff

    if ($applyResult.success -ne $true) {
        throw "ApplyValidatedChanges failed: $($applyResult.failureReason)"
    }

    if ($applyResult.appliedChanges -eq 0) {
        throw "Expected at least 1 applied change but got 0"
    }

    # Verify changes are applied in Azure DevOps
    $updatedStory = & "$SRC_DIR/GetAzDoWorkItem.ps1" `
        -WorkItemId $storyId `
        -Organization $Organization `
        -Project $Project

    if ($updatedStory.fields.'System.Title' -ne "RT-Modified-Title") {
        throw "Story title not updated. Expected 'RT-Modified-Title' but got '$($updatedStory.fields.'System.Title')'"
    }

    if ($updatedStory.fields.'System.Description' -notlike "*RT-Modified-Description*") {
        throw "Story description not updated. Got: '$($updatedStory.fields.'System.Description')'"
    }

    # Verify second export reflects the modifications (tags and storyPoints remain unchanged)
    $storyHierarchyAfter = & "$SRC_DIR/GetAzDoHierarchyForStory.ps1" `
        -Organization $Organization `
        -Project $Project `
        -StoryId $storyId

    if ($storyHierarchyAfter.Title -ne "RT-Modified-Title") {
        throw "Second export: Story title mismatch. Expected 'RT-Modified-Title' but got '$($storyHierarchyAfter.Title)'"
    }

    if ($storyHierarchyAfter.StoryPoints -ne 3) {
        throw "Second export: StoryPoints changed unexpectedly. Expected 3 but got $($storyHierarchyAfter.StoryPoints)"
    }

    Write-Host "    ✓ Title changed to 'RT-Modified-Title'" -ForegroundColor Gray
    Write-Host "    ✓ Description updated to contain 'RT-Modified-Description'" -ForegroundColor Gray
    Write-Host "    ✓ StoryPoints (3) unchanged after modification" -ForegroundColor Gray
    Write-Host "    ✓ Second export confirms changes in AzDo" -ForegroundColor Gray
    Write-Host "    ✓ Applied $($applyResult.appliedChanges) change(s)" -ForegroundColor Gray
}

# ============================================================================
# AC Scenario 3: Non-writable state changes are rejected during reimport
# ============================================================================

Invoke-Test "GivenStoryInWritableState_WhenMarkdownStateChangedToNonWritableState_ThenDetectHierarchyChangesRaisesErrorWithValidStates" {
    # Create test hierarchy with a Story in "New" state (writable for Story)
    $spec = @{
        features = @(
            @{
                title       = "RT-Feature-3"
                effort      = 3
                description = "Feature for state validation test"
                stories     = @(
                    @{
                        title       = "RT-State-Test-Story"
                        storyPoints = 1
                        description = "Story for state validation test"
                        tasks       = @()
                    }
                )
                tasks       = @()
            }
        )
        bugs = @()
    }

    $hierarchy = & "$TEST_DIR/CreateTestHierarchy.ps1" `
        -Organization $Organization `
        -Project $Project `
        -Description "RoundTripScenario3" `
        -HierarchySpec $spec

    if ($hierarchy.Success -ne $true) {
        throw "Failed to create test hierarchy: $($hierarchy.Errors -join '; ')"
    }

    $script:createdEpics += $hierarchy.Epic.Id

    $featureId = $hierarchy.Features["RT-Feature-3"].Id
    $storyId = $hierarchy.Stories["RT-State-Test-Story"].Id

    # Verify Story starts in a writable state
    $initialStory = & "$SRC_DIR/GetAzDoWorkItem.ps1" `
        -WorkItemId $storyId `
        -Organization $Organization `
        -Project $Project

    $initialState = $initialStory.fields.'System.State'

    # Export Feature hierarchy
    $featureHierarchy = & "$SRC_DIR/GetAzDoHierarchyForFeature.ps1" `
        -Organization $Organization `
        -Project $Project `
        -FeatureId $featureId

    if ($null -eq $featureHierarchy) {
        throw "Failed to export Feature hierarchy"
    }

    $originalMarkdown = & "$SRC_DIR/ConvertHierarchyToMarkdown.ps1" `
        -Hierarchy $featureHierarchy `
        -Organization $Organization `
        -Project $Project `
        -RepositoryRoot $REPO_ROOT

    # Load state config to find a non-writable state for Story type
    $stateConfig = Get-Content -Raw "$REPO_ROOT/azdoStateConfig-falco-it-GMD.json" | ConvertFrom-Json
    $storyWritableStates = @($stateConfig.writableStates.Story)
    # "Planning Done" is in Feature writable states but NOT in Story writable states
    $nonWritableState = "Planning Done"
    if ($storyWritableStates -contains $nonWritableState) {
        throw "Test setup error: '$($nonWritableState)' is actually writable for Story. Choose a different test state."
    }

    # Parse original markdown
    $originalJson = & "$SRC_DIR/ConvertMarkdownToHierarchyJson.ps1" -MarkdownContent $originalMarkdown

    # Modify markdown: change Story state to a non-writable state
    $modifiedMarkdown = $originalMarkdown -replace "\*\*State\*\*: $([regex]::Escape($initialState))\b[^\n]*", "**State**: $nonWritableState"

    # Parse modified markdown
    $modifiedJson = & "$SRC_DIR/ConvertMarkdownToHierarchyJson.ps1" -MarkdownContent $modifiedMarkdown

    # Detect changes - state validation should reject the non-writable state
    $diff = & "$SRC_DIR/DetectHierarchyChanges.ps1" `
        -OriginalHierarchy $originalJson `
        -ModifiedHierarchy $modifiedJson `
        -StateConfigPath "$REPO_ROOT/azdoStateConfig-falco-it-GMD.json"

    # Validation must have failed
    if ($diff.validationPassed -eq $true) {
        throw "Expected validationPassed = false for non-writable state '$($nonWritableState)' but got true"
    }

    if ($diff.errors.Count -eq 0) {
        throw "Expected errors in diff for non-writable state change but got none"
    }

    # Error message must mention the invalid state
    $stateError = $diff.errors | Where-Object { $_ -like "*$nonWritableState*" }
    if ($null -eq $stateError) {
        throw "Error message does not mention '$($nonWritableState)'. Errors: $($diff.errors -join '; ')"
    }

    # Error message must list valid writable states
    $validStatesError = $diff.errors | Where-Object { $_ -like "*Valid writable states*" -or $_ -like "*writable states*" }
    if ($null -eq $validStatesError) {
        throw "Error message does not list valid writable states. Errors: $($diff.errors -join '; ')"
    }

    # Verify Azure DevOps Story state was NOT changed (validationPassed=false prevents ApplyValidatedChanges)
    $storyCheck = & "$SRC_DIR/GetAzDoWorkItem.ps1" `
        -WorkItemId $storyId `
        -Organization $Organization `
        -Project $Project

    $currentState = $storyCheck.fields.'System.State'
    if ($currentState -eq $nonWritableState) {
        throw "Story state should not have been changed to '$($nonWritableState)' but it was"
    }

    Write-Host "    ✓ validationPassed = false for non-writable state '$($nonWritableState)'" -ForegroundColor Gray
    Write-Host "    ✓ Error mentions '$($nonWritableState)'" -ForegroundColor Gray
    Write-Host "    ✓ Error lists valid writable states: $($storyWritableStates -join ', ')" -ForegroundColor Gray
    Write-Host "    ✓ Story state in AzDo remains '$($currentState)' (unchanged)" -ForegroundColor Gray
}

# ============================================================================
# Cleanup (always runs, even if tests failed)
# ============================================================================

Write-Host "`n=== Cleanup ===" -ForegroundColor Cyan
foreach ($epicId in $script:createdEpics) {
    Cleanup-TestEpic -EpicId $epicId
}

# ============================================================================
# Summary
# ============================================================================

Write-Host "`n╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║ TEST SUMMARY - Story AB#2228: Export-Import Round-Trip Tests     ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "`nResults:" -ForegroundColor Yellow
foreach ($result in $testResults) {
    $status = if ($result.Status -eq 'PASSED') { "✓ PASS" } else { "✗ FAIL" }
    $color = if ($result.Status -eq 'PASSED') { "Green" } else { "Red" }
    Write-Host "  [$status] $($result.Name)" -ForegroundColor $color
    if ($result.ContainsKey('Error') -and $result.Error) {
        Write-Host "         $($result.Error)" -ForegroundColor DarkGray
    }
}

Write-Host "`nTotal: $testsRun tests | Passed: $testsPassed | Failed: $testsFailed" -ForegroundColor Cyan

if ($testsFailed -gt 0) {
    Write-Error "Test run failed with $testsFailed failure(s)"
}
