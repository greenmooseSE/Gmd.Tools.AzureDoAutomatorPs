#Requires -Version 7.0

<#
.SYNOPSIS
Shared validation helpers for Upsert scripts: field readOnly check and state writability check.

.DESCRIPTION
Dot-source this script from Upsert scripts to gain access to:
- Assert-FieldsNotReadOnly: validates each key in a -Fields hashtable is writable per appSettings.json
- Assert-StateIsWritable: validates a -State value is in the writable states list per appSettings.json

Both functions are no-ops when appSettings.json config is unavailable, ensuring backward compat.
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Assert-FieldsNotReadOnly {
    <#
    .SYNOPSIS
    Fails fast if any key in the provided -Fields hashtable is a readOnly field per appSettings.json.

    .PARAMETER Organization The Azure DevOps organization name.
    .PARAMETER Project The Azure DevOps project name.
    .PARAMETER WorkItemType The work item type (e.g. 'User Story', 'Feature').
    .PARAMETER Fields The hashtable keyed by referenceName to validate.
    #>
    param(
        [string]$Organization,
        [string]$Project,
        [string]$WorkItemType,
        [hashtable]$Fields
    )

    if ($null -eq $Fields -or $Fields.Count -eq 0) {
        return
    }
    if ([string]::IsNullOrWhiteSpace($Organization) -or [string]::IsNullOrWhiteSpace($Project)) {
        return
    }

    [array]$fieldDefs = @()
    try {
        $fieldDefs = @(& "$PSScriptRoot/LoadFieldConfiguration.ps1" -Organization $Organization -Project $Project -WorkItemType $WorkItemType -ErrorAction SilentlyContinue)
    } catch {
        # Config unavailable: skip validation
        return
    }

    if ($fieldDefs.Count -eq 0) {
        return
    }

    $lookup = @{}
    foreach ($f in $fieldDefs) {
        $lookup[$f.referenceName] = $f
    }

    foreach ($key in $Fields.Keys) {
        if ($lookup.ContainsKey($key) -and $lookup[$key].readOnly -eq $true) {
            throw "Field '$($key)' is readOnly and cannot be used in write operations."
        }
    }
}

function Assert-StateIsWritable {
    <#
    .SYNOPSIS
    Fails fast if the provided -State value is not in the writable states list per appSettings.json.

    .PARAMETER Organization The Azure DevOps organization name.
    .PARAMETER Project The Azure DevOps project name.
    .PARAMETER WorkItemType The work item type (e.g. 'User Story', 'Feature').
    .PARAMETER State The state name to validate.
    #>
    param(
        [string]$Organization,
        [string]$Project,
        [string]$WorkItemType,
        [string]$State
    )

    if ([string]::IsNullOrWhiteSpace($State)) {
        return
    }
    if ([string]::IsNullOrWhiteSpace($Organization) -or [string]::IsNullOrWhiteSpace($Project)) {
        return
    }

    $stateConfig = $null
    try {
        $stateConfig = & "$PSScriptRoot/LoadStateConfiguration.ps1" -Organization $Organization -Project $Project -ErrorAction SilentlyContinue
    } catch {
        # Config unavailable: skip validation
        return
    }

    if ($null -eq $stateConfig) {
        return
    }

    # LoadStateConfiguration returns writableStates keyed by short type name (Story, not User Story)
    $typeKey = switch ($WorkItemType) {
        'User Story' { 'Story' }
        default { $WorkItemType }
    }

    $writableStates = $stateConfig.writableStates[$typeKey]
    if ($null -eq $writableStates) {
        # Type not in config: skip validation
        return
    }

    if ($writableStates -notcontains $State) {
        throw "State '$($State)' is not a writable state for $($WorkItemType). Writable states are: $($writableStates -join ', ')"
    }
}
