<#
.SYNOPSIS
Run comprehensive system test for Azure DevOps automation scripts

.DESCRIPTION
Tests all automation scripts end-to-end against a real Azure DevOps instance.
Creates an Epic and child work items, tests all property setters and operations,
then outputs a summary of results. Does NOT test RemoveAzDoEpic (destructive operation).

Fails if Epic with specified title already exists (to avoid duplicate test data).

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER EpicTitle
Title for the test Epic to create. Script fails if Epic with this title already exists.
Default: "WIP System Test Epic"

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from FALCOIT_AZDO_PAT_WORKITEMSREADWRITE
environment variable (expected to be encrypted).

.OUTPUTS
Hashtable with test results summary including:
- CreatedEpicId: ID of created test Epic
- CreatedFeatureId: ID of created test Feature
- CreatedStoryId: ID of created test Story
- TestsPassed: Count of successful operations
- TestsFailed: Count of failed operations
- DetailsObj: Detailed results for each operation

.EXAMPLE
Run against FalcoIt with defaults:
    $results = .\RunSystemTest.ps1 -Organization "falco-it" -Project "GMD"

Custom epic title:
    $results = .\RunSystemTest.ps1 -Organization "falco-it" -Project "GMD" -EpicTitle "Custom Test Epic"

With explicit PAT token:
    $results = .\RunSystemTest.ps1 -Organization "falco-it" -Project "GMD" -PatToken $myToken

.NOTES
- Requires all automation scripts and helper modules in src directory
- Fails fast if Epic with specified title already exists
- Does not test RemoveAzDoEpic (destructive operation)
- Creates test Epic, Feature, and Story work items (cleanup requires manual deletion or RemoveAzDoEpic)
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$Project,

    [string]$EpicTitle = "WIP System Test Epic",

    [string]$PatToken
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Script directory
[string]$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

# Import modules
. "$SCRIPT_DIR/AzDoAutomatorConstants.ps1"
. "$SCRIPT_DIR/AzDoPatTokenHelper.ps1"
. "$SCRIPT_DIR/AzDoApiWrapper.ps1"
. "$SCRIPT_DIR/AzDoWorkItemHelper.ps1"

# Validate ssLogIt.ps1 exists
if (-not (Get-Command -Name 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    Write-Error "Required helper script 'ssLogIt.ps1' not found in PATH. Ensure helper scripts are available."
}

# Validate parameters
if ([string]::IsNullOrWhiteSpace($Organization)) {
    Write-Error "Parameter 'Organization' cannot be empty."
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    Write-Error "Parameter 'Project' cannot be empty."
}

if ([string]::IsNullOrWhiteSpace($EpicTitle)) {
    Write-Error "Parameter 'EpicTitle' cannot be empty."
}

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

# Test results tracking
[hashtable]$results = @{
    CreatedEpicId    = 0
    CreatedFeatureId = 0
    CreatedStoryId   = 0
    TestsPassed      = 0
    TestsFailed      = 0
    Details          = @()
}

function Log-TestResult {
    param(
        [string]$TestName,
        [bool]$Success,
        [string]$Message
    )

    $result = @{
        TestName = $TestName
        Success  = $Success
        Message  = $Message
    }

    $results.Details += $result

    if ($Success) {
        $results.TestsPassed++
        $null = & ssLogIt.ps1 -Level Info -Message "✓ $TestName : ::FgGreen::$Message::FgDefault::"
    }
    else {
        $results.TestsFailed++
        $null = & ssLogIt.ps1 -Level Error -Message "✗ $TestName : ::FgRed::$Message::FgDefault::"
    }
}

$null = & ssLogIt.ps1 -Level Info -Message "=========================================="
$null = & ssLogIt.ps1 -Level Info -Message "Starting System Test"
$null = & ssLogIt.ps1 -Level Info -Message "=========================================="
$null = & ssLogIt.ps1 -Level Info -Message "Organization: ::FgGreen::$Organization::FgDefault::"
$null = & ssLogIt.ps1 -Level Info -Message "Project: ::FgGreen::$Project::FgDefault::"
$null = & ssLogIt.ps1 -Level Info -Message "Epic Title: ::FgGreen::$EpicTitle::FgDefault::"
$null = & ssLogIt.ps1 -PushStackLevel -Message "Running Tests"

try {
    # ========================================================================
    # Test 1: Verify Epic doesn't already exist
    # ========================================================================
    $null = & ssLogIt.ps1 -Level Info -Message "Test 1: Checking if Epic already exists..."

    try {
        $existingEpic = & "$SCRIPT_DIR/FindAzDoItemByTitle.ps1" -Organization $Organization -Project $Project -Title $EpicTitle -Type $script:WORKITEM_TYPE_EPIC -PatToken $PatToken

        if ($null -ne $existingEpic) {
            Log-TestResult "Epic Existence Check" $false "Epic with title '$EpicTitle' already exists (ID: $($existingEpic.id)). Cannot proceed with test."
            throw "Epic already exists. Cannot create duplicate."
        }

        Log-TestResult "Epic Existence Check" $true "Confirmed Epic does not exist"
    }
    catch {
        Log-TestResult "Epic Existence Check" $false $_.Exception.Message
        throw;
    }

    # ========================================================================
    # Test 2: Create Epic
    # ========================================================================
    $null = & ssLogIt.ps1 -Level Info -Message "Test 2: Creating Epic..."

    try {
        $epic = & "$SCRIPT_DIR/NewAzDoEpic.ps1" -Organization $Organization -Project $Project -Title $EpicTitle -Description "Automated system test epic" -PatToken $PatToken

        if ($null -eq $epic -or $null -eq $epic.id) {
            throw "Failed to create Epic"
        }

        $results.CreatedEpicId = $epic.id
        Log-TestResult "Create Epic" $true "Created Epic with ID $($epic.id)"
    }
    catch {
        Log-TestResult "Create Epic" $false $_.Exception.Message
        throw;
    }

    # ========================================================================
    # Test 3: Create Feature under Epic
    # ========================================================================
    $null = & ssLogIt.ps1 -Level Info -Message "Test 3: Creating Feature under Epic..."

    try {
        $featureTitle = "$EpicTitle - Feature"
        $feature = & "$SCRIPT_DIR/NewAzDoFeature.ps1" -Organization $Organization -Project $Project -Title $featureTitle -ParentEpicId $epic.id -Description "Test feature" -PatToken $PatToken

        if ($null -eq $feature -or $null -eq $feature.id) {
            throw "Failed to create Feature"
        }

        $results.CreatedFeatureId = $feature.id
        Log-TestResult "Create Feature" $true "Created Feature with ID $($feature.id)"
    }
    catch {
        Log-TestResult "Create Feature" $false $_.Exception.Message
        throw;
    }

    # ========================================================================
    # Test 4: Create Story under Feature
    # ========================================================================
    $null = & ssLogIt.ps1 -Level Info -Message "Test 4: Creating Story under Feature..."

    try {
        $storyTitle = "$EpicTitle - Story"
        $story = & "$SCRIPT_DIR/NewAzDoStory.ps1" -Organization $Organization -Project $Project -Title $storyTitle -ParentFeatureId $feature.id `
            -Description "Test story description" -AcceptanceCriteria "Test AC" -StoryPoints 3 -PatToken $PatToken

        if ($null -eq $story -or $null -eq $story.id) {
            throw "Failed to create Story"
        }

        $results.CreatedStoryId = $story.id
        Log-TestResult "Create Story" $true "Created Story with ID $($story.id)"
    }
    catch {
        Log-TestResult "Create Story" $false $_.Exception.Message
        throw;
    }

    # ========================================================================
    # Test 5: Get Work Item
    # ========================================================================
    $null = & ssLogIt.ps1 -Level Info -Message "Test 5: Retrieving work item..."

    try {
        $retrieved = & "$SCRIPT_DIR/GetAzDoWorkItem.ps1" -Organization $Organization -Project $Project -WorkItemId $story.id -PatToken $PatToken

        if ($null -eq $retrieved -or $retrieved.id -ne $story.id) {
            throw "Failed to retrieve Story or ID mismatch"
        }

        Log-TestResult "Get Work Item" $true "Retrieved Story with ID $($retrieved.id)"
    }
    catch {
        Log-TestResult "Get Work Item" $false $_.Exception.Message
    }

    # ========================================================================
    # Test 6: Set Description
    # ========================================================================
    $null = & ssLogIt.ps1 -Level Info -Message "Test 6: Setting work item description..."

    try {
        $newDesc = "Updated description at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $updated = & "$SCRIPT_DIR/SetAzDoWorkItemDescription.ps1" -Organization $Organization -Project $Project -WorkItemId $story.id -Description $newDesc -PatToken $PatToken

        if ($null -eq $updated -or $updated.fields.'System.Description' -ne $newDesc) {
            throw "Description not updated correctly"
        }

        Log-TestResult "Set Description" $true "Description updated successfully"
    }
    catch {
        Log-TestResult "Set Description" $false $_.Exception.Message
    }

    # ========================================================================
    # Test 7: Set Acceptance Criteria
    # ========================================================================
    $null = & ssLogIt.ps1 -Level Info -Message "Test 7: Setting acceptance criteria..."

    try {
        $newAC = "Updated AC at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $updated = & "$SCRIPT_DIR/SetAzDoAcceptanceCriteria.ps1" -Organization $Organization -Project $Project -WorkItemId $story.id -AcceptanceCriteria $newAC -PatToken $PatToken

        if ($null -eq $updated -or $updated.fields.'Microsoft.VSTS.Common.AcceptanceCriteria' -ne $newAC) {
            throw "Acceptance Criteria not updated correctly"
        }

        Log-TestResult "Set Acceptance Criteria" $true "Acceptance Criteria updated successfully"
    }
    catch {
        Log-TestResult "Set Acceptance Criteria" $false $_.Exception.Message
    }

    # ========================================================================
    # Test 8: Set Story Points
    # ========================================================================
    $null = & ssLogIt.ps1 -Level Info -Message "Test 8: Setting story points..."

    try {
        $newSP = 8
        $updated = & "$SCRIPT_DIR/SetAzDoStoryPoints.ps1" -Organization $Organization -Project $Project -WorkItemId $story.id -StoryPoints $newSP -PatToken $PatToken

        if ($null -eq $updated -or $updated.fields.'Microsoft.VSTS.Scheduling.StoryPoints' -ne $newSP) {
            throw "Story Points not updated correctly"
        }

        Log-TestResult "Set Story Points" $true "Story Points updated to $newSP"
    }
    catch {
        Log-TestResult "Set Story Points" $false $_.Exception.Message
    }

    # ========================================================================
    # Test 9: Set Tags (Replace mode)
    # ========================================================================
    $null = & ssLogIt.ps1 -Level Info -Message "Test 9: Setting tags (Replace mode)..."

    try {
        $tags = @("test", "system-test", "automated")
        $updated = & "$SCRIPT_DIR/SetAzDoWorkItemTags.ps1" -Organization $Organization -Project $Project -WorkItemId $story.id -Tags $tags -Mode Replace -PatToken $PatToken

        if ($null -eq $updated) {
            throw "Failed to set tags"
        }

        Log-TestResult "Set Tags (Replace)" $true "Tags set: $($tags -join ', ')"
    }
    catch {
        Log-TestResult "Set Tags (Replace)" $false $_.Exception.Message
    }

    # ========================================================================
    # Test 10: Set Tags (Add mode)
    # ========================================================================
    $null = & ssLogIt.ps1 -Level Info -Message "Test 10: Setting tags (Add mode)..."

    try {
        $addTags = @("additional")
        $updated = & "$SCRIPT_DIR/SetAzDoWorkItemTags.ps1" -Organization $Organization -Project $Project -WorkItemId $story.id -Tags $addTags -Mode Add -PatToken $PatToken

        if ($null -eq $updated) {
            throw "Failed to add tags"
        }

        Log-TestResult "Set Tags (Add)" $true "Tags added: $($addTags -join ', ')"
    }
    catch {
        Log-TestResult "Set Tags (Add)" $false $_.Exception.Message
    }

    # ========================================================================
    # Test 11: Create Hierarchy from Markdown
    # ========================================================================
    $null = & ssLogIt.ps1 -Level Info -Message "Test 11: Creating hierarchy from markdown..."

    try {
        # Create temporary markdown file
        $tempMarkdownPath = Join-Path $env:TEMP "system-test-hierarchy-$(Get-Random).md"

        $markdownContent = @"
## Test Feature from Markdown
- Story A
  - AC: First acceptance criterion
  - SP: 3
- Story B
  - AC: Second acceptance criterion
  - SP: 5
"@

        Set-Content -LiteralPath $tempMarkdownPath -Value $markdownContent -Encoding UTF8

        # Run hierarchy creation
        $hierarchyResult = & "$SCRIPT_DIR/NewAzDoHierarchyFromMarkdown.ps1" -Organization $Organization -Project $Project `
            -MarkdownFilePath $tempMarkdownPath -EpicId $epic.id -PatToken $PatToken

        if ($null -eq $hierarchyResult -or $hierarchyResult.CreatedItems.Count -lt 3) {
            throw "Hierarchy creation did not produce expected results"
        }

        Log-TestResult "Create Hierarchy from Markdown" $true "Created $($hierarchyResult.CreatedItems.Count) work items from markdown"

        # Cleanup
        Remove-Item -LiteralPath $tempMarkdownPath -Force -ErrorAction SilentlyContinue
    }
    catch {
        Log-TestResult "Create Hierarchy from Markdown" $false $_.Exception.Message
        # Cleanup on error
        if (Test-Path -LiteralPath $tempMarkdownPath) {
            Remove-Item -LiteralPath $tempMarkdownPath -Force -ErrorAction SilentlyContinue
        }
    }

    # ========================================================================
    # Test 12: Update Existing Story
    # ========================================================================
    $null = & ssLogIt.ps1 -Level Info -Message "Test 12: Updating existing Story..."

    try {
        $updated = & "$SCRIPT_DIR/NewAzDoStory.ps1" -Organization $Organization -Project $Project -Title "$EpicTitle - Story" `
            -ParentFeatureId $feature.id -Description "Updated via UpdateExisting" -StoryPoints 5 -UpdateExisting -PatToken $PatToken

        if ($null -eq $updated -or $updated.id -ne $story.id) {
            throw "Failed to update existing Story or ID mismatch"
        }

        Log-TestResult "Update Existing Story" $true "Story updated with UpdateExisting switch"
    }
    catch {
        Log-TestResult "Update Existing Story" $false $_.Exception.Message
    }
}
catch {
    $null = & ssLogIt.ps1 -PopStackLevel -Message "Tests Stopped"
    $null = & ssLogIt.ps1 -Level Error -Message "::FgRed::System test failed::FgDefault::" -Exception $_
    Write-Error $_.Exception.Message
    throw
}

$null = & ssLogIt.ps1 -PopStackLevel

# ========================================================================
# Output Summary
# ========================================================================

$null = & ssLogIt.ps1 -Level Info -Message "=========================================="
$null = & ssLogIt.ps1 -Level Info -Message "System Test Summary"
$null = & ssLogIt.ps1 -Level Info -Message "=========================================="
$null = & ssLogIt.ps1 -Level Info -Message "Tests Passed: ::FgGreen::$($results.TestsPassed)::FgDefault::"
$null = & ssLogIt.ps1 -Level Info -Message "Tests Failed: ::FgRed::$($results.TestsFailed)::FgDefault::"
$null = & ssLogIt.ps1 -Level Info -Message ""
$null = & ssLogIt.ps1 -Level Info -Message "Created Work Items:"
$null = & ssLogIt.ps1 -Level Info -Message "  Epic ID: ::FgGreen::$($results.CreatedEpicId)::FgDefault::"
$null = & ssLogIt.ps1 -Level Info -Message "  Feature ID: ::FgGreen::$($results.CreatedFeatureId)::FgDefault::"
$null = & ssLogIt.ps1 -Level Info -Message "  Story ID: ::FgGreen::$($results.CreatedStoryId)::FgDefault::"
$null = & ssLogIt.ps1 -Level Info -Message ""

if ($results.TestsFailed -gt 0) {
    $null = & ssLogIt.ps1 -Level Warn -Message "Some tests failed. Review details above."
}
else {
    $null = & ssLogIt.ps1 -Level Info -Message "::FgGreen::All tests passed!::FgDefault::"
}

$null = & ssLogIt.ps1 -Level Info -Message "=========================================="

return $results
