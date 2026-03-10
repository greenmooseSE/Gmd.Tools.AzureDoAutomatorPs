<#
.SYNOPSIS
Retrieve an Azure DevOps Bug work item

.DESCRIPTION
Fetches a Bug work item from Azure DevOps by ID and returns its complete object with all fields,
comments, attachments, and tags populated.

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER BugId
The Bug work item ID to retrieve (required)

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
PSObject representing the Bug work item with all fields, comments, and metadata

.EXAMPLE
Retrieve a Bug by ID:
    $bug = .\GetAzDoBug.ps1 -Organization "myorg" -Project "myproject" -BugId 42

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read scope
- Returns complete Bug object with all metadata
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $false)]
    [string]$Organization,

    [Parameter(Mandatory = $false)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [int]$BugId,

    [string]$PatToken
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Import modules
. "$PSScriptRoot/AzDoPatTokenHelper.ps1"
. "$PSScriptRoot/AzDoApiWrapper.ps1"

# Validate ssLogIt.ps1 exists
if (-not (Get-Command -Name 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    Write-Error "Required helper script 'ssLogIt.ps1' not found in PATH. Ensure helper scripts are available."
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
if ([string]::IsNullOrWhiteSpace($Organization)) {
    Write-Error "Parameter 'Organization' cannot be empty."
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    Write-Error "Parameter 'Project' cannot be empty."
}

if ($BugId -le 0) {
    Write-Error "Parameter 'BugId' must be a positive integer."
}

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    $logMessage = "Retrieving Bug (ID: ::FgGreen::$BugId::FgDefault::)"
    $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"

    $bug = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $BugId -PatToken $PatToken

    if ($null -eq $bug) {
        $logMessage = "Bug with ID ::FgGreen::$BugId::FgDefault:: not found"
        $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
        Write-Error "Bug with ID $BugId not found in project $Project"
    }

    $bugTitle = if ($bug.fields.PSObject.Properties.Name -contains 'System.Title') { $bug.fields.'System.Title' } else { 'Unknown' }
    $logMessage = "Successfully retrieved Bug: $bugTitle (ID: $BugId)"
    $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"

    return $bug
}
catch {
    [string]$errorMsg = $_.Exception.Message
    $logMessage = "Failed to retrieve Bug (ID: $BugId): ::FgRed::$errorMsg::FgDefault::"
    $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
    throw
}
