<#
.SYNOPSIS
Load field definitions from appSettings.json for a given organization, project, and work item type.

.DESCRIPTION
Reads appSettings.json from the repository root and returns the array of field definition
objects for the specified organization, project, and work item type.

Each field object has the following properties:
- referenceName : Azure DevOps REST API reference name (e.g. "System.Title")
- label         : Human-readable label used in markdown (e.g. "Title")
- description   : Short description of the field (default: "")
- type          : Data type: string | integer | double | boolean | html | identity | treePath | dateTime
- readOnly      : true if the field must not be written via the API

If appSettings.json is missing or the org/project/type path does not exist, returns an empty array.
Results are cached per (org + project + type) to avoid repeated file I/O.

.PARAMETER Organization
The Azure DevOps organization name (required). Default: $env:GMD_AZDO_ORGANIZATION

.PARAMETER Project
The Azure DevOps project name (required). Default: $env:GMD_AZDO_PROJECT

.PARAMETER WorkItemType
Work item type name as used in appSettings.json: Epic, Feature, User Story, Bug, Task (required)

.PARAMETER RepositoryRoot
Root directory containing appSettings.json. Default: current working directory.

.PARAMETER Force
If specified, bypasses cache and reloads from file.

.OUTPUTS
Array of PSObject — each object has referenceName, label, description, type, readOnly.

.EXAMPLE
$fields = .\LoadFieldConfiguration.ps1 -Organization "falco-it" -Project "GMD" -WorkItemType "User Story"
$fields | Where-Object { -not $_.readOnly } | Select-Object label, referenceName

.NOTES
- Returns an empty array (not null) when no definitions are found.
- The cache is scoped to the script session; use -Force to bypass it.
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $false)]
    [string]$Organization,

    [Parameter(Mandatory = $false)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Epic', 'Feature', 'User Story', 'Bug', 'Task')]
    [string]$WorkItemType,

    [Parameter(Mandatory = $false)]
    [string]$RepositoryRoot = (Get-Location).Path,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'AzDoAutomatorConstants.ps1')

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

# Cache keyed by org/project/type
if (-not (Test-Path variable:script:_FieldConfigCache)) {
    $script:_FieldConfigCache = @{}
}

$cacheKey = "$Organization|$Project|$WorkItemType"

if (-not $Force -and $script:_FieldConfigCache.ContainsKey($cacheKey)) {
    ssLogIt.ps1 -Level Debug -Message "Field definitions for $WorkItemType ($Organization/$Project) returned from cache"
    return $script:_FieldConfigCache[$cacheKey]
}

$appSettingsPath = Join-Path $RepositoryRoot 'appSettings.json'

if (-not (Test-Path -Path $appSettingsPath)) {
    ssLogIt.ps1 -Level Debug -Message "appSettings.json not found at $RepositoryRoot; returning empty field definitions"
    $script:_FieldConfigCache[$cacheKey] = @()
    return @()
}

try {
    $raw = Get-Content -Path $appSettingsPath -Raw -Encoding UTF8 -ErrorAction Stop
    $settings = $raw | ConvertFrom-Json -ErrorAction Stop
}
catch {
    ssLogIt.ps1 -Level Debug -Message "Failed to parse appSettings.json: $_; returning empty field definitions"
    $script:_FieldConfigCache[$cacheKey] = @()
    return @()
}

$orgEntry = $settings.organizations.$Organization
if ($null -eq $orgEntry) {
    ssLogIt.ps1 -Level Debug -Message "Organization '$Organization' not found in appSettings.json; returning empty field definitions"
    $script:_FieldConfigCache[$cacheKey] = @()
    return @()
}

$projectEntry = $orgEntry.projects.$Project
if ($null -eq $projectEntry) {
    ssLogIt.ps1 -Level Debug -Message "Project '$Project' not found in appSettings.json for org '$Organization'; returning empty field definitions"
    $script:_FieldConfigCache[$cacheKey] = @()
    return @()
}

$fieldsDef = $projectEntry.fields
if ($null -eq $fieldsDef) {
    ssLogIt.ps1 -Level Debug -Message "No field definitions in appSettings.json for $Organization/$Project; returning empty"
    $script:_FieldConfigCache[$cacheKey] = @()
    return @()
}

$typeFields = $fieldsDef.$WorkItemType
if ($null -eq $typeFields) {
    ssLogIt.ps1 -Level Debug -Message "No field definitions for work item type '$WorkItemType' in appSettings.json; returning empty"
    $script:_FieldConfigCache[$cacheKey] = @()
    return @()
}

ssLogIt.ps1 -Level Debug -Message "Loaded $($typeFields.Count) field definitions for $WorkItemType ($Organization/$Project)"
$script:_FieldConfigCache[$cacheKey] = $typeFields
return $typeFields
