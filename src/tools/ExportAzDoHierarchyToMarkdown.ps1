<#
.SYNOPSIS
Export an Azure DevOps hierarchy to a markdown file for local comparison and review.

.DESCRIPTION
Downloads a complete Epic, Feature, or Story hierarchy from Azure DevOps and saves it
as a markdown file. Designed for use with diff tools to compare a local markdown plan
with the current state in Azure DevOps.

Typical workflow:
  1. Export current AzDo state: .\src\tools\ExportAzDoHierarchyToMarkdown.ps1 -EpicId 2535 -OutputFile azDoEpic.md
  2. Sort both for clean comparison: .\src\tools\SortMarkdownHierarchy.ps1 -MarkdownFile testEpic.md -MarkdownFile2 azDoEpic.md
  3. Diff the sorted versions: code --diff testEpic-sorted.md azDoEpic-sorted.md

.PARAMETER Organization
Azure DevOps organization name. Falls back to GMD_AZDO_ORGANIZATION environment variable.

.PARAMETER Project
Azure DevOps project name. Falls back to GMD_AZDO_PROJECT environment variable.

.PARAMETER EpicId
Epic ID to export. One of EpicId, FeatureId, or StoryId must be provided.

.PARAMETER FeatureId
Feature ID to export. One of EpicId, FeatureId, or StoryId must be provided.

.PARAMETER StoryId
Story ID to export. One of EpicId, FeatureId, or StoryId must be provided.

.PARAMETER OutputFile
Path to write the exported markdown. Required. Overwritten if it already exists.

.PARAMETER RepositoryRoot
Root directory for state configuration files. Default: repository root (parent of src/tools/).

.PARAMETER PatToken
Optional PAT token override. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW env variable.

.EXAMPLE
# Export Epic hierarchy to compare with local testEpic.md
.\src\tools\ExportAzDoHierarchyToMarkdown.ps1 -Organization "falco-it" -Project "GMD" -EpicId 2535 -OutputFile azDoEpic.md

# Then sort both files and diff
.\src\tools\SortMarkdownHierarchy.ps1 -MarkdownFile testEpic.md -MarkdownFile2 azDoEpic.md
code --diff testEpic-sorted.md azDoEpic-sorted.md

.EXAMPLE
# Export using environment variables for org/project
$env:GMD_AZDO_ORGANIZATION = "falco-it"
$env:GMD_AZDO_PROJECT = "GMD"
.\src\tools\ExportAzDoHierarchyToMarkdown.ps1 -EpicId 2535 -OutputFile azDoEpic.md

.NOTES
- Organization and Project can be omitted if set as environment variables
- Output file is overwritten if it already exists
- State warning comments and trailing markdown spaces are included in the export;
  use SortMarkdownHierarchy.ps1 to normalize both files before diffing
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $false)]
    [string]$Organization,

    [Parameter(Mandatory = $false)]
    [string]$Project,

    [Parameter(Mandatory = $false)]
    [int]$EpicId,

    [Parameter(Mandatory = $false)]
    [int]$FeatureId,

    [Parameter(Mandatory = $false)]
    [int]$StoryId,

    [Parameter(Mandatory = $true)]
    [string]$OutputFile,

    [Parameter(Mandatory = $false)]
    [string]$RepositoryRoot,

    [Parameter(Mandatory = $false)]
    [string]$PatToken
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Resolve repository root (parent of src/tools/ folder)
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
}

# Apply environment variable defaults if parameters not provided
if ([string]::IsNullOrWhiteSpace($Organization)) {
    $Organization = [Environment]::GetEnvironmentVariable('GMD_AZDO_ORGANIZATION')
    if ([string]::IsNullOrWhiteSpace($Organization)) {
        throw "Parameter 'Organization' is required. Provide via -Organization or set GMD_AZDO_ORGANIZATION environment variable."
    }
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    $Project = [Environment]::GetEnvironmentVariable('GMD_AZDO_PROJECT')
    if ([string]::IsNullOrWhiteSpace($Project)) {
        throw "Parameter 'Project' is required. Provide via -Project or set GMD_AZDO_PROJECT environment variable."
    }
}

# Determine work item type and ID
$itemType = $null
$itemId = $null

if ($PSBoundParameters.ContainsKey('EpicId') -and $EpicId -gt 0) {
    $itemType = 'Epic'
    $itemId = $EpicId
}
elseif ($PSBoundParameters.ContainsKey('FeatureId') -and $FeatureId -gt 0) {
    $itemType = 'Feature'
    $itemId = $FeatureId
}
elseif ($PSBoundParameters.ContainsKey('StoryId') -and $StoryId -gt 0) {
    $itemType = 'Story'
    $itemId = $StoryId
}
else {
    throw "One of -EpicId, -FeatureId, or -StoryId must be provided with a positive value."
}

# Resolve output file to absolute path
$OutputFile = [System.IO.Path]::GetFullPath($OutputFile)

Write-Host "`nExporting $itemType $itemId hierarchy from Azure DevOps..." -ForegroundColor Cyan
Write-Host "  Organization : $Organization" -ForegroundColor Gray
Write-Host "  Project      : $Project" -ForegroundColor Gray
Write-Host "  Output file  : $OutputFile" -ForegroundColor Gray

$srcPath = Join-Path $RepositoryRoot "src"
if (-not (Test-Path $srcPath)) {
    throw "Source directory not found: $srcPath"
}

try {
    Push-Location $srcPath

    # Build optional PatToken args
    $patArgs = @{}
    if (-not [string]::IsNullOrWhiteSpace($PatToken)) {
        $patArgs['PatToken'] = $PatToken
    }

    # Step 1: Download hierarchy from Azure DevOps
    Write-Host "`nFetching $itemType $($itemId)..." -ForegroundColor Gray

    $hierarchy = switch ($itemType) {
        'Epic' {
            & .\GetAzDoHierarchyForEpic.ps1 -Organization $Organization -Project $Project -EpicId $itemId @patArgs
        }
        'Feature' {
            & .\GetAzDoHierarchyForFeature.ps1 -Organization $Organization -Project $Project -FeatureId $itemId @patArgs
        }
        'Story' {
            & .\GetAzDoHierarchyForStory.ps1 -Organization $Organization -Project $Project -StoryId $itemId @patArgs
        }
    }

    if ($null -eq $hierarchy) {
        throw "Failed to fetch hierarchy. $itemType ID $itemId may not exist."
    }

    Write-Host "Successfully fetched hierarchy." -ForegroundColor Green

    # Step 2: Convert to markdown
    Write-Host "Converting hierarchy to markdown..." -ForegroundColor Gray

    $markdown = & .\ConvertHierarchyToMarkdown.ps1 `
        -Hierarchy $hierarchy `
        -Organization $Organization `
        -Project $Project `
        -RepositoryRoot $RepositoryRoot

    # Step 3: Write to output file
    $outputDir = Split-Path $OutputFile -Parent
    if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $markdown | Out-File $OutputFile -Encoding UTF8

    Write-Host "`nExport complete: $OutputFile" -ForegroundColor Green
}
finally {
    Pop-Location
}
