<#
.SYNOPSIS
Integration test for GetAzDoHierarchyForEpic functionality

.DESCRIPTION
Tests the GetAzDoHierarchyForEpic.ps1 script for retrieving Epic hierarchies
with Features and Stories.

Requires Environment variable set:
- GMD_AZDO_ORGANIZATION: Organization name
- GMD_AZDO_PROJECT: Project name
- GMD_AZDO_MACHINE_WORKITEMSRW: Encrypted PAT token

Run with: pwsh -File .\GetAzDoHierarchyForEpicTest.ps1

.NOTES
Creates temporary test Epic, Features, and Stories, then cleans them up.
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
    Write-Host "`n=== GetAzDoHierarchyForEpic Integration Tests ===" -ForegroundColor Cyan
    Write-Host "Organization: $Organization"
    Write-Host "Project: $Project"

    # Create test data
    Write-Host "`nCreating test hierarchy..." -ForegroundColor Cyan
    
    $epicTitle = "🏢 Hierarchy Test Epic $(Get-Random)"
    Write-Host "Creating test Epic: $epicTitle"
    $epic = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project -Title $epicTitle
    $script:createdItems += $epic.id
    Write-Host "Created Epic (ID: $($epic.id))" -ForegroundColor Green
    
    # Add epic description and effort
    & "$SRC_DIR/SetAzDoWorkItemDescription.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $epic.id -Description "Test Epic Description"
    & "$SRC_DIR/SetAzDoEffort.ps1" -Organization $Organization -Project $Project `
        -WorkItemId $epic.id -Effort 21

    # Create multiple features
    [array]$features = @()
    for ($i = 1; $i -le 2; $i++) {
        $featureTitle = "Test Feature $i $(Get-Random)"
        Write-Host "Creating Feature: $featureTitle"
        $feature = & "$SRC_DIR/UpsertAzDoFeature.ps1" -Organization $Organization -Project $Project `
            -Title $featureTitle -ParentEpicId $epic.id
        & "$SRC_DIR/SetAzDoWorkItemDescription.ps1" -Organization $Organization -Project $Project `
            -WorkItemId $feature.id -Description "Feature $i description"
        & "$SRC_DIR/SetAzDoEffort.ps1" -Organization $Organization -Project $Project `
            -WorkItemId $feature.id -Effort (8 * $i)
        $features += $feature
        Write-Host "Created Feature (ID: $($feature.id))" -ForegroundColor Green
    }

    # Create multiple stories under features
    Write-Host "`nCreating Stories under Features..."
    foreach ($feature in $features) {
        for ($i = 1; $i -le 2; $i++) {
            $storyTitle = "🧪 Story $i for Feature $($feature.id) $(Get-Random)"
            Write-Host "Creating Story under Feature $($feature.id): $storyTitle"
            $story = & "$SRC_DIR/UpsertAzDoStory.ps1" -Organization $Organization -Project $Project `
                -Title $storyTitle -ParentFeatureId $feature.id
            & "$SRC_DIR/SetAzDoWorkItemDescription.ps1" -Organization $Organization -Project $Project `
                -WorkItemId $story.id -Description "Story description"
            & "$SRC_DIR/SetAzDoStoryPoints.ps1" -Organization $Organization -Project $Project `
                -WorkItemId $story.id -StoryPoints (3 * $i)
            Write-Host "Created Story (ID: $($story.id))" -ForegroundColor Green
        }
    }

    # Run tests
    Write-Host "`n=== Running Tests ===" -ForegroundColor Cyan

    Invoke-Test "GetAzDoHierarchyForEpic retrieves hierarchy by ID" {
        $result = & "$SRC_DIR/GetAzDoHierarchyForEpic.ps1" -Organization $Organization -Project $Project `
            -EpicId $epic.id
        
        if ($null -eq $result) {
            throw "Result is null"
        }
        if ($result.Id -ne $epic.id) {
            throw "Epic ID mismatch"
        }
        if ([string]::IsNullOrWhiteSpace($result.Title)) {
            throw "Epic Title is empty"
        }
    }

    Invoke-Test "GetAzDoHierarchyForEpic retrieves hierarchy by title" {
        $result = & "$SRC_DIR/GetAzDoHierarchyForEpic.ps1" -Organization $Organization -Project $Project `
            -EpicTitle $epicTitle
        
        if ($null -eq $result) {
            throw "Result is null"
        }
        if ($result.Title -ne $epicTitle) {
            throw "Epic Title mismatch"
        }
    }

    Invoke-Test "GetAzDoHierarchyForEpic includes epic description and effort" {
        $result = & "$SRC_DIR/GetAzDoHierarchyForEpic.ps1" -Organization $Organization -Project $Project `
            -EpicId $epic.id
        
        if ([string]::IsNullOrWhiteSpace($result.Description)) {
            throw "Epic Description is empty"
        }
        if ($result.Effort -ne 21) {
            throw "Epic Effort mismatch: expected 21, got $($result.Effort)"
        }
    }

    Invoke-Test "GetAzDoHierarchyForEpic includes features" {
        $result = & "$SRC_DIR/GetAzDoHierarchyForEpic.ps1" -Organization $Organization -Project $Project `
            -EpicId $epic.id
        
        if ($null -eq $result.Features) {
            throw "Features array is null"
        }
        if (@($result.Features).Count -ne 2) {
            throw "Expected 2 features, got $(@($result.Features).Count)"
        }
    }

    Invoke-Test "GetAzDoHierarchyForEpic includes feature descriptions and effort" {
        $result = & "$SRC_DIR/GetAzDoHierarchyForEpic.ps1" -Organization $Organization -Project $Project `
            -EpicId $epic.id
        
        foreach ($feature in $result.Features) {
            if ([string]::IsNullOrWhiteSpace($feature.Description)) {
                throw "Feature Description is empty"
            }
            if ($feature.Effort -eq $null) {
                throw "Feature Effort is null"
            }
        }
    }

    Invoke-Test "GetAzDoHierarchyForEpic includes stories under features" {
        $result = & "$SRC_DIR/GetAzDoHierarchyForEpic.ps1" -Organization $Organization -Project $Project `
            -EpicId $epic.id
        
        $totalStories = 0
        foreach ($feature in $result.Features) {
            if ($null -eq $feature.Stories) {
                throw "Stories array is null for feature"
            }
            $totalStories += @($feature.Stories).Count
        }
        
        if ($totalStories -ne 4) {
            throw "Expected 4 total stories, got $totalStories"
        }
    }

    Invoke-Test "GetAzDoHierarchyForEpic includes full story details" {
        $result = & "$SRC_DIR/GetAzDoHierarchyForEpic.ps1" -Organization $Organization -Project $Project `
            -EpicId $epic.id
        
        foreach ($feature in $result.Features) {
            foreach ($story in $feature.Stories) {
                if ($story.PSObject.Properties.Name -notcontains "Id") {
                    throw "Story missing Id property"
                }
                if ($story.PSObject.Properties.Name -notcontains "Title") {
                    throw "Story missing Title property"
                }
                if ($story.PSObject.Properties.Name -notcontains "State") {
                    throw "Story missing State property"
                }
                if ($story.PSObject.Properties.Name -notcontains "StoryPoints") {
                    throw "Story missing StoryPoints property"
                }
                if ($story.PSObject.Properties.Name -notcontains "Comments") {
                    throw "Story missing Comments property"
                }
            }
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
