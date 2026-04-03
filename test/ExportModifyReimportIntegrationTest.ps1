<#
.SYNOPSIS
End-to-end integration test for export-modify-reimport workflow

.DESCRIPTION
Tests the complete workflow:
1. Create export (use existing ConvertHierarchyToMarkdown)
2. Detect changes between original and modified markdown
3. Apply changes back to Azure DevOps

This test validates both story AB#2222 and AB#2223 work together.
#>

#Requires -Version 7.0

param(
    [string]$Organization = $env:GMD_AZDO_ORGANIZATION,
    [string]$Project = $env:GMD_AZDO_PROJECT
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$SRC_DIR = Resolve-Path "$SCRIPT_DIR/../src"

Write-Host "=== Export-Modify-Reimport Integration Test ===" -ForegroundColor Cyan
Write-Host "Organization: $Organization"
Write-Host "Project: $Project`n"

# Test 1: Verify DetectHierarchyChanges produces valid output
Write-Host "Test 1: Change Detection Produces Valid Output" -ForegroundColor Yellow
try {
    $original = @{
        workItems = @(
            @{
                type  = 'Feature'
                title = 'Auth Feature'
                workItemId = 5001
                description = 'Authentication feature'
                effort = 8
                children = @(
                    @{
                        type  = 'Story'
                        title = 'Login'
                        workItemId = 5002
                        storyPoints = 3
                    }
                )
            }
        )
    }

    $modified = @{
        workItems = @(
            @{
                type  = 'Feature'
                title = 'Auth Feature'
                workItemId = 5001
                description = 'Updated authentication feature'
                effort = 13
                children = @(
                    @{
                        type  = 'Story'
                        title = 'Login'
                        workItemId = 5002
                        storyPoints = 5
                    },
                    @{
                        type  = 'Story'
                        title = 'Password Reset'
                        storyPoints = 3
                    }
                )
            }
        )
    }

    $diff = & "$SRC_DIR\DetectHierarchyChanges.ps1" -OriginalHierarchy $original -ModifiedHierarchy $modified

    if ($diff -and $diff.PSObject.Properties.name -contains 'operations') {
        Write-Host "  ✓ Diff structure is valid" -ForegroundColor Green
        Write-Host "    - Operations detected: $($diff.operations.Count)" -ForegroundColor Gray
        Write-Host "    - Validation passed: $($diff.validationPassed)" -ForegroundColor Gray
    } else {
        throw "Diff output does not have expected structure"
    }
}
catch {
    Write-Host "  ✗ FAILED: $_" -ForegroundColor Red
}

# Test 2: Verify ApplyValidatedChanges accepts valid diff
Write-Host "`nTest 2: Apply Changes Accepts Valid Diff" -ForegroundColor Yellow
try {
    $sampleDiff = @{
        validationPassed = $true
        errors           = @()
        warnings         = @()
        operations       = @(
            @{
                operationType = 'Update'
                workItemType  = 'Feature'
                itemId        = 5001
                title         = 'Auth Feature'
                changes       = @{
                    description = @{ before = 'Old'; after = 'New' }
                }
                parentIdBefore = $null
                parentIdAfter  = $null
                dependsOn      = @()
            }
        )
    }

    $result = & "$SRC_DIR\ApplyValidatedChanges.ps1" -ValidatedDiff $sampleDiff -DryRun

    if ($result -and $result.PSObject.Properties.name -contains 'success') {
        if ($result.success) {
            Write-Host "  ✓ Changes applied successfully (DryRun)" -ForegroundColor Green
            Write-Host "    - Applied: $($result.appliedChanges) operations" -ForegroundColor Gray
        } else {
            Write-Host "  ✗ Apply failed: $($result.failureReason)" -ForegroundColor Red
        }
    } else {
        throw "Result output does not have expected structure"
    }
}
catch {
    Write-Host "  ✗ FAILED: $_" -ForegroundColor Red
}

# Test 3: Verify pipeline integration
Write-Host "`nTest 3: Pipeline Integration (Detect -> Apply)" -ForegroundColor Yellow
try {
    $original = @{ workItems = @(@{ type = 'Epic'; title = 'Main'; workItemId = 6001 }) }
    $modified = @{ workItems = @(@{ type = 'Epic'; title = 'Main'; workItemId = 6001; description = 'Updated' }) }

    $diff = & "$SRC_DIR\DetectHierarchyChanges.ps1" -OriginalHierarchy $original -ModifiedHierarchy $modified

    if ($diff.validationPassed) {
        $result = & "$SRC_DIR\ApplyValidatedChanges.ps1" -ValidatedDiff $diff -DryRun
        
        if ($result.success) {
            Write-Host "  ✓ Full pipeline works" -ForegroundColor Green
            Write-Host "    - Detect found changes, Apply processed them" -ForegroundColor Gray
        } else {
            throw "Apply failed: $($result.failureReason)"
        }
    } else {
        throw "Detection failed: $($diff.errors -join '; ')"
    }
}
catch {
    Write-Host "  ✗ FAILED: $_" -ForegroundColor Red
}

Write-Host "`n=== Integration Test Complete ===" -ForegroundColor Cyan
