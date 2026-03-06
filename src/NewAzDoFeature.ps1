<#
.SYNOPSIS
Create or update an Azure DevOps Feature work item

.DESCRIPTION
Creates a new Feature in Azure DevOps, or updates an existing one if -UpdateExisting is specified.
When updating, searches for a feature with the same title within the same Epic (if ParentEpicId provided).

Supports creating Features under an optional parent Epic.
Returns the created or updated Feature work item with ID.

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER Title
The Feature title (required)

.PARAMETER Description
Optional description for the Feature

.PARAMETER ParentEpicId
Optional parent Epic work item ID. If provided, the Feature will be created as a child of this Epic.

.PARAMETER UpdateExisting
Switch parameter. If specified, will update the existing Feature if found. If not specified and the Feature
exists, script will fail with an error message.

.PARAMETER Effort
Optional effort value for the Feature (must be a non-negative integer)

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from FALCOIT_AZDO_PAT_WORKITEMSREADWRITE
environment variable (expected to be encrypted).

.OUTPUTS
PSObject representing the created or updated Feature work item with all fields populated

.EXAMPLE
Create a new Feature:
    $feature = .\New-AzDoFeature.ps1 -Organization "myorg" -Project "myproject" -Title "User Authentication"

Create a Feature under an Epic:
    $feature = .\New-AzDoFeature.ps1 -Organization "myorg" -Project "myproject" -Title "API Integration" -ParentEpicId 42

Update an existing Feature:
    $feature = .\New-AzDoFeature.ps1 -Organization "myorg" -Project "myproject" -Title "Existing Feature" -UpdateExisting -Description "Updated description"

Create a Feature with effort:
    $feature = .\New-AzDoFeature.ps1 -Organization "myorg" -Project "myproject" -Title "Search Feature" -Effort 13

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read/write scope
- Fails fast without updating if Feature exists and -UpdateExisting not specified
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [string]$Title,

    [string]$Description,

    [int]$ParentEpicId,

    [switch]$UpdateExisting,

    [int]$Effort,

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

if ($PSBoundParameters.ContainsKey('Effort') -and $Effort -lt 0) {
    Write-Error "Parameter 'Effort' must be a non-negative integer. Provided: $Effort"
}

# Log script start
$null = & ssLogIt.ps1 -Level Info -Message "Creating/updating Feature: ::FgGreen::$Title::FgDefault:: in project ::FgGreen::$Project::FgDefault::"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    # Search for existing Feature with same title in same parent context
    try {
        $scriptArgs = @{
            Organization = $Organization
            Project      = $Project
            Title        = $Title
            Type         = $script:WORKITEM_TYPE_FEATURE
        }

        if ($PSBoundParameters.ContainsKey('ParentEpicId')) {
            $scriptArgs['ParentId'] = $ParentEpicId
        }

        if ($PSBoundParameters.ContainsKey('PatToken')) {
            $scriptArgs['PatToken'] = $PatToken
        }

        # Build script call command dynamically
        $existingFeature = & "$PSScriptRoot/FindAzDoItemByTitle.ps1" @scriptArgs
    }
    catch {
        # Unexpected error - rethrow
        throw;
    }

    if ($null -ne $existingFeature) {
        # Feature already exists
        if (-not $UpdateExisting) {
            # Fail if not updating
            $logMessage = "Feature with title ::FgRed::$Title::FgDefault:: already exists (ID: $($existingFeature.id)). Use -UpdateExisting to update it."
            $null = & ssLogIt.ps1 -Level Error -Message "$logMessage"
            Write-Error "Feature already exists with title '$Title'. Use -UpdateExisting switch to update it."
        }

        # Update existing Feature
        $updateFields = @{
            $script:FIELD_SYSTEM_TITLE = $Title
        }

        if ($PSBoundParameters.ContainsKey('Description')) {
            $updateFields[$script:FIELD_DESCRIPTION] = $Description
        }

        if ($PSBoundParameters.ContainsKey('Effort')) {
            $updateFields[$script:FIELD_EFFORT] = $Effort
        }

        $logMessage = "Updating existing Feature (ID: $($existingFeature.id))"
        $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

        $updated = Update-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $existingFeature.id -Fields $updateFields -PatToken $PatToken

        $logMessage = "Successfully updated Feature ::FgGreen::$Title::FgDefault:: (ID: $($updated.id))"
        $null = & ssLogIt.ps1 -Level Info -Message "$logMessage"

        return $updated
    }

    # Create new Feature
    $createFields = @{
        $script:FIELD_SYSTEM_TITLE = $Title
    }

    if ($PSBoundParameters.ContainsKey('Description')) {
        $createFields[$script:FIELD_DESCRIPTION] = $Description
    }

    if ($PSBoundParameters.ContainsKey('Effort')) {
        $createFields[$script:FIELD_EFFORT] = $Effort
    }

    # Add parent Epic if specified
    if ($PSBoundParameters.ContainsKey('ParentEpicId')) {
        # Validate parent Epic exists
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
catch {
    [string]$errorMsg = $_.Exception.Message
    $logMessage = "Failed to create/update Feature: ::FgRed::$errorMsg::FgDefault::"
    $null = &ssLogIt.ps1 -Level Error -Message "$logMessage"
    throw
}
