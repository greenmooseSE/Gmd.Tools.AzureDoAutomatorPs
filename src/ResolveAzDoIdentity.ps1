#Requires -Version 7.0

<#
.SYNOPSIS
Resolves an Azure DevOps team member email address to an identity object.

.DESCRIPTION
Calls the Azure DevOps Identities API to resolve a mail address to an identity.
Returns a simplified identity object with DisplayName and UniqueName (email).
Fails fast with a clear error if no identity is found for the given email.

.PARAMETER Organization
The Azure DevOps organization name.

.PARAMETER Email
The email address to resolve to an Azure DevOps identity.

.PARAMETER PatToken
Optional PAT token. If not provided, retrieved from the environment.

.EXAMPLE
$identity = .\ResolveAzDoIdentity.ps1 -Organization "myorg" -Email "user@example.com"
# Returns: @{ DisplayName = "John Doe"; UniqueName = "user@example.com" }
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$Email,

    [string]$PatToken
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/AzDoPatTokenHelper.ps1"

if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

[string]$uri = "https://vssps.dev.azure.com/$Organization/_apis/identities?searchFilter=MailAddress&filterValue=$([Uri]::EscapeDataString($Email))&api-version=7.1-preview.1"

[string]$authHeader = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PatToken"))
$headers = @{
    'Authorization' = "Basic $authHeader"
    'Accept'        = 'application/json'
}

$null = & ssLogIt.ps1 -Level Debug -Message "Resolving identity for email: $Email (org: $Organization)"

[object]$response = $null
try {
    $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -TimeoutSec 30 -ErrorAction Stop
} catch {
    $null = & ssLogIt.ps1 -Level Error -Message "Identity API call failed for email: $Email" -Exception $_
    Write-Error "Failed to resolve identity for email '$Email': $($_.Exception.Message)"
}

[array]$identities = @()
if ($null -ne $response -and $null -ne $response.value) {
    $identities = @($response.value)
}

if ($identities.Count -eq 0) {
    $null = & ssLogIt.ps1 -Level Error -Message "No identity found for email: ::FgYellow::$Email::FgDefault::"
    Write-Error "No Azure DevOps identity found for email '$Email'. Ensure the email belongs to a member of the organization '$Organization'."
}

[object]$identity = $identities[0]
[string]$displayName = if ($identity.PSObject.Properties.Name -contains 'providerDisplayName') { $identity.providerDisplayName } else { $Email }
[string]$uniqueName  = $Email

$null = & ssLogIt.ps1 -Level Debug -Message "Resolved identity: ::FgGreen::$displayName::FgDefault:: ($uniqueName)"

return [PSCustomObject]@{
    DisplayName = $displayName
    UniqueName  = $uniqueName
}
