# Azure DevOps Automator - PowerShell Scripts

Comprehensive PowerShell script collection for automating Azure DevOps work item management. All scripts follow strict quality standards including PascalCase naming, strict mode v3, fail-fast error handling, and consistent logging using `ssLogIt.ps1`.

## Overview

This project provides a complete automation toolkit for Azure DevOps work item lifecycle management including:

- **Creating/Updating** Features and Stories
- **Getting/Setting** work item properties (description, acceptance criteria, story points)
- **Managing Tags** (add, replace, remove)
- **Generating hierarchies** from markdown files
- **Deleting** Epic and all children with safety confirmations

## Prerequisites

- **PowerShell 7.0+** (pwsh - PowerShell Core)
- **Azure DevOps Account** with API access
- **Personal Access Token (PAT)** with "Work Items (Read & Write)" scope
- **Helper Scripts**: `ssLogIt.ps1`, `ssEncryptDecrypt.ps1`, `ssInvokeExpr.ps1` available in PATH

## Setup

### 1. Configure PAT Token

Store your Azure DevOps Personal Access Token securely:

```powershell
# Option A: Set encrypted environment variable (recommended)
$token = "your-pat-token-here"
$encrypted = $token | ssEncryptDecrypt.ps1 -Encrypt
[Environment]::SetEnvironmentVariable('FALCOIT_AZDO_PAT_WORKITEMSREADWRITE', $encrypted, 'User')

# Option B: Pass token directly to scripts (less secure)
$script = ".\New-AzDoFeature.ps1 -Organization myorg -Project myproj -Title 'Feature' -PatToken $token"
```

### 2. Verify Helper Scripts

Ensure required helper scripts are in your PATH:

```powershell
Get-Command ssLogIt.ps1
Get-Command ssEncryptDecrypt.ps1
```

## Module Architecture

### Core Infrastructure Modules

These are dot-sourced by all automation scripts:

#### `AzDoAutomatorConstants.ps1`
Defines all constants used throughout the automation suite:
- API endpoints and versions
- Work item types (Epic, Feature, Story, Task)
- Field reference names (System.Title, Microsoft.VSTS.Common.AcceptanceCriteria, etc.)
- Regex patterns for markdown parsing
- HTTP methods and patch operations

#### `AzDoPatTokenHelper.ps1`
Manages PAT token retrieval and authentication:
- `Get-AzDoPatToken`: Retrieve PAT from environment with optional decryption
- `New-AzDoAuthHeader`: Create Basic Auth headers for API calls
- `Test-AzDoPatToken`: Validate PAT token validity
- `Confirm-SsEncryptDecryptHelperExists`: Check for helper script availability

#### `AzDoApiWrapper.ps1`
Low-level REST API wrapper with retry logic:
- `Invoke-AzDoWiql`: Execute WIQL queries
- `Get-AzDoWorkItemById`: Retrieve specific work items
- `New-AzDoWorkItem`: Create new work items
- `Update-AzDoWorkItem`: Update existing work items
- `Remove-AzDoWorkItem`: Delete work items
- Built-in retry logic for transient failures
- Comprehensive error logging

#### `AzDoWorkItemHelper.ps1`
High-level work item operations:
- `Find-AzDoWorkItemByTitle`: Search by title and parent
- `Test-AzDoWorkItemExists`: Check existence
- `Get-AzDoChildWorkItems`: Get direct children
- `Get-AzDoAllDescendants`: Get entire subtree recursively
- `Test-AzDoWorkItemIdValid`: Validate work item IDs
- `Get-AzDoWorkItemParent`: Get parent of work item

## Automation Scripts

### Feature/Story Management

#### `NewAzDoEpic.ps1`
Create new Epics (top-level work items).

```powershell
# Create Epic
$epic = .\NewAzDoEpic.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Title "Q1 2024 Roadmap" `
    -Description "All features planned for Q1 2024"

# Returned object has full work item details
Write-Host "Created Epic ID: $($epic.id)"
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `Title` (required): Epic title
- `Description` (optional): Epic description
- `PatToken` (optional): Override default PAT token

#### `NewAzDoFeature.ps1`
Create or update Features with optional parent Epic.

```powershell
# Create new Feature
$feature = .\NewAzDoFeature.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Title "User Authentication System" `
    -Description "Implement OAuth 2.0 authentication" `
    -ParentEpicId 42

# Update existing Feature
$feature = .\NewAzDoFeature.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Title "Existing Feature" `
    -Description "Updated description" `
    -UpdateExisting
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `Title` (required): Feature title
- `Description` (optional): Feature description
- `ParentEpicId` (optional): Parent Epic ID
- `UpdateExisting` (switch): Update if feature exists
- `PatToken` (optional): Override default PAT token

#### `NewAzDoStory.ps1`
Create or update Stories under a Feature.

```powershell
# Create Story with full details
$story = .\NewAzDoStory.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Title "Build Login Form" `
    -ParentFeatureId 123 `
    -Description "Create login form UI" `
    -AcceptanceCriteria @"
- Must support email/password login
- Must support OAuth 2.0 providers
- Must validate input on client side
"@ `
    -StoryPoints 5

# Update existing Story
$story = .\NewAzDoStory.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Title "Existing Story" `
    -ParentFeatureId 123 `
    -StoryPoints 8 `
    -UpdateExisting
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `Title` (required): Story title
- `ParentFeatureId` (required): Parent Feature ID
- `Description` (optional): Story description
- `AcceptanceCriteria` (optional): Acceptance criteria text
- `StoryPoints` (optional): Story points (non-negative integer)
- `UpdateExisting` (switch): Update if story exists
- `PatToken` (optional): Override default PAT token

#### `GetAzDoWorkItem.ps1`
Retrieve complete work item information.

```powershell
# Get work item
$workItem = .\GetAzDoWorkItem.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123

# Access fields
$title = $workItem.fields['System.Title']
$description = $workItem.fields['System.Description']
$storyPoints = $workItem.fields['Microsoft.VSTS.Scheduling.StoryPoints']
```

### Field Setters

#### `SetAzDoWorkItemDescription.ps1`
Update work item description.

```powershell
$updated = .\SetAzDoWorkItemDescription.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123 `
    -Description "Updated description text"
```

#### `SetAzDoAcceptanceCriteria.ps1`
Update work item acceptance criteria.

```powershell
$updated = .\SetAzDoAcceptanceCriteria.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123 `
    -AcceptanceCriteria "List of acceptance criteria"
```

#### `SetAzDoStoryPoints.ps1`
Update work item story points.

```powershell
$updated = .\SetAzDoStoryPoints.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123 `
    -StoryPoints 5
```

### Tag Management

#### `SetAzDoWorkItemTags.ps1`
Manage work item tags with three modes: Add, Replace, Remove.

```powershell
# Replace all tags
$updated = .\SetAzDoWorkItemTags.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123 `
    -Tags @("urgent", "api") `
    -Mode Replace

# Add tags to existing
$updated = .\SetAzDoWorkItemTags.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123 `
    -Tags @("new-tag") `
    -Mode Add

# Remove specific tags
$updated = .\SetAzDoWorkItemTags.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123 `
    -Tags @("old-tag") `
    -Mode Remove
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `WorkItemId` (required): Work item ID
- `Tags` (required): Array of tags
- `Mode` (optional): 'Add', 'Replace', or 'Remove' (default: 'Replace')
- `PatToken` (optional): Override default PAT token

### Advanced Operations

#### `NewAzDoHierarchyFromMarkdown.ps1`
Create complete work item hierarchy from markdown file.

Markdown format:
```markdown
# Epic Title (optional, for nested structure)

## Feature 1 Title
- Story 1 Title
  - AC: First acceptance criterion
  - AC: Second acceptance criterion
  - SP: 5
- Story 2 Title
  - SP: 8

## Feature 2 Title
- Story 3 Title
```

Usage:
```powershell
# Dry run preview
$result = .\NewAzDoHierarchyFromMarkdown.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -MarkdownFilePath ".\hierarchy.md" `
    -DryRun

# Create hierarchy with validation
$result = .\NewAzDoHierarchyFromMarkdown.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -MarkdownFilePath ".\hierarchy.md" `
    -EpicId 100

# Access results
Write-Host "Created: $($result.CreatedItems.Count) items"
```

**Features:**
- Pre-validates entire structure before creating items (fail-fast)
- Supports optional Epic parent
- Parses acceptance criteria and story points from markdown
- DryRun mode shows planned operations without creation
- Comprehensive error reporting

#### `RemoveAzDoEpic.ps1`
Delete an Epic and all child work items (DESTRUCTIVE OPERATION).

Usage:
```powershell
# Delete with confirmation prompt (safe default)
$result = .\RemoveAzDoEpic.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -EpicId 100

# Delete without confirmation (use with caution!)
$result = .\RemoveAzDoEpic.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -EpicId 100 `
    -Force

# Check results
$result.DeletedCount   # Number of successfully deleted items
$result.SkippedCount   # Number of items that failed to delete
$result.Cancelled      # Whether user cancelled operation
```

**Safety Features:**
- Lists all work items to be deleted before proceeding
- Requires user confirmation (type "YES") unless -Force specified
- Displays deletion progress
- Returns summary of results
- Logs all operations for audit trail

## Environment Variables

### Required
- **FALCOIT_AZDO_PAT_WORKITEMSREADWRITE**: Personal Access Token (recommended: encrypted)

## Logging Output

All scripts use `ssLogIt.ps1` for consistent, colored logging:
- **Info** (::FgGreen::): Successful operations
- **Debug** (::FgDefault::): Detailed operation steps
- **Warning** (::FgYellow::): Non-critical issues
- **Error** (::FgRed::): Failures and critical issues

Example output:
```
[INFO] Creating/updating Feature: ::FgGreen::User Authentication::FgDefault:: in project ::FgGreen::myproject::FgDefault::
[DEBUG] Creating new Feature with title ::FgGreen::User Authentication::FgDefault::
[INFO] Successfully created Feature ::FgGreen::User Authentication::FgDefault:: (ID: 456)
```

## Testing

Run basic integration tests to verify setup:

```powershell
.\test\BasicIntegrationTest.ps1
```

Tests verify:
- All helper modules load correctly
- All functions are defined
- Constants are properly initialized
- Required scripts exist and are accessible

## Error Handling

All scripts follow strict error handling practices:
- **Fail-fast**: Errors immediately abort execution (no silent failures)
- **Validation first**: Input validation before API calls
- **Clear messages**: Descriptive error messages with context
- **No fallbacks**: No silent error recovery or default behaviors

## Quality Standards

- **PascalCase naming**: All scripts follow `NewAzDoFeature` pattern
- **Strict mode v3**: Prevents uninitialized variable usage
- **Fail fast**: `$ErrorActionPreference = 'Stop'`
- **No null-forgiving**: No `!` operator without explanation
- **XML documentation**: Complete parameter documentation
- **Logging**: All operations logged via `ssLogIt.ps1`

## File Structure

```
.
├── src/
│   ├── AzDoAutomatorConstants.ps1           (Core constants)
│   ├── AzDoPatTokenHelper.ps1               (PAT token management)
│   ├── AzDoApiWrapper.ps1                   (REST API wrapper)
│   ├── AzDoWorkItemHelper.ps1               (Helper functions)
│   ├── NewAzDoEpic.ps1                      (Create Epic)
│   ├── NewAzDoFeature.ps1                   (Create/update Features)
│   ├── NewAzDoStory.ps1                     (Create/update Stories)
│   ├── GetAzDoWorkItem.ps1                  (Retrieve work item)
│   ├── SetAzDoWorkItemDescription.ps1       (Set description)
│   ├── SetAzDoAcceptanceCriteria.ps1        (Set acceptance criteria)
│   ├── SetAzDoStoryPoints.ps1               (Set story points)
│   ├── SetAzDoWorkItemTags.ps1              (Manage tags)
│   ├── NewAzDoHierarchyFromMarkdown.ps1     (Create from markdown)
│   ├── RemoveAzDoEpic.ps1                   (Delete Epic and children)
│   ├── RunSystemTest.ps1                    (System test suite)
│   └── VerifyAzDoPat.ps1                    (Verify PAT read access)
├── test/
│   └── BasicIntegrationTest.ps1             (Integration tests)
└── README.md                                 (This file)
```

## System Testing

### VerifyAzDoPat.ps1 - Verify PAT Work Item Read Access

Validates the PAT can read work items in the specified organization and project.

```powershell
# Verify PAT access
$isValid = .\src\VerifyAzDoPat.ps1 `
    -Organization "falco-it" `
    -Project "GMD"

Write-Host "PAT read access: $isValid"
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `PatToken` (optional): Override default PAT token

### RunSystemTest.ps1 - Comprehensive System Test Suite

Test all automation scripts end-to-end against a real Azure DevOps instance.

```powershell
# Run system test against default organization (falco-it) and project (GMD)
$results = .\src\RunSystemTest.ps1 `
    -Organization "falco-it" `
    -Project "GMD" `
    -EpicTitle "Automated System Test Epic"

# Check results
Write-Host "Tests Passed: $($results.TestsPassed)"
Write-Host "Tests Failed: $($results.TestsFailed)"
Write-Host "Created Epic ID: $($results.CreatedEpicId)"
Write-Host "Created Feature ID: $($results.CreatedFeatureId)"
Write-Host "Created Story ID: $($results.CreatedStoryId)"
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `EpicTitle` (optional): Title for test Epic (default: "WIP System Test Epic")
- `PatToken` (optional): Override default PAT token

**What Gets Tested:**
1. Verify test Epic doesn't exist (validation)
2. Create test Epic
3. Create Feature under Epic
4. Create Story under Feature (with AC and story points)
5. Retrieve created Story
6. Update Description
7. Update Acceptance Criteria
8. Update Story Points
9. Set Tags (Replace mode)
10. Set Tags (Add mode)
11. Create Hierarchy from Markdown
12. Update Existing Story

**Output:**
Returns hashtable with test results:
- `CreatedEpicId`: ID of test Epic
- `CreatedFeatureId`: ID of test Feature
- `CreatedStoryId`: ID of test Story
- `TestsPassed`: Count of successful tests
- `TestsFailed`: Count of failed tests
- `Details`: Array of individual test results

**Note:** RunSystemTest.ps1 does NOT test `RemoveAzDoEpic.ps1` (destructive operation). Test data remains for manual inspection.

## Common Tasks

### Create a complete feature with stories

```powershell
# 1. Create Feature
$feature = .\NewAzDoFeature.ps1 `
    -Organization "myorg" -Project "myproj" `
    -Title "Payment Processing" `
    -Description "Implement payment gateway integration"

# 2. Create Stories
$story1 = .\NewAzDoStory.ps1 `
    -Organization "myorg" -Project "myproj" `
    -Title "Stripe Integration" `
    -ParentFeatureId $feature.id `
    -StoryPoints 8

$story2 = .\NewAzDoStory.ps1 `
    -Organization "myorg" -Project "myproj" `
    -Title "PayPal Integration" `
    -ParentFeatureId $feature.id `
    -StoryPoints 5

# 3. Add tags
.\SetAzDoWorkItemTags.ps1 `
    -Organization "myorg" -Project "myproj" `
    -WorkItemId $feature.id `
    -Tags @("payment", "integration") `
    -Mode Replace
```

### Generate hierarchy from markdown

```powershell
# Create hierarchy.md file:
# Feature 1
# - Story 1
#   - SP: 5
# - Story 2
#   - AC: User can login
#   - SP: 8

.\NewAzDoHierarchyFromMarkdown.ps1 `
    -Organization "myorg" -Project "myproj" `
    -MarkdownFilePath ".\hierarchy.md"
```

### Bulk update stories

```powershell
# Update multiple work items
$storyIds = @(100, 101, 102)

foreach ($id in $storyIds) {
    .\SetAzDoStoryPoints.ps1 `
        -Organization "myorg" -Project "myproj" `
        -WorkItemId $id -StoryPoints 5
}
```

## Troubleshooting

### "ssLogIt.ps1 not found"
- Ensure helper scripts are in your PATH
- Verify PowerShell Path contains the directory with helper scripts
- Check: `Get-Command ssLogIt.ps1`

### PAT token errors
- Verify `FALCOIT_AZDO_PAT_WORKITEMSREADWRITE` is set
- Test decryption: `$env:FALCOIT_AZDO_PAT_WORKITEMSREADWRITE | ssEncryptDecrypt.ps1 -Decrypt`
- Ensure PAT token has "Work Items (Read & Write)" scope
- Check token hasn't expired in Azure DevOps

### Work item not found
- Verify work item ID is correct
- Confirm organization and project names
- Ensure PAT token has read access to the project

### Markdown parsing errors
- Check markdown structure matches format exactly
- Verify all titles are non-empty
- Ensure proper indentation (2 spaces for properties)
- Run with `-DryRun` first to validate structure

## Contributing

When adding new scripts:
- Follow PascalCase.ps1 naming convention
- Include `#Requires -Version 7.0` and `Set-StrictMode -Version 3.0`
- Set `$ErrorActionPreference = 'Stop'`
- Add comprehensive XML documentation comments
- Use `ssLogIt.ps1` for all logging with colored tokens
- Validate all inputs early (fail-fast)
- Support optional PathToken parameter
- Include examples in .DESCRIPTION

## License

[Your License Here]

## Support

For issues or questions about Azure DevOps automation scripts, please refer to the specific script header comments or review the Common Tasks section above.
