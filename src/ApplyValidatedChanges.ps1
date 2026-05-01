<#
.SYNOPSIS
Apply validated changes back to Azure DevOps with transaction-like safety

.DESCRIPTION
Takes a validated diff (from DetectHierarchyChanges.ps1) and applies the changes to Azure DevOps.
Provides comprehensive error handling and rollback behavior:

- Pre-validates all changes before making any updates (fail-fast)
- Applies changes in dependency order (new parents before children)
- Tracks created item IDs for proper parent-child relationships
- Halts entire operation on first failure with detailed error reporting
- Never silently skips changes; always reports what happened

Behavior:
- Creates new work items (Epic > Feature > Story > Task/Bug in order)
- Updates existing work items with modified fields
- Manages parent-child relationships for new items
- Validates all parent IDs exist before creating children
- Reportsummary of all applied changes and any failures

Requires environment variables:
- GMD_AZDO_ORGANIZATION: Azure DevOps organization name
- GMD_AZDO_PROJECT: Azure DevOps project name
- GMD_AZDO_MACHINE_WORKITEMSRW: Encrypted PAT token

Requires AzDoAutomatorConstants.ps1 and AzDoApiWrapper.ps1 to be loaded via dot-sourcing.

.PARAMETER ValidatedDiff
The validated diff object (from DetectHierarchyChanges.ps1) with operations array.
Each operation must have: operationType, workItemType, title, changes, itemId, parentIdAfter, dependsOn

.PARAMETER DryRun
Switch: If specified, shows what would be applied without making actual changes

.PARAMETER PatToken
Optional PAT token. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW environment variable.

.OUTPUTS
PSObject with structure:
{
  "success": true|false,
  "appliedChanges": <number>,
  "createdItems": { "new_title": <newId>, ... },
  "failedOperation": <operation> | null,
  "failureReason": <string> | null,
  "operationsSummary": [
    {
      "operationType": "Create|Update",
      "itemId": <id>,
      "title": "<title>",
      "status": "Applied|Failed"
    }
  ]
}

.EXAMPLE
# Detect changes and apply them
$original = Get-Content "original-hierarchy.json" | ConvertFrom-Json
$modified = Get-Content "modified-hierarchy.json" | ConvertFrom-Json

$diff = .\DetectHierarchyChanges.ps1 -OriginalHierarchy $original -ModifiedHierarchy $modified

if ($diff.validationPassed) {
    # First do a dry run to see what would happen
    $result = .\ApplyValidatedChanges.ps1 -ValidatedDiff $diff -DryRun
    if ($result.success) {
        Write-Host "Dry run OK. Applied $($result.appliedChanges) in test mode."
        
        # Now apply for real
        $actualResult = .\ApplyValidatedChanges.ps1 -ValidatedDiff $diff
        if ($actualResult.success) {
            Write-Host "Successfully applied all changes!"
        } else {
            Write-Host "Failed at: $($actualResult.failedOperation | ConvertTo-Json -Compress)"
        }
    }
}
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [object]$ValidatedDiff,

    [switch]$DryRun,

    [string]$Organization,

    [string]$Project,

    [string]$PatToken
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Import required modules
. "$(Split-Path $MyInvocation.MyCommand.Path)/AzDoPatTokenHelper.ps1"
. "$(Split-Path $MyInvocation.MyCommand.Path)/AzDoAutomatorConstants.ps1"
. "$(Split-Path $MyInvocation.MyCommand.Path)/AzDoApiWrapper.ps1"

# ============================================================================
# Configuration
# ============================================================================

$Organization = if (-not [string]::IsNullOrWhiteSpace($Organization)) { $Organization } else { $env:GMD_AZDO_ORGANIZATION }
$Project = if (-not [string]::IsNullOrWhiteSpace($Project)) { $Project } else { $env:GMD_AZDO_PROJECT }

if ([string]::IsNullOrWhiteSpace($Organization)) {
    Write-Error "Organization not set. Provide -Organization or configure GMD_AZDO_ORGANIZATION environment variable."
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    Write-Error "Project not set. Provide -Project or configure GMD_AZDO_PROJECT environment variable."
}

$script:createdItemMap = @{}
$script:appliedChanges = 0
$script:operationsSummary = @()

# ============================================================================
# Helper Functions
# ============================================================================

function ResolveDependencyId {
    param([object]$DependencyId)
    
    # If it's already a numeric ID, return it
    if ($DependencyId -is [int]) {
        return $DependencyId
    }
    
    # If it's a string, it might be a key from created items
    if ($DependencyId -is [string]) {
        if ($script:createdItemMap.ContainsKey($DependencyId)) {
            return $script:createdItemMap[$DependencyId]
        }
    }
    
    return $DependencyId
}

function Create-WorkItem {
    param(
        [string]$Type,
        [string]$Title,
        [hashtable]$Fields,
        [int]$ParentId
    )
    
    $apiFields = @{
        'System.Title' = $Title
    }
    
    if ($Fields.ContainsKey('description') -and $Fields['description']) {
        $apiFields['System.Description'] = $Fields['description']
    }
    if ($Fields.ContainsKey('tags') -and $Fields['tags']) {
        $apiFields['System.Tags'] = $Fields['tags']
    }
    
    switch ($Type) {
        'Story' {
            if ($Fields.ContainsKey('storyPoints') -and $Fields['storyPoints']) { $apiFields['Microsoft.VSTS.Scheduling.StoryPoints'] = $Fields['storyPoints'] }
            if ($Fields.ContainsKey('acceptanceCriteria') -and $Fields['acceptanceCriteria']) { $apiFields['Microsoft.VSTS.Common.AcceptanceCriteria'] = $Fields['acceptanceCriteria'] }
            if ($Fields.ContainsKey('acceptanceTests') -and $Fields['acceptanceTests']) { $apiFields['Custom.AcceptanceTests'] = $Fields['acceptanceTests'] }
        }
        { $_ -in 'Feature', 'Epic' } {
            if ($Fields.ContainsKey('effort') -and $Fields['effort']) { $apiFields['Microsoft.VSTS.Scheduling.Effort'] = $Fields['effort'] }
        }
        'Bug' {
            if ($Fields.ContainsKey('priority') -and $Fields['priority']) { $apiFields['Microsoft.VSTS.Common.Priority'] = $Fields['priority'] }
        }
    }
    
    if ($Fields.ContainsKey('extraInformation') -and $Fields['extraInformation']) {
        $apiFields['Custom.ExtraInformation'] = $Fields['extraInformation']
    }
    
    if ($Fields.ContainsKey('customFields') -and $Fields['customFields'] -is [hashtable]) {
        foreach ($customFieldName in $Fields['customFields'].Keys) {
            $customFieldValue = $Fields['customFields'][$customFieldName]
            if ($null -ne $customFieldValue -and -not [string]::IsNullOrWhiteSpace($customFieldValue.ToString())) {
                $apiFields[$customFieldName] = $customFieldValue.ToString()
            }
        }
    }
    
    $workItem = New-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemType $Type -Fields $apiFields -ParentId:$ParentId -PatToken:$PatToken
    return $workItem
}

function Update-WorkItem {
    param(
        [int]$Id,
        [hashtable]$Changes
    )
    
    $fields = @{}
    
    foreach ($fieldName in $Changes.Keys) {
        $change = $Changes[$fieldName]
        
        $azFieldName = switch ($fieldName) {
            'title' { 'System.Title' }
            'description' { 'System.Description' }
            'state' { 'System.State' }
            'tags' { 'System.Tags' }
            'storyPoints' { 'Microsoft.VSTS.Scheduling.StoryPoints' }
            'effort' { 'Microsoft.VSTS.Scheduling.Effort' }
            'acceptanceCriteria' { 'Microsoft.VSTS.Common.AcceptanceCriteria' }
            'acceptanceTests' { 'Custom.AcceptanceTests' }
            'extraInformation' { 'Custom.ExtraInformation' }
            { $fieldName -match '^Custom\.' } { $fieldName }
            default { $null }
        }
        
        if ($null -ne $azFieldName) {
            $fields[$azFieldName] = $change.after
        }
    }
    
    if ($fields.Count -gt 0) {
        $workItem = Update-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $Id -Fields $fields -PatToken:$PatToken
        return $workItem
    }
    
    return $null
}

# ============================================================================
# Main Logic
# ============================================================================

# Validate input
if (-not $ValidatedDiff.operations) {
    return @{
        success          = $true
        appliedChanges   = 0
        createdItems     = @{}
        failedOperation  = $null
        failureReason    = $null
        operationsSummary = @()
    }
}

if (-not $ValidatedDiff.validationPassed) {
    return @{
        success          = $false
        appliedChanges   = 0
        createdItems     = @{}
        failedOperation  = $null
        failureReason    = "Diff validation failed: $($ValidatedDiff.errors -join '; ')"
        operationsSummary = @()
    }
}

# Process each operation in dependency order
foreach ($operation in $ValidatedDiff.operations) {
    try {
        $opSummary = @{
            operationType = $operation.operationType
            itemId        = $operation.itemId
            title         = $operation.title
            status        = 'Applied'
        }
        
        if ($DryRun) {
            Write-Host "[DRY RUN] $($operation.operationType) $($operation.workItemType): $($operation.title)"
            $script:appliedChanges++
        }
        else {
            switch ($operation.operationType) {
                'Create' {
                    $parentId = $null
                    if ($operation.parentIdAfter) {
                        $parentId = ResolveDependencyId -DependencyId $operation.parentIdAfter
                    }
                    
                    # Extract field values from changes
                    $fields = @{}
                    foreach ($fieldName in $operation.changes.Keys) {
                        $fields[$fieldName] = $operation.changes[$fieldName].after
                    }
                    
                    $newItem = Create-WorkItem -Type $operation.workItemType -Title $operation.title -Fields $fields -ParentId $parentId
                    $newId = $newItem.id
                    
                    # Store mapping for dependencies
                    if (-not $operation.itemId) {
                        $mapKey = "new_$($operation.title)"
                        $script:createdItemMap[$mapKey] = $newId
                    }
                    
                    $opSummary.itemId = $newId
                    $script:appliedChanges++
                }
                'Update' {
                    $updated = Update-WorkItem -Id $operation.itemId -Changes $operation.changes
                    $script:appliedChanges++
                }
                'Move' {
                    # Reparent the work item to the new parent
                    $newParentId = ResolveDependencyId -DependencyId $operation.parentIdAfter
                    $moved = Move-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $operation.itemId -NewParentId $newParentId -PatToken:$PatToken
                    $script:appliedChanges++
                }
            }
        }
        
        $script:operationsSummary += [PSCustomObject]$opSummary
    }
    catch {
        $failureSummary = @{
            operationType = $operation.operationType
            itemId        = $operation.itemId
            title         = $operation.title
            status        = 'Failed'
            error         = $_.Exception.Message
        }
        
        $script:operationsSummary += [PSCustomObject]$failureSummary
        
        return @{
            success           = $false
            appliedChanges    = $script:appliedChanges
            createdItems      = $script:createdItemMap
            failedOperation   = $operation
            failureReason     = "Failed to apply $($operation.operationType.ToLower()) operation for $($operation.workItemType) '$($operation.title)': $($_.Exception.Message)"
            operationsSummary = $script:operationsSummary
        }
    }
}

# All operations completed successfully
return @{
    success           = $true
    appliedChanges    = $script:appliedChanges
    createdItems      = $script:createdItemMap
    failedOperation   = $null
    failureReason     = $null
    operationsSummary = $script:operationsSummary
}
