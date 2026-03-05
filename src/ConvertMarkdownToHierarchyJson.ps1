<#
.SYNOPSIS
Converts markdown hierarchy file to machine-friendly JSON structure

.DESCRIPTION
Parses a markdown file using hierarchical headers and produces a JSON structure representing
the hierarchy of Epic/Feature/Story work items with all their metadata. This adapter script
validates that all markdown content is properly captured and can be easily inspected.

Markdown format (with required type prefixes):
    # Epic: Epic Title
    **tags**: tag1, tag2
    **Description**
    Multi-line description with headers at level 3+
    ### Header in Epic Description
    More content here
    
    ## Feature: Feature Title
    **tags**: tag1, tag2
    **Description**
    Feature description with headers at level 3+
    ### Header in Feature Description
    
    ### Story: Story Title
    **tags**: tag1, tag2
    **SP**: 5
    **Description**
    Story description with headers at level 4+
    #### Header in Story Description
    
    #### Acceptance Criteria
    - [ ] Criterion 1
    
    #### AC Scenarios
    1. **Scenario**: First scenario
    
    #### Extra Information
    Additional notes

Validation Rules:
- Epic, Feature, and Story titles must be prefixed with "Epic: ", "Feature: ", and "Story: " respectively
- Headers in epic and feature descriptions must start at level 3 (###) or higher
- Headers in story descriptions must start at level 4 (####) or higher
- Newlines in descriptions can be enforced with trailing backslash

Output JSON structure:
    {
      "epics": [...],
      "topLevelFeatures": [...]
    }

.PARAMETER MarkdownFilePath
Path to markdown file to parse (required)

.OUTPUTS
JSON object with parsed hierarchy

.EXAMPLE
Convert markdown to JSON:
    .\ConvertMarkdownToHierarchyJson.ps1 -MarkdownFilePath "hierarchy.md" | ConvertTo-Json -Depth 10

Inspect structure:
    $json = .\ConvertMarkdownToHierarchyJson.ps1 -MarkdownFilePath "hierarchy.md"
    $json.epics[0].features[0].stories | Select-Object title, description

.NOTES
- Markdown file must exist and be readable
- Validates entire structure during parsing (including title prefixes and header levels in descriptions)
- Descriptions are preserved as-is from markdown (with newlines)
- All content is normalized and validated before output
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$MarkdownFilePath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Import modules
. "$PSScriptRoot\AzDoAutomatorConstants.ps1"

# ============================================================================
# Helper Functions for Description Validation
# ============================================================================

<#
.SYNOPSIS
Validates that epic and feature descriptions don't have headers at levels 1-2
#>
function Test-DescriptionHeaderLevelsForEpicFeature {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [string]$ItemType  # 'Epic' or 'Feature'
    )
    
    [string[]]$lines = $Description -split "`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $script:REGEX_MARKDOWN_HEADER_LEVEL_1_2) {
            throw "$ItemType description at line $i contains level 1/2 header (# or ##). Headers in $ItemType descriptions must start at level 3 (###) or higher to distinguish from hierarchy headers."
        }
    }
}

<#
.SYNOPSIS
Validates that story descriptions don't have headers at levels 1-3
#>
function Test-DescriptionHeaderLevelsForStory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description
    )
    
    [string[]]$lines = $Description -split "`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $script:REGEX_MARKDOWN_HEADER_LEVEL_1_2_3) {
            throw "Story description at line $i contains level 1/2/3 header (#, ##, or ###). Headers in story descriptions must start at level 4 (####) or higher to distinguish from hierarchy headers."
        }
    }
}

# Validate markdown file
if (-not (Test-Path -LiteralPath $MarkdownFilePath -PathType Leaf)) {
    throw "Markdown file not found: $MarkdownFilePath"
}

Write-Debug "Parsing markdown file: $MarkdownFilePath"

# Read and parse markdown file
[string[]]$lines = @(Get-Content -LiteralPath $MarkdownFilePath -Raw) -split "`n"

# Structure to hold parsed data
[object[]]$epics = @()
[hashtable]$currentEpic = $null
[object[]]$topLevelFeatures = @()
[hashtable]$currentFeature = $null
[hashtable]$currentStory = $null

# State machine for parsing
[string]$currentLineType = $null # 'epic', 'feature', 'story', 'epic_desc', 'feature_desc', 'story_desc', 'section'
[string]$currentSectionType = $null # 'AC', 'ACS', 'EI'
[string[]]$descriptionLines = @()
[string[]]$sectionLines = @()

Write-Debug "Starting markdown parse..."

for ($lineNum = 0; $lineNum -lt $lines.Count; $lineNum++) {
    [string]$line = $lines[$lineNum].TrimEnd()
    
    # Skip empty lines and comments
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('<!')) {
        # If collecting description and this is an empty line that's not at section boundary, it might be the end
        if ($currentLineType -match '_desc$' -and ($lineNum + 1 -lt $lines.Count)) {
            [string]$nextLine = $lines[$lineNum + 1].TrimEnd()
            if (-not [string]::IsNullOrWhiteSpace($nextLine) -and -not ($nextLine -match '^#{1,4}\s')) {
                # Not a header coming,  might be mid-description, continue skipping empty line
                continue
            }
            # Empty line before header or end of content, treat as end of description
            if ($descriptionLines.Count -gt 0) {
                [string]$desc = ($descriptionLines | Join-String -Separator "`n").Trim()
                if ($currentLineType -eq 'epic_desc' -and $null -ne $currentEpic) {
                    Test-DescriptionHeaderLevelsForEpicFeature -Description $desc -ItemType 'Epic'
                    $currentEpic['description'] = $desc
                }
                elseif ($currentLineType -eq 'feature_desc' -and $null -ne $currentFeature) {
                    Test-DescriptionHeaderLevelsForEpicFeature -Description $desc -ItemType 'Feature'
                    $currentFeature['description'] = $desc
                }
                elseif ($currentLineType -eq 'story_desc' -and $null -ne $currentStory) {
                    Test-DescriptionHeaderLevelsForStory -Description $desc
                    $currentStory['description'] = $desc
                }
                Write-Debug "Finalized description from empty line"
                $descriptionLines = @()
                $currentLineType = $null
            }
        }
        continue
    }

    # Section headers (#### ...)
    if ($line -match $script:REGEX_MARKDOWN_SECTION_HEADER) {
        # Finalize any active description first
        if ($descriptionLines.Count -gt 0) {
            [string]$desc = ($descriptionLines | Join-String -Separator "`n").Trim()
            if ($currentLineType -eq 'epic_desc' -and $null -ne $currentEpic) {
                Test-DescriptionHeaderLevelsForEpicFeature -Description $desc -ItemType 'Epic'
                $currentEpic['description'] = $desc
            }
            elseif ($currentLineType -eq 'feature_desc' -and $null -ne $currentFeature) {
                Test-DescriptionHeaderLevelsForEpicFeature -Description $desc -ItemType 'Feature'
                $currentFeature['description'] = $desc
            }
            elseif ($currentLineType -eq 'story_desc' -and $null -ne $currentStory) {
                Test-DescriptionHeaderLevelsForStory -Description $desc
                $currentStory['description'] = $desc
            }
            $descriptionLines = @()
        }
        
        # Finalize any active section before starting a new one
        if ($currentLineType -eq 'section' -and $null -ne $currentSectionType -and $sectionLines.Count -gt 0) {
            [string]$sectionContent = ($sectionLines | Join-String -Separator "`n").Trim()
            if ($currentSectionType -eq 'AC' -and $null -ne $currentStory) { $currentStory['acceptanceCriteria'] = $sectionContent }
            elseif ($currentSectionType -eq 'ACS' -and $null -ne $currentStory) { $currentStory['acScenarios'] = $sectionContent }
            elseif ($currentSectionType -eq 'EI' -and $null -ne $currentStory) { $currentStory['extraInformation'] = $sectionContent }
            $sectionLines = @()
        }
        
        [string]$sectionTitle = $matches[1].Trim()
        if ($sectionTitle -match 'Acceptance Criteria') {
            $currentSectionType = 'AC'
        }
        elseif ($sectionTitle -match 'AC Scenarios') {
            $currentSectionType = 'ACS'
        }
        elseif ($sectionTitle -match 'Extra Information') {
            $currentSectionType = 'EI'
        }
        $sectionLines = @()
        $currentLineType = 'section'
        Write-Debug "Found section: $sectionTitle"
        continue
    }

    # If we're in a section, collect lines for it
    if ($currentLineType -eq 'section') {
        if ($line -match '^#{1,3}\s') {
            # New hierarchy header, finalize section
            if ($sectionLines.Count -gt 0) {
                [string]$sectionContent = ($sectionLines | Join-String -Separator "`n").Trim()
                if ($currentSectionType -eq 'AC' -and $null -ne $currentStory) { $currentStory['acceptanceCriteria'] = $sectionContent }
                elseif ($currentSectionType -eq 'ACS' -and $null -ne $currentStory) { $currentStory['acScenarios'] = $sectionContent }
                elseif ($currentSectionType -eq 'EI' -and $null -ne $currentStory) { $currentStory['extraInformation'] = $sectionContent }
            }
            $sectionLines = @()
            $currentSectionType = $null
            $currentLineType = $null
            # Fall through to process the header
        }
        else {
            $sectionLines += $line
            continue
        }
    }

    # Hierarchy headers - these reset or create new items
    if ($line -match $script:REGEX_MARKDOWN_EPIC) {
        # Finalize any pending description
        if ($descriptionLines.Count -gt 0) {
            [string]$desc = ($descriptionLines | Join-String -Separator "`n").Trim()
            if ($currentLineType -eq 'epic_desc' -and $null -ne $currentEpic) {
                Test-DescriptionHeaderLevelsForEpicFeature -Description $desc -ItemType 'Epic'
                $currentEpic['description'] = $desc
            }
            $descriptionLines = @()
        }
        
        [string]$epicTitle = $matches[1].Trim()
        if ([string]::IsNullOrWhiteSpace($epicTitle)) {
            throw "Invalid Epic title at line $($lineNum+1) : Title cannot be empty"
        }
        $currentEpic = @{
            title       = $epicTitle
            tags        = @()
            description = $null
            features    = @()
        }
        $epics += $currentEpic
        $currentFeature = $null
        $currentStory = $null
        $currentLineType = 'epic'
        Write-Debug "Found Epic: $epicTitle"
        continue
    }

    if ($line -match $script:REGEX_MARKDOWN_FEATURE) {
        # Finalize any pending description
        if ($descriptionLines.Count -gt 0) {
            [string]$desc = ($descriptionLines | Join-String -Separator "`n").Trim()
            if ($currentLineType -eq 'epic_desc' -and $null -ne $currentEpic) {
                Test-DescriptionHeaderLevelsForEpicFeature -Description $desc -ItemType 'Epic'
                $currentEpic['description'] = $desc
            }
            elseif ($currentLineType -eq 'feature_desc' -and $null -ne $currentFeature) {
                Test-DescriptionHeaderLevelsForEpicFeature -Description $desc -ItemType 'Feature'
                $currentFeature['description'] = $desc
            }
            $descriptionLines = @()
        }
        
        [string]$featureTitle = $matches[1].Trim()
        if ([string]::IsNullOrWhiteSpace($featureTitle)) {
            throw "Invalid Feature title at line $($lineNum+1) : Title cannot be empty"
        }
        $currentFeature = @{
            title       = $featureTitle
            tags        = @()
            description = $null
            stories     = @()
        }
        if ($null -ne $currentEpic) {
            $currentEpic.features += $currentFeature
        }
        else {
            $topLevelFeatures += $currentFeature
        }
        $currentStory = $null
        $currentLineType = 'feature'
        Write-Debug "Found Feature: $featureTitle"
        continue
    }

    if ($line -match $script:REGEX_MARKDOWN_STORY) {
        # Finalize any pending description
        if ($descriptionLines.Count -gt 0) {
            [string]$desc = ($descriptionLines | Join-String -Separator "`n").Trim()
            if ($currentLineType -eq 'epic_desc' -and $null -ne $currentEpic) {
                Test-DescriptionHeaderLevelsForEpicFeature -Description $desc -ItemType 'Epic'
                $currentEpic['description'] = $desc
            }
            elseif ($currentLineType -eq 'feature_desc' -and $null -ne $currentFeature) {
                Test-DescriptionHeaderLevelsForEpicFeature -Description $desc -ItemType 'Feature'
                $currentFeature['description'] = $desc
            }
            elseif ($currentLineType -eq 'story_desc' -and $null -ne $currentStory) {
                Test-DescriptionHeaderLevelsForStory -Description $desc
                $currentStory['description'] = $desc
            }
            $descriptionLines = @()
        }
        
        [string]$storyTitle = $matches[1].Trim()
        if ([string]::IsNullOrWhiteSpace($storyTitle)) {
            throw "Invalid Story title at line $($lineNum+1) : Title cannot be empty"
        }
        if ($null -eq $currentFeature) {
            throw "Story found at line $($lineNum+1) but no parent Feature: $storyTitle"
        }
        $currentStory = @{
            title                = $storyTitle
            tags                 = @()
            description          = $null
            storyPoints          = $null
            acceptanceCriteria   = $null
            acScenarios          = $null
            extraInformation     = $null
        }
        $currentFeature.stories += $currentStory
        $currentLineType = 'story'
        Write-Debug "Found Story: $storyTitle"
        continue
    }

    # Metadata lines
    if ($line -match $script:REGEX_MARKDOWN_TAGS) {
        [string]$tagsStr = $matches[1].Trim() -replace '\\$', ''
        
        # Extract Story Points if found inline: **tags**: ... **SP**: number\
        if ($tagsStr -match '\*\*SP\*\*:\s*(\d+)') {
            [int]$sp = [int]$matches[1]
            if ($sp -lt 0) {
                throw "Invalid Story Points at line $($lineNum+1) : Must be non-negative. Found: $sp"
            }
            if ($null -ne $currentStory) {
                $currentStory['storyPoints'] = $sp
            }
            # Remove SP from tags string
            $tagsStr = $tagsStr -replace '\s*\*\*SP\*\*:\s*\d+', ''
        }
        
        if (-not [string]::IsNullOrWhiteSpace($tagsStr)) {
            [string[]]$tagsList = @($tagsStr -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($null -ne $currentStory) {
                $currentStory['tags'] = $tagsList
            }
            elseif ($null -ne $currentFeature) {
                $currentFeature['tags'] = $tagsList
            }
            elseif ($null -ne $currentEpic) {
                $currentEpic['tags'] = $tagsList
            }
        }
        continue
    }

    if ($line -match '^\*\*SP\*\*:\s*(\d+)') {
        [int]$sp = $matches[1]
        if ($sp -lt 0) {
            throw "Invalid Story Points at line $($lineNum+1) : Must be non-negative. Found: $sp"
        }
        if ($null -eq $currentStory) {
            throw "Story Points found at line $($lineNum+1) but no parent Story"
        }
        $currentStory['storyPoints'] = $sp
        continue
    }

    # Description start marker
    if ($line -match $script:REGEX_MARKDOWN_DESCRIPTION_START) {
        $currentLineType = if ($null -ne $currentStory) { 'story_desc' } elseif ($null -ne $currentFeature) { 'feature_desc' } else { 'epic_desc' }
        $descriptionLines = @()
        Write-Debug "Started collecting description for $currentLineType"
        continue
    }

    # If we're collecting a description, add to it
    if ($currentLineType -match '_desc$') {
        $descriptionLines += $line
        continue
    }
}

# Finalize any pending data
if ($descriptionLines.Count -gt 0) {
    [string]$desc = ($descriptionLines | Join-String -Separator "`n").Trim()
    if ($currentLineType -eq 'epic_desc' -and $null -ne $currentEpic) {
        Test-DescriptionHeaderLevelsForEpicFeature -Description $desc -ItemType 'Epic'
        $currentEpic['description'] = $desc
    }
    elseif ($currentLineType -eq 'feature_desc' -and $null -ne $currentFeature) {
        Test-DescriptionHeaderLevelsForEpicFeature -Description $desc -ItemType 'Feature'
        $currentFeature['description'] = $desc
    }
    elseif ($currentLineType -eq 'story_desc' -and $null -ne $currentStory) {
        Test-DescriptionHeaderLevelsForStory -Description $desc
        $currentStory['description'] = $desc
    }
}

if ($sectionLines.Count -gt 0 -and $null -ne $currentSectionType) {
    [string]$sectionContent = ($sectionLines | Join-String -Separator "`n").Trim()
    if ($currentSectionType -eq 'AC' -and $null -ne $currentStory) { $currentStory['acceptanceCriteria'] = $sectionContent }
    elseif ($currentSectionType -eq 'ACS' -and $null -ne $currentStory) { $currentStory['acScenarios'] = $sectionContent }
    elseif ($currentSectionType -eq 'EI' -and $null -ne $currentStory) { $currentStory['extraInformation'] = $sectionContent }
}

Write-Debug "Markdown parsing complete - finalized any pending sections"

# Build the output JSON structure
$output = @{
    epics             = $epics
    topLevelFeatures  = $topLevelFeatures
}

return $output
