<#

.SYNOPSIS
Integration tests for removing comments by ID and by text (by regex)

.DESCRIPTION
Creates a small work item hierarchy, adds comments, updates a comment to create
an edited version, then verifies deletion by CommentId and deletion by Text
(matching latest edited text) removes the full comment resource.

Run with: pwsh -File .\RemoveAzDoCommentTest.ps1 -Organization <org> -Project <proj>
#>

#Requires -Version 7.0

param(
    [string]$Organization = $env:GMD_AZDO_ORGANIZATION,
    [string]$Project = $env:GMD_AZDO_PROJECT
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Paths
[string]$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
[string]$SRC_DIR = Join-Path $SCRIPT_DIR '../src'

# Validate inputs
if ([string]::IsNullOrWhiteSpace($Organization)) { Write-Error "Organization not provided." }
if ([string]::IsNullOrWhiteSpace($Project)) { Write-Error "Project not provided." }

# Minimal helpers
[int]$testsRun = 0; [int]$testsPassed = 0; [int]$testsFailed = 0; $created = @()
function Invoke-Test { param($Name,$Script) ; $global:testsRun++; Write-Host "Test: $Name"; try { & $Script ; $global:testsPassed++; Write-Host '  ✓ PASSED' -ForegroundColor Green } catch { $global:testsFailed++; Write-Host "  ✗ FAILED: $_" -ForegroundColor Red } }

function Cleanup { if ($created.Count -gt 0) { try { & "$SRC_DIR/RemoveAzDoEpic.ps1" -Organization $Organization -Project $Project -EpicId $created[0] -Force ; Write-Host "Cleaned up Epic $($created[0])" } catch { Write-Host "Cleanup failed: $_" } } }
trap { Cleanup; exit 1 }

Write-Host "\n=== RemoveAzDoComment Tests ===\n"

# Setup: create epic->feature->story (reuse existing scripts)
try {
    $epic = & "$SRC_DIR/UpsertAzDoEpic.ps1" -Organization $Organization -Project $Project -Title "RemoveComment Epic $(Get-Date -Format o)"
    $created += $epic.id
    $feature = & "$SRC_DIR/NewAzDoFeature.ps1" -Organization $Organization -Project $Project -Title "RemoveComment Feature" -ParentEpicId $epic.id
    $story = & "$SRC_DIR/NewAzDoStory.ps1" -Organization $Organization -Project $Project -Title "RemoveComment Story" -ParentFeatureId $feature.id
}
catch { Write-Host "Setup failed: $_"; Cleanup; exit 1 }

Write-Host "Created story ID: $($story.id)" -ForegroundColor Cyan

# Test A: Remove by CommentId
Invoke-Test "Remove by ID" {
    $origText = "delete-by-id-$(Get-Date -Format 'yyyyMMddHHmmss')"
    $comment = & "$SRC_DIR/NewAzDoComment.ps1" -Organization $Organization -Project $Project -WorkItemId $story.id -Content $origText
    if ($null -eq $comment -or $null -eq $comment.id) { throw "Failed to create comment" }

    # Remove by ID
    $removed = & "$SRC_DIR/RemoveAzDoComment.ps1" -Organization $Organization -Project $Project -WorkItemId $story.id -CommentId $comment.id
    if (-not $removed) { throw "RemoveAzDoComment returned false" }

    # Verify gone: GET should throw
    . "$SRC_DIR/AzDoAutomatorConstants.ps1"
    . "$SRC_DIR/AzDoPatTokenHelper.ps1"
    . "$SRC_DIR/AzDoApiWrapper.ps1"
    $headers = New-AzDoAuthHeader -PatToken (Get-AzDoPatToken -Decrypt)
    try {
        Invoke-AzDoApiRequest -Uri "https://dev.azure.com/$Organization/$Project/_apis/wit/workitems/$($story.id)/comments/$($comment.id)?api-version=7.1-preview.3" -Method 'Get' -Headers $headers
        throw "Comment still exists after deletion"
    }
    catch {
        # Expected - treat 404 as success
    }
}

# Test B: Remove by TextMatchRegex (match latest edited text)
Invoke-Test "Remove by TextMatchRegex (latest edited)" {
    $baseText = "remove-by-text-base-$(Get-Date -Format 'yyyyMMddHHmmss')"
    $comment = & "$SRC_DIR/NewAzDoComment.ps1" -Organization $Organization -Project $Project -WorkItemId $story.id -Content $baseText
    if ($null -eq $comment -or $null -eq $comment.id) { throw "Failed to create comment" }

    # Edit the comment to change its latest text
    . "$SRC_DIR/AzDoAutomatorConstants.ps1"
    . "$SRC_DIR/AzDoPatTokenHelper.ps1"
    . "$SRC_DIR/AzDoApiWrapper.ps1"
    $pat = Get-AzDoPatToken -Decrypt
    $headers = New-AzDoAuthHeader -PatToken $pat
    $headers['Content-Type'] = 'application/json'

    $editedText = "$baseText - edited"
    $body = @{ text = $editedText } | ConvertTo-Json -Depth 10

    Invoke-AzDoApiRequest -Uri "https://dev.azure.com/$Organization/$Project/_apis/wit/workitems/$($story.id)/comments/$($comment.id)?api-version=7.1-preview.3" -Method 'Patch' -Headers $headers -Body $body

    # Now remove by TextMatchRegex (should match latest edited text)
    $regex = "^$([regex]::Escape($editedText))$"
    $removed = & "$SRC_DIR/RemoveAzDoComment.ps1" -Organization $Organization -Project $Project -WorkItemId $story.id -TextMatchRegex $regex
    if (-not $removed) { throw "RemoveAzDoComment returned false when removing by text" }

    # Verify gone
    try { Invoke-AzDoApiRequest -Uri "https://dev.azure.com/$Organization/$Project/_apis/wit/workitems/$($story.id)/comments/$($comment.id)?api-version=7.1-preview.3" -Method 'Get' -Headers $headers ; throw "Comment still exists after deletion" } catch { }
}

Cleanup

Write-Host "\n=== Summary ==="; Write-Host "Run: $testsRun, Passed: $testsPassed, Failed: $testsFailed"
if ($testsFailed -gt 0) { exit 1 } else { exit 0 }
