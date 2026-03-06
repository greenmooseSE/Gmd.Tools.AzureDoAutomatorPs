<#
.SYNOPSIS
Create an Azure DevOps Epic work item

.DESCRIPTION
Creates a new Epic in Azure DevOps. Epics are the top-level work item type used to organize Features.

Returns the created Epic work item with ID.

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER Title
The Epic title (required)

.PARAMETER Description
Optional description for the Epic

.PARAMETER Effort
Optional effort value for the Epic (must be a non-negative integer)

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from FALCOIT_AZDO_PAT_WORKITEMSREADWRITE
environment variable (expected to be encrypted).

.OUTPUTS
PSObject representing the created Epic work item with all fields populated

.EXAMPLE
Create a new Epic:
    $epic = .\NewAzDoEpic.ps1 -Organization "myorg" -Project "myproject" -Title "Q1 Features"

Create an Epic with description:
    $epic = .\NewAzDoEpic.ps1 -Organization "myorg" -Project "myproject" -Title "Q1 Features" -Description "Features planned for Q1"

Create an Epic with effort:
    $epic = .\NewAzDoEpic.ps1 -Organization "myorg" -Project "myproject" -Title "Q1 Features" -Effort 21

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read/write scope
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [string]$Title,

    [string]$Description,

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
    Write-Error "Required helper script 'ssLogIt.ps1' not found in PATH. Ensure helper scripts are available."
}

# Validate required parameters
if ([string]::IsNullOrWhiteSpace($Organization)) {
    Write-Error "Parameter 'Organization' cannot be empty."
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    Write-Error "Parameter 'Project' cannot be empty."
}

if ([string]::IsNullOrWhiteSpace($Title)) {
    Write-Error "Parameter 'Title' cannot be empty."
}

if ($PSBoundParameters.ContainsKey('Effort') -and $Effort -lt 0) {
    Write-Error "Parameter 'Effort' must be a non-negative integer. Provided: $Effort"
}

# Log script start
$null = & ssLogIt.ps1 -Level Info -Message "Creating Epic: ::FgGreen::$Title::FgDefault:: in project ::FgGreen::$Project::FgDefault::"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    # Create new Epic
    $createFields = @{
        $script:FIELD_SYSTEM_TITLE = $Title
    }

    if ($PSBoundParameters.ContainsKey('Description')) {
        $createFields[$script:FIELD_DESCRIPTION] = $Description
    }

    if ($PSBoundParameters.ContainsKey('Effort')) {
        $createFields[$script:FIELD_EFFORT] = $Effort
    }

    $logMessage = "Creating new Epic with title ::FgGreen::$Title::FgDefault::"
    $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

    $newEpic = New-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemType $script:WORKITEM_TYPE_EPIC -Fields $createFields -PatToken $PatToken

    $logMessage = "Successfully created Epic ::FgGreen::$Title::FgDefault:: (ID: $($newEpic.id))"
    $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"

    return $newEpic
}
catch {
    [string]$errorMsg = $_.Exception.Message
    $logMessage = "Failed to create Epic: ::FgRed::$errorMsg::FgDefault::"
    $null = & ssLogIt.ps1 -Level Error -Message "$logMessage" -Exception $_
    Write-Error $_
    throw
}
