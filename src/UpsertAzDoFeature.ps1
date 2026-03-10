<#
.SYNOPSIS
Create or update an Azure DevOps Feature work item

.DESCRIPTION
Unified UPSERT operation to create a new Feature or update an existing Feature in Azure DevOps.
Features are work items used to organize User Stories and Tasks.

Behavior depends on provided parameters:
- If -Id is provided: Update the existing Feature by ID (no title-based lookup)
- If -Id is not provided: UPSERT by Title (update if exists, create if not)
  - If -FailIfExist is also set: Creates only if no Feature with that title exists; fails if found

Returns the created or updated Feature work item with all current fields populated.

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER Title
The Feature title (required). Used as the primary key when -Id is not provided.

.PARAMETER Id
Optional Feature ID for direct update by ID. If provided, updates the Feature by this ID without title-based lookup.
Cannot be used with -FailIfExist (these are mutually exclusive).

.PARAMETER Description
Optional description for the Feature

.PARAMETER Effort
Optional effort value for the Feature (must be a non-negative integer)

.PARAMETER ParentEpicId
Optional parent Epic work item ID. If provided, the Feature will be created as a child of this Epic (for create operations only).

.PARAMETER FailIfExist
Optional switch for create-only mode when not using -Id. Only applicable without -Id.
If set, fails if a Feature with the specified Title already exists (prevents accidental overwrites).
Cannot be used with -Id (these are mutually exclusive).

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
PSObject representing the created or updated Feature work item with all fields populated

.EXAMPLE
Create or update Feature by title (standard UPSERT):
    $feature = .\UpsertAzDoFeature.ps1 -Organization "myorg" -Project "myproject" -Title "User Authentication" -Description "Updated description"

Create Feature only if title doesn't exist:
    $feature = .\UpsertAzDoFeature.ps1 -Organization "myorg" -Project "myproject" -Title "User Authentication" -FailIfExist

Create Feature under an Epic:
    $feature = .\UpsertAzDoFeature.ps1 -Organization "myorg" -Project "myproject" -Title "API Integration" -ParentEpicId 42

Update existing Feature by ID directly:
    $updated = .\UpsertAzDoFeature.ps1 -Organization "myorg" -Project "myproject" -Id 123 -Description "New description"

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read/write scope
- Supports partial updates (only specified fields are changed)
- Title-based lookup is performed when -Id is not provided
- ParentEpicId is only used when creating new Features
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $false)]
    [string]$Organization,

    [Parameter(Mandatory = $false)]
    [string]$Project,

    [string]$Title,

    [int]$Id,

    [string]$Description,

    [int]$Effort,

    [int]$ParentEpicId,

    [switch]$FailIfExist,

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
    Write-Error "Required helper script 'ssLogIt.ps1' not found in PATH. Ensure helper scripts are available."
}

# Validate required parameters
if ([string]::IsNullOrWhiteSpace($Organization)) {
    Write-Error "Parameter 'Organization' cannot be empty."
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    Write-Error "Parameter 'Project' cannot be empty."
}

# Validate mutually exclusive parameters
if ($PSBoundParameters.ContainsKey('Id') -and $PSBoundParameters.ContainsKey('FailIfExist')) {
    Write-Error "-Id and -FailIfExist are mutually exclusive. When -Id is provided, the Feature already exists, so -FailIfExist is not applicable."
}

# Title is required for create (not provided with -Id), but optional for update (provided with -Id)
if (-not $PSBoundParameters.ContainsKey('Id') -and [string]::IsNullOrWhiteSpace($Title)) {
    Write-Error "Parameter 'Title' is required when creating a new Feature (when -Id is not provided)."
}

if ($PSBoundParameters.ContainsKey('Effort') -and $Effort -lt 0) {
    Write-Error "Parameter 'Effort' must be a non-negative integer. Provided: $Effort"
}

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    # Check if -Id was provided (determine create vs update)
    if ($PSBoundParameters.ContainsKey('Id')) {
        # Update mode - update by ID directly without title-based lookup
        $existingFeature = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $Id -PatToken $PatToken

        if ($null -ne $existingFeature) {
            # Feature already exists
            if ($FailIfExist) {
                $logMessage = "Feature with ID ::FgGreen::$Id::FgDefault:: already exists and -FailIfExist is set"
                $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
                Write-Error "Feature already exists (ID: $Id). Cannot create in -FailIfExist mode."
            }

            # Update mode - update only provided fields
            $updateFields = @{}

            if ($PSBoundParameters.ContainsKey('Title')) {
                $updateFields[$script:FIELD_SYSTEM_TITLE] = $Title
            }

            if ($PSBoundParameters.ContainsKey('Description')) {
                $updateFields[$script:FIELD_DESCRIPTION] = $Description
            }

            if ($PSBoundParameters.ContainsKey('Effort')) {
                $updateFields[$script:FIELD_EFFORT] = $Effort
            }

            if ($updateFields.Count -eq 0) {
                Write-Error "At least one field must be provided for update (Title, Description, or Effort)."
            }

            $fieldList = @($updateFields.Keys) -join ", "
            $logMessage = "Updating existing Feature (ID: $Id) with fields: $fieldList"
            $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

            $updated = Update-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $Id -Fields $updateFields -PatToken $PatToken

            $logMessage = "Successfully updated Feature (ID: $($updated.id))"
            $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"

            return $updated
        }
        else {
            # Feature does not exist
            $logMessage = "Feature with ID ::FgGreen::$Id::FgDefault:: does not exist, cannot update."
            $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
            Write-Error "Feature with ID $Id does not exist. Cannot update non-existent Feature."
        }
    }
    else {
        # UPSERT mode - -Id not provided, search by title
        # Search for existing Feature with the same title
        $existingByTitle = & "$PSScriptRoot/FindAzDoItemByTitle.ps1" -Organization $Organization -Project $Project -Title $Title -Type $script:WORKITEM_TYPE_FEATURE -PatToken $PatToken -ErrorAction SilentlyContinue

        if ($null -ne $existingByTitle) {
            # Feature with this title already exists
            if ($PSBoundParameters.ContainsKey('FailIfExist')) {
                # Create-only mode: fail if title already exists
                $logMessage = "Feature with title ::FgGreen::$Title::FgDefault:: already exists (ID: $($existingByTitle.id)) and -FailIfExist is set"
                $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
                Write-Error "Feature with title '$Title' already exists (ID: $($existingByTitle.id)). Cannot create in -FailIfExist mode."
            }

            # Update mode: update the existing Feature by ID
            $updateFields = @{}

            if ($PSBoundParameters.ContainsKey('Description')) {
                $updateFields[$script:FIELD_DESCRIPTION] = $Description
            }

            if ($PSBoundParameters.ContainsKey('Effort')) {
                $updateFields[$script:FIELD_EFFORT] = $Effort
            }

            # Note: Title is already the same, so we don't need to update it unless explicitly provided for override
            # But since we matched by title, we typically don't change it
            if ($updateFields.Count -eq 0) {
                # No fields to update, just return the existing feature
                $logMessage = "Feature with title ::FgGreen::$Title::FgDefault:: already exists (ID: $($existingByTitle.id)), no field updates provided"
                $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"
                return $existingByTitle
            }

            $fieldList = @($updateFields.Keys) -join ", "
            $logMessage = "Updating existing Feature by title ::FgGreen::$Title::FgDefault:: (ID: $($existingByTitle.id)) with fields: $fieldList"
            $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

            $updated = Update-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $existingByTitle.id -Fields $updateFields -PatToken $PatToken

            $logMessage = "Successfully updated Feature (ID: $($updated.id))"
            $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"

            return $updated
        }
        else {
            # Feature with this title does not exist, create new one
            $createFields = @{
                $script:FIELD_SYSTEM_TITLE = $Title
            }

            if ($PSBoundParameters.ContainsKey('Description')) {
                $createFields[$script:FIELD_DESCRIPTION] = $Description
            }

            if ($PSBoundParameters.ContainsKey('Effort')) {
                $createFields[$script:FIELD_EFFORT] = $Effort
            }

            # Validate parent Epic if specified
            if ($PSBoundParameters.ContainsKey('ParentEpicId')) {
                try {
                    $parentEpic = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $ParentEpicId -PatToken $PatToken
                    if ($null -eq $parentEpic) {
                        Write-Error "Parent Epic with ID $ParentEpicId not found."
                    }

                    $logMessage = "Creating Feature as child of Epic (ID: $ParentEpicId)"
                    $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"
                }
                catch {
                    Write-Error "Failed to validate parent Epic with ID $ParentEpicId : $($_.Exception.Message)"
                }
            }

            $logMessage = "Creating new Feature with title ::FgGreen::$Title::FgDefault::"
            $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

            $createParams = @{
                Organization = $Organization
                Project      = $Project
                WorkItemType = $script:WORKITEM_TYPE_FEATURE
                Fields       = $createFields
                PatToken     = $PatToken
            }

            if ($PSBoundParameters.ContainsKey('ParentEpicId')) {
                $createParams['ParentId'] = $ParentEpicId
            }

            $newFeature = New-AzDoWorkItem @createParams

            $logMessage = "Successfully created Feature ::FgGreen::$Title::FgDefault:: (ID: $($newFeature.id))"
            $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"

            return $newFeature
        }
    }
}
catch {
    [string]$errorMsg = $_.Exception.Message
    $logMessage = "Failed to create/update Feature: ::FgRed::$errorMsg::FgDefault::"
    $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
    throw
}
