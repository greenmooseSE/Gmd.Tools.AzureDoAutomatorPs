#!/usr/bin/env pwsh
<#
.SYNOPSIS
Verification script showing the description parsing bug fix works
.DESCRIPTION
This script:
1. Creates a markdown file with descriptions (no colons) - the format that was failing
2. Parses it with the fixed parser
3. Verifies descriptions are now recognized
.NOTES
Demonstrates the fix for: Parser now recognizes **Description** without colons
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Mock ssLogIt if needed
if (-not (Get-Command 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    function ssLogIt.ps1 { param([string]$Level, [string]$Message, [object]$Exception) }
}

$testDir = $PSScriptRoot
$srcDir = Join-Path $PSScriptRoot '../src'

# Create test markdown with descriptions (no colons)
$testMarkdown = @"
# Epic: Test Epic For Descriptions
**tags**: regression, fix
**Description**
This epic tests that descriptions without colons are properly recognized by the parser

## Feature: User Management
**tags**: feature, user-facing
**Description**
Feature that manages user accounts and permissions

### Story: User Registration
**tags**: user-facing, security
**SP**: 5
**Description**
Implement user self-registration with email verification

#### Acceptance Criteria
- [ ] User can register with email
- [ ] Verification email is sent
- [ ] Account activated after verification

#### AC Scenarios
1. **Scenario**: Valid registration
   Given user enters valid email
   When registration form is submitted
   Then account is created in pending state

2. **Scenario**: Duplicate email
   Given email already registered
   When form submission is attempted
   Then error message shown

#### Extra Information
- Use SendGrid for email
- Implement rate limiting
"@

Write-Host "=" * 70
Write-Host "Testing Description Parser Fix" -ForegroundColor Cyan
Write-Host "=" * 70

# Create temp test file
$testFile = [System.IO.Path]::GetTempFileName() + ".md"
$testMarkdown | Set-Content -LiteralPath $testFile -Force

Write-Host "`nCreated test markdown at: $testFile" -ForegroundColor Yellow
Write-Host "`nTest markdown format uses **Description** WITHOUT colons"
Write-Host "`nParsing with fixed regex pattern: '^\*\*Description\*\*:?\s*(.*)$'"

try {
    # Parse the markdown
    $result = & (Join-Path $srcDir 'ConvertMarkdownToHierarchyJson.ps1') -MarkdownFilePath $testFile
    
    Write-Host "`n" + "=" * 70
    Write-Host "RESULTS" -ForegroundColor Green
    Write-Host "=" * 70
    
    # Epic
    $epic = $result.epics[0]
    Write-Host "`nEpic: $($epic.title)"
    Write-Host "  Tags: $($epic.tags -join ', ')"
    Write-Host "  Description: $($epic.description)" -ForegroundColor Green
    
    if ([string]::IsNullOrEmpty($epic.description)) {
        Write-Host "  ❌ FAILED: Description is null/empty (BUG NOT FIXED)" -ForegroundColor Red
        exit 1
    } else {
        Write-Host "  ✓ PASSED: Description recognized" -ForegroundColor Green
    }
    
    # Feature
    $feature = $epic.features[0]
    Write-Host "`nFeature: $($feature.title)"
    Write-Host "  Tags: $($feature.tags -join ', ')"
    Write-Host "  Description: $($feature.description)" -ForegroundColor Green
    
    if ([string]::IsNullOrEmpty($feature.description)) {
        Write-Host "  ❌ FAILED: Description is null/empty" -ForegroundColor Red
        exit 1
    } else {
        Write-Host "  ✓ PASSED: Description recognized" -ForegroundColor Green
    }
    
    # Story
    if ($feature.stories -and $feature.stories.Count -gt 0) {
        $story = $feature.stories[0]
        Write-Host "`nStory: $($story.title)"  
        Write-Host "  Tags: $($story.tags -join ', ')"
        Write-Host "  Story Points: $($story.storyPoints)"
        Write-Host "  Description: $($story.description)" -ForegroundColor Green
        
        if ([string]::IsNullOrEmpty($story.description)) {
            Write-Host "  ❌ FAILED: Description is null/empty" -ForegroundColor Red
            exit 1
        } else {
            Write-Host "  ✓ PASSED: Description recognized" -ForegroundColor Green
        }
        
        # Acceptance Criteria
        if ($story.acceptanceCriteria) {
            Write-Host "`n  Acceptance Criteria items: $($story.acceptanceCriteria.Split([Environment]::NewLine).Count)"
        }
        if ($story.acScenarios) {
            Write-Host "  AC Scenarios items: $($story.acScenarios.Split([Environment]::NewLine).Count)"
        }
        if ($story.extraInformation) {
            Write-Host "  Extra Information: $($story.extraInformation.Split([Environment]::NewLine).Count)"
        }
    }
    
    Write-Host "`n" + "=" * 70
    Write-Host "Status: ALL TESTS PASSED ✓" -ForegroundColor Green
    Write-Host "=" * 70
    Write-Host "`nThe parser now correctly recognizes descriptions WITHOUT colons."
    Write-Host "The fix: Changed regex to make colon optional: '^\*\*Description\*\*:?\s*(.*)$'"
    
} finally {
    Remove-Item -LiteralPath $testFile -Force -ErrorAction SilentlyContinue
}
