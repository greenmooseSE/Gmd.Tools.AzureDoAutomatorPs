<#
.SYNOPSIS
Sort and normalize markdown hierarchy files by WorkItemId for clean diffing.

.DESCRIPTION
Parses markdown hierarchy files, sorts work item sections at each level by WorkItemId
(ascending), and re-serializes to a clean canonical format — enabling meaningful
side-by-side diff between a local plan and an Azure DevOps export.

Each file is:
  1. Parsed into a hierarchy using ConvertMarkdownToHierarchyJson.ps1
  2. Sorted by WorkItemId at each level (ascending; items without IDs go last, sorted by title)
  3. Re-serialized in a clean canonical format (no state warning HTML comments, no trailing spaces)

Supports one or two files in a single call so both are normalized to the same format.

.PARAMETER MarkdownFile
Path to the first markdown file to sort. Required.

.PARAMETER OutputFile
Output path for the sorted first file. Default: original filename with "-sorted" suffix appended
before the extension (e.g. "testEpic.md" -> "testEpic-sorted.md").

.PARAMETER MarkdownFile2
Optional path to a second markdown file to sort in the same call (e.g. the AzDo export).

.PARAMETER OutputFile2
Output path for the sorted second file. Default: original filename with "-sorted" suffix.

.EXAMPLE
# Sort a single file (output saved as testEpic-sorted.md)
.\src\tools\SortMarkdownHierarchy.ps1 -MarkdownFile testEpic.md

.EXAMPLE
# Sort two files for diffing; outputs: testEpic-sorted.md and azDoEpic-sorted.md
.\src\tools\SortMarkdownHierarchy.ps1 -MarkdownFile testEpic.md -MarkdownFile2 azDoEpic.md

.EXAMPLE
# Full diff workflow
.\src\tools\ExportAzDoHierarchyToMarkdown.ps1 -EpicId 2535 -OutputFile azDoEpic.md
.\src\tools\SortMarkdownHierarchy.ps1 -MarkdownFile testEpic.md -MarkdownFile2 azDoEpic.md
code --diff testEpic-sorted.md azDoEpic-sorted.md

.EXAMPLE
# Specify explicit output paths
.\src\tools\SortMarkdownHierarchy.ps1 `
    -MarkdownFile testEpic.md -OutputFile testEpic-sorted.md `
    -MarkdownFile2 azDoEpic.md -OutputFile2 azDoEpic-sorted.md

.NOTES
- Items with WorkItemId are sorted by WorkItemId ascending
- Items without WorkItemId are placed after those with IDs, sorted alphabetically by title
- Trailing markdown whitespace (  ) is stripped from all content
- State warning HTML comments are removed from all content
- The canonical output is suitable for version-controlled diff comparison
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [string]$MarkdownFile,

    [Parameter(Mandatory = $false)]
    [string]$OutputFile,

    [Parameter(Mandatory = $false)]
    [string]$MarkdownFile2,

    [Parameter(Mandatory = $false)]
    [string]$OutputFile2
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# ============================================================================
# Helpers
# ============================================================================

function Get-SortedOutputPath {
    param([string]$InputPath)
    $dir = Split-Path $InputPath -Parent
    $base = [System.IO.Path]::GetFileNameWithoutExtension($InputPath)
    $ext = [System.IO.Path]::GetExtension($InputPath)
    $sortedName = "$base-sorted$ext"
    if ([string]::IsNullOrWhiteSpace($dir)) {
        return $sortedName
    }
    return Join-Path $dir $sortedName
}

function Sort-WorkItemsRecursively {
    param([object[]]$Items)

    if ($null -eq $Items -or $Items.Count -eq 0) {
        return @()
    }

    # Sort: items with WorkItemId ascending, then items without (sorted by title)
    $sorted = @($Items | Sort-Object @(
        @{
            Expression = {
                if ($null -ne $_['workItemId']) { [int]$_['workItemId'] }
                else { [int]::MaxValue }
            }
            Ascending = $true
        },
        @{
            Expression = { [string]$_['title'] }
            Ascending  = $true
        }
    ))

    # Recursively sort children
    foreach ($item in $sorted) {
        $childrenVal = $item['children']
        if ($null -ne $childrenVal -and $childrenVal.Count -gt 0) {
            $item['children'] = @(Sort-WorkItemsRecursively -Items @($childrenVal))
        }
    }

    return $sorted
}

function Normalize-Text {
    <#
    .SYNOPSIS
    Strips trailing whitespace per line and removes HTML comment blocks from text.
    #>
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    $lines = $Text -split "`n"
    $inComment = $false
    $result = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $lines) {
        $trimmed = $line.TrimEnd()

        # Handle HTML comment blocks (<!-- ... -->)
        if ($inComment) {
            if ($trimmed -match '-->') {
                $inComment = $false
            }
            continue
        }

        if ($trimmed -match '<!--') {
            if ($trimmed -match '-->') {
                # Single-line comment — skip it entirely
                continue
            }
            # Multi-line comment start — enter comment mode
            $inComment = $true
            continue
        }

        $result.Add($trimmed)
    }

    # Trim leading/trailing blank lines from the content block
    $content = ($result -join "`n").Trim()
    return $content
}

function Get-HeaderHashesForType {
    param([string]$Type)
    switch ($Type) {
        'Epic'    { return '#' }
        'Feature' { return '##' }
        'Story'   { return '###' }
        default   { return '####' }  # Task, Bug, etc.
    }
}

# Fields handled explicitly in the serializer — others are treated as custom fields
$script:KnownFields = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@(
        'type', 'title', 'workItemId', 'state', 'tags', 'storyPoints',
        'effort', 'description', 'acceptanceCriteria', 'acceptanceTests',
        'extraInformation', 'children'
    ),
    [System.StringComparer]::OrdinalIgnoreCase
)

function Format-ItemAsMarkdown {
    param([object]$Item)

    $sb = [System.Text.StringBuilder]::new()
    $hashes = Get-HeaderHashesForType -Type $Item['type']

    # Header line followed by blank line
    [void]$sb.AppendLine("$hashes $($Item['type']): $($Item['title'])")
    [void]$sb.AppendLine('')

    # WorkItemId
    if ($null -ne $Item['workItemId']) {
        [void]$sb.AppendLine("{WorkItemId}: $($Item['workItemId'])")
    }

    # State (if present and non-empty — strip any trailing " ⚠️ (read-only)" marker)
    $stateVal = $Item['state']
    if (-not [string]::IsNullOrWhiteSpace($stateVal)) {
        $stateVal = ($stateVal -replace '\s*⚠️.*$', '').Trim()
        [void]$sb.AppendLine("{State}: $stateVal")
    }

    # Tags (sorted alphabetically, semicolon-separated)
    $tagsVal = $Item['tags']
    if (-not [string]::IsNullOrWhiteSpace($tagsVal)) {
        $normalizedTags = ($tagsVal -split '\s*[,;]\s*' |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim() } |
            Sort-Object) -join '; '
        [void]$sb.AppendLine("{tags}: $normalizedTags")
    }

    # SP (story points — for stories)
    if ($null -ne $Item['storyPoints']) {
        [void]$sb.AppendLine("{Story Points}: $($Item['storyPoints'])")
    }

    # Effort (for epics/features)
    if ($null -ne $Item['effort']) {
        [void]$sb.AppendLine("{Effort}: $($Item['effort'])")
    }

    # Custom fields (Priority, OriginalEstimate, etc.) — sorted alphabetically
    $customKeys = @($Item.Keys | Where-Object { -not $script:KnownFields.Contains($_) } | Sort-Object)
    foreach ($key in $customKeys) {
        $val = $Item[$key]
        if ($null -ne $val -and -not [string]::IsNullOrWhiteSpace($val.ToString())) {
            [void]$sb.AppendLine("{$key}: $val")
        }
    }

    # Description
    $desc = Normalize-Text $Item['description']
    if (-not [string]::IsNullOrWhiteSpace($desc)) {
        [void]$sb.AppendLine('{Description}')
        [void]$sb.AppendLine($desc)
    }

    # Acceptance Criteria
    $ac = Normalize-Text $Item['acceptanceCriteria']
    if (-not [string]::IsNullOrWhiteSpace($ac)) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('#### Acceptance Criteria')
        [void]$sb.AppendLine($ac)
    }

    # Acceptance Tests
    $acs = Normalize-Text $Item['acceptanceTests']
    if (-not [string]::IsNullOrWhiteSpace($acs)) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('#### Acceptance Tests')
        [void]$sb.AppendLine($acs)
    }

    # Extra Information
    $ei = Normalize-Text $Item['extraInformation']
    if (-not [string]::IsNullOrWhiteSpace($ei)) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('#### Extra Information')
        [void]$sb.AppendLine($ei)
    }

    # Children (already sorted)
    $children = $Item['children']
    if ($null -ne $children -and $children.Count -gt 0) {
        [void]$sb.AppendLine('')
        foreach ($child in $children) {
            [void]$sb.AppendLine((Format-ItemAsMarkdown -Item $child))
        }
    }

    return $sb.ToString().TrimEnd()
}

function ConvertTo-SortedMarkdown {
    param([string]$Content, [string]$SourceLabel)

    $converterScript = Join-Path $PSScriptRoot ".." "ConvertMarkdownToHierarchyJson.ps1"
    $converterScript = (Resolve-Path $converterScript).Path

    Write-Host "  Parsing $SourceLabel..." -ForegroundColor Gray
    $parsed = & $converterScript -MarkdownContent $Content

    if ($null -eq $parsed -or $null -eq $parsed.workItems) {
        throw "Failed to parse markdown: $SourceLabel"
    }

    $rootItems = @($parsed.workItems)

    Write-Host "  Sorting $($rootItems.Count) top-level item(s)..." -ForegroundColor Gray
    $sorted = @(Sort-WorkItemsRecursively -Items $rootItems)

    # Re-serialize to canonical markdown
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $sorted) {
        $parts.Add((Format-ItemAsMarkdown -Item $item))
    }

    return ($parts -join ("`n`n")) + "`n"
}

function Process-MarkdownFile {
    param([string]$InputFile, [string]$Output)

    $InputFile = (Resolve-Path $InputFile).Path
    Write-Host "`nProcessing: $InputFile" -ForegroundColor Cyan

    $content = Get-Content $InputFile -Raw
    $sortedMarkdown = ConvertTo-SortedMarkdown -Content $content -SourceLabel (Split-Path $InputFile -Leaf)

    $outputDir = Split-Path $Output -Parent
    if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $sortedMarkdown | Out-File $Output -Encoding UTF8
    Write-Host "  Saved sorted output: $Output" -ForegroundColor Green
}

# ============================================================================
# Main
# ============================================================================

# Resolve output paths
if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    $OutputFile = Get-SortedOutputPath -InputPath $MarkdownFile
}
$OutputFile = [System.IO.Path]::GetFullPath($OutputFile)

if (-not [string]::IsNullOrWhiteSpace($MarkdownFile2) -and [string]::IsNullOrWhiteSpace($OutputFile2)) {
    $OutputFile2 = Get-SortedOutputPath -InputPath $MarkdownFile2
}
if (-not [string]::IsNullOrWhiteSpace($OutputFile2)) {
    $OutputFile2 = [System.IO.Path]::GetFullPath($OutputFile2)
}

# Validate inputs
if (-not (Test-Path $MarkdownFile)) {
    throw "Markdown file not found: $MarkdownFile"
}
if (-not [string]::IsNullOrWhiteSpace($MarkdownFile2) -and -not (Test-Path $MarkdownFile2)) {
    throw "Markdown file not found: $MarkdownFile2"
}

Write-Host "`n========== Sort Markdown Hierarchy ==========" -ForegroundColor Cyan

Process-MarkdownFile -InputFile $MarkdownFile -Output $OutputFile

if (-not [string]::IsNullOrWhiteSpace($MarkdownFile2)) {
    Process-MarkdownFile -InputFile $MarkdownFile2 -Output $OutputFile2
}

Write-Host "`nDone." -ForegroundColor Cyan

if (-not [string]::IsNullOrWhiteSpace($MarkdownFile2)) {
    Write-Host "`nTo diff the sorted files:" -ForegroundColor Yellow
    $f1 = Split-Path $OutputFile -Leaf
    $f2 = Split-Path $OutputFile2 -Leaf
    Write-Host "  code --diff $f1 $f2" -ForegroundColor Gray
}
