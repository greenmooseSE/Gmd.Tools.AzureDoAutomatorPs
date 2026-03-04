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
Optional PAT token for authentication. If not provided, retrieves from FALCOIT_AZDO_PAT_WORKITEMSREADWRITE
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
    Write-Error "Required helper script 'ssLogIt.ps1' not found in PATH."
}

# Validate required parameters
if (-not (Test-AzDoWorkItemIdValid $WorkItemId)) {
    Write-Error "Parameter 'WorkItemId' must be a positive integer."
}

if ($null -eq $Tags -or $Tags.Count -eq 0) {
    Write-Error "Parameter 'Tags' cannot be empty."
}

if ($Mode -notIn $script:VALID_TAG_MODES) {
    Write-Error "Parameter 'Mode' must be one of: $($script:VALID_TAG_MODES -join ', '). Provided: $Mode"
}

$null = & ssLogIt.ps1 -Level Info -Message "Updating tags for work item (ID: $WorkItemId) - Mode: $Mode"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    # Retrieve current work item to get existing tags
    $currentWorkItem = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $WorkItemId -PatToken $PatToken

    if ($null -eq $currentWorkItem) {
        Write-Error "Work item with ID $WorkItemId not found."
    }

    [string]$currentTagsString = $currentWorkItem.fields.($script:FIELD_SYSTEM_TAGS)
    [string[]]$currentTags = @()

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

    $updateFields = @{
        $script:FIELD_SYSTEM_TAGS = $tagsString
    }

    $updated = Update-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $WorkItemId -Fields $updateFields -PatToken $PatToken

    $null = & ssLogIt.ps1 -Level Info -Message "Successfully updated tags for work item (ID: $($updated.id))"

    return $updated
}
catch {
    $null = & ssLogIt.ps1 -Level Error -Message "Failed to update tags: $_" -Exception $_
    Write-Error $_
    throw
}
