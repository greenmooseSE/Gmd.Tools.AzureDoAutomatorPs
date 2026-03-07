<#
.SYNOPSIS
Integration test for GetAzDoHierarchyForFeature functionality

.DESCRIPTION
Tests the GetAzDoHierarchyForFeature.ps1 script for retrieving Feature hierarchies
with Stories and Tasks.

Requires Environment variable set:
- GMD_AZDO_ORGANIZATION: Organization name
- GMD_AZDO_PROJECT: Project name
- GMD_AZDO_MACHINE_WORKITEMSRW: Encrypted PAT token

Run with: pwsh -File .\GetAzDoHierarchyForFeatureTest.ps1

.NOTES
Creates temporary test Epic, Features, Stories, and Tasks, then cleans them up.
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
    }
}

function Cleanup {
    if ($script:createdItems.Count -gt 0) {
        Write-Host "`nCleaning up test items..." -ForegroundColor Cyan
        try {
            # Delete Epic (which will delete all children)
            $epicId = $script:createdItems[0]
            & "$SRC_DIR/RemoveAzDoEpic.ps1" -Organization $Organization -Project $Project -EpicId $epicId -Force
            Write-Host "Cleaned up test Epic (ID: $epicId)" -ForegroundColor Green
        }
        catch {
            Write-Host "Warning: Cleanup failed: $_" -ForegroundColor Yellow
        }
    }
}

# Register cleanup on exit
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Cleanup }

try {
    Write-Host "`n=== GetAzDoHierarchyForFeature Integration Tests ===" -ForegroundColor Cyan
    Write-Host "Organization: $Organization"
    Write-Host "Project: $Project"

    # Create test data
    Write-Host "`nCreating test data..." -ForegroundColor Cyan
    
    $epicTitle = "GetAzDoHierarchyForFeature Test Epic $(Get-Random)"
    Write-Host "Creating test Epic: $epicTitle"
    $epic = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project -Title $epicTitle
    $script:createdItems += $epic.id
    Write-Host "Created Epic (ID: $($epic.id))" -ForegroundColor Green

    $featureTitle = "GetAzDoHierarchyForFeature Test Feature $(Get-Random)"
    Write-Host "Creating test Feature: $featureTitle"
    $feature = & "$SRC_DIR/UpsertAzDoFeature.ps1" -Organization $Organization -Project $Project -Title $featureTitle -ParentId $epic.id
    $script:createdItems += $feature.id
    Write-Host "Created Feature (ID: $($feature.id))" -ForegroundColor Green

    # Create Stories
    $storyIds = @()
    for ($i = 1; $i -le 2; $i++) {
        $storyTitle = "🧪 GetAzDoHierarchyForFeature Test Story $i $(Get-Random)"
        Write-Host "Creating test Story $i: $storyTitle"
        $story = & "$SRC_DIR/UpsertAzDoStory.ps1" -Organization $Organization -Project $Project -Title $storyTitle -ParentId $feature.id
        $script:createdItems += $story.id
        $storyIds += $story.id
        Write-Host "Created Story $i (ID: $($story.id))" -ForegroundColor Green

        # Create Tasks for each Story
        for ($j = 1; $j -le 2; $j++) {
            $taskTitle = "🧪 Task $j for Story $i"
            Write-Host "  Creating Task $j: $taskTitle"
            $task = & "$SRC_DIR/UpsertAzDoTask.ps1" -Organization $Organization -Project $Project -Title $taskTitle -ParentId $story.id
            $script:createdItems += $task.id
            Write-Host "  Created Task (ID: $($task.id))" -ForegroundColor Green
        }
    }

    Write-Host "`nRunning tests...`n" -ForegroundColor Cyan

    # Test 1: Get by Feature ID
    Invoke-Test "GetAzDoHierarchyForFeature by ID" {
        $result = & "$SRC_DIR/GetAzDoHierarchyForFeature.ps1" -Organization $Organization -Project $Project -FeatureId $feature.id
        
        if ($null -eq $result) {
            throw "Result is null"
        }
        if ($result.Id -ne $feature.id) {
            throw "Feature ID mismatch"
        }
        if ([string]::IsNullOrWhiteSpace($result.Title)) {
            throw "Title is empty"
        }
        if ($result.Stories.Count -ne 2) {
            throw "Expected 2 Stories, got $($result.Stories.Count)"
        }
    }

    # Test 2: Get by Feature Title
    Invoke-Test "GetAzDoHierarchyForFeature by Title" {
        $result = & "$SRC_DIR/GetAzDoHierarchyForFeature.ps1" -Organization $Organization -Project $Project -FeatureTitle $feature.fields.'System.Title'
        
        if ($null -eq $result) {
            throw "Result is null"
        }
        if ($result.Id -ne $feature.id) {
            throw "Feature ID mismatch when searched by title"
        }
    }

    # Test 3: Verify Story details
    Invoke-Test "Stories have full details" {
        $result = & "$SRC_DIR/GetAzDoHierarchyForFeature.ps1" -Organization $Organization -Project $Project -FeatureId $feature.id
        
        foreach ($story in $result.Stories) {
            if ($story.PSObject.Properties.Name -notcontains "Title") {
                throw "Story missing Title"
            }
            if ($story.PSObject.Properties.Name -notcontains "State") {
                throw "Story missing State"
            }
            if ($story.PSObject.Properties.Name -notcontains "Tags") {
                throw "Story missing Tags"
            }
            if ($story.PSObject.Properties.Name -contains "Comments") {
                throw "Story should not have Comments"
            }
        }
    }

    # Test 4: Verify Tasks are included
    Invoke-Test "Stories include Tasks" {
        $result = & "$SRC_DIR/GetAzDoHierarchyForFeature.ps1" -Organization $Organization -Project $Project -FeatureId $feature.id
        
        foreach ($story in $result.Stories) {
            if ($story.PSObject.Properties.Name -notcontains "Tasks") {
                throw "Story missing Tasks property"
            }
            if ($story.Tasks.Count -lt 1) {
                throw "Story should have at least 1 Task, got $($story.Tasks.Count)"
            }
        }
    }

    # Test 5: Return null for non-existent Feature
    Invoke-Test "Returns null for non-existent Feature" {
        $result = & "$SRC_DIR/GetAzDoHierarchyForFeature.ps1" -Organization $Organization -Project $Project -FeatureId 999999
        
        if ($null -ne $result) {
            throw "Expected null for non-existent Feature, got: $result"
        }
    }

    # Output summary
    Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
    Write-Host "Tests Run: $testsRun" -ForegroundColor Cyan
    Write-Host "Passed: $testsPassed" -ForegroundColor Green
    Write-Host "Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { 'Red' } else { 'Green' })

    # Cleanup
    Cleanup

    # Exit with appropriate code
    exit $(if ($testsFailed -gt 0) { 1 } else { 0 })
}
catch {
    Write-Host "`nFatal error: $_" -ForegroundColor Red
    Cleanup
    exit 1
}
