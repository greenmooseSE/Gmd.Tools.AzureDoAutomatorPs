<#
.SYNOPSIS
Delete an Azure DevOps Epic and all its children

.DESCRIPTION
This is a DESTRUCTIVE operation that deletes an Epic and all child work items (Features, Stories, Tasks, etc.)
recursively. Requires confirmation at runtime unless -Force switch is used.

Before deletion, displays all work items to be deleted for review.

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER EpicId
The Epic work item ID to delete (required)

.PARAMETER Force
Switch: If specified, skips confirmation prompt. Use with caution!

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from FALCOIT_AZDO_PAT_WORKITEMSREADWRITE
environment variable (expected to be encrypted).

.OUTPUTS
Summary hashtable with deleted work item count and details

.EXAMPLE
Delete Epic with confirmation prompt (safe default):
    $result = .\Remove-AzDoEpic.ps1 -Organization "myorg" -Project "myproject" -EpicId 100

Delete Epic without confirmation (use with caution):
    $result = .\Remove-AzDoEpic.ps1 -Organization "myorg" -Project "myproject" -EpicId 100 -Force

.NOTES
- *** DESTRUCTIVE OPERATION ***
- Requires Azure DevOps REST API access
- Requires PAT token with work items read/write scope
- Will not proceed without user confirmation unless -Force is specified
- AI-generated work items created for testing should be the primary use case
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [int]$EpicId,

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

# Validate required parameters
if (-not (Test-AzDoWorkItemIdValid $EpicId)) {
    Write-Error "Parameter 'EpicId' must be a positive integer."
}

$null = & ssLogIt.ps1 -Level Info -Message "*** DESTRUCTIVE OPERATION: Preparing to delete Epic (ID: $EpicId) and all children ***"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    # Get all descendants
    $null = & ssLogIt.ps1 -Level Debug -Message "Retrieving Epic and all descendant work items..."
    $descendants = Get-AzDoAllDescendants -Organization $Organization -Project $Project -WorkItemId $EpicId -PatToken $PatToken

    # Get the Epic itself
    $epic = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $EpicId -PatToken $PatToken

    if ($null -eq $epic) {
        Write-Error "Epic with ID $EpicId not found."
    }

    $totalItemsToDelete = $descendants.Count + 1  # +1 for the epic itself

    # Display items to be deleted
    $epicTitle = $epic.fields.'System.Title'
    $null = & ssLogIt.ps1 -Level Warn -Message "The following $totalItemsToDelete work item(s) will be deleted:"
    $null = & ssLogIt.ps1 -Level Warn -Message "  Epic: ::FgRed::$epicTitle::FgDefault:: (ID: $EpicId)"

    if ($descendants.Count -gt 0) {
        $null = & ssLogIt.ps1 -PushStackLevel -Message "Descendants:"
        foreach ($descId in $descendants.Keys) {
            $descendant = $descendants[$descId]
            $descTitle = $descendant.fields.'System.Title'
            $descType = $descendant.fields.'System.WorkItemType'
            $null = & ssLogIt.ps1 -Level Warn -Message "    [$descType] $descTitle (ID: $descId)"
        }
        $null = & ssLogIt.ps1 -PopStackLevel
    }

    # Prompt for confirmation if not forced
    if (-not $Force) {
        $null = & ssLogIt.ps1 -Level Warn -Message ""
        Write-Host "Are you SURE you want to DELETE this Epic and $($descendants.Count) child item(s)?" -ForegroundColor Red
        Write-Host "This action CANNOT be undone!" -ForegroundColor Red
        [string]$response = Read-Host "Type 'YES' to confirm deletion, any other input to cancel"

        if ($response -ne 'YES') {
            $null = & ssLogIt.ps1 -Level Info -Message "Deletion cancelled by user"
            return @{
                Cancelled      = $true
                DeletedCount   = 0
                SkippedCount   = 0
            }
        }
    }

    $null = & ssLogIt.ps1 -Level Info -Message "Proceeding with deletion..."

    # Delete children first (to avoid parent-child constraints)
    [int]$deletedCount = 0
    [int]$skippedCount = 0

    if ($descendants.Count -gt 0) {
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

    # Delete the Epic itself
    try {
        Remove-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $EpicId -PatToken $PatToken
        $null = & ssLogIt.ps1 -Level Debug -Message "Deleted Epic: $epicTitle (ID: $EpicId)"
        $deletedCount++
    }
    catch {
        $null = & ssLogIt.ps1 -Level Error -Message "Failed to delete Epic $EpicId : $_" -Exception $_
        throw
    }

    $null = & ssLogIt.ps1 -Level Info -Message "Deletion complete: ::FgGreen::$deletedCount deleted::FgDefault::, ::FgRed::$skippedCount skipped::FgDefault::"

    return @{
        Cancelled      = $false
        DeletedCount   = $deletedCount
        SkippedCount   = $skippedCount
    }
}
catch {
    $null = & ssLogIt.ps1 -Level Error -Message "Failed to delete Epic: $_" -Exception $_
    Write-Error $_
    throw
}
