<#
.SYNOPSIS
Set the effort value of an Azure DevOps Epic or Feature work item

.DESCRIPTION
Updates the effort field of an existing Epic or Feature work item. Effort must be a non-negative integer.

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER WorkItemId
The work item ID to update (required)

.PARAMETER Effort
The new effort value, must be non-negative integer (required)

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
PSObject representing the updated work item

.EXAMPLE
    $updated = .\SetAzDoEffort.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123 -Effort 5

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read/write scope
- Effort must be a non-negative integer
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [int]$WorkItemId,

    [Parameter(Mandatory = $true)]
    [int]$Effort,

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
if (-not (Test-AzDoWorkItemIdValid $WorkItemId)) {
    Write-Error "Parameter 'WorkItemId' must be a positive integer."
}

if ($Effort -lt 0) {
    Write-Error "Parameter 'Effort' must be a non-negative integer. Provided: $Effort"
}

$null = & ssLogIt.ps1 -Level Info -Message "Updating effort for work item (ID: $WorkItemId) to $Effort"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    $updateFields = @{
        $script:FIELD_EFFORT = $Effort
    }

    $updated = Update-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $WorkItemId -Fields $updateFields -PatToken $PatToken

    $null = & ssLogIt.ps1 -Level Info -Message "Successfully updated effort for work item (ID: $($updated.id)) to $Effort"

    return $updated
}
catch {
    $null = & ssLogIt.ps1 -Level Error -Message "Failed to update effort: $_" -Exception $_
    Write-Error $_
    throw
}
