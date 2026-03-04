<#
.SYNOPSIS
Azure DevOps Work Item Helper Module

.DESCRIPTION
Utility functions for common work item operations such as:
- Querying work items by title and parent
- Checking work item existence
- Retrieving work items by ID
- Finding child work items

.NOTES
Requires AzDoAutomatorConstants.ps1 and AzDoApiWrapper.ps1 to be dot-sourced first.
#>

#Requires -Version 7.0

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# ============================================================================
# Public Functions
# ============================================================================

<#
.SYNOPSIS
Find a work item by title

.DESCRIPTION
Query Azure DevOps to find a work item with the specified title.
Optionally filter by parent work item ID or work item type.

.PARAMETER Organization
The Azure DevOps organization name

.PARAMETER Project
The project name

.PARAMETER Title
The work item title to search for

.PARAMETER ParentId
Optional: Parent work item ID to narrow search scope

.PARAMETER WorkItemType
Optional: Filter by work item type (Feature, Story, Task, etc.)

.PARAMETER PatToken
Optional PAT token. If not provided, retrieves from environment.

.OUTPUTS
Work item object if found, $null otherwise

.EXAMPLE
$feature = Find-AzDoWorkItemByTitle -Organization "myorg" -Project "myproject" -Title "My Feature"
$story = Find-AzDoWorkItemByTitle -Organization "myorg" -Project "myproject" -Title "My Story" -ParentId 456 -WorkItemType "Story"
#>
function Find-AzDoWorkItemByTitle {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$Title,

        [int]$ParentId,

        [string]$WorkItemType,

        [string]$PatToken
    )

    process {
        # Build WIQL query
        [string]$query = "SELECT [System.Id], [System.Title], [System.WorkItemType], [System.Parent] FROM WorkItems WHERE [System.Title] = '$Title'"

        if ($PSBoundParameters.ContainsKey('WorkItemType')) {
            $query += " AND [System.WorkItemType] = '$WorkItemType'"
        }

        if ($PSBoundParameters.ContainsKey('ParentId')) {
            $query += " AND [System.Parent] = '$ParentId'"
        }

        try {
            $workItems = Invoke-AzDoWiql -Organization $Organization -Project $Project -Query $query -PatToken:$PatToken

            if ($null -eq $workItems -or @($workItems).Count -eq 0) {
                return $null
            }

            if (@($workItems).Count -gt 1) {
                $logMessage = "Multiple work items found with title `'$Title`'. Returning first match."
                $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"
            }

            # Retrieve full work item details
            $firstId = $workItems[0].id
            return Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $firstId -PatToken:$PatToken
        }
        catch {
            Write-Error "Failed to find work item with title '$Title': $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
Check if a work item exists

.DESCRIPTION
Determine if a work item with the specified title exists in the project.

.PARAMETER Organization
The Azure DevOps organization name

.PARAMETER Project
The project name

.PARAMETER Title
The work item title to search for

.PARAMETER ParentId
Optional: Parent work item ID to narrow search scope

.PARAMETER WorkItemType
Optional: Filter by work item type

.PARAMETER PatToken
Optional PAT token. If not provided, retrieves from environment.

.OUTPUTS
[bool] $true if work item exists, $false otherwise

.EXAMPLE
if (Test-AzDoWorkItemExists -Organization "myorg" -Project "myproject" -Title "My Feature" -WorkItemType "Feature") {
    Write-Host "Feature already exists"
}
#>
function Test-AzDoWorkItemExists {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$Title,

        [int]$ParentId,

        [string]$WorkItemType,

        [string]$PatToken
    )

    process {
        try {
            $findParams = @{
                Organization = $Organization
                Project      = $Project
                Title        = $Title
            }

            if ($PSBoundParameters.ContainsKey('ParentId')) {
                $findParams['ParentId'] = $ParentId
            }

            if ($PSBoundParameters.ContainsKey('WorkItemType')) {
                $findParams['WorkItemType'] = $WorkItemType
            }

            if ($PSBoundParameters.ContainsKey('PatToken')) {
                $findParams['PatToken'] = $PatToken
            }

            $workItem = Find-AzDoWorkItemByTitle @findParams

            return $null -ne $workItem
        }
        catch {
            return $false
        }
    }
}

<#
.SYNOPSIS
Get all child work items of a parent

.DESCRIPTION
Retrieve all work items that have the specified parent ID.
Optionally filter by work item type.

.PARAMETER Organization
The Azure DevOps organization name

.PARAMETER Project
The project name

.PARAMETER ParentId
The parent work item ID

.PARAMETER WorkItemType
Optional: Filter by work item type (Feature, Story, Task, etc.)

.PARAMETER PatToken
Optional PAT token. If not provided, retrieves from environment.

.OUTPUTS
Array of child work item objects (may be empty if no children)

.EXAMPLE
$features = Get-AzDoChildWorkItems -Organization "myorg" -Project "myproject" -ParentId 123 -WorkItemType "Feature"
#>
function Get-AzDoChildWorkItems {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [int]$ParentId,

        [string]$WorkItemType,

        [string]$PatToken
    )

    process {
        # Build WIQL query
        [string]$query = "SELECT [System.Id], [System.Title], [System.WorkItemType], [System.Parent] FROM WorkItems WHERE [System.Parent] = '$ParentId'"

        if ($PSBoundParameters.ContainsKey('WorkItemType')) {
            $query += " AND [System.WorkItemType] = '$WorkItemType'"
        }

        try {
            $workItems = Invoke-AzDoWiql -Organization $Organization -Project $Project -Query $query -PatToken:$PatToken

            if ($null -eq $workItems -or @($workItems).Count -eq 0) {
                return @()
            }

            # Retrieve full details for each child item
            [object[]]$children = @()
            foreach ($item in $workItems) {
                $child = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $item.id -PatToken:$PatToken
                if ($null -ne $child) {
                    $children += $child
                }
            }

            return $children
        }
        catch {
            Write-Error "Failed to get child work items for parent $ParentId : $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
Get all descendants of a work item

.DESCRIPTION
Recursively retrieve all child and grandchild work items (complete hierarchy).
Useful for operations like deleting an Epic and all its children.

.PARAMETER Organization
The Azure DevOps organization name

.PARAMETER Project
The project name

.PARAMETER WorkItemId
The parent work item ID to get descendants for

.PARAMETER PatToken
Optional PAT token. If not provided, retrieves from environment.

.OUTPUTS
Hashtable with ID as key and work item as value for easy lookup during recursive operations

.EXAMPLE
$descendants = Get-AzDoAllDescendants -Organization "myorg" -Project "myproject" -WorkItemId 100
foreach ($id in $descendants.Keys) {
    Write-Host "Descendant: $($descendants[$id].fields['System.Title'])"
}
#>
function Get-AzDoAllDescendants {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [int]$WorkItemId,

        [string]$PatToken
    )

    process {
        [hashtable]$descendants = @{}

        function Get-DescendantsRecursive {
            param(
                [int]$ParentId
            )

            try {
                $children = Get-AzDoChildWorkItems -Organization $Organization -Project $Project -ParentId $ParentId -PatToken:$PatToken

                foreach ($child in $children) {
                    $childId = $child.id
                    $descendants[$childId] = $child

                    # Recursively get grandchildren
                    Get-DescendantsRecursive -ParentId $childId
                }
            }
            catch {
                $logMessage = "Error getting children of work item $ParentId : $_"
                $null = & ssLogIt.ps1 -Level Debug -Message "$logMessage"
            }
        }

        try {
            Get-DescendantsRecursive -ParentId $WorkItemId
            return $descendants
        }
        catch {
            Write-Error "Failed to get all descendants of work item $WorkItemId : $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
Validate work item ID format

.DESCRIPTION
Check if a provided work item ID is in valid format (positive integer).

.PARAMETER WorkItemId
The work item ID to validate

.OUTPUTS
[bool] $true if valid, $false otherwise

.EXAMPLE
if (Test-AzDoWorkItemIdValid 123) {
    Write-Host "Valid ID"
}
#>
function Test-AzDoWorkItemIdValid {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$WorkItemId
    )

    process {
        try {
            [int]$id = $WorkItemId
            return $id -gt 0
        }
        catch {
            return $false
        }
    }
}

<#
.SYNOPSIS
Get work item parent information

.DESCRIPTION
Retrieve the parent work item of the specified work item.

.PARAMETER Organization
The Azure DevOps organization name

.PARAMETER Project
The project name

.PARAMETER WorkItemId
The work item ID

.PARAMETER PatToken
Optional PAT token. If not provided, retrieves from environment.

.OUTPUTS
Parent work item object or $null if no parent

.EXAMPLE
$parent = Get-AzDoWorkItemParent -Organization "myorg" -Project "myproject" -WorkItemId 123
#>
function Get-AzDoWorkItemParent {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [int]$WorkItemId,

        [string]$PatToken
    )

    process {
        try {
            $workItem = Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $WorkItemId -PatToken:$PatToken

            if ($null -eq $workItem -or -not $workItem.fields.PSObject.Properties.Name.Contains('System.Parent')) {
                return $null
            }

            [int]$parentId = $workItem.fields.'System.Parent'

            if ($parentId -le 0) {
                return $null
            }

            return Get-AzDoWorkItemById -Organization $Organization -Project $Project -WorkItemId $parentId -PatToken:$PatToken
        }
        catch {
            return $null
        }
    }
}
