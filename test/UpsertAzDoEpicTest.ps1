<#
.SYNOPSIS
Integration test for UpsertAzDoEpic functionality

.DESCRIPTION
Tests the UpsertAzDoEpic.ps1 script for creating and updating Azure DevOps Epic work items.

Requires Environment variable set:
- GMD_AZDO_ORGANIZATION: Organization name
- GMD_AZDO_PROJECT: Project name
- GMD_AZDO_MACHINE_WORKITEMSRW: Encrypted PAT token

Run with: pwsh -File .\UpsertAzDoEpicTest.ps1

.NOTES
Tests three scenarios:
1. Create new Epic (no ID provided)
2. Update existing Epic with ID provided
3. Enforce create-only with -FailIfExist
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
[array]$createdEpics = @()

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
    if ($script:createdEpics.Count -gt 0) {
        Write-Host "`nCleaning up test items..." -ForegroundColor Cyan
        foreach ($epicId in $script:createdEpics) {
            try {
                & "$SRC_DIR/RemoveAzDoEpic.ps1" -Organization $Organization -Project $Project -EpicId $epicId -Force
                Write-Host "Cleaned up test Epic (ID: $epicId)" -ForegroundColor Green
            }
            catch {
                Write-Host "Warning: Cleanup failed for Epic $epicId : $_" -ForegroundColor Yellow
            }
        }
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Azure DevOps Upsert Epic Tests" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Setting up test data..." -ForegroundColor Cyan

try {
    # This test Epic will be used for update scenarios
    $testEpicScript = @{
        Organization = $Organization
        Project      = $Project
        Title        = "UpsertTest_Original_$(Get-Date -Format 'yyyyMMddHHmmss')"
        Description  = "Original description"
        Effort       = 5
    }
    $existingEpic = & "$SRC_DIR/UpsertAzDoEpic.ps1" @testEpicScript
    $script:createdEpics += $existingEpic.id
    Write-Host "Created test Epic for updates (ID: $($existingEpic.id))" -ForegroundColor Green
}
catch {
    Write-Host "Failed to set up test data: $_" -ForegroundColor Red
    Cleanup
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Running tests..." -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Scenario 1: Create new Epic (no ID provided)
Write-Host "`n--- Scenario 1: Create New Epic ---" -ForegroundColor Magenta

Invoke-Test "Script file exists" {
    if (-not (Test-Path "$SRC_DIR/UpsertAzDoEpic.ps1")) {
        throw "UpsertAzDoEpic.ps1 not found at $SRC_DIR/UpsertAzDoEpic.ps1"
    }
}

Invoke-Test "Script has Organization parameter" {
    $cmd = Get-Command -Name "$SRC_DIR/UpsertAzDoEpic.ps1"
    if ($cmd.Parameters.Keys -notcontains 'Organization') {
        throw "Organization parameter not found"
    }
}

Invoke-Test "Script has Title parameter" {
    $cmd = Get-Command -Name "$SRC_DIR/UpsertAzDoEpic.ps1"
    if ($cmd.Parameters.Keys -notcontains 'Title') {
        throw "Title parameter not found"
    }
}

Invoke-Test "Script has Id parameter (optional)" {
    $cmd = Get-Command -Name "$SRC_DIR/UpsertAzDoEpic.ps1"
    if ($cmd.Parameters.Keys -notcontains 'Id') {
        throw "Id parameter not found"
    }
}

Invoke-Test "Script has FailIfExist parameter (optional)" {
    $cmd = Get-Command -Name "$SRC_DIR/UpsertAzDoEpic.ps1"
    if ($cmd.Parameters.Keys -notcontains 'FailIfExist') {
        throw "FailIfExist parameter not found"
    }
}

Invoke-Test "Create new Epic without ID returns object with ID" {
    $newTitle = "UpsertTest_NewEpic_$(Get-Date -Format 'yyyyMMddHHmmss')"
    $upsertScript = @{
        Organization = $Organization
        Project      = $Project
        Title        = $newTitle
    }
    $newEpic = & "$SRC_DIR/UpsertAzDoEpic.ps1" @upsertScript
    
    if ($null -eq $newEpic -or $newEpic.id -le 0) {
        throw "New Epic should have a valid ID"
    }
    
    if ($newEpic.fields."System.Title" -ne $newTitle) {
        throw "Epic title does not match: expected '$newTitle', got '$($newEpic.fields.'System.Title')'"
    }
    
    $script:createdEpics += $newEpic.id
    Write-Host "    Created Epic ID: $($newEpic.id)" -ForegroundColor Cyan
}

Invoke-Test "Create new Epic with optional Description" {
    $newTitle = "UpsertTest_WithDesc_$(Get-Date -Format 'yyyyMMddHHmmss')"
    $description = "This is a test description"
    $upsertScript = @{
        Organization = $Organization
        Project      = $Project
        Title        = $newTitle
        Description  = $description
    }
    $newEpic = & "$SRC_DIR/UpsertAzDoEpic.ps1" @upsertScript
    
    if ($newEpic.fields."System.Description" -ne $description) {
        throw "Epic description does not match: expected '$description', got '$($newEpic.fields.'System.Description')'"
    }
    
    $script:createdEpics += $newEpic.id
    Write-Host "    Created Epic ID: $($newEpic.id) with description" -ForegroundColor Cyan
}

Invoke-Test "Create new Epic with optional Effort" {
    $newTitle = "UpsertTest_WithEffort_$(Get-Date -Format 'yyyyMMddHHmmss')"
    $effort = 13
    $upsertScript = @{
        Organization = $Organization
        Project      = $Project
        Title        = $newTitle
        Effort       = $effort
    }
    $newEpic = & "$SRC_DIR/UpsertAzDoEpic.ps1" @upsertScript
    
    if ($newEpic.fields."Microsoft.VSTS.Scheduling.Effort" -ne $effort) {
        throw "Epic effort does not match: expected $effort, got $($newEpic.fields.'Microsoft.VSTS.Scheduling.Effort')"
    }
    
    $script:createdEpics += $newEpic.id
    Write-Host "    Created Epic ID: $($newEpic.id) with effort" -ForegroundColor Cyan
}

Invoke-Test "Create new Epic with all optional parameters" {
    $newTitle = "UpsertTest_AllParams_$(Get-Date -Format 'yyyyMMddHHmmss')"
    $description = "Complete test epic"
    $effort = 21
    
    $upsertScript = @{
        Organization = $Organization
        Project      = $Project
        Title        = $newTitle
        Description  = $description
        Effort       = $effort
    }
    $newEpic = & "$SRC_DIR/UpsertAzDoEpic.ps1" @upsertScript
    
    if ($newEpic.fields."System.Title" -ne $newTitle) {
        throw "Title mismatch"
    }
    if ($newEpic.fields."System.Description" -ne $description) {
        throw "Description mismatch"
    }
    if ($newEpic.fields."Microsoft.VSTS.Scheduling.Effort" -ne $effort) {
        throw "Effort mismatch"
    }
    
    $script:createdEpics += $newEpic.id
    Write-Host "    Created Epic ID: $($newEpic.id) with all parameters" -ForegroundColor Cyan
}

# Scenario 2: Update existing Epic with ID provided
Write-Host "`n--- Scenario 2: Update Existing Epic ---" -ForegroundColor Magenta

Invoke-Test "Update Epic title by ID" {
    $updatedTitle = "UpsertTest_Updated_$(Get-Date -Format 'yyyyMMddHHmmss')"
    $upsertScript = @{
        Organization = $Organization
        Project      = $Project
        Id           = $existingEpic.id
        Title        = $updatedTitle
    }
    $updatedEpic = & "$SRC_DIR/UpsertAzDoEpic.ps1" @upsertScript
    
    if ($updatedEpic.fields."System.Title" -ne $updatedTitle) {
        throw "Epic title was not updated"
    }
    if ($updatedEpic.id -ne $existingEpic.id) {
        throw "Epic ID changed during update"
    }
    
    Write-Host "    Updated Epic ID: $($updatedEpic.id)" -ForegroundColor Cyan
}

Invoke-Test "Update Epic description only (partial update)" {
    $newDescription = "Updated description"
    $upsertScript = @{
        Organization = $Organization
        Project      = $Project
        Id           = $existingEpic.id
        Description  = $newDescription
    }
    $updatedEpic = & "$SRC_DIR/UpsertAzDoEpic.ps1" @upsertScript
    
    if ($updatedEpic.fields."System.Description" -ne $newDescription) {
        throw "Epic description was not updated"
    }
    
    Write-Host "    Updated Epic ID: $($updatedEpic.id) with new description" -ForegroundColor Cyan
}

Invoke-Test "Update Epic effort only (partial update)" {
    $newEffort = 34
    $upsertScript = @{
        Organization = $Organization
        Project      = $Project
        Id           = $existingEpic.id
        Effort       = $newEffort
    }
    $updatedEpic = & "$SRC_DIR/UpsertAzDoEpic.ps1" @upsertScript
    
    if ($updatedEpic.fields."Microsoft.VSTS.Scheduling.Effort" -ne $newEffort) {
        throw "Epic effort was not updated"
    }
    
    Write-Host "    Updated Epic ID: $($updatedEpic.id) with new effort" -ForegroundColor Cyan
}

Invoke-Test "Update Epic with multiple fields" {
    $newTitle = "UpsertTest_MultiUpdate_$(Get-Date -Format 'yyyyMMddHHmmss')"
    $newDescription = "Multi-field update"
    $newEffort = 55
    
    $upsertScript = @{
        Organization = $Organization
        Project      = $Project
        Id           = $existingEpic.id
        Title        = $newTitle
        Description  = $newDescription
        Effort       = $newEffort
    }
    $updatedEpic = & "$SRC_DIR/UpsertAzDoEpic.ps1" @upsertScript
    
    if ($updatedEpic.fields."System.Title" -ne $newTitle) {
        throw "Title not updated"
    }
    if ($updatedEpic.fields."System.Description" -ne $newDescription) {
        throw "Description not updated"
    }
    if ($updatedEpic.fields."Microsoft.VSTS.Scheduling.Effort" -ne $newEffort) {
        throw "Effort not updated"
    }
    
    Write-Host "    Updated Epic ID: $($updatedEpic.id) with multiple fields" -ForegroundColor Cyan
}

# Scenario 3: Enforce create-only with -FailIfExist
Write-Host "`n--- Scenario 3: Create-Only Mode with -FailIfExist ---" -ForegroundColor Magenta

Invoke-Test "FailIfExist errors when Epic already exists" {
    $errorOccurred = $false
    $upsertScript = @{
        Organization = $Organization
        Project      = $Project
        Id           = $existingEpic.id
        Title        = "ShouldFail"
        FailIfExist  = $true
    }
    
    try {
        & "$SRC_DIR/UpsertAzDoEpic.ps1" @upsertScript 2>&1 | Out-Null
    }
    catch {
        $errorOccurred = $true
    }
    
    if (-not $errorOccurred) {
        throw "Expected an error when -FailIfExist is used with existing Epic"
    }
    
    Write-Host "    Correctly failed when trying to create existing Epic" -ForegroundColor Cyan
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Tests Run:    $testsRun" -ForegroundColor Cyan
Write-Host "Tests Passed: $testsPassed" -ForegroundColor Green
Write-Host "Tests Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { 'Red' } else { 'Green' })

Cleanup

if ($testsFailed -gt 0) {
    exit 1
}

exit 0
