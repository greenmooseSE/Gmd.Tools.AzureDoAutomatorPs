<#
.SYNOPSIS
Create or update Azure DevOps work item hierarchy from a markdown file or content string

.DESCRIPTION
Parses markdown content using hierarchical headers and creates or updates a hierarchy of
Epic/Feature/Story/Task work items. When a markdown file path is provided, work item IDs
are written back to the file after creation, enabling idempotent re-runs: subsequent
invocations update existing items by ID instead of creating duplicates.

Organization, Project, and PatToken are retrieved from environment variables:
- GMD_AZDO_ORGANIZATION: Azure DevOps organization name
- GMD_AZDO_PROJECT: Azure DevOps project name
- GMD_AZDO_MACHINE_WORKITEMSRW: PAT token for work item operations

Markdown format:
    # Epic: Epic Title
    **WorkItemId**: 2215  (written back after first run)
    **tags**: tag1, tag2
    **Description**
    Multi-line description text
    
    ## Feature: Feature Title
    **tags**: tag1, tag2
    **Description**
    Feature description
    
    ### Story: Story Title
    **tags**: tag1, tag2
    **SP**: 5
    **Description**
    Story description ...
    
    #### Task: Task Title
    **Priority**: 1
    **OriginalEstimate**: 4
    **Description**
    Task details

.PARAMETER MarkdownContent
The markdown hierarchy content as a string. Either -MarkdownContent or -MarkdownFile must be provided.

.PARAMETER MarkdownFile
Path to a markdown file containing the hierarchy content. Either -MarkdownContent or -MarkdownFile must be provided.
After work items are created, **WorkItemId**: <id> lines are inserted after each work item header
so that subsequent runs update existing items instead of creating new ones.

.PARAMETER EpicId
Optional: Parent Epic ID. If not provided, Features become top-level work items.

.PARAMETER DryRun
Switch: If specified, shows planned operations without creating work items

.PARAMETER UpdateExisting
Switch: If specified and an item has no WorkItemId in the markdown, matches existing work items
by title (ignoring "(001)" suffixes) and updates them instead of creating new ones.

.OUTPUTS
PSObject with summary of created/planned work items with hierarchy

.EXAMPLE
Preview what will be created (DryRun):
    .\NewAzDoHierarchyFromMarkdown.ps1 -MarkdownFile ".\my-hierarchy.md" -DryRun

.EXAMPLE
Create hierarchy and write IDs back to file (first run):
    .\NewAzDoHierarchyFromMarkdown.ps1 -MarkdownFile ".\my-hierarchy.md"

.EXAMPLE
Re-run on same file to update existing items (uses WorkItemIds already in the file):
    .\NewAzDoHierarchyFromMarkdown.ps1 -MarkdownFile ".\my-hierarchy.md"

.NOTES
- When WorkItemId is present in the markdown, it is used directly for ID-based updates
- WorkItemId lines are written back only when -MarkdownFile is used (not -MarkdownContent)
- Hierarchy is inferred from header levels: # = Epic, ## = Feature, ### = Story, #### = Task/Bug
- Tasks do NOT support Acceptance Criteria or AC Scenarios (only Description, Priority, time tracking fields)
- Tasks require a Story parent in the markdown structure (enforced during parsing)
- Use RemoveAzDoTask.ps1 for individual Task deletion
- Use RemoveAzDoEpic.ps1 for cascading delete of entire Epic hierarchies
#>

#Requires -Version 7.0

param(
    [string]$MarkdownContent,

    [string]$MarkdownFile,

    [int]$EpicId,

    [switch]$DryRun,

    [switch]$UpdateExisting
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Import modules
. "$PSScriptRoot\AzDoAutomatorConstants.ps1"
. "$PSScriptRoot\AzDoPatTokenHelper.ps1"
. "$PSScriptRoot\AzDoApiWrapper.ps1"
. "$PSScriptRoot\AzDoWorkItemHelper.ps1"

# Validate ssLogIt.ps1 exists
if (-not (Get-Command -Name 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    Write-Error "Required helper script 'ssLogIt.ps1' not found in PATH."
}

# Validate that either MarkdownContent or MarkdownFile is provided
if ([string]::IsNullOrWhiteSpace($MarkdownContent) -and [string]::IsNullOrWhiteSpace($MarkdownFile)) {
    throw "Either -MarkdownContent or -MarkdownFile parameter must be provided"
}

# Read markdown content from file if MarkdownFile is provided
if (-not [string]::IsNullOrWhiteSpace($MarkdownFile)) {
    if (-not (Test-Path -LiteralPath $MarkdownFile -PathType Leaf)) {
        throw "Markdown file not found: $MarkdownFile"
    }
    $null = & ssLogIt.ps1 -Level Info -Message "Reading markdown file: ::FgGreen::$MarkdownFile::FgDefault::"
    $MarkdownContent = Get-Content -LiteralPath $MarkdownFile -Raw -ErrorAction Stop
}
else {
    # If -MarkdownContent is a file path reference (contains \ or /), try to auto-detect and read it
    if ($MarkdownContent -match '[\\/]' -and (Test-Path -LiteralPath $MarkdownContent -PathType Leaf -ErrorAction SilentlyContinue)) {
        $null = & ssLogIt.ps1 -Level Info -Message "Auto-detected file path in -MarkdownContent: ::FgGreen::$MarkdownContent::FgDefault:: Reading file..."
        # Save the resolved path so IDs are written back after creation
        $MarkdownFile = $MarkdownContent
        $MarkdownContent = Get-Content -LiteralPath $MarkdownContent -Raw -ErrorAction Stop
    }
}

# Get Organization, Project from environment variables
[string]$Organization = $env:GMD_AZDO_ORGANIZATION
[string]$Project = $env:GMD_AZDO_PROJECT
# Get PAT token - always decrypt from environment variable (skip for DryRun to avoid decryption errors)
[string]$PatToken = if (-not $DryRun) { Get-AzDoPatToken -Decrypt } else { "dry-run-no-token" }

if ([string]::IsNullOrWhiteSpace($Organization)) {
    throw "Environment variable GMD_AZDO_ORGANIZATION is not set"
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    throw "Environment variable GMD_AZDO_PROJECT is not set"
}

# Helper function to normalize title for matching (strip version suffixes like "(001)")
function Normalize-TitleForMatching {
    param(
        [string]$Title
    )
    
    # Strip "(NNN)" suffix where N is any digit (e.g., "(001)", "(01)", "(7)"), then trim whitespace
    $normalized = $Title -replace '\s*\(\d+\)\s*$', ''
    return $normalized.Trim()
}

# Helper function to analyze work items and determine create vs. update for dry-run
function Analyze-DryRunOperations {
    param(
        [object[]]$Epics,
        [object[]]$Features,
        [string]$Organization,
        [string]$Project,
        [string]$PatToken
    )
    
    $analysis = @{
        EpicsCreate    = 0
        EpicsUpdate    = 0
        FeaturesCreate = 0
        FeaturesUpdate = 0
        StoriesCreate  = 0
        StoriesUpdate  = 0
        BugsCreate     = 0
        BugsUpdate     = 0
        TasksCreate    = 0
        TasksUpdate    = 0
    }
    
    # Check if we're running with a dummy token (dry-run mode without real authentication)
    # If so, skip API calls and assume all items need to be created
    [bool]$isDryRunWithDummyToken = ($PatToken -eq "dry-run-no-token")
    
    # Helper to get existing story titles under a feature
    function Get-ExistingStoriesTitles {
        param([int]$FeatureId)
        $stories = @()
        try {
            $children = Get-AzDoChildWorkItems -Organization $Organization -Project $Project -ParentId $FeatureId -WorkItemType "User Story" -PatToken $PatToken -ErrorAction SilentlyContinue
            
            if ($children -and $children.Count -gt 0) {
                $stories = $children | ForEach-Object { $_.fields.'System.Title' }
            }
        }
        catch {
            $null = & ssLogIt.ps1 -Level Debug -Message "Failed to get stories for feature $FeatureId : $_"
        }
        return $stories
    }
    
    # Analyze epics
    foreach ($epic in $Epics) {
        # Skip API calls if using dummy dry-run token
        if ($isDryRunWithDummyToken) {
            $existingEpicId = $null
        }
        else {
            $existingEpicId = Find-ExistingWorkItemByTitle -Organization $Organization -Project $Project -Title $epic.title -Type $script:WORKITEM_TYPE_EPIC -PatToken $PatToken
        }
        
        if ($null -ne $existingEpicId -and [int]$existingEpicId -gt 0) {
            $analysis.EpicsUpdate++
        }
        else {
            $analysis.EpicsCreate++
            $existingEpicId = $null   # Reset to $null if invalid
        }
        
        # Analyze features within epic
        foreach ($feature in $epic.features) {
            # Only search under epic parent if epic ID is valid (skip if using dummy token)
            if (-not $isDryRunWithDummyToken -and $null -ne $existingEpicId -and [int]$existingEpicId -gt 0) {
                $existingFeatureId = Find-ExistingWorkItemByTitle -Organization $Organization -Project $Project -Title $feature.title -Type $script:WORKITEM_TYPE_FEATURE -ParentId $existingEpicId -PatToken $PatToken
            } else {
                $existingFeatureId = $null
            }
            if ($null -ne $existingFeatureId -and [int]$existingFeatureId -gt 0) {
                $analysis.FeaturesUpdate++
                
                # Get existing stories under this feature
                [string[]]$existingStories = Get-ExistingStoriesTitles -FeatureId $existingFeatureId
                
                # Analyze stories within existing feature
                foreach ($story in $feature.stories) {
                    $normalizedStoryTitle = Normalize-TitleForMatching -Title $story.title
                    $storyExists = $existingStories | Where-Object { (Normalize-TitleForMatching -Title $_) -eq $normalizedStoryTitle }
                    
                    if ($storyExists) {
                        $analysis.StoriesUpdate++
                    }
                    else {
                        $analysis.StoriesCreate++
                    }
                    
                    # Analyze bugs within story (assume new for now)
                    foreach ($bug in $story.bugs) {
                        $analysis.BugsCreate++
                    }
                    # Analyze tasks within story (assume new for now)
                    foreach ($task in $story.tasks) {
                        $analysis.TasksCreate++
                    }
                }
            }
            else {
                $analysis.FeaturesCreate++
                
                # All stories under new feature are new
                foreach ($story in $feature.stories) {
                    $analysis.StoriesCreate++
                    
                    # Analyze bugs within story
                    foreach ($bug in $story.bugs) {
                        $analysis.BugsCreate++
                    }
                    # Analyze tasks within story
                    foreach ($task in $story.tasks) {
                        $analysis.TasksCreate++
                    }
                }
            }
        }
    }
    
    # Analyze top-level features
    foreach ($feature in $Features) {
        # Skip API calls if using dummy dry-run token
        if ($isDryRunWithDummyToken) {
            $existingFeatureId = $null
        }
        else {
            $existingFeatureId = Find-ExistingWorkItemByTitle -Organization $Organization -Project $Project -Title $feature.title -Type $script:WORKITEM_TYPE_FEATURE -PatToken $PatToken
        }
        
        if ($null -ne $existingFeatureId -and [int]$existingFeatureId -gt 0) {
            $analysis.FeaturesUpdate++
            
            # Get existing stories under this feature
            [string[]]$existingStories = Get-ExistingStoriesTitles -FeatureId $existingFeatureId
            
            # Analyze stories within existing feature
            foreach ($story in $feature.stories) {
                $normalizedStoryTitle = Normalize-TitleForMatching -Title $story.title
                $storyExists = $existingStories | Where-Object { (Normalize-TitleForMatching -Title $_) -eq $normalizedStoryTitle }
                
                if ($storyExists) {
                    $analysis.StoriesUpdate++
                }
                else {
                    $analysis.StoriesCreate++
                }
                
                # Analyze bugs within story (assume new for now)
                foreach ($bug in $story.bugs) {
                    $analysis.BugsCreate++
                }
            }
        }
        else {
            $analysis.FeaturesCreate++
            
            # All stories under new feature are new
            foreach ($story in $feature.stories) {
                $analysis.StoriesCreate++
                
                # Analyze bugs within story
                foreach ($bug in $story.bugs) {
                    $analysis.BugsCreate++
                }
            }
        }
    }
    
    return $analysis
}

# Helper function to find existing work item by title, with optional parent filter
function Find-ExistingWorkItemByTitle {
    param(
        [string]$Organization,
        [string]$Project,
        [string]$Title,
        [string]$PatToken,
        [string]$Type,
        [int]$ParentId
    )
    
    $scriptArgs = @{
        Organization  = $Organization
        Project       = $Project
        Title         = $Title
        NormalizeTitle = $true
        PatToken      = $PatToken
    }

    if ($PSBoundParameters.ContainsKey('Type') -and -not [string]::IsNullOrWhiteSpace($Type)) {
        $scriptArgs['Type'] = $Type
    }

    if ($PSBoundParameters.ContainsKey('ParentId')) {
        $scriptArgs['ParentId'] = $ParentId
    }

    # Call FindAzDoItemByTitle without suppressing errors. If the item is not found, it returns $null (normal).
    # If an error occurs, it will be thrown and propagate up to the caller (fail-fast).
    $foundItem = & "$PSScriptRoot\FindAzDoItemByTitle.ps1" @scriptArgs
    
    if ($null -ne $foundItem -and $null -ne $foundItem.id -and [int]$foundItem.id -gt 0) {
        return [int]$foundItem.id
    }

    return $null
}

# Convert a Feature node from new workItems format to the legacy hashtable format
function Convert-HierarchyFeature {
    param([object]$Item)
    [string[]]$tags = if ($Item['tags']) { [string[]]($Item['tags'] -split '\s*,\s*' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) } else { [string[]]::new(0) }
    $feature = @{
        title       = $Item['title']
        workItemId  = $Item['workItemId']
        description = $Item['description']
        effort      = $Item['effort']
        tags        = $tags
        stories     = [array]@()
    }
    $children = $Item['children']
    if ($null -ne $children -and $children.Count -gt 0) {
        foreach ($child in @($children)) {
            if ($child['type'] -in @('Story', 'Bug')) {
                $feature.stories += @(Convert-HierarchyStory -Item $child)
            }
        }
    }
    return $feature
}

# Convert a Story/Bug node from new workItems format to the legacy hashtable format
function Convert-HierarchyStory {
    param([object]$Item)
    [string[]]$tags = if ($Item['tags']) { [string[]]($Item['tags'] -split '\s*,\s*' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) } else { [string[]]::new(0) }
    $story = @{
        title              = $Item['title']
        workItemId         = $Item['workItemId']
        description        = $Item['description']
        storyPoints        = $Item['storyPoints']
        acceptanceCriteria = $Item['acceptanceCriteria']
        acScenarios        = $Item['acScenarios']
        extraInformation   = $Item['extraInformation']
        tags               = $tags
        tasks              = [array]@()
        bugs               = [array]@()
    }
    $children = $Item['children']
    if ($null -ne $children -and $children.Count -gt 0) {
        foreach ($child in @($children)) {
            if ($child['type'] -eq 'Task') {
                [string[]]$taskTags = if ($child['tags']) { [string[]]($child['tags'] -split '\s*,\s*' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) } else { [string[]]::new(0) }
                $story.tasks += @(@{
                    title            = $child['title']
                    workItemId       = $child['workItemId']
                    description      = $child['description']
                    priority         = $child['priority']
                    originalEstimate = $child['originalEstimate']
                    remainingWork    = $child['remainingWork']
                    completedWork    = $child['completedWork']
                    tags             = $taskTags
                })
            }
            elseif ($child['type'] -eq 'Bug') {
                [string[]]$bugTags = if ($child['tags']) { [string[]]($child['tags'] -split '\s*,\s*' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) } else { [string[]]::new(0) }
                $story.bugs += @(@{
                    title       = $child['title']
                    workItemId  = $child['workItemId']
                    description = $child['description']
                    storyPoints = $child['storyPoints']
                    tags        = $bugTags
                })
            }
        }
    }
    return $story
}

# Convert from new workItems format (flat with children) to legacy epics/topLevelFeatures format
function Convert-WorkItemsToLegacyFormat {
    param([array]$WorkItems)
    [array]$epics = @()
    [array]$topLevelFeatures = @()
    foreach ($item in $WorkItems) {
        if ($item['type'] -eq 'Epic') {
            [string[]]$epicTags = if ($item['tags']) { [string[]]($item['tags'] -split '\s*,\s*' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) } else { [string[]]::new(0) }
            $epic = @{
                title       = $item['title']
                workItemId  = $item['workItemId']
                description = $item['description']
                effort      = $item['effort']
                tags        = $epicTags
                features    = [array]@()
            }
            $children = $item['children']
            if ($null -ne $children -and $children.Count -gt 0) {
                foreach ($child in @($children)) {
                    if ($child['type'] -eq 'Feature') {
                        $epic.features += @(Convert-HierarchyFeature -Item $child)
                    }
                }
            }
            $epics += $epic
        }
        elseif ($item['type'] -eq 'Feature') {
            $topLevelFeatures += @(Convert-HierarchyFeature -Item $item)
        }
    }
    return @{ Epics = $epics; TopLevelFeatures = $topLevelFeatures }
}

# Update the markdown file to insert **WorkItemId**: <id> after each work item header that does not already have one
function Update-MarkdownWithWorkItemIds {
    param(
        [string]$MarkdownFilePath,
        [hashtable]$TitleToIdMap
    )
    [string]$content = Get-Content -LiteralPath $MarkdownFilePath -Raw
    [string[]]$lines = $content -split '\r?\n'
    [System.Collections.Generic.List[string]]$newLines = [System.Collections.Generic.List[string]]::new()

    for ($i = 0; $i -lt $lines.Count; $i++) {
        [string]$line = $lines[$i]
        $newLines.Add($line)

        if ($line -match '^(#{1,5})\s+(Epic|Feature|Story|Task|Bug):\s+(.+)$') {
            [string]$titleFromHeader = $Matches[3].Trim()

            # Check if the next line already has **WorkItemId**: N
            [string]$nextLine = if ($i + 1 -lt $lines.Count) { $lines[$i + 1] } else { '' }
            if ($nextLine -match '^\*\*WorkItemId\*\*:') {
                continue
            }

            # Normalize title (strip trailing "(NNN)") to find a match
            [string]$normalizedTitle = $titleFromHeader -replace '\s*\(\d+\)\s*$', ''
            $normalizedTitle = $normalizedTitle.Trim()

            $foundId = $null
            foreach ($key in $TitleToIdMap.Keys) {
                [string]$keyStr = [string]$key
                if ($keyStr -eq $titleFromHeader -or $keyStr -eq $normalizedTitle) {
                    $foundId = $TitleToIdMap[$key]
                    break
                }
            }

            if ($null -ne $foundId) {
                $newLines.Add("**WorkItemId**: $foundId")
            }
        }
    }

    [string]$newContent = $newLines -join "`n"
    Set-Content -LiteralPath $MarkdownFilePath -Value $newContent -NoNewline -Encoding UTF8
}


try {
    # Call adapter to parse markdown to JSON
    $null = & ssLogIt.ps1 -Level Info -Message "Converting markdown to JSON structure..."
    $parsedHierarchy = & "$PSScriptRoot\ConvertMarkdownToHierarchyJson.ps1" -MarkdownContent $MarkdownContent -ErrorAction Stop

    # Convert from new workItems format (nested children) to legacy epics/topLevelFeatures format
    $converted = Convert-WorkItemsToLegacyFormat -WorkItems @($parsedHierarchy.workItems)
    [object[]]$epics = $converted.Epics
    [object[]]$features = $converted.TopLevelFeatures

    $null = & ssLogIt.ps1 -Level Debug -Message "Markdown conversion successful"

    if ($DryRun) {
        # Analyze operations in dry-run mode (which items will be created vs. updated)
        $analysis = Analyze-DryRunOperations -Epics $epics -Features $features -Organization $Organization -Project $Project -PatToken $PatToken
        
        # Calculate totals
        $totalEpicsCreate = $analysis.EpicsCreate
        $totalEpicsUpdate = $analysis.EpicsUpdate
        $totalFeaturesCreate = $analysis.FeaturesCreate
        $totalFeaturesUpdate = $analysis.FeaturesUpdate
        $totalStoriesCreate = $analysis.StoriesCreate
        $totalStoriesUpdate = $analysis.StoriesUpdate
        $totalBugsCreate = $analysis.BugsCreate
        $totalBugsUpdate = $analysis.BugsUpdate
        
        # Log detailed breakdown
        $null = & ssLogIt.ps1 -Level Info -Message "DRY RUN: Detailed breakdown of planned operations:"
        $null = & ssLogIt.ps1 -Level Info -Message "  Epics:    $totalEpicsCreate to create, $totalEpicsUpdate to update"
        $null = & ssLogIt.ps1 -Level Info -Message "  Features: $totalFeaturesCreate to create, $totalFeaturesUpdate to update"
        $null = & ssLogIt.ps1 -Level Info -Message "  Stories:  $totalStoriesCreate to create, $totalStoriesUpdate to update"
        $null = & ssLogIt.ps1 -Level Info -Message "  Bugs:     $totalBugsCreate to create, $totalBugsUpdate to update"
        $null = & ssLogIt.ps1 -Level Info -Message "  Tasks:    $($analysis.TasksCreate) to create, $($analysis.TasksUpdate) to update"
        $null = & ssLogIt.ps1 -Level Debug -Message "DryRun mode - no work items created"
        
        # Build complete dry-run output with detailed breakdown
        [hashtable]$dryRunOutput = @{
            DryRunMode          = $true
            Epics               = @{
                Create = $totalEpicsCreate
                Update = $totalEpicsUpdate
            }
            Features            = @{
                Create = $totalFeaturesCreate
                Update = $totalFeaturesUpdate
            }
            Stories             = @{
                Create = $totalStoriesCreate
                Update = $totalStoriesUpdate
            }
            Bugs                = @{
                Create = $totalBugsCreate
                Update = $totalBugsUpdate
            }
            Tasks               = @{
                Create = $analysis.TasksCreate
                Update = $analysis.TasksUpdate
            }
            Structure           = $parsedHierarchy
        }
        return $dryRunOutput
    }

    # Build dry-run summary for non-dry-run path
    [hashtable]$summary = @{
        PlannedEpics            = 0
        PlannedFeatures         = 0
        PlannedStories          = 0
        PlannedTasks            = 0
        CreatedItems            = @()
    }

    # Count items
    $epicCount = $epics.Count
    $totalFeatures = 0
    if ($epics.Count -gt 0) {
        $totalFeatures = [int]($epics | ForEach-Object { $_.Features.Count } | Measure-Object -Sum | Select-Object -ExpandProperty Sum);
    }
    $totalFeatures = if ($null -eq $totalFeatures) { 0 } else { [int]$totalFeatures }
    $totalFeatures += $features.Count
    
    $totalStories = 0
    $totalTasks = 0
    foreach ($epic in $epics) {
        foreach ($feature in $epic.Features) {
            if ($feature.Stories) {
                $totalStories += @($feature.Stories).Count
                foreach ($story in $feature.Stories) {
                    if ($story.tasks) {
                        $totalTasks += @($story.tasks).Count
                    }
                }
            }
        }
    }
    foreach ($feature in $features) {
        if ($feature.Stories) {
            $totalStories += @($feature.Stories).Count
            foreach ($story in $feature.Stories) {
                if ($story.tasks) {
                    $totalTasks += @($story.tasks).Count
                }
            }
        }
    }

    $summary.PlannedEpics = $epicCount
    $summary.PlannedFeatures = $totalFeatures
    $summary.PlannedStories = $totalStories
    $summary.PlannedTasks = $totalTasks

    # Create work items
    $null = & ssLogIt.ps1 -Level Info -Message "Creating work items from validated markdown..."

    [hashtable]$createdItems = @{}
    
    # Explicit map for task titles to their IDs (to ensure reliable tag application)
    [hashtable]$taskTitleToId = @{}

    # Create Epics and their children
    foreach ($epic in $epics) {
        $epicId = -1  # Use -1 as sentinel value for "not yet set"; 0 means invalid
        $null = & ssLogIt.ps1 -Level Debug -Message "Processing epic: $($epic.title) | initial epicId: $epicId | UpdateExisting: $UpdateExisting"
        
        # Use WorkItemId from markdown if available (takes precedence over title search)
        if ($null -ne $epic.workItemId -and [int]$epic.workItemId -gt 0) {
            $epicId = [int]$epic.workItemId
            $null = & ssLogIt.ps1 -Level Debug -Message "Using WorkItemId $epicId from markdown for Epic: $($epic.title)"
        }
        # Check for existing epic if UpdateExisting is specified (fallback when no workItemId)
        elseif ($UpdateExisting) {
            $null = & ssLogIt.ps1 -Level Debug -Message "UpdateExisting mode: checking for existing epic '$($epic.title)'"
            $existingEpicId = Find-ExistingWorkItemByTitle -Organization $Organization -Project $Project -Title $epic.title -Type $script:WORKITEM_TYPE_EPIC -NormalizeTitle -PatToken $PatToken
            $null = & ssLogIt.ps1 -Level Debug -Message "Find-ExistingWorkItemByTitle returned: $existingEpicId (type: $(if($null -eq $existingEpicId){'$null'}else{$existingEpicId.GetType().Name}))"
            # Validate that existingEpicId is not null and is a positive integer
            if ($null -ne $existingEpicId -and [int]$existingEpicId -gt 0) {
                $epicId = $existingEpicId
                $null = & ssLogIt.ps1 -Level Debug -Message "Found existing Epic with title: $($epic.title) (ID: $epicId), will update instead of create"
            } elseif ($null -ne $existingEpicId) {
                $null = & ssLogIt.ps1 -Level Debug -Message "Found item by title but ID is invalid: $existingEpicId (discarding)"
            }
        }
        
        # If no existing epic found, create new one
        # SAFETY CHECK: ensure epicId is a valid positive integer
        if ($epicId -le 0) {
            $epicId = -1
        }
        
        if ($epicId -eq -1) {
            $epicParams = @{
                Organization = $Organization
                Project      = $Project
                Title        = $epic.title
                PatToken     = $PatToken
            }

            if ($epic.description) {
                $epicParams['Description'] = $epic.description
            }

            if ($epic.effort) {
                $epicParams['Effort'] = $epic.effort
            }

            if ($PSBoundParameters.ContainsKey('EpicId')) {
                $epicParams['ParentEpicId'] = $EpicId
            }

            $null = & ssLogIt.ps1 -Level Debug -Message "Creating Epic: $($epic.title)"
            $createdEpic = & "$PSScriptRoot\UpsertAzDoEpic.ps1" @epicParams -ErrorAction Stop
            $epicId = $createdEpic.id
            $null = & ssLogIt.ps1 -Level Debug -Message "Created Epic with ID: $epicId (object type: $($createdEpic.GetType().Name))"
        }
        else {
            # Existing epic found - update description and effort if provided
            $null = & ssLogIt.ps1 -Level Debug -Message "Updating existing Epic: $($epic.title) (ID: $epicId)"
            
            if ($epic.description) {
                $null = & "$PSScriptRoot\SetAzDoWorkItemDescription.ps1" -Organization $Organization -Project $Project -WorkItemId $epicId -Description $epic.description -PatToken $PatToken -ErrorAction Stop
                $null = & ssLogIt.ps1 -Level Debug -Message "Updated Epic description for ID: $epicId"
            }
            
            if ($epic.effort) {
                $null = & "$PSScriptRoot\SetAzDoEffort.ps1" -Organization $Organization -Project $Project -WorkItemId $epicId -Effort $epic.effort -PatToken $PatToken -ErrorAction Stop
                $null = & ssLogIt.ps1 -Level Debug -Message "Updated Epic effort for ID: $epicId"
            }
            
            # Fetch updated epic for use as reference
            $createdEpic = & "$PSScriptRoot\GetAzDoWorkItem.ps1" -Organization $Organization -Project $Project -WorkItemId $epicId -PatToken $PatToken -ErrorAction Stop
        }
        
        $createdItems[$epicId] = $createdEpic

        foreach ($feature in $epic.features) {
            $featureId = -1  # Sentinel value for "not yet set"
            
            # Use WorkItemId from markdown if available (takes precedence over title search)
            if ($null -ne $feature.workItemId -and [int]$feature.workItemId -gt 0) {
                $featureId = [int]$feature.workItemId
                $null = & ssLogIt.ps1 -Level Debug -Message "Using WorkItemId $featureId from markdown for Feature: $($feature.title)"
            }
            # Check for existing feature if UpdateExisting is specified (fallback when no workItemId)
            elseif ($UpdateExisting) {
                $existingFeatureId = Find-ExistingWorkItemByTitle -Organization $Organization -Project $Project -Title $feature.title -Type $script:WORKITEM_TYPE_FEATURE -ParentId $epicId -NormalizeTitle -PatToken $PatToken
                if ($null -ne $existingFeatureId -and [int]$existingFeatureId -gt 0) {
                    $featureId = $existingFeatureId
                    $null = & ssLogIt.ps1 -Level Debug -Message "Found existing Feature with title: $($feature.title) (ID: $featureId), will update instead of create"
                }
            }
            
            # UPSERT feature - creates if doesn't exist, updates if exists
            $featureParams = @{
                Organization    = $Organization
                Project         = $Project
                Title           = $feature.title
                ParentEpicId    = $epicId
                PatToken        = $PatToken
            }

            # Pass Id when known from markdown so UpsertAzDoFeature updates by ID directly
            if ($featureId -gt 0) {
                $featureParams['Id'] = $featureId
            }

            if ($feature.description) {
                $featureParams['Description'] = $feature.description
            }

            if ($feature.effort) {
                $featureParams['Effort'] = $feature.effort
            }

            $null = & ssLogIt.ps1 -Level Debug -Message "UPSERT Feature: $($feature.title) under Epic"
            $createdFeature = & "$PSScriptRoot\UpsertAzDoFeature.ps1" @featureParams -ErrorAction Stop
            $featureId = $createdFeature.id
            
            $createdItems[$featureId] = $createdFeature

            foreach ($story in $feature.stories) {
                $storyId = -1  # Sentinel value for "not yet set"
                $foundExistingStory = $false
                
                # Use WorkItemId from markdown if available (takes precedence over title search)
                if ($null -ne $story.workItemId -and [int]$story.workItemId -gt 0) {
                    $storyId = [int]$story.workItemId
                    $foundExistingStory = $true
                    $null = & ssLogIt.ps1 -Level Debug -Message "Using WorkItemId $storyId from markdown for Story: $($story.title)"
                }
                # Check for existing story under this Feature if UpdateExisting is specified (fallback when no workItemId)
                elseif ($UpdateExisting) {
                    $existingStoryId = Find-ExistingWorkItemByTitle -Organization $Organization -Project $Project -Title $story.title -Type $script:WORKITEM_TYPE_STORY -ParentId $featureId -NormalizeTitle -PatToken $PatToken
                    if ($null -ne $existingStoryId -and [int]$existingStoryId -gt 0) {
                        $storyId = $existingStoryId
                        $foundExistingStory = $true
                        $null = & ssLogIt.ps1 -Level Debug -Message "Found existing Story with title: $($story.title) (ID: $storyId) under Feature $featureId, will update it"
                    }
                }
                
                # If no existing story found under this feature, create or update
                if ($storyId -eq -1) {
                    $storyParams = @{
                        Organization    = $Organization
                        Project         = $Project
                        Title           = $story.title
                        ParentFeatureId = $featureId
                        PatToken        = $PatToken
                    }

                    if ($story.description) {
                        $storyParams['Description'] = $story.description
                    }
                    if ($story.acceptanceCriteria) {
                        $storyParams['AcceptanceCriteria'] = $story.acceptanceCriteria
                    }
                    if ($story.acScenarios) {
                        $storyParams['AcScenarios'] = $story.acScenarios
                    }
                    if ($story.extraInformation) {
                        $storyParams['ExtraInformation'] = $story.extraInformation
                    }
                    if ($story.storyPoints) {
                        $storyParams['StoryPoints'] = $story.storyPoints
                    }

                    $null = & ssLogIt.ps1 -Level Debug -Message "Creating Story: $($story.title)"
                    $createdStory = & "$PSScriptRoot\UpsertAzDoStory.ps1" @storyParams -ErrorAction Stop
                    $storyId = $createdStory.id
                }
                else {
                    # Update existing story if found (only if there are fields to update)
                    $storyParams = @{
                        Organization = $Organization
                        Project      = $Project
                        Id           = $storyId
                        PatToken     = $PatToken
                    }

                    if ($story.description) {
                        $storyParams['Description'] = $story.description
                    }
                    if ($story.acceptanceCriteria) {
                        $storyParams['AcceptanceCriteria'] = $story.acceptanceCriteria
                    }
                    if ($story.acScenarios) {
                        $storyParams['AcScenarios'] = $story.acScenarios
                    }
                    if ($story.extraInformation) {
                        $storyParams['ExtraInformation'] = $story.extraInformation
                    }
                    if ($story.storyPoints) {
                        $storyParams['StoryPoints'] = $story.storyPoints
                    }

                    # Check if there are any fields to update (beyond the standard org/project/id/token)
                    [int]$fieldUpdateCount = $storyParams.Count - 4  # 4 = Organization, Project, Id, PatToken
                    if ($fieldUpdateCount -gt 0) {
                        $null = & ssLogIt.ps1 -Level Debug -Message "Updating Story: $($story.title) (ID: $storyId) with $fieldUpdateCount field(s)"
                        $createdStory = & "$PSScriptRoot\UpsertAzDoStory.ps1" @storyParams -ErrorAction Stop
                    }
                    else {
                        # No fields to update, just retrieve existing story as-is
                        $null = & ssLogIt.ps1 -Level Debug -Message "No fields to update for Story: $($story.title) (ID: $storyId), using existing story"
                        $createdStory = & "$PSScriptRoot\GetAzDoWorkItem.ps1" -Organization $Organization -Project $Project -WorkItemId $storyId -PatToken $PatToken -ErrorAction Stop
                    }
                }
                
                $createdItems[$storyId] = $createdStory

                # Process Tasks under this Story
                if ($story.tasks -and $story.tasks.Count -gt 0) {
                    foreach ($task in $story.tasks) {
                        $taskParams = @{
                            Organization  = $Organization
                            Project       = $Project
                            Title         = $task.title
                            ParentStoryId = $storyId
                            PatToken      = $PatToken
                        }

                        # Pass Id when task already exists (from markdown workItemId)
                        if ($null -ne $task.workItemId -and [int]$task.workItemId -gt 0) {
                            $taskParams['Id'] = [int]$task.workItemId
                        }

                        if ($task.description) {
                            $taskParams['Description'] = $task.description
                        }
                        if ($task.priority) {
                            $taskParams['Priority'] = $task.priority
                        }
                        if ($task.originalEstimate) {
                            $taskParams['OriginalEstimate'] = $task.originalEstimate
                        }
                        if ($task.remainingWork) {
                            $taskParams['RemainingWork'] = $task.remainingWork
                        }
                        if ($task.completedWork) {
                            $taskParams['CompletedWork'] = $task.completedWork
                        }

                        $null = & ssLogIt.ps1 -Level Debug -Message "Upserting Task: $($task.title) under Story (ID: $storyId)"
                        $createdTask = & "$PSScriptRoot\UpsertAzDoTask.ps1" @taskParams -ErrorAction Stop
                        $createdItems[$createdTask.id] = $createdTask
                        $taskTitleToId[$task.title] = $createdTask.id
                    }
                }
            }
        }
    }

    # Create top-level Features
    foreach ($feature in $features) {
        # UPSERT feature - creates if doesn't exist, updates if exists
        $featureParams = @{
            Organization = $Organization
            Project      = $Project
            Title        = $feature.title
            PatToken     = $PatToken
        }

        # Pass Id when known from markdown so UpsertAzDoFeature updates by ID directly
        if ($null -ne $feature.workItemId -and [int]$feature.workItemId -gt 0) {
            $featureParams['Id'] = [int]$feature.workItemId
        }

        if ($feature.description) {
            $featureParams['Description'] = $feature.description
        }

        if ($feature.effort) {
            $featureParams['Effort'] = $feature.effort
        }

        if ($PSBoundParameters.ContainsKey('EpicId')) {
            $featureParams['ParentEpicId'] = $EpicId
        }

        $null = & ssLogIt.ps1 -Level Debug -Message "UPSERT Feature: $($feature.title)"
        $createdFeature = & "$PSScriptRoot\UpsertAzDoFeature.ps1" @featureParams -ErrorAction Stop
        $featureId = $createdFeature.id
        
        $createdItems[$featureId] = $createdFeature

        foreach ($story in $feature.stories) {
            $storyId = -1  # Sentinel value for "not yet set"
            
            # Use WorkItemId from markdown if available (takes precedence over title search)
            if ($null -ne $story.workItemId -and [int]$story.workItemId -gt 0) {
                $storyId = [int]$story.workItemId
                $null = & ssLogIt.ps1 -Level Debug -Message "Using WorkItemId $storyId from markdown for Story: $($story.title)"
            }
            # Check for existing story under this Feature if UpdateExisting is specified (fallback when no workItemId)
            elseif ($UpdateExisting) {
                $existingStoryId = Find-ExistingWorkItemByTitle -Organization $Organization -Project $Project -Title $story.title -Type $script:WORKITEM_TYPE_STORY -ParentId $featureId -NormalizeTitle -PatToken $PatToken
                if ($null -ne $existingStoryId -and [int]$existingStoryId -gt 0) {
                    $storyId = $existingStoryId
                    $null = & ssLogIt.ps1 -Level Debug -Message "Found existing Story with title: $($story.title) (ID: $storyId) under Feature $featureId, will update it"
                }
            }
            
            # If no existing story found under this feature, create or update
            if ($storyId -eq -1) {
                $storyParams = @{
                    Organization    = $Organization
                    Project         = $Project
                    Title           = $story.title
                    ParentFeatureId = $featureId
                    PatToken        = $PatToken
                }

                if ($story.description) {
                    $storyParams['Description'] = $story.description
                }
                if ($story.acceptanceCriteria) {
                    $storyParams['AcceptanceCriteria'] = $story.acceptanceCriteria
                }
                if ($story.acScenarios) {
                    $storyParams['AcScenarios'] = $story.acScenarios
                }
                if ($story.extraInformation) {
                    $storyParams['ExtraInformation'] = $story.extraInformation
                }
                if ($story.storyPoints) {
                    $storyParams['StoryPoints'] = $story.storyPoints
                }

                $null = & ssLogIt.ps1 -Level Debug -Message "Creating Story: $($story.title)"
                $createdStory = & "$PSScriptRoot\UpsertAzDoStory.ps1" @storyParams -ErrorAction Stop
                $storyId = $createdStory.id
            }
            else {
                # Update existing story if found (only if there are fields to update)
                $storyParams = @{
                    Organization = $Organization
                    Project      = $Project
                    Id           = $storyId
                    PatToken     = $PatToken
                }

                if ($story.description) {
                    $storyParams['Description'] = $story.description
                }
                if ($story.acceptanceCriteria) {
                    $storyParams['AcceptanceCriteria'] = $story.acceptanceCriteria
                }
                if ($story.acScenarios) {
                    $storyParams['AcScenarios'] = $story.acScenarios
                }
                if ($story.extraInformation) {
                    $storyParams['ExtraInformation'] = $story.extraInformation
                }
                if ($story.storyPoints) {
                    $storyParams['StoryPoints'] = $story.storyPoints
                }

                # Check if there are any fields to update (beyond the standard org/project/id/token)
                [int]$fieldUpdateCount = $storyParams.Count - 4  # 4 = Organization, Project, Id, PatToken
                if ($fieldUpdateCount -gt 0) {
                    $null = & ssLogIt.ps1 -Level Debug -Message "Updating Story: $($story.title) (ID: $storyId) with $fieldUpdateCount field(s)"
                    $createdStory = & "$PSScriptRoot\UpsertAzDoStory.ps1" @storyParams -ErrorAction Stop
                }
                else {
                    # No fields to update, just retrieve existing story as-is
                    $null = & ssLogIt.ps1 -Level Debug -Message "No fields to update for Story: $($story.title) (ID: $storyId), using existing story"
                    $createdStory = & "$PSScriptRoot\GetAzDoWorkItem.ps1" -Organization $Organization -Project $Project -WorkItemId $storyId -PatToken $PatToken -ErrorAction Stop
                }
            }
            
            $createdItems[$storyId] = $createdStory

            # Process Tasks under this Story
            if ($story.tasks -and $story.tasks.Count -gt 0) {
                foreach ($task in $story.tasks) {
                    $taskParams = @{
                        Organization  = $Organization
                        Project       = $Project
                        Title         = $task.title
                        ParentStoryId = $storyId
                        PatToken      = $PatToken
                    }

                    # Pass Id when task already exists (from markdown workItemId)
                    if ($null -ne $task.workItemId -and [int]$task.workItemId -gt 0) {
                        $taskParams['Id'] = [int]$task.workItemId
                    }

                    if ($task.description) {
                        $taskParams['Description'] = $task.description
                    }
                    if ($task.priority) {
                        $taskParams['Priority'] = $task.priority
                    }
                    if ($task.originalEstimate) {
                        $taskParams['OriginalEstimate'] = $task.originalEstimate
                    }
                    if ($task.remainingWork) {
                        $taskParams['RemainingWork'] = $task.remainingWork
                    }
                    if ($task.completedWork) {
                        $taskParams['CompletedWork'] = $task.completedWork
                    }

                    $null = & ssLogIt.ps1 -Level Debug -Message "Upserting Task: $($task.title) under Story (ID: $storyId)"
                    $createdTask = & "$PSScriptRoot\UpsertAzDoTask.ps1" @taskParams -ErrorAction Stop
                    $createdItems[$createdTask.id] = $createdTask
                    $taskTitleToId[$task.title] = $createdTask.id
                }
            }
        }
    }

    $summary.CreatedItems = $createdItems

    # Apply tags to all created items
    $null = & ssLogIt.ps1 -Level Debug -Message "Applying tags to created work items..."
    [int]$taggedCount = 0
    [int]$tagErrorCount = 0

    # Build a map of titles to IDs for easier lookup
    [hashtable]$titleToId = @{}
    foreach ($itemId in $createdItems.Keys) {
        $item = $createdItems[$itemId]
        if ($item.PSObject.Properties['fields']) {
            $titleToId[$item.fields.'System.Title'] = @{ id = $itemId; type = $item.fields.'System.WorkItemType' }
        }
    }

    # Apply tags to epics and their children
    foreach ($epic in $epics) {
        if ($epic.tags -and $epic.tags.Count -gt 0) {
            if ($titleToId.ContainsKey($epic.title)) {
                $createdId = $titleToId[$epic.title].id
                try {
                    $null = & "$PSScriptRoot\SetAzDoWorkItemTags.ps1" `
                        -Organization $Organization `
                        -Project $Project `
                        -WorkItemId $createdId `
                        -Tags $epic.tags `
                        -Mode Add `
                        -PatToken $PatToken `
                        -ErrorAction Stop
                    $taggedCount++
                    $null = & ssLogIt.ps1 -Level Debug -Message "Tagged Epic (ID: $createdId) with: $($epic.tags -join ', ')"
                }
                catch {
                    $tagErrorCount++
                    $null = & ssLogIt.ps1 -Level Warn -Message "Failed to tag Epic (ID: $createdId): $_"
                }
            }
        }

        foreach ($feature in $epic.features) {
            if ($feature.tags -and $feature.tags.Count -gt 0) {
                if ($titleToId.ContainsKey($feature.title)) {
                    $createdId = $titleToId[$feature.title].id
                    try {
                        $null = & "$PSScriptRoot\SetAzDoWorkItemTags.ps1" `
                            -Organization $Organization `
                            -Project $Project `
                            -WorkItemId $createdId `
                            -Tags $feature.tags `
                            -Mode Add `
                            -PatToken $PatToken `
                            -ErrorAction Stop
                        $taggedCount++
                        $null = & ssLogIt.ps1 -Level Debug -Message "Tagged Feature (ID: $createdId) with: $($feature.tags -join ', ')"
                    }
                    catch {
                        $tagErrorCount++
                        $null = & ssLogIt.ps1 -Level Warn -Message "Failed to tag Feature (ID: $createdId): $_"
                    }
                }
            }

            foreach ($story in $feature.stories) {
                if ($story.tags -and $story.tags.Count -gt 0) {
                    if ($titleToId.ContainsKey($story.title)) {
                        $createdId = $titleToId[$story.title].id
                        try {
                            $null = & "$PSScriptRoot\SetAzDoWorkItemTags.ps1" `
                                -Organization $Organization `
                                -Project $Project `
                                -WorkItemId $createdId `
                                -Tags $story.tags `
                                -Mode Add `
                                -PatToken $PatToken `
                                -ErrorAction Stop
                            $taggedCount++
                            $null = & ssLogIt.ps1 -Level Debug -Message "Tagged Story (ID: $createdId) with: $($story.tags -join ', ')"
                        }
                        catch {
                            $tagErrorCount++
                            $null = & ssLogIt.ps1 -Level Warn -Message "Failed to tag Story (ID: $createdId): $_"
                        }
                    }
                }

                # Apply tags to tasks within story (in epic features)
                if ($story.tasks -and $story.tasks.Count -gt 0) {
                    foreach ($task in $story.tasks) {
                        if ($task.tags -and $task.tags.Count -gt 0) {
                            # Use explicit task ID mapping for tasks
                            if ($taskTitleToId.ContainsKey($task.title)) {
                                $createdId = $taskTitleToId[$task.title]
                                try {
                                    $null = & "$PSScriptRoot\SetAzDoWorkItemTags.ps1" `
                                        -Organization $Organization `
                                        -Project $Project `
                                        -WorkItemId $createdId `
                                        -Tags $task.tags `
                                        -Mode Add `
                                        -PatToken $PatToken `
                                        -ErrorAction Stop
                                    $taggedCount++
                                    $null = & ssLogIt.ps1 -Level Debug -Message "Tagged Task (ID: $createdId) with: $($task.tags -join ', ')"
                                }
                                catch {
                                    $tagErrorCount++
                                    $null = & ssLogIt.ps1 -Level Warn -Message "Failed to tag Task (ID: $createdId): $_"
                                }
                            }
                            else {
                                $null = & ssLogIt.ps1 -Level Warn -Message "Task title '$($task.title)' not found in created tasks mapping for tagging"
                            }
                        }
                    }
                }
            }
        }
    }

    # Apply tags to top-level features and their stories
    foreach ($feature in $features) {
        if ($feature.tags -and $feature.tags.Count -gt 0) {
            if ($titleToId.ContainsKey($feature.title)) {
                $createdId = $titleToId[$feature.title].id
                try {
                    $null = & "$PSScriptRoot\SetAzDoWorkItemTags.ps1" `
                        -Organization $Organization `
                        -Project $Project `
                        -WorkItemId $createdId `
                        -Tags $feature.tags `
                        -Mode Add `
                        -PatToken $PatToken `
                        -ErrorAction Stop
                    $taggedCount++
                    $null = & ssLogIt.ps1 -Level Debug -Message "Tagged Feature (ID: $createdId) with: $($feature.tags -join ', ')"
                }
                catch {
                    $tagErrorCount++
                    $null = & ssLogIt.ps1 -Level Warn -Message "Failed to tag Feature (ID: $createdId): $_"
                }
            }
        }

        foreach ($story in $feature.stories) {
            if ($story.tags -and $story.tags.Count -gt 0) {
                if ($titleToId.ContainsKey($story.title)) {
                    $createdId = $titleToId[$story.title].id
                    try {
                        $null = & "$PSScriptRoot\SetAzDoWorkItemTags.ps1" `
                            -Organization $Organization `
                            -Project $Project `
                            -WorkItemId $createdId `
                            -Tags $story.tags `
                            -Mode Add `
                            -PatToken $PatToken `
                            -ErrorAction Stop
                        $taggedCount++
                        $null = & ssLogIt.ps1 -Level Debug -Message "Tagged Story (ID: $createdId) with: $($story.tags -join ', ')"
                    }
                    catch {
                        $tagErrorCount++
                        $null = & ssLogIt.ps1 -Level Warn -Message "Failed to tag Story (ID: $createdId): $_"
                    }
                }
            }

            # Apply tags to tasks within story
            if ($story.tasks -and $story.tasks.Count -gt 0) {
                foreach ($task in $story.tasks) {
                    if ($task.tags -and $task.tags.Count -gt 0) {
                        # Use explicit task ID mapping for tasks
                        if ($taskTitleToId.ContainsKey($task.title)) {
                            $createdId = $taskTitleToId[$task.title]
                            try {
                                $null = & "$PSScriptRoot\SetAzDoWorkItemTags.ps1" `
                                    -Organization $Organization `
                                    -Project $Project `
                                    -WorkItemId $createdId `
                                    -Tags $task.tags `
                                    -Mode Add `
                                    -PatToken $PatToken `
                                    -ErrorAction Stop
                                $taggedCount++
                                $null = & ssLogIt.ps1 -Level Debug -Message "Tagged Task (ID: $createdId) with: $($task.tags -join ', ')"
                            }
                            catch {
                                $tagErrorCount++
                                $null = & ssLogIt.ps1 -Level Warn -Message "Failed to tag Task (ID: $createdId): $_"
                            }
                        }
                        else {
                            $null = & ssLogIt.ps1 -Level Warn -Message "Task title '$($task.title)' not found in created tasks mapping for tagging"
                        }
                    }
                }
            }
        }
    }

    if ($taggedCount -gt 0) {
        $null = & ssLogIt.ps1 -Level Info -Message "Tagged $taggedCount work items with specified tags"
    }
    if ($tagErrorCount -gt 0) {
        $null = & ssLogIt.ps1 -Level Warn -Message "$tagErrorCount tag operations failed"
    }

    # Write back work item IDs to the markdown file so subsequent runs update existing items
    if (-not [string]::IsNullOrWhiteSpace($MarkdownFile) -and $createdItems.Count -gt 0) {
        $null = & ssLogIt.ps1 -Level Info -Message "Writing work item IDs back to markdown file: ::FgGreen::$MarkdownFile::FgDefault::"
        [hashtable]$idWritebackMap = @{}
        foreach ($itemId in $createdItems.Keys) {
            $item = $createdItems[$itemId]
            if ($item.PSObject.Properties['fields']) {
                $idWritebackMap[$item.fields.'System.Title'] = $itemId
            }
        }
        Update-MarkdownWithWorkItemIds -MarkdownFilePath $MarkdownFile -TitleToIdMap $idWritebackMap
        $null = & ssLogIt.ps1 -Level Info -Message "Markdown updated with work item IDs"
    }

    return $summary
}
catch {
    $null = & ssLogIt.ps1 -Level Error -Message "Failed to create hierarchy from markdown: $_"
    throw
}
