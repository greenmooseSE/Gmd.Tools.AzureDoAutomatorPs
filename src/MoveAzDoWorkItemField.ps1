<#
.SYNOPSIS
Move or copy a field value from one field to another across Azure DevOps work items.

.DESCRIPTION
Moves or copies the value of one field to another field across a set of Azure DevOps work
items. Supports two scoping modes:
  - WorkItemId (ById parameter set): processes the specified work item and all its
    hierarchical descendants.
  - Global (Global parameter set): processes every work item in the project, including
    closed items.

By default the script performs a Move: it copies the source field value to the target field
and clears the source field. Use -Copy to leave the source field unchanged.

Use -DryRun to preview the impact without making any API changes.
Use -ConfirmEachItem to be prompted before each individual update.

.PARAMETER Organization
The Azure DevOps organization name. Default: $env:GMD_AZDO_ORGANIZATION.

.PARAMETER Project
The Azure DevOps project name. Default: $env:GMD_AZDO_PROJECT.

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from
GMD_AZDO_MACHINE_WORKITEMSRW environment variable (expected to be encrypted).

.PARAMETER SourceField
Field label as defined in appSettings.json (e.g. "Extra Information"). Both source and
target must be valid, non-readOnly field labels for each work item type.

.PARAMETER TargetField
Field label as defined in appSettings.json (e.g. "Story Acceptance Tests"). Must be a
writable field for each work item type.

.PARAMETER WorkItemId
Root work item ID (ById parameter set). Processes this item and all hierarchical
descendants.

.PARAMETER Global
Process all work items in the project (Global parameter set), including closed items.
Mutually exclusive with -WorkItemId.

.PARAMETER Copy
When specified, copies the source field value to the target field without clearing the
source. Default behaviour (without -Copy) is a Move: source field is cleared after copy.

.PARAMETER DryRun
Previews operations without making any API PATCH calls. Pipeline output shows Action =
"DryRun" for items that would be updated.

.PARAMETER ConfirmEachItem
Prompts Y/N before each individual update. Declining skips the item with Result =
"Declined".

.PARAMETER WorkItemType
Restrict processing to a specific work item type. Accepted values: Epic, Feature, Story,
Bug, Task, Any. Default: Any (processes all types).

.PARAMETER OverwriteNonEmptyTarget
When specified, overwrites the target field even if it already contains a value.
By default, work items where the target field is non-empty are skipped.

.PARAMETER ValuePreviewLength
Maximum number of characters shown when previewing field values in log output.
Newlines are stripped before truncation. Default: 100.

.PARAMETER MinId
Only process work items whose ID is greater than or equal to this value.
In Global mode the filter is also embedded in the WIQL query to avoid fetching
excluded items. Default: 0 (no filter).

.PARAMETER ChangedSince
Only process work items last changed on or after this date.
In Global mode the filter is also embedded in the WIQL query to avoid fetching
excluded items. If not specified, no date filter is applied.

.OUTPUTS
One PSObject per processed work item with properties:
  WorkItemId, Title, WorkItemType, SourceField, TargetField, Action, Result, Detail

.EXAMPLE
Move "Extra Information" to "Story Acceptance Tests" for a feature and its children:
    .\MoveAzDoWorkItemField.ps1 -WorkItemId 1234 -SourceField "Extra Information" -TargetField "Story Acceptance Tests"

Copy (keep source) with dry-run preview:
    .\MoveAzDoWorkItemField.ps1 -WorkItemId 1234 -SourceField "Extra Information" -TargetField "Story Acceptance Tests" -Copy -DryRun

Project-wide move in dry-run:
    .\MoveAzDoWorkItemField.ps1 -Global -SourceField "Extra Information" -TargetField "Story Acceptance Tests" -DryRun

.NOTES
- Requires Azure DevOps REST API access.
- Requires PAT token with work items read/write scope.
- Field resolution is driven by appSettings.json (label -> referenceName).
- Work items where the source field is empty, not applicable on the type, or the
  target is readOnly are skipped rather than producing an error.
- API rate limit: ~200 requests/minute for PAT-based auth. For very large projects
  using -Global, the script may be throttled. This is an accepted MVP limitation.
#>

#Requires -Version 7.0

[CmdletBinding(DefaultParameterSetName = 'ById')]
param(
    [Parameter(Mandatory = $false)]
    [string]$Organization,

    [Parameter(Mandatory = $false)]
    [string]$Project,

    [Parameter(Mandatory = $false)]
    [string]$PatToken,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceField,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TargetField,

    [Parameter(Mandatory = $true, ParameterSetName = 'ById')]
    [int]$WorkItemId,

    [Parameter(Mandatory = $true, ParameterSetName = 'Global')]
    [switch]$Global,

    [Parameter(Mandatory = $false)]
    [switch]$Copy,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$ConfirmEachItem,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Epic', 'Feature', 'Story', 'Bug', 'Task', 'Any')]
    [string]$WorkItemType = 'Any',

    [Parameter(Mandatory = $false)]
    [switch]$OverwriteNonEmptyTarget,

    [Parameter(Mandatory = $false)]
    [ValidateRange(10, 1000)]
    [int]$ValuePreviewLength = 100,

    [Parameter(Mandatory = $false)]
    [int]$MinId = 0,

    [Parameter(Mandatory = $false)]
    [datetime]$ChangedSince = [datetime]::MinValue
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/AzDoAutomatorConstants.ps1"
. "$PSScriptRoot/AzDoPatTokenHelper.ps1"
. "$PSScriptRoot/AzDoApiWrapper.ps1"
. "$PSScriptRoot/AzDoWorkItemHelper.ps1"

if (-not (Get-Command -Name 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    throw "Required helper script 'ssLogIt.ps1' not found in PATH."
}

if ([string]::IsNullOrWhiteSpace($Organization)) {
    $Organization = [Environment]::GetEnvironmentVariable('GMD_AZDO_ORGANIZATION')
}
if ([string]::IsNullOrWhiteSpace($Organization)) {
    throw "Parameter 'Organization' is required. Provide via -Organization or set GMD_AZDO_ORGANIZATION."
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    $Project = [Environment]::GetEnvironmentVariable('GMD_AZDO_PROJECT')
}
if ([string]::IsNullOrWhiteSpace($Project)) {
    throw "Parameter 'Project' is required. Provide via -Project or set GMD_AZDO_PROJECT."
}

if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

[string]$repoRoot    = Split-Path -Parent $PSScriptRoot
[string]$actionLabel = if ($Copy) { 'Copy' } else { 'Move' }
[string[]]$script:knownTypes = @('Epic', 'Feature', 'User Story', 'Bug', 'Task')

[int]$script:totalCount    = 0
[int]$script:updatedCount  = 0
[int]$script:skippedCount  = 0
[int]$script:errorCount    = 0
[int]$script:declinedCount = 0
$script:fieldConfigCache   = @{}

# ============================================================================
# Private helpers
# ============================================================================

function hFormatValuePreview {
    [CmdletBinding()]
    param([string]$Value)
    $flat = $Value -replace '[\r\n]+', ' '
    if ($flat.Length -gt $ValuePreviewLength) {
        return $flat.Substring(0, $ValuePreviewLength) + '...'
    }
    return $flat
}

function hGetFieldConfig {
    [CmdletBinding()]
    param([string]$WorkItemType)

    if ($script:fieldConfigCache.ContainsKey($WorkItemType)) {
        return $script:fieldConfigCache[$WorkItemType]
    }
    $fields = & "$PSScriptRoot/LoadFieldConfiguration.ps1" `
        -Organization $Organization `
        -Project $Project `
        -WorkItemType $WorkItemType `
        -RepositoryRoot $repoRoot
    $script:fieldConfigCache[$WorkItemType] = $fields
    return $fields
}

function hResolveFieldLabel {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([string]$Label)

    $result = @{}
    foreach ($type in $script:knownTypes) {
        $fields = hGetFieldConfig -WorkItemType $type
        $match = $fields | Where-Object { $_.label -eq $Label } | Select-Object -First 1
        if ($null -ne $match) {
            $result[$type] = $match
        }
    }
    return $result
}

function hNewResult {
    [CmdletBinding()]
    param(
        [int]$ItemId,
        [string]$ItemTitle,
        [string]$ItemType,
        [string]$Action,
        [string]$Result,
        [string]$Detail = ''
    )
    return [PSCustomObject]@{
        WorkItemId   = $ItemId
        Title        = $ItemTitle
        WorkItemType = $ItemType
        SourceField  = $SourceField
        TargetField  = $TargetField
        Action       = $Action
        Result       = $Result
        Detail       = $Detail
    }
}

function hCollectDescendants {
    [CmdletBinding()]
    param(
        [object]$RawItem,
        [System.Collections.Generic.List[object]]$Collected
    )
    $Collected.Add($RawItem)
    if ($null -eq $RawItem.PSObject.Properties['relations'] -or $null -eq $RawItem.relations) {
        return
    }
    $childRels = $RawItem.relations |
        Where-Object { $_.rel -eq 'System.LinkTypes.Hierarchy-Forward' }
    foreach ($rel in $childRels) {
        $childId = [int]($rel.url -split '/' | Select-Object -Last 1)
        if ($childId -le 0) { continue }
        try {
            $child = Get-AzDoWorkItemById `
                -Organization $Organization `
                -Project $Project `
                -WorkItemId $childId `
                -PatToken $PatToken
            if ($null -ne $child) {
                hCollectDescendants -RawItem $child -Collected $Collected
            }
        }
        catch {
            $null = & ssLogIt.ps1 -Level Warn -Message "Could not fetch child work item ::FgYellow::#$($childId)::FgDefault::: $_"
        }
    }
}

function hProcessWorkItem {
    [CmdletBinding()]
    param(
        [object]$RawItem,
        [hashtable]$SourceMap,
        [hashtable]$TargetMap
    )

    $script:totalCount++
    $itemId    = $RawItem.id
    $itemTitle = $RawItem.fields.'System.Title'
    $itemType  = $RawItem.fields.'System.WorkItemType'

    $null = & ssLogIt.ps1 -Level Debug -Message "Evaluating ::FgCyan::#$($itemId)::FgDefault:: '$($itemTitle)' [::FgCyan::$($itemType)::FgDefault::]"

    if ($MinId -gt 0 -and $itemId -lt $MinId) {
        $script:skippedCount++
        $null = & ssLogIt.ps1 -Level Debug -Message "  Skipped: ::FgCyan::#$($itemId)::FgDefault:: is below MinId filter (::FgYellow::$($MinId)::FgDefault::)"
        return hNewResult -ItemId $itemId -ItemTitle $itemTitle -ItemType $itemType `
            -Action 'Skip' -Result 'Skipped' -Detail "Item ID below MinId filter ($MinId)"
    }

    if ($ChangedSince -gt [datetime]::MinValue) {
        $changedProp = $RawItem.fields.PSObject.Properties['System.ChangedDate']
        if ($null -ne $changedProp) {
            [datetime]$changedDate = [datetime]$changedProp.Value
            if ($changedDate -lt $ChangedSince) {
                $script:skippedCount++
                $null = & ssLogIt.ps1 -Level Debug -Message "  Skipped: ::FgCyan::#$($itemId)::FgDefault:: changed $($changedDate.ToString('yyyy-MM-dd')), before ChangedSince filter (::FgYellow::$($ChangedSince.ToString('yyyy-MM-dd'))::FgDefault::)"
                return hNewResult -ItemId $itemId -ItemTitle $itemTitle -ItemType $itemType `
                    -Action 'Skip' -Result 'Skipped' -Detail "Item changed before ChangedSince filter ($($ChangedSince.ToString('yyyy-MM-dd')))"
            }
        }
    }

    if ($WorkItemType -ne 'Any') {
        # 'Story' in the parameter maps to 'User Story' in Azure DevOps
        $filterType = if ($WorkItemType -eq 'Story') { 'User Story' } else { $WorkItemType }
        if ($itemType -ne $filterType) {
            $script:skippedCount++
            $null = & ssLogIt.ps1 -Level Debug -Message "  Skipped: type filter is '::FgYellow::$($WorkItemType)::FgDefault::', item type is '::FgYellow::$($itemType)::FgDefault::'"
            return hNewResult -ItemId $itemId -ItemTitle $itemTitle -ItemType $itemType `
                -Action 'Skip' -Result 'Skipped' -Detail "Excluded by WorkItemType filter '$WorkItemType'"
        }
    }

    if (-not $SourceMap.ContainsKey($itemType)) {
        $script:skippedCount++
        $null = & ssLogIt.ps1 -Level Debug -Message "  Skipped: '::FgYellow::$($SourceField)::FgDefault::' not available on $($itemType)"
        return hNewResult -ItemId $itemId -ItemTitle $itemTitle -ItemType $itemType `
            -Action 'Skip' -Result 'Skipped' -Detail "Source field not available on $itemType"
    }

    $srcDef     = $SourceMap[$itemType]
    $srcRefName = $srcDef.referenceName

    if (-not $TargetMap.ContainsKey($itemType)) {
        $script:skippedCount++
        $null = & ssLogIt.ps1 -Level Debug -Message "  Skipped: '::FgYellow::$($TargetField)::FgDefault::' not available on $($itemType)"
        return hNewResult -ItemId $itemId -ItemTitle $itemTitle -ItemType $itemType `
            -Action 'Skip' -Result 'Skipped' -Detail "Target field not available on $itemType"
    }

    $tgtDef     = $TargetMap[$itemType]
    $tgtRefName = $tgtDef.referenceName

    if ($tgtDef.readOnly -eq $true) {
        $script:skippedCount++
        $null = & ssLogIt.ps1 -Level Debug -Message "  Skipped: target '::FgYellow::$($TargetField)::FgDefault::' is readOnly on $($itemType)"
        return hNewResult -ItemId $itemId -ItemTitle $itemTitle -ItemType $itemType `
            -Action 'Skip' -Result 'Skipped' -Detail "Target field is readOnly on $itemType"
    }

    $sourceValue = if ($null -ne $RawItem.fields.PSObject.Properties[$srcRefName]) {
        $RawItem.fields.$srcRefName
    }
    else {
        $null
    }
    if ([string]::IsNullOrWhiteSpace($sourceValue)) {
        $script:skippedCount++
        $null = & ssLogIt.ps1 -Level Debug -Message "  Skipped: source field is empty"
        return hNewResult -ItemId $itemId -ItemTitle $itemTitle -ItemType $itemType `
            -Action 'Skip' -Result 'Skipped' -Detail 'Source field is empty'
    }

    $targetValue = if ($null -ne $RawItem.fields.PSObject.Properties[$tgtRefName]) {
        $RawItem.fields.$tgtRefName
    }
    else {
        $null
    }
    if ($sourceValue -eq $targetValue) {
        $script:skippedCount++
        $null = & ssLogIt.ps1 -Level Info -Message "  Skipped: source and target field values are already identical on ::FgCyan::#$($itemId)::FgDefault::"
        return hNewResult -ItemId $itemId -ItemTitle $itemTitle -ItemType $itemType `
            -Action 'Skip' -Result 'Skipped' -Detail 'Source and target field values are already identical'
    }

    if (-not [string]::IsNullOrWhiteSpace($targetValue) -and -not $OverwriteNonEmptyTarget) {
        $script:skippedCount++
        $null = & ssLogIt.ps1 -Level Info -Message "  Skipped: target field is non-empty on ::FgCyan::#$($itemId)::FgDefault:: (use ::FgYellow::-OverwriteNonEmptyTarget::FgDefault:: to overwrite)"
        return hNewResult -ItemId $itemId -ItemTitle $itemTitle -ItemType $itemType `
            -Action 'Skip' -Result 'Skipped' -Detail 'Target field already has a value'
    }

    if ($ConfirmEachItem) {
        $srcPreview = hFormatValuePreview -Value $sourceValue
        $tgtPreview = if (-not [string]::IsNullOrWhiteSpace($targetValue)) {
            hFormatValuePreview -Value $targetValue
        } else { '(empty)' }
        $null = & ssLogIt.ps1 -Level Info -Message "$($actionLabel) '::FgYellow::$($SourceField)::FgDefault::' -> '::FgYellow::$($TargetField)::FgDefault::' on ::FgCyan::#$($itemId)::FgDefault:: '$($itemTitle)'`n  Source: '::FgGreen::$($srcPreview)::FgDefault::'`n  Target: '::FgYellow::$($tgtPreview)::FgDefault::'"
        $answer = Read-Host "Proceed? (Y/N)"
        if ($answer -notmatch '^[Yy]') {
            $script:skippedCount++
            $script:declinedCount++
            $null = & ssLogIt.ps1 -Level Info -Message "  Declined"
            return hNewResult -ItemId $itemId -ItemTitle $itemTitle -ItemType $itemType `
                -Action $actionLabel -Result 'Declined' -Detail 'User declined'
        }
    }

    if ($DryRun) {
        $script:updatedCount++
        $null = & ssLogIt.ps1 -Level Info -Message "  [DryRun] Would $($actionLabel.ToLower()) '::FgYellow::$($SourceField)::FgDefault::' -> '::FgYellow::$($TargetField)::FgDefault::' on ::FgCyan::#$($itemId)::FgDefault::"
        return hNewResult -ItemId $itemId -ItemTitle $itemTitle -ItemType $itemType `
            -Action 'DryRun' -Result 'Updated' -Detail "Would $($actionLabel.ToLower()) value"
    }

    $patchFields = @{
        $tgtRefName = $sourceValue
    }
    if (-not $Copy) {
        $patchFields[$srcRefName] = ''
    }

    try {
        $null = Update-AzDoWorkItem `
            -Organization $Organization `
            -Project $Project `
            -WorkItemId $itemId `
            -Fields $patchFields `
            -PatToken $PatToken

        $script:updatedCount++
        $null = & ssLogIt.ps1 -Level Info -Message "  ::FgGreen::✅ $($actionLabel)d::FgDefault:: '::FgYellow::$($SourceField)::FgDefault::' -> '::FgYellow::$($TargetField)::FgDefault::' on ::FgCyan::#$($itemId)::FgDefault::"
        return hNewResult -ItemId $itemId -ItemTitle $itemTitle -ItemType $itemType `
            -Action $actionLabel -Result 'Updated'
    }
    catch {
        $script:errorCount++
        $errMsg = $_.Exception.Message
        $null = & ssLogIt.ps1 -Level Error -Message "  ::FgRed::Error::FgDefault:: on ::FgCyan::#$($itemId)::FgDefault::: $($errMsg)" -Exception $_
        return hNewResult -ItemId $itemId -ItemTitle $itemTitle -ItemType $itemType `
            -Action $actionLabel -Result 'Error' -Detail $errMsg
    }
}

# ============================================================================
# Validate field labels (pre-flight)
# ============================================================================

$null = & ssLogIt.ps1 -Level Info -Message "Validating field labels '::FgYellow::$($SourceField)::FgDefault::' and '::FgYellow::$($TargetField)::FgDefault::'..."

$sourceFieldMap = hResolveFieldLabel -Label $SourceField
$targetFieldMap = hResolveFieldLabel -Label $TargetField

if ($sourceFieldMap.Count -eq 0) {
    throw "SourceField '$SourceField' is not a recognised field label in appSettings.json for any work item type."
}
if ($targetFieldMap.Count -eq 0) {
    throw "TargetField '$TargetField' is not a recognised field label in appSettings.json for any work item type."
}

# ============================================================================
# Collect and process work items
# ============================================================================

if ($PSCmdlet.ParameterSetName -eq 'ById') {
    $null = & ssLogIt.ps1 -Level Info -Message "Collecting hierarchy for work item ::FgCyan::$($WorkItemId)::FgDefault::..."

    $rootItem = Get-AzDoWorkItemById `
        -Organization $Organization `
        -Project $Project `
        -WorkItemId $WorkItemId `
        -PatToken $PatToken

    if ($null -eq $rootItem) {
        throw "Work item $WorkItemId not found."
    }

    $null = & ssLogIt.ps1 -Level Info -Message "Root: '::FgCyan::$($rootItem.fields.'System.Title')::FgDefault::' [::FgCyan::$($rootItem.fields.'System.WorkItemType')::FgDefault::]"
    $collected = [System.Collections.Generic.List[object]]::new()
    hCollectDescendants -RawItem $rootItem -Collected $collected
    $null = & ssLogIt.ps1 -Level Info -Message "Total work items to evaluate: ::FgCyan::$($collected.Count)::FgDefault::"

    foreach ($wi in $collected) {
        hProcessWorkItem -RawItem $wi -SourceMap $sourceFieldMap -TargetMap $targetFieldMap
    }
}
else {
    # Global scope: build WIQL with optional filters, then fetch and process item by item
    $null = & ssLogIt.ps1 -Level Info -Message "Global scope: querying all work items in project '::FgCyan::$($Project)::FgDefault::'..."

    [string]$wiqlWhere = "[System.TeamProject] = @project"
    if ($MinId -gt 0) {
        $wiqlWhere += " AND [System.Id] >= $MinId"
    }
    if ($ChangedSince -gt [datetime]::MinValue) {
        $wiqlWhere += " AND [System.ChangedDate] >= '$($ChangedSince.ToString('yyyy-MM-dd'))'"
    }
    $wiqlQuery = "SELECT [System.Id] FROM WorkItems WHERE $wiqlWhere ORDER BY [System.Id] ASC"

    $wiqlResults = Invoke-AzDoWiql `
        -Organization $Organization `
        -Project $Project `
        -Query $wiqlQuery `
        -PatToken $PatToken

    if ($null -ne $wiqlResults -and $wiqlResults.Count -gt 0) {
        $null = & ssLogIt.ps1 -Level Info -Message "WIQL returned ::FgCyan::$($wiqlResults.Count)::FgDefault:: work item(s). Fetching and processing..."

        [int]$processedSoFar = 0
        foreach ($wiRef in $wiqlResults) {
            $wiId = if ($null -ne $wiRef.id) { $wiRef.id } else {
                [int]($wiRef.url -split '/' | Select-Object -Last 1)
            }
            $processedSoFar++
            if ($processedSoFar % 25 -eq 0) {
                $null = & ssLogIt.ps1 -Level Debug -Message "Progress: ::FgCyan::$($processedSoFar)/$($wiqlResults.Count)::FgDefault::..."
            }
            try {
                $wi = Get-AzDoWorkItemById `
                    -Organization $Organization `
                    -Project $Project `
                    -WorkItemId $wiId `
                    -PatToken $PatToken
                if ($null -ne $wi) {
                    hProcessWorkItem -RawItem $wi -SourceMap $sourceFieldMap -TargetMap $targetFieldMap
                }
            }
            catch {
                $null = & ssLogIt.ps1 -Level Warn -Message "Could not fetch work item ::FgYellow::$($wiId)::FgDefault::: $_"
            }
        }
    }
    else {
        $null = & ssLogIt.ps1 -Level Info -Message "No work items found in project."
    }
}

# ============================================================================
# Summary
# ============================================================================

$summaryAction = if ($DryRun) { "DryRun ($($actionLabel))" } else { $actionLabel }
$null = & ssLogIt.ps1 -Level Info -Message "::FgGreen::✅ $($summaryAction) complete::FgDefault::: ::FgCyan::$($script:totalCount)::FgDefault:: evaluated, ::FgGreen::$($script:updatedCount)::FgDefault:: updated, ::FgYellow::$($script:skippedCount)::FgDefault:: skipped, ::FgRed::$($script:errorCount)::FgDefault:: errors"
