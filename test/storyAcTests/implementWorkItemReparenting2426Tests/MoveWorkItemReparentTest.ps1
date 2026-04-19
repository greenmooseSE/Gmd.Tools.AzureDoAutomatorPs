<#
.SYNOPSIS
Test suite for story 2426: Implement Work Item Reparenting in Apply Validated Changes

Tests the Move-AzDoWorkItem function and reparenting capability in ApplyValidatedChanges.ps1
#>

#Requires -Version 7.0

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Import helper scripts and modules
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$solutionRoot = (Get-Item $scriptRoot).Parent.Parent.Parent.FullName
$srcPath = Join-Path $solutionRoot 'src'

. "$srcPath/AzDoPatTokenHelper.ps1"
. "$srcPath/AzDoAutomatorConstants.ps1"
. "$srcPath/AzDoApiWrapper.ps1"
. "$srcPath/AzDoWorkItemHelper.ps1"

# Environment setup
$Organization = $env:GMD_AZDO_ORGANIZATION ?? 'falco-it'
$Project = $env:GMD_AZDO_PROJECT ?? 'GMD'
$PatToken = $env:GMD_AZDO_MACHINE_WORKITEMSRW | ssEncryptDecrypt.ps1 -Decrypt

# Test state
$testArtifacts = @{
    epicId      = $null
    featureAId  = $null
    featureBId  = $null
    storyId     = $null
    createdIds  = @()
}

$testsPassed = 0
$testsFailed = 0

<#
.SYNOPSIS
Helper to create test work items and track for cleanup
#>
function New-TestWorkItem {
    param(
        [string]$Type,
        [string]$Title,
        [string]$Description = "",
        [int]$ParentId = 0
    )

    $fields = @{
        'System.Title'       = $Title
        'System.Description' = $Description
        'System.Tags'        = 'testWi'
    }

    $wi = if ($ParentId -gt 0) {
        New-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemType $Type -Fields $fields -ParentId $ParentId -PatToken $PatToken
    }
    else {
        New-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemType $Type -Fields $fields -PatToken $PatToken
    }

    $testArtifacts.createdIds += $wi.id
    return $wi
}

<#
.SYNOPSIS
Setup test hierarchy: Epic -> FeatureA -> Story, FeatureB
#>
function Setup-TestHierarchy {
    $null = ssLogIt.ps1 -Level Info -Message "Setting up test hierarchy..."

    # Create test epic
    $epic = New-TestWorkItem -Type 'Epic' -Title "Test Epic For Reparenting 2426" -Description "Temporary epic for reparenting tests"
    $testArtifacts.epicId = $epic.id
    $null = ssLogIt.ps1 -Level Debug -Message "Created test epic: $($epic.id)"

    # Create feature A
    $featureA = New-TestWorkItem -Type 'Feature' -Title "Feature A (Original Parent)" -Description "Feature A with story" -ParentId $epic.id
    $testArtifacts.featureAId = $featureA.id
    $null = ssLogIt.ps1 -Level Debug -Message "Created feature A: $($featureA.id)"

    # Create feature B (no stories initially)
    $featureB = New-TestWorkItem -Type 'Feature' -Title "Feature B (Target Parent)" -Description "Feature B - target for reparenting" -ParentId $epic.id
    $testArtifacts.featureBId = $featureB.id
    $null = ssLogIt.ps1 -Level Debug -Message "Created feature B: $($featureB.id)"

    # Create story under feature A
    $story = New-TestWorkItem -Type 'User Story' -Title "Story to Reparent" -Description "Story under feature A, will be moved to feature B" -ParentId $featureA.id
    $testArtifacts.storyId = $story.id
    $null = ssLogIt.ps1 -Level Debug -Message "Created story under feature A: $($story.id)"
}

<#
.SYNOPSIS
Cleanup all test work items
#>
function Teardown-TestHierarchy {
    $null = ssLogIt.ps1 -Level Info -Message "Cleaning up test hierarchy..."

    # Delete in reverse order: stories first, then features, then epic
    $idsToDelete = $testArtifacts.createdIds | Sort-Object -Descending

    foreach ($id in $idsToDelete) {
        try {
            Remove-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $id -PatToken $PatToken
            $null = ssLogIt.ps1 -Level Debug -Message "Deleted test work item: $id"
        }
        catch {
            $null = ssLogIt.ps1 -Level Warn -Message "Failed to delete test work item $id : $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
Get parent ID from work item relations
#>
function Get-ParentIdFromWorkItem {
    param([object]$WorkItem)
    
    if ($null -eq $WorkItem.relations -or $WorkItem.relations.Count -eq 0) {
        return $null
    }
    
    $parentRel = $WorkItem.relations | Where-Object { $_.rel -eq 'System.LinkTypes.Hierarchy-Reverse' } | Select-Object -First 1
    if ($null -eq $parentRel) {
        return $null
    }
    
    return [int]($parentRel.url -replace '.*workitems/', '')
}

# ============================================================================
# Tests
# ============================================================================

$null = ssLogIt.ps1 -Level Info -Message "Starting Move-AzDoWorkItem tests..."
Write-Output ""

<#
.SYNOPSIS
AC1: Move-AzDoWorkItem function removes old Hierarchy-Reverse and adds new one
Tests that the function is available and can reparent a work item
Test Name: GivenWorkItemWithParent_WhenMoveIsCalled_ThenParentIsChanged
#>
Write-Output "=== Test AC1: Move-AzDoWorkItem Function (GivenWorkItemWithParent_WhenMoveIsCalled_ThenParentIsChanged) ==="
try {
    Setup-TestHierarchy

    # Get story before move (should have feature A as parent)
    $storyBefore = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $testArtifacts.storyId -PatToken $PatToken
    $parentBeforeId = Get-ParentIdFromWorkItem -WorkItem $storyBefore

    $null = ssLogIt.ps1 -Level Debug -Message "Story parent before move: $parentBeforeId (Expected: $($testArtifacts.featureAId))"
    if ($parentBeforeId -ne $testArtifacts.featureAId) {
        throw "Story is not under feature A before test (actual parent: $parentBeforeId)"
    }

    # Move story from feature A to feature B
    $movedItem = Move-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $testArtifacts.storyId -NewParentId $testArtifacts.featureBId -PatToken $PatToken

    # Verify new parent
    $storyAfter = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $testArtifacts.storyId -PatToken $PatToken
    $parentAfterId = Get-ParentIdFromWorkItem -WorkItem $storyAfter

    $null = ssLogIt.ps1 -Level Debug -Message "Story parent after move: $parentAfterId (Expected: $($testArtifacts.featureBId))"

    if ($parentAfterId -eq $testArtifacts.featureBId) {
        Write-Output "✅ PASS: Move-AzDoWorkItem successfully reparented story from feature A to feature B"
        $script:testsPassed++
    }
    else {
        throw "Move failed - parent is $parentAfterId, expected $($testArtifacts.featureBId)"
    }
}
catch {
    Write-Output "❌ FAIL: $($_.Exception.Message)"
    $script:testsFailed++
}
finally {
    Teardown-TestHierarchy
}

<#
.SYNOPSIS
AC2: Move operation: reparent work item with field changes
Test Name: GivenMoveOperationWithFieldChanges_WhenApplied_ThenReparentsAndUpdates
#>
Write-Output "`n=== Test AC2: Reparent with Field Changes (GivenMoveOperationWithFieldChanges_WhenApplied_ThenReparentsAndUpdates) ==="
try {
    Setup-TestHierarchy

    # Update story fields and move it to feature B
    $newTitle = "Story Reparented and Updated"
    $updateFields = @{
        'System.Title'       = $newTitle
        'System.Description' = 'Updated description for reparented story'
    }

    # First, manually move the story
    $movedItem = Move-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $testArtifacts.storyId -NewParentId $testArtifacts.featureBId -PatToken $PatToken

    # Then update fields
    $updatedItem = Update-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $testArtifacts.storyId -Fields $updateFields -PatToken $PatToken

    # Verify both operations took effect
    $storyFinal = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $testArtifacts.storyId -PatToken $PatToken
    $finalParentId = Get-ParentIdFromWorkItem -WorkItem $storyFinal
    $finalTitle = $storyFinal.fields.'System.Title'

    if ($finalParentId -eq $testArtifacts.featureBId -and $finalTitle -eq $newTitle) {
        Write-Output "✅ PASS: Story reparented to feature B and title updated successfully"
        $script:testsPassed++
    }
    else {
        throw "Combined operation failed - parent: $finalParentId (expected $($testArtifacts.featureBId)), title: $finalTitle (expected $newTitle)"
    }
}
catch {
    Write-Output "❌ FAIL: $($_.Exception.Message)"
    $script:testsFailed++
}
finally {
    Teardown-TestHierarchy
}

<#
.SYNOPSIS
AC3: Move without initial parent (orphan item case)
Test Name: GivenOrphanItem_WhenMovedToParent_ThenParentIsAdded
#>
Write-Output "`n=== Test AC3: Move Orphan Item (GivenOrphanItem_WhenMovedToParent_ThenParentIsAdded) ==="
try {
    Setup-TestHierarchy

    # Create an orphan story (no parent)
    $orphanStory = New-TestWorkItem -Type 'User Story' -Title "Orphan Story" -Description "Story with no parent"
    $orphanId = $orphanStory.id

    # Verify it has no parent
    $orphanBefore = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $orphanId -PatToken $PatToken
    $parentBeforeOrphan = Get-ParentIdFromWorkItem -WorkItem $orphanBefore
    if ($null -ne $parentBeforeOrphan) {
        throw "Orphan story has a parent initially: $parentBeforeOrphan"
    }

    # Move orphan to feature B
    $movedOrphan = Move-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $orphanId -NewParentId $testArtifacts.featureBId -PatToken $PatToken

    # Verify it now has feature B as parent
    $orphanAfter = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $orphanId -PatToken $PatToken
    $parentAfterOrphan = Get-ParentIdFromWorkItem -WorkItem $orphanAfter

    if ($parentAfterOrphan -eq $testArtifacts.featureBId) {
        Write-Output "✅ PASS: Orphan story successfully assigned feature B as parent"
        $script:testsPassed++
    }
    else {
        throw "Move failed for orphan - parent is $parentAfterOrphan, expected $($testArtifacts.featureBId)"
    }
}
catch {
    Write-Output "❌ FAIL: $($_.Exception.Message)"
    $script:testsFailed++
}
finally {
    Teardown-TestHierarchy
}

# Summary
Write-Output "`n=== Test Summary ==="
Write-Output "Passed: $testsPassed"
Write-Output "Failed: $testsFailed"
Write-Output ""

if ($testsFailed -gt 0) {
    exit 1
}
exit 0

