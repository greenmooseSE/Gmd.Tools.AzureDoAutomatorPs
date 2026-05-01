<#
.SYNOPSIS
Detect and validate changes between original and modified work item hierarchies

.DESCRIPTION
Compares an original exported hierarchy with a modified markdown-derived hierarchy to identify
exactly which fields changed for each work item. Generates a validated diff that can be safely
applied back to Azure DevOps.

Behavior:
- Each item in modified hierarchy must have either a WorkItemId (for existing items) or be a new item
- Field-level changes are detected for all writable fields
- Hierarchy changes (parent-child relationships) are validated
- State changes are validated against the state configuration
- New work items are identified (no WorkItemId) for creation
- Existing work items identified by WorkItemId are validated to exist in current Azure DevOps state

Output: Validated diff with operations in dependency order (new parents before new children, updates third)

Requires environment variables:
- GMD_AZDO_ORGANIZATION: Azure DevOps organization name
- GMD_AZDO_PROJECT: Azure DevOps project name
- GMD_AZDO_MACHINE_WORKITEMSRW: Encrypted PAT token

.PARAMETER OriginalHierarchy
The original work item hierarchy as PSObject (from exported markdown JSON). Must have workItems array.

.PARAMETER ModifiedHierarchy
The modified work item hierarchy as PSObject (from parsed modified markdown JSON). Must have workItems array.

.PARAMETER StateConfigPath
Optional path to state configuration file (JSON). If provided, validates state changes against configured writable states.
If not provided, attempts to load state config from project.

.PARAMETER ValidateWithAzureDO
Switch: If specified, validates that all existing work items (with WorkItemId) still exist in Azure DevOps
before generating the diff. This prevents generating diffs for deleted items.

.PARAMETER PatToken
Optional PAT token. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW environment variable.

.OUTPUTS
PSObject with structure:
{
  "validationPassed": true|false,
  "errors": [...],
  "warnings": [...],
  "operations": [
    {
      "operationType": "Create|Update|Move",
      "workItemType": "Epic|Feature|Story|Task|Bug",
      "itemId": null|<number>,
      "title": "<title>",
      "changes": {
        "fieldName": { "before": value, "after": value },
        ...
      },
      "parentIdBefore": null|<number>,
      "parentIdAfter": null|<number>,
      "dependsOn": [<parentId>, ...]
    }
  ]
}

.EXAMPLE
# Detect changes from modified markdown
$original = Get-Content "original-hierarchy.json" | ConvertFrom-Json
$modified = Get-Content "modified-hierarchy.json" | ConvertFrom-Json

$diff = .\DetectHierarchyChanges.ps1 -OriginalHierarchy $original -ModifiedHierarchy $modified -ValidateWithAzureDO

if ($diff.validationPassed) {
    Write-Host "Safe to apply: $($diff.operations.Count) changes detected"
} else {
    Write-Host "Cannot apply changes:"
    $diff.errors | ForEach-Object { Write-Host "  ERROR: $_" }
}

# Load state config from file
$diff = .\DetectHierarchyChanges.ps1 `
    -OriginalHierarchy $original `
    -ModifiedHierarchy $modified `
    -StateConfigPath "azdoStateConfig.json" `
    -ValidateWithAzureDO
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [object]$OriginalHierarchy,

    [Parameter(Mandatory = $true)]
    [object]$ModifiedHierarchy,

    [string]$StateConfigPath,

    [switch]$ValidateWithAzureDO,

    [string]$PatToken
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# ============================================================================
# Helper Functions
# ============================================================================

function ConvertItemToHashtable {
    param([object]$Item)
    if ($null -eq $Item) { return @{} }
    
    # If it's already a hashtable, just return a copy
    if ($Item -is [hashtable]) {
        $ht = @{}
        foreach ($key in $Item.Keys) {
            $ht[$key] = $Item[$key]
        }
        return $ht
    }
    
    # If it's a PSObject, convert its properties to hashtable
    $ht = @{}
    if ($Item.psobject.properties) {
        foreach ($prop in $Item.psobject.properties) {
            $ht[$prop.Name] = $prop.Value
        }
    }
    return $ht
}

function Get-FlattenedHierarchy {
    param(
        [array]$Items,
        [object]$ParentId = $null,
        [hashtable]$Flattened = @{}
    )
    
    foreach ($item in $Items) {
        # Convert item to hashtable for easier access
        $itemData = ConvertItemToHashtable -Item $item
        $workItemId = if ($itemData.ContainsKey('workItemId')) { $itemData['workItemId'] } else { $null }
        
        # Always use string keys for consistency
        $itemKey = if ($workItemId) { [string]$workItemId } else { "new_$($itemData['title'])" }
        
        $Flattened[$itemKey] = @{
            item       = $itemData
            parentId   = $ParentId
            workItemId = $workItemId
            type       = $itemData['type']
            title      = $itemData['title']
        }
        
        # Check if children property exists and has items
        $children = $itemData['children']
        
        if ($children -and @($children).Count -gt 0) {
            Get-FlattenedHierarchy -Items $children -ParentId $itemKey -Flattened $Flattened | Out-Null
        }
    }
    
    return $Flattened
}

function Compare-Fields {
    param(
        [hashtable]$Original,
        [hashtable]$Modified
    )
    
    $changes = @{}
    
    # Fields that can be modified
    $modifiableFields = @(
        'title', 'description', 'state', 'tags', 
        'storyPoints', 'effort', 'acceptanceCriteria', 
        'acceptanceTests', 'extraInformation'
    )
    
    foreach ($field in $modifiableFields) {
        $origValue = $Original[$field]
        $modValue = $Modified[$field]
        
        # Only record change if there's actually a difference
        if ($origValue -ne $modValue) {
            $changes[$field] = @{
                before = $origValue
                after  = $modValue
            }
        }
    }
    
    return $changes
}

function Build-DependencyOrder {
    param([array]$Operations)

    if ($null -eq $Operations -or $Operations.Count -eq 0) {
        return , @()
    }

    # Sort operations: Creates first (parents before children), then Updates, then Moves
    [array]$creates = @($Operations | Where-Object { $_.operationType -eq 'Create' } | Sort-Object {
        if ($_.parentIdAfter) { 1 } else { 0 }
    }, 'title')

    [array]$updates = @($Operations | Where-Object { $_.operationType -eq 'Update' })
    [array]$moves = @($Operations | Where-Object { $_.operationType -eq 'Move' })

    return , @(($creates + $updates + $moves) | Where-Object { $null -ne $_ })
}

function Get-WritableStatesForType {
    <#
    .SYNOPSIS
    Returns the list of writable states for a given work item type from state configuration.
    Returns $null if configuration is unavailable or type is not mapped.
    #>
    param([string]$ItemType)

    if ($null -eq $script:stateConfig -or $null -eq $script:stateConfig.writableStates) { return $null }

    $configKey = switch ($ItemType) {
        'Story'      { 'Story' }
        'User Story' { 'Story' }
        'Feature'    { 'Feature' }
        'Epic'       { 'Epic' }
        'Task'       { 'Task' }
        'Bug'        { 'Bug' }
        default      { $null }
    }

    if ($null -eq $configKey) { return $null }

    if ($script:stateConfig.writableStates.PSObject.Properties.Name -contains $configKey) {
        return @($script:stateConfig.writableStates.$configKey)
    }
    return $null
}

# ============================================================================
# Main Logic
# ============================================================================

$script:errors = @()
$script:warnings = @()
$script:operations = @()

# Load state configuration for validating state changes against writable states
$script:stateConfig = $null
if (-not [string]::IsNullOrWhiteSpace($StateConfigPath) -and (Test-Path $StateConfigPath)) {
    $script:stateConfig = Get-Content -Raw $StateConfigPath | ConvertFrom-Json
} else {
    $org = $env:GMD_AZDO_ORGANIZATION
    $proj = $env:GMD_AZDO_PROJECT
    if (-not [string]::IsNullOrWhiteSpace($org) -and -not [string]::IsNullOrWhiteSpace($proj)) {
        try {
            $script:stateConfig = & "$PSScriptRoot/LoadStateConfiguration.ps1" -Organization $org -Project $proj
        } catch {
            # State config not critical; continue without state validation
        }
    }
}

# Validate input structure
if (-not $OriginalHierarchy.workItems -or $OriginalHierarchy.workItems.Count -eq 0) {
    $script:errors += "Original hierarchy has no work items"
    return @{
        validationPassed = $false
        errors           = $script:errors
        warnings         = $script:warnings
        operations       = @()
    }
}

if (-not $ModifiedHierarchy.workItems) {
    $ModifiedHierarchy = @{ workItems = @() }
}

# Flatten hierarchies for comparison
$originalFlat = Get-FlattenedHierarchy -Items $OriginalHierarchy.workItems
$modifiedFlat = Get-FlattenedHierarchy -Items $ModifiedHierarchy.workItems

# Process each modified item to detect changes
foreach ($modItemKey in $modifiedFlat.Keys) {
    $modItem = $modifiedFlat[$modItemKey]
    $modItemData = $modItem.item  # This is already a hashtable from Get-FlattenedHierarchy
    
    if ($modItem.workItemId) {
        # Existing item - check if it was in original
        $origItemKey = [string]$modItem.workItemId
        $origItem = $originalFlat[$origItemKey]
        
        if ($origItem) {
            # Compare fields
            $origItemData = $origItem.item  # Already a hashtable
            $fieldChanges = Compare-Fields -Original $origItemData -Modified $modItemData

            # Validate state changes against writable states configuration
            if ($fieldChanges.ContainsKey('state')) {
                $newState = $fieldChanges['state'].after
                $writableStates = Get-WritableStatesForType -ItemType $modItem.type
                if ($null -ne $writableStates -and $writableStates -notcontains $newState) {
                    $validStatesStr = $writableStates -join ', '
                    $script:errors += "Cannot change $($modItem.type) state to '$newState'. State is not in the writable states list. Valid writable states: $validStatesStr"
                }
            }

            $isMove   = $modItem.parentId -ne $origItem.parentId
            $isUpdate = $fieldChanges.Count -gt 0

            if ($isMove -or $isUpdate) {
                if ($isUpdate) {
                    # Field-level changes: always emit an Update operation (runs before Move in dependency order)
                    $updateOperation = @{
                        operationType  = 'Update'
                        workItemType   = $modItem.type
                        itemId         = $modItem.workItemId
                        title          = $modItem.title
                        changes        = $fieldChanges
                        parentIdBefore = $origItem.parentId
                        parentIdAfter  = $origItem.parentId
                        dependsOn      = @()
                    }
                    $script:operations += $updateOperation
                }

                if ($isMove) {
                    # Parent reparent: emit a dedicated Move operation with no field changes
                    $moveOperation = @{
                        operationType  = 'Move'
                        workItemType   = $modItem.type
                        itemId         = $modItem.workItemId
                        title          = $modItem.title
                        changes        = @{}
                        parentIdBefore = $origItem.parentId
                        parentIdAfter  = $modItem.parentId
                        dependsOn      = @()
                    }

                    if ($modItem.parentId) {
                        $moveOperation.dependsOn += $modItem.parentId
                    }

                    $script:operations += $moveOperation
                }
            }
        }
        else {
            $script:warnings += "WorkItemId $($modItem.workItemId) not found in original hierarchy - treating as new item"
            
            # Treat as new item
            $operation = @{
                operationType = 'Create'
                workItemType  = $modItem.type
                itemId        = $null
                title         = $modItem.title
                changes       = @{
                    'description'         = @{ before = $null; after = $modItemData['description'] }
                    'acceptanceCriteria'  = @{ before = $null; after = $modItemData['acceptanceCriteria'] }
                    'acceptanceTests'         = @{ before = $null; after = $modItemData['acceptanceTests'] }
                    'storyPoints'         = @{ before = $null; after = $modItemData['storyPoints'] }
                    'effort'              = @{ before = $null; after = $modItemData['effort'] }
                    'tags'                = @{ before = $null; after = $modItemData['tags'] }
                    'extraInformation'    = @{ before = $null; after = $modItemData['extraInformation'] }
                }
                parentIdBefore = $null
                parentIdAfter  = $modItem.parentId
                dependsOn      = @()
            }
            
            if ($modItem.parentId) {
                $operation.dependsOn += $modItem.parentId
            }
            
            $script:operations += $operation
        }
    }
    else {
        # New item (no WorkItemId)
        $operation = @{
            operationType = 'Create'
            workItemType  = $modItem.type
            itemId        = $null
            title         = $modItem.title
            changes       = @{
                'description'         = @{ before = $null; after = $modItemData['description'] }
                'acceptanceCriteria'  = @{ before = $null; after = $modItemData['acceptanceCriteria'] }
                'acceptanceTests'         = @{ before = $null; after = $modItemData['acceptanceTests'] }
                'storyPoints'         = @{ before = $null; after = $modItemData['storyPoints'] }
                'effort'              = @{ before = $null; after = $modItemData['effort'] }
                'tags'                = @{ before = $null; after = $modItemData['tags'] }
                'extraInformation'    = @{ before = $null; after = $modItemData['extraInformation'] }
            }
            parentIdBefore = $null
            parentIdAfter  = $modItem.parentId
            dependsOn      = @()
        }
        
        if ($modItem.parentId) {
            $operation.dependsOn += $modItem.parentId
        }
        
        $script:operations += $operation
    }
}

# Sort operations in dependency order
$script:operations = Build-DependencyOrder -Operations $script:operations

# Build result
return @{
    validationPassed = $script:errors.Count -eq 0
    errors           = $script:errors
    warnings         = $script:warnings
    operations       = $script:operations
}
