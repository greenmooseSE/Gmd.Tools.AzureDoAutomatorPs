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
[int]$script:API_TIMEOUT_SECONDS = 120
[hashtable]$script:_htmlFieldCache = @{}

# ============================================================================
# Private Helper Functions
# ============================================================================

<#
.SYNOPSIS
Returns the set of field reference names whose type is 'html' for the given org/project,
read from appSettings.json. Result is cached per org/project for the session.
#>
function Get-HtmlFieldReferenceNames {
    param([string]$Organization, [string]$Project)

    [string]$cacheKey = "$Organization/$Project"
    if ($script:_htmlFieldCache.ContainsKey($cacheKey)) {
        return $script:_htmlFieldCache[$cacheKey]
    }

    [string[]]$htmlFields = @()
    try {
        [string]$appSettingsPath = Join-Path $PSScriptRoot '../appSettings.json'
        if (-not (Test-Path $appSettingsPath)) {
            $appSettingsPath = Join-Path (Get-Location).Path 'appSettings.json'
        }
        if (Test-Path $appSettingsPath) {
            $appSettings = Get-Content -Raw $appSettingsPath | ConvertFrom-Json
            $projectFields = $appSettings.organizations.$Organization.projects.$Project.fields
            if ($null -ne $projectFields) {
                foreach ($typeName in $projectFields.PSObject.Properties.Name) {
                    $htmlFields += @($projectFields.$typeName |
                        Where-Object { $_.type -eq 'html' } |
                        Select-Object -ExpandProperty referenceName)
                }
                $htmlFields = @($htmlFields | Select-Object -Unique)
            }
        }
    } catch {
        # Fall through to empty list; field will be sent without markdown hint
    }

    $script:_htmlFieldCache[$cacheKey] = $htmlFields
    return $htmlFields
}

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

                # Extract HTTP status code and response body if available.
                # Use PSObject.Properties to avoid Set-StrictMode errors when the exception
                # type (e.g. HttpRequestException in .NET 6+) lacks a .Response property.
                [object]$exResponse = if ($_.Exception.PSObject.Properties['Response']) { $_.Exception.Response } else { $null }
                if ($null -ne $exResponse) {
                    $statusCode = [int]$exResponse.StatusCode
                    
                    try {
                        $streamReader = [System.IO.StreamReader]::new($exResponse.GetResponseStream())
                        $responseBody = $streamReader.ReadToEnd()
                        $streamReader.Close()
                    }
                    catch {
                        # Could not read response body
                    }
                }
                elseif ($_.Exception.PSObject.Properties['StatusCode'] -and $null -ne $_.Exception.StatusCode) {
                    # HttpRequestException in .NET 6+ exposes StatusCode directly
                    $statusCode = [int]$_.Exception.StatusCode
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
            throw
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

        # Multiline fields that require markdown format specification — derived from appSettings.json
        [string[]]$multilineFields = @(Get-HtmlFieldReferenceNames -Organization $Organization -Project $Project)

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

        # Multiline fields that require markdown format specification — derived from appSettings.json
        [string[]]$multilineFields = @(Get-HtmlFieldReferenceNames -Organization $Organization -Project $Project)

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

            # Add multiline format specification for markdown fields.
            # Use 'add' (not 'replace') so it works even when the format path has never been set before.
            if ($fieldName -in $multilineFields -and -not [string]::IsNullOrWhiteSpace($Fields[$fieldName])) {
                $patchOps += @{
                    op    = 'add'
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
            throw
        }
    }
}

<#
.SYNOPSIS
Move a work item to a different parent (reparent)

.DESCRIPTION
Reparent an existing work item by removing its current parent relationship and establishing a new one.
This enables moving work items between features, epics, or changing their position in the hierarchy.

Changes parent by:
1. Retrieving the current work item to find existing parent relation
2. Removing the old System.LinkTypes.Hierarchy-Reverse relation (if exists)
3. Adding a new System.LinkTypes.Hierarchy-Reverse relation to the new parent

.PARAMETER Organization
The Azure DevOps organization name

.PARAMETER Project
The project name

.PARAMETER WorkItemId
The work item ID to move

.PARAMETER NewParentId
The ID of the new parent work item

.PARAMETER PatToken
Optional PAT token. If not provided, retrieves from environment.

.OUTPUTS
Updated work item object with new parent relation

.EXAMPLE
$moved = Move-AzDoWorkItem -Organization "myorg" -Project "myproject" -WorkItemId 100 -NewParentId 50

.NOTES
- If the work item has no current parent, only a new parent link is added
- If reparenting fails at any point, an exception is thrown
#>
function Move-AzDoWorkItem {
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
        [int]$NewParentId,

        [string]$PatToken
    )

    process {
        if ([string]::IsNullOrWhiteSpace($PatToken)) {
            $PatToken = Get-AzDoPatToken -Decrypt
        }

        $headers = New-AzDoAuthHeader -PatToken $PatToken
        $headers['Content-Type'] = 'application/json-patch+json'

        $uri = "https://dev.azure.com/$Organization/$Project/_apis/wit/workitems/$WorkItemId`?api-version=7.1-preview.3"

        try {
            # Get current work item to find existing parent relation
            $currentItem = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $WorkItemId -PatToken $PatToken

            $patchOps = @()

            # Find and remove existing parent relation (System.LinkTypes.Hierarchy-Reverse)
            if ($null -ne $currentItem.relations -and $currentItem.relations.Count -gt 0) {
                $parentRelationIndex = -1
                for ($i = 0; $i -lt $currentItem.relations.Count; $i++) {
                    if ($currentItem.relations[$i].rel -eq 'System.LinkTypes.Hierarchy-Reverse') {
                        $parentRelationIndex = $i
                        break
                    }
                }

                # If parent relation found, remove it
                if ($parentRelationIndex -ge 0) {
                    $patchOps += @{
                        op   = 'remove'
                        path = "/relations/$parentRelationIndex"
                    }
                }
            }

            # Add new parent relation
            $newParentUrl = "https://dev.azure.com/$Organization/$Project/_apis/wit/workItems/$NewParentId"
            $patchOps += @{
                op    = 'add'
                path  = '/relations/-'
                value = @{
                    rel        = 'System.LinkTypes.Hierarchy-Reverse'
                    url        = $newParentUrl
                    attributes = @{
                        comment = 'linked as parent'
                    }
                }
            }

            # Apply PATCH operations
            return Invoke-AzDoApiRequest -Uri $uri -Method 'Patch' -Headers $headers -Body $patchOps
        }
        catch {
            ssLogIt.ps1 -Level Error -Message "Failed to move work item $WorkItemId to parent $NewParentId : $($_.Exception.Message)"
            throw
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
            throw
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

function Update-AzDoComment {
    <#
    .SYNOPSIS
    Update an existing comment in Azure DevOps

    .DESCRIPTION
    Updates an existing comment on a work item.
    Returns the updated comment object.

    .PARAMETER Organization
    The Azure DevOps organization name (required)

    .PARAMETER Project
    The Azure DevOps project name (required)

    .PARAMETER WorkItemId
    The work item ID containing the comment (required)

    .PARAMETER CommentId
    The ID of the comment to update (required)

    .PARAMETER Content
    The new comment content, supports markdown formatting (required)

    .PARAMETER PatToken
    Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW environment variable.

    .OUTPUTS
    PSObject representing the updated comment with all metadata

    .EXAMPLE
    $comment = Update-AzDoComment -Organization "myorg" -Project "myproj" -WorkItemId 123 -CommentId 456 -Content "Updated comment text"
    #>
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
        [int]$CommentId,

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

        # Use PATCH method with the specific preview version for updating comment content
        $uri = "https://dev.azure.com/$Organization/$Project/_apis/wit/workitems/$WorkItemId/comments/$($CommentId)?format=markdown&api-version=7.1-preview.3"

        # The comments API expects a 'text' property for the comment body
        $body = @{
            text = $Content
        }

        [string]$bodyJson = $body | ConvertTo-Json -Depth 10

        try {
            return Invoke-AzDoApiRequest -Uri $uri -Method 'Patch' -Headers $headers -Body $bodyJson
        }
        catch {
            # Surface API error details (including response body) so callers can inspect and fail visibly
            $exMsg = $_.Exception.Message
            $null = & ssLogIt.ps1 -Level Error -Message "Update-AzDoComment failed: $exMsg" -Exception $_

            # If the exception message contains a response body (added by Invoke-AzDoApiRequest), log it explicitly
            if ($exMsg -match 'ResponseBody:\s*(.+)$') {
                $responseBody = $Matches[1]
                $null = & ssLogIt.ps1 -Level Error -Message "Update-AzDoComment - API response body: $responseBody"
            }

            # Do not swallow the error or return a simulated object; rethrow to make failure visible to callers
            throw
        }
    }
}

<#
.SYNOPSIS
Get all iterations from an Azure DevOps project

.DESCRIPTION
Retrieve all iterations (sprints) from an Azure DevOps project with full details.
Iterations are already sorted by start date in ascending order.

.PARAMETER Organization
The Azure DevOps organization name

.PARAMETER Project
The project name

.PARAMETER PatToken
Optional PAT token. If not provided, retrieves from environment.

.OUTPUTS
Array of iteration objects sorted by start date ascending, or $null if no iterations exist

.EXAMPLE
$iterations = Get-AzDoIterations -Organization "myorg" -Project "myproject"
#>
function Get-AzDoIterations {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [string]$PatToken
    )

    process {
        if ([string]::IsNullOrWhiteSpace($PatToken)) {
            $PatToken = Get-AzDoPatToken -Decrypt
        }

        $headers = New-AzDoAuthHeader -PatToken $PatToken

        # Iterations API endpoint
        $uri = "https://dev.azure.com/$Organization/$Project/_apis/work/teamsettings/iterations?api-version=7.1-preview.1"

        try {
            [object]$response = Invoke-AzDoApiRequest -Uri $uri -Method 'Get' -Headers $headers
            
            if ($null -eq $response -or $null -eq $response.value) {
                return $null
            }

            [object[]]$iterations = $response.value
            
            # Sort by start date ascending
            $iterations = $iterations | Sort-Object -Property {
                if ([string]::IsNullOrWhiteSpace($_.attributes.startDate)) {
                    [datetime]::MaxValue
                }
                else {
                    [datetime]$_.attributes.startDate
                }
            }

            return $iterations
        }
        catch {
            $null = & ssLogIt.ps1 -Level Error -Message "Failed to retrieve iterations from $Project : $($_.Exception.Message)" -Exception $_
            throw
        }
    }
}

<#
.SYNOPSIS
Create a new iteration in an Azure DevOps project

.DESCRIPTION
Create a new iteration (sprint) with specified start and end dates under an optional parent path.
Parent iteration paths must already exist before creating iterations under them.

Reference: https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/classification-nodes/create-or-update?view=azure-devops-rest-7.1&tabs=HTTP

.PARAMETER Organization
The Azure DevOps organization name

.PARAMETER Project
The project name

.PARAMETER IterationName
The name of the iteration

.PARAMETER StartDate
The start date (will use today if not specified when present)

.PARAMETER EndDate
The end date (finish date)

.PARAMETER ParentPath
Optional parent path for the iteration (e.g. "GMD/2026"). If specified, the iteration is created under this parent classification node.
Default is to create at project root level. NOTE: Parent iteration paths must already exist in Azure DevOps.

.PARAMETER PatToken
Optional PAT token. If not provided, retrieves from environment.

.OUTPUTS
The created iteration object

.EXAMPLE
$newIteration = New-AzDoIteration -Organization "myorg" -Project "myproject" -IterationName "Sprint 1" -StartDate "2026-01-04" -EndDate "2026-02-03"

Create under parent path "GMD/2026":
$newIteration = New-AzDoIteration -Organization "myorg" -Project "myproject" -ParentPath "GMD/2026" -IterationName "2026-01" -StartDate "2026-01-04" -EndDate "2026-02-03"
#>
function New-AzDoIteration {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$IterationName,

        [Parameter(Mandatory = $true)]
        [datetime]$StartDate,

        [Parameter(Mandatory = $true)]
        [datetime]$EndDate,

        [Parameter(Mandatory = $false)]
        [string]$ParentPath,

        [string]$PatToken
    )

    process {
        if ([string]::IsNullOrWhiteSpace($PatToken)) {
            $PatToken = Get-AzDoPatToken -Decrypt
        }

        $headers = New-AzDoAuthHeader -PatToken $PatToken

        # Iterations API endpoint - using project-level classification nodes (not team-specific)
        # Reference: https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/classification-nodes/create-or-update?view=azure-devops-rest-7.1&tabs=HTTP
        # If ParentPath is specified, append it to the URL to create under parent node
        # ParentPath can use forward slashes (GMD/2026) which get converted to backslashes for the API
        [string]$uri = "https://dev.azure.com/$Organization/$Project/_apis/wit/classificationnodes/iterations"
        
        if (-not [string]::IsNullOrWhiteSpace($ParentPath)) {
            # Convert forward slashes to backslashes (Azure DevOps uses backslashes in paths)
            # Then URL encode the backslashes
            [string]$normalizedPath = $ParentPath -replace '/', '\'
            [string]$encodedPath = [Uri]::EscapeDataString($normalizedPath)
            $uri = "$uri/$encodedPath"
        }
        
        $uri = "$uri`?api-version=7.1-preview.2"

        $body = @{
            name       = $IterationName
            attributes = @{
                startDate  = $StartDate.ToString('o')
                finishDate = $EndDate.ToString('o')
            }
        }

        try {
            return Invoke-AzDoApiRequest -Uri $uri -Method 'Post' -Headers $headers -Body $body
        }
        catch {
            $null = & ssLogIt.ps1 -Level Error -Message "Failed to create iteration '$IterationName' in $Project : $($_.Exception.Message)" -Exception $_
            throw
        }
    }
}
