<#
.SYNOPSIS
Create or update an Azure DevOps Story work item

.DESCRIPTION
Unified UPSERT operation to create a new Story or update an existing Story in Azure DevOps.
Stories are work items used to track feature-related work within a parent Feature.

Behavior depends on provided parameters:
- If -Id is provided: Update the existing Story by ID (no title-based lookup)
- If -Id is not provided: UPSERT by Title (update if exists, create if not)
  - If -FailIfExist is also set: Creates only if no Story with that title exists; fails if found

Returns the created or updated Story work item with all current fields populated.

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER Title
The Story title (required when creating or upserting by title). Used as the primary key when -Id is not provided.

.PARAMETER Id
Optional Story ID for direct update by ID. If provided, updates the Story by this ID without title-based lookup.
Cannot be used with -FailIfExist (these are mutually exclusive).

.PARAMETER Description
Optional description for the Story

.PARAMETER AcceptanceCriteria
Optional acceptance criteria for the Story

.PARAMETER AcScenarios
Optional acceptance criteria scenarios for the Story

.PARAMETER ExtraInformation
Optional extra information for the Story

.PARAMETER StoryPoints
Optional story point value (must be a non-negative number; decimals such as 0.5 are supported)

.PARAMETER Priority
Optional priority for the Story (1-4, where 1 is highest priority)

.PARAMETER OriginalEstimate
Optional original estimate in hours (non-negative number) for time tracking

.PARAMETER FixedIn
Optional text field indicating the version or build where this Story was fixed/completed

.PARAMETER DeployedToDev
Optional boolean indicating whether the Story has been deployed to the Dev environment

.PARAMETER DeployedToStaging
Optional boolean indicating whether the Story has been deployed to the Staging environment

.PARAMETER DeployedToProduction
Optional boolean indicating whether the Story has been deployed to the Production environment

.PARAMETER ParentFeatureId
Optional parent Feature work item ID. If provided, the Story will be created as a child of this Feature (for create operations only).

.PARAMETER FailIfExist
Optional switch for create-only mode when not using -Id. Only applicable without -Id.
If set, fails if a Story with the specified Title already exists (prevents accidental overwrites).
Cannot be used with -Id (these are mutually exclusive).

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
PSObject representing the created or updated Story work item with all fields populated

.EXAMPLE
Create or update Story by title (standard UPSERT):
    $story = .\UpsertAzDoStory.ps1 -Organization "myorg" -Project "myproject" -Title "User Login" -Description "Updated description"

Create Story only if title doesn't exist:
    $story = .\UpsertAzDoStory.ps1 -Organization "myorg" -Project "myproject" -Title "User Login" -FailIfExist

Create Story under a Feature:
    $story = .\UpsertAzDoStory.ps1 -Organization "myorg" -Project "myproject" -Title "Login Form" -ParentFeatureId 42 -StoryPoints 5

Update existing Story by ID directly:
    $updated = .\UpsertAzDoStory.ps1 -Organization "myorg" -Project "myproject" -Id 123 -AcceptanceCriteria "Must support OAuth"

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read/write scope
- Supports partial updates (only specified fields are changed)
- Title-based lookup is performed when -Id is not provided
- ParentFeatureId is only used when creating new Stories
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

    [string]$AcceptanceCriteria,

    [string]$AcScenarios,

    [string]$ExtraInformation,

    [double]$StoryPoints,

    [int]$Priority,

    [double]$OriginalEstimate,

    [string]$FixedIn,

    [bool]$DeployedToDev,

    [bool]$DeployedToStaging,

    [bool]$DeployedToProduction,

    [int]$ParentFeatureId,

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
    Write-Error "-Id and -FailIfExist are mutually exclusive. When -Id is provided, the Story already exists, so -FailIfExist is not applicable."
}

# Title is required for create (not provided with -Id), but optional for update (provided with -Id)
if (-not $PSBoundParameters.ContainsKey('Id') -and [string]::IsNullOrWhiteSpace($Title)) {
    Write-Error "Parameter 'Title' is required when creating a new Story (when -Id is not provided)."
}

if ($PSBoundParameters.ContainsKey('StoryPoints') -and $StoryPoints -lt 0) {
    Write-Error "Parameter 'StoryPoints' must be a non-negative number. Provided: $StoryPoints"
}

if ($PSBoundParameters.ContainsKey('Priority') -and ($Priority -lt 1 -or $Priority -gt 4)) {
    Write-Error "Parameter 'Priority' must be between 1 and 4 (1=highest). Provided: $Priority"
}

if ($PSBoundParameters.ContainsKey('OriginalEstimate') -and $OriginalEstimate -lt 0) {
    Write-Error "Parameter 'OriginalEstimate' must be a non-negative number. Provided: $OriginalEstimate"
}

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    # Check if -Id was provided (determine create vs update)
    if ($PSBoundParameters.ContainsKey('Id')) {
        # Update mode - update by ID directly without title-based lookup
        $existingStory = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $Id -PatToken $PatToken

        if ($null -ne $existingStory) {
            # Story already exists
            if ($FailIfExist) {
                $logMessage = "Story with ID ::FgGreen::$Id::FgDefault:: already exists and -FailIfExist is set"
                $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
                Write-Error "Story already exists (ID: $Id). Cannot create in -FailIfExist mode."
            }

            # Update mode - update only provided fields
            $updateFields = @{}

            if ($PSBoundParameters.ContainsKey('Title')) {
                $updateFields[$script:FIELD_SYSTEM_TITLE] = $Title
            }

            if ($PSBoundParameters.ContainsKey('Description')) {
                $updateFields[$script:FIELD_DESCRIPTION] = $Description
            }

            if ($PSBoundParameters.ContainsKey('AcceptanceCriteria')) {
                $updateFields[$script:FIELD_ACCEPTANCE_CRITERIA] = $AcceptanceCriteria
            }

            if ($PSBoundParameters.ContainsKey('AcScenarios')) {
                $updateFields[$script:FIELD_AC_SCENARIOS] = $AcScenarios
            }

            if ($PSBoundParameters.ContainsKey('ExtraInformation')) {
                $updateFields[$script:FIELD_EXTRA_INFORMATION] = $ExtraInformation
            }

            if ($PSBoundParameters.ContainsKey('StoryPoints')) {
                $updateFields[$script:FIELD_STORY_POINTS] = $StoryPoints
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

            if ($updateFields.Count -eq 0) {
                Write-Error "At least one field must be provided for update (Title, Description, AcceptanceCriteria, AcScenarios, ExtraInformation, StoryPoints, Priority, OriginalEstimate, FixedIn, DeployedToDev, DeployedToStaging, or DeployedToProduction)."
            }

            $fieldList = @($updateFields.Keys) -join ", "
            $logMessage = "Updating existing Story (ID: $Id) with fields: $fieldList"
            $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

            $updated = Update-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $Id -Fields $updateFields -PatToken $PatToken

            $logMessage = "Successfully updated Story (ID: $($updated.id))"
            $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"

            return $updated
        }
        else {
            # Story does not exist
            $logMessage = "Story with ID ::FgGreen::$Id::FgDefault:: does not exist, cannot update."
            $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
            Write-Error "Story with ID $Id does not exist. Cannot update non-existent Story."
        }
    }
    else {
        # UPSERT mode - -Id not provided, search by title
        # Search for existing Story with the same title
        $existingByTitle = & "$PSScriptRoot/FindAzDoItemByTitle.ps1" -Organization $Organization -Project $Project -Title $Title -Type $script:WORKITEM_TYPE_STORY -PatToken $PatToken -ErrorAction SilentlyContinue

        if ($null -ne $existingByTitle) {
            # Story with this title already exists
            if ($PSBoundParameters.ContainsKey('FailIfExist')) {
                # Create-only mode: fail if title already exists
                $logMessage = "Story with title ::FgGreen::$Title::FgDefault:: already exists (ID: $($existingByTitle.id)) and -FailIfExist is set"
                $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
                Write-Error "Story with title '$Title' already exists (ID: $($existingByTitle.id)). Cannot create in -FailIfExist mode."
            }

            # Update mode: update the existing Story by ID
            $updateFields = @{}

            if ($PSBoundParameters.ContainsKey('Description')) {
                $updateFields[$script:FIELD_DESCRIPTION] = $Description
            }

            if ($PSBoundParameters.ContainsKey('AcceptanceCriteria')) {
                $updateFields[$script:FIELD_ACCEPTANCE_CRITERIA] = $AcceptanceCriteria
            }

            if ($PSBoundParameters.ContainsKey('AcScenarios')) {
                $updateFields[$script:FIELD_AC_SCENARIOS] = $AcScenarios
            }

            if ($PSBoundParameters.ContainsKey('ExtraInformation')) {
                $updateFields[$script:FIELD_EXTRA_INFORMATION] = $ExtraInformation
            }

            if ($PSBoundParameters.ContainsKey('StoryPoints')) {
                $updateFields[$script:FIELD_STORY_POINTS] = $StoryPoints
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

            # Note: Title is already the same, so we don't need to update it unless explicitly provided for override
            # But since we matched by title, we typically don't change it
            if ($updateFields.Count -eq 0) {
                # No fields to update, just return the existing story
                $logMessage = "Story with title ::FgGreen::$Title::FgDefault:: already exists (ID: $($existingByTitle.id)), no field updates provided"
                $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"
                return $existingByTitle
            }

            $fieldList = @($updateFields.Keys) -join ", "
            $logMessage = "Updating existing Story by title ::FgGreen::$Title::FgDefault:: (ID: $($existingByTitle.id)) with fields: $fieldList"
            $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

            $updated = Update-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $existingByTitle.id -Fields $updateFields -PatToken $PatToken

            $logMessage = "Successfully updated Story (ID: $($updated.id))"
            $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"

            return $updated
        }
        else {
            # Story with this title does not exist, create new one
            $createFields = @{
                $script:FIELD_SYSTEM_TITLE = $Title
            }

            if ($PSBoundParameters.ContainsKey('Description')) {
                $createFields[$script:FIELD_DESCRIPTION] = $Description
            }

            if ($PSBoundParameters.ContainsKey('AcceptanceCriteria')) {
                $createFields[$script:FIELD_ACCEPTANCE_CRITERIA] = $AcceptanceCriteria
            }

            if ($PSBoundParameters.ContainsKey('AcScenarios')) {
                $createFields[$script:FIELD_AC_SCENARIOS] = $AcScenarios
            }

            if ($PSBoundParameters.ContainsKey('ExtraInformation')) {
                $createFields[$script:FIELD_EXTRA_INFORMATION] = $ExtraInformation
            }

            if ($PSBoundParameters.ContainsKey('StoryPoints')) {
                $createFields[$script:FIELD_STORY_POINTS] = $StoryPoints
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

            # Validate parent Feature if specified
            if ($PSBoundParameters.ContainsKey('ParentFeatureId')) {
                try {
                    $parentFeature = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $ParentFeatureId -PatToken $PatToken
                    if ($null -eq $parentFeature) {
                        Write-Error "Parent Feature with ID $ParentFeatureId not found."
                    }

                    $logMessage = "Creating Story as child of Feature (ID: $ParentFeatureId)"
                    $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"
                }
                catch {
                    Write-Error "Failed to validate parent Feature with ID $ParentFeatureId : $($_.Exception.Message)"
                }
            }

            $logMessage = "Creating new Story with title ::FgGreen::$Title::FgDefault::"
            $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

            $createParams = @{
                Organization = $Organization
                Project      = $Project
                WorkItemType = $script:WORKITEM_TYPE_STORY
                Fields       = $createFields
                PatToken     = $PatToken
            }

            if ($PSBoundParameters.ContainsKey('ParentFeatureId')) {
                $createParams['ParentId'] = $ParentFeatureId
            }

            $newStory = New-AzDoWorkItem @createParams

            $logMessage = "Successfully created Story ::FgGreen::$Title::FgDefault:: (ID: $($newStory.id))"
            $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"

            return $newStory
        }
    }
}
catch {
    [string]$errorMsg = $_.Exception.Message
    $logMessage = "Failed to create/update Story: ::FgRed::$errorMsg::FgDefault::"
    $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
    throw
}
