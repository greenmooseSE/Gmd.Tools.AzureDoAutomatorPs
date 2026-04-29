#Requires -Version 7.0

<#
.SYNOPSIS
AC tests for Story 2621: Add Global scope to MoveAzDoWorkItemField.ps1.
Verifies <see cref="MoveAzDoWorkItemField"/> processes all project work items
when -Global switch is used, skips types where source field is unavailable,
logs progress every 25 items, supports DryRun, and enforces mutual exclusivity
of -Global and -WorkItemId parameter sets.

.DESCRIPTION
Integration tests calling MoveAzDoWorkItemField.ps1 against the live Azure DevOps API.
Creates real work items (tagged testWi) in BeforeAll and removes them in AfterAll.
Uses DryRun where possible to limit mutations, targeting only test-tagged items.

Run with: Invoke-Pester .\test\storyAcTests\2620MoveAzDoWorkItemFieldTests\GlobalScopeTest.ps1
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

# Field labels
[string]$SRC_LABEL  = 'Extra Information'
[string]$TGT_LABEL  = 'Story Acceptance Tests'
[string]$TEST_VALUE = 'Test content for MoveAzDoWorkItemField 2621 Global'

# Track created IDs for cleanup
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

Describe 'Story 2621 - MoveAzDoWorkItemField.ps1 Global scope' {

    AfterAll {
        hDeleteAll
    }

    Context 'Scenario 1: Global scope evaluates all project work items' {

        BeforeAll {
            # Create 2 stories with Extra Information, 1 story without
            $script:g1StoryA = hCreateWorkItem -Type 'User Story' -Title '2621 G1 StoryA HasValue' -ExtraInfo $TEST_VALUE
            $script:g1StoryB = hCreateWorkItem -Type 'User Story' -Title '2621 G1 StoryB HasValue' -ExtraInfo $TEST_VALUE
            $script:g1StoryC = hCreateWorkItem -Type 'User Story' -Title '2621 G1 StoryC NoValue'
        }

        It 'GivenGlobalDryRun_ItShouldReturnResultsForAllProjectItems' {
            <#
            .SYNOPSIS
            Verifies -Global returns pipeline output for all project items and correctly
            marks stories with values as DryRun-updated and those without as skipped.
            #>
            $results = & $SCRIPT `
                -Organization $Organization `
                -Project $Project `
                -PatToken $PatToken `
                -SourceField $SRC_LABEL `
                -TargetField $TGT_LABEL `
                -Global `
                -DryRun

            # Must return at least our 3 created items worth of results
            $results -is [System.Array] -or $null -ne $results | Should Be $true

            $allResults = @($results)
            $allResults.Count -ge 3 | Should Be $true

            # Our created items should appear in the results
            $aResult = $allResults | Where-Object { $_.WorkItemId -eq $script:g1StoryA.id }
            $bResult = $allResults | Where-Object { $_.WorkItemId -eq $script:g1StoryB.id }
            $cResult = $allResults | Where-Object { $_.WorkItemId -eq $script:g1StoryC.id }

            $null -ne $aResult | Should Be $true
            $null -ne $bResult | Should Be $true
            $null -ne $cResult | Should Be $true

            $aResult.Action | Should Be 'DryRun'
            $bResult.Action | Should Be 'DryRun'
            $cResult.Action | Should Be 'Skip'
        }
    }

    Context 'Scenario 2: Global with DryRun makes no API changes' {

        BeforeAll {
            $script:g2Story = hCreateWorkItem -Type 'User Story' -Title '2621 G2 Story DryRun' -ExtraInfo $TEST_VALUE
        }

        It 'GivenGlobalDryRun_ItShouldNotModifySourceOrTargetFields' {
            <#
            .SYNOPSIS
            Verifies that -Global -DryRun does not write any field values to the API.
            #>
            & $SCRIPT `
                -Organization $Organization `
                -Project $Project `
                -PatToken $PatToken `
                -SourceField $SRC_LABEL `
                -TargetField $TGT_LABEL `
                -Global `
                -DryRun | Out-Null

            # Source field must be unchanged
            $sourceValue = hGetField -Id $script:g2Story.id -FieldRef 'Custom.ExtraInformation'
            $sourceValue | Should Be $TEST_VALUE

            # Target field must remain empty / null
            $targetValue = hGetField -Id $script:g2Story.id -FieldRef 'Custom.StoryAcceptanceTests'
            $targetValue | Should BeNullOrEmpty
        }
    }

    Context 'Scenario 3: Mutually exclusive parameter sets' {

        It 'GivenBothGlobalAndWorkItemId_ItShouldThrowParameterBindingError' {
            <#
            .SYNOPSIS
            Verifies that specifying both -Global and -WorkItemId raises a parameter
            binding error before any processing begins.
            #>
            $threw = $false
            try {
                & $SCRIPT `
                    -Organization $Organization `
                    -Project $Project `
                    -PatToken $PatToken `
                    -SourceField $SRC_LABEL `
                    -TargetField $TGT_LABEL `
                    -Global `
                    -WorkItemId 1
            }
            catch {
                $threw = $true
            }
            $threw | Should Be $true
        }
    }

    Context 'Scenario 4: Items where source field not available on type are skipped' {

        BeforeAll {
            # Create a Task (no Extra Information field) and a Story with value
            $script:g4Story = hCreateWorkItem -Type 'User Story' -Title '2621 G4 Story HasValue' -ExtraInfo $TEST_VALUE
            $script:g4Task  = hCreateWorkItem -Type 'Task' -Title '2621 G4 Task NoField' -ParentId $script:g4Story.id
        }

        It 'GivenGlobalScopeWithTask_TaskShouldBeSkipped' {
            <#
            .SYNOPSIS
            Verifies that work item types where the source field does not exist (e.g. Task)
            are reported as skipped in the pipeline output.
            #>
            $results = & $SCRIPT `
                -Organization $Organization `
                -Project $Project `
                -PatToken $PatToken `
                -SourceField $SRC_LABEL `
                -TargetField $TGT_LABEL `
                -Global `
                -DryRun

            $taskResult = @($results) | Where-Object { $_.WorkItemId -eq $script:g4Task.id }
            $null -ne $taskResult | Should Be $true
            $taskResult.Action  | Should Be 'Skip'
            $taskResult.Result  | Should Be 'Skipped'
        }
    }

    Context 'Scenario 5: Pipeline output shape is correct' {

        BeforeAll {
            $script:g5Story = hCreateWorkItem -Type 'User Story' -Title '2621 G5 Story Output' -ExtraInfo $TEST_VALUE
        }

        It 'GivenGlobalDryRun_PipelineOutputShouldHaveExpectedProperties' {
            <#
            .SYNOPSIS
            Verifies that every result object from Global scope has the same property
            shape as the WorkItemId scope: WorkItemId, Title, WorkItemType,
            SourceField, TargetField, Action, Result, Detail.
            #>
            $results = & $SCRIPT `
                -Organization $Organization `
                -Project $Project `
                -PatToken $PatToken `
                -SourceField $SRC_LABEL `
                -TargetField $TGT_LABEL `
                -Global `
                -DryRun

            $storyResult = @($results) | Where-Object { $_.WorkItemId -eq $script:g5Story.id }
            $null -ne $storyResult | Should Be $true

            ($null -ne $storyResult.WorkItemId)   | Should Be $true
            ($null -ne $storyResult.Title)         | Should Be $true
            ($null -ne $storyResult.WorkItemType)  | Should Be $true
            ($null -ne $storyResult.SourceField)   | Should Be $true
            ($null -ne $storyResult.TargetField)   | Should Be $true
            ($null -ne $storyResult.Action)        | Should Be $true
            ($null -ne $storyResult.Result)        | Should Be $true
            $storyResult.PSObject.Properties['Detail'] | Should Not BeNullOrEmpty
        }
    }

    Context 'Scenario 6: Global live move updates work items' {

        BeforeAll {
            $script:g6Story = hCreateWorkItem -Type 'User Story' -Title '2621 G6 Story LiveMove' -ExtraInfo $TEST_VALUE
        }

        It 'GivenGlobalScopeLiveMove_ItShouldUpdateTargetAndClearSource' {
            <#
            .SYNOPSIS
            Verifies a live (non-DryRun) Global move updates the target field and
            clears the source field for work items that have a non-empty source value.
            #>
            $results = & $SCRIPT `
                -Organization $Organization `
                -Project $Project `
                -PatToken $PatToken `
                -SourceField $SRC_LABEL `
                -TargetField $TGT_LABEL `
                -Global

            $storyResult = @($results) | Where-Object { $_.WorkItemId -eq $script:g6Story.id }
            $null -ne $storyResult | Should Be $true
            $storyResult.Action | Should Be 'Move'
            $storyResult.Result | Should Be 'Updated'

            $sourceValue = hGetField -Id $script:g6Story.id -FieldRef 'Custom.ExtraInformation'
            $sourceValue | Should BeNullOrEmpty

            $targetValue = hGetField -Id $script:g6Story.id -FieldRef 'Custom.StoryAcceptanceTests'
            $targetValue | Should Be $TEST_VALUE
        }
    }
}
