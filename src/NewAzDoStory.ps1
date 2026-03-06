<#
.SYNOPSIS
Create or update an Azure DevOps Story work item

.DESCRIPTION
Creates a new Story in Azure DevOps under a parent Feature, or updates an existing one if -UpdateExisting is specified.
When updating, searches for a story with the same title within the same Feature.

Supports setting description, acceptance criteria, acceptance criteria scenarios, extra information, and story points.
Returns the created or updated Story work item with ID.

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER Title
The Story title (required)

.PARAMETER ParentFeatureId
The parent Feature work item ID (required)

.PARAMETER Description
Optional description for the Story

.PARAMETER AcceptanceCriteria
Optional acceptance criteria for the Story

.PARAMETER AcScenarios
Optional acceptance criteria scenarios for the Story

.PARAMETER ExtraInformation
Optional extra information for the Story

.PARAMETER StoryPoints
Optional story point value (must be non-negative integer)

.PARAMETER UpdateExisting
Switch parameter. If specified, will update the existing Story if found. If not specified and the Story
exists, script will fail with an error message.

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
PSObject representing the created or updated Story work item with all fields populated

.EXAMPLE
Create a new Story:
    $story = .\New-AzDoStory.ps1 -Organization "myorg" -Project "myproject" -Title "User Login Form" -ParentFeatureId 123

Create a Story with full details:
    $story = .\New-AzDoStory.ps1 -Organization "myorg" -Project "myproject" -Title "Login Form" `
        -ParentFeatureId 123 -Description "Build login form" `
        -AcceptanceCriteria "Must support email/password and OAuth" -StoryPoints 5

Create a Story with all multi-line fields:
    $story = .\New-AzDoStory.ps1 -Organization "myorg" -Project "myproject" -Title "Login Flow" `
        -ParentFeatureId 123 -Description "Build complete login flow" `
        -AcceptanceCriteria "Must support email/password and OAuth" `
        -AcScenarios "Given user is on login page, When they enter credentials, Then they are authenticated" `
        -ExtraInformation "Requires integration with OAuth provider" -StoryPoints 5

Update an existing Story:
    $story = .\New-AzDoStory.ps1 -Organization "myorg" -Project "myproject" -Title "Existing Story" `
        -ParentFeatureId 123 -UpdateExisting -StoryPoints 8

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read/write scope
- ParentFeatureId must be a valid Feature work item ID
- Fails fast without updating if Story exists and -UpdateExisting not specified
- Supports multi-line fields: Description, AcceptanceCriteria, AcScenarios, ExtraInformation
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [string]$Title,

    [Parameter(Mandatory = $true)]
    [int]$ParentFeatureId,

    [string]$Description,

    [string]$AcceptanceCriteria,

    [string]$AcScenarios,

    [string]$ExtraInformation,

    [int]$StoryPoints,

    [switch]$UpdateExisting,

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

if ([string]::IsNullOrWhiteSpace($Title)) {
    Write-Error "Parameter 'Title' cannot be empty."
}

if (-not (Test-AzDoWorkItemIdValid $ParentFeatureId)) {
    Write-Error "Parameter 'ParentFeatureId' must be a positive integer."
}

# Validate StoryPoints if provided
if ($PSBoundParameters.ContainsKey('StoryPoints')) {
    if ($StoryPoints -lt 0) {
        Write-Error "Parameter 'StoryPoints' must be a non-negative integer. Provided: $StoryPoints"
    }
}

# Log script start
$null = & ssLogIt.ps1 -Level Info -Message "Creating/updating Story: ::FgGreen::$Title::FgDefault:: under Feature (ID: $ParentFeatureId)"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    # Validate parent Feature exists
    $logMessage = "Validating parent Feature (ID: $ParentFeatureId)"
    $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

    $parentFeature = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $ParentFeatureId -PatToken $PatToken
    if ($null -eq $parentFeature) {
        Write-Error "Parent Feature with ID $ParentFeatureId not found."
    }

    # Search for existing Story with same title in same Feature
    try {
        $scriptArgs = @{
            Organization = $Organization
            Project      = $Project
            Title        = $Title
            Type         = $script:WORKITEM_TYPE_STORY
            ParentId     = $ParentFeatureId
        }

        if ($PSBoundParameters.ContainsKey('PatToken')) {
            $scriptArgs['PatToken'] = $PatToken
        }

        $existingStory = & "$PSScriptRoot/FindAzDoItemByTitle.ps1" @scriptArgs
    }
    catch {
        # Unexpected error - rethrow
        throw
    }

    if ($null -ne $existingStory) {
        # Story already exists
        if (-not $UpdateExisting) {
            # Fail if not updating
            $logMessage = "Story with title ::FgRed::$Title::FgDefault:: already exists (ID: $($existingStory.id)). Use -UpdateExisting to update it."
            $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
            Write-Error "Story already exists with title '$Title'. Use -UpdateExisting switch to update it."
        }

        # Update existing Story
        $updateFields = @{
            $script:FIELD_SYSTEM_TITLE = $Title
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

        $logMessage = "Updating existing Story (ID: $($existingStory.id))"
        $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

        $updated = Update-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $existingStory.id -Fields $updateFields -PatToken $PatToken

        $logMessage = "Successfully updated Story ::FgGreen::$Title::FgDefault:: (ID: $($updated.id))"
        $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"

        return $updated
    }

    # Create new Story
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

    $logMessage = "Creating new Story with title ::FgGreen::$Title::FgDefault::"
    $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

    $createParams = @{
        Organization = $Organization
        Project      = $Project
        WorkItemType = $script:WORKITEM_TYPE_STORY
        Fields       = $createFields
        ParentId     = $ParentFeatureId
        PatToken     = $PatToken
    }

    $newStory = New-AzDoWorkItem @createParams

    $logMessage = "Successfully created Story ::FgGreen::$Title::FgDefault:: (ID: $($newStory.id))"
    $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"

    return $newStory
}
catch {
    [string]$errorMsg = $_.Exception.Message
    $logMessage = "Failed to create/update Story: $errorMsg"
    ssLogIt.ps1 -Level Error -Message "$logMessage";
    # Write-Error $_
    throw;
}
