<#
.SYNOPSIS
Load and cache state configuration from JSON files scoped by organization and project

.DESCRIPTION
Loads state configuration from repository root using organization and project naming pattern.
Configuration defines which states are writable for each work item type.
Results are cached in memory to avoid repeated file I/O.

Configuration file format: azdoStateConfig-{organization}-{project}.json
Example filename: azdoStateConfig-falco-it-GMD.json

If configuration file is missing, sensible defaults are applied.

Configuration structure:
{
  "writableStates": {
    "Epic": ["New", "Active"],
    "Feature": ["New", "Active", "Closed"],
    "Story": ["New", "Active", "Done"],
    "Task": ["New", "Active", "Closed"],
    "Bug": ["New", "Active", "Closed"]
  }
}

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
      "Feature" = @("New", "Active", "Closed")
      "Story" = @("New", "Active", "Done")
      "Task" = @("New", "Active", "Closed")
      "Bug" = @("New", "Active", "Closed")
    }
  }

.EXAMPLE
# Load configuration for organization and project
$config = .\LoadStateConfiguration.ps1 -Organization "falco-it" -Project "GMD"
$writableStates = $config.writableStates
$epicStates = $writableStates.Epic

# Force reload from file (ignore cache)
$config = .\LoadStateConfiguration.ps1 -Organization "falco-it" -Project "GMD" -Force

# Use specific repository root
$config = .\LoadStateConfiguration.ps1 -Organization "falco-it" -Project "GMD" -RepositoryRoot "C:\repo"

.NOTES
- First load caches configuration in memory via script scope variable
- Returns defaults if configuration file is missing
- Configuration files should be stored in version control
- Support for environment variable overrides via future enhancement
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

    # Build configuration filename
    $configFileName = "azdoStateConfig-$Organization-$Project.json"
    $configFilePath = Join-Path $RepositoryRoot $configFileName

    # Check if configuration file exists
    if (Test-Path -Path $configFilePath) {
        ssLogIt.ps1 -Level Info -Message "Loading state configuration from $configFilePath"
        
        try {
            $configContent = Get-Content -Path $configFilePath -Raw -Encoding UTF8 -ErrorAction Stop
            $config = $configContent | ConvertFrom-Json -ErrorAction Stop
            
            # Validate configuration structure
            if ($null -eq $config.writableStates) {
                throw "Configuration is missing 'writableStates' property"
            }
            
            ssLogIt.ps1 -Level Info -Message "State configuration loaded successfully from $configFileName"
            
            # Cache the configuration
            $script:_StateConfigurationCache[$cacheKey] = $config
            return $config
        }
        catch {
            ssLogIt.ps1 -Level Error -Message "Failed to load configuration from $configFilePath. Error: $_"
            throw
        }
    }
    else {
        # File not found, use defaults
        ssLogIt.ps1 -Level Info -Message "Configuration file $configFileName not found at $RepositoryRoot. Applying sensible defaults."
        $config = Get-DefaultStateConfiguration
        
        # Cache the default configuration
        $script:_StateConfigurationCache[$cacheKey] = $config
        return $config
    }
}

# Main execution
$result = Invoke-LoadStateConfiguration -Organization $Organization -Project $Project -RepositoryRoot $RepositoryRoot -SkipCache $Force

ssLogIt.ps1 -Level Info -Message "State configuration loaded for $Organization/$Project with $(($result.writableStates | Measure-Object).Count) work item types defined"

return $result
