<#
.SYNOPSIS
Convert markdown hierarchy to machine-friendly JSON structure with optional WorkItemId support

.DESCRIPTION
Unified parser for markdown hierarchies with flexible work item identification:
- **WorkItemId optional**: If present, uses it for identification. If absent, leaves null (for new items or title-based matching)
- **Type prefixes optional**: Titles may include "Epic:", "Feature:" etc. prefixes (automatically stripped)
- **State field supported**: Parses **State** metadata field for work item status
- **Hierarchical structure**: Maintains Epic > Feature > Story/Task/Bug nesting

Supported markdown format:
    # Epic: Epic Title
    **WorkItemId**: 2215
    **State**: Active
    **tags**: tag1, tag2
    **Description**
    Epic description text here
    
    ## Feature: Feature Title
    **WorkItemId**: 2216
    **State**: Under Development
    **tags**: tag1, tag2
    **Effort**: 13
    **Description**
    Feature description...
    
    ### Story: Story Title
    **WorkItemId**: 2217
    **tags**: tag1, tag2
    **SP**: 5
    **State**: Active
    **Description**
    Story description...
    
    #### Task: Task Title
    **WorkItemId**: 2220
    **State**: Active
    **Description**
    Task description...

Metadata fields (all optional):
- **WorkItemId**: N (for identifying existing work items, can be omitted for new items)
- **State**: Active, Under Development, etc. (optional)
- **tags**: comma-separated list (optional)
- **SP**: story points (for stories, optional)
- **Effort**: effort estimate (for features/epics, optional)
- **Description**: multi-line description (optional)

Output JSON structure:
    {
      "workItems": [
        {
          "type": "Epic",
          "title": "Title without prefix",
          "workItemId": 2215,
          "state": "Active",
          "tags": "tag1, tag2",
          "description": "...",
          "children": [...]
        }
      ]
    }

.PARAMETER MarkdownFilePath
Path to markdown file (required if MarkdownContent not provided)

.PARAMETER MarkdownContent
Raw markdown content as string (required if MarkdownFilePath not provided)

.OUTPUTS
Object with "workItems" array containing parsed hierarchy

.EXAMPLE
Parse from file:
    $result = .\ConvertMarkdownToHierarchyJson.ps1 -MarkdownFilePath "hierarchy.md"
    $result.workItems | ConvertTo-Json -Depth 5

Parse from content:
    $content = @"
    ## Feature: My Feature
    **WorkItemId**: 2216
    **SP**: 5
    **Description**
    Feature details...
    "@
    $result = .\ConvertMarkdownToHierarchyJson.ps1 -MarkdownContent $content
    $result

.NOTES
- WorkItemId can be omitted; script will still parse the item (useful for new hierarchies)
- Type prefixes (Epic:, Feature:, Story:) are optional and automatically stripped from titles
- All markdown lines without metadata or section headers are part of current item's description
- Hierarchical structure is inferred from header levels
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $false)]
    [string]$MarkdownFilePath,

    [Parameter(Mandatory = $false)]
    [string]$MarkdownContent
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Import constants
. "$PSScriptRoot/AzDoAutomatorConstants.ps1"

# ============================================================================
# Input Validation
# ============================================================================

if ([string]::IsNullOrWhiteSpace($MarkdownFilePath) -and [string]::IsNullOrWhiteSpace($MarkdownContent)) {
    throw "Either -MarkdownFilePath or -MarkdownContent must be provided"
}

if ($MarkdownFilePath) {
    if (-not (Test-Path -LiteralPath $MarkdownFilePath)) {
        throw "Markdown file not found: $MarkdownFilePath"
    }
    $MarkdownContent = Get-Content -LiteralPath $MarkdownFilePath -Raw
}

if ([string]::IsNullOrWhiteSpace($MarkdownContent)) {
    throw "Markdown content is empty or null"
}

# ============================================================================
# Helper Functions
# ============================================================================

<#
.SYNOPSIS
Get work item type and level from header line
Returns: @{type: 'Epic'|'Feature'|'Story'|'Task'|'Bug', level: 1-5, title: 'stripped title'} or $null
#>
function Get-WorkItemInfo {
    param([string]$Line)
    
    if ($Line -match '^(#{1,5})\s+(Epic|Feature|Story|Task|Bug):\s+(.+)$') {
        $level = $Matches[1].Length
        $type = $Matches[2]
        $title = $Matches[3].Trim()
        return @{
            type = $type
            level = $level
            title = $title
        }
    }
    return $null
}

<#
.SYNOPSIS
Extract metadata field value from line like **WorkItemId**: 2216
#>
function Get-MetadataField {
    param(
        [string]$Line,
        [string]$FieldName
    )
    
    if ($Line -match "\*\*$FieldName\*\*:\s*(.+?)(\s*\\)?$") {
        $value = $Matches[1].Trim()
        # Remove trailing line break markers
        $value = $value -replace '\s+$|\\?$', ''
        return $value
    }
    return $null
}

# ============================================================================
# Parser
# ============================================================================

function Parse-MarkdownToWorkItems {
    param([string]$Content)
    
    [string[]]$lines = $Content -split "`n"
    [array]$workItems = @()
    [object]$currentItem = $null
    [array]$descriptionBuffer = @()
    [bool]$collectingDescription = $false
    
    for ($lineNum = 0; $lineNum -lt $lines.Count; $lineNum++) {
        $line = $lines[$lineNum]
        
        # Check if this is a work item header
        $itemInfo = Get-WorkItemInfo -Line $line
        
        if ($null -ne $itemInfo) {
            # Save previous item if exists
            if ($null -ne $currentItem) {
                if ($descriptionBuffer.Count -gt 0) {
                    $currentItem.description = ($descriptionBuffer -join "`n").Trim()
                }
                $workItems += $currentItem
            }
            
            # Create new work item
            $currentItem = @{
                type = $itemInfo.type
                level = $itemInfo.level
                title = $itemInfo.title
                lineNumber = $lineNum + 1
                workItemId = $null
                state = $null
                tags = $null
                storyPoints = $null
                effort = $null
                description = $null
                children = @()
            }
            
            $descriptionBuffer = @()
            $collectingDescription = $false
        }
        elseif ($null -ne $currentItem -and $line -match '^\*\*') {
            # Metadata line
            $collectingDescription = $false
            
            # Extract all metadata fields
            $workItemId = Get-MetadataField -Line $line -FieldName "WorkItemId"
            if ($null -ne $workItemId) {
                $currentItem.workItemId = [int]$workItemId
            }
            
            $state = Get-MetadataField -Line $line -FieldName "State"
            if ($null -ne $state) {
                $currentItem.state = $state
            }
            
            $tags = Get-MetadataField -Line $line -FieldName "tags"
            if ($null -ne $tags) {
                $currentItem.tags = $tags
            }
            
            $sp = Get-MetadataField -Line $line -FieldName "SP"
            if ($null -ne $sp) {
                $currentItem.storyPoints = [int]$sp
            }
            
            $effort = Get-MetadataField -Line $line -FieldName "Effort"
            if ($null -ne $effort) {
                $currentItem.effort = [int]$effort
            }
            
            # Handle Description field
            if ($line -match '^\*\*Description\*\*') {
                $collectingDescription = $true
                # Description might continue on same line
                if ($line -match '^\*\*Description\*\*\s+(.+)$') {
                    $descriptionBuffer += $Matches[1]
                }
            }
        }
        elseif ($null -ne $currentItem -and $collectingDescription) {
            # Part of description (until next metadata or work item)
            if ($line -match '^\*\*' -or (Get-WorkItemInfo -Line $line)) {
                # Hit next metadata or work item, finalize current description
                $collectingDescription = $false
                # This line will be reprocessed in next iteration
                $lineNum--
            }
            else {
                # Add to description (including blank lines within description)
                $descriptionBuffer += $line
            }
        }
        elseif ($null -ne $currentItem -and -not [string]::IsNullOrWhiteSpace($line)) {
            # Non-metadata, non-header line outside description mode
            # (indicates start of implicit description)
            if (-not ($line -match '^\*\*') -and -not (Get-WorkItemInfo -Line $line)) {
                $descriptionBuffer += $line
                $collectingDescription = $true
            }
        }
    }
    
    # Save last item
    if ($null -ne $currentItem) {
        if ($descriptionBuffer.Count -gt 0) {
            $currentItem.description = ($descriptionBuffer -join "`n").Trim()
        }
        $workItems += $currentItem
    }
    
    return $workItems
}

<#
.SYNOPSIS
Build hierarchical structure from flat work items list
#>
function Build-Hierarchy {
    param([array]$WorkItems)
    
    $result = @()
    $stack = [System.Collections.Stack]::new()  # Use proper Stack object
    
    foreach ($item in $WorkItems) {
        # Pop stack until we find parent level
        while ($stack.Count -gt 0 -and $stack.Peek()[0] -ge $item.level) {
            $stack.Pop() | Out-Null
        }
        
        # Add to parent's children or root array
        if ($stack.Count -gt 0) {
            $parent = $stack.Peek()[1]
            $parent.children += @($item)
        }
        else {
            $result += @($item)
        }
        
        # Push current item to stack
        $stack.Push(@($item.level, $item)) | Out-Null
    }
    
    return $result
}

<#
.SYNOPSIS
Remove internal properties and clean output
#>
function Cleanup-Item {
    param([object]$Item)
    
    $cleaned = @{
        type = $Item.type
        title = $Item.title
        workItemId = $Item.workItemId
        state = $Item.state
        tags = $Item.tags
    }
    
    # Only include optional fields if present
    if ($null -ne $Item.storyPoints) { $cleaned.storyPoints = $Item.storyPoints }
    if ($null -ne $Item.effort) { $cleaned.effort = $Item.effort }
    if (-not [string]::IsNullOrWhiteSpace($Item.description)) { $cleaned.description = $Item.description }
    
    # Recursively clean children
    if ($Item.children.Count -gt 0) {
        $cleaned.children = @($Item.children | ForEach-Object { Cleanup-Item -Item $_ })
    }
    
    return $cleaned
}

# ============================================================================
# Execution
# ============================================================================

try {
    [string[]]$lines = $MarkdownContent -split "`n"
    $workItems = Parse-MarkdownToWorkItems -Content $MarkdownContent
    
    if ($workItems.Count -eq 0) {
        return @{ workItems = @() }
    }
    
    # Build hierarchy
    $hierarchy = Build-Hierarchy -WorkItems $workItems
    
    # Clean up and return
    $cleanedItems = @($hierarchy | ForEach-Object { Cleanup-Item -Item $_ })
    return @{ workItems = $cleanedItems }
}
catch {
    throw $_
}
