<#
.SYNOPSIS
Azure DevOps Automation Helper - Basic Integration Tests

.DESCRIPTION
Basic tests to validate core functionality of the helper modules.
Tests focus on function definitions, parameter validation, and error handling.

Run with: pwsh -File .\BasicIntegrationTest.ps1

.NOTES
For comprehensive testing against a real Azure DevOps instance, additional test fixtures would be needed.
#>

#Requires -Version 7.0

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Test configuration
[string]$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
[string]$SRC_DIR = Join-Path $SCRIPT_DIR '../src'

# Import modules
Write-Host "Loading modules..." -ForegroundColor Cyan
. (Join-Path $SRC_DIR 'AzDoAutomatorConstants.ps1')
. (Join-Path $SRC_DIR 'AzDoPatTokenHelper.ps1')
. (Join-Path $SRC_DIR 'AzDoApiWrapper.ps1')
. (Join-Path $SRC_DIR 'AzDoWorkItemHelper.ps1')

# Test counters
[int]$testsRun = 0
[int]$testsPassed = 0
[int]$testsFailed = 0

function Invoke-Test {
    [CmdletBinding()]
    param(
        [string]$Name,
        [scriptblock]$TestScript
    )

    $testsRun++
    Write-Host "Test: $Name" -ForegroundColor Yellow

    try {
        & $TestScript
        $testsPassed++
        Write-Host "  ✓ PASSED" -ForegroundColor Green
    }
    catch {
        $testsFailed++
        Write-Host "  ✗ FAILED: $_" -ForegroundColor Red
    }
}

# ============================================================================
# Constants Module Tests
# ============================================================================

Write-Host "`n=== Constants Module Tests ===" -ForegroundColor Cyan

Invoke-Test "Constants loaded" {
    if (-not (Test-Path variable:script:AZDO_API_VERSION)) {
        throw "AZDO_API_VERSION not defined"
    }
    if ($script:AZDO_API_VERSION -eq $null) {
        throw "AZDO_API_VERSION is null"
    }
}

Invoke-Test "Work item types defined" {
    if ([string]::IsNullOrWhiteSpace($script:WORKITEM_TYPE_EPIC)) {
        throw "WORKITEM_TYPE_EPIC not defined"
    }
    if ([string]::IsNullOrWhiteSpace($script:WORKITEM_TYPE_FEATURE)) {
        throw "WORKITEM_TYPE_FEATURE not defined"
    }
    if ([string]::IsNullOrWhiteSpace($script:WORKITEM_TYPE_STORY)) {
        throw "WORKITEM_TYPE_STORY not defined"
    }
}

Invoke-Test "Field reference names defined" {
    if ([string]::IsNullOrWhiteSpace($script:FIELD_SYSTEM_TITLE)) {
        throw "FIELD_SYSTEM_TITLE not defined"
    }
    if ([string]::IsNullOrWhiteSpace($script:FIELD_DESCRIPTION)) {
        throw "FIELD_DESCRIPTION not defined"
    }
    if ([string]::IsNullOrWhiteSpace($script:FIELD_STORY_POINTS)) {
        throw "FIELD_STORY_POINTS not defined"
    }
}

Invoke-Test "Regex patterns defined" {
    if ($script:REGEX_MARKDOWN_EPIC -eq $null) {
        throw "REGEX_MARKDOWN_EPIC not defined"
    }
    if ($script:REGEX_MARKDOWN_FEATURE -eq $null) {
        throw "REGEX_MARKDOWN_FEATURE not defined"
    }
    if ($script:REGEX_MARKDOWN_STORY -eq $null) {
        throw "REGEX_MARKDOWN_STORY not defined"
    }
}

# ============================================================================
# PAT Token Helper Tests
# ============================================================================

Write-Host "`n=== PAT Token Helper Tests ===" -ForegroundColor Cyan

Invoke-Test "ssEncryptDecrypt check function exists" {
    if ((Get-Command -Name 'Confirm-SsEncryptDecryptHelperExists' -ErrorAction SilentlyContinue) -eq $null) {
        throw "Confirm-SsEncryptDecryptHelperExists not found"
    }
}

Invoke-Test "Get-AzDoPatToken function exists" {
    if ((Get-Command -Name 'Get-AzDoPatToken' -ErrorAction SilentlyContinue) -eq $null) {
        throw "Get-AzDoPatToken not found"
    }
}

Invoke-Test "New-AzDoAuthHeader function exists" {
    if ((Get-Command -Name 'New-AzDoAuthHeader' -ErrorAction SilentlyContinue) -eq $null) {
        throw "New-AzDoAuthHeader not found"
    }
}

Invoke-Test "Test-AzDoPatToken function exists" {
    if ((Get-Command -Name 'Test-AzDoPatToken' -ErrorAction SilentlyContinue) -eq $null) {
        throw "Test-AzDoPatToken not found"
    }
}

# ============================================================================
# API Wrapper Tests
# ============================================================================

Write-Host "`n=== API Wrapper Tests ===" -ForegroundColor Cyan

Invoke-Test "Invoke-AzDoWiql function exists" {
    if ((Get-Command -Name 'Invoke-AzDoWiql' -ErrorAction SilentlyContinue) -eq $null) {
        throw "Invoke-AzDoWiql not found"
    }
}

Invoke-Test "Get-AzDoWorkItemById function exists" {
    if ((Get-Command -Name 'Get-AzDoWorkItemById' -ErrorAction SilentlyContinue) -eq $null) {
        throw "Get-AzDoWorkItemById not found"
    }
}

Invoke-Test "New-AzDoWorkItem function exists" {
    if ((Get-Command -Name 'New-AzDoWorkItem' -ErrorAction SilentlyContinue) -eq $null) {
        throw "New-AzDoWorkItem not found"
    }
}

Invoke-Test "Update-AzDoWorkItem function exists" {
    if ((Get-Command -Name 'Update-AzDoWorkItem' -ErrorAction SilentlyContinue) -eq $null) {
        throw "Update-AzDoWorkItem not found"
    }
}

Invoke-Test "Remove-AzDoWorkItem function exists" {
    if ((Get-Command -Name 'Remove-AzDoWorkItem' -ErrorAction SilentlyContinue) -eq $null) {
        throw "Remove-AzDoWorkItem not found"
    }
}

# ============================================================================
# Work Item Helper Tests
# ============================================================================

Write-Host "`n=== Work Item Helper Tests ===" -ForegroundColor Cyan

Invoke-Test "Find-AzDoWorkItemByTitle function exists" {
    if ((Get-Command -Name 'Find-AzDoWorkItemByTitle' -ErrorAction SilentlyContinue) -eq $null) {
        throw "Find-AzDoWorkItemByTitle not found"
    }
}

Invoke-Test "Test-AzDoWorkItemExists function exists" {
    if ((Get-Command -Name 'Test-AzDoWorkItemExists' -ErrorAction SilentlyContinue) -eq $null) {
        throw "Test-AzDoWorkItemExists not found"
    }
}

Invoke-Test "Get-AzDoChildWorkItems function exists" {
    if ((Get-Command -Name 'Get-AzDoChildWorkItems' -ErrorAction SilentlyContinue) -eq $null) {
        throw "Get-AzDoChildWorkItems not found"
    }
}

Invoke-Test "Get-AzDoAllDescendants function exists" {
    if ((Get-Command -Name 'Get-AzDoAllDescendants' -ErrorAction SilentlyContinue) -eq $null) {
        throw "Get-AzDoAllDescendants not found"
    }
}

Invoke-Test "Test-AzDoWorkItemIdValid function exists" {
    if ((Get-Command -Name 'Test-AzDoWorkItemIdValid' -ErrorAction SilentlyContinue) -eq $null) {
        throw "Test-AzDoWorkItemIdValid not found"
    }
}

Invoke-Test "Get-AzDoWorkItemParent function exists" {
    if ((Get-Command -Name 'Get-AzDoWorkItemParent' -ErrorAction SilentlyContinue) -eq $null) {
        throw "Get-AzDoWorkItemParent not found"
    }
}

# ============================================================================
# Helper Function Validation Tests
# ============================================================================

Write-Host "`n=== Helper Function Validation Tests ===" -ForegroundColor Cyan

Invoke-Test "Test-AzDoWorkItemIdValid accepts positive integers" {
    $result = Test-AzDoWorkItemIdValid -WorkItemId 123
    if ($result -ne $true) {
        throw "Expected true for valid ID 123, got $result"
    }
}

Invoke-Test "Test-AzDoWorkItemIdValid rejects zero" {
    $result = Test-AzDoWorkItemIdValid -WorkItemId 0
    if ($result -ne $false) {
        throw "Expected false for ID 0, got $result"
    }
}

Invoke-Test "Test-AzDoWorkItemIdValid rejects negative" {
    $result = Test-AzDoWorkItemIdValid -WorkItemId -5
    if ($result -ne $false) {
        throw "Expected false for negative ID, got $result"
    }
}

# ============================================================================
# Script File Validation Tests
# ============================================================================

Write-Host "`n=== Script File Validation Tests ===" -ForegroundColor Cyan

Invoke-Test "New-AzDoFeature.ps1 exists" {
    $path = Join-Path $SRC_DIR 'New-AzDoFeature.ps1'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "File not found: $path"
    }
}

Invoke-Test "New-AzDoStory.ps1 exists" {
    $path = Join-Path $SRC_DIR 'New-AzDoStory.ps1'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "File not found: $path"
    }
}

Invoke-Test "Get-AzDoWorkItem.ps1 exists" {
    $path = Join-Path $SRC_DIR 'Get-AzDoWorkItem.ps1'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "File not found: $path"
    }
}

Invoke-Test "Set-AzDoWorkItemTags.ps1 exists" {
    $path = Join-Path $SRC_DIR 'Set-AzDoWorkItemTags.ps1'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "File not found: $path"
    }
}

Invoke-Test "Remove-AzDoEpic.ps1 exists" {
    $path = Join-Path $SRC_DIR 'Remove-AzDoEpic.ps1'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "File not found: $path"
    }
}

Invoke-Test "New-AzDoHierarchyFromMarkdown.ps1 exists" {
    $path = Join-Path $SRC_DIR 'New-AzDoHierarchyFromMarkdown.ps1'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "File not found: $path"
    }
}

# ============================================================================
# Test Summary
# ============================================================================

Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Tests run:    $testsRun" -ForegroundColor White
Write-Host "Tests passed: $testsPassed" -ForegroundColor Green
Write-Host "Tests failed: $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })

if ($testsFailed -gt 0) {
    exit 1
}

Write-Host "`nAll basic integration tests passed!" -ForegroundColor Green
exit 0
