<#
.SYNOPSIS
Refresh an existing plan markdown file from Azure DevOps work item data.

.DESCRIPTION
Reads an existing plan file, resolves the top-level work item ID, fetches the current
hierarchy from Azure DevOps, and overwrites the plan file with the refreshed content.

Resolution order for the top-level work item ID:
  A. The top-level node in the plan has a {WorkItemId}  — used directly.
  B. No top-level ID but at least one child has a {WorkItemId}  — the parent ID is
     auto-detected via the child's Hierarchy-Reverse relation. A warning is logged.
  C. No {WorkItemId} found anywhere  — the script throws.

After the hierarchy is fetched from AzDo:
- Items in the plan that have a {WorkItemId} present in the fetched hierarchy are
  implicitly refreshed (they appear in the regenerated markdown).
- Items in the plan with a {WorkItemId} NOT found in the fetched hierarchy are logged
  as warnings.
- Items in the plan with no {WorkItemId} are logged as warnings unless
  -MatchExistingByTitle is set, in which case a title-based match is attempted within
  the same parent container.

The regenerated markdown (from the updated AzDo hierarchy) overwrites the original
plan file.

.PARAMETER PlanFilePath
Path to the existing plan markdown file to sync. Mandatory.

.PARAMETER Organization
Azure DevOps organization name. Defaults to GMD_AZDO_ORGANIZATION environment variable.

.PARAMETER Project
Azure DevOps project name. Defaults to GMD_AZDO_PROJECT environment variable.

.PARAMETER Pat
PAT token for authentication. If omitted, auto-retrieved from the encrypted
GMD_AZDO_MACHINE_WORKITEMSRW environment variable.

.PARAMETER MatchExistingByTitle
When set, plan items without a {WorkItemId} are matched against the fetched AzDo
hierarchy by title (case-insensitive) within the same parent container. If a match is
found, the item's WorkItemId is populated and the item is included in the synced output.

.OUTPUTS
[string] The resolved PlanFilePath, confirming the file that was updated.

.EXAMPLE
Sync plan file from AzDo:
    .\SyncMarkdownFromAzDo.ps1 -PlanFilePath ".\docs\plans\plan-2858-featSyncAzDoHierarchyToMarkdown.md"

Sync with title-based matching for unidentified items:
    .\SyncMarkdownFromAzDo.ps1 -PlanFilePath ".\docs\plans\plan.md" -MatchExistingByTitle
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [string]$PlanFilePath,

    [Parameter(Mandatory = $false)]
    [string]$Organization,

    [Parameter(Mandatory = $false)]
    [string]$Project,

    [Parameter(Mandatory = $false)]
    [string]$Pat,

    [Parameter(Mandatory = $false)]
    [switch]$MatchExistingByTitle
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Import modules
. "$PSScriptRoot/AzDoAutomatorConstants.ps1"
. "$PSScriptRoot/AzDoPatTokenHelper.ps1"
. "$PSScriptRoot/AzDoApiWrapper.ps1"
. "$PSScriptRoot/AzDoWorkItemHelper.ps1"

# Validate ssLogIt.ps1 exists
if (-not (Get-Command -Name 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    Write-Error "Required helper script 'ssLogIt.ps1' not found in PATH."
}

# Apply environment variable defaults
if ([string]::IsNullOrWhiteSpace($Organization)) {
    $Organization = [Environment]::GetEnvironmentVariable('GMD_AZDO_ORGANIZATION')
    if ([string]::IsNullOrWhiteSpace($Organization)) {
        Write-Error "Parameter 'Organization' is required. Provide via -Organization or set GMD_AZDO_ORGANIZATION environment variable."
    }
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    $Project = [Environment]::GetEnvironmentVariable('GMD_AZDO_PROJECT')
    if ([string]::IsNullOrWhiteSpace($Project)) {
        Write-Error "Parameter 'Project' is required. Provide via -Project or set GMD_AZDO_PROJECT environment variable."
    }
}

if (-not (Test-Path $PlanFilePath)) {
    throw "Plan file not found: '$PlanFilePath'."
}

# Resolve to absolute path for reliable output
$PlanFilePath = (Resolve-Path $PlanFilePath).Path

# Get PAT token
if ([string]::IsNullOrWhiteSpace($Pat)) {
    $Pat = Get-AzDoPatToken -Decrypt
}

$null = & ssLogIt.ps1 -Level Info -Message "Syncing plan file: ::FgGreen::$PlanFilePath::FgDefault::"

# ============================================================================
# Helper: flatten workItems tree into a list of all items (recursive)
# ============================================================================
function Get-FlatPlanItems {
    param([object[]]$Items, [object]$Parent = $null)

    [System.Collections.Generic.List[PSCustomObject]]$result = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($item in $Items) {
        $entry = [PSCustomObject]@{
            Item       = $item
            Parent     = $Parent
        }
        $result.Add($entry)

        # Items from ConvertMarkdownToHierarchyJson.ps1 are hashtables; leaf nodes omit 'children'.
        # Use ContainsKey to avoid strict-mode PropertyNotFoundException on missing keys.
        $itemChildren = $null
        if ($item -is [System.Collections.Hashtable]) {
            if ($item.ContainsKey('children')) { $itemChildren = $item['children'] }
        } else {
            $childrenProp = $item.PSObject.Properties['children']
            if ($null -ne $childrenProp) { $itemChildren = $childrenProp.Value }
        }

        if ($null -ne $itemChildren -and @($itemChildren).Count -gt 0) {
            $childResults = Get-FlatPlanItems -Items @($itemChildren) -Parent $item
            foreach ($cr in $childResults) {
                $result.Add($cr)
            }
        }
    }
    return $result
}

# ============================================================================
# Helper: build a flat hashtable of {id -> item} from AzDo hierarchy (recursive)
# ============================================================================
function Build-AzDoFlatMap {
    param([PSObject]$HierarchyItem)

    [hashtable]$map = @{}

    if ($null -ne $HierarchyItem -and $null -ne $HierarchyItem.Id) {
        $map[[int]$HierarchyItem.Id] = $HierarchyItem
    }

    # Recurse into Features (for Epics)
    if ($null -ne $HierarchyItem.PSObject.Properties['Features']) {
        foreach ($feature in @($HierarchyItem.Features)) {
            $childMap = Build-AzDoFlatMap -HierarchyItem $feature
            foreach ($k in $childMap.Keys) { $map[$k] = $childMap[$k] }
        }
    }

    # Recurse into Stories (for Epics/Features)
    if ($null -ne $HierarchyItem.PSObject.Properties['Stories']) {
        foreach ($story in @($HierarchyItem.Stories)) {
            $childMap = Build-AzDoFlatMap -HierarchyItem $story
            foreach ($k in $childMap.Keys) { $map[$k] = $childMap[$k] }
        }
    }

    # Recurse into Tasks
    if ($null -ne $HierarchyItem.PSObject.Properties['Tasks']) {
        foreach ($task in @($HierarchyItem.Tasks)) {
            if ($null -ne $task -and $null -ne $task.Id) {
                $map[[int]$task.Id] = $task
            }
        }
    }

    # Recurse into Bugs
    if ($null -ne $HierarchyItem.PSObject.Properties['Bugs']) {
        foreach ($bug in @($HierarchyItem.Bugs)) {
            if ($null -ne $bug -and $null -ne $bug.Id) {
                $map[[int]$bug.Id] = $bug
            }
        }
    }

    return $map
}

# ============================================================================
# Helper: get children of an AzDo hierarchy item by type
# ============================================================================
function Get-AzDoChildren {
    param([PSObject]$Item)

    [object[]]$children = @()
    if ($null -ne $Item.PSObject.Properties['Features']) { $children += @($Item.Features) }
    if ($null -ne $Item.PSObject.Properties['Stories'])  { $children += @($Item.Stories) }
    if ($null -ne $Item.PSObject.Properties['Tasks'])    { $children += @($Item.Tasks) }
    if ($null -ne $Item.PSObject.Properties['Bugs'])     { $children += @($Item.Bugs) }
    return $children
}

# ============================================================================
# Helper: build a pruned copy of an AzDo hierarchy PSObject,
# keeping only items whose IDs appear in $PlanIds.
# ============================================================================
function Build-PrunedHierarchy {
    param(
        [PSObject]$Item,
        [System.Collections.Generic.HashSet[int]]$PlanIds
    )

    $pruned = [PSCustomObject]@{}
    foreach ($prop in $Item.PSObject.Properties) {
        if ($prop.Name -notin @('Features', 'Stories', 'Tasks', 'Bugs')) {
            $pruned | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
        }
    }

    if ($Item.PSObject.Properties.Name -contains 'Features') {
        $prunedFeatures = [System.Collections.Generic.List[PSObject]]::new()
        foreach ($feature in @($Item.Features)) {
            if ($null -ne $feature.Id -and $PlanIds.Contains([int]$feature.Id)) {
                $prunedFeatures.Add((Build-PrunedHierarchy -Item $feature -PlanIds $PlanIds))
            }
        }
        $pruned | Add-Member -NotePropertyName 'Features' -NotePropertyValue $prunedFeatures.ToArray()
    }

    if ($Item.PSObject.Properties.Name -contains 'Stories') {
        $prunedStories = [System.Collections.Generic.List[PSObject]]::new()
        foreach ($story in @($Item.Stories)) {
            if ($null -ne $story.Id -and $PlanIds.Contains([int]$story.Id)) {
                $prunedStories.Add((Build-PrunedHierarchy -Item $story -PlanIds $PlanIds))
            }
        }
        $pruned | Add-Member -NotePropertyName 'Stories' -NotePropertyValue $prunedStories.ToArray()
    }

    if ($Item.PSObject.Properties.Name -contains 'Tasks') {
        $prunedTasks = [System.Collections.Generic.List[PSObject]]::new()
        foreach ($task in @($Item.Tasks)) {
            if ($null -ne $task.Id -and $PlanIds.Contains([int]$task.Id)) {
                $prunedTasks.Add($task)
            }
        }
        $pruned | Add-Member -NotePropertyName 'Tasks' -NotePropertyValue $prunedTasks.ToArray()
    }

    if ($Item.PSObject.Properties.Name -contains 'Bugs') {
        $prunedBugs = [System.Collections.Generic.List[PSObject]]::new()
        foreach ($bug in @($Item.Bugs)) {
            if ($null -ne $bug.Id -and $PlanIds.Contains([int]$bug.Id)) {
                $prunedBugs.Add($bug)
            }
        }
        $pruned | Add-Member -NotePropertyName 'Bugs' -NotePropertyValue $prunedBugs.ToArray()
    }

    return $pruned
}

# ============================================================================
# Step 1: Parse the existing plan
# ============================================================================
$null = & ssLogIt.ps1 -Level Debug -Message "Parsing existing plan file"
$planContent = Get-Content -Path $PlanFilePath -Raw
$parsed = & "$PSScriptRoot/ConvertMarkdownToHierarchyJson.ps1" `
    -MarkdownContent $planContent `
    -Organization $Organization `
    -Project $Project

$planWorkItems = @($parsed.workItems)

if ($planWorkItems.Count -eq 0) {
    throw "Cannot sync: plan file contains no parseable work items."
}

# ============================================================================
# Step 2: Resolve the top-level work item ID
# ============================================================================
[int]$topLevelId = 0
$topLevelItem = $planWorkItems[0]

# Flatten all plan items for processing
$allPlanEntries = @(Get-FlatPlanItems -Items $planWorkItems)

if ($null -ne $topLevelItem.workItemId -and $topLevelItem.workItemId -gt 0) {
    # Case A: top-level has a WorkItemId
    $topLevelId = [int]$topLevelItem.workItemId
    $null = & ssLogIt.ps1 -Level Debug -Message "Top-level work item ID: $topLevelId"
} else {
    # Case B/C: find first item with a WorkItemId
    $firstWithId = $allPlanEntries | Where-Object { $null -ne $_.Item.workItemId -and $_.Item.workItemId -gt 0 } | Select-Object -First 1

    if ($null -eq $firstWithId) {
        # Case C: no WorkItemId found anywhere
        throw "Cannot sync: no WorkItemId found in plan file. At least one work item must have a {WorkItemId} to anchor the sync."
    }

    # Case B: detect parent from child's parent link
    [int]$childId = [int]$firstWithId.Item.workItemId
    $null = & ssLogIt.ps1 -Level Debug -Message "Top-level node has no WorkItemId. Detecting parent from child ID: $childId"

    $childWorkItem = & "$PSScriptRoot/GetAzDoWorkItem.ps1" `
        -Organization $Organization `
        -Project $Project `
        -WorkItemId $childId `
        -PatToken $Pat

    $parentRelation = $null
    if ($null -ne $childWorkItem.relations) {
        $parentRelation = $childWorkItem.relations |
            Where-Object { $_.rel -eq 'System.LinkTypes.Hierarchy-Reverse' } |
            Select-Object -First 1
    }

    if ($null -eq $parentRelation) {
        throw "Cannot sync: work item $childId has no parent link. Cannot auto-detect the top-level work item ID."
    }

    $topLevelId = [int]($parentRelation.url -split '/' | Select-Object -Last 1)
    $topLevelTitle = $topLevelItem.title
    $null = & ssLogIt.ps1 -Level Warn -Message "Top-level node '$topLevelTitle' has no WorkItemId — parent ID ::FgYellow::$topLevelId::FgDefault:: detected from child $childId."
}

# ============================================================================
# Step 3: Fetch full hierarchy from AzDo
# ============================================================================
$null = & ssLogIt.ps1 -Level Debug -Message "Fetching top-level work item (ID: $topLevelId) to determine type"
$topWorkItem = & "$PSScriptRoot/GetAzDoWorkItem.ps1" `
    -Organization $Organization `
    -Project $Project `
    -WorkItemId $topLevelId `
    -PatToken $Pat

if ($null -eq $topWorkItem) {
    throw "Top-level work item ID $topLevelId was not found in Azure DevOps."
}

[string]$topType = $topWorkItem.fields.'System.WorkItemType'
$null = & ssLogIt.ps1 -Level Debug -Message "Top-level work item type: $topType"

[object]$hierarchy = $null
switch ($topType) {
    $script:WORKITEM_TYPE_EPIC {
        # Optimisation: fetch only the Feature hierarchies listed in the plan rather
        # than the full Epic, which would pull every feature and story under the epic.
        $topLevelChildren = @()
        $topLevelPlanItem = $planWorkItems[0]
        if ($topLevelPlanItem -is [System.Collections.Hashtable]) {
            if ($topLevelPlanItem.ContainsKey('children')) { $topLevelChildren = @($topLevelPlanItem['children']) }
        } else {
            $cp = $topLevelPlanItem.PSObject.Properties['children']
            if ($null -ne $cp) { $topLevelChildren = @($cp.Value) }
        }
        $planFeatureIds = @(
            $topLevelChildren |
            Where-Object { ($_ -is [System.Collections.Hashtable] -and $_.ContainsKey('workItemId') -and $null -ne $_['workItemId'] -and $_['workItemId'] -gt 0) } |
            ForEach-Object { [int]$_['workItemId'] }
        )

        if ($planFeatureIds.Count -gt 0) {
            $null = & ssLogIt.ps1 -Level Debug -Message "Building scoped Epic hierarchy — fetching $($planFeatureIds.Count) Feature(s) from plan: $($planFeatureIds -join ', ')"
            $featureHierarchies = [System.Collections.Generic.List[PSObject]]::new()
            foreach ($fid in $planFeatureIds) {
                $null = & ssLogIt.ps1 -Level Debug -Message "Fetching Feature hierarchy for ID: $fid"
                $fh = & "$PSScriptRoot/GetAzDoHierarchyForFeature.ps1" `
                    -Organization $Organization -Project $Project -FeatureId $fid -PatToken $Pat
                if ($null -ne $fh) { $featureHierarchies.Add($fh) }
            }
            $hierarchy = [PSCustomObject]@{
                Id          = $topWorkItem.id
                State       = $topWorkItem.fields.'System.State'
                Title       = $topWorkItem.fields.'System.Title'
                Description = if ($topWorkItem.fields.PSObject.Properties.Name -contains 'System.Description') { $topWorkItem.fields.'System.Description' } else { $null }
                Effort      = if ($topWorkItem.fields.PSObject.Properties.Name -contains 'Microsoft.VSTS.Scheduling.Effort') { $topWorkItem.fields.'Microsoft.VSTS.Scheduling.Effort' } else { $null }
                Tags        = if ($topWorkItem.fields.PSObject.Properties.Name -contains 'System.Tags') { $topWorkItem.fields.'System.Tags' } else { $null }
                ChangedDate = if ($topWorkItem.fields.PSObject.Properties.Name -contains 'System.ChangedDate') { $topWorkItem.fields.'System.ChangedDate' } else { $null }
                Features    = $featureHierarchies.ToArray()
            }
        } else {
            # No Feature IDs in plan — fall back to fetching the full Epic hierarchy
            $null = & ssLogIt.ps1 -Level Debug -Message "No Feature IDs found in plan; fetching full Epic hierarchy for ID: $topLevelId"
            $hierarchy = & "$PSScriptRoot/GetAzDoHierarchyForEpic.ps1" `
                -Organization $Organization -Project $Project -EpicId $topLevelId -PatToken $Pat
        }
    }
    $script:WORKITEM_TYPE_FEATURE {
        $null = & ssLogIt.ps1 -Level Debug -Message "Fetching Feature hierarchy for ID: $topLevelId"
        $hierarchy = & "$PSScriptRoot/GetAzDoHierarchyForFeature.ps1" `
            -Organization $Organization -Project $Project -FeatureId $topLevelId -PatToken $Pat
    }
    $script:WORKITEM_TYPE_STORY {
        $null = & ssLogIt.ps1 -Level Debug -Message "Fetching Story hierarchy for ID: $topLevelId"
        $hierarchy = & "$PSScriptRoot/GetAzDoHierarchyForStory.ps1" `
            -Organization $Organization -Project $Project -StoryId $topLevelId -PatToken $Pat
    }
    default {
        throw "Unsupported top-level work item type '$topType' for ID $topLevelId. Supported types: Epic, Feature, User Story."
    }
}

if ($null -eq $hierarchy) {
    throw "Failed to retrieve hierarchy for work item ID $topLevelId (type: $topType)."
}

# Build a flat ID map of all items in the fetched AzDo hierarchy
$azDoFlatMap = Build-AzDoFlatMap -HierarchyItem $hierarchy

# ============================================================================
# Step 4: Validate plan items against fetched hierarchy; log warnings
# ============================================================================
# Collect IDs to include in the pruned output hierarchy
$planIdSet = [System.Collections.Generic.HashSet[int]]::new()

foreach ($entry in $allPlanEntries) {
    $planItem = $entry.Item

    if ($null -ne $planItem.workItemId -and $planItem.workItemId -gt 0) {
        [int]$planItemId = [int]$planItem.workItemId
        [void]$planIdSet.Add($planItemId)
        if (-not $azDoFlatMap.ContainsKey($planItemId)) {
            $null = & ssLogIt.ps1 -Level Warn -Message "Work item $planItemId ('$($planItem.title)') was not found in the fetched hierarchy and will be skipped."
        }
    } else {
        if ($MatchExistingByTitle) {
            # Attempt title-based match within the same parent container
            [string]$planTitle = $planItem.title
            [string]$parentTitle = if ($null -ne $entry.Parent) { $entry.Parent.title } else { '<root>' }

            # Find AzDo items whose parent's title matches the parent container
            $matchedAzDoItem = $null

            # Search in the appropriate container in the AzDo hierarchy
            if ($null -ne $entry.Parent -and $null -ne $entry.Parent.workItemId -and $entry.Parent.workItemId -gt 0) {
                [int]$parentId = [int]$entry.Parent.workItemId
                if ($azDoFlatMap.ContainsKey($parentId)) {
                    $parentAzDoItem = $azDoFlatMap[$parentId]
                    $azDoSiblings = Get-AzDoChildren -Item $parentAzDoItem
                    $matchedAzDoItem = $azDoSiblings | Where-Object {
                        $null -ne $_.Title -and $_.Title.ToLower() -eq $planTitle.ToLower()
                    } | Select-Object -First 1
                }
            } else {
                # Parent is root — search in the top-level hierarchy children
                $azDoSiblings = Get-AzDoChildren -Item $hierarchy
                $matchedAzDoItem = $azDoSiblings | Where-Object {
                    $null -ne $_.Title -and $_.Title.ToLower() -eq $planTitle.ToLower()
                } | Select-Object -First 1
            }

            if ($null -ne $matchedAzDoItem) {
                $null = & ssLogIt.ps1 -Level Info -Message "Title match found for '$planTitle': work item ID ::FgGreen::$($matchedAzDoItem.Id)::FgDefault:: within parent '$parentTitle'."
                # Include the matched item in the pruned output
                [void]$planIdSet.Add([int]$matchedAzDoItem.Id)
            } else {
                $null = & ssLogIt.ps1 -Level Warn -Message "No title match found for '$planTitle' within parent '$parentTitle'."
            }
        } else {
            $null = & ssLogIt.ps1 -Level Warn -Message "Item '$($planItem.title)' has no WorkItemId and will be skipped. Use -MatchExistingByTitle to attempt a title-based match."
        }
    }
}

# ============================================================================
# Step 5: Regenerate markdown from the pruned AzDo hierarchy and overwrite
# ============================================================================
$null = & ssLogIt.ps1 -Level Debug -Message "Regenerating markdown from updated AzDo hierarchy (pruned to plan scope)"

# Prune the AzDo hierarchy to only the items present in the plan, so that
# sibling items in the same epic/feature are not included in the output.
$prunedHierarchy = Build-PrunedHierarchy -Item $hierarchy -PlanIds $planIdSet

[string]$repoRoot = (Resolve-Path "$PSScriptRoot/..").Path
[string]$updatedMarkdown = & "$PSScriptRoot/ConvertHierarchyToMarkdown.ps1" `
    -Hierarchy $prunedHierarchy `
    -Organization $Organization `
    -Project $Project `
    -RepositoryRoot $repoRoot

$null = & ssLogIt.ps1 -Level Debug -Message "Writing updated markdown to: $PlanFilePath"
$updatedMarkdown | Set-Content -Path $PlanFilePath -Encoding UTF8

$null = & ssLogIt.ps1 -Level Info -Message "Successfully synced plan file: ::FgGreen::$PlanFilePath::FgDefault::"

# Emit the file path to the pipeline
$PlanFilePath

