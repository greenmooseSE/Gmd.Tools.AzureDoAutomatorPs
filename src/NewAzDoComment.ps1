<#
.SYNOPSIS
Add a new comment to an Azure DevOps work item

.DESCRIPTION
Creates a new comment on an existing work item in Azure DevOps.
Supports markdown formatting in the comment content.
Returns the created comment object with metadata.

.PARAMETER Organization
The Azure DevOps organization name (required)

.PARAMETER Project
The Azure DevOps project name (required)

.PARAMETER WorkItemId
The work item ID to add the comment to (required)

.PARAMETER Content
The comment content, supports markdown formatting (required)

.PARAMETER PatToken
Optional PAT token for authentication. If not provided, retrieves from GMD_AZDO_MACHINE_WORKITEMSRW
environment variable (expected to be encrypted).

.OUTPUTS
PSObject representing the created comment with all metadata

.EXAMPLE
Add a simple comment:
    $comment = .\NewAzDoComment.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123 -Content "This is a comment"

Add a comment with markdown:
    $comment = .\NewAzDoComment.ps1 -Organization "myorg" -Project "myproject" -WorkItemId 123 -Content "**Important**: Please review this carefully"

.NOTES
- Requires Azure DevOps REST API access
- Requires PAT token with work items read/write scope
- WorkItemId must be a valid work item ID
- Comment content supports markdown formatting
#>

#Requires -Version 7.0

param(
    [Parameter(Mandatory = $false)]
    [string]$Organization,

    [Parameter(Mandatory = $false)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [int]$WorkItemId,

    [Parameter(Mandatory = $true)]
    [string]$Content,

    [string]$PatToken
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
    Write-Error "Required helper script 'ssLogIt.ps1' not found in PATH. Ensure helper scripts are available."
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

# Validate required parameters
if ([string]::IsNullOrWhiteSpace($Organization)) {
    Write-Error "Parameter 'Organization' cannot be empty."
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    Write-Error "Parameter 'Project' cannot be empty."
}

if (-not (Test-AzDoWorkItemIdValid $WorkItemId)) {
    Write-Error "Parameter 'WorkItemId' must be a positive integer."
}

if ([string]::IsNullOrWhiteSpace($Content)) {
    Write-Error "Parameter 'Content' cannot be empty."
}

# Log script start
$null = & ssLogIt.ps1 -Level Info -Message "Adding comment to work item ID: ::FgGreen::$WorkItemId::FgDefault::"

# Get PAT token if not provided
if ([string]::IsNullOrWhiteSpace($PatToken)) {
    $PatToken = Get-AzDoPatToken -Decrypt
}

try {
    # Validate work item exists
    $logMessage = "Validating work item (ID: $WorkItemId)"
    $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

    $workItem = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $WorkItemId -PatToken $PatToken
    if ($null -eq $workItem) {
        Write-Error "Work item with ID $WorkItemId not found."
    }

    $logMessage = "Work item found: ::FgGreen::$($workItem.fields.'System.Title')::FgDefault::"
    $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

    # Create the comment
    $logMessage = "Creating comment..."
    $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"

    $comment = New-AzDoComment -Organization $Organization -Project $Project -WorkItemId $WorkItemId -Content $Content -PatToken $PatToken

    if ($null -eq $comment) {
        Write-Error "Failed to create comment on work item $WorkItemId."
    }

    $null = & ssLogIt.ps1 -Level Info -Message "Comment created successfully (ID: ::FgGreen::$($comment.id)::FgDefault::)"

    return $comment
}
catch {
    $logMessage = "Failed to add comment: $_"
    $null = & ssLogIt.ps1 -Level Error -Message "$logMessage" -Exception $_
    throw
}
