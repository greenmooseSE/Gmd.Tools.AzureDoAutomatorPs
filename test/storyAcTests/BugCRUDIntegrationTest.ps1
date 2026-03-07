<#
.SYNOPSIS
Integration test for Bug CRUD operations - Stories 1641, 1642, 1643

.DESCRIPTION
Tests UpsertAzDoBug, GetAzDoBug, and RemoveAzDoBug scripts working together
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Path { $_ } -Parent
$scriptRoot = Join-Path $scriptRoot -ChildPath 'src'

$org = $env:GMD_AZDO_ORGANIZATION
$proj = $env:GMD_AZDO_PROJECT

if ([string]::IsNullOrWhiteSpace($org) -or [string]::IsNullOrWhiteSpace($proj)) {
    Write-Error "Environment variables GMD_AZDO_ORGANIZATION and GMD_AZDO_PROJECT must be set"
}

Write-Output "`n===== Bug CRUD Integration Test ====="
Write-Output "Organization: $org"
Write-Output "Project: $proj`n"

# Test 1: Create a Bug with UpsertAzDoBug
Write-Output "[TEST 1] Create Bug with UpsertAzDoBug.ps1"
try {
    $bugTitle = "IntegrationTest-Bug-$(Get-Random)"
    $bugPath = Join-Path $scriptRoot 'UpsertAzDoBug.ps1'
    
    $created = & $bugPath `
        -Organization $org `
        -Project $proj `
        -Title $bugTitle `
        -Priority 2 `
        -ReproSteps "Steps here" `
        -Description "Test bug" `
        -StoryPoints 3
    
    $bugId = $created.id
    Write-Output "✓ Created Bug ID: $bugId`n"
}
catch {
    Write-Output "✗ FAILED: $_`n"
    exit 1
}

# Test 2: Retrieve the Bug with GetAzDoBug
Write-Output "[TEST 2] Retrieve Bug with GetAzDoBug.ps1"
try {
    $getBugPath = Join-Path $scriptRoot 'GetAzDoBug.ps1'
    
    $retrieved = & $getBugPath `
        -Organization $org `
        -Project $proj `
        -BugId $bugId
    
    if ($retrieved.id -ne $bugId) {
        throw "Retrieved Bug ID doesn't match: expected $bugId, got $($retrieved.id)"
    }
    
    $retrievedTitle = if ($retrieved.fields.PSObject.Properties.Name -contains 'System.Title') { $retrieved.fields.'System.Title' } else { 'Unknown' }
    Write-Output "✓ Retrieved Bug: $retrievedTitle (ID: $($retrieved.id))`n"
}
catch {
    Write-Output "✗ FAILED: $_`n"
    exit 1
}

# Test 3: Delete the Bug with RemoveAzDoBug
Write-Output "[TEST 3] Delete Bug with RemoveAzDoBug.ps1"
try {
    $removeBugPath = Join-Path $scriptRoot 'RemoveAzDoBug.ps1'
    
    $result = & $removeBugPath `
        -Organization $org `
        -Project $proj `
        -BugId $bugId `
        -Force
    
    # Check if result contains success indicator
    if ($result -is [string] -and ($result -match '"success"\s*:\s*true' -or $result -match 'Bug deleted successfully')) {
        Write-Output "✓ Deleted Bug ID: $bugId`n"
    }
    else {
        Write-Output "Result: $result`n"
        throw "Deletion may have failed or returned unexpected result"
    }
}
catch {
    Write-Output "✗ FAILED: $_`n"
    exit 1
}

Write-Output "===== ALL INTEGRATION TESTS PASSED ====="
