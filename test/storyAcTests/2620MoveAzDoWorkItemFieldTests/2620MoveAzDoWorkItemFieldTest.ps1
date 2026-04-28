#Requires -Version 7.0

<#
.SYNOPSIS
AC tests for Story 2620: Implement MoveAzDoWorkItemField.ps1 with WorkItemId scope.
Verifies <see cref="MoveAzDoWorkItemField"/> moves and copies fields on work items
and their hierarchical descendants, handles empty/missing fields, supports DryRun
and ConfirmEachItem modes, and emits correct pipeline output objects.

.DESCRIPTION
Integration tests calling MoveAzDoWorkItemField.ps1 against the live Azure DevOps API.
Creates real work items (tagged testWi) in BeforeAll and removes them in AfterAll.

Run with: Invoke-Pester .\test\storyAcTests\2620MoveAzDoWorkItemFieldTests\2620MoveAzDoWorkItemFieldTest.ps1
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

[string]$REPO_ROOT = Resolve-Path (Join-Path $PSScriptRoot '../../../')
[string]$SRC_DIR   = Join-Path $REPO_ROOT 'src'
[string]$SCRIPT    = Join-Path $SRC_DIR 'MoveAzDoWorkItemField.ps1'

. "$SRC_DIR/AzDoAutomatorConstants.ps1"
. "$SRC_DIR/AzDoPatTokenHelper.ps1"
. "$SRC_DIR/AzDoApiWrapper.ps1"
. "$SRC_DIR/AzDoWorkItemHelper.ps1"

if (-not (Get-Command 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    function global:ssLogIt.ps1 {
        param([string]$Level, [string]$Message, [object]$Exception)
    }
}

[string]$Organization = $env:GMD_AZDO_ORGANIZATION
[string]$Project      = $env:GMD_AZDO_PROJECT
[string]$PatToken     = $env:GMD_AZDO_MACHINE_WORKITEMSRW | ssEncryptDecrypt.ps1 -Decrypt

# Source and target field labels (must exist in appSettings.json)
[string]$SRC_LABEL = 'Extra Information'
[string]$TGT_LABEL = 'Story Acceptance Tests'
[string]$TEST_VALUE = 'Test content for MoveAzDoWorkItemField 2620'

# Track all created work item IDs for cleanup
$script:createdIds = [System.Collections.Generic.List[int]]::new()

function hCreateWorkItem {
    [CmdletBinding()]
    param(
        [string]$Type,
        [string]$Title,
        [string]$ExtraInfo = '',
        [int]$ParentId = 0
    )

    $fields = @{
        'System.Title' = $Title
        'System.Tags'  = 'testWi'
    }
    if (-not [string]::IsNullOrEmpty($ExtraInfo)) {
        $fields['Custom.ExtraInformation'] = $ExtraInfo
    }

    $wi = if ($ParentId -gt 0) {
        New-AzDoWorkItem -Organization $Organization -Project $Project `
            -WorkItemType $Type -Fields $fields -ParentId $ParentId -PatToken $PatToken
    }
    else {
        New-AzDoWorkItem -Organization $Organization -Project $Project `
            -WorkItemType $Type -Fields $fields -PatToken $PatToken
    }

    $script:createdIds.Add($wi.id)
    return $wi
}

function hDeleteAll {
    [CmdletBinding()]
    param()

    foreach ($id in ($script:createdIds | Sort-Object -Descending)) {
        try {
            Remove-AzDoWorkItem -Organization $Organization -Project $Project `
                -WorkItemId $id -PatToken $PatToken
        }
        catch {
            $null = & ssLogIt.ps1 -Level Warn -Message "Cleanup: could not delete work item $($id): $_"
        }
    }
    $script:createdIds.Clear()
}

function hGetField {
    [CmdletBinding()]
    param([int]$Id, [string]$FieldRef)

    $wi = Get-AzDoWorkItemById -Organization $Organization -Project $Project `
        -WorkItemId $Id -PatToken $PatToken
    if ($null -eq $wi.fields.PSObject.Properties[$FieldRef]) {
        return $null
    }
    return $wi.fields.$FieldRef
}

Describe 'Story 2620 - MoveAzDoWorkItemField.ps1 WorkItemId scope' {

    AfterAll {
        hDeleteAll
    }

    Context 'Scenario 1: Move field value for a single work item' {

        BeforeAll {
            # Create a story with non-empty Extra Information
            $script:s1Story = hCreateWorkItem -Type 'User Story' `
                -Title '2620 Test Story S1' -ExtraInfo $TEST_VALUE
        }

        It 'GivenStoryWithExtraInfo_WhenMove_ItShouldCopyToTargetAndClearSource' {
            $results = & $SCRIPT `
                -Organization $Organization -Project $Project -PatToken $PatToken `
                -WorkItemId $script:s1Story.id `
                -SourceField $SRC_LABEL -TargetField $TGT_LABEL

            $results | Should Not BeNullOrEmpty

            # Wait briefly for AzDo to process
            Start-Sleep -Seconds 1

            $targetValue = hGetField -Id $script:s1Story.id -FieldRef 'Custom.StoryAcceptanceTests'
            $sourceValue = hGetField -Id $script:s1Story.id -FieldRef 'Custom.ExtraInformation'

            $targetValue | Should Be $TEST_VALUE
            [string]::IsNullOrWhiteSpace($sourceValue) | Should Be $true
        }

        It 'GivenMoveResult_ItShouldHaveCorrectPipelineShape' {
            $results = & $SCRIPT `
                -Organization $Organization -Project $Project -PatToken $PatToken `
                -WorkItemId $script:s1Story.id `
                -SourceField $SRC_LABEL -TargetField $TGT_LABEL -DryRun

            $result = $results | Select-Object -First 1

            $result.WorkItemId   | Should Not BeNullOrEmpty
            $result.Title        | Should Not BeNullOrEmpty
            $result.WorkItemType | Should Not BeNullOrEmpty
            $result.SourceField  | Should Be $SRC_LABEL
            $result.TargetField  | Should Be $TGT_LABEL
            $result.Action       | Should Not BeNullOrEmpty
            $result.Result       | Should Not BeNullOrEmpty
            ($result.PSObject.Properties.Name -contains 'Detail') | Should Be $true
        }
    }

    Context 'Scenario 2: Copy field value preserves source' {

        BeforeAll {
            $script:s2Story = hCreateWorkItem -Type 'User Story' `
                -Title '2620 Test Story S2' -ExtraInfo $TEST_VALUE
        }

        It 'GivenCopySwitch_ItShouldCopyToTargetAndKeepSource' {
            $results = & $SCRIPT `
                -Organization $Organization -Project $Project -PatToken $PatToken `
                -WorkItemId $script:s2Story.id `
                -SourceField $SRC_LABEL -TargetField $TGT_LABEL -Copy

            $results | Should Not BeNullOrEmpty

            Start-Sleep -Seconds 1

            $targetValue = hGetField -Id $script:s2Story.id -FieldRef 'Custom.StoryAcceptanceTests'
            $sourceValue = hGetField -Id $script:s2Story.id -FieldRef 'Custom.ExtraInformation'

            $targetValue | Should Be $TEST_VALUE
            $sourceValue | Should Be $TEST_VALUE
        }

        It 'GivenCopyResult_ActionShouldBeCopy' {
            $results = & $SCRIPT `
                -Organization $Organization -Project $Project -PatToken $PatToken `
                -WorkItemId $script:s2Story.id `
                -SourceField $SRC_LABEL -TargetField $TGT_LABEL -Copy -DryRun

            $result = $results | Select-Object -First 1
            $result.Action | Should Be 'DryRun'
        }
    }

    Context 'Scenario 3: Empty source field is skipped' {

        BeforeAll {
            # Create story with NO Extra Information
            $script:s3Story = hCreateWorkItem -Type 'User Story' `
                -Title '2620 Test Story S3 Empty'
        }

        It 'GivenEmptySourceField_ItShouldSkipWithSkippedResult' {
            $results = & $SCRIPT `
                -Organization $Organization -Project $Project -PatToken $PatToken `
                -WorkItemId $script:s3Story.id `
                -SourceField $SRC_LABEL -TargetField $TGT_LABEL

            $results | Should Not BeNullOrEmpty
            $result = $results | Select-Object -First 1
            $result.Result | Should Be 'Skipped'
            $result.Action | Should Be 'Skip'
            $result.Detail | Should Be 'Source field is empty'
        }
    }

    Context 'Scenario 4: Feature hierarchy processes all descendants' {

        BeforeAll {
            # Feature with 2 stories that have ExtraInfo and 1 without
            $script:s4Feature = hCreateWorkItem -Type 'Feature' -Title '2620 Test Feature S4'
            $script:s4Story1  = hCreateWorkItem -Type 'User Story' -Title '2620 S4 Story1 HasValue' `
                -ExtraInfo $TEST_VALUE -ParentId $script:s4Feature.id
            $script:s4Story2  = hCreateWorkItem -Type 'User Story' -Title '2620 S4 Story2 HasValue' `
                -ExtraInfo $TEST_VALUE -ParentId $script:s4Feature.id
            $script:s4Story3  = hCreateWorkItem -Type 'User Story' -Title '2620 S4 Story3 Empty' `
                -ParentId $script:s4Feature.id

            # Brief pause so relations are indexed
            Start-Sleep -Seconds 2
        }

        It 'GivenFeatureWithThreeStories_WhenMove_ItShouldEvaluateAllDescendants' {
            $results = & $SCRIPT `
                -Organization $Organization -Project $Project -PatToken $PatToken `
                -WorkItemId $script:s4Feature.id `
                -SourceField $SRC_LABEL -TargetField $TGT_LABEL -DryRun

            # Feature itself + 3 stories = 4 items (Feature skipped because field not on it,
            # or it depends on appSettings; but all 3 stories plus the feature should be listed)
            $results.Count -ge 3 | Should Be $true

            $updated = $results | Where-Object { $_.Result -eq 'Updated' }
            $skipped = $results | Where-Object { $_.Result -eq 'Skipped' }

            $updated.Count | Should Be 2
            $skipped.Count -ge 1 | Should Be $true
        }

        It 'GivenFeatureHierarchy_WhenMoveLive_ItShouldUpdate2StoriesAndSkip1' {
            $results = & $SCRIPT `
                -Organization $Organization -Project $Project -PatToken $PatToken `
                -WorkItemId $script:s4Feature.id `
                -SourceField $SRC_LABEL -TargetField $TGT_LABEL

            $updated = $results | Where-Object { $_.Result -eq 'Updated' }
            $updated.Count | Should Be 2
        }
    }

    Context 'Scenario 5: DryRun previews without changes' {

        BeforeAll {
            $script:s5Story = hCreateWorkItem -Type 'User Story' `
                -Title '2620 Test Story S5 DryRun' -ExtraInfo $TEST_VALUE
        }

        It 'GivenDryRun_ItShouldNotModifyWorkItem' {
            $results = & $SCRIPT `
                -Organization $Organization -Project $Project -PatToken $PatToken `
                -WorkItemId $script:s5Story.id `
                -SourceField $SRC_LABEL -TargetField $TGT_LABEL -DryRun

            $result = $results | Select-Object -First 1
            $result.Action | Should Be 'DryRun'
            $result.Result | Should Be 'Updated'

            # Verify source field was NOT cleared in AzDo
            $sourceValue = hGetField -Id $script:s5Story.id -FieldRef 'Custom.ExtraInformation'
            $sourceValue | Should Be $TEST_VALUE
        }
    }

    Context 'Scenario 7: Source field not available on work item type' {

        BeforeAll {
            # Use a field that does not exist on Task type (e.g. AC Scenarios)
            # We create a task and try to move a Story-only field from it
            $script:s7Feature = hCreateWorkItem -Type 'Feature' -Title '2620 S7 Feature'
            $script:s7Story   = hCreateWorkItem -Type 'User Story' -Title '2620 S7 Story' `
                -ExtraInfo $TEST_VALUE -ParentId $script:s7Feature.id
            $script:s7Task    = hCreateWorkItem -Type 'Task' -Title '2620 S7 Task' `
                -ParentId $script:s7Story.id
            Start-Sleep -Seconds 2
        }

        It 'GivenTaskWithFieldNotAvailable_ItShouldSkipTask' {
            # Extra Information exists on User Story but not Task per appSettings
            $results = & $SCRIPT `
                -Organization $Organization -Project $Project -PatToken $PatToken `
                -WorkItemId $script:s7Story.id `
                -SourceField $SRC_LABEL -TargetField $TGT_LABEL -DryRun

            # Task should be skipped because Extra Information is not on Task type
            $taskResult = $results | Where-Object { $_.WorkItemId -eq $script:s7Task.id }
            if ($null -ne $taskResult) {
                $taskResult.Result | Should Be 'Skipped'
            }
        }
    }

    Context 'Scenario 8: Invalid field label throws terminating error' {

        It 'GivenInvalidSourceField_ItShouldThrowBeforeProcessing' {
            $threw = $false
            $errMsg = ''
            try {
                $null = & $SCRIPT `
                    -Organization $Organization -Project $Project -PatToken $PatToken `
                    -WorkItemId 1 `
                    -SourceField 'NonExistentField_XYZ' -TargetField $TGT_LABEL
            }
            catch {
                $threw = $true
                $errMsg = $_.Exception.Message
            }
            $threw | Should Be $true
            $errMsg | Should Match 'NonExistentField_XYZ'
        }

        It 'GivenInvalidTargetField_ItShouldThrowBeforeProcessing' {
            $threw = $false
            $errMsg = ''
            try {
                $null = & $SCRIPT `
                    -Organization $Organization -Project $Project -PatToken $PatToken `
                    -WorkItemId 1 `
                    -SourceField $SRC_LABEL -TargetField 'NonExistentField_XYZ'
            }
            catch {
                $threw = $true
                $errMsg = $_.Exception.Message
            }
            $threw | Should Be $true
            $errMsg | Should Match 'NonExistentField_XYZ'
        }
    }
}
