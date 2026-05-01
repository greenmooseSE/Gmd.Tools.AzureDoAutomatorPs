<#
.SYNOPSIS
Convert markdown hierarchy to machine-friendly JSON structure with optional WorkItemId support

.DESCRIPTION
Unified parser for markdown hierarchies with flexible work item identification:
- {WorkItemId} optional: If present, uses it for identification. If absent, leaves null (for new items or title-based matching)
- Type prefixes optional: Titles may include "Epic:", "Feature:" etc. prefixes (automatically stripped)
- {State} field supported: Parses {State}: metadata field for work item status
- Hierarchical structure: Maintains Epic > Feature > Story/Task/Bug nesting

Supported markdown format:
    # Epic: Epic Title
    {WorkItemId}: 2215
    {State}: Active
    {tags}: tag1, tag2
    {Description}
    Epic description text here
    
    ## Feature: Feature Title
    {WorkItemId}: 2216
    {State}: Under Development
    {tags}: tag1, tag2
    {Effort}: 13
    {Description}
    Feature description...
    
    ### Story: Story Title
    {WorkItemId}: 2217
    {tags}: tag1, tag2
    {Story Points}: 5
    {State}: Active
    {Description}
    Story description...
    
    #### Task: Task Title
    {WorkItemId}: 2220
    {State}: Active
    {Description}
    Task description...

Metadata fields (all optional):
- {WorkItemId}: N (for identifying existing work items, can be omitted for new items)
- {LastChangedDate}: ISO 8601 UTC (local metadata written by NewAzDoHierarchyFromMarkdown.ps1; used for staleness detection, never sent to AzDo)
- {State}: Active, Under Development, etc. (optional)
- {tags}: comma-separated list (optional)
- {Story Points}: story points (for stories, optional)
- {Effort}: effort estimate (for features/epics, optional)
- {Description}: multi-line description (optional)

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
    {WorkItemId}: 2216
    {Story Points}: 5
    {Description}
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
    [string]$MarkdownContent,

    [Parameter(Mandatory = $false)]
    [string]$Organization,

    [Parameter(Mandatory = $false)]
    [string]$Project,

    [Parameter(Mandatory = $false)]
    [string]$RepositoryRoot
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Import constants
. "$PSScriptRoot/AzDoAutomatorConstants.ps1"

# ============================================================================
# Field Config Support (config-driven parsing)
# ============================================================================

# Cache of label→fieldDef lookups keyed by "org/project/type"
$script:_mdFieldCfgCache = @{}

<#
.SYNOPSIS
Returns a case-insensitive label→fieldDef hashtable for the given work item type.
Returns an empty hashtable when Organization or Project are not set.
#>
function Get-WorkItemFieldConfigLookup {
    param([string]$WorkItemType)

    if ([string]::IsNullOrWhiteSpace($Organization) -or [string]::IsNullOrWhiteSpace($Project)) {
        return @{}
    }

    # Parser uses type name "Story" but LoadFieldConfiguration expects "User Story"
    [string]$lookupType = if ($WorkItemType -eq 'Story') { 'User Story' } else { $WorkItemType }
    [string]$cacheKey = "$Organization/$Project/$lookupType"
    if (-not $script:_mdFieldCfgCache.ContainsKey($cacheKey)) {
        [string]$repoRoot = if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { (Resolve-Path "$PSScriptRoot/..").Path } else { $RepositoryRoot }
        $fields = @()
        try {
            $fields = @(& "$PSScriptRoot/LoadFieldConfiguration.ps1" -Organization $Organization -Project $Project -WorkItemType $lookupType -RepositoryRoot $repoRoot)
        } catch {
            if (Get-Command 'ssLogIt.ps1' -ErrorAction SilentlyContinue) {
                $null = & ssLogIt.ps1 -Level Debug -Message "Could not load field config for $($WorkItemType): $($_.Exception.Message)"
            }
        }
        $lookup = @{}
        foreach ($f in $fields) {
            $lookup[$f.label.ToLower()] = $f
        }
        $script:_mdFieldCfgCache[$cacheKey] = $lookup
    }
    return $script:_mdFieldCfgCache[$cacheKey]
}

<#
.SYNOPSIS
Coerces a raw string value to the target AzDo field type.
Returns $null if the value is empty or coercion fails.
#>
function Convert-ConfigFieldValue {
    param([string]$RawValue, [string]$FieldType)

    if ([string]::IsNullOrWhiteSpace($RawValue)) { return $null }
    try {
        switch ($FieldType) {
            'boolean'  { return [bool]::Parse($RawValue) }
            'integer'  { return [int]$RawValue }
            'double'   { return [double]$RawValue }
            'dateTime' { return $RawValue }   # keep as ISO 8601 string
            default    { return $RawValue }   # string, html, treePath, identity
        }
    } catch {
        if (Get-Command 'ssLogIt.ps1' -ErrorAction SilentlyContinue) {
            $null = & ssLogIt.ps1 -Level Debug -Message "Could not coerce value '$RawValue' to type '$FieldType': $_"
        }
        return $RawValue   # return as-is on coercion failure
    }
}

<#
.SYNOPSIS
Finalizes a collected custom/config field buffer into the appropriate target
(item.configFields keyed by referenceName, or item.customFields keyed by label).
#>
function Save-CollectedField {
    param([object]$Item, [string]$Name, [string[]]$Buffer)

    [string]$value = ($Buffer -join "`n").Trim()

    # "__cfg:{referenceName}" keys come from html-type config fields
    if ($Name.StartsWith('__cfg:')) {
        [string]$refName = $Name.Substring(6)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $Item.configFields[$refName] = $value
        }
    } else {
        $Item.customFields[$Name] = $value
    }
}

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
Tries to match a curly-brace field marker in one of three recognised forms and returns label and inline value.
Returns $null when no match. Recognised forms (all start-of-line):
  Bare:         {Label}        or  {Label}: value
  Bold-wrapped: **{Label}**    or  **{Label}**: value
  Header-style: ## {Label}     or  ## {Label}: value  (any 1-5 # chars)
#>
function Get-CurlyFieldMarker {
    param([string]$Line)

    # Trim trailing whitespace (generator adds two trailing spaces for markdown line breaks)
    [string]$trimmed = $Line.TrimEnd()

    $label       = $null
    $inlineValue = $null

    if ($trimmed -match '^\{([^}]+)\}(?::\s*(.+))?$') {
        $label       = $Matches[1]
        $inlineValue = if (-not [string]::IsNullOrWhiteSpace($Matches[2])) { $Matches[2].Trim() } else { $null }
    }
    elseif ($trimmed -match '^\*\*\{([^}]+)\}\*\*(?::\s*(.+))?$') {
        $label       = $Matches[1]
        $inlineValue = if (-not [string]::IsNullOrWhiteSpace($Matches[2])) { $Matches[2].Trim() } else { $null }
    }
    elseif ($trimmed -match '^#{1,5}\s+\{([^}]+)\}(?::\s*(.+))?$') {
        $label       = $Matches[1]
        $inlineValue = if (-not [string]::IsNullOrWhiteSpace($Matches[2])) { $Matches[2].Trim() } else { $null }
    }

    if ($null -eq $label) { return $null }
    return @{ label = $label; inlineValue = $inlineValue }
}

# ============================================================================
# Parser
# ============================================================================

function Parse-MarkdownToWorkItems {
    param([string]$Content)

    [string[]]$lines              = $Content -split '\r?\n'
    [array]$workItems             = @()
    [object]$currentItem          = $null
    [array]$descriptionBuffer     = @()
    [bool]$collectingDescription  = $false
    [bool]$script:collectingCustomField = $false
    [string]$script:customFieldName    = $null
    [array]$script:customFieldBuffer   = @()
    [hashtable]$currentItemFieldConfig = @{}
    [bool]$inCodeFence                 = $false
    [bool]$skippingUnknownSection      = $false

    for ($lineNum = 0; $lineNum -lt $lines.Count; $lineNum++) {
        $line = $lines[$lineNum]

        # ── Work-item header line ────────────────────────────────────────────
        $itemInfo = Get-WorkItemInfo -Line $line

        if ($null -ne $itemInfo) {
            # Finalise previous item
            if ($null -ne $currentItem) {
                if ($script:collectingCustomField -and $script:customFieldBuffer.Count -gt 0) {
                    Save-CollectedField -Item $currentItem -Name $script:customFieldName -Buffer $script:customFieldBuffer
                }
                if ($descriptionBuffer.Count -gt 0) {
                    $currentItem.description = ($descriptionBuffer -join "`n").Trim()
                }
                $workItems += $currentItem
            }

            $currentItem = @{
                type               = $itemInfo.type
                level              = $itemInfo.level
                title              = $itemInfo.title
                lineNumber         = $lineNum + 1
                workItemId         = $null
                lastChangedDate    = $null
                state              = $null
                assignedTo         = $null
                tags               = $null
                storyPoints        = $null
                effort             = $null
                priority           = $null
                originalEstimate   = $null
                fixedIn            = $null
                deployedToDev      = $null
                deployedToStaging  = $null
                deployedToProduction = $null
                description        = $null
                customFields       = @{}
                configFields       = @{}
                children           = @()
            }
            $currentItemFieldConfig      = Get-WorkItemFieldConfigLookup -WorkItemType $itemInfo.type
            $descriptionBuffer           = @()
            $collectingDescription       = $false
            $script:collectingCustomField = $false
            $script:customFieldName      = $null
            $script:customFieldBuffer    = @()
            $inCodeFence                 = $false
            $skippingUnknownSection      = $false
            continue
        }

        # ── Lines below only apply when inside a work item ───────────────────
        if ($null -eq $currentItem) { continue }

        # ── Code fence tracking — skip {…} parsing inside fenced code blocks ─
        if ($line.TrimEnd() -match '^```') {
            $inCodeFence = -not $inCodeFence
            if ($script:collectingCustomField) { $script:customFieldBuffer += $line }
            elseif ($collectingDescription)    { $descriptionBuffer += $line }
            # Lines inside an unknown section are ignored
            continue
        }
        if ($inCodeFence) {
            if ($script:collectingCustomField) { $script:customFieldBuffer += $line }
            elseif ($collectingDescription)    { $descriptionBuffer += $line }
            # Lines inside an unknown section are ignored
            continue
        }

        # ── Try to match a curly-brace field marker ──────────────────────────
        $marker = Get-CurlyFieldMarker -Line $line

        if ($null -ne $marker) {
            # ── Local metadata field: {LastChangedDate} is not an AzDo field, handle before config lookup ─
            if ($marker.label -eq 'LastChangedDate') {
                if (-not [string]::IsNullOrWhiteSpace($marker.inlineValue)) {
                    $currentItem.lastChangedDate = $marker.inlineValue
                }
                continue
            }

            # Resolve label → field definition via appSettings.json config
            $cfgField = if ($currentItemFieldConfig.Count -gt 0) {
                $currentItemFieldConfig[$marker.label.ToLower()]
            } else {
                $null
            }

            if ($null -ne $cfgField) {
                # ── Known field: reset skip mode and finalise any active collection first —
                $skippingUnknownSection = $false
                if ($script:collectingCustomField) {
                    Save-CollectedField -Item $currentItem -Name $script:customFieldName -Buffer $script:customFieldBuffer
                    $script:collectingCustomField = $false
                }
                if ($collectingDescription -and $descriptionBuffer.Count -gt 0) {
                    $currentItem.description = ($descriptionBuffer -join "`n").Trim()
                    $descriptionBuffer       = @()
                    $collectingDescription   = $false
                }

                # Dispatch based on well-known reference names
                switch ($cfgField.referenceName) {
                    'System.Id' {
                        if (-not [string]::IsNullOrWhiteSpace($marker.inlineValue)) {
                            $currentItem.workItemId = [int]$marker.inlineValue
                        }
                    }
                    'System.State' {
                        # Strip the read-only annotation " ⚠️ (read-only)" appended by ConvertHierarchyToMarkdown.ps1
                        $currentItem.state = if ($null -ne $marker.inlineValue) { ($marker.inlineValue -replace '\s*⚠️.*$', '').Trim() } else { $marker.inlineValue }
                    }
                    'System.AssignedTo' {
                        $currentItem.assignedTo = $marker.inlineValue
                    }
                    'System.Tags' {
                        $currentItem.tags = $marker.inlineValue
                    }
                    'System.Title' {
                        # Title is parsed from the header line — ignore duplicate field
                    }
                    'System.Description' {
                        $collectingDescription = $true
                        if (-not [string]::IsNullOrWhiteSpace($marker.inlineValue)) {
                            $descriptionBuffer += $marker.inlineValue
                        }
                    }
                    'Microsoft.VSTS.Scheduling.StoryPoints' {
                        if (-not [string]::IsNullOrWhiteSpace($marker.inlineValue)) {
                            $currentItem.storyPoints = [double]$marker.inlineValue
                        }
                    }
                    'Microsoft.VSTS.Scheduling.Effort' {
                        if (-not [string]::IsNullOrWhiteSpace($marker.inlineValue)) {
                            $currentItem.effort = [double]$marker.inlineValue
                        }
                    }
                    'Microsoft.VSTS.Common.Priority' {
                        if (-not [string]::IsNullOrWhiteSpace($marker.inlineValue)) {
                            $currentItem.priority = [int]$marker.inlineValue
                        }
                    }
                    'Microsoft.VSTS.Scheduling.OriginalEstimate' {
                        if (-not [string]::IsNullOrWhiteSpace($marker.inlineValue)) {
                            $currentItem.originalEstimate = [double]$marker.inlineValue
                        }
                    }
                    default {
                        if ($cfgField.type -eq 'html') {
                            # Enter multi-line collecting mode for html field
                            $script:collectingCustomField = $true
                            $script:customFieldName       = "__cfg:$($cfgField.referenceName)"
                            $script:customFieldBuffer     = if ([string]::IsNullOrWhiteSpace($marker.inlineValue)) { @() } else { @($marker.inlineValue) }
                        }
                        else {
                            # Non-html config field: coerce and store inline value
                            $coerced = Convert-ConfigFieldValue -RawValue $marker.inlineValue -FieldType $cfgField.type
                            if ($null -ne $coerced) {
                                $currentItem.configFields[$cfgField.referenceName] = $coerced
                            }
                        }
                    }
                }
            }
            else {
                # ── Unknown label: stop active collecting mode; do NOT add marker to any buffer
                if ($script:collectingCustomField -and $script:customFieldBuffer.Count -gt 0) {
                    Save-CollectedField -Item $currentItem -Name $script:customFieldName -Buffer $script:customFieldBuffer
                    $script:collectingCustomField = $false
                    $script:customFieldName       = $null
                    $script:customFieldBuffer     = @()
                }
                if ($collectingDescription -and $descriptionBuffer.Count -gt 0) {
                    $currentItem.description = ($descriptionBuffer -join "`n").Trim()
                    $descriptionBuffer       = @()
                    $collectingDescription   = $false
                }
                $skippingUnknownSection = $true
                if (Get-Command 'ssLogIt.ps1' -ErrorAction SilentlyContinue) {
                    $null = & ssLogIt.ps1 -Level Debug -Message "Unrecognised field label '$($marker.label)' for $($currentItem.type) item - skipping section"
                }
            }
        }
        # ── No curly-brace marker: route to active collecting buffer or ignore —
        elseif ($script:collectingCustomField) {
            $script:customFieldBuffer += $line
        }
        elseif ($collectingDescription) {
            $descriptionBuffer += $line
        }
        elseif ($skippingUnknownSection) {
            # Content after an unknown field marker is discarded until the next known marker
        }
        elseif (-not [string]::IsNullOrWhiteSpace($line)) {
            # Non-header, non-field-marker, non-whitespace line outside any collecting mode
            # → treat as the start of an implicit description block
            $descriptionBuffer   += $line
            $collectingDescription = $true
        }
    }

    # ── Finalise the last item ───────────────────────────────────────────────
    if ($null -ne $currentItem) {
        if ($script:collectingCustomField -and $script:customFieldBuffer.Count -gt 0) {
            Save-CollectedField -Item $currentItem -Name $script:customFieldName -Buffer $script:customFieldBuffer
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
        lastChangedDate = $Item.lastChangedDate
        state = $Item.state
        assignedTo = $Item.assignedTo
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
        if ($Item.customFields.ContainsKey('Acceptance Tests')) {
            $cleaned.acceptanceTests = $Item.customFields['Acceptance Tests']
        }
        if ($Item.customFields.ContainsKey('Extra Information')) {
            $cleaned.extraInformation = $Item.customFields['Extra Information']
        }

        # Map legacy "Custom.*" metadata-style fields (backward compat)
        if ($Item.customFields.ContainsKey('Custom.ExtraInformation')) {
            $cleaned.extraInformation = $Item.customFields['Custom.ExtraInformation']
        }
        
        # Include any other custom fields that weren't specifically mapped
        [string[]]$mappedFields = @('Acceptance Criteria', 'Acceptance Tests', 'Extra Information', 'Custom.ExtraInformation')
        foreach ($fieldName in $Item.customFields.Keys) {
            if ($fieldName -notin $mappedFields) {
                $cleaned[$fieldName] = $Item.customFields[$fieldName]
            }
        }
    }

    # Map config-driven html fields to top-level properties consumed by downstream scripts
    # (NewAzDoHierarchyFromMarkdown.ps1 and DetectHierarchyChanges.ps1 access these by name)
    # Handles both legacy Custom.* reference names and the canonical VSTS names.
    if ($null -ne $Item.configFields) {
        if (($Item.configFields.ContainsKey('Custom.AcceptanceCriteria') -or $Item.configFields.ContainsKey('Microsoft.VSTS.Common.AcceptanceCriteria')) -and -not $cleaned.ContainsKey('acceptanceCriteria')) {
            $cleaned.acceptanceCriteria = if ($Item.configFields.ContainsKey('Microsoft.VSTS.Common.AcceptanceCriteria')) { $Item.configFields['Microsoft.VSTS.Common.AcceptanceCriteria'] } else { $Item.configFields['Custom.AcceptanceCriteria'] }
        }
        if ($Item.configFields.ContainsKey('Custom.AcceptanceTests') -and -not $cleaned.ContainsKey('acceptanceTests')) {
            $cleaned.acceptanceTests = $Item.configFields['Custom.AcceptanceTests']
        }
        if ($Item.configFields.ContainsKey('Custom.ExtraInformation') -and -not $cleaned.ContainsKey('extraInformation')) {
            $cleaned.extraInformation = $Item.configFields['Custom.ExtraInformation']
        }
    }
    
    # Recursively clean children
    if ($null -ne $Item.children -and $Item.children.Count -gt 0) {
        $cleaned.children = @($Item.children | ForEach-Object { Cleanup-Item -Item $_ })
    }

    # Include config-driven fields in output (non-empty only).
    # Clone and remove fields already promoted to named top-level properties to prevent
    # them being sent twice (once via named param, once via the generic -Fields path).
    if ($null -ne $Item.configFields -and $Item.configFields.Count -gt 0) {
        $cfgClone = @{} + $Item.configFields
        $cfgClone.Remove('Custom.AcceptanceCriteria')
        $cfgClone.Remove('Microsoft.VSTS.Common.AcceptanceCriteria')
        $cfgClone.Remove('Custom.AcceptanceTests')
        $cfgClone.Remove('Custom.ExtraInformation')
        if ($cfgClone.Count -gt 0) {
            $cleaned.configFields = $cfgClone
        }
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
