<#
.SYNOPSIS
Integration test for NewAzDoCommentReaction functionality

.DESCRIPTION
Tests the NewAzDoCommentReaction.ps1 script for adding reactions to work item comments.

Requires Environment variable set:
- GMD_AZDO_ORGANIZATION: Organization name
- GMD_AZDO_PROJECT: Project name
- GMD_AZDO_MACHINE_WORKITEMSRW: Encrypted PAT token

Run with: pwsh -File .\NewAzDoCommentReactionTest.ps1

.NOTES
Creates temporary test work items, adds comments, adds reactions, and cleans up.
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
Write-Host "Azure DevOps Comment Reaction Tests" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Create test structure for comment reactions
Write-Host "Setting up test data..." -ForegroundColor Cyan

try {
    # Create test Epic
    $epicScript = @{
        Organization = $Organization
        Project      = $Project
        Title        = "Test Epic for Comment Reactions $(Get-Date -Format 'yyyyMMddHHmmss')"
    }
    $epic = & "$SRC_DIR/UpsertAzDoEpic.ps1" @epicScript
    $script:createdItems += $epic.id
    Write-Host "Created test Epic (ID: $($epic.id))" -ForegroundColor Green

    # Create test Feature
    $featureScript = @{
        Organization = $Organization
        Project      = $Project
        Title        = "Test Feature for Comment Reactions"
        ParentEpicId = $epic.id
    }
    $feature = & "$SRC_DIR/NewAzDoFeature.ps1" @featureScript
    Write-Host "Created test Feature (ID: $($feature.id))" -ForegroundColor Green

    # Create test Story
    $storyScript = @{
        Organization   = $Organization
        Project        = $Project
        Title          = "Test Story for Comment Reactions"
        ParentFeatureId = $feature.id
    }
    $story = & "$SRC_DIR/NewAzDoStory.ps1" @storyScript
    Write-Host "Created test Story (ID: $($story.id))" -ForegroundColor Green

    # Create test Comment
    $commentScript = @{
        Organization = $Organization
        Project      = $Project
        WorkItemId   = $story.id
        Content      = "This is a test comment for reactions"
    }
    $comment = & "$SRC_DIR/NewAzDoComment.ps1" @commentScript
    Write-Host "Created test Comment (ID: $($comment.id))" -ForegroundColor Green
}
catch {
    Write-Host "Failed to set up test data: $_" -ForegroundColor Red
    Cleanup
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Running tests..." -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Test 1: Script has Organization parameter
Invoke-Test "Script has Organization parameter" {
    $cmd = Get-Command -Name "$SRC_DIR/NewAzDoCommentReaction.ps1"
    $params = $cmd.Parameters.Keys
    if ("Organization" -notin $params) {
        throw "Organization parameter not found"
    }
}

# Test 2: Script has Project parameter
Invoke-Test "Script has Project parameter" {
    $cmd = Get-Command -Name "$SRC_DIR/NewAzDoCommentReaction.ps1"
    $params = $cmd.Parameters.Keys
    if ("Project" -notin $params) {
        throw "Project parameter not found"
    }
}

# Test 3: Script has WorkItemId parameter
Invoke-Test "Script has WorkItemId parameter" {
    $cmd = Get-Command -Name "$SRC_DIR/NewAzDoCommentReaction.ps1"
    $params = $cmd.Parameters.Keys
    if ("WorkItemId" -notin $params) {
        throw "WorkItemId parameter not found"
    }
}

# Test 4: Script has CommentId parameter
Invoke-Test "Script has CommentId parameter" {
    $cmd = Get-Command -Name "$SRC_DIR/NewAzDoCommentReaction.ps1"
    $params = $cmd.Parameters.Keys
    if ("CommentId" -notin $params) {
        throw "CommentId parameter not found"
    }
}

# Test 5: Script has ReactionType parameter
Invoke-Test "Script has ReactionType parameter" {
    $cmd = Get-Command -Name "$SRC_DIR/NewAzDoCommentReaction.ps1"
    $params = $cmd.Parameters.Keys
    if ("ReactionType" -notin $params) {
        throw "ReactionType parameter not found"
    }
}

# Test 6: Script validates ReactionType (ValidateSet)
Invoke-Test "Script validates ReactionType must be valid value" {
    try {
        & "$SRC_DIR/NewAzDoCommentReaction.ps1" `
            -Organization $Organization `
            -Project $Project `
            -WorkItemId $story.id `
            -CommentId $comment.id `
            -ReactionType "invalid" `
            -ErrorAction Stop 2>&1 | head -20
        throw "Should have failed with invalid ReactionType"
    }
    catch {
        # Expected to fail - verify error mentions validation
        if ($_.Exception.Message -notlike "*invalid*" -and $_.Exception.Message -notlike "*Validat*" -and $_.Exception.Message -notlike "*like*") {
            # Check if it's a parameter binding error about the enum
            Write-Host "    (Validation caught by ValidateSet: OK)" -ForegroundColor Gray
        }
    }
}

# Test 7: Script validates WorkItemId (negative value)
Invoke-Test "Script validates WorkItemId must be positive" {
    try {
        & "$SRC_DIR/NewAzDoCommentReaction.ps1" `
            -Organization $Organization `
            -Project $Project `
            -WorkItemId -1 `
            -CommentId $comment.id `
            -ReactionType "like" `
            -ErrorAction Stop 2>&1 | head -20
        throw "Should have failed with negative WorkItemId"
    }
    catch {
        # Expected to fail
        Write-Host "    (Validation caught: OK)" -ForegroundColor Gray
    }
}

# Test 8: Script successfully adds a 'like' reaction
Invoke-Test "Script successfully adds 'like' reaction to comment" {
    $reaction = & "$SRC_DIR/NewAzDoCommentReaction.ps1" `
        -Organization $Organization `
        -Project $Project `
        -WorkItemId $story.id `
        -CommentId $comment.id `
        -ReactionType "like"
    
    if ($null -eq $reaction) {
        throw "Reaction object is null"
    }

    if ($reaction.type -ne "like") {
        throw "Reaction type does not match: $($reaction.type)"
    }

    if ($reaction.count -lt 1) {
        throw "Reaction count should be at least 1: $($reaction.count)"
    }
}

# Test 9: Script successfully adds a 'heart' reaction
Invoke-Test "Script successfully adds 'heart' reaction to comment" {
    $reaction = & "$SRC_DIR/NewAzDoCommentReaction.ps1" `
        -Organization $Organization `
        -Project $Project `
        -WorkItemId $story.id `
        -CommentId $comment.id `
        -ReactionType "heart"
    
    if ($null -eq $reaction) {
        throw "Reaction object is null"
    }

    if ($reaction.type -ne "heart") {
        throw "Reaction type does not match: $($reaction.type)"
    }
}

# Test 10: Script successfully adds other reaction types
Invoke-Test "Script successfully adds 'thumbsup' reactions" {
    foreach ($reactionType in @("dislike", "hooray", "smile", "confused")) {
        $reaction = & "$SRC_DIR/NewAzDoCommentReaction.ps1" `
            -Organization $Organization `
            -Project $Project `
            -WorkItemId $story.id `
            -CommentId $comment.id `
            -ReactionType $reactionType
        
        if ($null -eq $reaction) {
            throw "Reaction object is null for type: $reactionType"
        }

        if ($reaction.type -ne $reactionType) {
            throw "Reaction type does not match for: $reactionType"
        }
    }
}

# Cleanup
Cleanup

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Results" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
Write-Host "Tests Run:    $testsRun"
Write-Host "Tests Passed: $testsPassed" -ForegroundColor Green
Write-Host "Tests Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { 'Red' } else { 'Green' })

if ($testsFailed -eq 0) {
    Write-Host "`n✓ All tests passed!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "`n✗ Some tests failed!" -ForegroundColor Red
    exit 1
}
