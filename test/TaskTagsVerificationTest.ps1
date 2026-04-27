#Requires -Version 7.0

<#
.SYNOPSIS
Test scenario verifying task tags are properly created and applied via NewAzDoHierarchyFromMarkdown.ps1
Tests that tasks created from markdown with tags actually have those tags set in Azure DevOps

.DESCRIPTION
This test scenario verifies:
1. Markdown with task tags is correctly parsed
2. Tasks are created under parent stories
3. Tags are applied to created tasks
4. Tag verification can fetch tags from created tasks
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$Organization = "falco-it"
$Project = "gmd"
$SRC_DIR = ".\src"

[System.Collections.ArrayList]$createdItems = @()

function Register-CreatedItem {
    param(
        [int]$ItemId,
        [string]$Type = "Unknown"
    )
    $createdItems.Add(
        [PSCustomObject]@{
            Id   = $ItemId
            Type = $Type
        }
    ) | Out-Null
}

function Cleanup-CreatedItems {
    Write-Host "`nCleaning up created test items..." -ForegroundColor Cyan
    
    # Sort by ID descending to delete children before parents
    $sortedItems = $createdItems | Sort-Object { $_.Id } -Descending
    
    foreach ($item in $sortedItems) {
        try {
            if ($item.Type -eq 'Task') {
                & "$SRC_DIR/RemoveAzDoTask.ps1" -Organization $Organization -Project $Project -TaskId $item.Id -Force -ErrorAction SilentlyContinue | Out-Null
                Write-Host "  Cleaned up Task ID: $($item.Id)" -ForegroundColor Green
            }
            elseif ($item.Type -eq 'Story') {
                & "$SRC_DIR/RemoveAzDoComment.ps1" -Organization $Organization -Project $Project -CommentId $item.Id -ErrorAction SilentlyContinue | Out-Null
                Write-Host "  Cleaned up Story ID: $($item.Id)" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "  Warning: Failed to clean up $($item.Type) ID: $($item.Id)" -ForegroundColor Yellow
        }
    }
}

# Create temporary markdown file with task tags
$tempMarkdownFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "TestTaskTags_$(Get-Date -Format 'yyyyMMddHHmmss').md")

$markdownContent = @"
# Epic: TaskTagsTestEpic_$(Get-Date -Format 'yyyyMMddHHmmss')
**tags**: epic-tag-1, epic-tag-2

## Feature: TaskTagsTestFeature_$(Get-Date -Format 'yyyyMMddHHmmss')
**tags**: feature-tag-1

### Story: TaskTagsTestStory_$(Get-Date -Format 'yyyyMMddHHmmss')
**tags**: story-tag-1, story-tag-2
**Story Points**: 8

#### Task: TaskTagsTest_Task1_$(Get-Date -Format 'yyyyMMddHHmmss')
**Description**: First test task with tags
**tags**: task-tag-1, task-tag-2, task-tag-3
**Priority**: 1
**Original Estimate**: 4

#### Task: TaskTagsTest_Task2_$(Get-Date -Format 'yyyyMMddHHmmss')
**Description**: Second test task with different tags
**tags**: task-tag-4
**Priority**: 2
**Remaining Work**: 2
"@

try {
    # Write markdown file
    Set-Content -Path $tempMarkdownFile -Value $markdownContent -Force
    Write-Host "Created temporary markdown test file: $tempMarkdownFile" -ForegroundColor Green
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║ TASK TAGS VERIFICATION TEST                                    ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    # Run NewAzDoHierarchyFromMarkdown with the test markdown
    Write-Host "`n[STEP 1] Creating hierarchy from markdown with task tags..." -ForegroundColor Yellow
    $result = & "$SRC_DIR/NewAzDoHierarchyFromMarkdown.ps1" `
        -Organization $Organization `
        -Project $Project `
        -MarkdownFilePath $tempMarkdownFile `
        -ErrorAction Stop
    
    if ($null -eq $result.CreatedItems -or $result.CreatedItems.Count -eq 0) {
        throw "No items created from markdown"
    }
    
    Write-Host "✓ Successfully created hierarchy from markdown" -ForegroundColor Green
    Write-Host "  Created items: $($result.CreatedItems.Count)" -ForegroundColor Green
    
    # Register all created items for cleanup
    foreach ($itemId in $result.CreatedItems.Keys) {
        $item = $result.CreatedItems[$itemId]
        $itemType = $item.fields.'System.WorkItemType'
        Register-CreatedItem -ItemId $itemId -Type $itemType
        Write-Host "  - $itemType (ID: $itemId): $($item.fields.'System.Title')" -ForegroundColor Cyan
    }
    
    # Extract task IDs from created items
    [System.Collections.ArrayList]$taskIds = @()
    foreach ($itemId in $result.CreatedItems.Keys) {
        $item = $result.CreatedItems[$itemId]
        if ($item.fields.'System.WorkItemType' -eq 'Task') {
            $taskIds.Add($itemId) | Out-Null
        }
    }
    
    Write-Host "`n[STEP 2] Verifying task tags were applied..." -ForegroundColor Yellow
    
    if ($taskIds.Count -eq 0) {
        throw "No tasks were created in hierarchy"
    }
    
    Write-Host "  Found $($taskIds.Count) tasks to verify" -ForegroundColor Cyan
    
    [int]$tasksWithTags = 0
    [int]$tasksWithoutTags = 0
    
    foreach ($taskId in $taskIds) {
        # Get the task details including tags
        $taskDetails = & "$SRC_DIR/GetAzDoWorkItem.ps1" `
            -Organization $Organization `
            -Project $Project `
            -WorkItemId $taskId `
            -ErrorAction Stop
        
        $taskTitle = $taskDetails.fields.'System.Title'
        
        # Check for tags - try different possible property paths
        $taskTags = $null
        if ($taskDetails.fields.PSObject.Properties['System.Tags']) {
            $taskTags = $taskDetails.fields.'System.Tags'
        }
        elseif ($taskDetails.PSObject.Properties['tags']) {
            $taskTags = $taskDetails.tags
        }
        
        if ([string]::IsNullOrWhiteSpace($taskTags)) {
            Write-Host "  ✗ Task '$taskTitle' (ID: $taskId) has NO tags" -ForegroundColor Red
            $tasksWithoutTags++
        }
        else {
            Write-Host "  ✓ Task '$taskTitle' (ID: $taskId) has tags: $taskTags" -ForegroundColor Green
            $tasksWithTags++
        }
    }
    
    # Summary
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║ TEST SUMMARY                                                   ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    Write-Host "`nTask Tags Verification Results:" -ForegroundColor Yellow
    Write-Host "  Tasks created: $($taskIds.Count)" -ForegroundColor Cyan
    Write-Host "  Tasks with tags: $tasksWithTags" -ForegroundColor Green
    Write-Host "  Tasks missing tags: $tasksWithoutTags" -ForegroundColor $(if ($tasksWithoutTags -gt 0) { 'Red' } else { 'Green' })
    
    if ($tasksWithoutTags -gt 0) {
        Write-Host "`n✗ FAILED: Some tasks did not receive tags" -ForegroundColor Red
        exit 1
    }
    else {
        Write-Host "`n✓ PASSED: All tasks received tags correctly" -ForegroundColor Green
        exit 0
    }
}
catch {
    Write-Host "`n✗ TEST FAILED: $_" -ForegroundColor Red
    exit 1
}
finally {
    # Cleanup
    Cleanup-CreatedItems
    
    # Remove temp markdown file
    if (Test-Path $tempMarkdownFile) {
        Remove-Item $tempMarkdownFile -Force -ErrorAction SilentlyContinue
        Write-Host "`nRemoved temporary markdown file" -ForegroundColor Green
    }
}
