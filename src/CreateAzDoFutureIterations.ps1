<#
.SYNOPSIS
Create Azure DevOps iterations starting from a specified date

.DESCRIPTION
Automatically creates iterations (sprints) starting from a specified date with configurable:
- Parent path where iterations should be created (required, e.g., "GMD/2026")
- Iteration length (weeks or months, default 1 month)
- Start date (required)
- Stop date for iteration creation (optional, prevents creating iterations beyond this date)
- Iteration name template with date format specifiers and optional counter
- Counter start value (required if template contains counter)

Only creates iterations if they do not already exist. Performs full validation before creating any items (fail-fast approach).

Organization, Project, and PatToken are retrieved from environment variables:
- GMD_AZDO_ORGANIZATION: Azure DevOps organization name
- GMD_AZDO_PROJECT: Azure DevOps project name
- GMD_AZDO_MACHINE_WORKITEMSRW: PAT token for work item operations

.PARAMETER Organization
Optional Azure DevOps organization name. If not provided, uses GMD_AZDO_ORGANIZATION environment variable.

.PARAMETER Project
Optional Azure DevOps project name. If not provided, uses GMD_AZDO_PROJECT environment variable.

.PARAMETER ParentPath
Required parent path for creating iterations (e.g., "GMD/2026"). Defines the iteration hierarchy level where iterations will be created.

.PARAMETER StartAt
Required date to start creating iterations from (format: yyyy-MM-dd, e.g., 2026-01-04).

.PARAMETER StopAt
Optional date to stop creating iterations. Prevents creating iterations that would start on or after this date (format: yyyy-MM-dd, e.g., 2026-12-31).
If not specified, iterations are created based on MonthsAhead parameter.

.PARAMETER IterationLength
Iteration length specification with unit suffix (default: "1m"):
- "1m", "2m", etc. for months
- "1w", "2w", etc. for weeks
Example: "2w" creates 2-week iterations, "1m" creates 1-month iterations

.PARAMETER IterationNameTemplate
Template for iteration names with support for:
- Date format specifiers: {yyyy}, {MM}, {dd}, {yyyy-MM}, etc. (standard .NET date format specifiers)
- {counterNonPadded}: Counter without padding (e.g., 1, 2, 10)
- {counterPadded}: Counter with zero-padding (e.g., 01, 02, 10)
Default: "{yyyy-MM}" (e.g., "2026-01", "2026-02")

.PARAMETER MonthsAhead
Number of months/weeks ahead to create iterations for (default: 6). Can be interpreted based on IterationLength.

.PARAMETER CounterStart
Starting value for counter (only used/required if IterationNameTemplate contains {counterNonPadded} or {counterPadded}).
If template contains counter, this parameter is mandatory.

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.PARAMETER DryRun
Switch: If specified, shows planned operations without creating iterations.

.OUTPUTS
PSObject with summary of created/planned iterations including:
- plannedIterations: Array of iterations that will be/were created
- totalCreated: Number of iterations created (0 in DryRun)
- message: Summary message

.EXAMPLE
Create 1-month iterations starting 2026-01-04 with default naming:
    .\CreateAzDoFutureIterations.ps1 -StartAt "2026-01-04"
    
Create 2-week iterations starting 2026-01-04:
    .\CreateAzDoFutureIterations.ps1 -StartAt "2026-01-04" -IterationLength "2w" -IterationNameTemplate "W{counterPadded}" -CounterStart 1
    
Create iterations with custom template:
    .\CreateAzDoFutureIterations.ps1 -StartAt "2026-01-04" -IterationNameTemplate "Sprint{counterNonPadded}" -CounterStart 1

Dry-run to see what would be created:
    .\CreateAzDoFutureIterations.ps1 -StartAt "2026-01-04" -DryRun

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read/write scope
- Iterations API: https://learn.microsoft.com/en-us/rest/api/azure/devops/work/iterations
- Only creates new iterations if they don't already exist by name and date range
- Iteration structure: path under project iterations
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $false)]
    [string]$Organization,

    [Parameter(Mandatory = $false)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [string]$ParentPath,

    [Parameter(Mandatory = $true)]
    [string]$StartAt,

    [Parameter(Mandatory = $false)]
    [string]$StopAt,

    [Parameter(Mandatory = $false)]
    [string]$IterationLength = "1m",

    [Parameter(Mandatory = $false)]
    [string]$IterationNameTemplate = "{yyyy-MM}",

    [Parameter(Mandatory = $false)]
    [int]$MonthsAhead = 6,

    [Parameter(Mandatory = $false)]
    [int]$CounterStart,

    [string]$PatToken,

    [switch]$DryRun
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Import modules
. "$PSScriptRoot/AzDoAutomatorConstants.ps1"
. "$PSScriptRoot/AzDoPatTokenHelper.ps1"
. "$PSScriptRoot/AzDoApiWrapper.ps1"

# Validate ssLogIt.ps1 exists
if (-not (Get-Command -Name 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    Write-Error "Required helper script 'ssLogIt.ps1' not found in PATH."
}

# ============================================================================
# Parameter Validation
# ============================================================================

# Validate ParentPath parameter
if ([string]::IsNullOrWhiteSpace($ParentPath)) {
    throw "Parameter 'ParentPath' is required and cannot be empty. Provide a parent path like 'GMD/2026'."
}

# Validate StartAt parameter
[datetime]$startAtDate = [datetime]::MinValue
try {
    $startAtDate = [datetime]::ParseExact($StartAt, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
}
catch {
    throw "Parameter 'StartAt' has invalid format. Expected 'yyyy-MM-dd' (e.g., 2026-01-04), got: $StartAt"
}

# Validate StopAt parameter if provided
[datetime]$stopAtDate = [datetime]::MaxValue
if (-not [string]::IsNullOrWhiteSpace($StopAt)) {
    try {
        $stopAtDate = [datetime]::ParseExact($StopAt, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        throw "Parameter 'StopAt' has invalid format. Expected 'yyyy-MM-dd' (e.g., 2026-12-31), got: $StopAt"
    }
    
    if ($stopAtDate -le $startAtDate) {
        throw "Parameter 'StopAt' must be after 'StartAt'. StartAt: $($startAtDate.ToString('yyyy-MM-dd')), StopAt: $($stopAtDate.ToString('yyyy-MM-dd'))"
    }
}

# Validate IterationLength parameter
if ($IterationLength -notmatch '^\d+[wm]$') {
    throw "Parameter 'IterationLength' has invalid format. Use format like '1m', '2w', '3m', got: $IterationLength"
}

[int]$duration = 0
[string]$durationUnit = ""
if ($IterationLength -match '^(\d+)([wm])$') {
    [int]$amount = [int]$Matches[1]
    [string]$unit = $Matches[2]
    
    if ($unit -eq 'w') {
        $duration = $amount * 7
        $durationUnit = "weeks"
    }
    else {
        # For months, we'll use average month length and adjust per iteration
        $duration = $amount
        $durationUnit = "months"
    }
}

# Validate IterationNameTemplate and CounterStart
[bool]$templateHasCounter = $IterationNameTemplate -match '\{counter'
[bool]$isDefaultTemplate = $IterationNameTemplate -eq "{yyyy-MM}"
[bool]$isDefaultLength = $IterationLength -eq "1m"

if ($templateHasCounter -and -not $PSBoundParameters.ContainsKey('CounterStart')) {
    throw "Parameter 'CounterStart' is required because IterationNameTemplate contains counter placeholders: $IterationNameTemplate"
}

if (-not $templateHasCounter -and $PSBoundParameters.ContainsKey('CounterStart')) {
    throw "Parameter 'CounterStart' cannot be specified if IterationNameTemplate does not contain {counterNonPadded} or {counterPadded}"
}

if (-not $isDefaultLength -and -not $PSBoundParameters.ContainsKey('IterationNameTemplate')) {
    throw "Parameter 'IterationNameTemplate' is required when using non-default IterationLength (current: $IterationLength). Provide -IterationNameTemplate parameter."
}

# Validate MonthsAhead parameter
if ($MonthsAhead -lt 1 -or $MonthsAhead -gt 24) {
    throw "MonthsAhead must be between 1 and 24. Provided value: $MonthsAhead"
}

# Apply environment variable defaults if parameters not provided
if ([string]::IsNullOrWhiteSpace($Organization)) {
    $Organization = [Environment]::GetEnvironmentVariable('GMD_AZDO_ORGANIZATION')
    if ([string]::IsNullOrWhiteSpace($Organization)) {
        Write-Error "Parameter 'Organization' is required. Provide via -Organization parameter or set GMD_AZDO_ORGANIZATION environment variable."
    }
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    $Project = [Environment]::GetEnvironmentVariable('GMD_AZDO_PROJECT')
    if ([string]::IsNullOrWhiteSpace($Project)) {
        Write-Error "Parameter 'Project' is required. Provide via -Project parameter or set GMD_AZDO_PROJECT environment variable."
    }
}

# Get PAT token
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

# ============================================================================
# Helper Functions
# ============================================================================

<#
.SYNOPSIS
Apply template to generate iteration name with date and counter substitutions
#>
function ApplyIterationNameTemplate {
    param(
        [string]$Template,
        [datetime]$IterationDate,
        [int]$Counter
    )
    
    [string]$result = $Template
    
    # Replace date format specifiers
    # Try common format specifiers
    $dateFormats = @(
        'yyyy', 'yy', 'MM', 'dd', 'HH', 'mm', 'ss',
        'yyyy-MM', 'yyyy-MM-dd', 'MM-dd', 'yyyy/MM', 'yyyy/MM/dd'
    )
    
    foreach ($format in $dateFormats) {
        [string]$placeholder = "{$format}"
        if ($result -contains $placeholder) {
            [string]$dateValue = $IterationDate.ToString($format)
            $result = $result -replace [regex]::Escape($placeholder), $dateValue
        }
    }
    
    # Replace counter placeholders
    [string]$counterPadded = $Counter.ToString('00')
    $result = $result -replace [regex]::Escape('{counterPadded}'), $counterPadded
    $result = $result -replace [regex]::Escape('{counterNonPadded}'), $Counter.ToString()
    
    return $result
}

<#
.SYNOPSIS
Calculate end date for an iteration given start date and duration
#>
function CalculateIterationEndDate {
    param(
        [datetime]$StartDate,
        [int]$Duration,
        [string]$DurationUnit
    )
    
    if ($DurationUnit -eq 'weeks') {
        # Duration is already in days (weeks * 7)
        return $StartDate.AddDays($Duration - 1)
    }
    else {
        # Duration is in months
        return $StartDate.AddMonths($Duration).AddDays(-1)
    }
}

<#
.SYNOPSIS
Check if iteration with same name and date range already exists
#>
function IterationExists {
    param(
        [object[]]$ExistingIterations,
        [string]$IterationName,
        [datetime]$StartDate,
        [datetime]$EndDate
    )
    
    if ($null -eq $ExistingIterations) {
        return $false
    }

    foreach ($iteration in $ExistingIterations) {
        if ($iteration.name -eq $IterationName) {
            if ((-not [string]::IsNullOrWhiteSpace($iteration.attributes.startDate)) -and 
                (-not [string]::IsNullOrWhiteSpace($iteration.attributes.finishDate))) {
                
                [datetime]$existingStart = [datetime]$iteration.attributes.startDate
                [datetime]$existingEnd = [datetime]$iteration.attributes.finishDate
                
                if ($existingStart -eq $StartDate -and $existingEnd -eq $EndDate) {
                    return $true
                }
            }
        }
    }

    return $false
}

<#
.SYNOPSIS
Create a single iteration via wrapper API
#>
function CreateIteration {
    param(
        [string]$IterationName,
        [datetime]$StartDate,
        [datetime]$EndDate,
        [string]$ParentPath,
        [string]$OrganizationName,
        [string]$ProjectName,
        [string]$PATToken
    )
    
    $null = & ssLogIt.ps1 -Level Debug -Message "Creating iteration: $IterationName under ::FgCyan::$ParentPath::FgDefault:: (Start: $($StartDate.ToString('yyyy-MM-dd')), End: $($EndDate.ToString('yyyy-MM-dd')))"

    try {
        [object]$response = New-AzDoIteration -Organization $OrganizationName -Project $ProjectName `
            -ParentPath $ParentPath -IterationName $IterationName -StartDate $StartDate -EndDate $EndDate -PatToken $PATToken
        return $response
    }
    catch {
        $null = & ssLogIt.ps1 -Level Error -Exception $_
        throw
    }
}

# ============================================================================
# Main Script Logic
# ============================================================================

$null = & ssLogIt.ps1 -Level Info -Message "Starting iteration creation for ::FgCyan::$Project::FgDefault::"
$null = & ssLogIt.ps1 -Level Info -Message "  ParentPath: ::FgYellow::$ParentPath::FgDefault::"
$null = & ssLogIt.ps1 -Level Info -Message "  StartAt: ::FgYellow::$($startAtDate.ToString('yyyy-MM-dd'))::FgDefault::"
if (-not [string]::IsNullOrWhiteSpace($StopAt)) {
    $null = & ssLogIt.ps1 -Level Info -Message "  StopAt: ::FgYellow::$($stopAtDate.ToString('yyyy-MM-dd'))::FgDefault::"
}
$null = & ssLogIt.ps1 -Level Info -Message "  IterationLength: ::FgYellow::$IterationLength::FgDefault:: (Duration: $duration $durationUnit)"
$null = & ssLogIt.ps1 -Level Info -Message "  IterationNameTemplate: ::FgYellow::$IterationNameTemplate::FgDefault::"
if ($templateHasCounter) {
    $null = & ssLogIt.ps1 -Level Info -Message "  CounterStart: ::FgYellow::$CounterStart::FgDefault::"
}
$null = & ssLogIt.ps1 -Level Info -Message "  MonthsAhead: ::FgYellow::$MonthsAhead::FgDefault:: (DryRun: $DryRun)"

# Retrieve existing iterations (only to check for duplicates)
$null = & ssLogIt.ps1 -Level Debug -Message "Retrieving existing iterations to check for duplicates..."
$existingIterations = & "$PSScriptRoot/GetAzDoIterations.ps1" -Organization $Organization -Project $Project -PatToken $PatToken

# Plan new iterations
[object[]]$plannedIterations = @()
[int]$createdCount = 0
[int]$currentCounter = if ($templateHasCounter) { $CounterStart } else { 0 }

for ($i = 0; $i -lt $MonthsAhead; $i++) {
    # Calculate the start date for this iteration
    [datetime]$iterationStartDate = if ($durationUnit -eq 'weeks') {
        $startAtDate.AddDays($i * $duration)
    }
    else {
        $startAtDate.AddMonths($i * $duration)
    }
    
    # Check if we've passed StopAt date (if specified)
    if ($iterationStartDate -ge $stopAtDate) {
        $null = & ssLogIt.ps1 -Level Debug -Message "Iteration start date ::FgYellow::$($iterationStartDate.ToString('yyyy-MM-dd'))::FgDefault:: is at or after StopAt date, stopping iteration creation"
        break
    }
    
    # Calculate the end date
    [datetime]$iterationEndDate = CalculateIterationEndDate -StartDate $iterationStartDate -Duration $duration -DurationUnit $durationUnit
    
    # Generate iteration name from template
    [string]$iterationName = ApplyIterationNameTemplate -Template $IterationNameTemplate -IterationDate $iterationStartDate -Counter $currentCounter
    
    # Check if iteration already exists
    if (IterationExists -ExistingIterations $existingIterations -IterationName $iterationName -StartDate $iterationStartDate -EndDate $iterationEndDate) {
        $null = & ssLogIt.ps1 -Level Debug -Message "Iteration ::FgYellow::$iterationName::FgDefault:: already exists, skipping"
        if ($templateHasCounter) {
            $currentCounter++
        }
        continue
    }

    [hashtable]$plannedIteration = @{
        name      = $iterationName
        startDate = $iterationStartDate.ToString('yyyy-MM-dd')
        endDate   = $iterationEndDate.ToString('yyyy-MM-dd')
    }

    $plannedIterations += $plannedIteration
    
    $null = & ssLogIt.ps1 -Level Info -Message "Planned iteration: ::FgGreen::$iterationName::FgDefault:: ($($iterationStartDate.ToString('yyyy-MM-dd')) to $($iterationEndDate.ToString('yyyy-MM-dd')))"

    if (-not $DryRun) {
        try {
            $null = CreateIteration -IterationName $iterationName -StartDate $iterationStartDate -EndDate $iterationEndDate `
                -ParentPath $ParentPath -OrganizationName $Organization -ProjectName $Project -PATToken $PatToken
            $createdCount++
            $null = & ssLogIt.ps1 -Level Info -Message "Created iteration: ::FgGreen::$iterationName::FgDefault::"
        }
        catch {
            $null = & ssLogIt.ps1 -Level Error -Message "Failed to create iteration ::FgRed::$iterationName::FgDefault::"
            throw
        }
    }
    
    if ($templateHasCounter) {
        $currentCounter++
    }
}

# Summary
[string]$message = if ($DryRun) {
    "DryRun: Would create $($plannedIterations.Count) iterations"
}
else {
    "Created $createdCount iterations"
}

$null = & ssLogIt.ps1 -Level Info -Message $message

[hashtable]$result = @{
    plannedIterations = $plannedIterations
    totalCreated      = $createdCount
    message           = $message
}

return $result
