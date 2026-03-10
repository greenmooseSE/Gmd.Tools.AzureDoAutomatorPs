<#
.SYNOPSIS
Create or update an Azure DevOps Bug work item

.DESCRIPTION
Unified UPSERT operation to create a new Bug or update an existing Bug in Azure DevOps.
Bugs represent defects or issues that need to be fixed.

Behavior depends on provided parameters:
- If -Id is provided: Update the existing Bug by ID (no title-based lookup)
- If -Id is not provided: UPSERT by Title (update if exists, create if not)
  - If -FailIfExist is also set: Creates only if no Bug with that title exists; fails if found

Returns the created or updated Bug work item with all current fields populated.

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER Title
The Bug title (required when creating or upserting by title). Used as the primary key when -Id is not provided.

.PARAMETER Id
Optional Bug ID for direct update by ID. If provided, updates the Bug by this ID without title-based lookup.
Cannot be used with -FailIfExist (these are mutually exclusive).

.PARAMETER Description
Optional description for the Bug

.PARAMETER Priority
Optional Priority for the Bug (1-4, where 1 is highest priority)

.PARAMETER ReproSteps
Optional reproduction steps for the Bug (description of how to reproduce)

.PARAMETER SystemInfo
Optional system information where the Bug was found

.PARAMETER StoryPoints
Optional story points for the Bug (effort estimation)

.PARAMETER FoundInBuild
Optional build where the Bug was found

.PARAMETER IntegratedInBuild
Optional build where the Bug was fixed/integrated

.PARAMETER ParentStoryId
Optional parent Story work item ID. If provided, the Bug will be created as a child of this Story (for create operations only).

.PARAMETER FailIfExist
Optional switch for create-only mode when not using -Id. Only applicable without -Id.
If set, fails if a Bug with the specified Title already exists (prevents accidental overwrites).
Cannot be used with -Id (these are mutually exclusive).

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
PSObject representing the created or updated Bug work item with all fields populated

.EXAMPLE
Create or update Bug by title (standard UPSERT):
    $bug = .\UpsertAzDoBug.ps1 -Organization "myorg" -Project "myproject" -Title "Login form crashes" -Priority 1 -ReproSteps "Click login button"

Create Bug only if title doesn't exist:
    $bug = .\UpsertAzDoBug.ps1 -Organization "myorg" -Project "myproject" -Title "Login fails" -FailIfExist -Priority 2

Create Bug under a Story with full metadata:
    $bug = .\UpsertAzDoBug.ps1 -Organization "myorg" -Project "myproject" -Title "Database timeout" -ParentStoryId 42 -Priority 1 `
        -ReproSteps "Run query on large dataset" -SystemInfo "Windows 10" -FoundInBuild "20.1" -StoryPoints 3

Update existing Bug by ID directly:
    $updated = .\UpsertAzDoBug.ps1 -Organization "myorg" -Project "myproject" -Id 123 -IntegratedInBuild "20.2"

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read/write scope
- Supports partial updates (only specified fields are changed)
- Title-based lookup is performed when -Id is not provided
- ParentStoryId is only used when creating new Bugs
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

    [int]$Priority,

    [string]$ReproSteps,

    [string]$SystemInfo,

    [double]$StoryPoints,

    [string]$FoundInBuild,

    [string]$IntegratedInBuild,

    [int]$ParentStoryId,

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
    Write-Error "-Id and -FailIfExist are mutually exclusive. When -Id is provided, the Bug already exists, so -FailIfExist is not applicable."
}

# Title is required for create (not provided with -Id), but optional for update (provided with -Id)
if (-not $PSBoundParameters.ContainsKey('Id') -and [string]::IsNullOrWhiteSpace($Title)) {
    Write-Error "Parameter 'Title' is required when creating a new Bug (when -Id is not provided)."
}

if ($PSBoundParameters.ContainsKey('Priority') -and ($Priority -lt 1 -or $Priority -gt 4)) {
    Write-Error "Parameter 'Priority' must be between 1 and 4 (1=highest). Provided: $Priority"
}

if ($PSBoundParameters.ContainsKey('StoryPoints') -and $StoryPoints -lt 0) {
    Write-Error "Parameter 'StoryPoints' must be a non-negative number. Provided: $StoryPoints"
}

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    # Check if -Id was provided (determine create vs update)
    if ($PSBoundParameters.ContainsKey('Id')) {
        # Update mode - update by ID directly without title-based lookup
        $existingBug = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $Id -PatToken $PatToken

        if ($null -ne $existingBug) {
            # Bug already exists
            if ($FailIfExist) {
                $logMessage = "Bug with ID ::FgGreen::$Id::FgDefault:: already exists and -FailIfExist is set"
                $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
                Write-Error "Bug already exists (ID: $Id). Cannot create in -FailIfExist mode."
            }

            # Update mode - update only provided fields
            $updateFields = @{}

            if ($PSBoundParameters.ContainsKey('Title')) {
                $updateFields[$script:FIELD_SYSTEM_TITLE] = $Title
            }

            if ($PSBoundParameters.ContainsKey('Description')) {
                $updateFields[$script:FIELD_DESCRIPTION] = $Description
            }

            if ($PSBoundParameters.ContainsKey('Priority')) {
                $updateFields[$script:FIELD_PRIORITY] = $Priority
            }

            if ($PSBoundParameters.ContainsKey('ReproSteps')) {
                $updateFields[$script:FIELD_REPRO_STEPS] = $ReproSteps
            }

            if ($PSBoundParameters.ContainsKey('SystemInfo')) {
                $updateFields[$script:FIELD_SYSTEM_INFO] = $SystemInfo
            }

            if ($PSBoundParameters.ContainsKey('StoryPoints')) {
                $updateFields[$script:FIELD_STORY_POINTS] = $StoryPoints
            }

            if ($PSBoundParameters.ContainsKey('FoundInBuild')) {
                $updateFields[$script:FIELD_FOUND_IN_BUILD] = $FoundInBuild
            }

            if ($PSBoundParameters.ContainsKey('IntegratedInBuild')) {
                $updateFields[$script:FIELD_INTEGRATED_IN_BUILD] = $IntegratedInBuild
            }

            if ($updateFields.Count -eq 0) {
                Write-Error "At least one field must be provided for update (Title, Description, Priority, ReproSteps, SystemInfo, StoryPoints, FoundInBuild, or IntegratedInBuild)."
            }

            $fieldList = @($updateFields.Keys) -join ", "
            $logMessage = "Updating existing Bug (ID: $Id) with fields: $fieldList"
            $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

            $updated = Update-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $Id -Fields $updateFields -PatToken $PatToken

            $logMessage = "Successfully updated Bug (ID: $($updated.id))"
            $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"

            return $updated
        }
        else {
            # Bug does not exist
            $logMessage = "Bug with ID ::FgGreen::$Id::FgDefault:: does not exist, cannot update."
            $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
            Write-Error "Bug with ID $Id does not exist. Cannot update non-existent Bug."
        }
    }
    else {
        # UPSERT mode - -Id not provided, search by title
        # Search for existing Bug with the same title
        $existingByTitle = & "$PSScriptRoot/FindAzDoItemByTitle.ps1" -Organization $Organization -Project $Project -Title $Title -Type $script:WORKITEM_TYPE_BUG -PatToken $PatToken -ErrorAction SilentlyContinue

        if ($null -ne $existingByTitle) {
            # Bug with this title already exists
            if ($PSBoundParameters.ContainsKey('FailIfExist')) {
                # Create-only mode: fail if title already exists
                $logMessage = "Bug with title ::FgGreen::$Title::FgDefault:: already exists (ID: $($existingByTitle.id)) and -FailIfExist is set"
                $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
                Write-Error "Bug with title '$Title' already exists (ID: $($existingByTitle.id)). Cannot create in -FailIfExist mode."
            }

            # Update mode: update the existing Bug by ID
            $updateFields = @{}

            if ($PSBoundParameters.ContainsKey('Description')) {
                $updateFields[$script:FIELD_DESCRIPTION] = $Description
            }

            if ($PSBoundParameters.ContainsKey('Priority')) {
                $updateFields[$script:FIELD_PRIORITY] = $Priority
            }

            if ($PSBoundParameters.ContainsKey('ReproSteps')) {
                $updateFields[$script:FIELD_REPRO_STEPS] = $ReproSteps
            }

            if ($PSBoundParameters.ContainsKey('SystemInfo')) {
                $updateFields[$script:FIELD_SYSTEM_INFO] = $SystemInfo
            }

            if ($PSBoundParameters.ContainsKey('StoryPoints')) {
                $updateFields[$script:FIELD_STORY_POINTS] = $StoryPoints
            }

            if ($PSBoundParameters.ContainsKey('FoundInBuild')) {
                $updateFields[$script:FIELD_FOUND_IN_BUILD] = $FoundInBuild
            }

            if ($PSBoundParameters.ContainsKey('IntegratedInBuild')) {
                $updateFields[$script:FIELD_INTEGRATED_IN_BUILD] = $IntegratedInBuild
            }

            # Note: Title is already the same, so we don't need to update it unless explicitly provided for override
            if ($updateFields.Count -eq 0) {
                # No fields to update, just return the existing bug
                $logMessage = "Bug with title ::FgGreen::$Title::FgDefault:: already exists (ID: $($existingByTitle.id)), no field updates provided"
                $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"
                return $existingByTitle
            }

            $fieldList = @($updateFields.Keys) -join ", "
            $logMessage = "Updating existing Bug by title ::FgGreen::$Title::FgDefault:: (ID: $($existingByTitle.id)) with fields: $fieldList"
            $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

            $updated = Update-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $existingByTitle.id -Fields $updateFields -PatToken $PatToken

            $logMessage = "Successfully updated Bug (ID: $($updated.id))"
            $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"

            return $updated
        }
        else {
            # Bug with this title does not exist, create new one
            $createFields = @{
                $script:FIELD_SYSTEM_TITLE = $Title
            }

            if ($PSBoundParameters.ContainsKey('Description')) {
                $createFields[$script:FIELD_DESCRIPTION] = $Description
            }

            if ($PSBoundParameters.ContainsKey('Priority')) {
                $createFields[$script:FIELD_PRIORITY] = $Priority
            }

            if ($PSBoundParameters.ContainsKey('ReproSteps')) {
                $createFields[$script:FIELD_REPRO_STEPS] = $ReproSteps
            }

            if ($PSBoundParameters.ContainsKey('SystemInfo')) {
                $createFields[$script:FIELD_SYSTEM_INFO] = $SystemInfo
            }

            if ($PSBoundParameters.ContainsKey('StoryPoints')) {
                $createFields[$script:FIELD_STORY_POINTS] = $StoryPoints
            }

            if ($PSBoundParameters.ContainsKey('FoundInBuild')) {
                $createFields[$script:FIELD_FOUND_IN_BUILD] = $FoundInBuild
            }

            if ($PSBoundParameters.ContainsKey('IntegratedInBuild')) {
                $createFields[$script:FIELD_INTEGRATED_IN_BUILD] = $IntegratedInBuild
            }

            # Validate parent Story if specified
            if ($PSBoundParameters.ContainsKey('ParentStoryId')) {
                try {
                    $parentStory = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $ParentStoryId -PatToken $PatToken
                    if ($null -eq $parentStory) {
                        Write-Error "Parent Story with ID $ParentStoryId not found."
                    }

                    $logMessage = "Creating Bug as child of Story (ID: $ParentStoryId)"
                    $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"
                }
                catch {
                    Write-Error "Failed to validate parent Story with ID $ParentStoryId : $($_.Exception.Message)"
                }
            }

            $logMessage = "Creating new Bug with title ::FgGreen::$Title::FgDefault::"
            $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

            $createParams = @{
                Organization = $Organization
                Project      = $Project
                WorkItemType = $script:WORKITEM_TYPE_BUG
                Fields       = $createFields
                PatToken     = $PatToken
            }

            if ($PSBoundParameters.ContainsKey('ParentStoryId')) {
                $createParams['ParentId'] = $ParentStoryId
            }

            $newBug = New-AzDoWorkItem @createParams

            $logMessage = "Successfully created Bug ::FgGreen::$Title::FgDefault:: (ID: $($newBug.id))"
            $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"

            return $newBug
        }
    }
}
catch {
    [string]$errorMsg = $_.Exception.Message
    $logMessage = "Failed to create/update Bug: ::FgRed::$errorMsg::FgDefault::"
    $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
    throw
}
