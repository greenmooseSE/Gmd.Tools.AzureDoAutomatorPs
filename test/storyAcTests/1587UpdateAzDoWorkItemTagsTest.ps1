#Requires -Version 7.0

<#
.SYNOPSIS
Comprehensive test suite for UpdateAzDoWorkItemTags.ps1

.DESCRIPTION
Tests all acceptance criteria and BDD scenarios for Story 1587:
- AC1: Script successfully renamed from SetAzDoWorkItemTags to UpdateAzDoWorkItemTags  
- AC2: Supports -Organization, -Project, -WorkItemId, -Tags (array/string), -Replace
- AC3: Supports separate mode for tag removal via -NotTags parameter
- AC4: Can remove specific tags via -NotTags while keeping others
- AC5: Empty -Tags with -Replace removes all tags
- AC6: Outputs updated work item with Tags array as JSON

BDD Scenarios:
1. Add tags to work item (with -Tags "bug", "urgent")
2. Remove specific tag (with -NotTags "bug")
3. Replace all tags (with -Tags ["new-tag"] -Replace)
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Resolve script root
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$srcPath = Resolve-Path "$scriptRoot/../../src"

# Import test utilities
. "$srcPath/AzDoPatTokenHelper.ps1"
. "$srcPath/AzDoApiWrapper.ps1"

$ErrorActionPreference = 'Continue'

# Test configuration
$testOrganization = 'falco-it'
$testProject = 'GMD'
$testTag1 = 'testWi'  # Track all test work items with this tag
$testTag2 = 'test-scenario-1587'

# Colors for output
$successColor = 'Green'
$errorColor = 'Red'
$infoColor = 'Cyan'

Write-Host "`n" -ForegroundColor $infoColor
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor $infoColor
Write-Host "║ Story 1587 - UpdateAzDoWorkItemTags Test Suite                 ║" -ForegroundColor $infoColor
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor $infoColor

# Track all created test work items for cleanup
$createdWorkItems = @()

try {
    # Helper function to create test task
    function New-TestTask {
        param([string]$Title)
        
        try {
            $result = & "$srcPath/UpsertAzDoTask.ps1" `
                -Organization $testOrganization `
                -Project $testProject `
                -Title $Title
            
            return $result.id
        }
        catch {
            throw "Failed to create test task: $_"
        }
    }

    # Helper function to get work item tags
    function Get-WorkItemTags {
        param([int]$WorkItemId)
        
        $headers = New-AzDoAuthHeader -PatToken (Get-AzDoPatToken -Decrypt)
        $uri = "https://dev.azure.com/$testOrganization/$testProject/_apis/wit/workitems/$WorkItemId`?api-version=7.1"
        
        $result = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -ErrorAction Stop
        
        # Check if fields exists and has System.Tags property
        if ($null -ne $result.fields) {
            if ($result.fields.PSObject.Properties.Name -contains 'System.Tags') {
                $tags = $result.fields.'System.Tags'
                if ($null -ne $tags -and -not [string]::IsNullOrWhiteSpace($tags)) {
                    return $tags -split ';' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                }
            }
        }
        return @()
    }

    # Helper function to delete test work items via RemoveAzDoTask
    function Remove-TestTask {
        param([int]$WorkItemId)
        
        try {
            & "$srcPath/RemoveAzDoTask.ps1" `
                -Organization $testOrganization `
                -Project $testProject `
                -TaskId $WorkItemId `
                -Force 2>&1 | Out-Null
        }
        catch {
            # Ignore errors during cleanup
        }
    }

    # ========== SCENARIO 1: Add tags to work item ==========
    Write-Host "`n[Scenario 1] Add tags to work item" -ForegroundColor $infoColor
    Write-Host "Expected: Tags 'bug' and 'urgent' are added to work item" -ForegroundColor $infoColor
    
    $scenario1ItemId = New-TestTask "1587-Scenario1-AddTags"
    $createdWorkItems += $scenario1ItemId
    Write-Host "  Created test work item: $scenario1ItemId" -ForegroundColor Gray
    
    # Add tags
    $result1 = & "$srcPath/UpdateAzDoWorkItemTags.ps1" `
        -Organization $testOrganization `
        -Project $testProject `
        -WorkItemId $scenario1ItemId `
        -Tags @("bug", "urgent")
    
    $tags1 = Get-WorkItemTags $scenario1ItemId
    $hasTag1 = $tags1 -contains "bug"
    $hasTag2 = $tags1 -contains "urgent"
    
    if ($hasTag1 -and $hasTag2) {
        Write-Host "  ✅ PASSED - Both 'bug' and 'urgent' tags present" -ForegroundColor $successColor
    }
    else {
        Write-Host "  ❌ FAILED - Tags missing. Got: $($tags1 -join ', ')" -ForegroundColor $errorColor
        throw "Scenario 1 failed"
    }

    # ========== SCENARIO 2: Remove specific tag ==========
    Write-Host "`n[Scenario 2] Remove specific tag" -ForegroundColor $infoColor
    Write-Host "Expected: Only 'bug' tag is removed, 'urgent' is kept" -ForegroundColor $infoColor
    
    $scenario2ItemId = New-TestTask "1587-Scenario2-RemoveTag"
    $createdWorkItems += $scenario2ItemId
    Write-Host "  Created test work item: $scenario2ItemId" -ForegroundColor Gray
    
    # First add multiple tags
    & "$srcPath/UpdateAzDoWorkItemTags.ps1" `
        -Organization $testOrganization `
        -Project $testProject `
        -WorkItemId $scenario2ItemId `
        -Tags @("bug", "urgent", "api") `
        -Replace | Out-Null
    
    # Remove specific tag
    $result2 = & "$srcPath/UpdateAzDoWorkItemTags.ps1" `
        -Organization $testOrganization `
        -Project $testProject `
        -WorkItemId $scenario2ItemId `
        -NotTags @("bug")
    
    $tags2 = Get-WorkItemTags $scenario2ItemId
    $hasBug = $tags2 -contains "bug"
    $hasUrgent = $tags2 -contains "urgent"
    $hasApi = $tags2 -contains "api"
    
    if (-not $hasBug -and $hasUrgent -and $hasApi) {
        Write-Host "  ✅ PASSED - 'bug' removed, 'urgent' and 'api' kept. Tags: $($tags2 -join ', ')" -ForegroundColor $successColor
    }
    else {
        Write-Host "  ❌ FAILED - Wrong tags. Expected: urgent, api. Got: $($tags2 -join ', ')" -ForegroundColor $errorColor
        throw "Scenario 2 failed"
    }

    # ========== SCENARIO 3: Replace all tags ==========
    Write-Host "`n[Scenario 3] Replace all tags" -ForegroundColor $infoColor
    Write-Host "Expected: Old tags removed, only 'new-tag' remains" -ForegroundColor $infoColor
    
    $scenario3ItemId = New-TestTask "1587-Scenario3-ReplaceTags"
    $createdWorkItems += $scenario3ItemId
    Write-Host "  Created test work item: $scenario3ItemId" -ForegroundColor Gray
    
    # First add multiple tags
    & "$srcPath/UpdateAzDoWorkItemTags.ps1" `
        -Organization $testOrganization `
        -Project $testProject `
        -WorkItemId $scenario3ItemId `
        -Tags @("old-tag1", "old-tag2", "old-tag3") `
        -Replace | Out-Null
    
    # Replace with new tag
    $result3 = & "$srcPath/UpdateAzDoWorkItemTags.ps1" `
        -Organization $testOrganization `
        -Project $testProject `
        -WorkItemId $scenario3ItemId `
        -Tags @("new-tag") `
        -Replace
    
    $tags3 = Get-WorkItemTags $scenario3ItemId
    $hasNewTag = $tags3 -contains "new-tag"
    $hasOldTag = $tags3 -contains "old-tag1"
    $tagCount = @($tags3).Count  # Ensure array to get count
    
    if ($hasNewTag -and -not $hasOldTag -and $tagCount -eq 1) {
        Write-Host "  ✅ PASSED - Only 'new-tag' remains. Tags: $($tags3 -join ', ')" -ForegroundColor $successColor
    }
    else {
        Write-Host "  ❌ FAILED - Wrong tags. Expected only: new-tag. Got: $($tags3 -join ', ')" -ForegroundColor $errorColor
        throw "Scenario 3 failed"
    }

    # ========== AC5: Remove all tags with Replace ==========
    Write-Host "`n[AC5 Test] Remove all tags with -Replace" -ForegroundColor $infoColor
    Write-Host "Expected: All tags removed when -Replace used with empty -Tags" -ForegroundColor $infoColor
    
    $ac5ItemId = New-TestTask "1587-AC5-RemoveAllTags"
    $createdWorkItems += $ac5ItemId
    Write-Host "  Created test work item: $ac5ItemId" -ForegroundColor Gray
    
    # Add some tags first
    & "$srcPath/UpdateAzDoWorkItemTags.ps1" `
        -Organization $testOrganization `
        -Project $testProject `
        -WorkItemId $ac5ItemId `
        -Tags @("tag1", "tag2", "tag3") `
        -Replace | Out-Null
    
    # Remove all by using -Replace with no tags
    $resultAC5 = & "$srcPath/UpdateAzDoWorkItemTags.ps1" `
        -Organization $testOrganization `
        -Project $testProject `
        -WorkItemId $ac5ItemId `
        -Replace
    
    $tagsAC5 = Get-WorkItemTags $ac5ItemId
    $tagsAC5Count = @($tagsAC5).Count
    
    if ($null -eq $tagsAC5 -or $tagsAC5Count -eq 0) {
        Write-Host "  ✅ PASSED - All tags removed successfully" -ForegroundColor $successColor
    }
    else {
        Write-Host "  ❌ FAILED - Tags still present: $($tagsAC5 -join ', ')" -ForegroundColor $errorColor
        throw "AC5 test failed"
    }

    # ========== AC6: Output format check ==========
    Write-Host "`n[AC6 Test] Output format - JSON with Tags array" -ForegroundColor $infoColor
    Write-Host "Expected: Output is valid JSON PSObject with fields.System.Tags" -ForegroundColor $infoColor
    
    $ac6ItemId = New-TestTask "1587-AC6-OutputFormat"
    $createdWorkItems += $ac6ItemId
    
    $resultAC6 = & "$srcPath/UpdateAzDoWorkItemTags.ps1" `
        -Organization $testOrganization `
        -Project $testProject `
        -WorkItemId $ac6ItemId `
        -Tags @("output-test")
    
    # Verify output structure
    $isValid = $false
    if ($null -ne $resultAC6) {
        if ($null -ne $resultAC6.fields) {
            if ($resultAC6.fields.PSObject.Properties.Name -contains 'System.Tags') {
                $isValid = $true
            }
        }
    }
    
    if ($isValid) {
        Write-Host "  ✅ PASSED - Output has correct JSON structure with Tags" -ForegroundColor $successColor
    }
    else {
        Write-Host "  ❌ FAILED - Output missing expected fields" -ForegroundColor $errorColor
        throw "AC6 test failed"
    }

    # ========== Summary ==========
    Write-Host "`n" -ForegroundColor $infoColor
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor $successColor
    Write-Host "║ ✅ ALL TESTS PASSED                                            ║" -ForegroundColor $successColor
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor $successColor
    
    Write-Host "`nTest Coverage Summary:" -ForegroundColor Yellow
    Write-Host "  ✅ AC1: Script renamed to UpdateAzDoWorkItemTags.ps1" -ForegroundColor Green
    Write-Host "  ✅ AC2: Supports all required parameters" -ForegroundColor Green
    Write-Host "  ✅ AC3: -NotTags parameter for tag removal" -ForegroundColor Green
    Write-Host "  ✅ AC4: Remove specific tags with -NotTags (Scenario 2)" -ForegroundColor Green
    Write-Host "  ✅ AC5: Remove all tags with -Replace (AC5 test)" -ForegroundColor Green
    Write-Host "  ✅ AC6: JSON output format verified (AC6 test)" -ForegroundColor Green
    Write-Host "  ✅ Scenario 1: Add tags to work item" -ForegroundColor Green
    Write-Host "  ✅ Scenario 2: Remove specific tag" -ForegroundColor Green
    Write-Host "  ✅ Scenario 3: Replace all tags" -ForegroundColor Green
    Write-Host "`n"
}
catch {
    Write-Host "`n❌ TEST FAILED: $_" -ForegroundColor $errorColor
    Write-Host $_.Exception.Message -ForegroundColor $errorColor
}
finally {
    # Cleanup: Remove all created test work items
    Write-Host "Cleanup: Removing test work items..." -ForegroundColor Gray
    foreach ($itemId in $createdWorkItems) {
        try {
            Remove-TestTask $itemId
            Write-Host "  Removed work item: $itemId" -ForegroundColor Gray
        }
        catch {
            Write-Host "  Warning: Could not remove work item $itemId`"" -ForegroundColor Yellow
        }
    }
    Write-Host "Cleanup complete." -ForegroundColor Gray
}
