#Requires -Version 7.0

<#
.SYNOPSIS
Test that tasks created via NewAzDoHierarchyFromMarkdown have tags applied

.DESCRIPTION
Verifies that:
1. Tasks inherit tags from markdown (custom tags)
2. Tasks receive autoGen tag like other work items
3. All tags are applied to created task work items in Azure DevOps

Test creates a minimal hierarchy with a task that has custom tags, then verifies
the tags are present on the created work item.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$Project,

    [string]$PatToken
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\..\src\AzDoPatTokenHelper.ps1"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

# Create test markdown with a task that has specific tags
$testMarkdown = @"
# Task Tags Test Epic

**tags**: test, hierarchy\
**Effort**: 5

Test epic for task tags.

## Feature: Task Testing

**tags**: features\
**Effort**: 3

Feature with tasks.

### Story: Task Tags Verification

**tags**: stories\
**SP**: 2

Story with tagged task.

#### Task: Verify Tags Applied

**tags**: tasktest, custom\
**Priority**: 1

**Description**: This task should have its tags applied in Azure DevOps.

**Original Estimate**: 2

**Remaining**: 2

**Completed**: 0
"@

$tempFile = Join-Path -Path $env:TEMP -ChildPath "task-tags-test-$([Guid]::NewGuid()).md"
$testMarkdown | Set-Content -Path $tempFile -Encoding UTF8

try {
    Write-Host "Creating test hierarchy with tagged task..." -ForegroundColor Cyan
    
    # Create hierarchy
    $result = & "$PSScriptRoot\..\src\NewAzDoHierarchyFromMarkdown.ps1" `
        -Organization $Organization `
        -Project $Project `
        -MarkdownFilePath $tempFile `
        -PatToken $PatToken `
        -ErrorAction Stop
    
    # Find the created task
    $createdTask = $null
    foreach ($itemId in $result.CreatedItems.Keys) {
        $item = $result.CreatedItems[$itemId]
        if ($item.PSObject.Properties['fields'] -and 
            $item.fields.'System.WorkItemType' -eq 'Task' -and
            $item.fields.'System.Title' -eq 'Verify Tags Applied') {
            $createdTask = $item
            $createdTaskId = $itemId
            break
        }
    }
    
    if ($null -eq $createdTask) {
        throw "Created task not found in results"
    }
    
    Write-Host "Found created task ID: $createdTaskId" -ForegroundColor Green
    
    # Get the work item to check tags
    Write-Host "Retrieving task to verify tags..." -ForegroundColor Cyan
    $retrievedTask = & "$PSScriptRoot\..\src\GetAzDoWorkItem.ps1" `
        -Organization $Organization `
        -Project $Project `
        -WorkItemId $createdTaskId `
        -PatToken $PatToken `
        -ErrorAction Stop
    
    # Extract tags
    $tags = $retrievedTask.fields.'System.Tags' -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    
    Write-Host "Task ID $createdTaskId tags:" -ForegroundColor Cyan
    Write-Host "  $($tags -join ', ')" -ForegroundColor Yellow
    
    # Verify tags
    $hasTaskTest = $tags -contains 'tasktest'
    $hasCustom = $tags -contains 'custom'
    $hasAutoGen = $tags -contains 'autoGen'
    
    Write-Host "`nTag verification:" -ForegroundColor Cyan
    Write-Host "  ✓ tasktest tag: $(if($hasTaskTest) { 'PRESENT' } else { 'MISSING' })" -ForegroundColor $(if($hasTaskTest) { 'Green' } else { 'Red' })
    Write-Host "  ✓ custom tag: $(if($hasCustom) { 'PRESENT' } else { 'MISSING' })" -ForegroundColor $(if($hasCustom) { 'Green' } else { 'Red' })
    Write-Host "  ✓ autoGen tag: $(if($hasAutoGen) { 'PRESENT' } else { 'MISSING' })" -ForegroundColor $(if($hasAutoGen) { 'Green' } else { 'Red' })
    
    if ($hasTaskTest -and $hasCustom -and $hasAutoGen) {
        Write-Host "`n✓ ALL TESTS PASSED: Task tags are correctly applied!" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "`n✗ TEST FAILED: Some tags are missing!" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "Test failed: $_" -ForegroundColor Red
    exit 1
}
finally {
    # Clean up
    if (Test-Path -Path $tempFile) {
        Remove-Item -Path $tempFile -Force
    }
}
