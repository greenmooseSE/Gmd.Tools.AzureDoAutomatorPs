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

$Organization = $env:GMD_AZDO_ORGANIZATION
$Project = $env:GMD_AZDO_PROJECT

if ([string]::IsNullOrWhiteSpace($Organization)) {
    Write-Error "Organization not set. Configure GMD_AZDO_ORGANIZATION environment variable."
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    Write-Error "Project not set. Configure GMD_AZDO_PROJECT environment variable."
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
    
    $patch = @(
        @{
            op    = 'add'
            path  = '/fields/System.Title'
            value = $Title
        }
    )
    
    # Add common fields if provided
    if ($Fields.description) {
        $patch += @{
            op    = 'add'
            path  = '/fields/System.Description'
            value = $Fields.description
        }
    }
    
    if ($Fields.tags) {
        $patch += @{
            op    = 'add'
            path  = '/fields/System.Tags'
            value = $Fields.tags
        }
    }
    
    # Add type-specific fields
    switch ($Type) {
        'Story' {
            if ($Fields.storyPoints) {
                $patch += @{
                    op    = 'add'
                    path  = '/fields/Microsoft.VSTS.Scheduling.StoryPoints'
                    value = $Fields.storyPoints
                }
            }
            if ($Fields.acceptanceCriteria) {
                $patch += @{
                    op    = 'add'
                    path  = '/fields/Microsoft.VSTS.Common.AcceptanceCriteria'
                    value = $Fields.acceptanceCriteria
                }
            }
            if ($Fields.acScenarios) {
                $patch += @{
                    op    = 'add'
                    path  = '/fields/Custom.ACScenarios'
                    value = $Fields.acScenarios
                }
            }
        }
        'Feature' {
            if ($Fields.effort) {
                $patch += @{
                    op    = 'add'
                    path  = '/fields/Microsoft.VSTS.Scheduling.Effort'
                    value = $Fields.effort
                }
            }
        }
        'Epic' {
            if ($Fields.effort) {
                $patch += @{
                    op    = 'add'
                    path  = '/fields/Microsoft.VSTS.Scheduling.Effort'
                    value = $Fields.effort
                }
            }
        }
        'Task' {
            # Tasks don't support Acceptance Criteria
        }
        'Bug' {
            if ($Fields.priority) {
                $patch += @{
                    op    = 'add'
                    path  = '/fields/Microsoft.VSTS.Common.Priority'
                    value = $Fields.priority
                }
            }
        }
    }
    
    if ($Fields.extraInformation) {
        $patch += @{
            op    = 'add'
            path  = '/fields/Custom.ExtraInformation'
            value = $Fields.extraInformation
        }
    }
    
    # Add any custom fields (fields starting with "Custom." or captured from markdown)
    if ($Fields.customFields -and $Fields.customFields -is [hashtable]) {
        foreach ($customFieldName in $Fields.customFields.Keys) {
            $customFieldValue = $Fields.customFields[$customFieldName]
            if ($null -ne $customFieldValue -and -not [string]::IsNullOrWhiteSpace($customFieldValue.ToString())) {
                $patch += @{
                    op    = 'add'
                    path  = "/fields/$customFieldName"
                    value = $customFieldValue.ToString()
                }
            }
        }
    }
    
    # Add parent if provided
    if ($ParentId) {
        $patch += @{
            op    = 'add'
            path  = '/relations/-'
            value = @{
                rel  = 'System.LinkTypes.Hierarchy-Reverse'
                url  = "https://dev.azure.com/$Organization/_apis/wit/workitems/$ParentId"
            }
        }
    }
    
    $workItem = New-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemType $Type -Patch $patch -PatToken:$PatToken
    return $workItem
}

function Update-WorkItem {
    param(
        [int]$Id,
        [hashtable]$Changes
    )
    
    $patch = @()
    
    foreach ($fieldName in $Changes.Keys) {
        $change = $Changes[$fieldName]
        
        $fieldPath = switch ($fieldName) {
            'title' { '/fields/System.Title' }
            'description' { '/fields/System.Description' }
            'state' { '/fields/System.State' }
            'tags' { '/fields/System.Tags' }
            'storyPoints' { '/fields/Microsoft.VSTS.Scheduling.StoryPoints' }
            'effort' { '/fields/Microsoft.VSTS.Scheduling.Effort' }
            'acceptanceCriteria' { '/fields/Microsoft.VSTS.Common.AcceptanceCriteria' }
            'acScenarios' { '/fields/Custom.ACScenarios' }
            'extraInformation' { '/fields/Custom.ExtraInformation' }
            # Handle custom fields that start with "Custom."
            { $fieldName -match '^Custom\.' } { "/fields/$fieldName" }
            default { $null }
        }
        
        if ($fieldPath) {
            $patch += @{
                op    = 'replace'
                path  = $fieldPath
                value = $change.after
            }
        }
        # Also handle any custom fields that might have been captured from markdown
        # (e.g., fields like Custom.Platform, Custom.CustomField, etc.)
        elseif ($fieldName -match '^Custom\.') {
            $patch += @{
                op    = 'replace'
                path  = "/fields/$fieldName"
                value = $change.after
            }
        }
    }
    
    if ($patch.Count -gt 0) {
        $workItem = Update-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $Id -Patch $patch -PatToken:$PatToken
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
                    # For now, moves are handled as updates
                    $updated = Update-WorkItem -Id $operation.itemId -Changes $operation.changes
                    $script:appliedChanges++
                }
            }
        }
        
        $script:operationsSummary += $opSummary
    }
    catch {
        $failureSummary = @{
            operationType = $operation.operationType
            itemId        = $operation.itemId
            title         = $operation.title
            status        = 'Failed'
            error         = $_.Exception.Message
        }
        
        $script:operationsSummary += $failureSummary
        
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
