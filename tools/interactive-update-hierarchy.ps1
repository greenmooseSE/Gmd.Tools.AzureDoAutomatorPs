<#
.SYNOPSIS
Interactive script for safely updating work item hierarchy in Azure DevOps

.DESCRIPTION
Provides a guided workflow to:
1. Export current hierarchy from Azure DevOps
2. Modify hierarchy via markdown
3. Preview changes before applying
4. Apply changes with user confirmation

This script implements the "Update Hierarchy Structure in Azure DevOps" recipe correctly
with proper validation, preview, and safety confirmations.

.PARAMETER Organization
Azure DevOps organization name (e.g., "falco-it")

.PARAMETER Project
Azure DevOps project name (e.g., "GMD")

.PARAMETER EpicId
Epic ID to export and modify. Required if not using -FeatureId or -StoryId

.PARAMETER FeatureId
Feature ID to export and modify (optional alternative to EpicId)

.PARAMETER StoryId
Story ID to export and modify (optional alternative to EpicId)

.PARAMETER MarkdownFile
Path to markdown file with modifications. If not provided, exports and opens in editor.

.PARAMETER SkipEditor
If specified, won't open markdown file in editor (useful for automated workflows)

.PARAMETER OriginalMarkdownPath
Path to existing original hierarchy markdown file. If provided, skips fetching from Azure DevOps.
Useful for iterating on changes without repeated API calls.

.PARAMETER RunAsDebug
If specified, runs in debug mode: performs all steps but stops after preview without applying changes.
Also skips user confirmation prompt. Useful for testing and validation.

.PARAMETER RepositoryRoot
Root directory for state configuration. Default: current working directory.

.EXAMPLE
.\interactive-update-hierarchy.ps1 -Organization "falco-it" -Project "GMD" -EpicId 1577

# Exports Epic 1577, opens in editor, then guides through preview and apply

.EXAMPLE
.\interactive-update-hierarchy.ps1 -Organization "falco-it" -Project "GMD" -EpicId 1577 -MarkdownFile "./hierarchy-modified.md" -SkipEditor

# Imports specific modified markdown and applies changes

.NOTES
Requires:
- GetAzDoHierarchyForEpic.ps1, GetAzDoHierarchyForFeature.ps1, GetAzDoHierarchyForStory.ps1
- ConvertHierarchyToMarkdown.ps1
- ConvertMarkdownToHierarchyJson.ps1
- DetectHierarchyChanges.ps1
- ApplyValidatedChanges.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Organization,
    
    [Parameter(Mandatory = $true)]
    [string] $Project,
    
    [Parameter(Mandatory = $false)]
    [int] $EpicId,
    
    [Parameter(Mandatory = $false)]
    [int] $FeatureId,
    
    [Parameter(Mandatory = $false)]
    [int] $StoryId,
    
    [Parameter(Mandatory = $false)]
    [string] $MarkdownFile,
    
    [Parameter(Mandatory = $false)]
    [switch] $SkipEditor,
    
    [Parameter(Mandatory = $false)]
    [string] $OriginalMarkdownPath,
    
    [Parameter(Mandatory = $false)]
    [switch] $RunAsDebug,
    
    [Parameter(Mandatory = $false)]
    [string] $RepositoryRoot = $PWD
)

Set-StrictMode -Version 3
$ErrorActionPreference = 'Stop'

# Save current location for restoration
$originalLocation = Get-Location

# Validate that src directory exists
$srcPath = Join-Path $RepositoryRoot "src"
if (-not (Test-Path $srcPath)) {
    throw "Source directory not found: $srcPath"
}

# Get full path of markdown file if provided
if ($MarkdownFile) {
    [string]$MarkdownFile = Resolve-Path $MarkdownFile;
}

# Get full path of original markdown if provided
if ($OriginalMarkdownPath) {
    [string]$OriginalMarkdownPath = Resolve-Path $OriginalMarkdownPath;
}

# Validate parameters
$itemType = $null
$itemId = $null

if ($EpicId -gt 0) {
    $itemType = "Epic"
    $itemId = $EpicId
}
elseif ($FeatureId -gt 0) {
    $itemType = "Feature"
    $itemId = $FeatureId
}
elseif ($StoryId -gt 0) {
    $itemType = "Story"
    $itemId = $StoryId
}
else {
    throw "Must specify one of: -EpicId, -FeatureId, or -StoryId"
}

Write-Host "`n========== Azure DevOps Hierarchy Update ==========" -ForegroundColor Cyan
Write-Host "Organization: $Organization" -ForegroundColor Gray
Write-Host "Project: $Project" -ForegroundColor Gray
Write-Host "$itemType ID: $itemId" -ForegroundColor Gray
Write-Host "================================================`n" -ForegroundColor Cyan

try {
    Push-Location $srcPath
    # ============================================
    # STEP 1: Export or Load Original Hierarchy
    # ============================================
    if ($OriginalMarkdownPath) {
        Write-Host "STEP 1: Loading original hierarchy from markdown..." -ForegroundColor Yellow
        
        if (-not (Test-Path $OriginalMarkdownPath)) {
            throw "Original markdown file not found: $OriginalMarkdownPath"
        }
        
        $originalMarkdown = Get-Content $OriginalMarkdownPath -Raw
        Write-Host "✓ Loaded original hierarchy from: $OriginalMarkdownPath" -ForegroundColor Green
    }
    else {
        Write-Host "STEP 1: Exporting original $itemType hierarchy from Azure DevOps..." -ForegroundColor Yellow
        
        $originalHierarchy = switch ($itemType) {
            "Epic" {
                & .\GetAzDoHierarchyForEpic.ps1 -Organization $Organization -Project $Project -EpicId $itemId
            }
            "Feature" {
                & .\GetAzDoHierarchyForFeature.ps1 -Organization $Organization -Project $Project -FeatureId $itemId
            }
            "Story" {
                & .\GetAzDoHierarchyForStory.ps1 -Organization $Organization -Project $Project -StoryId $itemId
            }
        }
        
        if (-not $originalHierarchy) {
            throw "Failed to export hierarchy. $itemType ID $itemId may not exist."
        }
        
        Write-Host "✓ Successfully exported hierarchy" -ForegroundColor Green
    }
    
    # ============================================
    # STEP 2: Convert Original Hierarchy to Markdown (if needed)
    # ============================================
    if (-not $OriginalMarkdownPath) {
        Write-Host "`nSTEP 2: Converting original hierarchy to Markdown..." -ForegroundColor Yellow
        
        $originalMarkdown = & .\ConvertHierarchyToMarkdown.ps1 `
            -Hierarchy $originalHierarchy `
            -Organization $Organization `
            -Project $Project
        
        # Save original for reference
        $exportPath = Join-Path $RepositoryRoot "hierarchy-export-original.md"
        $originalMarkdown | Out-File $exportPath -Encoding UTF8
        Write-Host "✓ Original exported to: $exportPath" -ForegroundColor Green
    }
    else {
        Write-Host "`nSTEP 2: Skipping markdown conversion (using provided original)" -ForegroundColor Gray
    }
    
    # Convert original markdown to JSON for comparison
    Write-Host "`nConverting original to JSON format..." -ForegroundColor Gray
    $originalJsObject = & .\ConvertMarkdownToHierarchyJson.ps1 `
        -MarkdownContent $originalMarkdown
    
    if (-not $originalJsObject) {
        throw "Failed to convert original hierarchy to JSON format."
    }
    
    # ============================================
    # STEP 3: Get Modified Markdown
    # ============================================
    Write-Host "`nSTEP 3: Getting modified hierarchy..." -ForegroundColor Yellow
    
    if ([string]::IsNullOrEmpty($MarkdownFile)) {
        # Export template for editing
        $workFile = Join-Path $RepositoryRoot "hierarchy-export-work.md"
        $originalMarkdown | Out-File $workFile -Encoding UTF8
        
        if (-not $SkipEditor) {
            Write-Host "Opening markdown file in editor for modification..." -ForegroundColor Cyan
            Write-Host "File: $workFile" -ForegroundColor Gray
            Write-Host "`nInstructions:" -ForegroundColor Yellow
            Write-Host "1. Edit the hierarchy structure as needed" -ForegroundColor Gray
            Write-Host "2. You can move stories to different features" -ForegroundColor Gray
            Write-Host "3. You can reorder work items" -ForegroundColor Gray
            Write-Host "4. DO NOT change WorkItemId values" -ForegroundColor DarkYellow
            Write-Host "5. Save and close the editor when done" -ForegroundColor Gray
            Write-Host "`nPress any key to open editor..." -ForegroundColor Yellow
            $null = $Host.UI.RawUserInterface.ReadKey("NoEcho,IncludeKeyDown")
            
            Invoke-Item $workFile  # Open with default editor
            
            Write-Host "`nPress any key when you've finished editing..." -ForegroundColor Yellow
            $null = $Host.UI.RawUserInterface.ReadKey("NoEcho,IncludeKeyDown")
        }
        
        $MarkdownFile = $workFile
    }
    
    if (-not (Test-Path $MarkdownFile)) {
        throw "Markdown file not found: $MarkdownFile"
    }
    
    $modifiedMarkdown = Get-Content $MarkdownFile -Raw
    Write-Host "✓ Loaded modified hierarchy from: $MarkdownFile" -ForegroundColor Green
    
    # ============================================
    # STEP 4: Convert Modified Markdown to JSON
    # ============================================
    Write-Host "`nSTEP 4: Parsing modified hierarchy..." -ForegroundColor Yellow
    
    $modifiedHierarchy = & .\ConvertMarkdownToHierarchyJson.ps1 `
        -MarkdownContent $modifiedMarkdown
    
    if (-not $modifiedHierarchy) {
        throw "Failed to parse modified hierarchy. Check markdown format."
    }
    
    Write-Host "✓ Successfully parsed modified hierarchy" -ForegroundColor Green
    
    # ============================================
    # STEP 5: Detect Changes
    # ============================================
    Write-Host "`nSTEP 5: Detecting differences..." -ForegroundColor Yellow
    
    $diff = & .\DetectHierarchyChanges.ps1 `
        -OriginalHierarchy $originalJsObject `
        -ModifiedHierarchy $modifiedHierarchy
    
    if (-not $diff.validationPassed) {
        Write-Host "✗ Validation failed:" -ForegroundColor Red
        $diff.errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        throw "Cannot apply changes due to validation errors."
    }
    
    if ($diff.warnings.Count -gt 0) {
        Write-Host "⚠ Warnings:" -ForegroundColor Yellow
        $diff.warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    }
    
    Write-Host "✓ Diff validation passed" -ForegroundColor Green
    
    if ($diff.operations.Count -eq 0) {
        Write-Host "`n! No changes detected. Original and modified hierarchies are identical." -ForegroundColor Cyan
        return
    }
    
    Write-Host "`nDetected $($diff.operations.Count) operation(s) to apply" -ForegroundColor Green
    
    # ============================================
    # STEP 6: Preview Changes (DRY RUN)
    # ============================================
    Write-Host "`nSTEP 6: Previewing changes (DRY RUN)..." -ForegroundColor Yellow
    
    $preview = & .\ApplyValidatedChanges.ps1 `
        -ValidatedDiff $diff `
        -DryRun:$true
    
    Write-Host "`n📋 PREVIEW OF CHANGES:`n" -ForegroundColor Cyan
    
    if ($preview.operationsSummary.Count -gt 0) {
        $preview.operationsSummary | Format-Table @(
            @{ Label = "Type"; Expression = { $_.operationType }; Width = 12 },
            @{ Label = "Item"; Expression = { $_.title }; Width = 40 },
            @{ Label = "ID"; Expression = { $_.itemId }; Width = 8 },
            @{ Label = "Status"; Expression = { $_.status }; Width = 15 }
        ) -AutoSize
    }
    
    Write-Host "`nSummary:" -ForegroundColor Gray
    $operationSummary = $preview.operationsSummary | Group-Object operationType | Select-Object @(
        @{ Label = "Operation"; Expression = { $_.Name } },
        @{ Label = "Count"; Expression = { $_.Count } }
    )
    $operationSummary | Format-Table -AutoSize
    
    # ============================================
    # STEP 7: User Confirmation
    # ============================================
    Write-Host "`n" -ForegroundColor Yellow
    Write-Host "⚠️  IMPORTANT: Review the changes above carefully!" -ForegroundColor Yellow
    Write-Host ""
    
    if ($RunAsDebug) {
        Write-Host "🔍 DEBUG MODE: Stopping after preview without applying changes" -ForegroundColor Cyan
        Write-Host "Remove -RunAsDebug parameter to apply changes." -ForegroundColor Gray
        return
    }
    
    $proceed = Read-Host "Do you want to apply these changes to Azure DevOps? (yes/no)"
    
    if ($proceed -ne "yes") {
        Write-Host "`n✗ Cancelled. No changes applied." -ForegroundColor Yellow
        return
    }
    
    # ============================================
    # STEP 8: Apply Changes
    # ============================================
    Write-Host "`nSTEP 7: Applying changes to Azure DevOps..." -ForegroundColor Yellow
    
    $result = & .\ApplyValidatedChanges.ps1 `
        -ValidatedDiff $diff `
        -DryRun:$false
    
    Write-Host "`n✓ Changes applied successfully!" -ForegroundColor Green
    
    Write-Host "`nResults:" -ForegroundColor Gray
    $result.operationsSummary | Format-Table @(
        @{ Label = "Type"; Expression = { $_.operationType }; Width = 12 },
        @{ Label = "Item"; Expression = { $_.itemTitle }; Width = 40 },
        @{ Label = "Result"; Expression = { $_.result }; Width = 20 }
    ) -AutoSize
    
    Write-Host "`n========== Update Complete ==========" -ForegroundColor Cyan
    Write-Host "Total operations: $($result.operationsSummary.Count)" -ForegroundColor Green
    Write-Host "====================================`n" -ForegroundColor Cyan
}
catch {
    Write-Host "`n✗ ERROR: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    exit 1
}
finally {
    Pop-Location
}
