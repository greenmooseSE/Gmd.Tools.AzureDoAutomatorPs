<#
.SYNOPSIS
Create a temporary test hierarchy in Azure DevOps for testing purposes.

.DESCRIPTION
Helper function for tests that need to create temporary work item hierarchies in Azure DevOps.
Creates an Epic with "TEST-" prefix followed by a timestamp, then creates the specified hierarchy
structure underneath it. All created work items are tagged with "testWi" for easy identification and cleanup.

This function manages the complete lifecycle:
- Creates Epic with deterministic naming: "TEST-<timestamp>-<description>"
- Creates Features, Stories, Tasks, Bugs according to specification
- Tags all items with "testWi" for easy orphan detection
- Returns object with all created work item IDs for test verification
- Cleanup should be performed using RemoveAzDoEpic.ps1 with -Force

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER Description
Brief description for the test Epic title (required). Will be prefixed with "TEST-<timestamp>-"
Example: "Export-Import-Test" becomes "TEST-20260403-210250-Export-Import-Test"

.PARAMETER HierarchySpec
Hashtable specification of the hierarchy structure to create. Uses nested structure.
Example:
    $spec = @{
        features = @(
            @{
                title        = "Feature 1"
                effort       = 8
                description  = "Feature 1 description"
                stories      = @(
                    @{
                        title        = "Story 1.1"
                        storyPoints  = 3
                        description  = "Story description"
                        tasks        = @(
                            @{ title = "Task 1.1.1"; effort = 2 }
                        )
                    }
                )
                tasks        = @(
                    @{ title = "Feature Task 1"; effort = 1 }
                )
            }
        )
        bugs     = @(
            @{ title = "Bug 1"; severity = "Critical" }
        )
    }

.PARAMETER CustomProperties
Optional hashtable for custom work item properties to apply to all items.
Supports: tags (array or semicolon-separated string), effort, storyPoints, severity
Example: @{ tags = @("integration-test", "automation"); effort = 5 }

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
PSObject with structure:
    @{
        Success = $true|$false
        Epic    = @{ Id = 123; Title = "TEST-..."; Url = "..." }
        Features   = @{ feature1Title = @{ Id = 456; ... }; ... }
        Stories    = @{ story1Title = @{ Id = 789; ... }; ... }
        Tasks      = @{ task1Title = @{ Id = 101; ... }; ... }
        Bugs       = @{ bug1Title = @{ Id = 102; ... }; ... }
        AllWorkItemIds = @(123, 456, 789, ...)  # For easy cleanup/validation
        Errors = @()  # Any errors encountered during creation
    }

.EXAMPLE
Create simple test hierarchy:
    $spec = @{
        features = @(
            @{
                title       = "Auth Feature"
                effort      = 8
                description = "Authentication"
                stories     = @(
                    @{ title = "Login Story"; storyPoints = 3 }
                )
            }
        )
    }
    $result = .\CreateTestHierarchy.ps1 -Organization "falco-it" -Project "GMD" -Description "Auth-Test" -HierarchySpec $spec
    Write-Host "Created Epic: $($result.Epic.Id)"
    Write-Host "All work items: $($result.AllWorkItemIds -join ',')"

    # Later, cleanup all created items with:
    # .\RemoveAzDoEpic.ps1 -Organization "falco-it" -Project "GMD" -EpicId $result.Epic.Id -Force

.NOTES
- The "testWi" tag is automatically added to all created items
- For hierarchies with 100+ items, consider batching calls
- All operations should be wrapped in try/finally to ensure cleanup runs
- Returns immediately on first creation failure (partial hierarchies may exist)
- Timestamps are in format "yyyyMMdd-HHmmss" for uniqueness
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $false)]
    [string]$Organization,

    [Parameter(Mandatory = $false)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [string]$Description,

    [Parameter(Mandatory = $true)]
    [hashtable]$HierarchySpec,

    [Parameter(Mandatory = $false)]
    [hashtable]$CustomProperties,

    [string]$PatToken
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Import modules
$SRC_DIR = Join-Path $PSScriptRoot '../src' -Resolve
. (Join-Path $SRC_DIR 'AzDoAutomatorConstants.ps1')
. (Join-Path $SRC_DIR 'AzDoPatTokenHelper.ps1')
. (Join-Path $SRC_DIR 'AzDoApiWrapper.ps1')
. (Join-Path $SRC_DIR 'AzDoWorkItemHelper.ps1')

# Validate ssLogIt.ps1 exists
if (-not (Get-Command -Name 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    Write-Error "Required helper script 'ssLogIt.ps1' not found in PATH."
}

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

# Initialize result structure
$result = @{
    Success         = $false
    Epic            = $null
    Features        = @{}
    Stories         = @{}
    Tasks           = @{}
    Bugs            = @{}
    AllWorkItemIds  = @()
    Errors          = @()
}

$null = & ssLogIt.ps1 -Level Info -Message "Creating test hierarchy: $Description"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    try {
        $PatToken = Get-AzDoPatToken -Decrypt
    }
    catch {
        $msg = "PAT token retrieval failed. Provide -PatToken or set GMD_AZDO_MACHINE_WORKITEMSRW environment variable."
        $result.Errors += $msg
        & "$PSScriptRoot/ssLogIt.ps1" -Level Error -Message $msg
        return $result
    }
}

# Generate unique Epic title with timestamp
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$epicTitle = "TEST-$timestamp-$Description"

try {
    # Create Epic
    $null = & ssLogIt.ps1 -Level Debug -Message "Creating Epic: $epicTitle"
    $epic = & (Join-Path $SRC_DIR 'UpsertAzDoEpic.ps1') `
        -Organization $Organization `
        -Project $Project `
        -Title $epicTitle `
        -Description "Auto-generated test hierarchy for: $Description" `
        -PatToken $PatToken

    if ($null -eq $epic -or $null -eq $epic.id) {
        throw "Failed to create Epic"
    }

    $result.Epic = @{
        Id    = $epic.id
        Title = $epicTitle
        Url   = $epic.url
    }
    $result.AllWorkItemIds += $epic.id

    # Tag the Epic with "testWi"
    $null = & ssLogIt.ps1 -Level Debug -Message "Tagging Epic with 'testWi'"
    $null = & (Join-Path $SRC_DIR 'UpdateAzDoWorkItemTags.ps1') `
        -Organization $Organization `
        -Project $Project `
        -WorkItemId $epic.id `
        -Tags @("testWi") `
        -PatToken $PatToken

    $null = & ssLogIt.ps1 -Level Info -Message "Epic created with ID: $($epic.id)"

    # Helper function to create child work items
    function New-TestWorkItem {
        [CmdletBinding()]
        param(
            [string]$Type,  # 'Feature', 'Story', 'Task', 'Bug'
            [int]$ParentId,
            [string]$Title,
            [string]$Description = "",
            [int]$Effort = $null,
            [int]$StoryPoints = $null
        )

        try {
            $null = & ssLogIt.ps1 -Level Debug -Message "Creating $Type under parent $ParentId : $Title"

            # Determine parent parameter name based on type
            $parentParamName = switch ($Type) {
                'Feature'   { 'ParentEpicId' }
                'Story'     { 'ParentFeatureId' }
                'Task'      { 'ParentStoryId' }
                'Bug'       { 'ParentStoryId' }
                default     { throw "Unknown work item type: $Type" }
            }

            # Map type to script name
            $scriptNameMap = @{
                'Feature'   = 'UpsertAzDoFeature'
                'Story'     = 'UpsertAzDoStory'
                'Task'      = 'UpsertAzDoTask'
                'Bug'       = 'UpsertAzDoBug'
            }

            # Call appropriate Upsert script based on type
            $scriptName = $scriptNameMap[$Type]
            if ([string]::IsNullOrWhiteSpace($scriptName)) {
                throw "Unknown work item type: $Type"
            }

            $scriptPath = Join-Path $SRC_DIR "${scriptName}.ps1"

            if (-not (Test-Path $scriptPath)) {
                throw "Script not found: $scriptPath"
            }

            $params = @{
                Organization = $Organization
                Project      = $Project
                Title        = $Title
                PatToken     = $PatToken
                FailIfExist  = $true  # Ensure we create new items for tests
            }

            # Add parent parameter
            $params[$parentParamName] = $ParentId

            if (-not [string]::IsNullOrWhiteSpace($Description)) {
                $params.Description = $Description
            }

            # Add type-specific parameters
            switch ($Type) {
                'Feature' {
                    if ($null -ne $Effort) {
                        $params.Effort = $Effort
                    }
                }
                'Story' {
                    if ($null -ne $StoryPoints) {
                        $params.StoryPoints = $StoryPoints
                    }
                }
                'Task' {
                    # Tasks don't have Story Points or Effort in these scripts
                    # They use OriginalEstimate/RemainingWork/CompletedWork for time tracking
                }
                'Bug' {
                    # Bugs can have StoryPoints
                    if ($null -ne $StoryPoints) {
                        $params.StoryPoints = $StoryPoints
                    }
                }
            }

            $workItem = & $scriptPath @params

            if ($null -eq $workItem -or $null -eq $workItem.id) {
                throw "Failed to create $($Type): returned null or no id"
            }

            # Tag with "testWi"
            $null = & (Join-Path $SRC_DIR 'UpdateAzDoWorkItemTags.ps1') `
                -Organization $Organization `
                -Project $Project `
                -WorkItemId $workItem.id `
                -Tags @("testWi") `
                -PatToken $PatToken

            $result.AllWorkItemIds += $workItem.id

            return $workItem
        }
        catch {
            $msg = "Failed to create $Type '$Title': $_"
            $result.Errors += $msg
            & ssLogIt.ps1 -Level Error -Message $msg
            throw $_
        }
    }

    # Create Features
    if ($HierarchySpec.features) {
        $null = & ssLogIt.ps1 -PushStackLevel -Message "Creating Features:"

        foreach ($featureSpec in $HierarchySpec.features) {
            $feature = New-TestWorkItem `
                -Type "Feature" `
                -ParentId $epic.id `
                -Title $featureSpec.title `
                -Description $featureSpec.description `
                -Effort $featureSpec.effort

            $result.Features[$feature.fields.'System.Title'] = @{
                Id    = $feature.id
                Title = $feature.fields.'System.Title'
                Url   = $feature.url
            }

            $null = & ssLogIt.ps1 -Level Debug -Message "Feature created: $($feature.id)"

            # Create Stories under Feature
            if ($featureSpec.stories) {
                foreach ($storySpec in $featureSpec.stories) {
                    $story = New-TestWorkItem `
                        -Type "Story" `
                        -ParentId $feature.id `
                        -Title $storySpec.title `
                        -Description $storySpec.description `
                        -StoryPoints $storySpec.storyPoints

                    $result.Stories[$story.fields.'System.Title'] = @{
                        Id       = $story.id
                        Title    = $story.fields.'System.Title'
                        ParentId = $feature.id
                        Url      = $story.url
                    }

                    # Create Tasks under Story
                    if ($storySpec.tasks) {
                        foreach ($taskSpec in $storySpec.tasks) {
                            $task = New-TestWorkItem `
                                -Type "Task" `
                                -ParentId $story.id `
                                -Title $taskSpec.title `
                                -Effort $taskSpec.effort

                            $result.Tasks[$task.fields.'System.Title'] = @{
                                Id       = $task.id
                                Title    = $task.fields.'System.Title'
                                ParentId = $story.id
                                Url      = $task.url
                            }
                        }
                    }
                }
            }

            # Create Tasks directly under Feature (if specified)
            if ($featureSpec.tasks) {
                foreach ($taskSpec in $featureSpec.tasks) {
                    $task = New-TestWorkItem `
                        -Type "Task" `
                        -ParentId $feature.id `
                        -Title $taskSpec.title `
                        -Effort $taskSpec.effort

                    $result.Tasks[$task.fields.'System.Title'] = @{
                        Id       = $task.id
                        Title    = $task.fields.'System.Title'
                        ParentId = $feature.id
                        Url      = $task.url
                    }
                }
            }
        }

        $null = & ssLogIt.ps1 -PopStackLevel
    }

    # Create Bugs directly under Epic (if specified)
    if ($HierarchySpec.bugs) {
        $null = & ssLogIt.ps1 -PushStackLevel -Message "Creating Bugs:"

        foreach ($bugSpec in $HierarchySpec.bugs) {
            $bug = New-TestWorkItem `
                -Type "Bug" `
                -ParentId $epic.id `
                -Title $bugSpec.title `
                -Description $bugSpec.description

            $result.Bugs[$bug.fields.'System.Title'] = @{
                Id    = $bug.id
                Title = $bug.fields.'System.Title'
                Url   = $bug.url
            }
        }

        $null = & ssLogIt.ps1 -PopStackLevel
    }

    $result.Success = $true

    $null = & ssLogIt.ps1 -Level Info -Message "Test hierarchy created successfully with $($result.AllWorkItemIds.Count) work items"
    $null = & ssLogIt.ps1 -Level Info -Message "Epic ID: $($result.Epic.Id) | Features: $($result.Features.Count) | Stories: $($result.Stories.Count) | Tasks: $($result.Tasks.Count) | Bugs: $($result.Bugs.Count)"

    return $result
}
catch {
    $msg = "Failed to create test hierarchy: $_"
    $result.Errors += $msg
    & ssLogIt.ps1 -Level Error -Message $msg

    # Attempt cleanup on partial creation
    if ($null -ne $result.Epic -and $result.Epic.Id -gt 0) {
        $null = & ssLogIt.ps1 -Level Warn -Message "Attempting cleanup of partial hierarchy (Epic ID: $($result.Epic.Id))..."
        try {
            & (Join-Path $SRC_DIR 'RemoveAzDoEpic.ps1') `
                -Organization $Organization `
                -Project $Project `
                -EpicId $result.Epic.Id `
                -Force `
                -PatToken $PatToken
        }
        catch {
            $null = & ssLogIt.ps1 -Level Error -Message "Cleanup failed: $_"
        }
    }

    return $result
}
