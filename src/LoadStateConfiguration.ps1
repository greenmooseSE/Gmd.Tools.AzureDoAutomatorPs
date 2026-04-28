<#
.SYNOPSIS
Load and cache state configuration from JSON files scoped by organization and project

.DESCRIPTION
Loads state configuration from repository root. Supports two configuration formats:

1. Unified appSettings.json (preferred): organizations.{org}.projects.{project}.states.{WorkItemType}
   Contains state objects with name, category, and readOnly flag.
   States in "Completed" or "Removed" categories are readOnly; all others are writable.

Results are cached in memory to avoid repeated file I/O.

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER RepositoryRoot
Root directory where configuration files are stored. If not provided, uses current working directory.
Default: current working directory (Get-Location)

.PARAMETER Force
If specified, ignores cache and reloads configuration from file

.OUTPUTS
PSObject with structure:
  @{
    writableStates = @{
      "Epic" = @("New", "Active")
      "Feature" = @("New", "Active", "Planning")
      "Story" = @("New", "Design", "Under Development")
      "Task" = @("New", "Active")
      "Bug" = @("New", "Under Development")
    }
  }

.EXAMPLE
$config = .\LoadStateConfiguration.ps1 -Organization "falco-it" -Project "GMD"
$writableStates = $config.writableStates
$epicStates = $writableStates.Epic

# Force reload from file (ignore cache)
$config = .\LoadStateConfiguration.ps1 -Organization "falco-it" -Project "GMD" -Force

# Use specific repository root
$config = .\LoadStateConfiguration.ps1 -Organization "falco-it" -Project "GMD" -RepositoryRoot "C:\repo"

.NOTES
- First load caches configuration in memory via script scope variable
- Reads from appSettings.json; returns built-in defaults if not present or org/project not found
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$Project,

    [Parameter(Mandatory = $false)]
    [string]$RepositoryRoot = (Get-Location).Path,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Load helper scripts
. (Join-Path $PSScriptRoot "AzDoAutomatorConstants.ps1")

# Cache variable to store loaded configurations
if (-not (Test-Path variable:script:_StateConfigurationCache)) {
    $script:_StateConfigurationCache = @{}
}

function Get-DefaultStateConfiguration {
    <#
    .SYNOPSIS
    Returns sensible defaults for state configuration
    
    By default, only New and Active states are writable. Done and Closed states
    should never be modified during export-import operations as they represent
    terminal states that require manual completion in Azure DevOps.
    #>
    return @{
        writableStates = @{
            "Epic"    = @("New", "Active")
            "Feature" = @("New", "Active")
            "Story"   = @("New", "Active")
            "Task"    = @("New", "Active")
            "Bug"     = @("New", "Active")
        }
    }
}

function ConvertFrom-AppSettingsStates {
    <#
    .SYNOPSIS
    Converts appSettings.json state definitions for an org/project into writableStates hashtable.
    Returns $null if the org/project path is not found in the provided settings object.
    #>
    param(
        [object]$AppSettings,
        [string]$Organization,
        [string]$Project
    )

    $orgEntry = $AppSettings.organizations.$Organization
    if ($null -eq $orgEntry) {
        return $null
    }

    $projectEntry = $orgEntry.projects.$Project
    if ($null -eq $projectEntry) {
        return $null
    }

    $statesDef = $projectEntry.states
    if ($null -eq $statesDef) {
        return $null
    }

    $writableStates = @{}
    $statesDef.PSObject.Properties | ForEach-Object {
        $workItemType = $_.Name
        $stateObjects = $_.Value
        $writableList = @($stateObjects | Where-Object { $_.readOnly -eq $false } | ForEach-Object { $_.name })
        # Normalize key: appSettings uses "User Story" but legacy uses "Story" — keep both names to preserve compat
        $writableStates[$workItemType] = $writableList
    }

    # Add "Story" alias if "User Story" is defined (legacy callers may use "Story" as the key)
    if ($writableStates.ContainsKey('User Story') -and -not $writableStates.ContainsKey('Story')) {
        $writableStates['Story'] = $writableStates['User Story']
    }

    return @{ writableStates = $writableStates }
}

function Invoke-LoadStateConfiguration {
    [CmdletBinding()]
    param(
        [string]$Organization,
        [string]$Project,
        [string]$RepositoryRoot,
        [bool]$SkipCache = $false
    )

    $cacheKey = "$Organization-$Project"

    # Check cache first
    if (-not $SkipCache -and $script:_StateConfigurationCache.ContainsKey($cacheKey)) {
        ssLogIt.ps1 -Level Debug -Message "Configuration for $Organization/$Project found in cache"
        return $script:_StateConfigurationCache[$cacheKey]
    }

    # --- Attempt 1: read from unified appSettings.json ---
    $appSettingsPath = Join-Path $RepositoryRoot 'appSettings.json'
    if (Test-Path -Path $appSettingsPath) {
        ssLogIt.ps1 -Level Debug -Message "Found appSettings.json at $appSettingsPath; attempting to load state config from it"
        try {
            $appSettingsContent = Get-Content -Path $appSettingsPath -Raw -Encoding UTF8 -ErrorAction Stop
            $appSettings = $appSettingsContent | ConvertFrom-Json -ErrorAction Stop
            $config = ConvertFrom-AppSettingsStates -AppSettings $appSettings -Organization $Organization -Project $Project
            if ($null -ne $config) {
                ssLogIt.ps1 -Level Info -Message "State configuration loaded from appSettings.json for $Organization/$Project"
                $script:_StateConfigurationCache[$cacheKey] = $config
                return $config
            }
            ssLogIt.ps1 -Level Debug -Message "appSettings.json does not contain state definitions for $Organization/$Project; using defaults"
        }
        catch {
            ssLogIt.ps1 -Level Debug -Message "Failed to parse appSettings.json: $_. Using defaults."
        }
    }

    # --- Fallback: built-in defaults ---
    ssLogIt.ps1 -Level Info -Message "No configuration found for $Organization/$Project at $RepositoryRoot. Applying sensible defaults."
    $config = Get-DefaultStateConfiguration

    $script:_StateConfigurationCache[$cacheKey] = $config
    return $config
}

# Main execution
$result = Invoke-LoadStateConfiguration -Organization $Organization -Project $Project -RepositoryRoot $RepositoryRoot -SkipCache $Force

ssLogIt.ps1 -Level Info -Message "State configuration loaded for $Organization/$Project with $(($result.writableStates | Measure-Object).Count) work item types defined"

return $result
