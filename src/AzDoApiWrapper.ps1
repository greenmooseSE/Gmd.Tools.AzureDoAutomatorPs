<#
.SYNOPSIS
Azure DevOps REST API Wrapper Module

.DESCRIPTION
Provides functions to invoke Azure DevOps REST API endpoints with proper authentication,
error handling, retry logic, and logging. Uses ssLogIt.ps1 for all output messages.

.NOTES
Requires AzDoAutomatorConstants.ps1 and AzDoPatTokenHelper.ps1 to be dot-sourced first.
All API calls include retry logic for transient failures.
#>

#Requires -Version 7.0

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# ============================================================================
# Private Configuration
# ============================================================================

[int]$script:RETRY_MAX_ATTEMPTS = 3
[int]$script:RETRY_DELAY_MS = 1000
[int]$script:API_TIMEOUT_SECONDS = 30

# ============================================================================
# Private Helper Functions
# ============================================================================

<#
.SYNOPSIS
Execute a REST API call with retry logic and error handling

.DESCRIPTION
Internal function that handles all REST API calls to Azure DevOps.
Implements retry logic for transient failures and comprehensive error handling.
#>
function Invoke-AzDoApiRequest {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [string]$Method = 'Get',

        [hashtable]$Headers,

        [object]$Body,

        [string]$ContentType = 'application/json'
    )

    process {
        [int]$attempt = 0
        [object]$response = $null

        while ($attempt -lt $script:RETRY_MAX_ATTEMPTS) {
            $attempt++
            try {
                $invokeParams = @{
                    Uri         = $Uri
                    Method      = $Method
                    Headers     = $Headers
                    TimeoutSec  = $script:API_TIMEOUT_SECONDS
                    ErrorAction = 'Stop'
                }
                
                # Only set ContentType separately if it's not already in headers
                if (-not $Headers.ContainsKey('Content-Type') -and -not [string]::IsNullOrWhiteSpace($ContentType)) {
                    $invokeParams['ContentType'] = $ContentType
                }

                if ($Method -in @('Post', 'Patch') -and $null -ne $Body) {
                    if ($Body -is [string]) {
                        $invokeParams['Body'] = $Body
                    }
                    else {
                        # Ensure we send proper JSON array format for PATCH operations
                        if ($Body -is [array]) {
                            # Already an array - convert to JSON, ensuring array format is preserved
                            [string]$json = $Body | ConvertTo-Json -Depth 10 -ErrorAction Stop
                            # ConvertTo-Json unwraps single-element arrays, so force-wrap if needed
                            if (-not $json.TrimStart().StartsWith('[')) {
                                $json = "[$json]"
                            }
                            $invokeParams['Body'] = $json
                        }
                        else {
                            # Single item - wrap in array to ensure [ ...]format
                            $invokeParams['Body'] = @($Body) | ConvertTo-Json -Depth 10 -ErrorAction Stop
                        }
                    }
                    $null = & ssLogIt.ps1 -Level Debug -Message "Request body: $($invokeParams['Body'])"
                }

                $response = Invoke-RestMethod @invokeParams

                # Log successful API call with debug level
                $logMessage = "Azure DevOps API call successful: $Method $Uri"
                $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

                return $response
            }
            catch {
                [string]$errorMessage = $_.Exception.Message
                [int]$statusCode = 0
                [string]$responseBody = ""

                # Extract HTTP status code and response body if available
                if ($_.Exception.Response) {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                    
                    try {
                        $streamReader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
                        $responseBody = $streamReader.ReadToEnd()
                        $streamReader.Close()
                    }
                    catch {
                        # Could not read response body
                    }
                }

                # Determine if error is transient (retry-able)
                [bool]$isTransient = $statusCode -in @(429, 500, 502, 503, 504) -or
                                     $errorMessage -like '*timeout*' -or
                                     $errorMessage -like '*connection*'

                if ($isTransient -and $attempt -lt $script:RETRY_MAX_ATTEMPTS) {
                    [int]$delayMs = $script:RETRY_DELAY_MS * $attempt
                    $logMessage = "Transient error on attempt $attempt/$script:RETRY_MAX_ATTEMPTS (HTTP $statusCode). Retrying in $($delayMs)ms..."
                    $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"
                    Start-Sleep -Milliseconds $delayMs
                    continue
                }

                # Non-transient error or max retries exceeded
                $logMessage = "Azure DevOps API call failed: $Method $Uri (HTTP $statusCode)"
                $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
                
                # Log response body for debugging 400/401/403 errors
                if ($statusCode -in @(400, 401, 403)) {
                    if ($responseBody) {
                        $null = & ssLogIt.ps1 -Level Error -Message "Response body: $responseBody"
                    } else {
                        $null = & ssLogIt.ps1 -Level Error -Message "Response body: (empty)"
                    }
                }

                # Try to parse structured error response
                if ([string]::IsNullOrWhiteSpace($responseBody) -eq $false) {
                    try {
                        $errorDetails = $responseBody | ConvertFrom-Json -ErrorAction SilentlyContinue
                        $parsedMessage = $errorDetails.message -or $errorDetails.error.message -or $errorDetails.Message
                        if ($parsedMessage) {
                            $errorMessage = $parsedMessage
                        }
                    }
                    catch {
                        # Couldn't parse error response, use original message
                    }
                }

                ssLogIt.ps1 -Level Error -Message "Azure DevOps API request failed ($Method $Uri): $errorMessage" -Exception $_;

                # Include response body and status code in the thrown exception so callers can inspect it
                $detailedMessage = $errorMessage
                if ($statusCode -ne 0) { $detailedMessage = "$detailedMessage (HTTP $statusCode)" }
                if (-not [string]::IsNullOrWhiteSpace($responseBody)) { $detailedMessage = "$detailedMessage`nResponseBody: $responseBody" }

                throw (New-Object System.Exception($detailedMessage))
            }
        }

        # Should not reach here
        throw "Azure DevOps API request failed after $script:RETRY_MAX_ATTEMPTS attempts: $Uri"
    }
}

# ============================================================================
# Public API Functions
# ============================================================================

<#
.SYNOPSIS
Query work items from Azure DevOps using WIQL

.DESCRIPTION
Execute a WIQL (Work Item Query Language) query against Azure DevOps.

.PARAMETER Organization
The Azure DevOps organization name

.PARAMETER Project
The project name

.PARAMETER Query
The WIQL query string

.PARAMETER PatToken
Optional PAT token. If not provided, retrieves from environment.

.OUTPUTS
Array of work item objects

.EXAMPLE
$workItems = Invoke-AzDoWiql -Organization "myorg" -Project "myproject" -Query "SELECT [System.Id], [System.Title] FROM WorkItems WHERE [System.Title] = 'MyFeature'"
#>
function Invoke-AzDoWiql {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$Query,

        [string]$PatToken
    )

    process {
        if ([string]::IsNullOrWhiteSpace($PatToken)) {
            $PatToken = Get-AzDoPatToken -Decrypt
        }

        $headers = New-AzDoAuthHeader -PatToken $PatToken

        $uri = "https://dev.azure.com/$Organization/$Project/_apis/wit/wiql?api-version=7.1"

        $body = @{
            query = $Query
        }

        try {
            # Try direct HTTP call first to capture 404s without full error logging
            $invokeParams = @{
                Uri         = $uri
                Method      = 'Post'
                Headers     = $headers
                TimeoutSec  = 30
                ErrorAction = 'Stop'
                ContentType = 'application/json'
                Body        = $body | ConvertTo-Json -Depth 10
            }
            
            $result = Invoke-RestMethod @invokeParams

            if ($result.workItems) {
                return $result.workItems
            }

            return @()
        }
        catch [System.Net.Http.HttpRequestException] {
            # Check if it's a 404 (endpoint not available - known limitation)
            if ($_.Exception.Response.StatusCode -eq 'NotFound') {
                $null = & ssLogIt.ps1 -Level Debug -Message "WIQL endpoint not available (404) - child work items query will return empty"
                return @()
            }
            
            # For other HTTP errors, log and re-throw
            Write-Error "Failed to execute WIQL query: $($_.Exception.Message)"
        }
        catch {
            # Catch other exceptions (like timeouts) and re-throw
            Write-Error "Failed to execute WIQL query: $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
Get a single work item by ID

.DESCRIPTION
Retrieve detailed information about a specific work item.

.PARAMETER Organization
The Azure DevOps organization name

.PARAMETER Project
The project name

.PARAMETER WorkItemId
The work item ID

.PARAMETER PatToken
Optional PAT token. If not provided, retrieves from environment.

.OUTPUTS
Work item object with all fields

.EXAMPLE
$workItem = Get-AzDoWorkItemById -Organization "myorg" -Project "myproject" -WorkItemId 123
#>
function Get-AzDoWorkItemById {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [int]$WorkItemId,

        [string]$PatToken
    )

    process {
        if ([string]::IsNullOrWhiteSpace($PatToken)) {
            $PatToken = Get-AzDoPatToken -Decrypt
        }

        $headers = New-AzDoAuthHeader -PatToken $PatToken

        $uri = "https://dev.azure.com/$Organization/$Project/_apis/wit/workitems/$WorkItemId`?api-version=7.1-preview.3&`$expand=all"

        try {
            return Invoke-AzDoApiRequest -Uri $uri -Method 'Get' -Headers $headers
        }
        catch {
            Write-Error "Failed to retrieve work item $WorkItemId : $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
Create a new work item

.DESCRIPTION
Create a new work item in Azure DevOps with specified fields.

.PARAMETER Organization
The Azure DevOps organization name

.PARAMETER Project
The project name

.PARAMETER WorkItemType
The work item type (Feature, Story, Task, etc.)

.PARAMETER Fields
Hashtable of field names and values

.PARAMETER PatToken
Optional PAT token. If not provided, retrieves from environment.

.OUTPUTS
Created work item object

.EXAMPLE
$fields = @{
    'System.Title' = 'New Feature'
    'System.Description' = 'Feature description'
}
$newItem = New-AzDoWorkItem -Organization "myorg" -Project "myproject" -WorkItemType "Feature" -Fields $fields
#>
function New-AzDoWorkItem {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$WorkItemType,

        [Parameter(Mandatory = $true)]
        [hashtable]$Fields,

        [int]$ParentId,

        [string]$PatToken
    )

    process {
        if ([string]::IsNullOrWhiteSpace($PatToken)) {
            $PatToken = Get-AzDoPatToken -Decrypt
        }

        $headers = New-AzDoAuthHeader -PatToken $PatToken
        $headers['Content-Type'] = 'application/json-patch+json'

        # Per Azure DevOps REST API 7.1: POST /workitems/$Type format (OData style)
        # Use string concatenation to produce literal $VariableName in URL
        $uri = "https://dev.azure.com/$Organization/$Project/_apis/wit/workitems/`$" + $WorkItemType + "?api-version=7.1"

        # Multiline fields that require markdown format specification
        [string[]]$multilineFields = @(
            'System.Description',
            'Microsoft.VSTS.Common.AcceptanceCriteria',
            'Custom.ACScenarios',
            'Custom.ExtraInformation'
        )

        # Build PATCH operations for fields
        $patchOps = @()
        foreach ($fieldName in $Fields.Keys) {
            # Skip System.Parent field - we handle parent via relations instead
            if ($fieldName -eq 'System.Parent') {
                continue
            }
            $patchOps += @{
                op    = 'add'
                path  = "/fields/$fieldName"
                value = $Fields[$fieldName]
            }

            # Add multiline format specification for markdown fields
            if ($fieldName -in $multilineFields -and -not [string]::IsNullOrWhiteSpace($Fields[$fieldName])) {
                $patchOps += @{
                    op    = 'add'
                    path  = "/multilineFieldsFormat/$fieldName"
                    value = 'Markdown'
                }
            }
        }

        # Handle parent relationship if ParentId is provided
        if ($PSBoundParameters.ContainsKey('ParentId') -and $ParentId -gt 0) {
            $parentUrl = "https://dev.azure.com/$Organization/$Project/_apis/wit/workItems/$ParentId"
            $patchOps += @{
                op    = 'add'
                path  = '/relations/-'
                value = @{
                    rel        = 'System.LinkTypes.Hierarchy-Reverse'
                    url        = $parentUrl
                    attributes = @{
                        comment = 'linked as parent'
                    }
                }
            }
        }

        try {
            return Invoke-AzDoApiRequest -Uri $uri -Method 'Post' -Headers $headers -Body $patchOps
        }
        catch {
            ssLogIt.ps1 -Level Error -Message "Failed to create work item of type '$WorkItemType': $($_.Exception.Message)"
            throw;
        }
    }
}

<#
.SYNOPSIS
Update an existing work item

.DESCRIPTION
Update specific fields of an existing work item using PATCH operations.

.PARAMETER Organization
The Azure DevOps organization name

.PARAMETER Project
The project name

.PARAMETER WorkItemId
The work item ID to update

.PARAMETER Fields
Hashtable of field names and values to update

.PARAMETER PatToken
Optional PAT token. If not provided, retrieves from environment.

.OUTPUTS
Updated work item object

.EXAMPLE
$updates = @{
    'System.Title' = 'Updated Title'
    'System.State' = 'Active'
}
$updated = Update-AzDoWorkItem -Organization "myorg" -Project "myproject" -WorkItemId 123 -Fields $updates
#>
function Update-AzDoWorkItem {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [int]$WorkItemId,

        [Parameter(Mandatory = $true)]
        [hashtable]$Fields,

        [string]$PatToken
    )

    process {
        if ([string]::IsNullOrWhiteSpace($PatToken)) {
            $PatToken = Get-AzDoPatToken -Decrypt
        }

        $headers = New-AzDoAuthHeader -PatToken $PatToken
        $headers['Content-Type'] = 'application/json-patch+json'

        $uri = "https://dev.azure.com/$Organization/$Project/_apis/wit/workitems/$WorkItemId`?api-version=7.1-preview.3"

        # Multiline fields that require markdown format specification
        [string[]]$multilineFields = @(
            'System.Description',
            'Microsoft.VSTS.Common.AcceptanceCriteria',
            'Custom.ACScenarios',
            'Custom.ExtraInformation'
        )

        # Build PATCH operations for fields
        $patchOps = @()
        foreach ($fieldName in $Fields.Keys) {
            # Skip System.Parent field - parent relationships should be managed via relations
            if ($fieldName -eq 'System.Parent') {
                continue
            }
            $patchOps += @{
                op    = 'replace'
                path  = "/fields/$fieldName"
                value = $Fields[$fieldName]
            }

            # Add multiline format specification for markdown fields
            if ($fieldName -in $multilineFields -and -not [string]::IsNullOrWhiteSpace($Fields[$fieldName])) {
                $patchOps += @{
                    op    = 'replace'
                    path  = "/multilineFieldsFormat/$fieldName"
                    value = 'Markdown'
                }
            }
        }

        try {
            return Invoke-AzDoApiRequest -Uri $uri -Method 'Patch' -Headers $headers -Body $patchOps
        }
        catch {
            Write-Error "Failed to update work item $WorkItemId : $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
Delete a work item

.DESCRIPTION
Delete an existing work item from Azure DevOps.

.PARAMETER Organization
The Azure DevOps organization name

.PARAMETER Project
The project name

.PARAMETER WorkItemId
The work item ID to delete

.PARAMETER PatToken
Optional PAT token. If not provided, retrieves from environment.

.EXAMPLE
Remove-AzDoWorkItem -Organization "myorg" -Project "myproject" -WorkItemId 123
#>
function Remove-AzDoWorkItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [int]$WorkItemId,

        [string]$PatToken
    )

    process {
        if ([string]::IsNullOrWhiteSpace($PatToken)) {
            $PatToken = Get-AzDoPatToken -Decrypt
        }

        $headers = New-AzDoAuthHeader -PatToken $PatToken

        $uri = "https://dev.azure.com/$Organization/$Project/_apis/wit/workitems/$WorkItemId`?api-version=7.1-preview.3"

        try {
            $null = Invoke-WebRequest -Uri $uri -Method 'Delete' -Headers $headers -TimeoutSec $script:API_TIMEOUT_SECONDS
            $logMessage = "Deleted work item $WorkItemId"
            $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"
        }
        catch {
            Write-Error "Failed to delete work item $WorkItemId : $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
Add a comment to an existing work item

.DESCRIPTION
Add a new comment to a work item in Azure DevOps. Comments support markdown formatting.

.PARAMETER Organization
The Azure DevOps organization name

.PARAMETER Project
The project name

.PARAMETER WorkItemId
The work item ID to add comment to

.PARAMETER Content
The comment content (supports markdown)

.PARAMETER PatToken
Optional PAT token. If not provided, retrieves from environment.

.OUTPUTS
Comment object with metadata

.EXAMPLE
$comment = New-AzDoComment -Organization "myorg" -Project "myproject" -WorkItemId 123 -Content "This is a comment"
#>
function New-AzDoComment {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [int]$WorkItemId,

        [Parameter(Mandatory = $true)]
        [string]$Content,

        [string]$PatToken
    )

    process {
        if ([string]::IsNullOrWhiteSpace($PatToken)) {
            $PatToken = Get-AzDoPatToken -Decrypt
        }

        $headers = New-AzDoAuthHeader -PatToken $PatToken
        $headers['Content-Type'] = 'application/json'

        # Use the specific preview version with comment create support
        $uri = "https://dev.azure.com/$Organization/$Project/_apis/wit/workitems/$WorkItemId/comments?format=markdown&api-version=7.1-preview.4"

        # The comments API expects a 'text' property for the comment body
        $body = @{
            text = $Content
        }

        # Convert to JSON string to prevent array wrapping by Invoke-AzDoApiRequest
        # The comments API expects {"content":"..."} not [{"content":"..."}]
        [string]$bodyJson = $body | ConvertTo-Json -Depth 10

        try {
            return Invoke-AzDoApiRequest -Uri $uri -Method 'Post' -Headers $headers -Body $bodyJson
        }
        catch {
            # Surface API error details (including response body) so callers can inspect and fail visibly
            $exMsg = $_.Exception.Message
            $null = & ssLogIt.ps1 -Level Error -Message "New-AzDoComment failed: $exMsg" -Exception $_

            # If the exception message contains a response body (added by Invoke-AzDoApiRequest), log it explicitly
            if ($exMsg -match 'ResponseBody:\s*(.+)$') {
                $responseBody = $Matches[1]
                $null = & ssLogIt.ps1 -Level Error -Message "New-AzDoComment - API response body: $responseBody"
            }

            # Do not swallow the error or return a simulated object; rethrow to make failure visible to callers
            throw
        }
    }
}
