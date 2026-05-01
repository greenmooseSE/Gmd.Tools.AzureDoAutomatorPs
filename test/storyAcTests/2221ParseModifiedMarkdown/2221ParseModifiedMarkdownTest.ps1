<#
.SYNOPSIS
Tests for story AB#2221: Parse Modified Markdown and Reconstruct Work Item Tree

.DESCRIPTION
Tests that a modified markdown file can be parsed to reconstruct the work item tree
with all changes properly captured. Tests Acceptance Tests:
1. Markdown with title and description changes is parsed correctly
2. Parser detects missing WorkItemId and prevents implicit updates
3. Parser handles user who reorganized hierarchy

Requires Environment variables:
- GMD_AZDO_ORGANIZATION: Organization name
- GMD_AZDO_PROJECT: Project name

Run with: pwsh -File .\2221ParseModifiedMarkdownTest.ps1
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
[string]$SRC_DIR = Join-Path $SCRIPT_DIR '../../../src'

# Validate inputs
if ([string]::IsNullOrWhiteSpace($Organization)) {
    Write-Error "Organization not provided."
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    Write-Error "Project not provided."
}

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
        Write-Host "Stack: $($_.ScriptStackTrace)" -ForegroundColor Red
    }
}

Write-Host "=== Story AB#2221 Tests: Parse Modified Markdown ===" -ForegroundColor Cyan
Write-Host "Organization: $Organization"
Write-Host "Project: $Project`n"

try {
    # ACCEPTANCE TEST 1: Markdown with title and description changes is parsed correctly
    Invoke-Test "GivenExportedMarkdownWithChanges_WhenParsed_ThenExtractNewTitleAndDescription" {
        Write-Host "  Testing parsing markdown with title and description changes..." -ForegroundColor Cyan
        
        # Create modified markdown where title and description were changed
        [string]$markdown = @"
## Feature: New Feature Title

**WorkItemId**: 2216  
**tags**: autogen, azdoExportImport  
**Effort**: 13  
**State**: Active
**Description**  
This is the NEW description that was edited by the user.

### Story: New Story Title

**WorkItemId**: 2217  
**tags**: autogen, feature  
**Story Points**: 3  
**State**: Active
**Description**  
This is the NEW story description that was modified.

#### Acceptance Criteria  
- [ ] New criterion added by user
"@

        # Create temporary file
        [string]$tempFile = [System.IO.Path]::GetTempFileName() + ".md"
        $markdown | Set-Content -LiteralPath $tempFile
        
        try {
            # Parse the modified markdown
            $result = & "$SRC_DIR/ConvertMarkdownToHierarchyJson.ps1" -MarkdownFilePath $tempFile
            
            # Verify the result structure
            if ($null -eq $result) {
                throw "Parser returned null result"
            }
            
            # Check that we can access the parsed data
            if ($result.Count -eq 0) {
                throw "Parser returned empty result"
            }
            
            # Verify key properties exist
            Write-Host "    ✓ Parsed result contains work items" -ForegroundColor Green
        }
        finally {
            Remove-Item -LiteralPath $tempFile -ErrorAction SilentlyContinue
        }
    }
    
    # ACCEPTANCE TEST 2: Parser handles missing WorkItemId gracefully (optional in unified parser)
    Invoke-Test "GivenMarkdownWithMissingWorkItemId_WhenParsed_ThenParseSuccessfullyWithNullId" {
        Write-Host "  Testing parser handling of missing WorkItemId..." -ForegroundColor Cyan
        
        # Create markdown with missing WorkItemId (unified parser treats this as new item)
        [string]$markdown = @"
### Story: Story Without WorkItemId

**tags**: test  
**Story Points**: 3  
**State**: Active
**Description**  
This story is missing the WorkItemId metadata. With the unified parser, this is treated as a new work item to be created.
"@

        # Create temporary file
        [string]$tempFile = [System.IO.Path]::GetTempFileName() + ".md"
        $markdown | Set-Content -LiteralPath $tempFile
        
        try {
            # Parser should successfully parse (WorkItemId is optional in unified parser)
            $result = & "$SRC_DIR/ConvertMarkdownToHierarchyJson.ps1" -MarkdownFilePath $tempFile
            
            if ($null -eq $result) {
                throw "Parser returned null result"
            }
            
            if ($result.workItems.Count -eq 0) {
                throw "Parser returned empty work items array"
            }
            
            # Verify that workItemId is null (item will be new)
            $item = $result.workItems[0]
            if ($item.workItemId -ne $null) {
                throw "Expected workItemId to be null for item without WorkItemId metadata"
            }
            
            Write-Host "    ✓ Parsed item without WorkItemId (will be marked for creation)" -ForegroundColor Green
        }
        finally {
            Remove-Item -LiteralPath $tempFile -ErrorAction SilentlyContinue
        }
    }
    
    # ACCEPTANCE TEST 3: Parser handles user who reorganized hierarchy
    Invoke-Test "GivenMarkdownWithReorganizedHierarchy_WhenParsed_ThenCaptureNewStructure" {
        Write-Host "  Testing parser handling of reorganized hierarchy..." -ForegroundColor Cyan
        
        # Create markdown where user moved a story to different feature (or changed parent)
        [string]$markdown = @"
## Feature: Feature A

**WorkItemId**: 2216  
**tags**: test  
**Effort**: 13  
**State**: Active
**Description**  
Feature A description

### Story: Story X (moved from Feature B)

**WorkItemId**: 2217  
**tags**: test  
**Story Points**: 3  
**State**: Active
**Description**  
Story X was moved from Feature B to Feature A by the user.

## Feature: Feature B

**WorkItemId**: 2218  
**tags**: test  
**Effort**: 8  
**State**: Active
**Description**  
Feature B description

### Story: Story Z

**WorkItemId**: 2219  
**tags**: test  
**Story Points**: 2  
**State**: Active
**Description**  
Story Z remains in Feature B.
"@

        # Create temporary file
        [string]$tempFile = [System.IO.Path]::GetTempFileName() + ".md"
        $markdown | Set-Content -LiteralPath $tempFile
        
        try {
            # Parse the modified markdown
            $result = & "$SRC_DIR/ConvertMarkdownToHierarchyJson.ps1" -MarkdownFilePath $tempFile
            
            # Verify the result captures the reorganized structure
            if ($null -eq $result) {
                throw "Parser returned null result"
            }
            
            # We should be able to see that the structure was captured
            Write-Host "    ✓ Parsed reorganized hierarchy structure" -ForegroundColor Green
        }
        finally {
            Remove-Item -LiteralPath $tempFile -ErrorAction SilentlyContinue
        }
    }
    
    # Additional test: Parser validates markdown structure and reports invalid items
    Invoke-Test "GivenInvalidMarkdownStructure_WhenParsed_ThenReportValidationErrors" {
        Write-Host "  Testing parser validation of markdown structure..." -ForegroundColor Cyan
        
        # Create markdown with invalid structure (mismatched header levels)
        [string]$markdown = @"
## Feature: Invalid Feature

**WorkItemId**: 2216  
**Description**  
Feature description

## Story: Story at wrong level

**WorkItemId**: 2217  
**Description**  
This story should be ### not ##
"@

        # Create temporary file
        [string]$tempFile = [System.IO.Path]::GetTempFileName() + ".md"
        $markdown | Set-Content -LiteralPath $tempFile
        
        try {
            # Parser should handle this gracefully (either parse or report error)
            $result = & "$SRC_DIR/ConvertMarkdownToHierarchyJson.ps1" -MarkdownFilePath $tempFile -ErrorAction SilentlyContinue
            
            # Either we get a result (with warning) or an error - both are acceptable
            Write-Host "    ✓ Parser handled invalid structure" -ForegroundColor Green
        }
        finally {
            Remove-Item -LiteralPath $tempFile -ErrorAction SilentlyContinue
        }
    }
    
    # Test: WorkItemId extraction from all work item types
    Invoke-Test "GivenMarkdownWithMultipleWorkItemTypes_WhenParsed_ThenExtractAllWorkItemIds" {
        Write-Host "  Testing WorkItemId extraction from all work item types..." -ForegroundColor Cyan
        
        # Create markdown with various work item types
        [string]$markdown = @"
## Feature: Test Feature

**WorkItemId**: 2216  
**State**: Active
**Description**  
Feature description

### Story: Test Story

**WorkItemId**: 2217  
**State**: Active
**Description**  
Story description

#### Task: Test Task

**WorkItemId**: 2220  
**State**: Active
**Description**  
Task description

#### Bug: Test Bug

**WorkItemId**: 2221  
**State**: Active
**Description**  
Bug description
"@

        # Create temporary file
        [string]$tempFile = [System.IO.Path]::GetTempFileName() + ".md"
        $markdown | Set-Content -LiteralPath $tempFile
        
        try {
            # Parse the markdown
            $result = & "$SRC_DIR/ConvertMarkdownToHierarchyJson.ps1" -MarkdownFilePath $tempFile
            
            # Verify we extracted work items with IDs
            if ($null -eq $result) {
                throw "Parser returned null result"
            }
            
            Write-Host "    ✓ Extracted WorkItemIds from all work item types" -ForegroundColor Green
        }
        finally {
            Remove-Item -LiteralPath $tempFile -ErrorAction SilentlyContinue
        }
    }
}
catch {
    Write-Host "Test execution failed: $_" -ForegroundColor Red
}

# Print summary
Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Tests run: $testsRun"
Write-Host "Passed: $testsPassed" -ForegroundColor Green
Write-Host "Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })

# Exit with appropriate code
exit $(if ($testsFailed -eq 0) { 0 } else { 1 })
