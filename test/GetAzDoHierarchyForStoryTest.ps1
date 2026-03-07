<#
.SYNOPSIS
Integration test for GetAzDoHierarchyForStory functionality

.DESCRIPTION
Tests the GetAzDoHierarchyForStory.ps1 script for retrieving Story hierarchies
with Tasks.

Requires Environment variable set:
- GMD_AZDO_ORGANIZATION: Organization name
- GMD_AZDO_PROJECT: Project name
- GMD_AZDO_MACHINE_WORKITEMSRW: Encrypted PAT token

Run with: pwsh -File .\GetAzDoHierarchyForStoryTest.ps1

.NOTES
Creates temporary test Epic, Feature, Story, and Tasks, then cleans them up.
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
    Write-Host "`n=== GetAzDoHierarchyForStory Integration Tests ===" -ForegroundColor Cyan
    Write-Host "Organization: $Organization"
    Write-Host "Project: $Project"

    # Create test data
    Write-Host "`nCreating test data..." -ForegroundColor Cyan
    
    $epicTitle = "GetAzDoHierarchyForStory Test Epic $(Get-Random)"
    Write-Host "Creating test Epic: $epicTitle"
    $epic = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project -Title $epicTitle
    $script:createdItems += $epic.id
    Write-Host "Created Epic (ID: $($epic.id))" -ForegroundColor Green

    $featureTitle = "GetAzDoHierarchyForStory Test Feature $(Get-Random)"
    Write-Host "Creating test Feature: $featureTitle"
    $feature = & "$SRC_DIR/UpsertAzDoFeature.ps1" -Organization $Organization -Project $Project -Title $featureTitle -ParentEpicId $epic.id
    $script:createdItems += $feature.id
    Write-Host "Created Feature (ID: $($feature.id))" -ForegroundColor Green

    $storyTitle = "🧪 GetAzDoHierarchyForStory Test Story $(Get-Random)"
    Write-Host "Creating test Story: $storyTitle"
    $story = & "$SRC_DIR/UpsertAzDoStory.ps1" -Organization $Organization -Project $Project -Title $storyTitle -ParentFeatureId $feature.id
    $script:createdItems += $story.id
    Write-Host "Created Story (ID: $($story.id))" -ForegroundColor Green

    # Create Tasks
    $taskIds = @()
    for ($i = 1; $i -le 3; $i++) {
        $taskTitle = "🧪 Task $i for Story"
        Write-Host "Creating test Task $($i): $taskTitle"
        $task = & "$SRC_DIR/UpsertAzDoTask.ps1" -Organization $Organization -Project $Project -Title $taskTitle -ParentStoryId $story.id
        $script:createdItems += $task.id
        $taskIds += $task.id
        Write-Host "Created Task $($i) (ID: $($task.id))" -ForegroundColor Green
    }

    Write-Host "`nRunning tests...`n" -ForegroundColor Cyan

    # Test 1: Get by Story ID
    Invoke-Test "GetAzDoHierarchyForStory by ID" {
        $result = & "$SRC_DIR/GetAzDoHierarchyForStory.ps1" -Organization $Organization -Project $Project -StoryId $story.id
        
        if ($null -eq $result) {
            throw "Result is null"
        }
        if ($result.Id -ne $story.id) {
            throw "Story ID mismatch"
        }
        if ([string]::IsNullOrWhiteSpace($result.Title)) {
            throw "Title is empty"
        }
        if ($result.Tasks.Count -ne 3) {
            throw "Expected 3 Tasks, got $($result.Tasks.Count)"
        }
    }

    # Test 2: Get by Story Title
    Invoke-Test "GetAzDoHierarchyForStory by Title" {
        $result = & "$SRC_DIR/GetAzDoHierarchyForStory.ps1" -Organization $Organization -Project $Project -StoryTitle $story.fields.'System.Title'
        
        if ($null -eq $result) {
            throw "Result is null"
        }
        if ($result.Id -ne $story.id) {
            throw "Story ID mismatch when searched by title"
        }
    }

    # Test 3: Verify Story has full details
    Invoke-Test "Story has full details" {
        $result = & "$SRC_DIR/GetAzDoHierarchyForStory.ps1" -Organization $Organization -Project $Project -Story Id $story.id
        
        if ($result.PSObject.Properties.Name -notcontains "Title") {
            throw "Story missing Title"
        }
        if ($result.PSObject.Properties.Name -notcontains "State") {
            throw "Story missing State"
        }
        if ($result.PSObject.Properties.Name -notcontains "Tags") {
            throw "Story missing Tags"
        }
        if ($result.PSObject.Properties.Name -contains "Comments") {
            throw "Story should not have Comments"
        }
        if ($result.PSObject.Properties.Name -notcontains "Tasks") {
            throw "Story missing Tasks property"
        }
    }

    # Test 4: Verify Tasks are included
    Invoke-Test "Tasks are included in output" {
        $result = & "$SRC_DIR/GetAzDoHierarchyForStory.ps1" -Organization $Organization -Project $Project -StoryId $story.id
        
        if ($result.Tasks.Count -lt 1) {
            throw "Story should have Tasks"
        }
        
        foreach ($task in $result.Tasks) {
            if ($task.PSObject.Properties.Name -notcontains "Title") {
                throw "Task missing Title"
            }
            if ($task.PSObject.Properties.Name -notcontains "State") {
                throw "Task missing State"
            }
            if ($task.PSObject.Properties.Name -notcontains "Tags") {
                throw "Task missing Tags"
            }
        }
    }

    # Test 5: Return null for non-existent Story
    Invoke-Test "Returns null for non-existent Story" {
        $result = & "$SRC_DIR/GetAzDoHierarchyForStory.ps1" -Organization $Organization -Project $Project -StoryId 999999
        
        if ($null -ne $result) {
            throw "Expected null for non-existent Story, got: $result"
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
