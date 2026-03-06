<#
.SYNOPSIS
Manage tags on Azure DevOps work items

.DESCRIPTION
Add, replace, or remove tags on existing work items. Supports three modes:
- Add: Add new tags to existing tags (union)
- Replace: Replace all tags with new ones
- Remove: Remove specified tags from work item

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER WorkItemId
The work item ID to update (required)

.PARAMETER Tags
Array of tags to add/replace/remove (required)

.PARAMETER Mode
Tag operation mode: 'Add', 'Replace', or 'Remove' (default: 'Replace')

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
PSObject representing the updated work item

.EXAMPLE
Replace all tags:
    $updated = .\Set-AzDoWorkItemTags.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123 -Tags @("urgent", "api")

Add tags to existing:
    $updated = .\Set-AzDoWorkItemTags.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123 -Tags @("frontend") -Mode Add

Remove specific tags:
    $updated = .\Set-AzDoWorkItemTags.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123 -Tags @("urgent") -Mode Remove

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read/write scope
- Tags are space-separated in Azure DevOps
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [int]$WorkItemId,

    [Parameter(Mandatory = $true)]
    [string[]]$Tags,

    [ValidateSet('Add', 'Replace', 'Remove')]
    [string]$Mode = 'Replace',

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
    & "$PSScriptRoot/ssLogIt.ps1" -Level Error -Message "Required helper script 'ssLogIt.ps1' not found in PATH."
    throw "Required helper script 'ssLogIt.ps1' not found in PATH."
}

# Validate required parameters
if (-not (Test-AzDoWorkItemIdValid $WorkItemId)) {
    & "$PSScriptRoot/ssLogIt.ps1" -Level Error -Message "Parameter 'WorkItemId' must be a positive integer."
    throw "Parameter 'WorkItemId' must be a positive integer."
}

if ($null -eq $Tags -or $Tags.Count -eq 0) {
    & "$PSScriptRoot/ssLogIt.ps1" -Level Error -Message "Parameter 'Tags' cannot be empty."
    throw "Parameter 'Tags' cannot be empty."
}

if ($Mode -notIn $script:VALID_TAG_MODES) {
    & "$PSScriptRoot/ssLogIt.ps1" -Level Error -Message "Parameter 'Mode' must be one of: $($script:VALID_TAG_MODES -join ', '). Provided: $Mode"
    throw "Parameter 'Mode' must be one of: $($script:VALID_TAG_MODES -join ', '). Provided: $Mode"
}

$null = & ssLogIt.ps1 -Level Info -Message "Updating tags for work item (ID: $WorkItemId) - Mode: $Mode"

# Get PAT token if not provided (provide clearer error when retrieval/decryption fails)
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    try {
        $PatToken = Get-AzDoPatToken -Decrypt
    }
    catch {
        & "$PSScriptRoot/ssLogIt.ps1" -Level Error -Message "PAT token retrieval failed. Provide -PatToken or set GMD_AZDO_MACHINE_WORKITEMSRW environment variable (encrypted) or set `$pat variable in session."
        throw "PAT token retrieval failed. Provide -PatToken or set GMD_AZDO_MACHINE_WORKITEMSRW environment variable (encrypted) or set `$pat variable in session."
    }
}

try {
    # Retrieve current work item to get existing tags
    $currentWorkItem = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $WorkItemId -PatToken $PatToken

    if ($null -eq $currentWorkItem) {
        & "$PSScriptRoot/ssLogIt.ps1" -Level Error -Message "Work item with ID $WorkItemId not found."
        throw "Work item with ID $WorkItemId not found."
    }

    # Attempt to locate fields object in several possible response shapes
    $fieldsObj = $null
    try {
        if ($currentWorkItem -and $currentWorkItem.PSObject -and $currentWorkItem.PSObject.Properties.Name -contains 'fields') {
            $fieldsObj = $currentWorkItem.fields
        }
        elseif ($currentWorkItem -is [System.Collections.IEnumerable] -and -not ($currentWorkItem -is [string])) {
            # If an array or collection was returned, try first element
            $first = $currentWorkItem | Select-Object -First 1
            if ($first -and $first.PSObject.Properties.Name -contains 'fields') {
                $fieldsObj = $first.fields
            }
        }
        else {
            # Try to parse as JSON string if necessary
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
        # no-op, will handle below
    }

    if ($null -eq $fieldsObj) {
        $null = & ssLogIt.ps1 -Level Error -Message "Unable to locate 'fields' in work item response. Dumping response for debugging."
        $dump = $currentWorkItem | ConvertTo-Json -Depth 3 -ErrorAction SilentlyContinue
        $null = & ssLogIt.ps1 -Level Debug -Message "Work item response: $dump"
        & "$PSScriptRoot/ssLogIt.ps1" -Level Error -Message "The work item response does not contain a 'fields' element. See debug log for full response."
        throw "The work item response does not contain a 'fields' element. See debug log for full response."
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

    # Parse current tags - handle null/empty case
    if (-not [string]::IsNullOrWhiteSpace($currentTagsString)) {
        $currentTags = $currentTagsString -split ';' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    # Process tags based on mode
    [string[]]$newTags = @()

    switch ($Mode) {
        'Add' {
            # Combine existing and new tags, remove duplicates
            $newTags = @($currentTags + $Tags) | Select-Object -Unique | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            $null = & ssLogIt.ps1 -Level Debug -Message "Adding $($Tags.Count) tag(s) to existing tags"
        }
        'Replace' {
            # Simply use the new tags
            $newTags = $Tags | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            $null = & ssLogIt.ps1 -Level Debug -Message "Replacing all tags with $($Tags.Count) new tag(s)"
        }
        'Remove' {
            # Remove specified tags from current tags
            $newTags = $currentTags | Where-Object { $_ -notin $Tags }
            $null = & ssLogIt.ps1 -Level Debug -Message "Removing $($Tags.Count) tag(s) from existing tags"
        }
    }

    # Format tags as semicolon-separated string (Azure DevOps format)
    [string]$tagsString = $newTags -join '; '

    # Manually construct JSON with proper escaping to handle special characters in tags
    # This is critical because ConvertTo-Json may not properly escape quotes and other special chars
    [string]$escapedTags = $tagsString -replace '"', '\"'
    [string]$jsonBody = '[{"op":"replace","path":"/fields/System.Tags","value":"' + $escapedTags + '"}]'


    $null = & ssLogIt.ps1 -Level Debug -Message "JSON Patch Body: $jsonBody"

    # Call API directly with the JSON string
    try {
        $headers = New-AzDoAuthHeader -PatToken $PatToken
    }
    catch {
        & "$PSScriptRoot/ssLogIt.ps1" -Level Error -Message "Failed to create authentication header. Provide -PatToken or set GMD_AZDO_MACHINE_WORKITEMSRW environment variable or set `$pat in session."
        throw "Failed to create authentication header. Provide -PatToken or set GMD_AZDO_MACHINE_WORKITEMSRW environment variable or set `$pat in session."
    }

    $headers['Content-Type'] = 'application/json-patch+json'

    $uri = "https://dev.azure.com/$Organization/$Project/_apis/wit/workitems/$WorkItemId`?api-version=$($script:AZDO_API_VERSION)"

    $updated = Invoke-RestMethod -Method Patch -Uri $uri -Headers $headers -Body $jsonBody -ErrorAction Stop

    $null = & ssLogIt.ps1 -Level Info -Message "Successfully updated tags for work item (ID: $($updated.id))"

    return $updated
}
catch {
    $null = & ssLogIt.ps1 -Level Error -Message "Failed to update tags: $_" -Exception $_
    & "$PSScriptRoot/ssLogIt.ps1" -Level Error -Message ("$($_)")
    throw
}
