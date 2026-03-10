<#
.SYNOPSIS
Remove a comment from an Azure DevOps work item


.DESCRIPTION
Deletes a comment by ID from a given work item or deletes comment(s) whose
latest text matches a provided regular expression using the Azure DevOps
comments API.

.PARAMETER Organization
Azure DevOps organization name (required)

.PARAMETER Project
Azure DevOps project name (required)

.PARAMETER WorkItemId
Work item ID that contains the comment (required)

.PARAMETER CommentId
ID of the comment to delete (required when not using TextMatchRegex)

.PARAMETER TextMatchRegex
Regular expression used to match the latest comment text. If supplied,
comments whose latest text matches this regex will be deleted. Use
escaped anchors if you need exact matches.

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW environment variable.

.OUTPUTS
Boolean - $true if deletion succeeded

.EXAMPLE
.\RemoveAzDoComment.ps1 -Organization myorg -Project myproj -WorkItemId 123 -CommentId 456

.EXAMPLE
# Remove comments whose latest text exactly equals "Obsolete note"
.\RemoveAzDoComment.ps1 -Organization myorg -Project myproj -WorkItemId 123 -TextMatchRegex "^Obsolete note$"
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $false)]
    [string]$Organization,

    [Parameter(Mandatory = $false)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [int]$WorkItemId,

    [int]$CommentId,

    [string]$TextMatchRegex,

    [string]$PatToken
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Import modules
. "$PSScriptRoot/AzDoAutomatorConstants.ps1"
. "$PSScriptRoot/AzDoPatTokenHelper.ps1"
. "$PSScriptRoot/AzDoApiWrapper.ps1"
. "$PSScriptRoot/AzDoWorkItemHelper.ps1"

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

if (-not (Test-AzDoWorkItemIdValid $WorkItemId)) {
    Write-Error "Parameter 'WorkItemId' must be a positive integer."
}

 

$null = & ssLogIt.ps1 -Level Info -Message "Removing comment $CommentId from work item ID: ::FgGreen::$WorkItemId::FgDefault::"

if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

    try {
        $headers = New-AzDoAuthHeader -PatToken $PatToken
        $headers['Content-Type'] = 'application/json'

        # If TextMatchRegex is supplied, find comment(s) whose latest text matches the regex
        if (-not [string]::IsNullOrWhiteSpace($TextMatchRegex)) {
            $null = & ssLogIt.ps1 -Level Debug -Message "Searching comments for matching regex"
            # Validate regex early
            try { $null = [regex]::new($TextMatchRegex) } catch { throw "Invalid regular expression in TextMatchRegex: $($_.Exception.Message)" }
            $commentsUri = "https://dev.azure.com/$Organization/$Project/_apis/wit/workitems/$($WorkItemId)/comments?api-version=7.1-preview.3"
            $commentsResponse = Invoke-AzDoApiRequest -Uri $commentsUri -Method 'Get' -Headers $headers

            if ($null -eq $commentsResponse) {
                $null = & ssLogIt.ps1 -Level Error -Message "No comments found for work item $WorkItemId"
                throw [System.InvalidOperationException]"No comments found for work item $WorkItemId"
            }

            # Normalize list: API may return an object with 'value' or an array directly
            if ($commentsResponse -is [array]) {
                $items = $commentsResponse
            }
            else {
                # Try common property names or any array-valued property
                if ($commentsResponse.PSObject.Properties.Name -contains 'value') { $items = $commentsResponse.value }
                elseif ($commentsResponse.PSObject.Properties.Name -contains 'comments') { $items = $commentsResponse.comments }
                else {
                    foreach ($p in $commentsResponse.PSObject.Properties) {
                        if ($p.Value -is [array]) { $items = $p.Value; break }
                    }
                }
            }

            if (-not $items) {
                $null = & ssLogIt.ps1 -Level Error -Message "No comments present for work item $WorkItemId"
                throw [System.InvalidOperationException]"No comments present for work item $WorkItemId"
            }

            # Keep only latest version per comment id
            $latest = @{}
            foreach ($c in $items) {
                $id = $c.id
                if (-not $latest.ContainsKey($id) -or $latest[$id].version -lt $c.version) {
                    $latest[$id] = $c
                }
            }

            $localMatches = New-Object System.Collections.Generic.List[object]
            foreach ($pair in $latest.GetEnumerator()) {
                $c = $pair.Value
                $bodyText = $null
                if ($null -ne $c.text) { $bodyText = $c.text }
                elseif ($null -ne $c.content) { $bodyText = $c.content }
                elseif ($null -ne $c.body) { $bodyText = $c.body }

                # Normalize body to a string before regex matching to avoid
                # errors when the API returns structured content (objects/arrays)
                if ($null -eq $bodyText) { $textStr = '' }
                elseif ($bodyText -is [string]) { $textStr = $bodyText }
                else { $textStr = $bodyText | ConvertTo-Json -Depth 10 }

                if ($textStr -match $TextMatchRegex) { $null = $localMatches.Add([int]$c.id) }
            }

            if ($localMatches.Count -eq 0) {
                $null = & ssLogIt.ps1 -Level Info -Message "No comment matched regex: $TextMatchRegex"
                return $false
            }

            # Delete each matched comment id (deletes full comment resource including edits)
            foreach ($matchId in $localMatches) {
                $uri = "https://dev.azure.com/$Organization/$Project/_apis/wit/workitems/$($WorkItemId)/comments/$($matchId)?api-version=7.1-preview.3"
                $null = & ssLogIt.ps1 -Level Debug -Message "Deleting comment $matchId via $uri"
                Invoke-AzDoApiRequest -Uri $uri -Method 'Delete' -Headers $headers -Body $null
                $null = & ssLogIt.ps1 -Level Info -Message "Deleted comment $matchId"
            }

            return $true
        }

        # Otherwise delete by explicit CommentId
        if ($CommentId -le 0) { throw "Either CommentId or TextMatchRegex must be supplied" }

        $uri = "https://dev.azure.com/$Organization/$Project/_apis/wit/workitems/$($WorkItemId)/comments/$($CommentId)?api-version=7.1-preview.3"

        $null = & ssLogIt.ps1 -Level Debug -Message "Sending DELETE $uri"

        Invoke-AzDoApiRequest -Uri $uri -Method 'Delete' -Headers $headers -Body $null

        $null = & ssLogIt.ps1 -Level Info -Message "Comment $CommentId removed from work item $WorkItemId"

        return $true
    }
    catch {
        $null = & ssLogIt.ps1 -Level Error -Message "Failed to remove comment $($CommentId): $($_.Exception.Message)" -Exception $_
        throw
    }
