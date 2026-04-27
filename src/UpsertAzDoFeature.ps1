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
Optional effort value for the Feature (must be a non-negative number; decimals such as 0.5 are supported)

.PARAMETER Priority
Optional priority for the Feature (1-4, where 1 is highest priority)

.PARAMETER OriginalEstimate
Optional original estimate in hours (non-negative number) for time tracking

.PARAMETER FixedIn
Optional text field indicating the version or build where this Feature was fixed/completed

.PARAMETER DeployedToDev
Optional boolean indicating whether the Feature has been deployed to the Dev environment

.PARAMETER DeployedToStaging
Optional boolean indicating whether the Feature has been deployed to the Staging environment

.PARAMETER DeployedToProduction
Optional boolean indicating whether the Feature has been deployed to the Production environment

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

    [double]$Effort,

    [int]$Priority,

    [double]$OriginalEstimate,

    [string]$FixedIn,

    [bool]$DeployedToDev,

    [bool]$DeployedToStaging,

    [bool]$DeployedToProduction,

    [int]$ParentEpicId,

    [hashtable]$Fields,

    [string]$State,

    [string]$AssignedTo,

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
. "$PSScriptRoot/ValidateUpsertFields.ps1"

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
    Write-Error "Parameter 'Effort' must be a non-negative number. Provided: $Effort"
}

if ($PSBoundParameters.ContainsKey('Priority') -and ($Priority -lt 1 -or $Priority -gt 4)) {
    Write-Error "Parameter 'Priority' must be between 1 and 4 (1=highest). Provided: $Priority"
}

if ($PSBoundParameters.ContainsKey('OriginalEstimate') -and $OriginalEstimate -lt 0) {
    Write-Error "Parameter 'OriginalEstimate' must be a non-negative number. Provided: $OriginalEstimate"
}

# Validate -Fields and -State against appSettings.json config
if ($PSBoundParameters.ContainsKey('Fields') -and $null -ne $Fields) {
    Assert-FieldsNotReadOnly -Organization $Organization -Project $Project -WorkItemType $script:WORKITEM_TYPE_FEATURE -Fields $Fields
}
if ($PSBoundParameters.ContainsKey('State')) {
    Assert-StateIsWritable -Organization $Organization -Project $Project -WorkItemType $script:WORKITEM_TYPE_FEATURE -State $State
}

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

# Resolve -AssignedTo email to identity before any API call
[object]$resolvedIdentity = $null
if ($PSBoundParameters.ContainsKey('AssignedTo') -and -not [string]::IsNullOrWhiteSpace($AssignedTo)) {
    $resolvedIdentity = & "$PSScriptRoot/ResolveAzDoIdentity.ps1" -Organization $Organization -Email $AssignedTo -PatToken $PatToken
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

            # Merge -Fields first; explicit params below take precedence
            if ($PSBoundParameters.ContainsKey('Fields') -and $null -ne $Fields) {
                foreach ($k in $Fields.Keys) { $updateFields[$k] = $Fields[$k] }
            }

            if ($PSBoundParameters.ContainsKey('Title')) {
                $updateFields[$script:FIELD_SYSTEM_TITLE] = $Title
            }

            if ($PSBoundParameters.ContainsKey('Description')) {
                $updateFields[$script:FIELD_DESCRIPTION] = $Description
            }

            if ($PSBoundParameters.ContainsKey('Effort')) {
                $updateFields[$script:FIELD_EFFORT] = $Effort
            }

            if ($PSBoundParameters.ContainsKey('Priority')) {
                $updateFields[$script:FIELD_PRIORITY] = $Priority
            }

            if ($PSBoundParameters.ContainsKey('OriginalEstimate')) {
                $updateFields[$script:FIELD_ORIGINAL_ESTIMATE] = $OriginalEstimate
            }

            if ($PSBoundParameters.ContainsKey('FixedIn')) {
                $updateFields[$script:FIELD_FIXED_IN] = $FixedIn
            }

            if ($PSBoundParameters.ContainsKey('DeployedToDev')) {
                $updateFields[$script:FIELD_DEPLOYED_TO_DEV] = $DeployedToDev
            }

            if ($PSBoundParameters.ContainsKey('DeployedToStaging')) {
                $updateFields[$script:FIELD_DEPLOYED_TO_STAGING] = $DeployedToStaging
            }

            if ($PSBoundParameters.ContainsKey('DeployedToProduction')) {
                $updateFields[$script:FIELD_DEPLOYED_TO_PRODUCTION] = $DeployedToProduction
            }

            if ($PSBoundParameters.ContainsKey('State')) {
                $updateFields[$script:FIELD_SYSTEM_STATE] = $State
            }

            if ($null -ne $resolvedIdentity) {
                $updateFields[$script:FIELD_SYSTEM_ASSIGNED_TO] = @{ uniqueName = $resolvedIdentity.UniqueName; displayName = $resolvedIdentity.DisplayName }
            }

            if ($updateFields.Count -eq 0) {
                Write-Error "At least one field must be provided for update (Title, Description, Effort, Priority, OriginalEstimate, FixedIn, DeployedToDev, DeployedToStaging, DeployedToProduction, State, AssignedTo, or -Fields)."
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

            # Merge -Fields first; explicit params below take precedence
            if ($PSBoundParameters.ContainsKey('Fields') -and $null -ne $Fields) {
                foreach ($k in $Fields.Keys) { $updateFields[$k] = $Fields[$k] }
            }

            if ($PSBoundParameters.ContainsKey('Description')) {
                $updateFields[$script:FIELD_DESCRIPTION] = $Description
            }

            if ($PSBoundParameters.ContainsKey('Effort')) {
                $updateFields[$script:FIELD_EFFORT] = $Effort
            }

            if ($PSBoundParameters.ContainsKey('Priority')) {
                $updateFields[$script:FIELD_PRIORITY] = $Priority
            }

            if ($PSBoundParameters.ContainsKey('OriginalEstimate')) {
                $updateFields[$script:FIELD_ORIGINAL_ESTIMATE] = $OriginalEstimate
            }

            if ($PSBoundParameters.ContainsKey('FixedIn')) {
                $updateFields[$script:FIELD_FIXED_IN] = $FixedIn
            }

            if ($PSBoundParameters.ContainsKey('DeployedToDev')) {
                $updateFields[$script:FIELD_DEPLOYED_TO_DEV] = $DeployedToDev
            }

            if ($PSBoundParameters.ContainsKey('DeployedToStaging')) {
                $updateFields[$script:FIELD_DEPLOYED_TO_STAGING] = $DeployedToStaging
            }

            if ($PSBoundParameters.ContainsKey('DeployedToProduction')) {
                $updateFields[$script:FIELD_DEPLOYED_TO_PRODUCTION] = $DeployedToProduction
            }

            if ($PSBoundParameters.ContainsKey('State')) {
                $updateFields[$script:FIELD_SYSTEM_STATE] = $State
            }

            if ($null -ne $resolvedIdentity) {
                $updateFields[$script:FIELD_SYSTEM_ASSIGNED_TO] = @{ uniqueName = $resolvedIdentity.UniqueName; displayName = $resolvedIdentity.DisplayName }
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

            # Merge -Fields first; explicit params below take precedence
            if ($PSBoundParameters.ContainsKey('Fields') -and $null -ne $Fields) {
                foreach ($k in $Fields.Keys) { $createFields[$k] = $Fields[$k] }
            }

            if ($PSBoundParameters.ContainsKey('Description')) {
                $createFields[$script:FIELD_DESCRIPTION] = $Description
            }

            if ($PSBoundParameters.ContainsKey('Effort')) {
                $createFields[$script:FIELD_EFFORT] = $Effort
            }

            if ($PSBoundParameters.ContainsKey('Priority')) {
                $createFields[$script:FIELD_PRIORITY] = $Priority
            }

            if ($PSBoundParameters.ContainsKey('OriginalEstimate')) {
                $createFields[$script:FIELD_ORIGINAL_ESTIMATE] = $OriginalEstimate
            }

            if ($PSBoundParameters.ContainsKey('FixedIn')) {
                $createFields[$script:FIELD_FIXED_IN] = $FixedIn
            }

            if ($PSBoundParameters.ContainsKey('DeployedToDev')) {
                $createFields[$script:FIELD_DEPLOYED_TO_DEV] = $DeployedToDev
            }

            if ($PSBoundParameters.ContainsKey('DeployedToStaging')) {
                $createFields[$script:FIELD_DEPLOYED_TO_STAGING] = $DeployedToStaging
            }

            if ($PSBoundParameters.ContainsKey('DeployedToProduction')) {
                $createFields[$script:FIELD_DEPLOYED_TO_PRODUCTION] = $DeployedToProduction
            }

            if ($PSBoundParameters.ContainsKey('State')) {
                $createFields[$script:FIELD_SYSTEM_STATE] = $State
            }

            if ($null -ne $resolvedIdentity) {
                $createFields[$script:FIELD_SYSTEM_ASSIGNED_TO] = @{ uniqueName = $resolvedIdentity.UniqueName; displayName = $resolvedIdentity.DisplayName }
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
