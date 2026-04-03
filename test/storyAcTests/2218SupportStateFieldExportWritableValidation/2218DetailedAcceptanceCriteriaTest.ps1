#Requires -Version 7.0

<#
.SYNOPSIS
Detailed AC Scenarios tests for story 2218: Export markdown with state field and validation

.DESCRIPTION
Tests the ConvertHierarchyToMarkdown.ps1 script to verify:
- State field appears in markdown metadata
- Editable states have no warnings
- Non-editable states include warning comments
- Markdown export completes successfully with various states

.NOTES
Tests the actual markdown export functionality
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$SRC_DIR = ".\src"
$Organization = "falco-it"
$Project = "GMD"

# Test tracking
[System.Collections.ArrayList]$tests = @()

function Record-Test {
    param(
        [string]$Scenario,
        [bool]$Passed,
        [string]$Details
    )
    $null = $tests.Add([PSCustomObject]@{
        Scenario = $Scenario
        Passed   = $Passed
        Details  = $Details
    })
}

function Print-Summary {
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║ DETAILED AC TESTS - Story 2218: Markdown Export with State     ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    
    $passed = @($tests | Where-Object { $_.Passed }).Count
    $failed = @($tests | Where-Object { -not $_.Passed }).Count
    
    Write-Host "`nResults:" -ForegroundColor Yellow
    $tests | ForEach-Object {
        $status = if ($_.Passed) { "✓ PASS" } else { "✗ FAIL" }
        $color = if ($_.Passed) { "Green" } else { "Red" }
        Write-Host "  [$status] $($_.Scenario)" -ForegroundColor $color
        if ($_.Details) {
            Write-Host "         $($_.Details)" -ForegroundColor DarkGray
        }
    }
    
    Write-Host "`nTotal: $($tests.Count) tests | Passed: $passed | Failed: $failed" -ForegroundColor Cyan
    
    return $failed -eq 0
}

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "DETAILED AC TESTS - Story 2218: Export to Markdown with State" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

# Get PAT token
$pat = $env:GMD_AZDO_MACHINE_WORKITEMSRW | & 'C:\Dev\own\GDrive\Work\Dev\bbTooling\PowerShell\ssEncryptDecrypt.ps1' -Decrypt

# ============================================================================
# DETAILED AC SCENARIO 1: Export markdown includes State field
# ============================================================================
Write-Host "`n[DETAILED TEST 1] Markdown export includes State field in metadata" -ForegroundColor Yellow

try {
    # Get story hierarchy
    $hierarchy = & "$SRC_DIR/GetAzDoHierarchyForStory.ps1" `
        -Organization $Organization `
        -Project $Project `
        -StoryId 2218 `
        -PatToken $pat
    
    if ($null -eq $hierarchy) {
        throw "Failed to retrieve story hierarchy"
    }
    
    # Export to markdown
    $markdown = & "$SRC_DIR/ConvertHierarchyToMarkdown.ps1" `
        -Hierarchy $hierarchy `
        -Organization $Organization `
        -Project $Project
    
    if ($null -eq $markdown) {
        throw "ConvertHierarchyToMarkdown returned null"
    }
    
    # Verify State field is in the markdown
    if ($markdown -notmatch '\*\*State\*\*:') {
        throw "Markdown does not contain '**State**:' field"
    }
    
    # Extract the state value
    $stateLineMatch = [regex]::Match($markdown, '\*\*State\*\*:\s*(.+?)(\n|$)')
    if (-not $stateLineMatch.Success) {
        throw "Could not extract state value from markdown"
    }
    
    $exportedState = $stateLineMatch.Groups[1].Value.Trim()
    
    Record-Test -Scenario "✅ Detailed AC 1: State field in markdown 🧪 VerifyStateFieldInMarkdown" `
                -Passed $true `
                -Details "Exported markdown includes State: $exportedState"
    
    Write-Host "  ✓ PASSED: State field found in markdown export" -ForegroundColor Green
    Write-Host "    - Exported State: $exportedState" -ForegroundColor DarkGray
    Write-Host "    - Markdown includes '**State**:' metadata" -ForegroundColor DarkGray
    
} catch {
    Record-Test -Scenario "✅ Detailed AC 1: State field in markdown 🧪 VerifyStateFieldInMarkdown" `
                -Passed $false `
                -Details $_.Exception.Message
    Write-Host "  ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# DETAILED AC SCENARIO 2: Editable state has no warning
# ============================================================================
Write-Host "`n[DETAILED TEST 2] Editable state (in writableStates) has no warning comment" -ForegroundColor Yellow

try {
    # Get story hierarchy  
    $hierarchy = & "$SRC_DIR/GetAzDoHierarchyForStory.ps1" `
        -Organization $Organization `
        -Project $Project `
        -StoryId 2218 `
        -PatToken $pat
    
    $currentState = $hierarchy.State
    
    # Load configuration to check if state is writable
    $config = & "$SRC_DIR/LoadStateConfiguration.ps1" -Organization $Organization -Project $Project
    $writableStates = $config.writableStates.Story
    $isStateWritable = $writableStates -contains $currentState
    
    if (-not $isStateWritable) {
        throw "Story is not in a writable state ($currentState). Cannot test editable state scenario with this story. Writable states: $($writableStates -join ', ')"
    }
    
    # Export to markdown
    $markdown = & "$SRC_DIR/ConvertHierarchyToMarkdown.ps1" `
        -Hierarchy $hierarchy `
        -Organization $Organization `
        -Project $Project
    
    # Verify NO warning comment appears at the beginning (before the ### Story header)
    # Check that there's no "<!-- WARNING" comment before the story header
    $beforeStoryHeader = $markdown.Substring(0, $markdown.IndexOf('### Story')).Trim()
    
    if ($beforeStoryHeader -match '<!--\s*WARNING') {
        throw "Warning comment found for editable state (should not be present)"
    }
    
    # Verify state is NOT marked with ⚠️
    if ($markdown -match '\*\*State\*\*:.*⚠️.*read-only') {
        throw "State is marked as read-only but should be editable"
    }
    
    Record-Test -Scenario "✅ Detailed AC 2: No warning for editable state 🧪 VerifyEditableStateNoWarning" `
                -Passed $true `
                -Details "State '$currentState' is editable with no warning comment"
    
    Write-Host "  ✓ PASSED: Editable state has no warning" -ForegroundColor Green
    Write-Host "    - State: $currentState (writable)" -ForegroundColor DarkGray
    Write-Host "    - No WARNING comment" -ForegroundColor DarkGray
    Write-Host "    - State not marked as read-only" -ForegroundColor DarkGray
    
} catch {
    Record-Test -Scenario "✅ Detailed AC 2: No warning for editable state 🧪 VerifyEditableStateNoWarning" `
                -Passed $false `
                -Details $_.Exception.Message
    Write-Host "  ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# DETAILED AC SCENARIO 3: Non-editable state has warning comment
# ============================================================================
Write-Host "`n[DETAILED TEST 3] Non-editable state (NOT in writableStates) has warning comment" -ForegroundColor Yellow

try {
    # Create a mock hierarchy with a non-writable state
    # We'll simulate a story with "Closed" state
    
    $config = & "$SRC_DIR/LoadStateConfiguration.ps1" -Organization $Organization -Project $Project
    $writableStates = $config.writableStates.Story
    
    # Create a mock hierarchy object for testing
    $mockHierarchy = [PSCustomObject]@{
        Id = 9999
        Title = "Test Story with Non-Writable State"
        State = "Closed"  # Assuming this is not in writable states
        Description = "This is a test story"
        AcceptanceCriteria = $null
        ACScenarios = $null
        StoryPoints = 5
        Tags = "test"
        ExtraInformation = $null
        Tasks = @()
        Bugs = @()
    }
    
    # Verify Closed is NOT in writableStates
    if ($writableStates -contains "Closed") {
        throw "Test assumption failed: 'Closed' is actually writable for this organization. Cannot test non-writable scenario."
    }
    
    # Export to markdown
    $markdown = & "$SRC_DIR/ConvertHierarchyToMarkdown.ps1" `
        -Hierarchy $mockHierarchy `
        -Organization $Organization `
        -Project $Project
    
    # Verify WARNING comment appears BEFORE the story header
    if ($markdown -notmatch '<!--\s*WARNING') {
        throw "WARNING comment not found for non-writable state"
    }
    
    # Verify the warning mentions the state is not writable
    if ($markdown -notmatch 'State.*NOT in the writable states list') {
        throw "WARNING comment does not mention that state is not writable"
    }
    
    # Verify State is marked with ⚠️ (read-only)
    if ($markdown -notmatch '\*\*State\*\*:\s*Closed.*⚠️.*read-only') {
        throw "State not correctly marked as read-only"
    }
    
    Record-Test -Scenario "✅ Detailed AC 3: Warning for non-editable state 🧪 VerifyNonEditableStateWarning" `
                -Passed $true `
                -Details "State 'Closed' has appropriate warning comment and read-only marker"
    
    Write-Host "  ✓ PASSED: Non-writable state has warning comment" -ForegroundColor Green
    Write-Host "    - State: Closed (non-writable)" -ForegroundColor DarkGray
    Write-Host "    - WARNING comment included" -ForegroundColor DarkGray
    Write-Host "    - State marked with ⚠️ (read-only)" -ForegroundColor DarkGray
    Write-Host "    - Warning indicates state changes will be ignored" -ForegroundColor DarkGray
    
} catch {
    Record-Test -Scenario "✅ Detailed AC 3: Warning for non-editable state 🧪 VerifyNonEditableStateWarning" `
                -Passed $false `
                -Details $_.Exception.Message
    Write-Host "  ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# DETAILED AC SCENARIO 4: Export with incomplete configuration uses defaults
# ============================================================================
Write-Host "`n[DETAILED TEST 4] Export works with incomplete/missing configuration (defaults applied)" -ForegroundColor Yellow

try {
    # Get a story
    $hierarchy = & "$SRC_DIR/GetAzDoHierarchyForStory.ps1" `
        -Organization $Organization `
        -Project $Project `
        -StoryId 2218 `
        -PatToken $pat
    
    # Create a temp directory without config file
    $tempDir = New-Item -ItemType Directory -Path (Join-Path $env:TEMP "test-export-$(Get-Random)") -Force
    
    try {
        # Export using non-existent org/project (will use defaults)
        $markdown = & "$SRC_DIR/ConvertHierarchyToMarkdown.ps1" `
            -Hierarchy $hierarchy `
            -Organization "nonexistent-org" `
            -Project "nonexistent-project" `
            -RepositoryRoot $tempDir.FullName
        
        if ($null -eq $markdown) {
            throw "Export failed when configuration was missing"
        }
        
        # Verify markdown was generated successfully
        if ($markdown.Length -lt 50) {
            throw "Generated markdown is too short, likely incomplete"
        }
        
        # Verify State field is still present even with default config
        if ($markdown -notmatch '\*\*State\*\*:') {
            throw "State field not included when using default configuration"
        }
        
        Record-Test -Scenario "✅ Detailed AC 4: Export with defaults 🧪 VerifyExportWithDefaultConfig" `
                    -Passed $true `
                    -Details "Export successful with default configuration fallback"
        
        Write-Host "  ✓ PASSED: Export works with incomplete configuration" -ForegroundColor Green
        Write-Host "    - Defaults applied automatically" -ForegroundColor DarkGray
        Write-Host "    - State field included in output" -ForegroundColor DarkGray
        Write-Host "    - Export completed successfully" -ForegroundColor DarkGray
        
    } finally {
        Remove-Item $tempDir -Force -Recurse -ErrorAction SilentlyContinue
    }
    
} catch {
    Record-Test -Scenario "✅ Detailed AC 4: Export with defaults 🧪 VerifyExportWithDefaultConfig" `
                -Passed $false `
                -Details $_.Exception.Message
    Write-Host "  ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# Print summary and return exit code
# ============================================================================
$allPassed = Print-Summary
$exitCode = if ($allPassed) { 0 } else { 1 }
exit $exitCode
