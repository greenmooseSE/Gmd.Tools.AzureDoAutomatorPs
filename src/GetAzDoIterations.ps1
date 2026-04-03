<#
.SYNOPSIS
Retrieve all iterations from an Azure DevOps project

.DESCRIPTION
Fetches all iterations (sprints/iterations) from an Azure DevOps project.
Returns complete iteration details including dates, names, and structure.
Iterations are returned in chronological order by start date.

Organization and Project can be provided via parameters or environment variables:
- GMD_AZDO_ORGANIZATION: Azure DevOps organization name
- GMD_AZDO_PROJECT: Azure DevOps project name
- GMD_AZDO_MACHINE_WORKITEMSRW: PAT token for operations

.PARAMETER Organization
Optional Azure DevOps organization name. If not provided, uses GMD_AZDO_ORGANIZATION environment variable.

.PARAMETER Project
Optional Azure DevOps project name. If not provided, uses GMD_AZDO_PROJECT environment variable.

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
Array of PSObject representing iterations. Each iteration includes:
- id: Unique iteration identifier
- name: Iteration name
- path: Iteration path in hierarchy
- startDate: Iteration start date (if set)
- finishDate: Iteration end date (if set)
- state: Iteration state (e.g., "Active", "Completed", "Future")
- attributes: Iteration configuration details

Returns $null if no iterations exist.

.EXAMPLE
Get all iterations from default organization/project:
    $iterations = .\GetAzDoIterations.ps1
    $iterations | Format-Table

Get iterations from specific organization/project:
    $iterations = .\GetAzDoIterations.ps1 -Organization "myorg" -Project "myproject"

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read scope
- Iterations API: https://learn.microsoft.com/en-us/rest/api/azure/devops/work/iterations
- Results are sorted by start date in ascending order
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $false)]
    [string]$Organization,

    [Parameter(Mandatory = $false)]
    [string]$Project,

    [string]$PatToken
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Import modules
. "$PSScriptRoot/AzDoAutomatorConstants.ps1"
. "$PSScriptRoot/AzDoPatTokenHelper.ps1"
. "$PSScriptRoot/AzDoApiWrapper.ps1"

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

# Get PAT token
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

# ============================================================================
# Main Script Logic
# ============================================================================

$null = & ssLogIt.ps1 -Level Info -Message "Retrieving iterations from project ::FgCyan::$Project::FgDefault:: in organization ::FgCyan::$Organization::FgDefault::"

try {
    [object[]]$iterations = Get-AzDoIterations -Organization $Organization -Project $Project -PatToken $PatToken
    
    if ($null -eq $iterations) {
        $null = & ssLogIt.ps1 -Level Debug -Message "No iterations found in project"
        return $null
    }

    $null = & ssLogIt.ps1 -Level Info -Message "Retrieved ::FgGreen::$($iterations.Count)::FgDefault:: iterations"
    
    foreach ($iteration in $iterations) {
        $null = & ssLogIt.ps1 -Level Debug -Message "  - $($iteration.name) (Start: $($iteration.attributes.startDate ?? 'Not set'), End: $($iteration.attributes.finishDate ?? 'Not set'), State: $($iteration.attributes.timeFrame ?? 'Unknown'))"
    }

    return $iterations
}
catch {
    $null = & ssLogIt.ps1 -Level Error -Exception $_
    throw
}
