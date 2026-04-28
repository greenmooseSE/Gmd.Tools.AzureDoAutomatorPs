#Requires -Version 7.0

<#
.SYNOPSIS
Builds an Azure DevOps identity object from an email address.

.DESCRIPTION
Returns a simplified identity object with DisplayName and UniqueName (email).
The Azure DevOps work item PATCH API accepts the email address directly in
System.AssignedTo and resolves the identity server-side, so no API call is
required.

.PARAMETER Email
The email address to use as the Azure DevOps identity.

.EXAMPLE
$identity = .\ResolveAzDoIdentity.ps1 -Email "user@example.com"
# Returns: @{ DisplayName = "user@example.com"; UniqueName = "user@example.com" }
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Email
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$null = & ssLogIt.ps1 -Level Debug -Message "Resolving identity for email: $Email"

return [PSCustomObject]@{
    DisplayName = $Email
    UniqueName  = $Email
}
