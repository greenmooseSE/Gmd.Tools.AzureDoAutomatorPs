<#
.SYNOPSIS
Integration test for GetAzDoUserStory functionality

.DESCRIPTION
Tests the GetAzDoUserStory.ps1 script for retrieving User Stories
with both full and subset modes.

Requires Environment variable set:
- GMD_AZDO_ORGANIZATION: Organization name
- GMD_AZDO_PROJECT: Project name
- GMD_AZDO_MACHINE_WORKITEMSRW: Encrypted PAT token

Run with: pwsh -File .\GetAzDoUserStoryTest.ps1

.NOTES
Creates temporary test Epic, Feature, and Story, then cleans them up.
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
    Write-Host "`n=== GetAzDoUserStory Integration Tests ===" -ForegroundColor Cyan
    Write-Host "Organization: $Organization"
    Write-Host "Project: $Project"

    # Create test data
    Write-Host "`nCreating test data..." -ForegroundColor Cyan
    
    $epicTitle = "GetAzDoUserStory Test Epic $(Get-Random)"
    Write-Host "Creating test Epic: $epicTitle"
    $epic = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project -Title $epicTitle
    $script:createdItems += $epic.id
    Write-Host "Created Epic (ID: $($epic.id))" -ForegroundColor Green

    $featureTitle = "GetAzDoUserStory Test Feature $(Get-Random)"
    Write-Host "Creating test Feature: $featureTitle"
    $feature = & "$SRC_DIR/UpsertAzDoFeature.ps1" -Organization $Organization -Project $Project -Title $featureTitle -ParentEpicId $epic.id
    Write-Host "Created Feature (ID: $($feature.id))" -ForegroundColor Green

    $storyTitle = "🧪 GetAzDoUserStory Test Story $(Get-Random)"
    Write-Host "Creating test Story: $storyTitle"
    $story = & "$SRC_DIR/NewAzDoStory.ps1" -Organization $Organization -Project $Project -Title $storyTitle -ParentFeatureId $feature.id
    Write-Host "Created Story (ID: $($story.id))" -ForegroundColor Green

    # Update the story with additional properties
    Write-Host "Adding story properties..."
    & "$SRC_DIR/SetAzDoWorkItemDescription.ps1" -Organization $Organization -Project $Project -WorkItemId $story.id -Description "Test description for story"
    & "$SRC_DIR/SetAzDoAcceptanceCriteria.ps1" -Organization $Organization -Project $Project -WorkItemId $story.id -AcceptanceCriteria "Test AC1`nTest AC2"
    & "$SRC_DIR/SetAzDoStoryPoints.ps1" -Organization $Organization -Project $Project -WorkItemId $story.id -StoryPoints 5
    & "$SRC_DIR/SetAzDoWorkItemTags.ps1" -Organization $Organization -Project $Project -WorkItemId $story.id -Tags "test; integration"

    # Run tests
    Write-Host "`n=== Running Tests ===" -ForegroundColor Cyan

    Invoke-Test "GetAzDoUserStory with subset (default)" {
        $result = & "$SRC_DIR/GetAzDoUserStory.ps1" -Organization $Organization -Project $Project -WorkItemId $story.id
        
        if ($null -eq $result) {
            throw "Result is null"
        }
        
        # Check required fields
        if ($result.Id -ne $story.id) {
            throw "Id mismatch: expected $($story.id), got $($result.Id)"
        }
        if ([string]::IsNullOrWhiteSpace($result.Title)) {
            throw "Title is empty"
        }
        if ([string]::IsNullOrWhiteSpace($result.State)) {
            throw "State is empty"
        }
        if ($result.PSObject.Properties.Name -notcontains "Comments") {
            throw "Comments property missing"
        }
    }

    Invoke-Test "GetAzDoUserStory with -Full switch" {
        $result = & "$SRC_DIR/GetAzDoUserStory.ps1" -Organization $Organization -Project $Project -WorkItemId $story.id -Full
        
        if ($null -eq $result) {
            throw "Result is null"
        }
        
        # Check that full result has all standard work item properties
        if ($result.PSObject.Properties.Name -notcontains "id") {
            throw "id property missing from full result"
        }
        if ($result.PSObject.Properties.Name -notcontains "fields") {
            throw "fields property missing from full result"
        }
    }

    Invoke-Test "GetAzDoUserStory returns correct story points" {
        $result = & "$SRC_DIR/GetAzDoUserStory.ps1" -Organization $Organization -Project $Project -WorkItemId $story.id
        
        if ($result.StoryPoints -ne 5) {
            throw "StoryPoints mismatch: expected 5, got $($result.StoryPoints)"
        }
    }

    Invoke-Test "GetAzDoUserStory returns description" {
        $result = & "$SRC_DIR/GetAzDoUserStory.ps1" -Organization $Organization -Project $Project -WorkItemId $story.id
        
        if ([string]::IsNullOrWhiteSpace($result.Description)) {
            throw "Description is empty"
        }
    }

    Invoke-Test "GetAzDoUserStory returns acceptance criteria" {
        $result = & "$SRC_DIR/GetAzDoUserStory.ps1" -Organization $Organization -Project $Project -WorkItemId $story.id
        
        if ([string]::IsNullOrWhiteSpace($result.AcceptanceCriteria)) {
            throw "AcceptanceCriteria is empty"
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
