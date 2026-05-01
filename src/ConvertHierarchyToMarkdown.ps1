<#
.SYNOPSIS
Convert an Azure DevOps hierarchy to markdown format with state validation

.DESCRIPTION
Exports an Epic/Feature/Story hierarchy to markdown format including:
- Supports Epic (with nested Features and Stories)
- Supports Feature (with nested Stories)
- Supports Story with Tasks and Bugs
- State field in metadata section for Stories
- Marks editable vs non-editable states based on configuration
- Adds warning comments for non-writable states
- Adds 2 trailing spaces before newlines for markdown line breaks (except headers, lists, tables)

The exported markdown is compatible with NewAzDoHierarchyFromMarkdown.ps1 for round-trip import.

.PARAMETER Hierarchy
The hierarchy object from GetAzDoHierarchyForEpic.ps1, GetAzDoHierarchyForFeature.ps1, or GetAzDoHierarchyForStory.ps1 (required)

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER RepositoryRoot
Root directory where state configuration files are stored. Default: current working directory.

.OUTPUTS
String containing the markdown representation of the hierarchy

.EXAMPLE
# Export an epic hierarchy to markdown
$hierarchy = .\GetAzDoHierarchyForEpic.ps1 -EpicId 100 -Organization "myorg" -Project "myproj"
$markdown = .\ConvertHierarchyToMarkdown.ps1 -Hierarchy $hierarchy -Organization "myorg" -Project "myproj"
$markdown | Out-File "epic.md"

# Export a feature hierarchy to markdown
$hierarchy = .\GetAzDoHierarchyForFeature.ps1 -FeatureId 200 -Organization "myorg" -Project "myproj"
$markdown = .\ConvertHierarchyToMarkdown.ps1 -Hierarchy $hierarchy -Organization "myorg" -Project "myproj"
$markdown | Out-File "feature.md"

# Export a story hierarchy to markdown
$hierarchy = .\GetAzDoHierarchyForStory.ps1 -StoryId 300 -Organization "myorg" -Project "myproj"
$markdown = .\ConvertHierarchyToMarkdown.ps1 -Hierarchy $hierarchy -Organization "myorg" -Project "myproj"
$markdown | Out-File "story.md"

.NOTES
- Requires LoadStateConfiguration.ps1 for writable states validation
- Adds 2 trailing spaces before newlines for proper markdown line breaks
- Non-writable states include a warning comment before the markdown
- Compatible with NewAzDoHierarchyFromMarkdown.ps1 for reimport
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [PSObject]$Hierarchy,

    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$Project,

    [Parameter(Mandatory = $false)]
    [string]$RepositoryRoot = (Get-Location).Path
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Import modules
. "$PSScriptRoot/AzDoAutomatorConstants.ps1"

# Load state configuration
$config = & "$PSScriptRoot/LoadStateConfiguration.ps1" -Organization $Organization -Project $Project -RepositoryRoot $RepositoryRoot

# ============================================================================
# Config-driven field output support
# ============================================================================

$script:_htmFieldCfgCache = @{}

<#
.SYNOPSIS
Returns ordered array of fieldDef objects for the given work item type, or empty array when unavailable.
#>
function Get-FieldConfigForType {
    param([string]$WorkItemType)
    [string]$key = "$Organization/$Project/$WorkItemType"
    if (-not $script:_htmFieldCfgCache.ContainsKey($key)) {
        $fields = @()
        try {
            $fields = @(& "$PSScriptRoot/LoadFieldConfiguration.ps1" -Organization $Organization -Project $Project -WorkItemType $WorkItemType -RepositoryRoot $RepositoryRoot)
        } catch {
            $fields = @()
        }
        $script:_htmFieldCfgCache[$key] = $fields
    }
    return $script:_htmFieldCfgCache[$key]
}

<#
.SYNOPSIS
Labels that are already output as core metadata fields and must be skipped during config-driven output.
#>
[string[]]$script:CoreOutputLabels = @('WorkItemId', 'Tags', 'Story Points', 'Effort', 'State', 'Description', 'Title', 'Assigned To', 'Area Path', 'Iteration Path', 'Acceptance Criteria', 'Acceptance Tests', 'Extra Information')

<#
.SYNOPSIS
Appends markdown lines for any config-driven fields present in the item's configFields hashtable,
emitting them in the order defined in appSettings.json and skipping already-output core labels.
Returns markdown string fragment (may be empty).
#>
function Get-ConfigFieldsMarkdown {
    param([PSObject]$Item, [string]$WorkItemType)

    if (-not ($Item.PSObject.Properties.Name -contains 'configFields')) { return '' }
    [hashtable]$cfgFields = $Item.configFields
    if ($null -eq $cfgFields -or $cfgFields.Count -eq 0) { return '' }

    $fieldDefs = @(Get-FieldConfigForType -WorkItemType $WorkItemType)
    if ($fieldDefs.Count -eq 0) { return '' }

    [string]$fragment = ''
    foreach ($fd in $fieldDefs) {
        if ($fd.label -in $script:CoreOutputLabels) { continue }
        if (-not $cfgFields.ContainsKey($fd.referenceName)) { continue }
        $val = $cfgFields[$fd.referenceName]
        if ($null -eq $val) { continue }
        [string]$strVal = $val.ToString()
        if ([string]::IsNullOrWhiteSpace($strVal)) { continue }
        $escaped = Format-MarkdownText $strVal
        if ($fd.type -eq 'html') {
            $content = Add-MarkdownLineBreaks $escaped
            $fragment += "{$($fd.label)}  `n$content`n"
        } else {
            $fragment += "{$($fd.label)}: $escaped  `n"
        }
    }
    return $fragment
}

function Format-MarkdownText {
    <#
    .SYNOPSIS
    Escape markdown special characters in text
    #>
    param([string]$Text)
    
    if ([string]::IsNullOrEmpty($Text)) {
        return ""
    }
    
    # Escape pipe characters for markdown tables
    $Text = $Text -replace '\|', '\|'
    
    return $Text
}

function Format-Tags {
    <#
    .SYNOPSIS
    Normalize a tags string: split by comma or semicolon, trim, sort alphabetically, rejoin with "; ".
    #>
    param([string]$Tags)
    
    if ([string]::IsNullOrWhiteSpace($Tags)) {
        return ""
    }
    
    $sorted = $Tags -split '\s*[,;]\s*' |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.Trim() } |
        Sort-Object
    
    return $sorted -join '; '
}

function Add-MarkdownLineBreaks {
    <#
    .SYNOPSIS
    Add 2 trailing spaces to lines for markdown line breaks (except headers, bullets, tables)
    #>
    param([string]$Text)
    
    if ([string]::IsNullOrEmpty($Text)) {
        return ""
    }

    # Strip HTML structural tags from AzDo HTML field values (e.g. <header>, <div>, <p>)
    # so that exported markdown is plain text, matching what Normalize-HtmlValue produces
    # on the AzDo side during comparison in NewAzDoHierarchyFromMarkdown.ps1.
    $Text = $Text -replace '<[^>]+>', ''

    # Decode HTML entities to plain text. AzDo stores rich-text fields as HTML so
    # entities like &lt;ISO8601&gt; must be decoded to their literal characters for
    # the exported markdown. After stripping tags above, no bare < remains from HTML
    # structure, so no re-encoding is needed.
    $Text = $Text -replace '&nbsp;', ' '
    $Text = $Text -replace '&lt;', '<'
    $Text = $Text -replace '&gt;', '>'
    $Text = $Text -replace '&amp;', '&'
    $Text = $Text -replace '&quot;', '"'

    # Split text by newlines
    $lines = $Text -split "`n"
    $result = @()
    
    foreach ($line in $lines) {
        # Don't add trailing spaces to:
        # - Headers (lines starting with #)
        # - Bullet points (lines starting with -, *, +)
        # - Numbered lists (lines starting with digits followed by period/paren)
        # - Tables (lines with |)
        # - Empty lines
        
        if ($line -match '^\s*$' -or `
            $line -match '^\s*[#]{1,6}\s' -or `
            $line -match '^\s*[-*+]\s' -or `
            $line -match '^\s*\d+[\.\)]\s' -or `
            $line -match '\|' -or `
            $line.TrimEnd() -match '^`{3,}') {
            # Don't add trailing spaces
            $result += $line
        }
        else {
            # Strip any existing trailing whitespace first, then add exactly 2 spaces.
            # Avoids doubling trailing spaces on round-trip when AzDo already stores them.
            $result += "$($line.TrimEnd())  "
        }
    }
    
    return $result -join "`n"
}

function New-StateWarningComment {
    <#
    .SYNOPSIS
    Generate a warning comment for non-writable states
    #>
    param(
        [string]$State,
        [string]$WorkItemType,
        [string[]]$WritableStates
    )
    
    $statesStr = $WritableStates -join ', '
    
    return @"
<!-- WARNING: State '$State' is NOT in the writable states list for $WorkItemType items.
     Writable states: $statesStr
     During reimport, any state changes will be ignored. Do NOT modify the state field. -->
"@
}

function Convert-StoryToMarkdown {
    <#
    .SYNOPSIS
    Convert a Story hierarchy to markdown
    #>
    param(
        [PSObject]$Story
    )
    
    $Id = $Story.Id
    $Title = Format-MarkdownText $Story.Title
    $State = $Story.State
    $Description = $Story.Description
    $AcceptanceCriteria = $Story.AcceptanceCriteria
    $AcceptanceTests = $Story.AcceptanceTests
    $StoryPoints = $Story.StoryPoints
    $Tags = $Story.Tags
    $ExtraInformation = $Story.ExtraInformation
    $CustomFields = if ($Story.PSObject.Properties.Name -contains 'CustomFields') { $Story.CustomFields } else { @{} }
    
    # Determine if state is writable
    $workItemType = "Story"
    $writableStates = $config.writableStates.$workItemType
    $isStateWritable = $writableStates -contains $State
    
    # Build markdown output
    $markdown = @"
### Story: $Title

"@
    
    # Add warning comment if state is not writable
    if (-not $isStateWritable) {
        $markdown += (New-StateWarningComment -State $State -WorkItemType $workItemType -WritableStates $writableStates)
        $markdown += "`n`n"
    }
    
    # Add metadata
    $markdown += "{WorkItemId}: $Id  `n"
    
    if ($Tags) {
        $markdown += "{tags}: $(Format-Tags $Tags)  `n"
    }
    
    if ($StoryPoints) {
        $markdown += "{Story Points}: $StoryPoints  `n"
    }
    
    # Add State field to metadata
    $stateMarker = if ($isStateWritable) { "" } else { " ⚠️ (read-only)" }
    $markdown += "{State}: $State$stateMarker  `n"
    
    # Add config-driven fields (from configFields hashtable, in config order)
    $markdown += Get-ConfigFieldsMarkdown -Item $Story -WorkItemType 'User Story'
    
    # Add description
    if ($Description) {
        $markdown += "{Description}  `n"
        $markdown += (Add-MarkdownLineBreaks $Description)
        $markdown += "`n"
    }
    
    # Add acceptance criteria
    if ($AcceptanceCriteria) {
        $markdown += "`n{Acceptance Criteria}  `n"
        $markdown += (Add-MarkdownLineBreaks $AcceptanceCriteria)
        $markdown += "`n"
    }
    
    # Add Acceptance Tests
    if ($AcceptanceTests) {
        $markdown += "`n{Acceptance Tests}  `n"
        $markdown += (Add-MarkdownLineBreaks $AcceptanceTests)
        $markdown += "`n"
    }
    
    # Add extra information
    if ($ExtraInformation) {
        $markdown += "`n{Extra Information}  `n"
        $markdown += (Add-MarkdownLineBreaks $ExtraInformation)
        $markdown += "`n"
    }
    
    # Add tasks if present (check if Tasks property exists and has items)
    if ($Story.PSObject.Properties.Name -contains 'Tasks' -and $null -ne $Story.Tasks -and $Story.Tasks.Count -gt 0) {
        $markdown += "`n"
        foreach ($task in $Story.Tasks) {
            $taskId = $task.Id
            $taskTitle = Format-MarkdownText $task.Title
            $taskState = $task.State
            $taskDescription = $task.Description
            
            # Determine if task state is writable
            $taskType = "Task"
            $taskWritableStates = $config.writableStates.$taskType
            $isTaskStateWritable = $taskWritableStates -contains $taskState
            
            # Add warning if task state is not writable
            if (-not $isTaskStateWritable) {
                $markdown += (New-StateWarningComment -State $taskState -WorkItemType $taskType -WritableStates $taskWritableStates)
                $markdown += "`n"
            }
            
            $markdown += "#### Task: $taskTitle  `n`n"
            $markdown += "{WorkItemId}: $taskId  `n"
            $markdown += "{State}: $taskState$(if (-not $isTaskStateWritable) { ' ⚠️ (read-only)' })  `n"
            
            if ($taskDescription) {
                $markdown += "{Description}  `n"
                $markdown += (Add-MarkdownLineBreaks $taskDescription)
                $markdown += "`n"
            }
            
            $markdown += "`n"
        }
    }
    
    # Add bugs if present (check if Bugs property exists and has items)
    if ($Story.PSObject.Properties.Name -contains 'Bugs' -and $null -ne $Story.Bugs -and $Story.Bugs.Count -gt 0) {
        $markdown += "`n"
        foreach ($bug in $Story.Bugs) {
            $bugId = $bug.Id
            $bugTitle = Format-MarkdownText $bug.Title
            $bugState = $bug.State
            $bugDescription = $bug.Description
            
            # Determine if bug state is writable
            $bugType = "Bug"
            $bugWritableStates = $config.writableStates.$bugType
            $isBugStateWritable = $bugWritableStates -contains $bugState
            
            # Add warning if bug state is not writable
            if (-not $isBugStateWritable) {
                $markdown += (New-StateWarningComment -State $bugState -WorkItemType $bugType -WritableStates $bugWritableStates)
                $markdown += "`n"
            }
            
            $markdown += "#### Bug: $bugTitle  `n`n"
            $markdown += "{WorkItemId}: $bugId  `n"
            $markdown += "{State}: $bugState$(if (-not $isBugStateWritable) { ' ⚠️ (read-only)' })  `n"
            
            if ($bugDescription) {
                $markdown += "{Description}  `n"
                $markdown += (Add-MarkdownLineBreaks $bugDescription)
                $markdown += "`n"
            }
            
            $markdown += "`n"
        }
    }
    
    return $markdown
}

function Convert-FeatureToMarkdown {
    <#
    .SYNOPSIS
    Convert a Feature hierarchy to markdown
    #>
    param(
        [PSObject]$Feature
    )
    
    $Id = $Feature.Id
    $Title = Format-MarkdownText $Feature.Title
    $State = $Feature.State
    $Description = $Feature.Description
    $Effort = $Feature.Effort
    $Tags = $Feature.Tags
    
    # Determine if state is writable
    $workItemType = "Feature"
    $writableStates = $config.writableStates.$workItemType
    $isStateWritable = $writableStates -contains $State
    
    # Build markdown output
    $markdown = @"
## Feature: $Title

"@
    
    # Add warning comment if state is not writable
    if (-not $isStateWritable) {
        $markdown += (New-StateWarningComment -State $State -WorkItemType $workItemType -WritableStates $writableStates)
        $markdown += "`n`n"
    }
    
    # Add metadata
    $markdown += "{WorkItemId}: $Id  `n"
    
    if ($Tags) {
        $markdown += "{tags}: $(Format-Tags $Tags)  `n"
    }
    
    if ($Effort) {
        $markdown += "{Effort}: $Effort  `n"
    }
    
    # Add State field to metadata
    $stateMarker = if ($isStateWritable) { "" } else { " ⚠️ (read-only)" }
    $markdown += "{State}: $State$stateMarker  `n"
    
    # Add config-driven fields (from configFields hashtable, in config order)
    $markdown += Get-ConfigFieldsMarkdown -Item $Feature -WorkItemType 'Feature'
    
    # Add description
    if ($Description) {
        $markdown += "{Description}  `n"
        $markdown += (Add-MarkdownLineBreaks $Description)
        $markdown += "`n"
    }
    
    # Add stories if present (check if Stories property exists and has items)
    if ($Feature.PSObject.Properties.Name -contains 'Stories' -and $null -ne $Feature.Stories -and $Feature.Stories.Count -gt 0) {
        $markdown += "`n"
        foreach ($story in $Feature.Stories) {
            $markdown += (Convert-StoryToMarkdown -Story $story)
            $markdown += "`n"
        }
    }
    
    return $markdown
}

function Convert-EpicToMarkdown {
    <#
    .SYNOPSIS
    Convert an Epic hierarchy to markdown
    #>
    param(
        [PSObject]$Epic
    )
    
    $Id = $Epic.Id
    $Title = Format-MarkdownText $Epic.Title
    $State = $Epic.State
    $Description = $Epic.Description
    $Effort = $Epic.Effort
    $Tags = $Epic.Tags
    
    # Determine if state is writable
    $workItemType = "Epic"
    $writableStates = $config.writableStates.$workItemType
    $isStateWritable = $writableStates -contains $State
    
    # Build markdown output
    $markdown = @"
# Epic: $Title

"@
    
    # Add warning comment if state is not writable
    if (-not $isStateWritable) {
        $markdown += (New-StateWarningComment -State $State -WorkItemType $workItemType -WritableStates $writableStates)
        $markdown += "`n`n"
    }
    
    # Add metadata
    $markdown += "{WorkItemId}: $Id  `n"
    
    if ($Tags) {
        $markdown += "{tags}: $(Format-Tags $Tags)  `n"
    }
    
    if ($Effort) {
        $markdown += "{Effort}: $Effort  `n"
    }
    
    # Add State field to metadata
    $stateMarker = if ($isStateWritable) { "" } else { " ⚠️ (read-only)" }
    $markdown += "{State}: $State$stateMarker  `n"
    
    # Add config-driven fields (from configFields hashtable, in config order)
    $markdown += Get-ConfigFieldsMarkdown -Item $Epic -WorkItemType 'Epic'
    
    # Add description
    if ($Description) {
        $markdown += "{Description}  `n"
        $markdown += (Add-MarkdownLineBreaks $Description)
        $markdown += "`n"
    }
    
    # Add features if present (check if Features property exists and has items)
    if ($Epic.PSObject.Properties.Name -contains 'Features' -and $null -ne $Epic.Features -and $Epic.Features.Count -gt 0) {
        $markdown += "`n"
        foreach ($feature in $Epic.Features) {
            $markdown += (Convert-FeatureToMarkdown -Feature $feature)
            $markdown += "`n"
        }
    }
    
    return $markdown
}

try {
    # Validate hierarchy
    if ($null -eq $Hierarchy) {
        throw "Hierarchy parameter cannot be null"
    }
    
    if ($null -eq $Hierarchy.Id) {
        throw "Hierarchy must contain an Id field"
    }
    
    if ($null -eq $Hierarchy.Title) {
        throw "Hierarchy must contain a Title field"
    }
    
    # Determine hierarchy type and convert accordingly
    # Check if Features property exists (this is an Epic)
    if ($Hierarchy.PSObject.Properties.Name -contains 'Features') {
        $markdown = Convert-EpicToMarkdown -Epic $Hierarchy
    }
    # Check if Stories property exists (this is a Feature)
    elseif ($Hierarchy.PSObject.Properties.Name -contains 'Stories') {
        $markdown = Convert-FeatureToMarkdown -Feature $Hierarchy
    }
    # Otherwise it's a Story
    else {
        $markdown = Convert-StoryToMarkdown -Story $Hierarchy
    }
    
    return $markdown
}
catch {
    Write-Error "Failed to convert hierarchy to markdown: $_"
    throw
}
