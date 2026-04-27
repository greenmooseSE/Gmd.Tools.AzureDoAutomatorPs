<#
.SYNOPSIS
Create or update an Azure DevOps Task work item

.DESCRIPTION
Unified UPSERT operation to create a new Task or update an existing Task in Azure DevOps.
Tasks are leaf-level work items used to track individual work within a User Story.

Behavior depends on provided parameters:
- If -Id is provided: Update the existing Task by ID (no title-based lookup)
- If -Id is not provided: UPSERT by Title (update if exists, create if not)
  - If -FailIfExist is also set: Creates only if no Task with that title exists; fails if found

Returns the created or updated Task work item with all current fields populated.

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER Title
The Task title (required when creating or upserting by title). Used as the primary key when -Id is not provided.

.PARAMETER Id
Optional Task ID for direct update by ID. If provided, updates the Task by this ID without title-based lookup.
Cannot be used with -FailIfExist (these are mutually exclusive).

.PARAMETER Description
Optional description for the Task

.PARAMETER Priority
Optional Priority for the Task (1-4, where 1 is highest priority)

.PARAMETER OriginalEstimate
Optional Original Estimate (in hours, non-negative number) for time tracking

.PARAMETER RemainingWork
Optional Remaining Work (in hours, non-negative number) for progress tracking

.PARAMETER CompletedWork
Optional Completed Work (in hours, non-negative number) for progress tracking

.PARAMETER State
Optional state for the Task (e.g., "To Do", "In Progress", "Done")

.PARAMETER ParentStoryId
Optional parent Story work item ID. If provided, the Task will be created as a child of this Story (for create operations only).

.PARAMETER FailIfExist
Optional switch for create-only mode when not using -Id. Only applicable without -Id.
If set, fails if a Task with the specified Title already exists (prevents accidental overwrites).
Cannot be used with -Id (these are mutually exclusive).

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
PSObject representing the created or updated Task work item with all fields populated

.EXAMPLE
Create or update Task by title (standard UPSERT):
    $task = .\UpsertAzDoTask.ps1 -Organization "myorg" -Project "myproject" -Title "Implement login form" -Description "Updated description"

Create Task only if title doesn't exist:
    $task = .\UpsertAzDoTask.ps1 -Organization "myorg" -Project "myproject" -Title "Implement login form" -FailIfExist

Create Task under a Story with time tracking:
    $task = .\UpsertAzDoTask.ps1 -Organization "myorg" -Project "myproject" -Title "Unit tests" -ParentStoryId 42 -Priority 2 -OriginalEstimate 8 -RemainingWork 8

Update existing Task by ID directly:
    $updated = .\UpsertAzDoTask.ps1 -Organization "myorg" -Project "myproject" -Id 123 -State "In Progress" -RemainingWork 4

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read/write scope
- Supports partial updates (only specified fields are changed)
- Title-based lookup is performed when -Id is not provided
- ParentStoryId is only used when creating new Tasks
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

    [double]$OriginalEstimate,

    [double]$RemainingWork,

    [double]$CompletedWork,

    [string]$State,

    [int]$ParentStoryId,

    [hashtable]$Fields,

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
    Write-Error "-Id and -FailIfExist are mutually exclusive. When -Id is provided, the Task already exists, so -FailIfExist is not applicable."
}

# Title is required for create (not provided with -Id), but optional for update (provided with -Id)
if (-not $PSBoundParameters.ContainsKey('Id') -and [string]::IsNullOrWhiteSpace($Title)) {
    Write-Error "Parameter 'Title' is required when creating a new Task (when -Id is not provided)."
}

if ($PSBoundParameters.ContainsKey('Priority') -and ($Priority -lt 1 -or $Priority -gt 4)) {
    Write-Error "Parameter 'Priority' must be between 1 and 4 (1=highest). Provided: $Priority"
}

if ($PSBoundParameters.ContainsKey('OriginalEstimate') -and $OriginalEstimate -lt 0) {
    Write-Error "Parameter 'OriginalEstimate' must be a non-negative number. Provided: $OriginalEstimate"
}

if ($PSBoundParameters.ContainsKey('RemainingWork') -and $RemainingWork -lt 0) {
    Write-Error "Parameter 'RemainingWork' must be a non-negative number. Provided: $RemainingWork"
}

if ($PSBoundParameters.ContainsKey('CompletedWork') -and $CompletedWork -lt 0) {
    Write-Error "Parameter 'CompletedWork' must be a non-negative number. Provided: $CompletedWork"
}

# Validate -Fields and -State against appSettings.json config
if ($PSBoundParameters.ContainsKey('Fields') -and $null -ne $Fields) {
    Assert-FieldsNotReadOnly -Organization $Organization -Project $Project -WorkItemType $script:WORKITEM_TYPE_TASK -Fields $Fields
}
if ($PSBoundParameters.ContainsKey('State')) {
    Assert-StateIsWritable -Organization $Organization -Project $Project -WorkItemType $script:WORKITEM_TYPE_TASK -State $State
}

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    # Check if -Id was provided (determine create vs update)
    if ($PSBoundParameters.ContainsKey('Id')) {
        # Update mode - update by ID directly without title-based lookup
        $existingTask = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $Id -PatToken $PatToken

        if ($null -ne $existingTask) {
            # Task already exists
            if ($FailIfExist) {
                $logMessage = "Task with ID ::FgGreen::$Id::FgDefault:: already exists and -FailIfExist is set"
                $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
                Write-Error "Task already exists (ID: $Id). Cannot create in -FailIfExist mode."
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

            if ($PSBoundParameters.ContainsKey('Priority')) {
                $updateFields[$script:FIELD_PRIORITY] = $Priority
            }

            if ($PSBoundParameters.ContainsKey('OriginalEstimate')) {
                $updateFields[$script:FIELD_ORIGINAL_ESTIMATE] = $OriginalEstimate
            }

            if ($PSBoundParameters.ContainsKey('RemainingWork')) {
                $updateFields[$script:FIELD_REMAINING_WORK] = $RemainingWork
            }

            if ($PSBoundParameters.ContainsKey('CompletedWork')) {
                $updateFields[$script:FIELD_COMPLETED_WORK] = $CompletedWork
            }

            if ($PSBoundParameters.ContainsKey('State')) {
                $updateFields[$script:FIELD_SYSTEM_STATE] = $State
            }

            if ($updateFields.Count -eq 0) {
                Write-Error "At least one field must be provided for update (Title, Description, Priority, OriginalEstimate, RemainingWork, CompletedWork, or State)."
            }

            $fieldList = @($updateFields.Keys) -join ", "
            $logMessage = "Updating existing Task (ID: $Id) with fields: $fieldList"
            $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

            $updated = Update-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $Id -Fields $updateFields -PatToken $PatToken

            $logMessage = "Successfully updated Task (ID: $($updated.id))"
            $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"

            return $updated
        }
        else {
            # Task does not exist
            $logMessage = "Task with ID ::FgGreen::$Id::FgDefault:: does not exist, cannot update."
            $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
            Write-Error "Task with ID $Id does not exist. Cannot update non-existent Task."
        }
    }
    else {
        # UPSERT mode - -Id not provided, search by title
        # Search for existing Task with the same title
        $existingByTitle = & "$PSScriptRoot/FindAzDoItemByTitle.ps1" -Organization $Organization -Project $Project -Title $Title -Type $script:WORKITEM_TYPE_TASK -PatToken $PatToken -ErrorAction SilentlyContinue

        if ($null -ne $existingByTitle) {
            # Task with this title already exists
            if ($PSBoundParameters.ContainsKey('FailIfExist')) {
                # Create-only mode: fail if title already exists
                $logMessage = "Task with title ::FgGreen::$Title::FgDefault:: already exists (ID: $($existingByTitle.id)) and -FailIfExist is set"
                $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
                Write-Error "Task with title '$Title' already exists (ID: $($existingByTitle.id)). Cannot create in -FailIfExist mode."
            }

            # Update mode: update the existing Task by ID
            $updateFields = @{}

            # Merge -Fields first; explicit params below take precedence
            if ($PSBoundParameters.ContainsKey('Fields') -and $null -ne $Fields) {
                foreach ($k in $Fields.Keys) { $updateFields[$k] = $Fields[$k] }
            }

            if ($PSBoundParameters.ContainsKey('Description')) {
                $updateFields[$script:FIELD_DESCRIPTION] = $Description
            }

            if ($PSBoundParameters.ContainsKey('Priority')) {
                $updateFields[$script:FIELD_PRIORITY] = $Priority
            }

            if ($PSBoundParameters.ContainsKey('OriginalEstimate')) {
                $updateFields[$script:FIELD_ORIGINAL_ESTIMATE] = $OriginalEstimate
            }

            if ($PSBoundParameters.ContainsKey('RemainingWork')) {
                $updateFields[$script:FIELD_REMAINING_WORK] = $RemainingWork
            }

            if ($PSBoundParameters.ContainsKey('CompletedWork')) {
                $updateFields[$script:FIELD_COMPLETED_WORK] = $CompletedWork
            }

            if ($PSBoundParameters.ContainsKey('State')) {
                $updateFields[$script:FIELD_SYSTEM_STATE] = $State
            }

            # Note: Title is already the same, so we don't need to update it unless explicitly provided for override
            # But since we matched by title, we typically don't change it
            if ($updateFields.Count -eq 0) {
                # No fields to update, just return the existing task
                $logMessage = "Task with title ::FgGreen::$Title::FgDefault:: already exists (ID: $($existingByTitle.id)), no field updates provided"
                $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"
                return $existingByTitle
            }

            $fieldList = @($updateFields.Keys) -join ", "
            $logMessage = "Updating existing Task by title ::FgGreen::$Title::FgDefault:: (ID: $($existingByTitle.id)) with fields: $fieldList"
            $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

            $updated = Update-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $existingByTitle.id -Fields $updateFields -PatToken $PatToken

            $logMessage = "Successfully updated Task (ID: $($updated.id))"
            $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"

            return $updated
        }
        else {
            # Task with this title does not exist, create new one
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

            if ($PSBoundParameters.ContainsKey('Priority')) {
                $createFields[$script:FIELD_PRIORITY] = $Priority
            }

            if ($PSBoundParameters.ContainsKey('OriginalEstimate')) {
                $createFields[$script:FIELD_ORIGINAL_ESTIMATE] = $OriginalEstimate
            }

            if ($PSBoundParameters.ContainsKey('RemainingWork')) {
                $createFields[$script:FIELD_REMAINING_WORK] = $RemainingWork
            }

            if ($PSBoundParameters.ContainsKey('CompletedWork')) {
                $createFields[$script:FIELD_COMPLETED_WORK] = $CompletedWork
            }

            if ($PSBoundParameters.ContainsKey('State')) {
                $createFields[$script:FIELD_SYSTEM_STATE] = $State
            }

            # Validate parent Story if specified
            if ($PSBoundParameters.ContainsKey('ParentStoryId')) {
                try {
                    $parentStory = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $ParentStoryId -PatToken $PatToken
                    if ($null -eq $parentStory) {
                        Write-Error "Parent Story with ID $ParentStoryId not found."
                    }

                    $logMessage = "Creating Task as child of Story (ID: $ParentStoryId)"
                    $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"
                }
                catch {
                    Write-Error "Failed to validate parent Story with ID $ParentStoryId : $($_.Exception.Message)"
                }
            }

            $logMessage = "Creating new Task with title ::FgGreen::$Title::FgDefault::"
            $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

            $createParams = @{
                Organization = $Organization
                Project      = $Project
                WorkItemType = $script:WORKITEM_TYPE_TASK
                Fields       = $createFields
                PatToken     = $PatToken
            }

            if ($PSBoundParameters.ContainsKey('ParentStoryId')) {
                $createParams['ParentId'] = $ParentStoryId
            }

            $newTask = New-AzDoWorkItem @createParams

            $logMessage = "Successfully created Task ::FgGreen::$Title::FgDefault:: (ID: $($newTask.id))"
            $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"

            return $newTask
        }
    }
}
catch {
    [string]$errorMsg = $_.Exception.Message
    $logMessage = "Failed to create/update Task: ::FgRed::$errorMsg::FgDefault::"
    $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
    throw
}
