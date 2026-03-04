<#
.SYNOPSIS
Azure DevOps PAT Token Helper Module

.DESCRIPTION
Handles retrieval and management of Azure DevOps Personal Access Tokens (PAT).
Supports:
- Retrieving encrypted PAT tokens from environment variables
- Decryption of tokens
- Base64 encoding for API authentication
- PAT token validation

.NOTES
Uses ssEncryptDecrypt.ps1 for token decryption when needed.
Default environment variable: FALCOIT_AZDO_PAT_WORKITEMSREADWRITE
#>

#Requires -Version 7.0

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# ============================================================================
# Private Helper Functions
# ============================================================================

<#
.SYNOPSIS
Check if ssEncryptDecrypt.ps1 helper is available

.DESCRIPTION
Verifies that the ssEncryptDecrypt.ps1 script is available in PATH.
#>
function Confirm-SsEncryptDecryptHelperExists {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $cmd = Get-Command -Name 'ssEncryptDecrypt.ps1' -ErrorAction SilentlyContinue
        return $null -ne $cmd
    }
    catch {
        return $false
    }
}

# ============================================================================
# Public Functions
# ============================================================================

<#
.SYNOPSIS
Get the Azure DevOps PAT token from environment

.DESCRIPTION
Retrieves the PAT token from environment variable, with optional decryption.
Defaults to FALCOIT_AZDO_PAT_WORKITEMSREADWRITE which is expected to be encrypted.

.PARAMETER PatToken
Optional: Provide explicit PAT token. If not provided, retrieves from environment.

.PARAMETER EnvironmentVariableName
Optional: Override the default environment variable name.

.PARAMETER Decrypt
Optional: Attempt to decrypt the token using ssEncryptDecrypt.ps1

.OUTPUTS
[string] The PAT token

.EXAMPLE
$token = Get-AzDoPatToken
$token = Get-AzDoPatToken -Decrypt
#>
function Get-AzDoPatToken {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [string]$PatToken,

        [string]$EnvironmentVariableName = 'FALCOIT_AZDO_PAT_WORKITEMSREADWRITE',

        [switch]$Decrypt
    )

    process {
        # If explicit PAT token provided, validate and return it
        if ($PSBoundParameters.ContainsKey('PatToken') -and -not [string]::IsNullOrWhiteSpace($PatToken)) {
            if ([string]::IsNullOrWhiteSpace($PatToken)) {
                Write-Error "PAT token parameter provided but is empty."
            }
            return $PatToken
        }

        # Try to get token from environment variable
        [string]$token = [Environment]::GetEnvironmentVariable($EnvironmentVariableName)
        if ([string]::IsNullOrWhiteSpace($token)) {
            Write-Error "Unable to retrieve PAT token. Environment variable '$EnvironmentVariableName' is not set or is empty."
        }

        # If Decrypt switch is provided, attempt decryption
        if ($Decrypt) {
            # Check if ssEncryptDecrypt.ps1 is available
            if (-not (Confirm-SsEncryptDecryptHelperExists)) {
                Write-Error "Cannot decrypt token: ssEncryptDecrypt.ps1 helper not found in PATH. Ensure helper scripts are available."
            }

            try {
                $token = $token | ssEncryptDecrypt.ps1 -Decrypt
            }
            catch {
                Write-Error "Failed to decrypt PAT token: $($_.Exception.Message)"
            }
        }

        # Validate token is not empty after retrieval/decryption
        if ([string]::IsNullOrWhiteSpace($token)) {
            Write-Error "PAT token is empty after retrieval. Token retrieval or decryption may have failed."
        }

        return $token
    }
}

<#
.SYNOPSIS
Create a Basic Authentication header for Azure DevOps API

.DESCRIPTION
Takes a PAT token and creates a properly formatted Basic Authentication header
for use with Azure DevOps REST API calls.

Format: Base64 encode ":{PatToken}" and create Authorization header.

.PARAMETER PatToken
The Personal Access Token to encode. If not provided, will attempt to retrieve
from environment.

.OUTPUTS
[hashtable] Hash table with 'Authorization' key containing the Basic Auth header value

.EXAMPLE
$headers = New-AzDoAuthHeader -PatToken $myToken
$headers = New-AzDoAuthHeader
#>
function New-AzDoAuthHeader {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [string]$PatToken
    )

    process {
        # If no token provided, attempt to retrieve from environment
        if ([string]::IsNullOrWhiteSpace($PatToken)) {
            $PatToken = Get-AzDoPatToken -Decrypt
        }

        # Validate token is available
        if ([string]::IsNullOrWhiteSpace($PatToken)) {
            Write-Error "Unable to create authentication header: PAT token is missing or empty."
        }

        try {
            # Azure DevOps uses Basic Auth with empty username and PAT as password
            # Format: :{PatToken} encoded in Base64
            [string]$authString = ":$PatToken"
            [byte[]]$authBytes = [System.Text.Encoding]::ASCII.GetBytes($authString)
            [string]$authBase64 = [System.Convert]::ToBase64String($authBytes)

            return @{
                'Authorization' = "Basic $authBase64"
                'Content-Type'  = 'application/json'
            }
        }
        catch {
            Write-Error "Failed to create authentication header: $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
Test Azure DevOps PAT token validity

.DESCRIPTION
Tests if the provided PAT token is valid by making a simple API call
to Azure DevOps. Requires organization parameter.

.PARAMETER Organization
The Azure DevOps organization name

.PARAMETER PatToken
Optional PAT token. If not provided, retrieves from environment.

.OUTPUTS
[bool] $true if token is valid, $false otherwise

.EXAMPLE
if (Test-AzDoPatToken -Organization "myorg") {
    Write-Host "Token is valid"
}
#>
function Test-AzDoPatToken {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [string]$PatToken
    )

    process {
        try {
            if ([string]::IsNullOrWhiteSpace($PatToken)) {
                $PatToken = Get-AzDoPatToken -Decrypt
            }

            $headers = New-AzDoAuthHeader -PatToken $PatToken
            $uri = "https://dev.azure.com/$Organization/_apis/projects?api-version=7.1-preview.3"

            $response = Invoke-WebRequest -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
            return $response.StatusCode -eq 200
        }
        catch {
            return $false
        }
    }
}
