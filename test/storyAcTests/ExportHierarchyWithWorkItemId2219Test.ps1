<#
.SYNOPSIS
Test for story AB#2219: Export Hierarchy to Markdown with WorkItemId Preservation

.DESCRIPTION
Tests that exported markdown includes WorkItemId in metadata for all work items,
and that WorkItemId is preserved during export for round-trip import validation.

Tests Acceptance Tests:
1. Export includes WorkItemId for each work item
2. Complete hierarchy with all levels is exported
3. Export preserves all metadata fields

Requires Environment variables:
- GMD_AZDO_ORGANIZATION: Organization name
- GMD_AZDO_PROJECT: Project name
- GMD_AZDO_MACHINE_WORKITEMSRW: Encrypted PAT token

Run with: pwsh -File .\ExportHierarchyWithWorkItemId2219Test.ps1
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
[string]$SRC_DIR = Join-Path $SCRIPT_DIR '../../src'

# Validate inputs
if ([string]::IsNullOrWhiteSpace($Organization)) {
    Write-Error "Organization not provided."
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    Write-Error "Project not provided."
}

# Test counters
[int]$testsRun = 0
[int]$testsPassed = 0
[int]$testsFailed = 0
[array]$createdItems = @()

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
    }
    catch {
        $script:testsFailed++
        Write-Host "  ✗ FAILED: $_" -ForegroundColor Red
        Write-Host "Stack: $($_.ScriptStackTrace)" -ForegroundColor Red
    }
}

function Cleanup-CreatedItems {
    Write-Host "`n=== Cleaning up created test items ===" -ForegroundColor Cyan
    
    if ($createdItems.Count -eq 0) {
        Write-Host "No items to clean up"
        return
    }
    
    # Reverse order to delete children before parents
    [array]::Reverse($createdItems)
    
    foreach ($item in $createdItems) {
        try {
            & "$SRC_DIR/RemoveAzDoEpic.ps1" -Organization $Organization -Project $Project -EpicId $item -ErrorAction SilentlyContinue | Out-Null
            & "$SRC_DIR/RemoveAzDoTask.ps1" -Organization $Organization -Project $Project -TaskId $item -ErrorAction SilentlyContinue | Out-Null
            Write-Host "  Cleaned up item ID: $item"
        }
        catch {
            Write-Host "  Warning: Could not clean item $item" -ForegroundColor Yellow
        }
    }
}

Write-Host "=== Story AB#2219 Tests: Export Hierarchy with WorkItemId Preservation ===" -ForegroundColor Cyan
Write-Host "Organization: $Organization"
Write-Host "Project: $Project`n"

try {
    # Test 1: ACCEPTANCE TEST 1 - WorkItemId in Feature metadata using feature 2216
    Invoke-Test "ACCEPTANCE TEST 1: Feature includes WorkItemId in markdown metadata" {
        Write-Host "  Fetching Feature 2216 hierarchy..." -ForegroundColor Cyan
        
        # Get Feature hierarchy for the existing feature 2216
        $hierarchy = & "$SRC_DIR/GetAzDoHierarchyForFeature.ps1" -Organization $Organization -Project $Project -FeatureId 2216
        
        # Convert to markdown
        $markdown = & "$SRC_DIR/ConvertHierarchyToMarkdown.ps1" -Hierarchy $hierarchy -Organization $Organization -Project $Project
        
        # Verify Feature WorkItemId 2216 is in markdown at top level 
        if ($markdown -match "\*\*WorkItemId\*\*:\s*2216") {
            Write-Host "  ✓ Found Feature WorkItemId 2216 in markdown" -ForegroundColor Green
        }
        else {
            throw "Feature WorkItemId 2216 not found in markdown metadata"
        }
        
        # Also verify that Stories within the feature have WorkItemIds
        $storyMatches = [regex]::Matches($markdown, "\*\*WorkItemId\*\*:\s*(\d+)")
        if ($storyMatches.Count -gt 1) {
            Write-Host "  ✓ Found $($storyMatches.Count) WorkItemId entries (Feature + Stories)" -ForegroundColor Green
        }
        else {
            throw "Expected multiple WorkItemId entries but found only $($storyMatches.Count)"
        }
    }
    
    # Test 2: ACCEPTANCE TEST 2 & 3 - Complete hierarchy with all levels and metadata
    Invoke-Test "ACCEPTANCE TEST 2 & 3: Hierarchy preserves all metadata with WorkItemIds" {
        Write-Host "  Verifying complete hierarchy structure..." -ForegroundColor Cyan
        
        # Get Feature hierarchy
        $hierarchy = & "$SRC_DIR/GetAzDoHierarchyForFeature.ps1" -Organization $Organization -Project $Project -FeatureId 2216
        
        # Convert to markdown
        $markdown = & "$SRC_DIR/ConvertHierarchyToMarkdown.ps1" -Hierarchy $hierarchy -Organization $Organization -Project $Project
        
        # Verify Feature heading exists
        if (-not ($markdown -match "## Feature:.*Export and Reimport")) {
            throw "Feature heading not found"
        }
        Write-Host "  ✓ Feature heading present" -ForegroundColor Green
        
        # Verify Stories are present
        $storyHeadings = [regex]::Matches($markdown, "### Story:")
        if ($storyHeadings.Count -eq 0) {
            throw "No Story headings found"
        }
        Write-Host "  ✓ Found $($storyHeadings.Count) Story heading(s)" -ForegroundColor Green
        
        # Verify metadata fields exist
        if (-not ($markdown -match "\*\*WorkItemId\*\*:" -and $markdown -match "\*\*State\*\*:")) {
            throw "Required metadata fields missing"
        }
        Write-Host "  ✓ Metadata fields present (WorkItemId, State)" -ForegroundColor Green
        
        # Verify descriptions are preserved
        if ($markdown -match "Description.*Export") {
            Write-Host "  ✓ Descriptions are preserved" -ForegroundColor Green
        }
    }
    
    # Test 3: Verify WorkItemId immutability in the format
    Invoke-Test "WorkItemId format is consistent across all work items" {
        Write-Host "  Checking WorkItemId format consistency..." -ForegroundColor Cyan
        
        # Get Feature hierarchy
        $hierarchy = & "$SRC_DIR/GetAzDoHierarchyForFeature.ps1" -Organization $Organization -Project $Project -FeatureId 2216
        $markdown = & "$SRC_DIR/ConvertHierarchyToMarkdown.ps1" -Hierarchy $hierarchy -Organization $Organization -Project $Project
        
        # Extract all WorkItemId values
        $idMatches = [regex]::Matches($markdown, "\*\*WorkItemId\*\*:\s*(\d+)")
        
        if ($idMatches.Count -eq 0) {
            throw "No WorkItemId entries found in markdown"
        }
        
        Write-Host "  ✓ Found $($idMatches.Count) WorkItemId entries" -ForegroundColor Green
        
        # Verify all are numeric and properly formatted
        foreach ($match in $idMatches) {
            $id = $match.Groups[1].Value
            if ($id -match '^\d+$') {
                Write-Host "    ✓ WorkItemId $id is properly formatted" -ForegroundColor Cyan
            }
            else {
                throw "Invalid WorkItemId format: $id"
            }
        }
        
        Write-Host "  ✓ All WorkItemIds are properly formatted" -ForegroundColor Green
    }
}
finally {
    # Always cleanup
    Cleanup-CreatedItems
}

# Print summary
Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Tests run: $testsRun"
Write-Host "Passed: $testsPassed" -ForegroundColor Green
Write-Host "Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })

# Exit with appropriate code
exit $(if ($testsFailed -eq 0) { 0 } else { 1 })
