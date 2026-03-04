<#
.SYNOPSIS
Retrieve an Azure DevOps work item by ID

.DESCRIPTION
Fetches a work item from Azure DevOps by its ID and returns all available fields including:
- Title, ID, Type, State
- Description, Acceptance Criteria, Story Points
- Tags, Parent, Area, Iteration
- All custom fields

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER WorkItemId
The work item ID to retrieve (required)

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from FALCOIT_AZDO_PAT_WORKITEMSREADWRITE
environment variable (expected to be encrypted).

.OUTPUTS
PSObject representing the complete work item with all fields

.EXAMPLE
    $workItem = .\Get-AzDoWorkItem.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123
    $workItem | Format-List

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read scope
- Returns $null if work item not found
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [int]$WorkItemId,

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

$null = & ssLogIt.ps1 -Level Info -Message "Retrieving work item (ID: $WorkItemId)"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    $workItem = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $WorkItemId -PatToken $PatToken

    if ($null -eq $workItem) {
        $null = & ssLogIt.ps1 -Level Error -Message "Work item not found (ID: $WorkItemId)"
        Write-Error "Work item with ID $WorkItemId not found."
    }

    $title = $workItem.fields.'System.Title'
    $type = $workItem.fields.'System.WorkItemType'
    $null = & ssLogIt.ps1 -Level Info -Message "Successfully retrieved work item: ::FgGreen::$title::FgDefault:: (Type: $type, ID: $($workItem.id))"

    return $workItem
}
catch {
    $null = & ssLogIt.ps1 -Level Error -Message "Failed to retrieve work item: $_" -Exception $_
    Write-Error $_
    throw
}
