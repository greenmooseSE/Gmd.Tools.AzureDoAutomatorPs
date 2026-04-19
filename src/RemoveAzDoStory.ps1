<#
.SYNOPSIS
Delete an Azure DevOps Story work item, optionally including its child Tasks.

.DESCRIPTION
This is a DESTRUCTIVE operation that deletes a Story work item. Requires confirmation at runtime
unless -Force switch is used.

Without -Recursive, only the Story itself is deleted. If the Story has child Tasks they will become
orphaned (still exist but with no parent). A warning is shown when child Tasks are detected.

With -Recursive, all child Tasks are deleted first, then the Story itself is deleted.

Before deletion, displays all work items to be deleted for review.

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER StoryId
The Story work item ID to delete (required)

.PARAMETER Recursive
Switch: If specified, recursively deletes all child Tasks before deleting the Story.
Without this switch only the Story itself is deleted and child Tasks are orphaned.

.PARAMETER Force
Switch: If specified, skips confirmation prompt. Use with caution!

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
Summary hashtable with deleted work item count and details

.EXAMPLE
Delete Story only (children become orphaned):
    $result = .\RemoveAzDoStory.ps1 -Organization "myorg" -Project "myproject" -StoryId 100

Delete Story and all child Tasks:
    $result = .\RemoveAzDoStory.ps1 -Organization "myorg" -Project "myproject" -StoryId 100 -Recursive

Delete Story and all child Tasks without confirmation:
    $result = .\RemoveAzDoStory.ps1 -Organization "myorg" -Project "myproject" -StoryId 100 -Recursive -Force

.NOTES
- *** DESTRUCTIVE OPERATION ***
- Requires Azure DevOps REST API access
- Requires PAT token with work items read/write scope
- Will not proceed without user confirmation unless -Force is specified
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $false)]
    [string]$Organization,

    [Parameter(Mandatory = $false)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [int]$StoryId,

    [switch]$Recursive,

    [switch]$Force,

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

if (-not (Test-AzDoWorkItemIdValid $StoryId)) {
    Write-Error "Parameter 'StoryId' must be a positive integer."
}

$null = & ssLogIt.ps1 -Level Info -Message "*** DESTRUCTIVE OPERATION: Preparing to delete Story (ID: $StoryId)$(if ($Recursive) { ' and all children' }) ***"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    # Get the Story itself
    $story = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $StoryId -PatToken $PatToken

    if ($null -eq $story) {
        Write-Error "Story with ID $StoryId not found."
    }

    $storyTitle = $story.fields.'System.Title'

    # Get child tasks
    $null = & ssLogIt.ps1 -Level Debug -Message "Retrieving child work items..."
    $children = Get-AzDoAllDescendants -Organization $Organization -Project $Project -WorkItemId $StoryId -PatToken $PatToken

    if ($Recursive) {
        $totalItemsToDelete = $children.Count + 1

        $null = & ssLogIt.ps1 -Level Warn -Message "The following $totalItemsToDelete work item(s) will be deleted:"
        $null = & ssLogIt.ps1 -Level Warn -Message "  Story: ::FgRed::$storyTitle::FgDefault:: (ID: $StoryId)"

        if ($children.Count -gt 0) {
            $null = & ssLogIt.ps1 -PushStackLevel -Message "Children:"
            foreach ($childId in $children.Keys) {
                $child = $children[$childId]
                $childTitle = $child.fields.'System.Title'
                $childType = $child.fields.'System.WorkItemType'
                $null = & ssLogIt.ps1 -Level Warn -Message "  [$childType] $childTitle (ID: $childId)"
            }
            $null = & ssLogIt.ps1 -PopStackLevel
        }
    }
    else {
        if ($children.Count -gt 0) {
            $null = & ssLogIt.ps1 -Level Warn -Message "WARNING: Story ::FgYellow::$storyTitle::FgDefault:: (ID: $StoryId) has $($children.Count) child work item(s) that will become ORPHANED (no parent) after deletion."
            $null = & ssLogIt.ps1 -Level Warn -Message "Use -Recursive to delete all children as well."
        }
        $null = & ssLogIt.ps1 -Level Warn -Message "The following 1 work item will be deleted:"
        $null = & ssLogIt.ps1 -Level Warn -Message "  Story: ::FgRed::$storyTitle::FgDefault:: (ID: $StoryId)"
    }

    # Prompt for confirmation if not forced
    if (-not $Force) {
        $null = & ssLogIt.ps1 -Level Warn -Message ""
        if ($Recursive) {
            Write-Host "Are you SURE you want to DELETE this Story and $($children.Count) child item(s)?" -ForegroundColor Red
        }
        else {
            Write-Host "Are you SURE you want to DELETE this Story?" -ForegroundColor Red
        }
        Write-Host "This action CANNOT be undone!" -ForegroundColor Red
        [string]$response = Read-Host "Type 'YES' to confirm deletion, any other input to cancel"

        if ($response -ne 'YES') {
            $null = & ssLogIt.ps1 -Level Info -Message "Deletion cancelled by user"
            return @{
                Cancelled    = $true
                DeletedCount = 0
                SkippedCount = 0
            }
        }
    }

    $null = & ssLogIt.ps1 -Level Info -Message "Proceeding with deletion..."

    [int]$deletedCount = 0
    [int]$skippedCount = 0

    if ($Recursive -and $children.Count -gt 0) {
        $null = & ssLogIt.ps1 -PushStackLevel -Message "Deleting child work items..."
        foreach ($childId in $children.Keys) {
            try {
                $child = $children[$childId]
                $childTitle = $child.fields.'System.Title'

                Remove-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $childId -PatToken $PatToken

                $null = & ssLogIt.ps1 -Level Debug -Message "Deleted: $childTitle (ID: $childId)"
                $deletedCount++
            }
            catch {
                $null = & ssLogIt.ps1 -Level Error -Message "Failed to delete work item $childId : $_" -Exception $_
                throw
            }
        }
        $null = & ssLogIt.ps1 -PopStackLevel
    }

    # Delete the Story itself
    try {
        Remove-AzDoWorkItem -Organization $Organization -Project $Project -WorkItemId $StoryId -PatToken $PatToken
        $null = & ssLogIt.ps1 -Level Debug -Message "Deleted Story: $storyTitle (ID: $StoryId)"
        $deletedCount++
    }
    catch {
        $null = & ssLogIt.ps1 -Level Error -Message "Failed to delete Story $StoryId : $_" -Exception $_
        throw
    }

    $null = & ssLogIt.ps1 -Level Info -Message "Deletion complete: ::FgGreen::$deletedCount deleted::FgDefault::, ::FgRed::$skippedCount skipped::FgDefault::"

    return @{
        Cancelled    = $false
        DeletedCount = $deletedCount
        SkippedCount = $skippedCount
    }
}
catch {
    $null = & ssLogIt.ps1 -Level Error -Message "Failed to delete Story: $_" -Exception $_
    Write-Error $_
    throw
}
