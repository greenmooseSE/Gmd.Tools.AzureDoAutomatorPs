<#
.SYNOPSIS
Tests for Story 1588: Ensure tags retrieval consistency across all work item types

.DESCRIPTION
Verifies that tags retrieval is applied consistently to all work item types 
(Epic, Feature, Story, Task) in the Azure DevOps automation scripts.

AC Scenarios tested:
- AC SCENARIO 1: Tags are retrieved for all hierarchy levels (Epic, Features, Stories)
- AC SCENARIO 2: Tags can be set and retrieved for Tasks
- AC SCENARIO 3: GetAzDoUserStory includes tags in returned object
- AC SCENARIO 4: All work items in hierarchy have consistent tag access

Requires Environment variables set:
- GMD_AZDO_ORGANIZATION: Organization name
- GMD_AZDO_PROJECT: Project name
- GMD_AZDO_MACHINE_WORKITEMSRW: Encrypted PAT token

Run with: pwsh -File .\1588EnsureTagRetrievalConsistencyTest.ps1

.NOTES
Creates temporary test work items with tags, then cleans them up.
All created test work items are tagged with 'testWi' for easy cleanup.
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
    Write-Error "Organization not provided. Set GMD_AZDO_ORGANIZATION environment variable or pass -Organization parameter."
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    Write-Error "Project not provided. Set GMD_AZDO_PROJECT environment variable or pass -Project parameter."
}

# Test configuration - tag to mark test items
$testTag = 'testWi'

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
            Write-Host "Cleaned up test Epic and all child work items (ID: $epicId)" -ForegroundColor Green
        }
        catch {
            Write-Host "Warning: Cleanup failed: $_" -ForegroundColor Yellow
        }
    }
}

# Register cleanup on exit
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Cleanup }

try {
    Write-Host "`n=== Story 1588: Tags Retrieval Consistency Tests ===" -ForegroundColor Cyan
    Write-Host "Organization: $Organization"
    Write-Host "Project: $Project"
    Write-Host "Test tag: $testTag"

    # Create test hierarchy with tags
    Write-Host "`nCreating test hierarchy with tags..." -ForegroundColor Cyan
    
    $epicTitle = "🏷️  Tags Test Epic $(Get-Random)"
    Write-Host "Creating test Epic: $epicTitle"
    $epic = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project -Title $epicTitle
    $script:createdItems += $epic.id
    
    # Add tags to Epic
    & "$SRC_DIR/SetAzDoWorkItemTags.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $epic.id -Tags "testTag1;$testTag"
    Write-Host "Created Epic with tags (ID: $($epic.id))" -ForegroundColor Green

    # Create Feature
    $featureTitle = "Test Feature for Tags $(Get-Random)"
    Write-Host "Creating Feature: $featureTitle"
    $feature = & "$SRC_DIR/UpsertAzDoFeature.ps1" -Organization $Organization -Project $Project `
        -Title $featureTitle -ParentEpicId $epic.id
    
    # Add tags to Feature
    & "$SRC_DIR/SetAzDoWorkItemTags.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $feature.id -Tags "featureTag;$testTag"
    Write-Host "Created Feature with tags (ID: $($feature.id))" -ForegroundColor Green

    # Create Story
    $storyTitle = "🧪 Story with Tags $(Get-Random)"
    Write-Host "Creating Story: $storyTitle"
    $story = & "$SRC_DIR/UpsertAzDoStory.ps1" -Organization $Organization -Project $Project `
        -Title $storyTitle -ParentFeatureId $feature.id
    
    # Add tags to Story
    & "$SRC_DIR/SetAzDoWorkItemTags.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $story.id -Tags "storyTag;$testTag"
    Write-Host "Created Story with tags (ID: $($story.id))" -ForegroundColor Green

    # Create Task
    $taskTitle = "Test Task with Tags $(Get-Random)"
    Write-Host "Creating Task: $taskTitle"
    $task = & "$SRC_DIR/UpsertAzDoTask.ps1" -Organization $Organization -Project $Project `
        -Title $taskTitle -ParentStoryId $story.id
    
    # Add tags to Task
    & "$SRC_DIR/SetAzDoWorkItemTags.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $task.id -Tags "taskTag;$testTag"
    Write-Host "Created Task with tags (ID: $($task.id))" -ForegroundColor Green

    # Run tests
    Write-Host "`n=== Running Tests ===" -ForegroundColor Cyan

    # AC SCENARIO 1: Tags are retrieved for all hierarchy levels (Epic, Features, Stories)
    Invoke-Test "AC SCENARIO 1: GetAzDoHierarchyForEpic includes Tags for Epic" {
        $result = & "$SRC_DIR/GetAzDoHierarchyForEpic.ps1" -Organization $Organization -Project $Project `
            -EpicId $epic.id
        
        if ($result.PSObject.Properties.Name -notcontains "Tags") {
            throw "Epic missing Tags property in hierarchy"
        }
        
        if ([string]::IsNullOrWhiteSpace($result.Tags)) {
            throw "Epic Tags are empty in hierarchy"
        }
        
        if ($result.Tags -notlike "*testTag1*") {
            throw "Epic Tags do not contain expected tag 'testTag1', got: $($result.Tags)"
        }
    }

    Invoke-Test "AC SCENARIO 1: GetAzDoHierarchyForEpic includes Tags for Features" {
        $result = & "$SRC_DIR/GetAzDoHierarchyForEpic.ps1" -Organization $Organization -Project $Project `
            -EpicId $epic.id
        
        if ($null -eq $result.Features -or @($result.Features).Count -eq 0) {
            throw "No Features in hierarchy"
        }
        
        foreach ($featureInHierarchy in $result.Features) {
            if ($featureInHierarchy.PSObject.Properties.Name -notcontains "Tags") {
                throw "Feature missing Tags property in hierarchy"
            }
            
            if ([string]::IsNullOrWhiteSpace($featureInHierarchy.Tags)) {
                throw "Feature Tags are empty in hierarchy"
            }
            
            if ($featureInHierarchy.Tags -notlike "*featureTag*") {
                throw "Feature Tags do not contain expected tag 'featureTag', got: $($featureInHierarchy.Tags)"
            }
        }
    }

    Invoke-Test "AC SCENARIO 1: GetAzDoHierarchyForEpic includes Tags for Stories" {
        $result = & "$SRC_DIR/GetAzDoHierarchyForEpic.ps1" -Organization $Organization -Project $Project `
            -EpicId $epic.id
        
        if ($null -eq $result.Features -or @($result.Features).Count -eq 0) {
            throw "No Features in hierarchy"
        }
        
        $storiesFound = 0
        foreach ($featureInHierarchy in $result.Features) {
            if ($null -ne $featureInHierarchy.Stories -and @($featureInHierarchy.Stories).Count -gt 0) {
                foreach ($storyInHierarchy in $featureInHierarchy.Stories) {
                    $storiesFound++
                    if ($storyInHierarchy.PSObject.Properties.Name -notcontains "Tags") {
                        throw "Story missing Tags property in hierarchy"
                    }
                    
                    if ([string]::IsNullOrWhiteSpace($storyInHierarchy.Tags)) {
                        throw "Story Tags are empty in hierarchy"
                    }
                    
                    if ($storyInHierarchy.Tags -notlike "*storyTag*") {
                        throw "Story Tags do not contain expected tag 'storyTag', got: $($storyInHierarchy.Tags)"
                    }
                }
            }
        }
        
        if ($storiesFound -eq 0) {
            throw "No Stories found in hierarchy"
        }
    }

    # AC SCENARIO 2: Tags can be set and retrieved for Tasks
    Invoke-Test "AC SCENARIO 2: GetAzDoWorkItem includes Tags for Task" {
        $result = & "$SRC_DIR/GetAzDoWorkItem.ps1" -Organization $Organization -Project $Project `
            -WorkItemId $task.id
        
        if ($result.PSObject.Properties.Name -notcontains "fields") {
            throw "Work item missing fields property"
        }
        
        if ($result.fields.PSObject.Properties.Name -notcontains "System.Tags") {
            throw "Task work item missing System.Tags field"
        }
        
        if ([string]::IsNullOrWhiteSpace($result.fields.'System.Tags')) {
            throw "Task Tags are empty"
        }
    }

    # AC SCENARIO 3: GetAzDoUserStory includes tags in returned object
    Invoke-Test "AC SCENARIO 3: GetAzDoUserStory includes Tags property" {
        $result = & "$SRC_DIR/GetAzDoUserStory.ps1" -Organization $Organization -Project $Project `
            -WorkItemId $story.id
        
        if ($result.PSObject.Properties.Name -notcontains "Tags") {
            throw "Story subset object missing Tags property"
        }
        
        if ([string]::IsNullOrWhiteSpace($result.Tags)) {
            throw "Story Tags are empty in subset object"
        }
        
        if ($result.Tags -notlike "*storyTag*") {
            throw "Story Tags do not contain expected tag 'storyTag' in subset, got: $($result.Tags)"
        }
    }

    # AC SCENARIO 4: All work items consistently have tags property
    Invoke-Test "AC SCENARIO 4: All work item types use System.Tags field" {
        # Test Epic
        $epicWi = & "$SRC_DIR/GetAzDoWorkItem.ps1" -Organization $Organization -Project $Project -WorkItemId $epic.id
        if ($epicWi.fields.'System.Tags' -notlike "*testTag1*") {
            throw "Epic does not have System.Tags set correctly"
        }
        
        # Test Feature
        $featureWi = & "$SRC_DIR/GetAzDoWorkItem.ps1" -Organization $Organization -Project $Project -WorkItemId $feature.id
        if ($featureWi.fields.'System.Tags' -notlike "*featureTag*") {
            throw "Feature does not have System.Tags set correctly"
        }
        
        # Test Story
        $storyWi = & "$SRC_DIR/GetAzDoWorkItem.ps1" -Organization $Organization -Project $Project -WorkItemId $story.id
        if ($storyWi.fields.'System.Tags' -notlike "*storyTag*") {
            throw "Story does not have System.Tags set correctly"
        }
        
        # Test Task
        $taskWi = & "$SRC_DIR/GetAzDoWorkItem.ps1" -Organization $Organization -Project $Project -WorkItemId $task.id
        if ($taskWi.fields.'System.Tags' -notlike "*taskTag*") {
            throw "Task does not have System.Tags set correctly"
        }
    }

    # Output summary
    Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
    Write-Host "Tests Run: $testsRun"
    Write-Host "Passed: $testsPassed" -ForegroundColor Green
    Write-Host "Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })

    if ($testsFailed -gt 0) {
        exit 1
    }
}
finally {
    Cleanup
}
