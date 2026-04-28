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
    **Story Points**: 5
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
# Get PAT token - always decrypt from environment variable (required even for DryRun to compare field values)
[string]$PatToken = Get-AzDoPatToken -Decrypt

if ([string]::IsNullOrWhiteSpace($Organization)) {
    throw "Environment variable GMD_AZDO_ORGANIZATION is not set"
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    throw "Environment variable GMD_AZDO_PROJECT is not set"
}

# HTML-encodes < characters in rich-text field values that are NOT part of a standard HTML
# element. AzDo description fields are stored as HTML; unknown tags like <FooBar> are stripped
# by the sanitizer, so they must be sent as &lt;FooBar> to be displayed as literal text.
# Recognised HTML elements (br, p, strong, em, …) are left untouched so they continue to
# render correctly in the AzDo UI.
function Encode-NonHtmlAngleBrackets {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }
    # Standard HTML element names that must NOT be encoded.
    [string]$htmlTagNames = 'a|abbr|address|article|aside|audio|b|blockquote|br|button|caption|cite|code|col|colgroup|dd|del|details|dfn|div|dl|dt|em|fieldset|figcaption|figure|footer|form|h[1-6]|header|hr|i|img|input|ins|kbd|label|legend|li|main|mark|menu|nav|ol|optgroup|option|p|pre|q|s|samp|section|select|small|source|span|strong|sub|summary|sup|table|tbody|td|textarea|tfoot|th|thead|time|title|tr|u|ul|var|video'
    # Encode any < that is not the start of a recognised HTML opening or closing tag.
    return $Text -replace "(?i)<(?!/?($htmlTagNames)(\s|>|/))", '&lt;'
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

# Compares markdown field values against the current state of a work item retrieved from AzDo.
# Returns 'Create' (no existing item), 'NoChange' (all fields identical), or 'Update' (at least one field differs).
# MarkdownFields is a hashtable mapping AzDo field reference names to the markdown values (may be $null/missing).
# ExistingItem is the AzDo work item object as returned by Get-AzDoWorkItemById (has .fields property).
function Get-WorkItemChangeState {
    param(
        [hashtable]$MarkdownFields,
        [object]$ExistingItem
    )

    function Normalize-HtmlValue {
        param([string]$Value)
        # Strip HTML tags and decode basic entities for comparison.
        # AzDo returns rich-text fields as HTML; strip all tags for plain-text comparison.
        # Angle-bracket identifiers (e.g. <StmtsDir>) are stored by AzDo as &lt;StmtsDir&gt;,
        # so they survive the strip and are restored by the &lt; decode below.
        if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
        $stripped = $Value -replace '<[^>]+>', ''
        $stripped = $stripped -replace '&nbsp;', ' '
        $stripped = $stripped -replace '&lt;', '<'
        $stripped = $stripped -replace '&gt;', '>'
        $stripped = $stripped -replace '&amp;', '&'
        $stripped = $stripped -replace '&quot;', '"'
        $stripped = $stripped.Trim()
        # Normalize numeric strings: parse as double then re-stringify to avoid "2" vs "2.0" mismatches
        $parsed = $null
        if ([double]::TryParse($stripped, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
            return $parsed.ToString([System.Globalization.CultureInfo]::InvariantCulture)
        }
        return $stripped
    }

    if ($null -eq $ExistingItem) {
        return 'Create'
    }

    # AzDo omits null/unset fields from its JSON response, so $ExistingItem.fields is a
    # PSCustomObject where accessing a missing property throws. Convert to a hashtable so
    # that missing keys naturally return $null instead.
    $existingFields = @{}
    $ExistingItem.fields.PSObject.Properties | ForEach-Object { $existingFields[$_.Name] = $_.Value }

    foreach ($fieldName in $MarkdownFields.Keys) {
        $markdownValue = $MarkdownFields[$fieldName]
        $azDoValue = $existingFields[$fieldName]

        # AzDo returns System.AssignedTo as a complex object with uniqueName/displayName.
        # Extract uniqueName for a reliable string comparison.
        if ($fieldName -eq 'System.AssignedTo' -and $azDoValue -is [System.Management.Automation.PSCustomObject]) {
            $azDoValue = if ($azDoValue.PSObject.Properties.Name -contains 'uniqueName') { $azDoValue.uniqueName } else { '' }
        }

        # Treat $null and empty string as equivalent
        [string]$normalizedMarkdown = if ($null -eq $markdownValue) { '' } else { [string]$markdownValue }
        [string]$normalizedAzDo = if ($null -eq $azDoValue) { '' } else { [string]$azDoValue }

        # AzDo returns HTML for rich-text fields; strip tags before comparing
        $strippedAzDo = Normalize-HtmlValue -Value $normalizedAzDo
        $strippedMarkdown = Normalize-HtmlValue -Value $normalizedMarkdown

        if ($strippedMarkdown -ne $strippedAzDo) {
            return 'Update'
        }
    }

    return 'NoChange'
}

# Resolves the AzDo work item ID for a given item, using workItemId from markdown when available,
# or falling back to a title search. Returns $null if the item does not exist in AzDo.
function Resolve-ExistingWorkItemId {
    param(
        [string]$Organization,
        [string]$Project,
        [string]$PatToken,
        [object]$Item,
        [string]$Type,
        [int]$ParentId
    )

    if ($null -ne $Item.workItemId -and [int]$Item.workItemId -gt 0) {
        return [int]$Item.workItemId
    }

    $searchArgs = @{
        Organization = $Organization
        Project      = $Project
        Title        = $Item.title
        Type         = $Type
        NormalizeTitle = $true
        PatToken     = $PatToken
    }
    if ($PSBoundParameters.ContainsKey('ParentId') -and $ParentId -gt 0) {
        $searchArgs['ParentId'] = $ParentId
    }

    $found = & "$PSScriptRoot\FindAzDoItemByTitle.ps1" @searchArgs -ErrorAction SilentlyContinue
    if ($null -ne $found -and [int]$found.id -gt 0) {
        return [int]$found.id
    }

    return $null
}

# Maps config-field reference names to corresponding Upsert script parameter names.
# Fields not listed here are not yet supported by existing Upsert scripts (Story 004 adds generic -Fields).
$script:_cfgToUpsertParam = @{
    'Microsoft.VSTS.Scheduling.OriginalEstimate' = 'OriginalEstimate'
    'Microsoft.VSTS.Scheduling.StoryPoints'      = 'StoryPoints'
    'Microsoft.VSTS.Scheduling.Effort'           = 'Effort'
    'Custom.FixedIn'                             = 'FixedIn'
    'Custom.DeployedToDev'                       = 'DeployedToDev'
    'Custom.DeployedToStaging'                   = 'DeployedToStaging'
    'Custom.DeployedToProduction'                = 'DeployedToProduction'
}

<#
.SYNOPSIS
Merges writable configFields from a parsed work item into the Upsert params hashtable.
Only fields with known Upsert param names are transferred; others are logged as unsupported.
An existing param value (set by explicit named property handling) is never overridden.
#>
function Merge-ConfigFieldsToParams {
    param([hashtable]$Params, [object]$Item)

    $cfgFields = $null
    if ($Item -is [hashtable] -and $Item.ContainsKey('configFields')) {
        $cfgFields = $Item['configFields']
    } elseif ($Item.PSObject.Properties.Name -contains 'configFields') {
        $cfgFields = $Item.configFields
    }
    if ($null -eq $cfgFields -or $cfgFields.Count -eq 0) { return }

    foreach ($refName in $cfgFields.Keys) {
        $paramName = $script:_cfgToUpsertParam[$refName]
        if ([string]::IsNullOrWhiteSpace($paramName)) {
            # No named param mapping: fall back to -Fields hashtable keyed by referenceName
            if (-not $Params.ContainsKey('Fields')) {
                $Params['Fields'] = @{}
            }
            if (-not $Params['Fields'].ContainsKey($refName)) {
                $Params['Fields'][$refName] = $cfgFields[$refName]
            }
            continue
        }
        if (-not $Params.ContainsKey($paramName)) {
            $Params[$paramName] = $cfgFields[$refName]
        }
    }
}

# Builds the field comparison hashtable for an Epic from its markdown representation.
function Get-EpicMarkdownFields {
    param([object]$Epic)
    $fields = @{}
    if ($Epic.title) { $fields[$script:FIELD_SYSTEM_TITLE] = $Epic.title }
    if ($Epic.description) { $fields[$script:FIELD_DESCRIPTION] = $Epic.description }
    if ($Epic.effort) { $fields[$script:FIELD_EFFORT] = [string]$Epic.effort }
    return $fields
}

# Builds the field comparison hashtable for a Feature from its markdown representation.
function Get-FeatureMarkdownFields {
    param([object]$Feature)
    $fields = @{}
    if ($Feature.title) { $fields[$script:FIELD_SYSTEM_TITLE] = $Feature.title }
    if ($Feature.state) { $fields[$script:FIELD_SYSTEM_STATE] = $Feature.state }
    if (-not [string]::IsNullOrWhiteSpace($Feature.assignedTo)) { $fields[$script:FIELD_SYSTEM_ASSIGNED_TO] = $Feature.assignedTo }
    if ($Feature.description) { $fields[$script:FIELD_DESCRIPTION] = $Feature.description }
    if ($Feature.effort) { $fields[$script:FIELD_EFFORT] = [string]$Feature.effort }
    if ($Feature.priority) { $fields[$script:FIELD_PRIORITY] = [string]$Feature.priority }
    if ($Feature.originalEstimate) { $fields[$script:FIELD_ORIGINAL_ESTIMATE] = [string]$Feature.originalEstimate }
    if ($Feature.fixedIn) { $fields[$script:FIELD_FIXED_IN] = $Feature.fixedIn }
    if ($null -ne $Feature.deployedToDev) { $fields[$script:FIELD_DEPLOYED_TO_DEV] = [string]$Feature.deployedToDev }
    if ($null -ne $Feature.deployedToStaging) { $fields[$script:FIELD_DEPLOYED_TO_STAGING] = [string]$Feature.deployedToStaging }
    if ($null -ne $Feature.deployedToProduction) { $fields[$script:FIELD_DEPLOYED_TO_PRODUCTION] = [string]$Feature.deployedToProduction }
    # Include config-driven fields (e.g. Custom.FeatureAcceptanceTests)
    $featureCfgFields = if ($Feature -is [hashtable]) { $Feature['configFields'] } else { $Feature.configFields }
    if ($null -ne $featureCfgFields -and $featureCfgFields.Count -gt 0) {
        foreach ($refName in $featureCfgFields.Keys) {
            if (-not $fields.ContainsKey($refName)) { $fields[$refName] = $featureCfgFields[$refName] }
        }
    }
    return $fields
}

# Builds the field comparison hashtable for a Story from its markdown representation.
function Get-StoryMarkdownFields {
    param([object]$Story)
    $fields = @{}
    if ($Story.title) { $fields[$script:FIELD_SYSTEM_TITLE] = $Story.title }
    if ($Story.state) { $fields[$script:FIELD_SYSTEM_STATE] = $Story.state }
    if (-not [string]::IsNullOrWhiteSpace($Story.assignedTo)) { $fields[$script:FIELD_SYSTEM_ASSIGNED_TO] = $Story.assignedTo }
    if ($Story.description) { $fields[$script:FIELD_DESCRIPTION] = $Story.description }
    if ($Story.acceptanceCriteria) { $fields[$script:FIELD_ACCEPTANCE_CRITERIA] = $Story.acceptanceCriteria }
    if ($Story.acScenarios) { $fields[$script:FIELD_AC_SCENARIOS] = $Story.acScenarios }
    if ($Story.extraInformation) { $fields[$script:FIELD_EXTRA_INFORMATION] = $Story.extraInformation }
    if ($Story.storyPoints) { $fields[$script:FIELD_STORY_POINTS] = [string]$Story.storyPoints }
    if ($Story.priority) { $fields[$script:FIELD_PRIORITY] = [string]$Story.priority }
    if ($Story.originalEstimate) { $fields[$script:FIELD_ORIGINAL_ESTIMATE] = [string]$Story.originalEstimate }
    if ($Story.fixedIn) { $fields[$script:FIELD_FIXED_IN] = $Story.fixedIn }
    if ($null -ne $Story.deployedToDev) { $fields[$script:FIELD_DEPLOYED_TO_DEV] = [string]$Story.deployedToDev }
    if ($null -ne $Story.deployedToStaging) { $fields[$script:FIELD_DEPLOYED_TO_STAGING] = [string]$Story.deployedToStaging }
    if ($null -ne $Story.deployedToProduction) { $fields[$script:FIELD_DEPLOYED_TO_PRODUCTION] = [string]$Story.deployedToProduction }
    # Include config-driven fields (e.g. Custom.StoryAcceptanceTests)
    $storyCfgFields = if ($Story -is [hashtable]) { $Story['configFields'] } else { $Story.configFields }
    if ($null -ne $storyCfgFields -and $storyCfgFields.Count -gt 0) {
        foreach ($refName in $storyCfgFields.Keys) {
            if (-not $fields.ContainsKey($refName)) { $fields[$refName] = $storyCfgFields[$refName] }
        }
    }
    return $fields
}

# Builds the field comparison hashtable for a Task from its markdown representation.
function Get-TaskMarkdownFields {
    param([object]$Task)
    $fields = @{}
    if ($Task.title) { $fields[$script:FIELD_SYSTEM_TITLE] = $Task.title }
    if ($Task.description) { $fields[$script:FIELD_DESCRIPTION] = $Task.description }
    if ($Task.priority) { $fields[$script:FIELD_PRIORITY] = [string]$Task.priority }
    if ($Task.originalEstimate) { $fields[$script:FIELD_ORIGINAL_ESTIMATE] = [string]$Task.originalEstimate }
    if ($Task.remainingWork) { $fields[$script:FIELD_REMAINING_WORK] = [string]$Task.remainingWork }
    if ($Task.completedWork) { $fields[$script:FIELD_COMPLETED_WORK] = [string]$Task.completedWork }
    return $fields
}

# Compares markdown tags against the System.Tags field of an existing AzDo work item.
# Returns $true if tags need to be applied (differ from current state), $false when identical.
function Test-TagsChanged {
    param(
        [string[]]$MarkdownTags,
        [object]$ExistingItem
    )
    [string]$azDoTags = if ($null -ne $ExistingItem -and $ExistingItem.PSObject.Properties['fields'] -and $ExistingItem.fields.PSObject.Properties['System.Tags']) { $ExistingItem.fields.'System.Tags' } else { '' }
    [bool]$mdEmpty = ($null -eq $MarkdownTags -or $MarkdownTags.Count -eq 0)
    [bool]$azEmpty = [string]::IsNullOrWhiteSpace($azDoTags)
    if ($mdEmpty -and $azEmpty) { return $false }
    if ($mdEmpty -ne $azEmpty) { return $true }
    [string]$normalizedMarkdown = ($MarkdownTags | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ -ne '' } | Sort-Object) -join '; '
    [string]$normalizedAzDo = ($azDoTags -split '\s*;\s*' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ -ne '' } | Sort-Object) -join '; '
    return $normalizedMarkdown -ne $normalizedAzDo
}

# Helper function to analyze work items and determine create vs. update vs. no-change for dry-run.
function Analyze-DryRunOperations {
    param(
        [object[]]$Epics,
        [object[]]$Features,
        [string]$Organization,
        [string]$Project,
        [string]$PatToken
    )

    $analysis = @{
        EpicsCreate      = 0
        EpicsUpdate      = 0
        EpicsNoChange    = 0
        FeaturesCreate   = 0
        FeaturesUpdate   = 0
        FeaturesNoChange = 0
        StoriesCreate    = 0
        StoriesUpdate    = 0
        StoriesNoChange  = 0
        BugsCreate       = 0
        BugsUpdate       = 0
        BugsNoChange     = 0
        TasksCreate      = 0
        TasksUpdate      = 0
        TasksNoChange    = 0
    }

    # Determines the change state for a single item using shared Get-WorkItemChangeState logic.
    # Also checks tags via Test-TagsChanged so that tag-only changes are reported as Update.
    function Get-ItemChangeState {
        param(
            [string]$Organization,
            [string]$Project,
            [string]$PatToken,
            [object]$Item,
            [string]$Type,
            [hashtable]$MarkdownFields,
            [int]$ParentId
        )

        $resolveArgs = @{
            Organization = $Organization
            Project      = $Project
            PatToken     = $PatToken
            Item         = $Item
            Type         = $Type
        }
        if ($PSBoundParameters.ContainsKey('ParentId') -and $ParentId -gt 0) {
            $resolveArgs['ParentId'] = $ParentId
        }

        $existingId = Resolve-ExistingWorkItemId @resolveArgs
        if ($null -eq $existingId) {
            return @{ State = 'Create'; Id = $null }
        }

        $existing = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $existingId -PatToken $PatToken
        $state = Get-WorkItemChangeState -MarkdownFields $MarkdownFields -ExistingItem $existing
        # If content fields are unchanged, also check tags so tag-only changes are reported as Update
        if ($state -eq 'NoChange' -and (Test-TagsChanged -MarkdownTags $Item.tags -ExistingItem $existing)) {
            $state = 'Update'
        }
        return @{ State = $state; Id = $existingId }
    }

    # Analyze epics
    foreach ($epic in $Epics) {
        $epicResult = Get-ItemChangeState -Organization $Organization -Project $Project -PatToken $PatToken `
            -Item $epic -Type $script:WORKITEM_TYPE_EPIC -MarkdownFields (Get-EpicMarkdownFields -Epic $epic)

        switch ($epicResult.State) {
            'Create'   { $analysis.EpicsCreate++ }
            'Update'   { $analysis.EpicsUpdate++ }
            'NoChange' { $analysis.EpicsNoChange++ }
        }
        $existingEpicId = $epicResult.Id

        foreach ($feature in $epic.features) {
            $featureArgs = @{
                Organization   = $Organization
                Project        = $Project
                PatToken       = $PatToken
                Item           = $feature
                Type           = $script:WORKITEM_TYPE_FEATURE
                MarkdownFields = Get-FeatureMarkdownFields -Feature $feature
            }
            if ($null -ne $existingEpicId) { $featureArgs['ParentId'] = $existingEpicId }
            $featureResult = Get-ItemChangeState @featureArgs

            switch ($featureResult.State) {
                'Create'   { $analysis.FeaturesCreate++ }
                'Update'   { $analysis.FeaturesUpdate++ }
                'NoChange' { $analysis.FeaturesNoChange++ }
            }
            $existingFeatureId = $featureResult.Id

            foreach ($story in $feature.stories) {
                $storyArgs = @{
                    Organization   = $Organization
                    Project        = $Project
                    PatToken       = $PatToken
                    Item           = $story
                    Type           = $script:WORKITEM_TYPE_STORY
                    MarkdownFields = Get-StoryMarkdownFields -Story $story
                }
                if ($null -ne $existingFeatureId) { $storyArgs['ParentId'] = $existingFeatureId }
                $storyResult = Get-ItemChangeState @storyArgs

                switch ($storyResult.State) {
                    'Create'   { $analysis.StoriesCreate++ }
                    'Update'   { $analysis.StoriesUpdate++ }
                    'NoChange' { $analysis.StoriesNoChange++ }
                }

                foreach ($bug in $story.bugs) {
                    $analysis.BugsCreate++
                }
                foreach ($task in $story.tasks) {
                    $taskArgs = @{
                        Organization   = $Organization
                        Project        = $Project
                        PatToken       = $PatToken
                        Item           = $task
                        Type           = $script:WORKITEM_TYPE_TASK
                        MarkdownFields = Get-TaskMarkdownFields -Task $task
                    }
                    $existingStoryId = $storyResult.Id
                    if ($null -ne $existingStoryId) { $taskArgs['ParentId'] = $existingStoryId }
                    $taskResult = Get-ItemChangeState @taskArgs

                    switch ($taskResult.State) {
                        'Create'   { $analysis.TasksCreate++ }
                        'Update'   { $analysis.TasksUpdate++ }
                        'NoChange' { $analysis.TasksNoChange++ }
                    }
                }
            }
        }
    }

    # Analyze top-level features
    foreach ($feature in $Features) {
        $featureResult = Get-ItemChangeState -Organization $Organization -Project $Project -PatToken $PatToken `
            -Item $feature -Type $script:WORKITEM_TYPE_FEATURE -MarkdownFields (Get-FeatureMarkdownFields -Feature $feature)

        switch ($featureResult.State) {
            'Create'   { $analysis.FeaturesCreate++ }
            'Update'   { $analysis.FeaturesUpdate++ }
            'NoChange' { $analysis.FeaturesNoChange++ }
        }
        $existingFeatureId = $featureResult.Id

        foreach ($story in $feature.stories) {
            $storyArgs = @{
                Organization   = $Organization
                Project        = $Project
                PatToken       = $PatToken
                Item           = $story
                Type           = $script:WORKITEM_TYPE_STORY
                MarkdownFields = Get-StoryMarkdownFields -Story $story
            }
            if ($null -ne $existingFeatureId) { $storyArgs['ParentId'] = $existingFeatureId }
            $storyResult = Get-ItemChangeState @storyArgs

            switch ($storyResult.State) {
                'Create'   { $analysis.StoriesCreate++ }
                'Update'   { $analysis.StoriesUpdate++ }
                'NoChange' { $analysis.StoriesNoChange++ }
            }

            foreach ($bug in $story.bugs) {
                $analysis.BugsCreate++
            }
            foreach ($task in $story.tasks) {
                $taskArgs = @{
                    Organization   = $Organization
                    Project        = $Project
                    PatToken       = $PatToken
                    Item           = $task
                    Type           = $script:WORKITEM_TYPE_TASK
                    MarkdownFields = Get-TaskMarkdownFields -Task $task
                }
                $existingStoryId = $storyResult.Id
                if ($null -ne $existingStoryId) { $taskArgs['ParentId'] = $existingStoryId }
                $taskResult = Get-ItemChangeState @taskArgs

                switch ($taskResult.State) {
                    'Create'   { $analysis.TasksCreate++ }
                    'Update'   { $analysis.TasksUpdate++ }
                    'NoChange' { $analysis.TasksNoChange++ }
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
    [string[]]$tags = if ($Item['tags']) { [string[]]($Item['tags'] -split '\s*[,;]\s*' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) } else { [string[]]::new(0) }
    $feature = @{
        title              = $Item['title']
        workItemId         = $Item['workItemId']
        state              = $Item['state']
        assignedTo         = $Item['assignedTo']
        description        = Encode-NonHtmlAngleBrackets $Item['description']
        effort             = $Item['effort']
        priority           = $Item['priority']
        originalEstimate   = $Item['originalEstimate']
        fixedIn            = $Item['fixedIn']
        deployedToDev      = $Item['deployedToDev']
        deployedToStaging  = $Item['deployedToStaging']
        deployedToProduction = $Item['deployedToProduction']
        tags               = $tags
        stories            = [array]@()
        configFields       = if ($null -ne $Item['configFields']) { $Item['configFields'] } else { @{} }
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
    [string[]]$tags = if ($Item['tags']) { [string[]]($Item['tags'] -split '\s*[,;]\s*' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) } else { [string[]]::new(0) }
    $story = @{
        title                = $Item['title']
        workItemId           = $Item['workItemId']
        state                = $Item['state']
        assignedTo           = $Item['assignedTo']
        description          = Encode-NonHtmlAngleBrackets $Item['description']
        storyPoints          = $Item['storyPoints']
        acceptanceCriteria   = Encode-NonHtmlAngleBrackets $Item['acceptanceCriteria']
        acScenarios          = Encode-NonHtmlAngleBrackets $Item['acScenarios']
        extraInformation     = Encode-NonHtmlAngleBrackets $Item['extraInformation']
        priority             = $Item['priority']
        originalEstimate     = $Item['originalEstimate']
        fixedIn              = $Item['fixedIn']
        deployedToDev        = $Item['deployedToDev']
        deployedToStaging    = $Item['deployedToStaging']
        deployedToProduction = $Item['deployedToProduction']
        tags                 = $tags
        tasks                = [array]@()
        bugs                 = [array]@()
        configFields         = if ($null -ne $Item['configFields']) { $Item['configFields'] } else { @{} }
    }
    $children = $Item['children']
    if ($null -ne $children -and $children.Count -gt 0) {
        foreach ($child in @($children)) {
            if ($child['type'] -eq 'Task') {
                [string[]]$taskTags = if ($child['tags']) { [string[]]($child['tags'] -split '\s*[,;]\s*' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) } else { [string[]]::new(0) }
                $story.tasks += @(@{
                    title            = $child['title']
                    workItemId       = $child['workItemId']
                    description      = Encode-NonHtmlAngleBrackets $child['description']
                    priority         = $child['priority']
                    originalEstimate = $child['originalEstimate']
                    remainingWork    = $child['remainingWork']
                    completedWork    = $child['completedWork']
                    tags             = $taskTags
                })
            }
            elseif ($child['type'] -eq 'Bug') {
                [string[]]$bugTags = if ($child['tags']) { [string[]]($child['tags'] -split '\s*[,;]\s*' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) } else { [string[]]::new(0) }
                $story.bugs += @(@{
                    title       = $child['title']
                    workItemId  = $child['workItemId']
                    description = Encode-NonHtmlAngleBrackets $child['description']
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
            [string[]]$epicTags = if ($item['tags']) { [string[]]($item['tags'] -split '\s*[,;]\s*' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) } else { [string[]]::new(0) }
            $epic = @{
                title       = $item['title']
                workItemId  = $item['workItemId']
                description = Encode-NonHtmlAngleBrackets $item['description']
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

# Update the markdown file to insert **WorkItemId**: <id> after each work item header that does not already have one,
# and insert **State**: <state> after the WorkItemId line when not already present.
function Update-MarkdownWithWorkItemIds {
    param(
        [string]$MarkdownFilePath,
        [hashtable]$TitleToIdMap,
        [hashtable]$TitleToStateMap
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

                # Also insert State when a state map is provided and State is not already on next-next line
                if ($null -ne $TitleToStateMap) {
                    $foundState = $null
                    foreach ($key in $TitleToStateMap.Keys) {
                        [string]$keyStr = [string]$key
                        if ($keyStr -eq $titleFromHeader -or $keyStr -eq $normalizedTitle) {
                            $foundState = $TitleToStateMap[$key]
                            break
                        }
                    }
                    if (-not [string]::IsNullOrWhiteSpace($foundState)) {
                        # Check the line after the one we just inserted is not already a State line
                        [string]$lineAfterNextLine = if ($i + 1 -lt $lines.Count) { $lines[$i + 1] } else { '' }
                        if ($lineAfterNextLine -notmatch '^\*\*State\*\*:') {
                            $newLines.Add("**State**: $foundState")
                        }
                    }
                }
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
        # Analyze operations in dry-run mode (which items will be created vs. updated vs. unchanged)
        $analysis = Analyze-DryRunOperations -Epics $epics -Features $features -Organization $Organization -Project $Project -PatToken $PatToken
        
        # Log detailed breakdown
        $null = & ssLogIt.ps1 -Level Info -Message "DRY RUN: Detailed breakdown of planned operations:"
        $null = & ssLogIt.ps1 -Level Info -Message "  Epics:    $($analysis.EpicsCreate) to create, $($analysis.EpicsUpdate) to update, $($analysis.EpicsNoChange) no change"
        $null = & ssLogIt.ps1 -Level Info -Message "  Features: $($analysis.FeaturesCreate) to create, $($analysis.FeaturesUpdate) to update, $($analysis.FeaturesNoChange) no change"
        $null = & ssLogIt.ps1 -Level Info -Message "  Stories:  $($analysis.StoriesCreate) to create, $($analysis.StoriesUpdate) to update, $($analysis.StoriesNoChange) no change"
        $null = & ssLogIt.ps1 -Level Info -Message "  Bugs:     $($analysis.BugsCreate) to create, $($analysis.BugsUpdate) to update, $($analysis.BugsNoChange) no change"
        $null = & ssLogIt.ps1 -Level Info -Message "  Tasks:    $($analysis.TasksCreate) to create, $($analysis.TasksUpdate) to update, $($analysis.TasksNoChange) no change"
        $null = & ssLogIt.ps1 -Level Debug -Message "DryRun mode - no work items created"
        
        # Build complete dry-run output with detailed breakdown
        [hashtable]$dryRunOutput = @{
            DryRunMode = $true
            Epics      = @{
                Create   = $analysis.EpicsCreate
                Update   = $analysis.EpicsUpdate
                NoChange = $analysis.EpicsNoChange
            }
            Features   = @{
                Create   = $analysis.FeaturesCreate
                Update   = $analysis.FeaturesUpdate
                NoChange = $analysis.FeaturesNoChange
            }
            Stories    = @{
                Create   = $analysis.StoriesCreate
                Update   = $analysis.StoriesUpdate
                NoChange = $analysis.StoriesNoChange
            }
            Bugs       = @{
                Create   = $analysis.BugsCreate
                Update   = $analysis.BugsUpdate
                NoChange = $analysis.BugsNoChange
            }
            Tasks      = @{
                Create   = $analysis.TasksCreate
                Update   = $analysis.TasksUpdate
                NoChange = $analysis.TasksNoChange
            }
            Structure  = $parsedHierarchy
        }
        return $dryRunOutput
    }

    # Build summary for tracking actual operations performed
    [hashtable]$summary = @{
        PlannedEpics    = 0
        PlannedFeatures = 0
        PlannedStories  = 0
        PlannedTasks    = 0
        CreatedItems    = @{}  # all processed items by ID; kept for caller compatibility
        Created         = @{ Epics = 0; Features = 0; Stories = 0; Tasks = 0 }
        Updated         = @{ Epics = 0; Features = 0; Stories = 0; Tasks = 0 }
        NoChange        = @{ Epics = 0; Features = 0; Stories = 0; Tasks = 0 }
        TagsApplied     = 0
        TagsSkipped     = 0
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
    $null = & ssLogIt.ps1 -Level Info -Message "Processing work items from markdown..."

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
            $summary.Created.Epics++
        }
        else {
            # Existing epic found - update description and effort only if content changed
            $existingEpic = & "$PSScriptRoot\GetAzDoWorkItem.ps1" -Organization $Organization -Project $Project -WorkItemId $epicId -PatToken $PatToken -ErrorAction Stop
            $epicChangeState = Get-WorkItemChangeState -MarkdownFields (Get-EpicMarkdownFields -Epic $epic) -ExistingItem $existingEpic

            if ($epicChangeState -eq 'Update') {
                $null = & ssLogIt.ps1 -Level Debug -Message "Updating existing Epic: $($epic.title) (ID: $epicId)"

                if ($epic.description) {
                    $null = & "$PSScriptRoot\SetAzDoWorkItemDescription.ps1" -Organization $Organization -Project $Project -WorkItemId $epicId -Description $epic.description -PatToken $PatToken -ErrorAction Stop
                    $null = & ssLogIt.ps1 -Level Debug -Message "Updated Epic description for ID: $epicId"
                }

                if ($epic.effort) {
                    $null = & "$PSScriptRoot\SetAzDoEffort.ps1" -Organization $Organization -Project $Project -WorkItemId $epicId -Effort $epic.effort -PatToken $PatToken -ErrorAction Stop
                    $null = & ssLogIt.ps1 -Level Debug -Message "Updated Epic effort for ID: $epicId"
                }

                # Fetch updated epic
                $createdEpic = & "$PSScriptRoot\GetAzDoWorkItem.ps1" -Organization $Organization -Project $Project -WorkItemId $epicId -PatToken $PatToken -ErrorAction Stop
                $summary.Updated.Epics++
            }
            else {
                $null = & ssLogIt.ps1 -Level Debug -Message "No changes detected for Epic: $($epic.title) (ID: $epicId), skipping update"
                $createdEpic = $existingEpic
                $summary.NoChange.Epics++
            }
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
            
            # UPSERT feature - creates if it doesn't exist, updates only when content has changed
            $featureParams = @{
                Organization = $Organization
                Project      = $Project
                Title        = $feature.title
                ParentEpicId = $epicId
                PatToken     = $PatToken
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

            if ($feature.priority) {
                $featureParams['Priority'] = $feature.priority
            }

            if ($feature.originalEstimate) {
                $featureParams['OriginalEstimate'] = $feature.originalEstimate
            }

            if ($feature.fixedIn) {
                $featureParams['FixedIn'] = $feature.fixedIn
            }

            if ($null -ne $feature.deployedToDev) {
                $featureParams['DeployedToDev'] = $feature.deployedToDev
            }

            if ($null -ne $feature.deployedToStaging) {
                $featureParams['DeployedToStaging'] = $feature.deployedToStaging
            }

            if ($null -ne $feature.deployedToProduction) {
                $featureParams['DeployedToProduction'] = $feature.deployedToProduction
            }
            if ($feature.state) {
                $featureParams['State'] = $feature.state
            }
            if (-not [string]::IsNullOrWhiteSpace($feature.assignedTo)) {
                $featureParams['AssignedTo'] = $feature.assignedTo
            }
            # Merge config-driven fields from configFields into featureParams
            Merge-ConfigFieldsToParams -Params $featureParams -Item $feature

            # Skip upsert when item exists and content is identical
            [bool]$shouldUpsertFeature = $true
            [string]$featureState = 'Create'  # default when no existing ID
            if ($featureId -gt 0) {
                $existingFeature = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $featureId -PatToken $PatToken
                $featureChangeState = Get-WorkItemChangeState -MarkdownFields (Get-FeatureMarkdownFields -Feature $feature) -ExistingItem $existingFeature
                if ($featureChangeState -eq 'NoChange') {
                    $shouldUpsertFeature = $false
                    $featureState = 'NoChange'
                    $null = & ssLogIt.ps1 -Level Debug -Message "No changes detected for Feature: $($feature.title) (ID: $featureId), skipping update"
                    $createdFeature = $existingFeature
                } else {
                    $featureState = 'Update'
                }
            }

            if ($shouldUpsertFeature) {
                $null = & ssLogIt.ps1 -Level Debug -Message "UPSERT Feature: $($feature.title) under Epic"
                $createdFeature = & "$PSScriptRoot\UpsertAzDoFeature.ps1" @featureParams -ErrorAction Stop
            }
            $featureId = $createdFeature.id
            switch ($featureState) {
                'Create'   { $summary.Created.Features++ }
                'Update'   { $summary.Updated.Features++ }
                'NoChange' { $summary.NoChange.Features++ }
            }
            
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
                    if ($story.priority) {
                        $storyParams['Priority'] = $story.priority
                    }
                    if ($story.originalEstimate) {
                        $storyParams['OriginalEstimate'] = $story.originalEstimate
                    }
                    if ($story.fixedIn) {
                        $storyParams['FixedIn'] = $story.fixedIn
                    }
                    if ($null -ne $story.deployedToDev) {
                        $storyParams['DeployedToDev'] = $story.deployedToDev
                    }
                    if ($null -ne $story.deployedToStaging) {
                        $storyParams['DeployedToStaging'] = $story.deployedToStaging
                    }
                    if ($null -ne $story.deployedToProduction) {
                        $storyParams['DeployedToProduction'] = $story.deployedToProduction
                    }
                    if ($story.state) {
                        $storyParams['State'] = $story.state
                    }
                    if (-not [string]::IsNullOrWhiteSpace($story.assignedTo)) {
                        $storyParams['AssignedTo'] = $story.assignedTo
                    }
                    # Merge config-driven fields from configFields into storyParams
                    Merge-ConfigFieldsToParams -Params $storyParams -Item $story

                    $null = & ssLogIt.ps1 -Level Debug -Message "Creating Story: $($story.title)"
                    $createdStory = & "$PSScriptRoot\UpsertAzDoStory.ps1" @storyParams -ErrorAction Stop
                    $storyId = $createdStory.id
                    $summary.Created.Stories++
                }
                else {
                    # Update existing story only when content has changed
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
                    if ($story.priority) {
                        $storyParams['Priority'] = $story.priority
                    }
                    if ($story.originalEstimate) {
                        $storyParams['OriginalEstimate'] = $story.originalEstimate
                    }
                    if ($story.fixedIn) {
                        $storyParams['FixedIn'] = $story.fixedIn
                    }
                    if ($null -ne $story.deployedToDev) {
                        $storyParams['DeployedToDev'] = $story.deployedToDev
                    }
                    if ($null -ne $story.deployedToStaging) {
                        $storyParams['DeployedToStaging'] = $story.deployedToStaging
                    }
                    if ($null -ne $story.deployedToProduction) {
                        $storyParams['DeployedToProduction'] = $story.deployedToProduction
                    }
                    if ($story.state) {
                        $storyParams['State'] = $story.state
                    }
                    if (-not [string]::IsNullOrWhiteSpace($story.assignedTo)) {
                        $storyParams['AssignedTo'] = $story.assignedTo
                    }
                    # Merge config-driven fields from configFields into storyParams
                    Merge-ConfigFieldsToParams -Params $storyParams -Item $story

                    # Check if there are any fields to update (beyond the standard org/project/id/token)
                    $existingStory = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $storyId -PatToken $PatToken
                    $storyChangeState = Get-WorkItemChangeState -MarkdownFields (Get-StoryMarkdownFields -Story $story) -ExistingItem $existingStory
                    if ($storyChangeState -eq 'NoChange') {
                        $null = & ssLogIt.ps1 -Level Debug -Message "No changes detected for Story: $($story.title) (ID: $storyId), skipping update"
                        $createdStory = $existingStory
                        $summary.NoChange.Stories++
                    }
                    else {
                        $null = & ssLogIt.ps1 -Level Debug -Message "Updating Story: $($story.title) (ID: $storyId)"
                        $createdStory = & "$PSScriptRoot\UpsertAzDoStory.ps1" @storyParams -ErrorAction Stop
                        $summary.Updated.Stories++
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

                        # Skip upsert when task exists and content is identical
                        [bool]$shouldUpsertTask = $true
                        if ($taskParams.ContainsKey('Id')) {
                            $existingTask = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $taskParams['Id'] -PatToken $PatToken
                            $taskChangeState = Get-WorkItemChangeState -MarkdownFields (Get-TaskMarkdownFields -Task $task) -ExistingItem $existingTask
                            if ($taskChangeState -eq 'NoChange') {
                                $shouldUpsertTask = $false
                                $null = & ssLogIt.ps1 -Level Debug -Message "No changes detected for Task: $($task.title) (ID: $($taskParams['Id'])), skipping update"
                                $createdTask = $existingTask
                            }
                        }

                        if ($shouldUpsertTask) {
                            $null = & ssLogIt.ps1 -Level Debug -Message "Upserting Task: $($task.title) under Story (ID: $storyId)"
                            $createdTask = & "$PSScriptRoot\UpsertAzDoTask.ps1" @taskParams -ErrorAction Stop
                        }
                        if (-not $shouldUpsertTask) {
                            $summary.NoChange.Tasks++
                        } elseif ($taskParams.ContainsKey('Id')) {
                            $summary.Updated.Tasks++
                        } else {
                            $summary.Created.Tasks++
                        }
                        $createdItems[$createdTask.id] = $createdTask
                        $taskTitleToId[$task.title] = $createdTask.id
                    }
                }
            }
        }
    }

    # Create top-level Features
    foreach ($feature in $features) {
        # UPSERT feature - creates if it doesn't exist, updates only when content has changed
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

        if ($feature.priority) {
            $featureParams['Priority'] = $feature.priority
        }

        if ($feature.originalEstimate) {
            $featureParams['OriginalEstimate'] = $feature.originalEstimate
        }

        if ($feature.fixedIn) {
            $featureParams['FixedIn'] = $feature.fixedIn
        }

        if ($null -ne $feature.deployedToDev) {
            $featureParams['DeployedToDev'] = $feature.deployedToDev
        }

        if ($null -ne $feature.deployedToStaging) {
            $featureParams['DeployedToStaging'] = $feature.deployedToStaging
        }

        if ($null -ne $feature.deployedToProduction) {
            $featureParams['DeployedToProduction'] = $feature.deployedToProduction
        }
        if ($feature.state) {
            $featureParams['State'] = $feature.state
        }
        if (-not [string]::IsNullOrWhiteSpace($feature.assignedTo)) {
            $featureParams['AssignedTo'] = $feature.assignedTo
        }
        # Merge config-driven fields from configFields into featureParams
        Merge-ConfigFieldsToParams -Params $featureParams -Item $feature

        if ($PSBoundParameters.ContainsKey('EpicId')) {
            $featureParams['ParentEpicId'] = $EpicId
        }

        # Skip upsert when item exists and content is identical
        [bool]$shouldUpsertFeature = $true
        [string]$featureState = 'Create'  # default when no existing ID
        if ($featureParams.ContainsKey('Id')) {
            $existingFeature = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $featureParams['Id'] -PatToken $PatToken
            $featureChangeState = Get-WorkItemChangeState -MarkdownFields (Get-FeatureMarkdownFields -Feature $feature) -ExistingItem $existingFeature
            if ($featureChangeState -eq 'NoChange') {
                $shouldUpsertFeature = $false
                $featureState = 'NoChange'
                $null = & ssLogIt.ps1 -Level Debug -Message "No changes detected for Feature: $($feature.title) (ID: $($featureParams['Id'])), skipping update"
                $createdFeature = $existingFeature
            } else {
                $featureState = 'Update'
            }
        }

        if ($shouldUpsertFeature) {
            $null = & ssLogIt.ps1 -Level Debug -Message "UPSERT Feature: $($feature.title)"
            $createdFeature = & "$PSScriptRoot\UpsertAzDoFeature.ps1" @featureParams -ErrorAction Stop
        }
        $featureId = $createdFeature.id
        switch ($featureState) {
            'Create'   { $summary.Created.Features++ }
            'Update'   { $summary.Updated.Features++ }
            'NoChange' { $summary.NoChange.Features++ }
        }

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
            
            # If no existing story found, create it
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
                if ($story.priority) {
                    $storyParams['Priority'] = $story.priority
                }
                if ($story.originalEstimate) {
                    $storyParams['OriginalEstimate'] = $story.originalEstimate
                }
                if ($story.fixedIn) {
                    $storyParams['FixedIn'] = $story.fixedIn
                }
                if ($null -ne $story.deployedToDev) {
                    $storyParams['DeployedToDev'] = $story.deployedToDev
                }
                if ($null -ne $story.deployedToStaging) {
                    $storyParams['DeployedToStaging'] = $story.deployedToStaging
                }
                if ($null -ne $story.deployedToProduction) {
                    $storyParams['DeployedToProduction'] = $story.deployedToProduction
                }
                if ($story.state) {
                    $storyParams['State'] = $story.state
                }
                if (-not [string]::IsNullOrWhiteSpace($story.assignedTo)) {
                    $storyParams['AssignedTo'] = $story.assignedTo
                }
                # Merge config-driven fields from configFields into storyParams
                Merge-ConfigFieldsToParams -Params $storyParams -Item $story

                $null = & ssLogIt.ps1 -Level Debug -Message "Creating Story: $($story.title)"
                $createdStory = & "$PSScriptRoot\UpsertAzDoStory.ps1" @storyParams -ErrorAction Stop
                $storyId = $createdStory.id
                $summary.Created.Stories++
            }
            else {
                # Update existing story only when content has changed
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
                if ($story.priority) {
                    $storyParams['Priority'] = $story.priority
                }
                if ($story.originalEstimate) {
                    $storyParams['OriginalEstimate'] = $story.originalEstimate
                }
                if ($story.fixedIn) {
                    $storyParams['FixedIn'] = $story.fixedIn
                }
                if ($null -ne $story.deployedToDev) {
                    $storyParams['DeployedToDev'] = $story.deployedToDev
                }
                if ($null -ne $story.deployedToStaging) {
                    $storyParams['DeployedToStaging'] = $story.deployedToStaging
                }
                if ($null -ne $story.deployedToProduction) {
                    $storyParams['DeployedToProduction'] = $story.deployedToProduction
                }
                if ($story.state) {
                    $storyParams['State'] = $story.state
                }
                if (-not [string]::IsNullOrWhiteSpace($story.assignedTo)) {
                    $storyParams['AssignedTo'] = $story.assignedTo
                }
                # Merge config-driven fields from configFields into storyParams
                Merge-ConfigFieldsToParams -Params $storyParams -Item $story

                $existingStory = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $storyId -PatToken $PatToken
                $storyChangeState = Get-WorkItemChangeState -MarkdownFields (Get-StoryMarkdownFields -Story $story) -ExistingItem $existingStory
                if ($storyChangeState -eq 'NoChange') {
                    $null = & ssLogIt.ps1 -Level Debug -Message "No changes detected for Story: $($story.title) (ID: $storyId), skipping update"
                    $createdStory = $existingStory
                    $summary.NoChange.Stories++
                }
                else {
                    $null = & ssLogIt.ps1 -Level Debug -Message "Updating Story: $($story.title) (ID: $storyId)"
                    $createdStory = & "$PSScriptRoot\UpsertAzDoStory.ps1" @storyParams -ErrorAction Stop
                    $summary.Updated.Stories++
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

                    # Skip upsert when task exists and content is identical
                    [bool]$shouldUpsertTask = $true
                    if ($taskParams.ContainsKey('Id')) {
                        $existingTask = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $taskParams['Id'] -PatToken $PatToken
                        $taskChangeState = Get-WorkItemChangeState -MarkdownFields (Get-TaskMarkdownFields -Task $task) -ExistingItem $existingTask
                        if ($taskChangeState -eq 'NoChange') {
                            $shouldUpsertTask = $false
                            $null = & ssLogIt.ps1 -Level Debug -Message "No changes detected for Task: $($task.title) (ID: $($taskParams['Id'])), skipping update"
                            $createdTask = $existingTask
                        }
                    }

                    if ($shouldUpsertTask) {
                        $null = & ssLogIt.ps1 -Level Debug -Message "Upserting Task: $($task.title) under Story (ID: $storyId)"
                        $createdTask = & "$PSScriptRoot\UpsertAzDoTask.ps1" @taskParams -ErrorAction Stop
                    }
                    if (-not $shouldUpsertTask) {
                        $summary.NoChange.Tasks++
                    } elseif ($taskParams.ContainsKey('Id')) {
                        $summary.Updated.Tasks++
                    } else {
                        $summary.Created.Tasks++
                    }
                    $createdItems[$createdTask.id] = $createdTask
                    $taskTitleToId[$task.title] = $createdTask.id
                }
            }
        }
    }

    $summary.CreatedItems = $createdItems

    # Apply tags to work items — only when tags differ from what is already in AzDo
    $null = & ssLogIt.ps1 -Level Debug -Message "Checking tags for processed work items..."
    [int]$taggedCount = 0
    [int]$tagSkippedCount = 0
    [int]$tagErrorCount = 0

    # Build a map of titles to IDs for easier lookup
    [hashtable]$titleToId = @{}
    foreach ($itemId in $createdItems.Keys) {
        $item = $createdItems[$itemId]
        if ($item.PSObject.Properties['fields']) {
            $titleToId[$item.fields.'System.Title'] = @{ id = $itemId; type = $item.fields.'System.WorkItemType' }
        }
    }

    # Helper: apply tags only when they differ from current AzDo state
    function Invoke-TagIfChanged {
        param($WorkItemId, [string[]]$MarkdownTags, [string]$ItemLabel)
        $cachedItem = $createdItems[$WorkItemId]
        if (-not (Test-TagsChanged -MarkdownTags $MarkdownTags -ExistingItem $cachedItem)) {
            $null = & ssLogIt.ps1 -Level Debug -Message "Tags unchanged for $ItemLabel (ID: $WorkItemId), skipping"
            return 'Skipped'
        }
        $null = & "$PSScriptRoot\SetAzDoWorkItemTags.ps1" `
            -Organization $Organization `
            -Project $Project `
            -WorkItemId $WorkItemId `
            -Tags $MarkdownTags `
            -Mode Add `
            -PatToken $PatToken `
            -ErrorAction Stop
        $null = & ssLogIt.ps1 -Level Debug -Message "Tagged $ItemLabel (ID: $WorkItemId) with: $($MarkdownTags -join ', ')"
        return 'Applied'
    }

    # Apply tags to epics and their children
    foreach ($epic in $epics) {
        if ($epic.tags -and $epic.tags.Count -gt 0 -and $titleToId.ContainsKey($epic.title)) {
            $createdId = $titleToId[$epic.title].id
            try {
                switch (Invoke-TagIfChanged -WorkItemId $createdId -MarkdownTags $epic.tags -ItemLabel 'Epic') {
                    'Applied' { $taggedCount++ }
                    'Skipped' { $tagSkippedCount++ }
                }
            }
            catch { $tagErrorCount++; $null = & ssLogIt.ps1 -Level Warn -Message "Failed to tag Epic (ID: $createdId): $_" }
        }

        foreach ($feature in $epic.features) {
            if ($feature.tags -and $feature.tags.Count -gt 0 -and $titleToId.ContainsKey($feature.title)) {
                $createdId = $titleToId[$feature.title].id
                try {
                    switch (Invoke-TagIfChanged -WorkItemId $createdId -MarkdownTags $feature.tags -ItemLabel 'Feature') {
                        'Applied' { $taggedCount++ }
                        'Skipped' { $tagSkippedCount++ }
                    }
                }
                catch { $tagErrorCount++; $null = & ssLogIt.ps1 -Level Warn -Message "Failed to tag Feature (ID: $createdId): $_" }
            }

            foreach ($story in $feature.stories) {
                if ($story.tags -and $story.tags.Count -gt 0 -and $titleToId.ContainsKey($story.title)) {
                    $createdId = $titleToId[$story.title].id
                    try {
                        switch (Invoke-TagIfChanged -WorkItemId $createdId -MarkdownTags $story.tags -ItemLabel 'Story') {
                            'Applied' { $taggedCount++ }
                            'Skipped' { $tagSkippedCount++ }
                        }
                    }
                    catch { $tagErrorCount++; $null = & ssLogIt.ps1 -Level Warn -Message "Failed to tag Story (ID: $createdId): $_" }
                }

                if ($story.tasks -and $story.tasks.Count -gt 0) {
                    foreach ($task in $story.tasks) {
                        if ($task.tags -and $task.tags.Count -gt 0) {
                            if ($taskTitleToId.ContainsKey($task.title)) {
                                $createdId = $taskTitleToId[$task.title]
                                try {
                                    switch (Invoke-TagIfChanged -WorkItemId $createdId -MarkdownTags $task.tags -ItemLabel 'Task') {
                                        'Applied' { $taggedCount++ }
                                        'Skipped' { $tagSkippedCount++ }
                                    }
                                }
                                catch { $tagErrorCount++; $null = & ssLogIt.ps1 -Level Warn -Message "Failed to tag Task (ID: $createdId): $_" }
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
        if ($feature.tags -and $feature.tags.Count -gt 0 -and $titleToId.ContainsKey($feature.title)) {
            $createdId = $titleToId[$feature.title].id
            try {
                switch (Invoke-TagIfChanged -WorkItemId $createdId -MarkdownTags $feature.tags -ItemLabel 'Feature') {
                    'Applied' { $taggedCount++ }
                    'Skipped' { $tagSkippedCount++ }
                }
            }
            catch { $tagErrorCount++; $null = & ssLogIt.ps1 -Level Warn -Message "Failed to tag Feature (ID: $createdId): $_" }
        }

        foreach ($story in $feature.stories) {
            if ($story.tags -and $story.tags.Count -gt 0 -and $titleToId.ContainsKey($story.title)) {
                $createdId = $titleToId[$story.title].id
                try {
                    switch (Invoke-TagIfChanged -WorkItemId $createdId -MarkdownTags $story.tags -ItemLabel 'Story') {
                        'Applied' { $taggedCount++ }
                        'Skipped' { $tagSkippedCount++ }
                    }
                }
                catch { $tagErrorCount++; $null = & ssLogIt.ps1 -Level Warn -Message "Failed to tag Story (ID: $createdId): $_" }
            }

            if ($story.tasks -and $story.tasks.Count -gt 0) {
                foreach ($task in $story.tasks) {
                    if ($task.tags -and $task.tags.Count -gt 0) {
                        if ($taskTitleToId.ContainsKey($task.title)) {
                            $createdId = $taskTitleToId[$task.title]
                            try {
                                switch (Invoke-TagIfChanged -WorkItemId $createdId -MarkdownTags $task.tags -ItemLabel 'Task') {
                                    'Applied' { $taggedCount++ }
                                    'Skipped' { $tagSkippedCount++ }
                                }
                            }
                            catch { $tagErrorCount++; $null = & ssLogIt.ps1 -Level Warn -Message "Failed to tag Task (ID: $createdId): $_" }
                        }
                        else {
                            $null = & ssLogIt.ps1 -Level Warn -Message "Task title '$($task.title)' not found in created tasks mapping for tagging"
                        }
                    }
                }
            }
        }
    }

    if ($tagErrorCount -gt 0) {
        $null = & ssLogIt.ps1 -Level Warn -Message "$tagErrorCount tag operations failed"
    }

    $summary.TagsApplied = $taggedCount
    $summary.TagsSkipped = $tagSkippedCount

    # Write back work item IDs to the markdown file so subsequent runs update existing items
    [int]$newItemCount = $summary.Created.Epics + $summary.Created.Features + $summary.Created.Stories + $summary.Created.Tasks
    if (-not [string]::IsNullOrWhiteSpace($MarkdownFile) -and $newItemCount -gt 0) {
        $null = & ssLogIt.ps1 -Level Info -Message "Writing work item IDs back to markdown file: ::FgGreen::$MarkdownFile::FgDefault::"
        [hashtable]$idWritebackMap = @{}
        [hashtable]$stateWritebackMap = @{}
        foreach ($itemId in $createdItems.Keys) {
            $item = $createdItems[$itemId]
            if ($item.PSObject.Properties['fields']) {
                $idWritebackMap[$item.fields.'System.Title'] = $itemId
                $stateWritebackMap[$item.fields.'System.Title'] = $item.fields.'System.State'
            }
        }
        Update-MarkdownWithWorkItemIds -MarkdownFilePath $MarkdownFile -TitleToIdMap $idWritebackMap -TitleToStateMap $stateWritebackMap
        $null = & ssLogIt.ps1 -Level Info -Message "Markdown updated with work item IDs and states"
    }

    # Log a clear summary of what actually happened
    [int]$totalCreated  = $summary.Created.Epics  + $summary.Created.Features  + $summary.Created.Stories  + $summary.Created.Tasks
    [int]$totalUpdated  = $summary.Updated.Epics  + $summary.Updated.Features  + $summary.Updated.Stories  + $summary.Updated.Tasks
    [int]$totalNoChange = $summary.NoChange.Epics + $summary.NoChange.Features + $summary.NoChange.Stories + $summary.NoChange.Tasks
    $null = & ssLogIt.ps1 -Level Info -Message "=== Operation Summary ==="
    $null = & ssLogIt.ps1 -Level Info -Message "  Epics:    $($summary.Created.Epics) created, $($summary.Updated.Epics) updated, $($summary.NoChange.Epics) no change"
    $null = & ssLogIt.ps1 -Level Info -Message "  Features: $($summary.Created.Features) created, $($summary.Updated.Features) updated, $($summary.NoChange.Features) no change"
    $null = & ssLogIt.ps1 -Level Info -Message "  Stories:  $($summary.Created.Stories) created, $($summary.Updated.Stories) updated, $($summary.NoChange.Stories) no change"
    $null = & ssLogIt.ps1 -Level Info -Message "  Tasks:    $($summary.Created.Tasks) created, $($summary.Updated.Tasks) updated, $($summary.NoChange.Tasks) no change"
    $null = & ssLogIt.ps1 -Level Info -Message "  Tags:     $taggedCount applied, $tagSkippedCount skipped (no change)"
    $null = & ssLogIt.ps1 -Level Info -Message "  Total:    $totalCreated created, $totalUpdated updated, $totalNoChange no change"

    return $summary
}
catch {
    $null = & ssLogIt.ps1 -Level Error -Message "Failed to create hierarchy from markdown: $_"
    throw
}
