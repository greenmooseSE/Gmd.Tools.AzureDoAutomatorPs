<#
.SYNOPSIS
Set the extra information of an Azure DevOps work item

.DESCRIPTION
Updates the extra information field of an existing work item (typically used for Stories).

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER WorkItemId
The work item ID to update (required)

.PARAMETER ExtraInformation
The new extra information text (required)

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
PSObject representing the updated work item

.EXAMPLE
    $updated = .\Set-AzDoExtraInformation.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123 -ExtraInformation "Additional context and notes"

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read/write scope
- Field name: Custom.ExtraInformation (may need adjustment per organization)
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
    [string]$ExtraInformation,

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

if ([string]::IsNullOrWhiteSpace($ExtraInformation)) {
    Write-Error "Parameter 'ExtraInformation' cannot be empty."
}

$null = & ssLogIt.ps1 -Level Info -Message "Updating extra information for work item (ID: $WorkItemId)"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    $updateFields = @{
        $script:FIELD_EXTRA_INFORMATION = $ExtraInformation
    }

    $updated = Update-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $WorkItemId -Fields $updateFields -PatToken $PatToken

    $null = & ssLogIt.ps1 -Level Info -Message "Successfully updated extra information for work item (ID: $($updated.id))"

    return $updated
}
catch {
    $null = & ssLogIt.ps1 -Level Error -Message "Failed to update extra information: $_" -Exception $_
    Write-Error $_
    throw
}
