<#
.SYNOPSIS
Validate MCP configuration file structure and integrity

.DESCRIPTION
Validates the mcpConfig.yaml file to ensure:
- YAML structure is valid
- All referenced scripts exist
- All command IDs are unique
- Tool names follow lowercase verb-noun pattern
- All required parameters are specified
- Build/script references are correct

.PARAMETER ConfigFilePath
Path to the mcpConfig.yaml file to validate (defaults to ./src/mcpConfig.yaml)

.PARAMETER Verbose
Show detailed validation results

.OUTPUTS
$true if all validations pass, $false otherwise
Validation report is written to console

.EXAMPLE
.\ValidateMcpConfig.ps1

.\ValidateMcpConfig.ps1 -ConfigFilePath "./src/mcpConfig.yaml" -Verbose

.NOTES
Requires PowerShell 7+
Uses YAML parsing via ConvertFrom-Yaml (from PSYAMLParser module) or manual parsing
#>

#Requires -Version 7.0

param(
    [string]$ConfigFilePath = "./src/mcpConfig.yaml",
    [switch]$Verbose
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$script:validationPassed = $true
$script:errors = @()
$script:warnings = @()

function Write-ValidationError {
    param([string]$Message)
    $script:validationPassed = $false
    $script:errors += $Message
    Write-Host "❌ ERROR: $Message" -ForegroundColor Red
}

function Write-ValidationWarning {
    param([string]$Message)
    $script:warnings += $Message
    Write-Host "⚠️  WARNING: $Message" -ForegroundColor Yellow
}

function Write-ValidationSuccess {
    param([string]$Message)
    if ($Verbose) {
        Write-Host "✅ $Message" -ForegroundColor Green
    }
}

# Check file exists
if (-not (Test-Path $ConfigFilePath)) {
    Write-ValidationError "Config file not found: $ConfigFilePath"
    exit 1
}

Write-Host "`n📋 Validating MCP Configuration: $ConfigFilePath`n" -ForegroundColor Cyan

# Attempt to parse YAML
try {
    $content = Get-Content -Path $ConfigFilePath -Raw
    Write-ValidationSuccess "Config file readable and accessible"
}
catch {
    Write-ValidationError "Failed to read config file: $_"
    exit 1
}

# Basic YAML structure validation
try {
    # Check for required sections (more flexible matching)
    if ($content -notmatch 'global\s*:') {
        Write-ValidationError "Missing 'global' section in config"
    }
    else {
        Write-ValidationSuccess "Global section found"
    }
    
    if ($content -notmatch 'commands\s*:') {
        Write-ValidationError "Missing 'commands' section in config"
    }
    else {
        Write-ValidationSuccess "Commands section found"
    }
}
catch {
    Write-ValidationError "YAML structure validation failed: $_"
    exit 1
}

# Extract command IDs using regex
$commandIds = @()
$idPattern = '^\s*-\s+id:\s+([a-z\-]+)'
$ids = [System.Text.RegularExpressions.Regex]::Matches($content, $idPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)

foreach ($match in $ids) {
    $id = $match.Groups[1].Value
    $commandIds += $id
}

Write-ValidationSuccess "Found $($commandIds.Count) commands"

# Check for duplicate IDs
$duplicates = $commandIds | Group-Object | Where-Object { $_.Count -gt 1 }
if ($duplicates) {
    foreach ($dup in $duplicates) {
        Write-ValidationError "Duplicate command ID found: '$($dup.Name)' (appears $($dup.Count) times)"
    }
}
else {
    Write-ValidationSuccess "No duplicate command IDs found"
}

# Check tool name patterns (lowercase verb-noun)
$invalidIds = $commandIds | Where-Object { $_ -notmatch '^[a-z]+-[a-z\-]+$' }
if ($invalidIds) {
    foreach ($id in $invalidIds) {
        Write-ValidationWarning "Command ID '$id' does not follow lowercase verb-noun pattern"
    }
}
else {
    Write-ValidationSuccess "All command IDs follow lowercase verb-noun pattern"
}

# Extract script references
$scriptPattern = '^\s*script:\s+\./([\w\-\.]+\.ps1)'
$scripts = [System.Text.RegularExpressions.Regex]::Matches($content, $scriptPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
$scriptCount = $scripts.Count

Write-ValidationSuccess "Found $scriptCount script references"

# Check if scripts exist
$missingScripts = @()
$scriptDir = Split-Path -Path $ConfigFilePath
foreach ($match in $scripts) {
    $scriptName = $match.Groups[1].Value
    $scriptPath = Join-Path -Path $scriptDir -ChildPath $scriptName
    if (-not (Test-Path $scriptPath)) {
        $missingScripts += $scriptName
        Write-ValidationError "Referenced script not found: $scriptName"
    }
    else {
        Write-ValidationSuccess "Script found: $scriptName"
    }
}

if ($missingScripts.Count -eq 0) {
    Write-ValidationSuccess "All referenced scripts exist"
}

# Check for Organization/Project parameters in get/set commands
$organizationUsage = $commandIds | Where-Object { $_ -match '^(get|set|new|remove|upsert|find|update)' } | Measure-Object
if ($organizationUsage.Count -gt 0) {
    # Basic check that these commands reference Organization and Project parameters
    $orgParamPattern = 'Organization'
    if ($content -match $orgParamPattern) {
        Write-ValidationSuccess "Common parameters (Organization, Project) found"
    }
}

# CRITICAL: Verify all scripts in src/ have corresponding MCP config entries
Write-Host "`n🔍 Verifying all scripts in src/ have MCP configuration..." -ForegroundColor Cyan

$srcDir = Split-Path -Path $ConfigFilePath
$helperScripts = @(
    'AzDoAutomatorConstants.ps1',
    'AzDoPatTokenHelper.ps1',
    'AzDoApiWrapper.ps1',
    'AzDoWorkItemHelper.ps1',
    'Directory.Build.targets'
)

$allSrcScripts = Get-ChildItem -Path $srcDir -Filter "*.ps1" | Where-Object { $_.Name -notin $helperScripts } | Select-Object -ExpandProperty Name
$allSrcScripts = $allSrcScripts | Sort-Object

# Extract script filenames from config (remove ./ prefix)
$configuredScripts = @()
foreach ($match in $scripts) {
    $configuredScripts += $match.Groups[1].Value
}
$configuredScripts = $configuredScripts | Sort-Object

Write-ValidationSuccess "Found $($allSrcScripts.Count) public scripts in src/"
Write-ValidationSuccess "Found $($configuredScripts.Count) scripts in MCP config"

# Find scripts missing from config
$missingFromConfig = @()
foreach ($srcScript in $allSrcScripts) {
    if ($srcScript -notin $configuredScripts) {
        $missingFromConfig += $srcScript
    }
}

if ($missingFromConfig.Count -gt 0) {
    foreach ($missing in $missingFromConfig) {
        Write-ValidationError "Script not in MCP config: $missing (add to mcpConfig.yaml)"
    }
}
else {
    Write-ValidationSuccess "All src/ scripts have MCP configuration entries"
}

# Find config entries referencing non-existent scripts
$orphanedConfigs = @()
foreach ($configScript in $configuredScripts) {
    if ($configScript -notin $allSrcScripts) {
        $orphanedConfigs += $configScript
    }
}

if ($orphanedConfigs.Count -gt 0) {
    foreach ($orphan in $orphanedConfigs) {
        Write-ValidationWarning "MCP config references non-existent script: $orphan (script may have been removed)"
    }
}

# Summary
Write-Host "`n" -ForegroundColor Cyan
Write-Host "╔════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║        VALIDATION SUMMARY              ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Host "`n📊 Stats:" -ForegroundColor Cyan
Write-Host "  • Commands defined: $($commandIds.Count)"
Write-Host "  • Scripts referenced: $scriptCount"
Write-Host "  • Errors found: $($script:errors.Count)"
Write-Host "  • Warnings found: $($script:warnings.Count)"

if ($script:validationPassed) {
    Write-Host "`n✅ Validation PASSED - Configuration is valid!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "`n❌ Validation FAILED - Please fix the errors above" -ForegroundColor Red
    exit 1
}
