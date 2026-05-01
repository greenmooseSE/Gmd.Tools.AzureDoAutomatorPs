<#
.SYNOPSIS
Set the acceptance tests (BDD scenarios) of an Azure DevOps work item

.DESCRIPTION
Updates the Custom.AcceptanceTests field of an existing work item (typically used for Stories).

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER WorkItemId
The work item ID to update (required)

.PARAMETER AcceptanceTests
The new acceptance tests text (Gherkin/BDD scenarios) (required)

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
PSObject representing the updated work item

.EXAMPLE
    $updated = .\SetAzDoAcceptanceTests.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123 -AcceptanceTests "Given user logs in, When they click logout button, Then session ends"

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read/write scope
- Field name: Custom.AcceptanceTests
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $false)]
    [string]$Organization,

    [Parameter(Mandatory = $false)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [int]$WorkItemId,

    [Parameter(Mandatory = $true)]
    [string]$AcceptanceTests,

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

# Validate required parameters
if (-not (Test-AzDoWorkItemIdValid $WorkItemId)) {
    Write-Error "Parameter 'WorkItemId' must be a positive integer."
}

if ([string]::IsNullOrWhiteSpace($AcceptanceTests)) {
    Write-Error "Parameter 'AcceptanceTests' cannot be empty."
}

$null = & ssLogIt.ps1 -Level Info -Message "Updating acceptance tests for work item (ID: $WorkItemId)"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    $updateFields = @{
        $script:FIELD_ACCEPTANCE_TESTS = $AcceptanceTests
    }

    $updated = Update-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $WorkItemId -Fields $updateFields -PatToken $PatToken

    $null = & ssLogIt.ps1 -Level Info -Message "Successfully updated acceptance tests for work item (ID: $($updated.id))"

    return $updated
}
catch {
    $null = & ssLogIt.ps1 -Level Error -Message "Failed to update acceptance tests: $_" -Exception $_
    Write-Error $_
    throw
}
