<#
.SYNOPSIS
Verify PAT has read access to Azure DevOps work items

.DESCRIPTION
Runs a minimal WIQL query to validate that the supplied PAT token can read
work items for the specified organization and project.

.PARAMETER Organization
Azure DevOps organization name (required)

.PARAMETER Project
Azure DevOps project name (required)

.PARAMETER PatToken
Optional PAT token. If not provided, uses FALCOIT_AZDO_PAT_WORKITEMSREADWRITE
from the environment (encrypted) and decrypts it.

.OUTPUTS
Boolean: $true if read access is confirmed

.EXAMPLE
.\VerifyAzDoPat.ps1 -Organization "falco-it" -Project "GMD"

.EXAMPLE
.\VerifyAzDoPat.ps1 -Organization "falco-it" -Project "GMD" -PatToken $token
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$Project,

    [string]$PatToken
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

[string]$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

. "$SCRIPT_DIR/AzDoAutomatorConstants.ps1"
. "$SCRIPT_DIR/AzDoPatTokenHelper.ps1"
. "$SCRIPT_DIR/AzDoApiWrapper.ps1"

if (-not (Get-Command -Name 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    Write-Error "Required helper script 'ssLogIt.ps1' not found in PATH. Ensure helper scripts are available."
}

if ([string]::IsNullOrWhiteSpace($Organization)) {
    Write-Error "Parameter 'Organization' cannot be empty."
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    Write-Error "Parameter 'Project' cannot be empty."
}

if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    $null = & ssLogIt.ps1 -Level Info -Message "Verifying PAT work item read access for ::FgGreen::$Organization/$Project::FgDefault::"

    [string]$wiql = "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = '$Project'"

    $workItems = Invoke-AzDoWiql -Organization $Organization -Project $Project -Query $wiql -PatToken $PatToken

    $count = @($workItems).Count
    $null = & ssLogIt.ps1 -Level Info -Message "Read access verified. Work items returned: ::FgGreen::$count::FgDefault::"

    return $true
}
catch {
    [string]$errorMsg = $_.Exception.Message
    $null = & ssLogIt.ps1 -Level Error -Message "Failed to verify PAT access: ::FgRed::$errorMsg::FgDefault::" -Exception $_
    Write-Error $_
    throw
}
