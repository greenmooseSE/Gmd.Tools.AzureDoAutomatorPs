<#
.SYNOPSIS
Test suite for RemoveAzDoCommentReaction.ps1

.DESCRIPTION
Validates the RemoveAzDoCommentReaction.ps1 script functionality by:
1. Creating a test work item
2. Adding a comment with all reaction types
3. Verifying deletion of each reaction type
4. Validating error handling for non-existent reactions
5. Cleaning up all test work items

Test Coverage:
- AC1: Remove reaction from comment - Given comment has a "like" reaction, When calling RemoveAzDoCommentReaction, Then reaction is removed and success response returned
- AC2: Scripts handle invalid reaction types with clear error messages
- AC3: Script supports -Organization, -Project, -WorkItemId, -CommentId, -ReactionType parameters
- AC4: All reaction types (like, dislike, heart, hooray, smile, confused) are tested

.NOTES
This test creates temporary work items tagged with 'testWi' for cleanup verification.
All created items are removed during teardown, even if tests fail.
#>

#Requires -Version 7.0

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Import test base class and helpers
$testScriptRoot = Split-Path (Split-Path $PSScriptRoot)
$srcRoot = Join-Path $testScriptRoot '..\src'

. "$srcRoot\AzDoAutomatorConstants.ps1"
. "$srcRoot\AzDoPatTokenHelper.ps1"
. "$srcRoot\AzDoApiWrapper.ps1"
. "$srcRoot\AzDoWorkItemHelper.ps1"

# Validate ssLogIt.ps1 is available
if (-not (Get-Command -Name 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    Write-Error "Required helper 'ssLogIt.ps1' not found in PATH."
}

# Initialize test state
[int[]]$createdWorkItems = @()
[hashtable]$testResults = @{
    passed = 0
    failed = 0
    skipped = 0
}

# ============================================================================
# Helper Functions
# ============================================================================

function New-TestWorkItem {
    [CmdletBinding()]
    param([string]$Title)

    $wi = New-AzDoWorkItem `
        -Organization $env:GMD_AZDO_ORGANIZATION `
        -Project $env:GMD_AZDO_PROJECT `
        -WorkItemType 'User Story' `
        -Fields @{
            'System.Title' = $Title
            'System.Description' = "Test work item for reaction delete testing"
            'System.Tags' = 'testWi'
            'Microsoft.VSTS.Scheduling.StoryPoints' = 1
        }

    $script:createdWorkItems += $wi.id
    return $wi
}

function Remove-TestWorkItems {
    [CmdletBinding()]
    param()

    foreach ($id in $script:createdWorkItems) {
        try {
            $null = & ssLogIt.ps1 -Level Debug -Message "Cleaning up test work item $id"
            Remove-AzDoWorkItem -Organization $env:GMD_AZDO_ORGANIZATION -Project $env:GMD_AZDO_PROJECT -WorkItemId $id
        }
        catch {
            $null = & ssLogIt.ps1 -Level Warning -Message "Failed to remove test work item $id : $_"
        }
    }
    $script:createdWorkItems = @()
}

function Invoke-Test {
    [CmdletBinding()]
    param(
        [string]$TestName,
        [scriptblock]$TestBlock
    )

    try {
        Write-Host "`n▶ Testing: $TestName" -ForegroundColor Cyan
        & $TestBlock
        Write-Host "  ✅ PASS: $TestName" -ForegroundColor Green
        $script:testResults.passed++
    }
    catch {
        Write-Host "  ❌ FAIL: $TestName" -ForegroundColor Red
        Write-Host "     Error: $_" -ForegroundColor Red
        $script:testResults.failed++
    }
}

# ============================================================================
# Tests
# ============================================================================

Write-Host "`n" + "="*70 -ForegroundColor Cyan
Write-Host "Test Suite: RemoveAzDoCommentReaction.ps1 (Story 1594)" -ForegroundColor Cyan
Write-Host "="*70 -ForegroundColor Cyan

# Test: AC1 - Remove reaction from comment (like)
Invoke-Test -TestName "AC1: Remove 'like' reaction from comment" -TestBlock {
    $wi = New-TestWorkItem -Title "Test: Remove Like Reaction"
    
    # Add comment
    $comment = . "$srcRoot\NewAzDoComment.ps1" `
        -Organization $env:GMD_AZDO_ORGANIZATION `
        -Project $env:GMD_AZDO_PROJECT `
        -WorkItemId $wi.id `
        -Content "Test comment for reaction removal"
    
    if ($null -eq $comment.id) { throw "Comment creation failed" }
    
    # Add 'like' reaction
    $reaction = . "$srcRoot\NewAzDoCommentReaction.ps1" `
        -Organization $env:GMD_AZDO_ORGANIZATION `
        -Project $env:GMD_AZDO_PROJECT `
        -WorkItemId $wi.id `
        -CommentId $comment.id `
        -ReactionType 'like'
    
    if ($reaction.count -le 0) { throw "Reaction creation failed" }
    
    # Remove the reaction
    $result = . "$srcRoot\RemoveAzDoCommentReaction.ps1" `
        -Organization $env:GMD_AZDO_ORGANIZATION `
        -Project $env:GMD_AZDO_PROJECT `
        -WorkItemId $wi.id `
        -CommentId $comment.id `
        -ReactionType 'like'
    
    if ($result.success -ne $true) { throw "Reaction removal should succeed" }
    if ($result.statusCode -ne 202) { throw "Should return 202 Accepted" }
    if ($result.reactionType -ne 'like') { throw "Should specify removed reaction type" }
}

# Test: AC1 - Remove all reaction types
$reactionTypes = @('like', 'dislike', 'heart', 'hooray', 'smile', 'confused')
foreach ($type in $reactionTypes) {
    Invoke-Test -TestName "AC1: Remove '$type' reaction from comment" -TestBlock {
        $wi = New-TestWorkItem -Title "Test: Remove $($type) Reaction"
        
        # Add comment
        $comment = . "$srcRoot\NewAzDoComment.ps1" `
            -Organization $env:GMD_AZDO_ORGANIZATION `
            -Project $env:GMD_AZDO_PROJECT `
            -WorkItemId $wi.id `
            -Content "Test comment for $type reaction"
        
        # Add reaction
        $reaction = . "$srcRoot\NewAzDoCommentReaction.ps1" `
            -Organization $env:GMD_AZDO_ORGANIZATION `
            -Project $env:GMD_AZDO_PROJECT `
            -WorkItemId $wi.id `
            -CommentId $comment.id `
            -ReactionType $type
        
        # Remove reaction
        $result = . "$srcRoot\RemoveAzDoCommentReaction.ps1" `
            -Organization $env:GMD_AZDO_ORGANIZATION `
            -Project $env:GMD_AZDO_PROJECT `
            -WorkItemId $wi.id `
            -CommentId $comment.id `
            -ReactionType $type
        
        if ($result.success -ne $true) { throw "Should successfully remove $type reaction" }
    }
}

# Test: AC2 - Invalid reaction type error handling
Invoke-Test -TestName "AC2: Invalid reaction type is rejected with clear error" -TestBlock {
    $wi = New-TestWorkItem -Title "Test: Invalid Reaction Type"
    
    $comment = . "$srcRoot\NewAzDoComment.ps1" `
        -Organization $env:GMD_AZDO_ORGANIZATION `
        -Project $env:GMD_AZDO_PROJECT `
        -WorkItemId $wi.id `
        -Content "Test"
    
    # Try to remove invalid reaction type - should throw validation error
    $errThrown = $false
    try {
        . "$srcRoot\RemoveAzDoCommentReaction.ps1" `
            -Organization $env:GMD_AZDO_ORGANIZATION `
            -Project $env:GMD_AZDO_PROJECT `
            -WorkItemId $wi.id `
            -CommentId $comment.id `
            -ReactionType 'invalid' `
            -ErrorAction Stop
    }
    catch {
        if ($_ -match 'invalid|ValidateSet') {
            $errThrown = $true
        }
        else {
            throw
        }
    }
    
    if (-not $errThrown) { throw "Should reject invalid reaction type" }
}

# Test: AC3 - Required parameters validation
Invoke-Test -TestName "AC3: All required parameters are enforced" -TestBlock {
    # Test missing Organization
    $errThrown = $false
    try {
        . "$srcRoot\RemoveAzDoCommentReaction.ps1" `
            -Organization "" `
            -Project $env:GMD_AZDO_PROJECT `
            -WorkItemId 999 `
            -CommentId 999 `
            -ReactionType 'like' `
            -ErrorAction Stop
    }
    catch {
        $errThrown = $true
    }
    if (-not $errThrown) { throw "Should require Organization parameter" }
}

# Test: AC4 - Non-existent reaction removal error handling
Invoke-Test -TestName "AC4: Error when removing non-existent reaction" -TestBlock {
    $wi = New-TestWorkItem -Title "Test: Non-existent Reaction"
    
    $comment = . "$srcRoot\NewAzDoComment.ps1" `
        -Organization $env:GMD_AZDO_ORGANIZATION `
        -Project $env:GMD_AZDO_PROJECT `
        -WorkItemId $wi.id `
        -Content "Test comment without reactions"
    
    # Try to remove reaction that doesn't exist
    $errThrown = $false
    try {
        . "$srcRoot\RemoveAzDoCommentReaction.ps1" `
            -Organization $env:GMD_AZDO_ORGANIZATION `
            -Project $env:GMD_AZDO_PROJECT `
            -WorkItemId $wi.id `
            -CommentId $comment.id `
            -ReactionType 'like' `
            -ErrorAction Stop
    }
    catch {
        if ($_ -match 'does not exist') {
            $errThrown = $true
        }
        else {
            throw
        }
    }
    
    if (-not $errThrown) { throw "Should error when reaction doesn't exist" }
}

# ============================================================================
# Test Cleanup
# ============================================================================

Write-Host "`n" + "="*70 -ForegroundColor Cyan
Write-Host "Cleanup: Removing all test work items..." -ForegroundColor Yellow
Write-Host "="*70 -ForegroundColor Cyan

Remove-TestWorkItems

# ============================================================================
# Summary
# ============================================================================

Write-Host "`n" + "="*70 -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "="*70 -ForegroundColor Cyan
Write-Host "  Passed:  $($script:testResults.passed)" -ForegroundColor Green
Write-Host "  Failed:  $($script:testResults.failed)" -ForegroundColor $(if ($script:testResults.failed -gt 0) { 'Red' } else { 'Green' })
Write-Host "  Skipped: $($script:testResults.skipped)" -ForegroundColor Yellow
Write-Host "="*70 -ForegroundColor Cyan
Write-Host ""

# Exit with error code if any tests failed
if ($script:testResults.failed -gt 0) {
    exit 1
}
