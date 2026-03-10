<#
.SYNOPSIS
Update or remove tags on Azure DevOps work items.

.DESCRIPTION
Add, replace, or remove tags on existing work items. Supports multiple update modes:
- Add tags: Append new tags while keeping existing ones
- Replace tags: Replace all existing tags with new ones (use -Replace switch)
- Remove tags: Remove specific tags using -NotTags parameter

.PARAMETER Organization
The Azure DevOps organization name (required).

.PARAMETER Project
The Azure DevOps project name (required).

.PARAMETER WorkItemId
The work item ID to update (required).

.PARAMETER Tags
Array of tag names or semicolon-separated string to add or replace. If -Replace is set and -Tags is empty, all tags are removed.

.PARAMETER Replace
Switch parameter. When set, replaces all existing tags with the tags specified in -Tags parameter. When not set, adds tags to existing ones.

.PARAMETER NotTags
Array of specific tags to remove from work item. Keeps all other tags unchanged. Cannot be used with -Tags or -Replace together.

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW environment variable (expected to be encrypted).

.OUTPUTS
PSObject representing the updated work item with Tags field.

.EXAMPLE
Add tags to work item:
    .\UpdateAzDoWorkItemTags.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123 -Tags @("bug", "urgent")

Replace all tags:
    .\UpdateAzDoWorkItemTags.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123 -Tags @("backend", "api") -Replace

Remove specific tags:
    .\UpdateAzDoWorkItemTags.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123 -NotTags @("urgent", "temp")

Remove all tags:
    .\UpdateAzDoWorkItemTags.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123 -Replace

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read/write scope
- Tags are semicolon-separated in Azure DevOps API
- -NotTags and -Replace/-Tags are mutually exclusive
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $false)]
    [string]$Organization,

    [Parameter(Mandatory = $false)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [int]$WorkItemId,

    [Parameter(Mandatory = $false)]
    [string[]]$Tags,

    [Parameter(Mandatory = $false)]
    [switch]$Replace,

    [Parameter(Mandatory = $false)]
    [string[]]$NotTags,

    [string]$PatToken
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

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

# Import modules
. "$PSScriptRoot/AzDoAutomatorConstants.ps1"
. "$PSScriptRoot/AzDoPatTokenHelper.ps1"
. "$PSScriptRoot/AzDoApiWrapper.ps1"
. "$PSScriptRoot/AzDoWorkItemHelper.ps1"

# Validate ssLogIt.ps1 exists
if (-not (Get-Command -Name 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    & "$PSScriptRoot/ssLogIt.ps1" -Level Error -Message "Required helper script 'ssLogIt.ps1' not found in PATH."
    throw "Required helper script 'ssLogIt.ps1' not found in PATH."
}

# Validate required parameters
if (-not (Test-AzDoWorkItemIdValid $WorkItemId)) {
    & "$PSScriptRoot/ssLogIt.ps1" -Level Error -Message "Parameter 'WorkItemId' must be a positive integer."
    throw "Parameter 'WorkItemId' must be a positive integer."
}

# Mutual exclusivity checks
if ($null -ne $NotTags -and $NotTags.Count -gt 0) {
    if (($null -ne $Tags -and $Tags.Count -gt 0) -or $Replace) {
        & "$PSScriptRoot/ssLogIt.ps1" -Level Error -Message "Parameter '-NotTags' cannot be used together with '-Tags' or '-Replace'."
        throw "Parameter '-NotTags' cannot be used together with '-Tags' or '-Replace'."
    }
}

# If no Tags specified and no Replace/NotTags, this is an error
if (($null -eq $Tags -or $Tags.Count -eq 0) -and -not $Replace -and ($null -eq $NotTags -or $NotTags.Count -eq 0)) {
    & "$PSScriptRoot/ssLogIt.ps1" -Level Error -Message "Must provide either -Tags, -Replace (with or without Tags), or -NotTags."
    throw "Must provide either -Tags, -Replace (with or without Tags), or -NotTags."
}

# Determine operation mode
$mode = if ($null -ne $NotTags -and $NotTags.Count -gt 0) { 'Remove' } elseif ($Replace) { 'Replace' } else { 'Add' }

$null = & ssLogIt.ps1 -Level Info -Message "Updating tags for work item (ID: $WorkItemId) - Mode: $mode"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    try {
        $PatToken = Get-AzDoPatToken -Decrypt
    }
    catch {
        & "$PSScriptRoot/ssLogIt.ps1" -Level Error -Message "PAT token retrieval failed. Provide -PatToken or set GMD_AZDO_MACHINE_WORKITEMSRW environment variable (encrypted)."
        throw "PAT token retrieval failed. Provide -PatToken or set GMD_AZDO_MACHINE_WORKITEMSRW environment variable (encrypted)."
    }
}

try {
    # Retrieve current work item to get existing tags
    $currentWorkItem = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $WorkItemId -PatToken $PatToken

    if ($null -eq $currentWorkItem) {
        & "$PSScriptRoot/ssLogIt.ps1" -Level Error -Message "Work item with ID $WorkItemId not found."
        throw "Work item with ID $WorkItemId not found."
    }

    # Extract fields object
    $fieldsObj = $null
    try {
        if ($currentWorkItem -and $currentWorkItem.PSObject.Properties.Name -contains 'fields') {
            $fieldsObj = $currentWorkItem.fields
        }
        elseif ($currentWorkItem -is [System.Collections.IEnumerable] -and -not ($currentWorkItem -is [string])) {
            $first = $currentWorkItem | Select-Object -First 1
            if ($first -and $first.PSObject.Properties.Name -contains 'fields') {
                $fieldsObj = $first.fields
            }
        }
        else {
            if ($currentWorkItem -is [string]) {
                try {
                    $parsed = $currentWorkItem | ConvertFrom-Json -ErrorAction Stop
                    if ($parsed.PSObject.Properties.Name -contains 'fields') {
                        $fieldsObj = $parsed.fields
                    }
                }
                catch {
                    # ignore
                }
            }
        }
    }
    catch {
        # no-op
    }

    if ($null -eq $fieldsObj) {
        $null = & ssLogIt.ps1 -Level Error -Message "Unable to locate 'fields' in work item response."
        $dump = $currentWorkItem | ConvertTo-Json -Depth 3 -ErrorAction SilentlyContinue
        $null = & ssLogIt.ps1 -Level Debug -Message "Work item response: $dump"
        throw "The work item response does not contain a 'fields' element."
    }

    # Retrieve existing tags from the fields object
    [string]$currentTagsString = ''
    [string[]]$currentTags = @()

    if ($null -ne $fieldsObj) {
        try {
            if ($fieldsObj.PSObject.Properties.Name -contains $script:FIELD_SYSTEM_TAGS) {
                $currentTagsString = [string]($fieldsObj.($script:FIELD_SYSTEM_TAGS))
            }
            elseif ($fieldsObj -is [System.Collections.IDictionary] -and $fieldsObj.Contains($script:FIELD_SYSTEM_TAGS)) {
                $currentTagsString = [string]$fieldsObj[$script:FIELD_SYSTEM_TAGS]
            }
            else {
                $currentTagsString = ''
            }
        }
        catch {
            $currentTagsString = ''
        }
    }

    # Parse current tags
    if (-not [string]::IsNullOrWhiteSpace($currentTagsString)) {
        $currentTags = $currentTagsString -split ';' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    # Process tags based on mode
    [string[]]$newTags = @()

    switch ($mode) {
        'Add' {
            # Combine existing and new tags, remove duplicates
            $newTags = @($currentTags + $Tags) | Select-Object -Unique | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            $null = & ssLogIt.ps1 -Level Debug -Message "Adding $($Tags.Count) tag(s) to existing tags. New total: $($newTags.Count)"
        }
        'Replace' {
            # Replace all tags with new ones (or empty if -Tags is empty/null)
            if ($null -ne $Tags -and $Tags.Count -gt 0) {
                $newTags = $Tags | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                $null = & ssLogIt.ps1 -Level Debug -Message "Replacing all tags with $($newTags.Count) new tag(s)"
            }
            else {
                $newTags = @()
                $null = & ssLogIt.ps1 -Level Debug -Message "Removing all tags (Replace with empty list)"
            }
        }
        'Remove' {
            # Remove specified tags from current tags
            $newTags = $currentTags | Where-Object { $_ -notin $NotTags }
            $null = & ssLogIt.ps1 -Level Debug -Message "Removing $($NotTags.Count) tag(s) from existing tags. Remaining: $($newTags.Count)"
        }
    }

    # Format tags as semicolon-separated string (Azure DevOps format)
    [string]$tagsString = $newTags -join '; '

    # Manually construct JSON with proper escaping
    [string]$escapedTags = $tagsString -replace '"', '\"'
    [string]$jsonBody = '[{"op":"replace","path":"/fields/System.Tags","value":"' + $escapedTags + '"}]'

    $null = & ssLogIt.ps1 -Level Debug -Message "JSON Patch Body: $jsonBody"

    # Call API with the JSON patch
    try {
        $headers = New-AzDoAuthHeader -PatToken $PatToken
    }
    catch {
        & "$PSScriptRoot/ssLogIt.ps1" -Level Error -Message "Failed to create authentication header."
        throw "Failed to create authentication header."
    }

    $headers['Content-Type'] = 'application/json-patch+json'

    $uri = "https://dev.azure.com/$Organization/$Project/_apis/wit/workitems/$WorkItemId`?api-version=$($script:AZDO_API_VERSION)"

    $updated = Invoke-RestMethod -Method Patch -Uri $uri -Headers $headers -Body $jsonBody -ErrorAction Stop

    $null = & ssLogIt.ps1 -Level Info -Message "Successfully updated tags for work item (ID: $($updated.id))"

    return $updated
}
catch {
    $null = & ssLogIt.ps1 -Level Error -Message "Failed to update tags: $_" -Exception $_
    throw
}
