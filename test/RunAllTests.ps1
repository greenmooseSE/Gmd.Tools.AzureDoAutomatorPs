<#
.SYNOPSIS
Master test runner for all Azure DevOps Automator scripts

.DESCRIPTION
Runs all integration and unit tests for the Azure DevOps Automator toolkit.
Tests can be run optionally with verbose output for debugging.

Requires Environment variables:
- GMD_AZDO_ORGANIZATION: Organization name (default: falco-it)
- GMD_AZDO_PROJECT: Project name (default: GMD)
- GMD_AZDO_MACHINE_WORKITEMSRW: Encrypted PAT token

Run with: pwsh -File .\RunAllTests.ps1

Exit codes:
- 0: All tests passed
- 1: One or more tests failed
#>

#Requires -Version 7.0

param(
    [string]$Organization = $env:GMD_AZDO_ORGANIZATION ?? 'falco-it',
    [string]$Project = $env:GMD_AZDO_PROJECT ?? 'GMD',
    [switch]$Verbose,
    [switch]$SkipBasicTests,
    [switch]$SkipGetAzDoUserStoryTests,
    [switch]$SkipUpdateAzDoUserStoryTests,
    [switch]$SkipGetAzDoHierarchyTests
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Test configuration
[string]$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
[string]$SRC_DIR = Join-Path $SCRIPT_DIR '../src'

# Test counters
[int]$totalTests = 0
[int]$totalPassed = 0
[int]$totalFailed = 0
[array]$testResults = @()

function Test-Script {
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$ScriptPath,
        [hashtable]$Arguments
    )

    $script:totalTests++
    Write-Host "`n" -ForegroundColor Cyan
    Write-Host "════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "Running: $Name" -ForegroundColor Cyan
    Write-Host "════════════════════════════════════════════════" -ForegroundColor Cyan

    try {
        $startTime = Get-Date
        
        if ($Verbose) {
            & $ScriptPath @Arguments
        }
        else {
            & $ScriptPath @Arguments 2>&1 | Where-Object { $_ -match '(PASSED|FAILED|Summary|Error|Exception)' }
        }
        
        $duration = (Get-Date) - $startTime
        $script:totalPassed++
        
        $result = @{
            Name = $Name
            Status = 'PASSED'
            Duration = $duration
        }
        
        Write-Host "`n✓ $Name PASSED (${duration}s)" -ForegroundColor Green
    }
    catch {
        $script:totalFailed++
        
        $result = @{
            Name = $Name
            Status = 'FAILED'
            Error = $_.Exception.Message
        }
        
        Write-Host "`n✗ $Name FAILED" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    $script:testResults += [PSObject]$result
}

# Main test execution
try {
    Write-Host "`n"
    Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║ Azure DevOps Automator - Master Test Runner    ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    Write-Host "`nConfiguration:" -ForegroundColor Cyan
    Write-Host "  Organization: $Organization"
    Write-Host "  Project: $Project"
    Write-Host "  Verbose: $Verbose"

    # Run BasicIntegrationTest
    if (-not $SkipBasicTests) {
        Test-Script -Name "BasicIntegrationTest" -ScriptPath "$SCRIPT_DIR/BasicIntegrationTest.ps1" -Arguments @{}
    }

    # Run GetAzDoUserStoryTest
    if (-not $SkipGetAzDoUserStoryTests) {
        Test-Script -Name "GetAzDoUserStoryTest" -ScriptPath "$SCRIPT_DIR/GetAzDoUserStoryTest.ps1" -Arguments @{
            Organization = $Organization
            Project = $Project
        }
    }

    # Run UpdateAzDoUserStoryTest
    if (-not $SkipUpdateAzDoUserStoryTests) {
        Test-Script -Name "UpdateAzDoUserStoryTest" -ScriptPath "$SCRIPT_DIR/UpdateAzDoUserStoryTest.ps1" -Arguments @{
            Organization = $Organization
            Project = $Project
        }
    }

    # Run GetAzDoHierarchyForEpicTest
    if (-not $SkipGetAzDoHierarchyTests) {
        Test-Script -Name "GetAzDoHierarchyForEpicTest" -ScriptPath "$SCRIPT_DIR/GetAzDoHierarchyForEpicTest.ps1" -Arguments @{
            Organization = $Organization
            Project = $Project
        }
    }

    # Print summary
    Write-Host "`n`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║ Test Execution Summary                         ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    Write-Host "`nResults:"
    Write-Host "  Total Tests: $totalTests" -ForegroundColor Cyan
    Write-Host "  Passed: $totalPassed" -ForegroundColor Green
    Write-Host "  Failed: $totalFailed" -ForegroundColor $(if ($totalFailed -eq 0) { 'Green' } else { 'Red' })

    if ($totalTests -gt 0) {
        $passPercentage = [Math]::Round(($totalPassed / $totalTests) * 100, 2)
        Write-Host "  Pass Rate: $passPercentage%" -ForegroundColor $(if ($passPercentage -eq 100) { 'Green' } else { 'Yellow' })
    }

    # Detailed results
    if ($testResults.Count -gt 0) {
        Write-Host "`nDetailed Results:" -ForegroundColor Cyan
        foreach ($result in $testResults) {
            $statusColor = if ($result.Status -eq 'PASSED') { 'Green' } else { 'Red' }
            Write-Host "  [$($result.Status)] $($result.Name)" -ForegroundColor $statusColor
            if ($result.Error) {
                Write-Host "    Error: $($result.Error)" -ForegroundColor Red
            }
        }
    }

    Write-Host "`n"
    
    # Exit with appropriate code
    if ($totalFailed -gt 0) {
        exit 1
    }
    else {
        exit 0
    }
}
catch {
    Write-Host "`nFATAL ERROR: $_" -ForegroundColor Red
    Write-Host "Exception: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
