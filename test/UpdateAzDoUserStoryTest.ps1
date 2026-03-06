<#
.SYNOPSIS
Integration test for UpdateAzDoUserStory functionality

.DESCRIPTION
Tests the UpdateAzDoUserStory.ps1 script for updating User Story properties
via PATCH operations.

Requires Environment variable set:
- GMD_AZDO_ORGANIZATION: Organization name
- GMD_AZDO_PROJECT: Project name
- GMD_AZDO_MACHINE_WORKITEMSRW: Encrypted PAT token

Run with: pwsh -File .\UpdateAzDoUserStoryTest.ps1

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
    Write-Host "`n=== UpdateAzDoUserStory Integration Tests ===" -ForegroundColor Cyan
    Write-Host "Organization: $Organization"
    Write-Host "Project: $Project"

    # Create test data
    Write-Host "`nCreating test data..." -ForegroundColor Cyan
    
    $epicTitle = "UpdateAzDoUserStory Test Epic $(Get-Random)"
    Write-Host "Creating test Epic: $epicTitle"
    $epic = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project -Title $epicTitle
    $script:createdItems += $epic.id
    Write-Host "Created Epic (ID: $($epic.id))" -ForegroundColor Green

    $featureTitle = "UpdateAzDoUserStory Test Feature $(Get-Random)"
    Write-Host "Creating test Feature: $featureTitle"
    $feature = & "$SRC_DIR/NewAzDoFeature.ps1" -Organization $Organization -Project $Project -Title $featureTitle -ParentEpicId $epic.id
    Write-Host "Created Feature (ID: $($feature.id))" -ForegroundColor Green

    $storyTitle = "🧪 UpdateAzDoUserStory Test Story $(Get-Random)"
    Write-Host "Creating test Story: $storyTitle"
    $story = & "$SRC_DIR/NewAzDoStory.ps1" -Organization $Organization -Project $Project -Title $storyTitle -ParentFeatureId $feature.id
    Write-Host "Created Story (ID: $($story.id))" -ForegroundColor Green

    # Run tests
    Write-Host "`n=== Running Tests ===" -ForegroundColor Cyan

    Invoke-Test "UpdateAzDoUserStory updates title" {
        $newTitle = "Updated Title $(Get-Random)"
        $result = & "$SRC_DIR/UpdateAzDoUserStory.ps1" -Organization $Organization -Project $Project `
            -WorkItemId $story.id -Title $newTitle
        
        if ($result.fields.'System.Title' -ne $newTitle) {
            throw "Title not updated: expected '$newTitle', got '$($result.fields.'System.Title')'"
        }
    }

    Invoke-Test "UpdateAzDoUserStory updates description" {
        $newDescription = "Updated description $(Get-Random)"
        $result = & "$SRC_DIR/UpdateAzDoUserStory.ps1" -Organization $Organization -Project $Project `
            -WorkItemId $story.id -Description $newDescription
        
        if ($result.fields.'System.Description' -ne $newDescription) {
            throw "Description not updated"
        }
    }

    Invoke-Test "UpdateAzDoUserStory updates story points" {
        $result = & "$SRC_DIR/UpdateAzDoUserStory.ps1" -Organization $Organization -Project $Project `
            -WorkItemId $story.id -StoryPoints 8
        
        if ($result.fields.'Microsoft.VSTS.Scheduling.StoryPoints' -ne 8) {
            throw "StoryPoints not updated: expected 8, got $($result.fields.'Microsoft.VSTS.Scheduling.StoryPoints')"
        }
    }

    Invoke-Test "UpdateAzDoUserStory updates acceptance criteria" {
        $newAC = "New AC1`nNew AC2`nNew AC3"
        $result = & "$SRC_DIR/UpdateAzDoUserStory.ps1" -Organization $Organization -Project $Project `
            -WorkItemId $story.id -AcceptanceCriteria $newAC
        
        if ($result.fields.'Microsoft.VSTS.Common.AcceptanceCriteria' -ne $newAC) {
            throw "AcceptanceCriteria not updated"
        }
    }

    Invoke-Test "UpdateAzDoUserStory updates tags" {
        $newTags = "updated; tag; list"
        $result = & "$SRC_DIR/UpdateAzDoUserStory.ps1" -Organization $Organization -Project $Project `
            -WorkItemId $story.id -Tags $newTags
        
        if ($result.fields.'System.Tags' -ne $newTags) {
            throw "Tags not updated: expected '$newTags', got '$($result.fields.'System.Tags')'"
        }
    }

    Invoke-Test "UpdateAzDoUserStory updates multiple fields at once" {
        $newTitle = "Multi-update Title $(Get-Random)"
        $newPoints = 13
        $result = & "$SRC_DIR/UpdateAzDoUserStory.ps1" -Organization $Organization -Project $Project `
            -WorkItemId $story.id -Title $newTitle -StoryPoints $newPoints -Tags "multi; update"
        
        if ($result.fields.'System.Title' -ne $newTitle) {
            throw "Title not updated in multi-update"
        }
        if ($result.fields.'Microsoft.VSTS.Scheduling.StoryPoints' -ne $newPoints) {
            throw "StoryPoints not updated in multi-update"
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
