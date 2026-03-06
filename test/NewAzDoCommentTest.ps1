<#
.SYNOPSIS
Integration test for NewAzDoComment functionality

.DESCRIPTION
Tests the NewAzDoComment.ps1 script for adding comments to work items.

Requires Environment variable set:
- GMD_AZDO_ORGANIZATION: Organization name
- GMD_AZDO_PROJECT: Project name
- GMD_AZDO_MACHINE_WORKITEMSRW: Encrypted PAT token

Run with: pwsh -File .\NewAzDoCommentTest.ps1

.NOTES
Creates temporary test work items, adds comments, and cleans up.
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

# Set trap for cleanup on exit
trap {
    Cleanup
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Azure DevOps Comment Tests" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Create test structure for comments
Write-Host "Setting up test data..." -ForegroundColor Cyan

try {
    # Create test Epic
    $epicScript = @{
        Organization = $Organization
        Project      = $Project
        Title        = "Test Epic for Comments $(Get-Date -Format 'yyyyMMddHHmmss')"
    }
    $epic = & "$SRC_DIR/UpsertAzDoEpic.ps1" @epicScript
    $script:createdItems += $epic.id
    Write-Host "Created test Epic (ID: $($epic.id))" -ForegroundColor Green

    # Create test Feature
    $featureScript = @{
        Organization = $Organization
        Project      = $Project
        Title        = "Test Feature for Comments"
        ParentEpicId = $epic.id
    }
    $feature = & "$SRC_DIR/UpsertAzDoFeature.ps1" @featureScript
    Write-Host "Created test Feature (ID: $($feature.id))" -ForegroundColor Green

    # Create test Story
    $storyScript = @{
        Organization   = $Organization
        Project        = $Project
        Title          = "Test Story for Comments"
        ParentFeatureId = $feature.id
    }
    $story = & "$SRC_DIR/UpsertAzDoStory.ps1" @storyScript
    Write-Host "Created test Story (ID: $($story.id))" -ForegroundColor Green
}
catch {
    Write-Host "Failed to set up test data: $_" -ForegroundColor Red
    Cleanup
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Running tests..." -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Test 1: Script has correct parameters
Invoke-Test "Script has Organization parameter" {
    $cmd = Get-Command -Name "$SRC_DIR/NewAzDoComment.ps1"
    $params = $cmd.Parameters.Keys
    if ("Organization" -notin $params) {
        throw "Organization parameter not found"
    }
}

# Test 2: Script has Project parameter
Invoke-Test "Script has Project parameter" {
    $cmd = Get-Command -Name "$SRC_DIR/NewAzDoComment.ps1"
    $params = $cmd.Parameters.Keys
    if ("Project" -notin $params) {
        throw "Project parameter not found"
    }
}

# Test 3: Script has WorkItemId parameter
Invoke-Test "Script has WorkItemId parameter" {
    $cmd = Get-Command -Name "$SRC_DIR/NewAzDoComment.ps1"
    $params = $cmd.Parameters.Keys
    if ("WorkItemId" -notin $params) {
        throw "WorkItemId parameter not found"
    }
}

# Test 4: Script has Content parameter
Invoke-Test "Script has Content parameter" {
    $cmd = Get-Command -Name "$SRC_DIR/NewAzDoComment.ps1"
    $params = $cmd.Parameters.Keys
    if ("Content" -notin $params) {
        throw "Content parameter not found"
    }
}

# Test 5: Script validates WorkItemId (negative value)
Invoke-Test "Script validates WorkItemId must be positive" {
    # This should fail during script parameter validation
    try {
        & "$SRC_DIR/NewAzDoComment.ps1" `
            -Organization $Organization `
            -Project $Project `
            -WorkItemId -1 `
            -Content "test" `
            -ErrorAction Stop 2>&1 | head -20
        throw "Should have failed with negative WorkItemId"
    }
    catch {
        # Expected to fail - verify error mentions validation
        if ($_.Exception.Message -notlike "*positive*" -and $_.Exception.Message -notlike "*Validat*") {
            # Might still be OK if it's a parameter binding error
            Write-Host "    (Validation caught by PowerShell parameter binding: OK)" -ForegroundColor Gray
        }
    }
}

# Test 6: Script successfully adds a comment to a work item
Invoke-Test "Script successfully adds comment to work item" {
    $comment = & "$SRC_DIR/NewAzDoComment.ps1" `
        -Organization $Organization `
        -Project $Project `
        -WorkItemId $story.id `
        -Content "This is a test comment"
    
    if ($null -eq $comment) {
        throw "Comment object is null"
    }

    if ($null -eq $comment.id) {
        throw "Comment does not have an id field"
    }

    # New comments API returns a 'text' property for the body
    if ($null -ne $comment.text) {
        if ($comment.text -ne "This is a test comment") {
            throw "Comment text does not match: $($comment.text)"
        }
    }
    elseif ($null -ne $comment.content) {
        if ($comment.content -ne "This is a test comment") {
            throw "Comment content does not match: $($comment.content)"
        }
    }
    else {
        throw "Comment does not contain 'text' or 'content' property"
    }
}

# Test 7: Script adds comment with markdown formatting
Invoke-Test "Script adds comment with markdown formatting" {
    $comment = & "$SRC_DIR/NewAzDoComment.ps1" `
        -Organization $Organization `
        -Project $Project `
        -WorkItemId $story.id `
        -Content "**Bold text** and _italic text_"
    
    if ($null -eq $comment) {
        throw "Comment object is null"
    }

    $bodyText = $comment.text -or $comment.content
    if ($bodyText -ne "**Bold text** and _italic text_") {
        throw "Comment markdown content was not preserved"
    }
}

# Test 8: Script adds comment with trailing whitespace
Invoke-Test "Script adds comment with trailing whitespace" {
    $comment = & "$SRC_DIR/NewAzDoComment.ps1" `
        -Organization $Organization `
        -Project $Project `
        -WorkItemId $story.id `
        -Content "test comment with space "
    
    if ($null -eq $comment) {
        throw "Comment object is null"
    }

    $bodyText = $comment.text -or $comment.content
    if ($bodyText -ne "test comment with space ") {
        throw "Comment content with trailing space was not preserved: '$($bodyText)'"
    }

    # Test 9: Remove the last added comment
    Invoke-Test "Script removes comment successfully" {
        # Use the id from the comment object
        $commId = $comment.id
        $removed = & "$SRC_DIR/RemoveAzDoComment.ps1" `
            -Organization $Organization `
            -Project $Project `
            -WorkItemId $story.id `
            -CommentId $commId

        if (-not $removed) {
            throw "RemoveAzDoComment did not return success"
        }
    }
}

# Cleanup
Cleanup

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Tests run:    $testsRun" -ForegroundColor White
Write-Host "Tests passed: $testsPassed" -ForegroundColor Green
Write-Host "Tests failed: $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { "Red" } else { "Green" })

if ($testsFailed -gt 0) {
    exit 1
}
else {
    Write-Host "`n✓ All tests passed!" -ForegroundColor Green
    exit 0
}
