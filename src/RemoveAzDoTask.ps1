<#
.SYNOPSIS
Delete an Azure DevOps Task work item

.DESCRIPTION
Deletes a Task work item from Azure DevOps by ID. Requires confirmation at runtime unless -Force switch is used.

Tasks are typically leaf-level work items with no children, so deletion is straightforward.

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER TaskId
The Task work item ID to delete (required)

.PARAMETER Force
Switch: If specified, skips confirmation prompt. Use with caution!

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
Boolean - $true if deletion succeeded; PSObject with summary on success

.EXAMPLE
Delete Task with confirmation prompt (safe default):
    $result = .\RemoveAzDoTask.ps1 -Organization "myorg" -Project "myproject" -TaskId 100

Delete Task without confirmation (use with caution):
    $result = .\RemoveAzDoTask.ps1 -Organization "myorg" -Project "myproject" -TaskId 100 -Force

.NOTES
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
    [int]$TaskId,

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

# Validate required parameters
if (-not (Test-AzDoWorkItemIdValid $TaskId)) {
    Write-Error "Parameter 'TaskId' must be a positive integer."
}

$null = & ssLogIt.ps1 -Level Info -Message "Preparing to delete Task (ID: $TaskId)"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    # Get the Task itself
    $task = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $TaskId -PatToken $PatToken

    if ($null -eq $task) {
        Write-Error "Task with ID $TaskId not found."
    }

    # Display task being deleted
    $taskTitle = $task.fields.'System.Title'
    $null = & ssLogIt.ps1 -Level Warn -Message "The following Task will be deleted:"
    $null = & ssLogIt.ps1 -Level Warn -Message "  Task: ::FgRed::$taskTitle::FgDefault:: (ID: $TaskId)"

    # Prompt for confirmation if not forced
    if (-not $Force) {
        $null = & ssLogIt.ps1 -Level Warn -Message ""
        Write-Host "Are you SURE you want to DELETE this Task?" -ForegroundColor Red
        Write-Host "This action CANNOT be undone!" -ForegroundColor Red
        [string]$response = Read-Host "Type 'YES' to confirm deletion, any other input to cancel"

        if ($response -ne 'YES') {
            $null = & ssLogIt.ps1 -Level Info -Message "Deletion cancelled by user"
            return @{
                Cancelled      = $true
                DeletedCount   = 0
            }
        }
    }

    $null = & ssLogIt.ps1 -Level Info -Message "Proceeding with deletion..."

    # Delete the Task
    try {
        Remove-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $TaskId -PatToken $PatToken

        $null = & ssLogIt.ps1 -Level Debug -Message "Deleted Task: $taskTitle (ID: $TaskId)"
        $null = & ssLogIt.ps1 -Level Info -Message "Deletion complete: ::FgGreen::Task deleted successfully::FgDefault::"

        return @{
            Cancelled      = $false
            DeletedCount   = 1
            TaskTitle      = $taskTitle
            TaskId         = $TaskId
        }
    }
    catch {
        $null = & ssLogIt.ps1 -Level Error -Message "Failed to delete Task $TaskId : $_" -Exception $_
        throw
    }
}
catch {
    $null = & ssLogIt.ps1 -Level Error -Message "Failed to delete Task: $_" -Exception $_
    Write-Error $_
    throw
}
