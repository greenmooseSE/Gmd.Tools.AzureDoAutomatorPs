<#
.SYNOPSIS
Delete an Azure DevOps Feature work item, optionally including all its children.

.DESCRIPTION
This is a DESTRUCTIVE operation that deletes a Feature work item. Requires confirmation at runtime
unless -Force switch is used.

Without -Recursive, only the Feature itself is deleted. If the Feature has child work items (Stories,
Tasks, Bugs) they will become orphaned (still exist but with no parent). A warning is shown when
children are detected.

With -Recursive, all child work items are deleted first (Stories, Tasks, Bugs), then the Feature
itself is deleted.

Before deletion, displays all work items to be deleted for review.

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER FeatureId
The Feature work item ID to delete (required)

.PARAMETER Recursive
Switch: If specified, recursively deletes all child work items before deleting the Feature.
Without this switch only the Feature itself is deleted and children are orphaned.

.PARAMETER Force
Switch: If specified, skips confirmation prompt. Use with caution!

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
Summary hashtable with deleted work item count and details

.EXAMPLE
Delete Feature only (children become orphaned):
    $result = .\RemoveAzDoFeature.ps1 -Organization "myorg" -Project "myproject" -FeatureId 100

Delete Feature and all children recursively:
    $result = .\RemoveAzDoFeature.ps1 -Organization "myorg" -Project "myproject" -FeatureId 100 -Recursive

Delete Feature and all children without confirmation:
    $result = .\RemoveAzDoFeature.ps1 -Organization "myorg" -Project "myproject" -FeatureId 100 -Recursive -Force

.NOTES
- *** DESTRUCTIVE OPERATION ***
- Requires Azure DevOps REST API access
- Requires PAT token with work items read/write scope
- Will not proceed without user confirmation unless -Force is specified
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $false)]
    [string]$Organization,

    [Parameter(Mandatory = $false)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [int]$FeatureId,

    [switch]$Recursive,

    [switch]$Force,

    [string]$PatToken
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

# Apply environment variable defaults if parameters not provided
if ([string]::IsNullOrWhiteSpace($Organization)) {
    $Organization = [Environment]::GetEnvironmentVariable('GMD_AZDO_ORGANIZATION')
    if ([string]::IsNullOrWhiteSpace($Organization)) {
        Write-Error "Parameter 'Organization' is required. Provide via -Organization parameter or set GMD_AZDO_ORGANIZATION environment variable."
    }
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    $Project = [Environment]::GetEnvironmentVariable('GMD_AZDO_PROJECT')
    if ([string]::IsNullOrWhiteSpace($Project)) {
        Write-Error "Parameter 'Project' is required. Provide via -Project parameter or set GMD_AZDO_PROJECT environment variable."
    }
}

if (-not (Test-AzDoWorkItemIdValid $FeatureId)) {
    Write-Error "Parameter 'FeatureId' must be a positive integer."
}

$null = & ssLogIt.ps1 -Level Info -Message "*** DESTRUCTIVE OPERATION: Preparing to delete Feature (ID: $FeatureId)$(if ($Recursive) { ' and all children' }) ***"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    # Get the Feature itself
    $feature = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $FeatureId -PatToken $PatToken

    if ($null -eq $feature) {
        Write-Error "Feature with ID $FeatureId not found."
    }

    $featureTitle = $feature.fields.'System.Title'

    # Get descendants for either listing or deletion
    $null = & ssLogIt.ps1 -Level Debug -Message "Retrieving descendant work items..."
    $descendants = Get-AzDoAllDescendants -Organization $Organization -Project $Project -WorkItemId $FeatureId -PatToken $PatToken

    if ($Recursive) {
        $totalItemsToDelete = $descendants.Count + 1  # +1 for the feature itself

        $null = & ssLogIt.ps1 -Level Warn -Message "The following $totalItemsToDelete work item(s) will be deleted:"
        $null = & ssLogIt.ps1 -Level Warn -Message "  Feature: ::FgRed::$featureTitle::FgDefault:: (ID: $FeatureId)"

        if ($descendants.Count -gt 0) {
            $null = & ssLogIt.ps1 -PushStackLevel -Message "Descendants:"
            foreach ($descId in $descendants.Keys) {
                $descendant = $descendants[$descId]
                $descTitle = $descendant.fields.'System.Title'
                $descType = $descendant.fields.'System.WorkItemType'
                $null = & ssLogIt.ps1 -Level Warn -Message "  [$descType] $descTitle (ID: $descId)"
            }
            $null = & ssLogIt.ps1 -PopStackLevel
        }
    }
    else {
        # Non-recursive: warn if Feature has children that will become orphaned
        if ($descendants.Count -gt 0) {
            $null = & ssLogIt.ps1 -Level Warn -Message "WARNING: Feature ::FgYellow::$featureTitle::FgDefault:: (ID: $FeatureId) has $($descendants.Count) child work item(s) that will become ORPHANED (no parent) after deletion."
            $null = & ssLogIt.ps1 -Level Warn -Message "Use -Recursive to delete all children as well."
        }
        $null = & ssLogIt.ps1 -Level Warn -Message "The following 1 work item will be deleted:"
        $null = & ssLogIt.ps1 -Level Warn -Message "  Feature: ::FgRed::$featureTitle::FgDefault:: (ID: $FeatureId)"
    }

    # Prompt for confirmation if not forced
    if (-not $Force) {
        $null = & ssLogIt.ps1 -Level Warn -Message ""
        if ($Recursive) {
            Write-Host "Are you SURE you want to DELETE this Feature and $($descendants.Count) child item(s)?" -ForegroundColor Red
        }
        else {
            Write-Host "Are you SURE you want to DELETE this Feature?" -ForegroundColor Red
        }
        Write-Host "This action CANNOT be undone!" -ForegroundColor Red
        [string]$response = Read-Host "Type 'YES' to confirm deletion, any other input to cancel"

        if ($response -ne 'YES') {
            $null = & ssLogIt.ps1 -Level Info -Message "Deletion cancelled by user"
            return @{
                Cancelled    = $true
                DeletedCount = 0
                SkippedCount = 0
            }
        }
    }

    $null = & ssLogIt.ps1 -Level Info -Message "Proceeding with deletion..."

    [int]$deletedCount = 0
    [int]$skippedCount = 0

    if ($Recursive -and $descendants.Count -gt 0) {
        # Delete children first (leaf-to-root order)
        $null = & ssLogIt.ps1 -PushStackLevel -Message "Deleting child work items..."
        foreach ($descId in $descendants.Keys) {
            try {
                $descendant = $descendants[$descId]
                $descTitle = $descendant.fields.'System.Title'

                Remove-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $descId -PatToken $PatToken

                $null = & ssLogIt.ps1 -Level Debug -Message "Deleted: $descTitle (ID: $descId)"
                $deletedCount++
            }
            catch {
                $null = & ssLogIt.ps1 -Level Error -Message "Failed to delete work item $descId : $_" -Exception $_
                throw
            }
        }
        $null = & ssLogIt.ps1 -PopStackLevel
    }

    # Delete the Feature itself
    try {
        Remove-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $FeatureId -PatToken $PatToken
        $null = & ssLogIt.ps1 -Level Debug -Message "Deleted Feature: $featureTitle (ID: $FeatureId)"
        $deletedCount++
    }
    catch {
        $null = & ssLogIt.ps1 -Level Error -Message "Failed to delete Feature $FeatureId : $_" -Exception $_
        throw
    }

    $null = & ssLogIt.ps1 -Level Info -Message "Deletion complete: ::FgGreen::$deletedCount deleted::FgDefault::, ::FgRed::$skippedCount skipped::FgDefault::"

    return @{
        Cancelled    = $false
        DeletedCount = $deletedCount
        SkippedCount = $skippedCount
    }
}
catch {
    $null = & ssLogIt.ps1 -Level Error -Message "Failed to delete Feature: $_" -Exception $_
    Write-Error $_
    throw
}
