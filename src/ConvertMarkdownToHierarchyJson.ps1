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

<#
.SYNOPSIS
Validates that bug descriptions don't have headers at levels 1-4
#>
function Test-DescriptionHeaderLevelsForBug {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description
    )
    
    [string[]]$lines = $Description -split "`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $script:REGEX_MARKDOWN_HEADER_LEVEL_1_2_3_4) {
            throw "Bug description at line $i contains level 1/2/3/4 header (#, ##, ###, or ####). Headers in bug descriptions must start at level 5 (#####) or higher to distinguish from hierarchy headers."
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
[hashtable]$currentBug = $null

# State machine for parsing
[string]$currentLineType = $null # 'epic', 'feature', 'story', 'bug', 'epic_desc', 'feature_desc', 'story_desc', 'bug_desc', 'section'
[string]$currentSectionType = $null # 'AC', 'ACS', 'EI', 'RS', 'SI', 'FIB', 'IIB'
[string[]]$descriptionLines = @()
[string[]]$sectionLines = @()

Write-Debug "Starting markdown parse..."

for ($lineNum = 0; $lineNum -lt $lines.Count; $lineNum++) {
    [string]$line = $lines[$lineNum].TrimEnd()
    
    # Skip empty lines and comments
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('<!')) {
        # If collecting description and this is an empty line that's not at section boundary, check what comes next
        if ($currentLineType -match '_desc$' -and ($lineNum + 1 -lt $lines.Count)) {
            # Skip consecutive empty/blank lines to find the next non-empty line
            [int]$nextNonEmptyIdx = $lineNum + 1
            while ($nextNonEmptyIdx -lt $lines.Count -and [string]::IsNullOrWhiteSpace($lines[$nextNonEmptyIdx])) {
                $nextNonEmptyIdx++
            }
            
            [bool]$isHierarchyBoundary = $false
            if ($nextNonEmptyIdx -lt $lines.Count) {
                [string]$nextLine = $lines[$nextNonEmptyIdx].TrimEnd()
                
                # For Epic descriptions: stop at # Epic: or ## Feature:
                if ($currentLineType -eq 'epic_desc') {
                    $isHierarchyBoundary = ($nextLine -match $script:REGEX_MARKDOWN_EPIC) -or ($nextLine -match $script:REGEX_MARKDOWN_FEATURE)
                }
                # For Feature descriptions: stop at ## Feature: or ### Story: or # Epic:
                elseif ($currentLineType -eq 'feature_desc') {
                    $isHierarchyBoundary = ($nextLine -match $script:REGEX_MARKDOWN_FEATURE) -or ($nextLine -match $script:REGEX_MARKDOWN_STORY) -or ($nextLine -match $script:REGEX_MARKDOWN_EPIC)
                }
                # For Story descriptions: stop at ### Story: or #### Bug: or ## Feature: or # Epic: or #### SectionHeader
                elseif ($currentLineType -eq 'story_desc') {
                    $isHierarchyBoundary = ($nextLine -match $script:REGEX_MARKDOWN_STORY) -or ($nextLine -match $script:REGEX_MARKDOWN_BUG) -or ($nextLine -match $script:REGEX_MARKDOWN_FEATURE) -or ($nextLine -match $script:REGEX_MARKDOWN_EPIC) -or ($nextLine -match $script:REGEX_MARKDOWN_SECTION_HEADER)
                }
                # For Bug descriptions: stop at #### Bug: or ### Story: or ## Feature: or # Epic: or ##### SectionHeader
                elseif ($currentLineType -eq 'bug_desc') {
                    $isHierarchyBoundary = ($nextLine -match $script:REGEX_MARKDOWN_BUG) -or ($nextLine -match $script:REGEX_MARKDOWN_STORY) -or ($nextLine -match $script:REGEX_MARKDOWN_FEATURE) -or ($nextLine -match $script:REGEX_MARKDOWN_EPIC) -or ($nextLine -match '^\#\#\#\#\#\s')
                }
                
                if (-not $isHierarchyBoundary) {
                    # Not a hierarchy boundary coming, might be mid-description, continue skipping empty lines
                    continue
                }
            }
            
            # Empty line(s) before hierarchy boundary or end of content, treat as end of description
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
                elseif ($currentLineType -eq 'bug_desc' -and $null -ne $currentBug) {
                    Test-DescriptionHeaderLevelsForBug -Description $desc
                    $currentBug['description'] = $desc
                }
                Write-Debug "Finalized description from empty line(s)"
                $descriptionLines = @()
                $currentLineType = $null
            }
        }
        continue
    }

    # Section headers (#### ...) - but only finalize description if we're in a story or bug
    if ($line -match $script:REGEX_MARKDOWN_SECTION_HEADER) {
        # Only treat as section header if we're collecting story description, in section mode, or have an active story
        if ($currentLineType -eq 'story_desc' -or $currentLineType -eq 'section' -or ($null -ne $currentStory -and [string]::IsNullOrWhiteSpace($currentLineType))) {
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
                elseif ($currentLineType -eq 'bug_desc' -and $null -ne $currentBug) {
                    Test-DescriptionHeaderLevelsForBug -Description $desc
                    $currentBug['description'] = $desc
                }
                $descriptionLines = @()
            }
            
            # Finalize any active section before starting a new one
            if ($currentLineType -eq 'section' -and $null -ne $currentSectionType -and $sectionLines.Count -gt 0) {
                [string]$sectionContent = ($sectionLines | Join-String -Separator "`n").Trim()
                if ($currentSectionType -eq 'AC' -and $null -ne $currentStory) { $currentStory['acceptanceCriteria'] = $sectionContent }
                elseif ($currentSectionType -eq 'ACS' -and $null -ne $currentStory) { $currentStory['acScenarios'] = $sectionContent }
                elseif ($currentSectionType -eq 'EI' -and $null -ne $currentStory) { $currentStory['extraInformation'] = $sectionContent }
                elseif ($currentSectionType -eq 'RS' -and $null -ne $currentBug) { $currentBug['reproSteps'] = $sectionContent }
                elseif ($currentSectionType -eq 'SI' -and $null -ne $currentBug) { $currentBug['systemInfo'] = $sectionContent }
                elseif ($currentSectionType -eq 'FIB' -and $null -ne $currentBug) { $currentBug['foundInBuild'] = $sectionContent }
                elseif ($currentSectionType -eq 'IIB' -and $null -ne $currentBug) { $currentBug['integratedInBuild'] = $sectionContent }
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
            elseif ($sectionTitle -match 'Repro Steps') {
                $currentSectionType = 'RS'
            }
            elseif ($sectionTitle -match 'System Info') {
                $currentSectionType = 'SI'
            }
            elseif ($sectionTitle -match 'Found in Build|Found In Build') {
                $currentSectionType = 'FIB'
            }
            elseif ($sectionTitle -match 'Integrated in Build|Integrated In Build') {
                $currentSectionType = 'IIB'
            }
            $sectionLines = @()
            $currentLineType = 'section'
            Write-Debug "Found section: $sectionTitle"
            continue
        }
        else {
            # For epic/feature descriptions, #### headers are part of the description content, not section markers
            if ($currentLineType -match '_desc$') {
                $descriptionLines += $line
                continue
            }
        }
    }
    
    # Also handle ##### headers for bug section markers
    if ($line -match '^\#\#\#\#\#\s+(.+)$') {
        if ($currentLineType -eq 'bug_desc' -or $currentLineType -eq 'section' -or ($null -ne $currentBug -and [string]::IsNullOrWhiteSpace($currentLineType))) {
            # Finalize any active description first
            if ($descriptionLines.Count -gt 0) {
                [string]$desc = ($descriptionLines | Join-String -Separator "`n").Trim()
                if ($currentLineType -eq 'bug_desc' -and $null -ne $currentBug) {
                    Test-DescriptionHeaderLevelsForBug -Description $desc
                    $currentBug['description'] = $desc
                }
                $descriptionLines = @()
            }
            
            # Finalize any active section before starting a new one
            if ($currentLineType -eq 'section' -and $null -ne $currentSectionType -and $sectionLines.Count -gt 0) {
                [string]$sectionContent = ($sectionLines | Join-String -Separator "`n").Trim()
                if ($currentSectionType -eq 'RS' -and $null -ne $currentBug) { $currentBug['reproSteps'] = $sectionContent }
                elseif ($currentSectionType -eq 'SI' -and $null -ne $currentBug) { $currentBug['systemInfo'] = $sectionContent }
                elseif ($currentSectionType -eq 'FIB' -and $null -ne $currentBug) { $currentBug['foundInBuild'] = $sectionContent }
                elseif ($currentSectionType -eq 'IIB' -and $null -ne $currentBug) { $currentBug['integratedInBuild'] = $sectionContent }
                $sectionLines = @()
            }
            
            [string]$sectionTitle = $matches[1].Trim()
            if ($sectionTitle -match 'Repro Steps') {
                $currentSectionType = 'RS'
            }
            elseif ($sectionTitle -match 'System Info') {
                $currentSectionType = 'SI'
            }
            elseif ($sectionTitle -match 'Found in Build|Found In Build') {
                $currentSectionType = 'FIB'
            }
            elseif ($sectionTitle -match 'Integrated in Build|Integrated In Build') {
                $currentSectionType = 'IIB'
            }
            $sectionLines = @()
            $currentLineType = 'section'
            Write-Debug "Found bug section: $sectionTitle"
            continue
        }
        else {
            # For bug descriptions, ##### headers are part of the description content, not section markers
            if ($currentLineType -eq 'bug_desc') {
                $descriptionLines += $line
                continue
            }
        }
    }

    # If we're in a section, collect lines for it
    if ($currentLineType -eq 'section') {
        if ($line -match '^#{1,3}\s' -or $line -match '^\#\#\#\#\s' -or $line -match '^\#\#\#\#\#\s') {
            # New hierarchy header, finalize section
            if ($sectionLines.Count -gt 0) {
                [string]$sectionContent = ($sectionLines | Join-String -Separator "`n").Trim()
                if ($currentSectionType -eq 'AC' -and $null -ne $currentStory) { $currentStory['acceptanceCriteria'] = $sectionContent }
                elseif ($currentSectionType -eq 'ACS' -and $null -ne $currentStory) { $currentStory['acScenarios'] = $sectionContent }
                elseif ($currentSectionType -eq 'EI' -and $null -ne $currentStory) { $currentStory['extraInformation'] = $sectionContent }
                elseif ($currentSectionType -eq 'RS' -and $null -ne $currentBug) { $currentBug['reproSteps'] = $sectionContent }
                elseif ($currentSectionType -eq 'SI' -and $null -ne $currentBug) { $currentBug['systemInfo'] = $sectionContent }
                elseif ($currentSectionType -eq 'FIB' -and $null -ne $currentBug) { $currentBug['foundInBuild'] = $sectionContent }
                elseif ($currentSectionType -eq 'IIB' -and $null -ne $currentBug) { $currentBug['integratedInBuild'] = $sectionContent }
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
            effort      = $null
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
            effort      = $null
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
            elseif ($currentLineType -eq 'bug_desc' -and $null -ne $currentBug) {
                Test-DescriptionHeaderLevelsForBug -Description $desc
                $currentBug['description'] = $desc
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
            bugs                 = @()
        }
        $currentFeature.stories += $currentStory
        $currentBug = $null
        $currentLineType = 'story'
        Write-Debug "Found Story: $storyTitle"
        continue
    }

    if ($line -match $script:REGEX_MARKDOWN_BUG) {
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
            elseif ($currentLineType -eq 'bug_desc' -and $null -ne $currentBug) {
                Test-DescriptionHeaderLevelsForBug -Description $desc
                $currentBug['description'] = $desc
            }
            $descriptionLines = @()
        }
        
        [string]$bugTitle = $matches[1].Trim()
        if ([string]::IsNullOrWhiteSpace($bugTitle)) {
            throw "Invalid Bug title at line $($lineNum+1) : Title cannot be empty"
        }
        if ($null -eq $currentStory) {
            throw "Bug found at line $($lineNum+1) but no parent Story: $bugTitle"
        }
        $currentBug = @{
            title                = $bugTitle
            tags                 = @()
            description          = $null
            storyPoints          = $null
            priority             = $null
            reproSteps           = $null
            systemInfo           = $null
            foundInBuild         = $null
            integratedInBuild    = $null
        }
        $currentStory.bugs += $currentBug
        $currentLineType = 'bug'
        Write-Debug "Found Bug: $bugTitle"
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
        if ($null -ne $currentBug) {
            $currentBug['storyPoints'] = $sp
        }
        elseif ($null -eq $currentStory) {
            throw "Story Points found at line $($lineNum+1) but no parent Story or Bug"
        }
        else {
            $currentStory['storyPoints'] = $sp
        }
        continue
    }

    if ($line -match $script:REGEX_MARKDOWN_PRIORITY) {
        [int]$priority = [int]$matches[1]
        if ($priority -lt 1 -or $priority -gt 4) {
            throw "Invalid Priority at line $($lineNum+1) : Must be between 1 and 4. Found: $priority"
        }
        if ($null -eq $currentBug) {
            throw "Priority found at line $($lineNum+1) but no parent Bug"
        }
        $currentBug['priority'] = $priority
        continue
    }

    if ($line -match '^\*\*Effort\*\*:\s*(\d+)') {
        [int]$effort = $matches[1]
        if ($effort -lt 0) {
            throw "Invalid Effort at line $($lineNum+1) : Must be non-negative. Found: $effort"
        }
        if ($null -ne $currentStory) {
            throw "Effort found at line $($lineNum+1) but should only be on Epic or Feature, not Story"
        }
        if ($null -ne $currentFeature) {
            $currentFeature['effort'] = $effort
        }
        elseif ($null -ne $currentEpic) {
            $currentEpic['effort'] = $effort
        }
        else {
            throw "Effort found at line $($lineNum+1) but no parent Epic or Feature"
        }
        continue
    }

    # Description start marker
    if ($line -match $script:REGEX_MARKDOWN_DESCRIPTION_START) {
        $currentLineType = if ($null -ne $currentBug) { 'bug_desc' } elseif ($null -ne $currentStory) { 'story_desc' } elseif ($null -ne $currentFeature) { 'feature_desc' } else { 'epic_desc' }
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
    elseif ($currentLineType -eq 'bug_desc' -and $null -ne $currentBug) {
        Test-DescriptionHeaderLevelsForBug -Description $desc
        $currentBug['description'] = $desc
    }
}

if ($sectionLines.Count -gt 0 -and $null -ne $currentSectionType) {
    [string]$sectionContent = ($sectionLines | Join-String -Separator "`n").Trim()
    if ($currentSectionType -eq 'AC' -and $null -ne $currentStory) { $currentStory['acceptanceCriteria'] = $sectionContent }
    elseif ($currentSectionType -eq 'ACS' -and $null -ne $currentStory) { $currentStory['acScenarios'] = $sectionContent }
    elseif ($currentSectionType -eq 'EI' -and $null -ne $currentStory) { $currentStory['extraInformation'] = $sectionContent }
    elseif ($currentSectionType -eq 'RS' -and $null -ne $currentBug) { $currentBug['reproSteps'] = $sectionContent }
    elseif ($currentSectionType -eq 'SI' -and $null -ne $currentBug) { $currentBug['systemInfo'] = $sectionContent }
    elseif ($currentSectionType -eq 'FIB' -and $null -ne $currentBug) { $currentBug['foundInBuild'] = $sectionContent }
    elseif ($currentSectionType -eq 'IIB' -and $null -ne $currentBug) { $currentBug['integratedInBuild'] = $sectionContent }
}

Write-Debug "Markdown parsing complete - finalized any pending sections"

# Add "autoGen" tag to all items (Epics, Features, Stories, Bugs)
foreach ($epic in $epics) {
    if ($epic.tags -notcontains 'autoGen') {
        $epic.tags += 'autoGen'
    }
    foreach ($feature in $epic.features) {
        if ($feature.tags -notcontains 'autoGen') {
            $feature.tags += 'autoGen'
        }
        foreach ($story in $feature.stories) {
            if ($story.tags -notcontains 'autoGen') {
                $story.tags += 'autoGen'
            }
            foreach ($bug in $story.bugs) {
                if ($bug.tags -notcontains 'autoGen') {
                    $bug.tags += 'autoGen'
                }
            }
        }
    }
}
foreach ($feature in $topLevelFeatures) {
    if ($feature.tags -notcontains 'autoGen') {
        $feature.tags += 'autoGen'
    }
    foreach ($story in $feature.stories) {
        if ($story.tags -notcontains 'autoGen') {
            $story.tags += 'autoGen'
        }
        foreach ($bug in $story.bugs) {
            if ($bug.tags -notcontains 'autoGen') {
                $bug.tags += 'autoGen'
            }
        }
    }
}

Write-Debug "Added 'autoGen' tag to all items"

# Build the output JSON structure
$output = @{
    epics             = $epics
    topLevelFeatures  = $topLevelFeatures
}

return $output
