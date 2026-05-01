<#
.SYNOPSIS
Export an Azure DevOps work item hierarchy to a new plan markdown file.

.DESCRIPTION
Fetches the full hierarchy for an Epic, Feature, or User Story from Azure DevOps,
converts it to the standard plan markdown format, and writes it to a file on disk.

When -OutputPath is not supplied the file is auto-named using the convention:
    docs/plans/plan-{id}-{type}{CamelCaseTitle}.md
where {type} is one of: epic, feat, story.

The resolved output file path is written to the pipeline on success.

.PARAMETER WorkItemId
ID of the Epic, Feature, or User Story to export. Mandatory.

.PARAMETER Organization
Azure DevOps organization name. Defaults to GMD_AZDO_ORGANIZATION environment variable.

.PARAMETER Project
Azure DevOps project name. Defaults to GMD_AZDO_PROJECT environment variable.

.PARAMETER Pat
PAT token for authentication. If omitted, auto-retrieved from the encrypted
GMD_AZDO_MACHINE_WORKITEMSRW environment variable.

.PARAMETER OutputPath
Full output file path. If omitted, the path is auto-generated from the work item
ID, type, and title under docs/plans/.

.PARAMETER Overwrite
When set, allows overwriting an existing file. If not set and the target file
already exists, the script throws an error.

.OUTPUTS
[string] The resolved output file path.

.EXAMPLE
Export Epic 1577 to an auto-named plan file:
    .\ExportAzDoToMarkdown.ps1 -WorkItemId 1577

Export Feature 2000 to a specific path:
    .\ExportAzDoToMarkdown.ps1 -WorkItemId 2000 -OutputPath "C:/tmp/my-plan.md"
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [int]$WorkItemId,

    [Parameter(Mandatory = $false)]
    [string]$Organization,

    [Parameter(Mandatory = $false)]
    [string]$Project,

    [Parameter(Mandatory = $false)]
    [string]$Pat,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [switch]$Overwrite
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

# Apply environment variable defaults
if ([string]::IsNullOrWhiteSpace($Organization)) {
    $Organization = [Environment]::GetEnvironmentVariable('GMD_AZDO_ORGANIZATION')
    if ([string]::IsNullOrWhiteSpace($Organization)) {
        Write-Error "Parameter 'Organization' is required. Provide via -Organization or set GMD_AZDO_ORGANIZATION environment variable."
    }
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    $Project = [Environment]::GetEnvironmentVariable('GMD_AZDO_PROJECT')
    if ([string]::IsNullOrWhiteSpace($Project)) {
        Write-Error "Parameter 'Project' is required. Provide via -Project or set GMD_AZDO_PROJECT environment variable."
    }
}

# Get PAT token
if ([string]::IsNullOrWhiteSpace($Pat)) {
    $Pat = Get-AzDoPatToken -Decrypt
}

$null = & ssLogIt.ps1 -Level Info -Message "Exporting work item hierarchy for ID: ::FgGreen::$WorkItemId::FgDefault::"

# Step 1: Detect work item type
$null = & ssLogIt.ps1 -Level Debug -Message "Fetching work item type for ID: $WorkItemId"
$workItem = & "$PSScriptRoot/GetAzDoWorkItem.ps1" `
    -Organization $Organization `
    -Project $Project `
    -WorkItemId $WorkItemId `
    -PatToken $Pat

if ($null -eq $workItem) {
    throw "Work item with ID $WorkItemId was not found."
}

[string]$workItemType = $workItem.fields.'System.WorkItemType'
[string]$workItemTitle = $workItem.fields.'System.Title'

$null = & ssLogIt.ps1 -Level Debug -Message "Work item type: $workItemType, title: $workItemTitle"

# Step 2: Fetch hierarchy based on type
[object]$hierarchy = $null

switch ($workItemType) {
    $script:WORKITEM_TYPE_EPIC {
        $null = & ssLogIt.ps1 -Level Debug -Message "Fetching Epic hierarchy for ID: $WorkItemId"
        $hierarchy = & "$PSScriptRoot/GetAzDoHierarchyForEpic.ps1" `
            -Organization $Organization `
            -Project $Project `
            -EpicId $WorkItemId `
            -PatToken $Pat
    }
    $script:WORKITEM_TYPE_FEATURE {
        $null = & ssLogIt.ps1 -Level Debug -Message "Fetching Feature hierarchy for ID: $WorkItemId"
        $hierarchy = & "$PSScriptRoot/GetAzDoHierarchyForFeature.ps1" `
            -Organization $Organization `
            -Project $Project `
            -FeatureId $WorkItemId `
            -PatToken $Pat
    }
    $script:WORKITEM_TYPE_STORY {
        $null = & ssLogIt.ps1 -Level Debug -Message "Fetching Story hierarchy for ID: $WorkItemId"
        $hierarchy = & "$PSScriptRoot/GetAzDoHierarchyForStory.ps1" `
            -Organization $Organization `
            -Project $Project `
            -StoryId $WorkItemId `
            -PatToken $Pat
    }
    default {
        throw "Unsupported work item type '$workItemType' for work item ID $WorkItemId. Supported types are: Epic, Feature, User Story."
    }
}

if ($null -eq $hierarchy) {
    throw "Failed to retrieve hierarchy for work item ID $WorkItemId (type: $workItemType)."
}

# Step 3: Convert hierarchy to markdown
$null = & ssLogIt.ps1 -Level Debug -Message "Converting hierarchy to markdown"
[string]$markdownContent = & "$PSScriptRoot/ConvertHierarchyToMarkdown.ps1" `
    -Hierarchy $hierarchy `
    -Organization $Organization `
    -Project $Project

# Step 4: Resolve output path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    # Build auto-named path: plan-{id}-{type}{CamelCaseTitle}.md
    [string]$typePrefix = switch ($workItemType) {
        $script:WORKITEM_TYPE_EPIC    { 'epic' }
        $script:WORKITEM_TYPE_FEATURE { 'feat' }
        $script:WORKITEM_TYPE_STORY   { 'story' }
    }

    # Convert title to PascalCase, stripping non-alphanumeric chars
    [string]$camelTitle = ($workItemTitle -split '[^a-zA-Z0-9]+' |
        Where-Object { $_ -ne '' } |
        ForEach-Object { $_.Substring(0,1).ToUpper() + $_.Substring(1) }) -join ''

    [string]$fileName = "plan-$WorkItemId-$typePrefix$camelTitle.md"
    [string]$repoRoot = (Resolve-Path "$PSScriptRoot/..").Path
    $OutputPath = Join-Path $repoRoot "docs/plans/$fileName"
    $null = & ssLogIt.ps1 -Level Debug -Message "Auto-generated output path: $OutputPath"
}

# Check if file already exists
if ((Test-Path $OutputPath) -and -not $Overwrite) {
    throw "Output file already exists: '$OutputPath'. Use -Overwrite to replace."
}

# Step 5: Write file and emit path
$null = & ssLogIt.ps1 -Level Debug -Message "Writing markdown to: $OutputPath"
$markdownContent | Set-Content -Path $OutputPath -Encoding UTF8

$null = & ssLogIt.ps1 -Level Info -Message "Successfully exported hierarchy to: ::FgGreen::$OutputPath::FgDefault::"

# Emit the resolved path to the pipeline
$OutputPath
