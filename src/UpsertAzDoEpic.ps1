<#
.SYNOPSIS
Create or update an Azure DevOps Epic work item

.DESCRIPTION
Unified UPSERT operation to create a new Epic or update an existing Epic in Azure DevOps.
Epics are the top-level work item type used to organize Features.

Behavior depends on provided parameters:
- If -Id is provided: Update the existing Epic by ID (no title-based lookup)
- If -Id is not provided: UPSERT by Title (update if exists, create if not)
  - If -FailIfExist is also set: Creates only if no Epic with that title exists; fails if found

Returns the created or updated Epic work item with all current fields populated.

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER Title
The Epic title (required). Used as the primary key when -Id is not provided.

.PARAMETER Id
Optional Epic ID for direct update by ID. If provided, updates the Epic by this ID without title-based lookup.
Cannot be used with -FailIfExist (these are mutually exclusive).

.PARAMETER Description
Optional description for the Epic

.PARAMETER Effort
Optional effort value for the Epic (must be a non-negative number; decimals such as 0.5 are supported)

.PARAMETER FailIfExist
Optional switch for create-only mode when not using -Id. Only applicable without -Id.
If set, fails if an Epic with the specified Title already exists (prevents accidental overwrites).
Cannot be used with -Id (these are mutually exclusive).

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
PSObject representing the created or updated Epic work item with all fields populated

.EXAMPLE
Create or update Epic by title (standard UPSERT):
    $epic = .\UpsertAzDoEpic.ps1 -Organization "myorg" -Project "myproject" -Title "Q1 Features" -Description "Updated description"

Create Epic only if title doesn't exist:
    $epic = .\UpsertAzDoEpic.ps1 -Organization "myorg" -Project "myproject" -Title "Q1 Features" -FailIfExist

Update existing Epic by ID directly:
    $updated = .\UpsertAzDoEpic.ps1 -Organization "myorg" -Project "myproject" -Id 123 -Description "New description"

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read/write scope
- Supports partial updates (only specified fields are changed)
- Title-based lookup is performed when -Id is not provided
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

    [hashtable]$Fields,

    [string]$State,

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
    Write-Error "-Id and -FailIfExist are mutually exclusive. When -Id is provided, the Epic already exists, so -FailIfExist is not applicable."
}

# Title is required for create (not provided with -Id), but optional for update (provided with -Id)
if (-not $PSBoundParameters.ContainsKey('Id') -and [string]::IsNullOrWhiteSpace($Title)) {
    Write-Error "Parameter 'Title' is required when creating a new Epic (when -Id is not provided)."
}

if ($PSBoundParameters.ContainsKey('Effort') -and $Effort -lt 0) {
    Write-Error "Parameter 'Effort' must be a non-negative number. Provided: $Effort"
}

# Validate -Fields and -State against appSettings.json config
if ($PSBoundParameters.ContainsKey('Fields') -and $null -ne $Fields) {
    Assert-FieldsNotReadOnly -Organization $Organization -Project $Project -WorkItemType $script:WORKITEM_TYPE_EPIC -Fields $Fields
}
if ($PSBoundParameters.ContainsKey('State')) {
    Assert-StateIsWritable -Organization $Organization -Project $Project -WorkItemType $script:WORKITEM_TYPE_EPIC -State $State
}

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    # Check if -Id was provided (determine create vs update)
    if ($PSBoundParameters.ContainsKey('Id')) {
        # Update or create-only mode
        $existingEpic = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $Id -PatToken $PatToken
        
        if ($null -ne $existingEpic) {
            # Epic already exists
            if ($FailIfExist) {
                $logMessage = "Epic with ID ::FgGreen::$Id::FgDefault:: already exists and -FailIfExist is set"
                $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
                Write-Error "Epic already exists (ID: $Id). Cannot create in -FailIfExist mode."
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

            if ($PSBoundParameters.ContainsKey('State')) {
                $updateFields[$script:FIELD_SYSTEM_STATE] = $State
            }

            if ($updateFields.Count -eq 0) {
                Write-Error "At least one field must be provided for update (Title, Description, Effort, State, or -Fields)."
            }

            $fieldList = @($updateFields.Keys) -join ", "
            $logMessage = "Updating existing Epic (ID: $Id) with fields: $fieldList"
            $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

            $updated = Update-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $Id -Fields $updateFields -PatToken $PatToken

            $logMessage = "Successfully updated Epic (ID: $($updated.id))"
            $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"

            return $updated
        }
        else {
            # Epic does not exist
            $logMessage = "Epic with ID ::FgGreen::$Id::FgDefault:: does not exist, cannot update."
            $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
            Write-Error "Epic with ID $Id does not exist. Cannot update non-existent Epic."
        }
    }
    else {
        # UPSERT mode - -Id not provided, search by title
        # Search for existing Epic with the same title
        $existingByTitle = & "$PSScriptRoot/FindAzDoItemByTitle.ps1" -Organization $Organization -Project $Project -Title $Title -Type $script:WORKITEM_TYPE_EPIC -PatToken $PatToken -ErrorAction SilentlyContinue
        
        if ($null -ne $existingByTitle) {
            # Epic with this title already exists
            if ($PSBoundParameters.ContainsKey('FailIfExist')) {
                # Create-only mode: fail if title already exists
                $logMessage = "Epic with title ::FgGreen::$Title::FgDefault:: already exists (ID: $($existingByTitle.id)) and -FailIfExist is set"
                $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
                Write-Error "Epic with title '$Title' already exists (ID: $($existingByTitle.id)). Cannot create in -FailIfExist mode."
            }
            
            # Update mode: update the existing Epic by ID
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

            if ($PSBoundParameters.ContainsKey('State')) {
                $updateFields[$script:FIELD_SYSTEM_STATE] = $State
            }
            
            # Note: Title is already the same, so we don't need to update it unless explicitly provided for override
            # But since we matched by title, we typically don't change it
            if ($updateFields.Count -eq 0) {
                # No fields to update, just return the existing epic
                $logMessage = "Epic with title ::FgGreen::$Title::FgDefault:: already exists (ID: $($existingByTitle.id)), no field updates provided"
                $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"
                return $existingByTitle
            }
            
            $fieldList = @($updateFields.Keys) -join ", "
            $logMessage = "Updating existing Epic by title ::FgGreen::$Title::FgDefault:: (ID: $($existingByTitle.id)) with fields: $fieldList"
            $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"
            
            $updated = Update-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $existingByTitle.id -Fields $updateFields -PatToken $PatToken
            
            $logMessage = "Successfully updated Epic (ID: $($updated.id))"
            $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"
            
            return $updated
        }
        else {
            # Epic with this title does not exist, create new one
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

            if ($PSBoundParameters.ContainsKey('State')) {
                $createFields[$script:FIELD_SYSTEM_STATE] = $State
            }

            $logMessage = "Creating new Epic with title ::FgGreen::$Title::FgDefault::"
            $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

            $newEpic = New-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemType $script:WORKITEM_TYPE_EPIC -Fields $createFields -PatToken $PatToken

            $logMessage = "Successfully created Epic ::FgGreen::$Title::FgDefault:: (ID: $($newEpic.id))"
            $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"

            return $newEpic
        }
    }
}
catch {
    [string]$errorMsg = $_.Exception.Message
    $logMessage = "Failed to upsert Epic: ::FgRed::$errorMsg::FgDefault::"
    $null = & ssLogIt.ps1 -Level Error -Message "$logMessage" -Exception $_
    Write-Error $_
    throw
}
