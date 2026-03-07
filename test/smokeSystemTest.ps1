<#
.SYNOPSIS
Smoke test for work item creation, tag management, and retrieval across all work item types

.DESCRIPTION
Creates one work item of each type (Epic, Feature, Story, Task) with initial tags,
verifies tag retrieval, adds additional tags, verifies they were added, then cleans up.

Requires Environment variables set:
- GMD_AZDO_ORGANIZATION: Organization name
- GMD_AZDO_PROJECT: Project name
- GMD_AZDO_MACHINE_WORKITEMSRW: Encrypted PAT token

Run with: pwsh -File .\test\smokeSystemTest.ps1

.NOTES
This is a basic smoke test to verify core tag functionality across all work item types.
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
[string]$SRC_DIR = Join-Path $SCRIPT_DIR '../src'

# Validate inputs
if ([string]::IsNullOrWhiteSpace($Organization)) {
    Write-Error "Organization not provided. Set GMD_AZDO_ORGANIZATION environment variable or pass -Organization parameter."
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    Write-Error "Project not provided. Set GMD_AZDO_PROJECT environment variable or pass -Project parameter."
}

# Cache for created work item IDs
[array]$createdItemIds = @()

function Add-CreatedItem {
    [CmdletBinding()]
    param(
        [int]$ItemId
    )
    $script:createdItemIds += $ItemId
}

function Cleanup {
    if ($script:createdItemIds.Count -gt 0) {
        Write-Host "`nCleaning up test items..." -ForegroundColor Cyan
        
        # Sort IDs in descending order to delete children before parents
        $idsToDelete = $script:createdItemIds | Sort-Object -Descending -Unique
        
        foreach ($itemId in $idsToDelete) {
            try {
                # Try to remove as Epic (which should remove all children if it is the parent)
                # Use -Force to skip confirmation and -ErrorAction to suppress errors if not an Epic
                & "$SRC_DIR/RemoveAzDoEpic.ps1" -Organization $Organization -Project $Project -EpicId $itemId -Force -ErrorAction SilentlyContinue
                Write-Host "Cleaned up work item (ID: $itemId)" -ForegroundColor Green
            }
            catch {
                # Item may have already been deleted or hierarchy may have been removed already
                Write-Host "Cleanup skipped for ID: $itemId" -ForegroundColor Yellow
            }
        }
    }
}

# Register cleanup on exit
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Cleanup }

try {
    Write-Host "`n=== Smoke Test: Work Item Tags ===`n" -ForegroundColor Cyan
    Write-Host "Organization: $Organization"
    Write-Host "Project: $Project`n"

    # Test 1: Create Epic with tags and verify
    Write-Host "`n--- Test 1: Epic ---" -ForegroundColor Yellow
    $epicTitle = "Smoke Test Epic $(Get-Random)"
    Write-Host "Creating Epic: $epicTitle"
    $epic = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project -Title $epicTitle
    $epicId = $epic.id
    Add-CreatedItem -ItemId $epicId
    Write-Host "Created Epic (ID: $epicId)" -ForegroundColor Green

    # Add initial tags
    & "$SRC_DIR/SetAzDoWorkItemTags.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $epicId -Tags "smokeTest;epic-initial"
    Write-Host "Added initial tags to Epic" -ForegroundColor Green

    # Verify tags via GetAzDoWorkItem
    $epicRetrieved = & "$SRC_DIR/GetAzDoWorkItem.ps1" -Organization $Organization -Project $Project -WorkItemId $epicId
    if ($epicRetrieved.fields.'System.Tags' -like "*epic-initial*") {
        Write-Host "✓ Epic tags verified" -ForegroundColor Green
    }
    else {
        throw "Epic tags not found or incorrect: $($epicRetrieved.fields.'System.Tags')"
    }

    # Add additional tag
    & "$SRC_DIR/SetAzDoWorkItemTags.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $epicId -Tags "smokeTest;epic-initial;epic-added" -Mode Add
    Write-Host "Added additional tag to Epic" -ForegroundColor Green

    # Verify new tags
    $epicRetrieved2 = & "$SRC_DIR/GetAzDoWorkItem.ps1" -Organization $Organization -Project $Project -WorkItemId $epicId
    if ($epicRetrieved2.fields.'System.Tags' -like "*epic-added*") {
        Write-Host "✓ Additional Epic tag verified" -ForegroundColor Green
    }
    else {
        throw "Additional Epic tag not found: $($epicRetrieved2.fields.'System.Tags')"
    }

    # Test 2: Create Feature with tags and verify
    Write-Host "`n--- Test 2: Feature ---" -ForegroundColor Yellow
    $featureTitle = "Smoke Test Feature $(Get-Random)"
    Write-Host "Creating Feature: $featureTitle"
    $feature = & "$SRC_DIR/UpsertAzDoFeature.ps1" -Organization $Organization -Project $Project `
        -Title $featureTitle -ParentEpicId $epicId
    $featureId = $feature.id
    Add-CreatedItem -ItemId $featureId
    Write-Host "Created Feature (ID: $featureId)" -ForegroundColor Green

    # Add initial tags
    & "$SRC_DIR/SetAzDoWorkItemTags.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $featureId -Tags "smokeTest;feature-initial"
    Write-Host "Added initial tags to Feature" -ForegroundColor Green

    # Verify tags
    $featureRetrieved = & "$SRC_DIR/GetAzDoWorkItem.ps1" -Organization $Organization -Project $Project -WorkItemId $featureId
    if ($featureRetrieved.fields.'System.Tags' -like "*feature-initial*") {
        Write-Host "✓ Feature tags verified" -ForegroundColor Green
    }
    else {
        throw "Feature tags not found or incorrect: $($featureRetrieved.fields.'System.Tags')"
    }

    # Add additional tag
    & "$SRC_DIR/SetAzDoWorkItemTags.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $featureId -Tags "smokeTest;feature-initial;feature-added" -Mode Add
    Write-Host "Added additional tag to Feature" -ForegroundColor Green

    # Verify new tags
    $featureRetrieved2 = & "$SRC_DIR/GetAzDoWorkItem.ps1" -Organization $Organization -Project $Project -WorkItemId $featureId
    if ($featureRetrieved2.fields.'System.Tags' -like "*feature-added*") {
        Write-Host "✓ Additional Feature tag verified" -ForegroundColor Green
    }
    else {
        throw "Additional Feature tag not found: $($featureRetrieved2.fields.'System.Tags')"
    }

    # Test 3: Create Story with tags and verify
    Write-Host "`n--- Test 3: Story ---" -ForegroundColor Yellow
    $storyTitle = "Smoke Test Story $(Get-Random)"
    Write-Host "Creating Story: $storyTitle"
    $story = & "$SRC_DIR/UpsertAzDoStory.ps1" -Organization $Organization -Project $Project `
        -Title $storyTitle -ParentFeatureId $featureId
    $storyId = $story.id
    Add-CreatedItem -ItemId $storyId
    Write-Host "Created Story (ID: $storyId)" -ForegroundColor Green

    # Add initial tags
    & "$SRC_DIR/SetAzDoWorkItemTags.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $storyId -Tags "smokeTest;story-initial"
    Write-Host "Added initial tags to Story" -ForegroundColor Green

    # Verify tags via GetAzDoUserStory
    $storyRetrieved = & "$SRC_DIR/GetAzDoUserStory.ps1" -Organization $Organization -Project $Project -WorkItemId $storyId
    if ($storyRetrieved.Tags -like "*story-initial*") {
        Write-Host "✓ Story tags verified" -ForegroundColor Green
    }
    else {
        throw "Story tags not found or incorrect: $($storyRetrieved.Tags)"
    }

    # Add additional tag
    & "$SRC_DIR/SetAzDoWorkItemTags.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $storyId -Tags "smokeTest;story-initial;story-added" -Mode Add
    Write-Host "Added additional tag to Story" -ForegroundColor Green

    # Verify new tags
    $storyRetrieved2 = & "$SRC_DIR/GetAzDoUserStory.ps1" -Organization $Organization -Project $Project -WorkItemId $storyId
    if ($storyRetrieved2.Tags -like "*story-added*") {
        Write-Host "✓ Additional Story tag verified" -ForegroundColor Green
    }
    else {
        throw "Additional Story tag not found: $($storyRetrieved2.Tags)"
    }

    # Test 4: Create Task with tags and verify
    Write-Host "`n--- Test 4: Task ---" -ForegroundColor Yellow
    $taskTitle = "Smoke Test Task $(Get-Random)"
    Write-Host "Creating Task: $taskTitle"
    $task = & "$SRC_DIR/UpsertAzDoTask.ps1" -Organization $Organization -Project $Project `
        -Title $taskTitle -ParentStoryId $storyId
    $taskId = $task.id
    Add-CreatedItem -ItemId $taskId
    Write-Host "Created Task (ID: $taskId)" -ForegroundColor Green

    # Add initial tags
    & "$SRC_DIR/SetAzDoWorkItemTags.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $taskId -Tags "smokeTest;task-initial"
    Write-Host "Added initial tags to Task" -ForegroundColor Green

    # Verify tags
    $taskRetrieved = & "$SRC_DIR/GetAzDoWorkItem.ps1" -Organization $Organization -Project $Project -WorkItemId $taskId
    if ($taskRetrieved.fields.'System.Tags' -like "*task-initial*") {
        Write-Host "✓ Task tags verified" -ForegroundColor Green
    }
    else {
        throw "Task tags not found or incorrect: $($taskRetrieved.fields.'System.Tags')"
    }

    # Add additional tag
    & "$SRC_DIR/SetAzDoWorkItemTags.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $taskId -Tags "smokeTest;task-initial;task-added" -Mode Add
    Write-Host "Added additional tag to Task" -ForegroundColor Green

    # Verify new tags
    $taskRetrieved2 = & "$SRC_DIR/GetAzDoWorkItem.ps1" -Organization $Organization -Project $Project -WorkItemId $taskId
    if ($taskRetrieved2.fields.'System.Tags' -like "*task-added*") {
        Write-Host "✓ Additional Task tag verified" -ForegroundColor Green
    }
    else {
        throw "Additional Task tag not found: $($taskRetrieved2.fields.'System.Tags')"
    }

    Write-Host "`n=== ALL SMOKE TESTS PASSED ===" -ForegroundColor Green
}
catch {
    Write-Host "`n✗ SMOKE TEST FAILED: $_" -ForegroundColor Red
    exit 1
}
finally {
    Cleanup
}
