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
    **Story Points**: 5
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
- **Story Points**: story points (for stories, optional)
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
    **Story Points**: 5
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
Return the named section for special content headers (Acceptance Criteria, AC Scenarios, Extra Information).
Returns the section name string or $null if the line is not a special section header.
#>
function Get-SpecialSectionName {
    param([string]$Line)
    if ($Line -match '^#{1,5}\s+(Acceptance Criteria|AC Scenarios|Extra Information)\s*$') {
        return $Matches[1]
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
    [bool]$script:collectingCustomField = $false
    [string]$script:customFieldName = $null
    [array]$script:customFieldBuffer = @()
    [bool]$script:isHashHeaderField = $false
    
    # Regex that matches a proper metadata line: **FieldName**: value  OR  **Description** (no colon)
    # This intentionally excludes bold text in descriptions like **As a** system administrator
    [string]$metadataLineRegex = '^\*\*[^*]+\*\*(\s*:|\s*$)'

    for ($lineNum = 0; $lineNum -lt $lines.Count; $lineNum++) {
        $line = $lines[$lineNum]
        
        # Check if this is a work item header or a special section header
        $itemInfo = Get-WorkItemInfo -Line $line
        $specialSection = Get-SpecialSectionName -Line $line
        
        if ($null -ne $itemInfo) {
            # Save previous item if exists
            if ($null -ne $currentItem) {
                # Finalize any pending custom field
                if ($script:collectingCustomField -and $script:customFieldBuffer.Count -gt 0) {
                    $currentItem.customFields[$script:customFieldName] = ($script:customFieldBuffer -join "`n").Trim()
                    $script:collectingCustomField = $false
                }
                
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
                priority = $null
                originalEstimate = $null
                fixedIn = $null
                deployedToDev = $null
                deployedToStaging = $null
                deployedToProduction = $null
                description = $null
                customFields = @{}
                children = @()
            }
            
            $descriptionBuffer = @()
            $collectingDescription = $false
        }
        elseif ($null -ne $currentItem -and $null -ne $specialSection) {
            # Special section header: #### Acceptance Criteria / AC Scenarios / Extra Information
            # Finalize any in-progress description or custom field, then collect this section's content
            if ($script:collectingCustomField -and $script:customFieldBuffer.Count -gt 0) {
                $currentItem.customFields[$script:customFieldName] = ($script:customFieldBuffer -join "`n").Trim()
            }
            $script:collectingCustomField = $false
            $collectingDescription = $false
            if ($descriptionBuffer.Count -gt 0) {
                $currentItem.description = ($descriptionBuffer -join "`n").Trim()
                $descriptionBuffer = @()
            }
            # Start collecting section content into a named custom field
            $script:collectingCustomField = $true
            $script:customFieldName = $specialSection
            $script:customFieldBuffer = @()
            $script:isHashHeaderField = $true
        }
        elseif ($null -ne $currentItem -and -not $script:collectingCustomField -and -not $collectingDescription -and $line -match $metadataLineRegex) {
            # Metadata line (e.g. **tags**: ..., **Story Points**: 5, **Description**)
            # Only reached when not currently collecting a custom field or description content.
            # Bold lines like **Foo**: bar inside descriptions/fields are caught by the collection
            # branches below (collectingCustomField / collectingDescription), which fire when this
            # block is excluded by the guard conditions.
            
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
            
            # Parse both "Story Points" (new) and "SP" (legacy) for backward compatibility
            $sp = Get-MetadataField -Line $line -FieldName "Story Points"
            if ($null -eq $sp) {
                $sp = Get-MetadataField -Line $line -FieldName "SP"
            }
            if ($null -ne $sp) {
                $currentItem.storyPoints = [double]$sp
            }
            
            $effort = Get-MetadataField -Line $line -FieldName "Effort"
            if ($null -ne $effort) {
                $currentItem.effort = [double]$effort
            }
            
            $priority = Get-MetadataField -Line $line -FieldName "Priority"
            if ($null -ne $priority) {
                $currentItem.priority = [int]$priority
            }
            
            $originalEstimate = Get-MetadataField -Line $line -FieldName "OriginalEstimate"
            if ($null -ne $originalEstimate) {
                $currentItem.originalEstimate = [double]$originalEstimate
            }
            
            $fixedIn = Get-MetadataField -Line $line -FieldName "FixedIn"
            if ($null -ne $fixedIn) {
                $currentItem.fixedIn = $fixedIn
            }
            
            $deployedToDevValue = Get-MetadataField -Line $line -FieldName "DeployedToDev"
            if ($null -ne $deployedToDevValue) {
                $currentItem.deployedToDev = [bool]::Parse($deployedToDevValue)
            }
            
            $deployedToStagingValue = Get-MetadataField -Line $line -FieldName "DeployedToStaging"
            if ($null -ne $deployedToStagingValue) {
                $currentItem.deployedToStaging = [bool]::Parse($deployedToStagingValue)
            }
            
            $deployedToProductionValue = Get-MetadataField -Line $line -FieldName "DeployedToProduction"
            if ($null -ne $deployedToProductionValue) {
                $currentItem.deployedToProduction = [bool]::Parse($deployedToProductionValue)
            }
            
            # Handle Description field
            if ($line -match '^\*\*Description\*\*') {
                $collectingDescription = $true
                # Description might continue on same line: **Description** text  OR  **Description**: text
                if ($line -match '^\*\*Description\*\*[\s:]+(.+)$') {
                    $descriptionBuffer += $Matches[1]
                }
            }
            # Handle custom fields (any field starting with Custom. or other custom fields)
            elseif ($line -match '^\*\*([^*]+)\*\*:\s*(.*)$') {
                $fieldName = $Matches[1]
                $fieldValue = $Matches[2].Trim()
                # Skip standard fields that we've already processed
                if ($fieldName -notin @('WorkItemId', 'State', 'tags', 'SP', 'Effort', 'Description', 'Priority', 'OriginalEstimate', 'FixedIn', 'DeployedToDev', 'DeployedToStaging', 'DeployedToProduction')) {
                    # Always enter collecting mode so continuation lines (e.g. multi-line
                    # Custom.ACScenarios written by ConvertHierarchyToMarkdown.ps1) are captured.
                    # If the field value begins on the same line, seed the buffer with it.
                    $script:collectingCustomField = $true
                    $script:customFieldName = $fieldName
                    $script:customFieldBuffer = if ([string]::IsNullOrWhiteSpace($fieldValue)) { @() } else { @($fieldValue) }
                    $script:isHashHeaderField = $false
                }
            }
        }
        elseif ($null -ne $currentItem -and $script:collectingCustomField) {
            # Collecting multi-line custom field value.
            # For metadata-line custom fields (isHashHeaderField=false): a new metadata line ends
            # this field and is reprocessed. For hash-header sections (Acceptance Criteria, AC
            # Scenarios, Extra Information; isHashHeaderField=true): bold lines like **Foo**: bar
            # are content and must not terminate collection.
            if ($line -match $metadataLineRegex -and -not $script:isHashHeaderField) {
                # Hit next metadata field – finalize current custom field and reprocess this line
                $currentItem.customFields[$script:customFieldName] = ($script:customFieldBuffer -join "`n").Trim()
                $script:collectingCustomField = $false
                # This line will be reprocessed in next iteration
                $lineNum--
            }
            else {
                # Add to custom field value (including blank lines within field)
                $script:customFieldBuffer += $line
            }
        }
        elseif ($null -ne $currentItem -and $collectingDescription) {
            # Collecting description content.
            # Bold-formatted lines like **Foo**: bar are treated as description content, NOT metadata.
            # Only work item headers (handled above) or special-section headers (handled above)
            # end description collection – no termination check needed here.
            $descriptionBuffer += $line
        }
        elseif ($null -ne $currentItem -and -not [string]::IsNullOrWhiteSpace($line)) {
            # Non-metadata, non-header line outside description mode
            # (indicates start of implicit description)
            if (-not ($line -match $metadataLineRegex) -and -not (Get-WorkItemInfo -Line $line)) {
                $descriptionBuffer += $line
                $collectingDescription = $true
            }
        }
    }
    
    # Save last item
    if ($null -ne $currentItem) {
        # Finalize any pending custom field
        if ($script:collectingCustomField -and $script:customFieldBuffer.Count -gt 0) {
            $currentItem.customFields[$script:customFieldName] = ($script:customFieldBuffer -join "`n").Trim()
            $script:collectingCustomField = $false
        }
        
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
    if ($null -ne $Item.priority) { $cleaned.priority = $Item.priority }
    if ($null -ne $Item.originalEstimate) { $cleaned.originalEstimate = $Item.originalEstimate }
    if (-not [string]::IsNullOrWhiteSpace($Item.fixedIn)) { $cleaned.fixedIn = $Item.fixedIn }
    if ($null -ne $Item.deployedToDev) { $cleaned.deployedToDev = $Item.deployedToDev }
    if ($null -ne $Item.deployedToStaging) { $cleaned.deployedToStaging = $Item.deployedToStaging }
    if ($null -ne $Item.deployedToProduction) { $cleaned.deployedToProduction = $Item.deployedToProduction }
    if (-not [string]::IsNullOrWhiteSpace($Item.description)) { $cleaned.description = $Item.description }
    
    # Map custom fields to top-level properties for consistency with Azure DevOps export
    # This ensures DetectHierarchyChanges can properly compare original vs modified
    if ($null -ne $Item.customFields -and $Item.customFields.Count -gt 0) {
        # Map section-header style fields (#### Acceptance Criteria etc.) to canonical names
        if ($Item.customFields.ContainsKey('Acceptance Criteria')) {
            $cleaned.acceptanceCriteria = $Item.customFields['Acceptance Criteria']
        }
        if ($Item.customFields.ContainsKey('AC Scenarios')) {
            $cleaned.acScenarios = $Item.customFields['AC Scenarios']
        }
        if ($Item.customFields.ContainsKey('Extra Information')) {
            $cleaned.extraInformation = $Item.customFields['Extra Information']
        }

        # Map legacy "Custom.*" metadata-style fields (backward compat)
        if ($Item.customFields.ContainsKey('Custom.ACScenarios')) {
            $cleaned.acScenarios = $Item.customFields['Custom.ACScenarios']
        }
        if ($Item.customFields.ContainsKey('Custom.ExtraInformation')) {
            $cleaned.extraInformation = $Item.customFields['Custom.ExtraInformation']
        }
        
        # Include any other custom fields that weren't specifically mapped
        [string[]]$mappedFields = @('Acceptance Criteria', 'AC Scenarios', 'Extra Information', 'Custom.ACScenarios', 'Custom.ExtraInformation')
        foreach ($fieldName in $Item.customFields.Keys) {
            if ($fieldName -notin $mappedFields) {
                $cleaned[$fieldName] = $Item.customFields[$fieldName]
            }
        }
    }
    
    # Recursively clean children
    if ($null -ne $Item.children -and $Item.children.Count -gt 0) {
        $cleaned.children = @($Item.children | ForEach-Object { Cleanup-Item -Item $_ })
    }
    
    return $cleaned
}

# ============================================================================
# Execution
# ============================================================================

try {
    [string[]]$lines = $MarkdownContent -split "`n"
    $workItems = @(Parse-MarkdownToWorkItems -Content $MarkdownContent)
    
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
