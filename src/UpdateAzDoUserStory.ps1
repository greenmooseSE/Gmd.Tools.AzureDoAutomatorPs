<#
.SYNOPSIS
Update an Azure DevOps User Story by ID

.DESCRIPTION
Updates a User Story in Azure DevOps by its ID using a PATCH operation.
Only updates fields that are provided as parameters - fields not specified will not be changed.

Supports updating:
- Title, Description
- State (to transition state)
- AcceptanceCriteria, ACScenarios, ExtraInformation
- StoryPoints, Tags

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER WorkItemId
The User Story work item ID to update (required)

.PARAMETER Title
Optional: New title for the User Story

.PARAMETER Description
Optional: New description for the User Story

.PARAMETER State
Optional: New state for the User Story (e.g., "New", "Under Development", "Done")

.PARAMETER AcceptanceCriteria
Optional: New acceptance criteria text

.PARAMETER ACScenarios
Optional: New AC Scenarios text

.PARAMETER ExtraInformation
Optional: New extra information text

.PARAMETER StoryPoints
Optional: New story points value

.PARAMETER Tags
Optional: Comma-separated list of tags to set. Replaces existing tags.

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
PSObject representing the updated User Story work item

.EXAMPLE
Update User Story title:
    $story = .\UpdateAzDoUserStory.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123 -Title "New Title"

Update multiple fields:
    $story = .\UpdateAzDoUserStory.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123 `
        -Title "Updated Title" -Description "New description" -StoryPoints 5 -Tags "bug, documentation"

Update state:
    $story = .\UpdateAzDoUserStory.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123 -State "Under Development"

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read/write scope
- Only specified fields are updated; others remain unchanged
- Tags replace any existing tags when specified
- State transitions must be valid for the current state
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [int]$WorkItemId,

    [string]$Title,

    [string]$Description,

    [string]$State,

    [string]$AcceptanceCriteria,

    [string]$ACScenarios,

    [string]$ExtraInformation,

    [int]$StoryPoints,

    [string]$Tags,

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

# At least one field must be specified for update
$updateFieldsCount = @(
    $PSBoundParameters.ContainsKey('Title'),
    $PSBoundParameters.ContainsKey('Description'),
    $PSBoundParameters.ContainsKey('State'),
    $PSBoundParameters.ContainsKey('AcceptanceCriteria'),
    $PSBoundParameters.ContainsKey('ACScenarios'),
    $PSBoundParameters.ContainsKey('ExtraInformation'),
    $PSBoundParameters.ContainsKey('StoryPoints'),
    $PSBoundParameters.ContainsKey('Tags')
) | Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count

if ($updateFieldsCount -eq 0) {
    Write-Error "At least one field must be specified for update (Title, Description, State, AcceptanceCriteria, ACScenarios, ExtraInformation, StoryPoints, or Tags)."
}

$null = & ssLogIt.ps1 -Level Info -Message "Updating User Story (ID: $WorkItemId)"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    # Verify work item exists and is a User Story
    $workItem = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $WorkItemId -PatToken $PatToken

    if ($null -eq $workItem) {
        $null = & ssLogIt.ps1 -Level Error -Message "Work item not found (ID: $WorkItemId)"
        Write-Error "Work item with ID $WorkItemId not found."
    }

    $workItemType = $workItem.fields.'System.WorkItemType'
    if ($workItemType -ne $script:WORKITEM_TYPE_STORY) {
        $null = & ssLogIt.ps1 -Level Error -Message "Work item is not a User Story (Type: $workItemType, ID: $WorkItemId)"
        Write-Error "Work item with ID $WorkItemId is not a User Story (Type: $workItemType)."
    }

    # Build Fields hashtable for update
    $updateFields = @{}

    if ($PSBoundParameters.ContainsKey('Title')) {
        $updateFields['System.Title'] = $Title
        $null = & ssLogIt.ps1 -Level Debug -Message "Queuing update: Title = '::FgGreen::$Title::FgDefault::'"
    }

    if ($PSBoundParameters.ContainsKey('Description')) {
        $updateFields['System.Description'] = $Description
        $null = & ssLogIt.ps1 -Level Debug -Message "Queuing update: Description"
    }

    if ($PSBoundParameters.ContainsKey('State')) {
        $updateFields['System.State'] = $State
        $null = & ssLogIt.ps1 -Level Debug -Message "Queuing update: State = '::FgGreen::$State::FgDefault::'"
    }

    if ($PSBoundParameters.ContainsKey('AcceptanceCriteria')) {
        $updateFields['Microsoft.VSTS.Common.AcceptanceCriteria'] = $AcceptanceCriteria
        $null = & ssLogIt.ps1 -Level Debug -Message "Queuing update: AcceptanceCriteria"
    }

    if ($PSBoundParameters.ContainsKey('ACScenarios')) {
        $updateFields['Custom.ACScenarios'] = $ACScenarios
        $null = & ssLogIt.ps1 -Level Debug -Message "Queuing update: ACScenarios"
    }

    if ($PSBoundParameters.ContainsKey('ExtraInformation')) {
        $updateFields['Custom.ExtraInformation'] = $ExtraInformation
        $null = & ssLogIt.ps1 -Level Debug -Message "Queuing update: ExtraInformation"
    }

    if ($PSBoundParameters.ContainsKey('StoryPoints')) {
        $updateFields['Microsoft.VSTS.Scheduling.StoryPoints'] = $StoryPoints
        $null = & ssLogIt.ps1 -Level Debug -Message "Queuing update: StoryPoints = $StoryPoints"
    }

    if ($PSBoundParameters.ContainsKey('Tags')) {
        $updateFields['System.Tags'] = $Tags
        $null = & ssLogIt.ps1 -Level Debug -Message "Queuing update: Tags = '::FgGreen::$Tags::FgDefault::'"
    }

    # Perform the update using Update-AzDoWorkItem
    $updatedWorkItem = Update-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $WorkItemId -Fields $updateFields -PatToken $PatToken

    if ($null -eq $updatedWorkItem) {
        $null = & ssLogIt.ps1 -Level Error -Message "Failed to update User Story (ID: $WorkItemId)"
        Write-Error "Failed to update User Story with ID $WorkItemId."
    }

    $title = $updatedWorkItem.fields.'System.Title'
    $null = & ssLogIt.ps1 -Level Info -Message "Successfully updated User Story: ::FgGreen::$title::FgDefault:: (ID: $($updatedWorkItem.id))"

    return $updatedWorkItem
}
catch {
    $null = & ssLogIt.ps1 -Level Error -Message "Failed to update User Story: $_" -Exception $_
    Write-Error $_
    throw
}
