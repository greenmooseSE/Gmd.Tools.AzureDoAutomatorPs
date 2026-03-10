<#
.SYNOPSIS
Delete an Azure DevOps Bug work item

.DESCRIPTION
Removes a Bug work item from Azure DevOps by ID. By default, prompts for confirmation before deletion.
Use -Force to delete without confirmation.

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER BugId
The Bug work item ID to delete (required)

.PARAMETER Force
Optional switch to delete without confirmation prompt

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
JSON success summary with deleted Bug ID and status

.EXAMPLE
Delete a Bug with confirmation:
    .\RemoveAzDoBug.ps1 -Organization "myorg" -Project "myproject" -BugId 42

Delete a Bug without confirmation:
    .\RemoveAzDoBug.ps1 -Organization "myorg" -Project "myproject" -BugId 42 -Force

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items delete scope
- Deletion is permanent and cannot be undone
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $false)]
    [string]$Organization,

    [Parameter(Mandatory = $false)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [int]$BugId,

    [switch]$Force,

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
    # Fetch Bug first to get title for confirmation
    $logMessage = "Fetching Bug (ID: ::FgGreen::$BugId::FgDefault::) for deletion"
    $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

    $bug = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $BugId -PatToken $PatToken

    if ($null -eq $bug) {
        $logMessage = "Bug with ID ::FgGreen::$BugId::FgDefault:: not found"
        $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
        Write-Error "Bug with ID $BugId not found in project $Project"
    }

    $bugTitle = if ($bug.fields.PSObject.Properties.Name -contains 'System.Title') { $bug.fields.'System.Title' } else { 'Unknown' }

    # Confirm deletion unless -Force is used
    if (-not $Force) {
        $logMessage = "Requesting confirmation to delete Bug: $bugTitle (ID: ::FgGreen::$BugId::FgDefault::)"
        $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"

        $confirm = Read-Host "Delete Bug '$bugTitle' (ID: $BugId)? (y/n)"
        if ($confirm -ne 'y') {
            $logMessage = "Bug deletion cancelled by user"
            $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"
            return @{
                success = $false
                message = "Deletion cancelled"
                bugId   = $BugId
                bugTitle = $bugTitle
            } | ConvertTo-Json
        }
    }

    # Perform deletion
    $logMessage = "Deleting Bug: $bugTitle (ID: ::FgGreen::$BugId::FgDefault::)"
    $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

    Remove-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $BugId -PatToken $PatToken

    $logMessage = "Successfully deleted Bug: $bugTitle (ID: ::FgGreen::$BugId::FgDefault::)"
    $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"

    return @{
        success  = $true
        message  = "Bug deleted successfully"
        bugId    = $BugId
        bugTitle = $bugTitle
    } | ConvertTo-Json
}
catch {
    [string]$errorMsg = $_.Exception.Message
    $logMessage = "Failed to delete Bug (ID: $BugId): ::FgRed::$errorMsg::FgDefault::"
    $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
    throw
}
