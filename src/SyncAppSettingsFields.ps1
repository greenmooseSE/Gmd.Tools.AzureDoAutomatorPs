<#
.SYNOPSIS
Synchronize appSettings.json field definitions against the live Azure DevOps project.

.DESCRIPTION
Queries the Azure DevOps REST API for each known work item type (Epic, Feature, User Story,
Bug, Task) and compares the returned field definitions against the entries stored in
appSettings.json for the given organization and project.

Fields present in the API but absent from appSettings.json are added using the API-supplied
name, description, type, and readOnly values. Existing entries are never modified, preserving
any human-curated labels, descriptions, or readOnly overrides.

Use -DryRun to preview additions without writing to disk.
Use -Prune to also remove entries from appSettings.json whose referenceName is no longer
returned by the API (use with caution).

.PARAMETER Organization
The Azure DevOps organization name. Default: $env:GMD_AZDO_ORGANIZATION.

.PARAMETER Project
The Azure DevOps project name. Default: $env:GMD_AZDO_PROJECT.

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from
GMD_AZDO_MACHINE_WORKITEMSRW environment variable (expected to be encrypted).

.PARAMETER RepositoryRoot
Root directory containing appSettings.json. Default: parent of $PSScriptRoot.

.PARAMETER DryRun
Previews additions and removals without writing to appSettings.json.

.PARAMETER Prune
When specified, removes field entries whose referenceName is not returned by the API.

.OUTPUTS
One PSObject per change with properties: WorkItemType, ReferenceName, Label, ChangeType.
ChangeType is 'Add' or 'Remove'.

.EXAMPLE
Preview what fields would be added:
    .\SyncAppSettingsFields.ps1 -DryRun

Apply additions:
    .\SyncAppSettingsFields.ps1

Apply additions and remove stale entries:
    .\SyncAppSettingsFields.ps1 -Prune
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Organization,

    [Parameter(Mandatory = $false)]
    [string]$Project,

    [Parameter(Mandatory = $false)]
    [string]$PatToken,

    [Parameter(Mandatory = $false)]
    [string]$RepositoryRoot,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$Prune
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/AzDoAutomatorConstants.ps1"
. "$PSScriptRoot/AzDoPatTokenHelper.ps1"

if (-not (Get-Command -Name 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    throw "Required helper script 'ssLogIt.ps1' not found in PATH."
}

if ([string]::IsNullOrWhiteSpace($Organization)) {
    $Organization = [Environment]::GetEnvironmentVariable('GMD_AZDO_ORGANIZATION')
}
if ([string]::IsNullOrWhiteSpace($Organization)) {
    throw "Parameter 'Organization' is required. Provide via -Organization or set GMD_AZDO_ORGANIZATION."
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    $Project = [Environment]::GetEnvironmentVariable('GMD_AZDO_PROJECT')
}
if ([string]::IsNullOrWhiteSpace($Project)) {
    throw "Parameter 'Project' is required. Provide via -Project or set GMD_AZDO_PROJECT."
}

if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}

# ============================================================================
# Private helpers
# ============================================================================

# Fetches all fields for a given work item type from the Azure DevOps REST API,
# enriched with type and readOnly from the project-level field definitions.
function hGetApiFields {
    [CmdletBinding()]
    param(
        [string]$WorkItemType,
        [hashtable]$Headers,
        [hashtable]$FieldLookup
    )

    # URL-encode work item type name (e.g. "User Story" -> "User%20Story")
    $encodedType = [Uri]::EscapeDataString($WorkItemType)
    $uri = "https://dev.azure.com/$Organization/$Project/_apis/wit/workitemtypes/$encodedType/fields?api-version=7.1"

    $null = & ssLogIt.ps1 -Level Debug -Message "Querying API fields for ::FgCyan::$($WorkItemType)::FgDefault::..."

    $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $Headers -TimeoutSec 60 -ErrorAction Stop

    # Enrich each entry with type/readOnly/description from the project-level lookup
    $result = foreach ($f in $response.value) {
        $detail = if ($FieldLookup.ContainsKey($f.referenceName)) { $FieldLookup[$f.referenceName] } else { $null }
        [PSCustomObject]@{
            referenceName = $f.referenceName
            name          = $f.name
            description   = if ($null -ne $detail -and -not [string]::IsNullOrWhiteSpace($detail.description)) { $detail.description } else { '' }
            type          = if ($null -ne $detail) { $detail.type } else { 'string' }
            readOnly      = if ($null -ne $detail) { [bool]$detail.readOnly } else { $false }
        }
    }
    return $result
}

# ============================================================================
# Load appSettings.json
# ============================================================================

[string]$appSettingsPath = Join-Path $RepositoryRoot 'appSettings.json'

if (-not (Test-Path -Path $appSettingsPath)) {
    throw "appSettings.json not found at '$RepositoryRoot'."
}

$null = & ssLogIt.ps1 -Level Info -Message "Loading ::FgCyan::appSettings.json::FgDefault:: from '$RepositoryRoot'..."

$rawJson  = Get-Content -Path $appSettingsPath -Raw -Encoding UTF8 -ErrorAction Stop
$settings = $rawJson | ConvertFrom-Json -ErrorAction Stop

# Ensure org/project path exists
if ($null -eq $settings.organizations.$Organization) {
    throw "Organization '$Organization' not found in appSettings.json."
}
if ($null -eq $settings.organizations.$Organization.projects.$Project) {
    throw "Project '$Project' not found under organization '$Organization' in appSettings.json."
}

$projectNode = $settings.organizations.$Organization.projects.$Project

if ($null -eq $projectNode.PSObject.Properties['fields']) {
    throw "No 'fields' node found under organizations.$Organization.projects.$Project in appSettings.json."
}

$fieldsNode = $projectNode.fields

# ============================================================================
# Build auth header and process each work item type
# ============================================================================

$headers = New-AzDoAuthHeader -PatToken $PatToken

# Fetch the project-level field definitions once (carries type, readOnly, description)
$null = & ssLogIt.ps1 -Level Info -Message "Fetching all field definitions for project '::FgCyan::$($Project)::FgDefault::'..."
$allFieldsUri = "https://dev.azure.com/$Organization/$Project/_apis/wit/fields?api-version=7.1"
$allFieldsResponse = Invoke-RestMethod -Uri $allFieldsUri -Method Get -Headers $headers -TimeoutSec 60 -ErrorAction Stop

[hashtable]$fieldLookup = @{}
foreach ($f in $allFieldsResponse.value) {
    $fieldLookup[$f.referenceName] = $f
}
$null = & ssLogIt.ps1 -Level Debug -Message "Loaded ::FgCyan::$($fieldLookup.Count)::FgDefault:: field definitions from project."

[string[]]$knownTypes = @('Epic', 'Feature', 'User Story', 'Bug', 'Task')
[System.Collections.Generic.List[object]]$changes = [System.Collections.Generic.List[object]]::new()

foreach ($wiType in $knownTypes) {
    $null = & ssLogIt.ps1 -Level Info -Message "Processing work item type: ::FgCyan::$($wiType)::FgDefault::"

    $apiFields = hGetApiFields -WorkItemType $wiType -Headers $headers -FieldLookup $fieldLookup

    # Get the existing appSettings entries for this type (array, may be absent)
    $typeKey = $wiType
    $existing = if ($null -ne $fieldsNode.PSObject.Properties[$typeKey]) {
        @($fieldsNode.$typeKey)
    } else {
        @()
    }

    $existingRefNames = @($existing | Select-Object -ExpandProperty referenceName)

    # ----- Additions -----
    foreach ($apiField in $apiFields) {
        if ($existingRefNames -contains $apiField.referenceName) {
            continue
        }

        $newEntry   = [PSCustomObject]@{
            referenceName = $apiField.referenceName
            label         = $apiField.name
            description   = $apiField.description
            type          = $apiField.type
            readOnly      = $apiField.readOnly
        }

        $null = & ssLogIt.ps1 -Level Info -Message "  ::FgGreen::+ Add::FgDefault:: ::FgYellow::$($apiField.referenceName)::FgDefault:: ('$($apiField.name)') [$($apiField.type)]"

        if (-not $DryRun) {
            $existing += $newEntry
        }

        $changes.Add([PSCustomObject]@{
            WorkItemType  = $wiType
            ReferenceName = $apiField.referenceName
            Label         = $apiField.name
            ChangeType    = 'Add'
        })
    }

    # ----- Pruning (optional) -----
    if ($Prune) {
        $apiRefNames = @($apiFields | Select-Object -ExpandProperty referenceName)
        $toRemove    = $existing | Where-Object { $apiRefNames -notcontains $_.referenceName }

        foreach ($stale in $toRemove) {
            $null = & ssLogIt.ps1 -Level Info -Message "  ::FgRed::- Remove::FgDefault:: ::FgYellow::$($stale.referenceName)::FgDefault:: ('$($stale.label)')"

            $changes.Add([PSCustomObject]@{
                WorkItemType  = $wiType
                ReferenceName = $stale.referenceName
                Label         = $stale.label
                ChangeType    = 'Remove'
            })
        }

        if (-not $DryRun) {
            $existing = @($existing | Where-Object { $apiRefNames -contains $_.referenceName })
        }
    }

    # Write back updated list for this type (only when not DryRun)
    if (-not $DryRun) {
        $fieldsNode.$typeKey = $existing
    }
}

# ============================================================================
# Write appSettings.json
# ============================================================================

if ($DryRun) {
    $addCount    = ($changes | Where-Object { $_.ChangeType -eq 'Add' }).Count
    $removeCount = ($changes | Where-Object { $_.ChangeType -eq 'Remove' }).Count
    $null = & ssLogIt.ps1 -Level Info -Message "::FgYellow::[DryRun]::FgDefault:: ::FgGreen::$($addCount)::FgDefault:: field(s) would be added, ::FgRed::$($removeCount)::FgDefault:: would be removed. No changes written."
} else {
    $null = & ssLogIt.ps1 -Level Info -Message "Writing updated ::FgCyan::appSettings.json::FgDefault::..."
    $settings | ConvertTo-Json -Depth 20 | Set-Content -Path $appSettingsPath -Encoding UTF8 -NoNewline
    $addCount    = ($changes | Where-Object { $_.ChangeType -eq 'Add' }).Count
    $removeCount = ($changes | Where-Object { $_.ChangeType -eq 'Remove' }).Count
    $null = & ssLogIt.ps1 -Level Info -Message "::FgGreen::✅ Sync complete::FgDefault::: ::FgGreen::$($addCount)::FgDefault:: field(s) added, ::FgRed::$($removeCount)::FgDefault:: removed."
}

return $changes
