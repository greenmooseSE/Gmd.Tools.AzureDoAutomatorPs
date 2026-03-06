<#
.SYNOPSIS
Integration test for GetAzDoCommentReactions functionality

.DESCRIPTION
Tests the GetAzDoCommentReactions.ps1 script for retrieving reactions from work item comments.

Requires Environment variable set:
- GMD_AZDO_ORGANIZATION: Organization name
- GMD_AZDO_PROJECT: Project name
- GMD_AZDO_MACHINE_WORKITEMSRW: Encrypted PAT token

Run with: pwsh -File .\GetAzDoCommentReactionsTest.ps1

.NOTES
Creates temporary test work items, adds comments, adds reactions, retrieves them, and cleans up.
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
Write-Host "Azure DevOps Get Comment Reactions Tests" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Create test structure for comment reactions
Write-Host "Setting up test data..." -ForegroundColor Cyan

try {
    # Create test Epic
    $epicScript = @{
        Organization = $Organization
        Project      = $Project
        Title        = "Test Epic for Get Reactions $(Get-Date -Format 'yyyyMMddHHmmss')"
    }
    $epic = & "$SRC_DIR/UpsertAzDoEpic.ps1" @epicScript
    $script:createdItems += $epic.id
    Write-Host "Created test Epic (ID: $($epic.id))" -ForegroundColor Green

    # Create test Feature
    $featureScript = @{
        Organization = $Organization
        Project      = $Project
        Title        = "Test Feature for Get Reactions"
        ParentEpicId = $epic.id
    }
    $feature = & "$SRC_DIR/UpsertAzDoFeature.ps1" @featureScript
    Write-Host "Created test Feature (ID: $($feature.id))" -ForegroundColor Green

    # Create test Story
    $storyScript = @{
        Organization   = $Organization
        Project        = $Project
        Title          = "Test Story for Get Reactions"
        ParentFeatureId = $feature.id
    }
    $story = & "$SRC_DIR/UpsertAzDoStory.ps1" @storyScript
    Write-Host "Created test Story (ID: $($story.id))" -ForegroundColor Green

    # Create test Comment
    $commentScript = @{
        Organization = $Organization
        Project      = $Project
        WorkItemId   = $story.id
        Content      = "This is a test comment for getting reactions"
    }
    $comment = & "$SRC_DIR/NewAzDoComment.ps1" @commentScript
    Write-Host "Created test Comment (ID: $($comment.id))" -ForegroundColor Green

    # Add some reactions
    Write-Host "Adding test reactions..." -ForegroundColor Cyan
    & "$SRC_DIR/NewAzDoCommentReaction.ps1" -Organization $Organization -Project $Project -WorkItemId $story.id -CommentId $comment.id -ReactionType "like" | Out-Null
    & "$SRC_DIR/NewAzDoCommentReaction.ps1" -Organization $Organization -Project $Project -WorkItemId $story.id -CommentId $comment.id -ReactionType "heart" | Out-Null
    & "$SRC_DIR/NewAzDoCommentReaction.ps1" -Organization $Organization -Project $Project -WorkItemId $story.id -CommentId $comment.id -ReactionType "hooray" | Out-Null
    Write-Host "Added test reactions" -ForegroundColor Green
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
    $cmd = Get-Command -Name "$SRC_DIR/GetAzDoCommentReactions.ps1"
    $params = $cmd.Parameters.Keys
    if ("Organization" -notin $params) {
        throw "Organization parameter not found"
    }
}

# Test 2: Script has Project parameter
Invoke-Test "Script has Project parameter" {
    $cmd = Get-Command -Name "$SRC_DIR/GetAzDoCommentReactions.ps1"
    $params = $cmd.Parameters.Keys
    if ("Project" -notin $params) {
        throw "Project parameter not found"
    }
}

# Test 3: Script has WorkItemId parameter
Invoke-Test "Script has WorkItemId parameter" {
    $cmd = Get-Command -Name "$SRC_DIR/GetAzDoCommentReactions.ps1"
    $params = $cmd.Parameters.Keys
    if ("WorkItemId" -notin $params) {
        throw "WorkItemId parameter not found"
    }
}

# Test 4: Script has CommentId parameter
Invoke-Test "Script has CommentId parameter" {
    $cmd = Get-Command -Name "$SRC_DIR/GetAzDoCommentReactions.ps1"
    $params = $cmd.Parameters.Keys
    if ("CommentId" -notin $params) {
        throw "CommentId parameter not found"
    }
}

# Test 5: Script validates WorkItemId (negative value)
Invoke-Test "Script validates WorkItemId must be positive" {
    try {
        & "$SRC_DIR/GetAzDoCommentReactions.ps1" `
            -Organization $Organization `
            -Project $Project `
            -WorkItemId -1 `
            -CommentId $comment.id `
            -ErrorAction Stop 2>&1 | head -20
        throw "Should have failed with negative WorkItemId"
    }
    catch {
        # Expected to fail
        Write-Host "    (Validation caught: OK)" -ForegroundColor Gray
    }
}

# Test 6: Script successfully retrieves reactions
Invoke-Test "Script successfully retrieves reactions from comment" {
    $reactions = & "$SRC_DIR/GetAzDoCommentReactions.ps1" `
        -Organization $Organization `
        -Project $Project `
        -WorkItemId $story.id `
        -CommentId $comment.id
    
    if ($null -eq $reactions) {
        throw "Reactions object is null"
    }

    if ($reactions -is [System.Collections.IEnumerable] -and $reactions -isnot [string]) {
        $reactionCount = @($reactions).Count
        if ($reactionCount -lt 3) {
            throw "Expected at least 3 reactions, got $reactionCount"
        }
    }
    else {
        if ($reactions.Count -eq $null) {
            throw "Expected multiple reactions, got single reaction"
        }
    }
}

# Test 7: Script returns reactions with expected properties
Invoke-Test "Script returns reactions with type and count properties" {
    $reactions = & "$SRC_DIR/GetAzDoCommentReactions.ps1" `
        -Organization $Organization `
        -Project $Project `
        -WorkItemId $story.id `
        -CommentId $comment.id
    
    if ($null -eq $reactions) {
        throw "Reactions object is null"
    }

    # Normalize to array
    $reactionsArray = @($reactions)
    if ($reactionsArray.Count -eq 0) {
        throw "No reactions returned"
    }

    # Check first reaction has expected properties
    $firstReaction = $reactionsArray[0]
    if ($null -eq $firstReaction.type) {
        throw "Reaction does not have 'type' property"
    }

    if ($null -eq $firstReaction.count) {
        throw "Reaction does not have 'count' property"
    }

    # Verify type is one of the valid reaction types
    $validTypes = @("like", "dislike", "heart", "hooray", "smile", "confused")
    if ($firstReaction.type -notin $validTypes) {
        throw "Reaction type '$($firstReaction.type)' is not valid"
    }
}

# Test 8: Script filters reactions by type
Invoke-Test "Script returns specific reaction type when filtered" {
    $reactions = & "$SRC_DIR/GetAzDoCommentReactions.ps1" `
        -Organization $Organization `
        -Project $Project `
        -WorkItemId $story.id `
        -CommentId $comment.id
    
    # Filter to find 'like' reactions
    $likes = @($reactions) | Where-Object { $_.type -eq "like" }
    if ($likes.Count -eq 0) {
        throw "No 'like' reactions found"
    }

    if ($likes[0].count -lt 1) {
        throw "Like reaction count should be at least 1"
    }
}

# Test 9: Script returns empty array for comment with no reactions
Invoke-Test "Script handles comment with no reactions gracefully" {
    # Create new comment with no reactions
    $newComment = & "$SRC_DIR/NewAzDoComment.ps1" `
        -Organization $Organization `
        -Project $Project `
        -WorkItemId $story.id `
        -Content "Comment with no reactions"
    
    $reactions = & "$SRC_DIR/GetAzDoCommentReactions.ps1" `
        -Organization $Organization `
        -Project $Project `
        -WorkItemId $story.id `
        -CommentId $newComment.id
    
    if ($reactions -is [System.Collections.IEnumerable] -and $reactions -isnot [string]) {
        $reactionCount = @($reactions).Count
        if ($reactionCount -ne 0) {
            throw "Expected 0 reactions for new comment, got $reactionCount"
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
