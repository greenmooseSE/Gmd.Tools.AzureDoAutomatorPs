# Azure DevOps Automator - PowerShell Scripts

Comprehensive PowerShell script collection for automating Azure DevOps work item management. All scripts follow strict quality standards including PascalCase naming, strict mode v3, fail-fast error handling, and consistent logging using `ssLogIt.ps1`.

## Overview

This project provides a complete automation toolkit for Azure DevOps work item lifecycle management including:

- **Creating/Updating** Epics, Features, Stories, Bugs, and Tasks — all with `-Fields`, `-State`, and `-AssignedTo` support
- **Getting/Setting** work item properties (description, acceptance criteria, story points, effort, AssignedTo)
- **Managing Tags** (add, replace, remove)
- **Managing Iterations** (retrieving, creating future iterations based on existing patterns)
- **Generating hierarchies** from markdown files
- **Deleting** work items with optional recursive child deletion (`-Recursive`) and safety confirmations (Epics, Features, Stories, Bugs, Tasks)
- **Unified Configuration** via `appSettings.json` — field definitions, state definitions, and identity resolution driven by a single config file per org/project

## Table of Contents

- [Prerequisites](#prerequisites)
- [Setup](#setup)
  - [Configure PAT Token](#1-configure-pat-token)
  - [Verify Helper Scripts](#2-verify-helper-scripts)
- [Module Architecture](#module-architecture)
- [Automation Scripts](#automation-scripts)
- [Iteration Management](#iteration-management)
- [Markdown Hierarchy Workflow](#markdown-hierarchy-workflow)
- [Markdown Hierarchy Template Generation](#markdown-hierarchy-template-generation)
- [Creating Work Item Hierarchies from Markdown](#creating-work-item-hierarchies-from-markdown)
- [Special Handling](#special-handling)
- [Creating Tasks Within Stories](#creating-tasks-within-stories)
- [Creating Bugs Within Stories](#creating-bugs-within-stories)
- [Example Hierarchy](#example-hierarchy)
- [Unified Field and State Configuration](#unified-field-and-state-configuration)
  - [appSettings.json](#appSettingsjson)
  - [LoadFieldConfiguration.ps1](#loadfieldconfigurationps1)
  - [ValidateUpsertFields.ps1](#validateupsertfieldsps1)
  - [AssignedTo Support](#assignedto-support)
  - [SyncAppSettingsFields.ps1](#syncappsettingsfieldsps1)
- [Field Migration](#field-migration)
  - [MoveAzDoWorkItemField.ps1](#moveazdoworkitemfieldps1)
- [State Configuration Management](#state-configuration-management)
- [Export-Modify-Reimport Workflow](#export-modify-reimport-workflow)
- [Download and Compare Workflow](#download-and-compare-workflow)
- [Recipes](#recipes)
  - [Generate Azure DevOps Hierarchy from Markdown](#generate-azure-devops-hierarchy-from-markdown)
  - [Update Hierarchy Structure in Azure DevOps](#update-hierarchy-structure-in-azure-devops)
- [MCP Server Integration](#mcp-server-integration)
- [Testing](#testing)
  - [Test Hierarchy Helper](#test-hierarchy-helper)
  - [Test Markdown Generator](#test-markdown-generator)
- [Contributing](#contributing)

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
[Environment]::SetEnvironmentVariable('GMD_AZDO_MACHINE_WORKITEMSRW', $encrypted, 'User')

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
- Work item types (Epic, Feature, Story, Task, Bug)
- Field reference names (System.Title, System.AssignedTo, Microsoft.VSTS.Common.AcceptanceCriteria, etc.)
- Regex patterns for markdown parsing
- HTTP methods and patch operations

#### `LoadFieldConfiguration.ps1`
Loads field definitions for a specific work item type from `appSettings.json`:
- Returns an array of field objects: `referenceName`, `label`, `description`, `type`, `readOnly`
- Used by `GetAzDoWorkItem.ps1` to enrich results with named properties
- Used by `GenerateAzDoMarkdownHierarchyTemplate.ps1` to build the SUPPORTED FIELDS REFERENCE section
- No-op (returns empty array) when appSettings.json is absent or has no matching entry

#### `ValidateUpsertFields.ps1`
Pre-flight validation helpers called by all Upsert scripts before making any API call:
- `Assert-FieldsNotReadOnly -Organization -Project -WorkItemType -Fields`: Throws if any key in the `-Fields` hashtable is marked `readOnly: true` in `appSettings.json`
- `Assert-StateIsWritable -Organization -Project -WorkItemType -State`: Throws if `-State` is not in the `writableStates` list for the given work item type

#### `ResolveAzDoIdentity.ps1`
Resolves an email address to an Azure DevOps identity object before any PATCH/POST call:
- Calls `GET _apis/identities?searchFilter=MailAddress&filterValue={email}&api-version=7.1-preview.1`
- Fails fast with a clear error if no matching identity is found
- Returns `[PSCustomObject]@{ DisplayName = "..."; UniqueName = "<email>" }`
- Used by all five Upsert scripts when `-AssignedTo` is supplied

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
- `Move-AzDoWorkItem`: Reparent work items to a new parent (supports hierarchy reorganization)
- `Remove-AzDoWorkItem`: Delete work items
- `New-AzDoComment`: Add comment to a work item
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

#### `UpsertAzDoEpic.ps1`
Create or update Epics (UPSERT operation). Epics are the top-level work items with no parent.

```powershell
# Create or update Epic by title (standard UPSERT)
$epic = .\UpsertAzDoEpic.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Title "Platform Modernization" `
    -Description "Modernise the entire platform stack" `
    -Effort 80

# Transition an Epic to a new state and assign it
$epic = .\UpsertAzDoEpic.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Title "Platform Modernization" `
    -State "Active" `
    -AssignedTo "lead@myorg.com"

# Pass arbitrary writable fields via hashtable
$epic = .\UpsertAzDoEpic.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Title "Platform Modernization" `
    -Fields @{ 'System.Tags' = 'platform; initiative' }

# Update existing Epic by ID
$epic = .\UpsertAzDoEpic.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Id 100 `
    -Effort 100
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `Title` (required for create, optional for ID-based update): Epic title
- `Id` (optional): Epic ID for direct update (cannot be used with `-FailIfExist`)
- `Description` (optional): Epic description
- `Effort` (optional): Effort value (non-negative number; decimals supported)
- `State` (optional): Transition the Epic to a writable state; validated against `appSettings.json` before the API call
- `AssignedTo` (optional): Email address of the team member to assign this Epic to; resolved to an Azure DevOps identity before the API call — fails fast if the email is not found
- `Fields` (optional): Hashtable of additional writable fields keyed by `referenceName`; validated against `appSettings.json` before the API call — read-only fields are rejected
- `FailIfExist` (switch): Create-only mode; fails if an Epic with this title already exists
- `PatToken` (optional): Override default PAT token

#### `UpsertAzDoFeature.ps1`
Create or update Features (UPSERT operation) with optional parent Epic.

```powershell
# Create or update Feature by title (standard UPSERT)
$feature = .\UpsertAzDoFeature.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Title "User Authentication System" `
    -Description "Implement OAuth 2.0 authentication" `
    -Effort 13

# Create Feature under an Epic
$feature = .\UpsertAzDoFeature.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Title "Search Feature" `
    -Description "Implement search functionality" `
    -ParentEpicId 42

# Create Feature only if title doesn't exist (create-only mode)
$feature = .\UpsertAzDoFeature.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Title "New Feature" `
    -FailIfExist

# Update existing Feature by ID directly
$feature = .\UpsertAzDoFeature.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Id 123 `
    -Description "Updated description" `
    -Effort 21
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `Title` (required for create): Feature title
- `Id` (optional): Feature ID for direct update. Cannot be used with -FailIfExist
- `Description` (optional): Feature description
- `ParentEpicId` (optional): Parent Epic ID (used only when creating)
- `Effort` (optional): Effort value (non-negative number; decimals supported, e.g. 2.5)
- `Priority` (optional): Priority level 1-4 (1=highest, 4=lowest)
- `OriginalEstimate` (optional): Original estimate in hours (non-negative number)
- `FixedIn` (optional): Text field for the version or build where the feature was completed
- `DeployedToDev` (optional): Boolean — whether the feature has been deployed to Dev
- `DeployedToStaging` (optional): Boolean — whether the feature has been deployed to Staging
- `DeployedToProduction` (optional): Boolean — whether the feature has been deployed to Production
- `State` (optional): Transition the Feature to a writable state; validated against `appSettings.json` before the API call
- `AssignedTo` (optional): Email address of the team member to assign this Feature to; resolved to an Azure DevOps identity before the API call — fails fast if the email is not found
- `Fields` (optional): Hashtable of additional writable fields keyed by `referenceName`; validated against `appSettings.json` before the API call — read-only fields are rejected
- `FailIfExist` (switch): Create-only mode; fails if feature exists. Cannot be used with -Id
- `PatToken` (optional): Override default PAT token

**Behavior:**
- If `-Id` provided: Updates Feature by ID directly (no title-based lookup)
- If `-Id` not provided: UPSERT by Title (updates if exists, creates if not)
  - With `-FailIfExist`: Creates only if title doesn't exist; fails if found


#### `UpsertAzDoStory.ps1`
Create or update Stories under a Feature using unified UPSERT operation.

```powershell
# Create or update Story by title (standard UPSERT)
$story = .\UpsertAzDoStory.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Title "Build Login Form" `
    -Description "Create login form UI" `
    -AcceptanceCriteria @"
- Must support email/password login
- Must support OAuth 2.0 providers
- Must validate input on client side
"@ `
    -StoryPoints 5

# Create Story only if title doesn't exist
$story = .\UpsertAzDoStory.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Title "New Story" `
    -ParentFeatureId 123 `
    -FailIfExist

# Update existing Story by ID directly
$story = .\UpsertAzDoStory.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Id 456 `
    -Title "New Title" `
    -StoryPoints 8

# Create Story under a Feature
$story = .\UpsertAzDoStory.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Title "Feature Story" `
    -ParentFeatureId 123 `
    -Description "Story under Feature" `
    -StoryPoints 5
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `Title` (required for create, optional for ID-based update): Story title
- `Id` (optional): Story ID for direct update (cannot be used with `-FailIfExist`)
- `Description` (optional): Story description
- `AcceptanceCriteria` (optional): Acceptance criteria text
- `AcScenarios` (optional): Acceptance criteria scenarios
- `ExtraInformation` (optional): Extra information text
- `StoryPoints` (optional): Story points (non-negative integer)
- `Priority` (optional): Priority level 1-4 (1=highest, 4=lowest)
- `OriginalEstimate` (optional): Original estimate in hours (non-negative number)
- `FixedIn` (optional): Text field for the version or build where the story was completed
- `DeployedToDev` (optional): Boolean — whether the story has been deployed to Dev
- `DeployedToStaging` (optional): Boolean — whether the story has been deployed to Staging
- `DeployedToProduction` (optional): Boolean — whether the story has been deployed to Production
- `State` (optional): Transition the Story to a writable state; validated against `appSettings.json` before the API call
- `AssignedTo` (optional): Email address of the team member to assign this Story to; resolved to an Azure DevOps identity before the API call — fails fast if the email is not found
- `Fields` (optional): Hashtable of additional writable fields keyed by `referenceName`; validated against `appSettings.json` before the API call — read-only fields are rejected
- `ParentFeatureId` (optional): Parent Feature ID (for creation only)
- `FailIfExist` (switch): Create-only mode; fails if title exists (cannot be used with `-Id`)
- `PatToken` (optional): Override default PAT token

**Behavior:**
- If `-Id` provided: Updates Story by ID directly (no title-based lookup)
- If `-Id` not provided: UPSERT by Title (updates if exists, creates if not)
  - With `-FailIfExist`: Creates only if title doesn't exist; fails if found

#### `UpsertAzDoTask.ps1`
Create or update Tasks under a Story using unified UPSERT operation. Tasks are leaf-level work items used to track individual work.

```powershell
# Create or update Task by title (standard UPSERT)
$task = .\UpsertAzDoTask.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Title "Write unit tests" `
    -Description "Implement unit tests for login module" `
    -Effort 3

# Create Task under a Story
$task = .\UpsertAzDoTask.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Title "Implement login validation" `
    -ParentStoryId 456 `
    -Description "Validate email format and password strength" `
    -Effort 5

# Create Task only if title doesn't exist
$task = .\UpsertAzDoTask.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Title "New Task" `
    -ParentStoryId 456 `
    -FailIfExist

# Update existing Task by ID directly
$task = .\UpsertAzDoTask.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Id 789 `
    -State "In Progress" `
    -Effort 2
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `Title` (required for create, optional for ID-based update): Task title
- `Id` (optional): Task ID for direct update (cannot be used with `-FailIfExist`)
- `Description` (optional): Task description
- `Effort` (optional): Effort value (non-negative number; decimals supported, e.g. 0.5)
- `State` (optional): Task state (e.g., "To Do", "In Progress", "Done"); validated against `appSettings.json` before the API call
- `AssignedTo` (optional): Email address of the team member to assign this Task to; resolved to an Azure DevOps identity before the API call — fails fast if the email is not found
- `Fields` (optional): Hashtable of additional writable fields keyed by `referenceName`; validated against `appSettings.json` before the API call — read-only fields are rejected
- `ParentStoryId` (optional): Parent Story ID (for creation only)
- `FailIfExist` (switch): Create-only mode; fails if title exists (cannot be used with `-Id`)
- `PatToken` (optional): Override default PAT token

**Behavior:**
- If `-Id` provided: Updates Task by ID directly (no title-based lookup)
- If `-Id` not provided: UPSERT by Title (updates if exists, creates if not)
  - With `-FailIfExist`: Creates only if title doesn't exist; fails if found

#### `RemoveAzDoTask.ps1`
Delete a Task work item with optional confirmation prompt. Tasks are leaf-level items with no children.

```powershell
# Delete Task with confirmation prompt (safe default)
$result = .\RemoveAzDoTask.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -TaskId 789

# Delete Task without confirmation prompt
$result = .\RemoveAzDoTask.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -TaskId 789 `
    -Force
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `TaskId` (required): Task ID to delete
- `Force` (switch): Skip confirmation prompt
- `PatToken` (optional): Override default PAT token

**Behavior:**
- Without `-Force`: Displays task details and prompts for confirmation (requires "YES" response)
- With `-Force`: Deletes immediately without confirmation
- Returns summary with deletion status

### Bug Management

#### `UpsertAzDoBug.ps1`
Create or update Bugs (UPSERT operation) with full field support. Bugs support priority levels, reproduction steps, system information, and integration build tracking.

```powershell
# Create or update Bug by title (standard UPSERT)
$bug = .\UpsertAzDoBug.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Title "Login screen crashes on invalid input" `
    -Description "When entering special characters in password field, app crashes" `
    -Priority 1 `
    -ReproSteps "1. Open login page 2. Enter special characters in password 3. Click submit" `
    -SystemInfo "Windows 11, Chrome 120" `
    -StoryPoints 5

# Create Bug under a Story
$bug = .\UpsertAzDoBug.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Title "API returns 500 error" `
    -Priority 2 `
    -ParentStoryId 456 `
    -FoundInBuild "Build 2026.3.1" `
    -IntegratedInBuild "Build 2026.3.2"

# Create Bug only if title doesn't exist
$bug = .\UpsertAzDoBug.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Title "New Bug" `
    -Priority 3 `
    -FailIfExist

# Update existing Bug by ID directly
$bug = .\UpsertAzDoBug.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Id 789 `
    -Priority 1 `
    -ReproSteps "Updated reproduction steps"
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `Title` (required for create, optional for ID-based update): Bug title
- `Id` (optional): Bug ID for direct update (cannot be used with `-FailIfExist`)
- `Description` (optional): Bug description
- `Priority` (optional): Priority level 1-4 (1=highest, 4=lowest)
- `ReproSteps` (optional): Steps to reproduce the bug
- `SystemInfo` (optional): System/environment information
- `StoryPoints` (optional): Story points (non-negative integer)
- `FoundInBuild` (optional): Build where bug was found
- `IntegratedInBuild` (optional): Build where fix was integrated
- `State` (optional): Transition the Bug to a writable state; validated against `appSettings.json` before the API call
- `AssignedTo` (optional): Email address of the team member to assign this Bug to; resolved to an Azure DevOps identity before the API call — fails fast if the email is not found
- `Fields` (optional): Hashtable of additional writable fields keyed by `referenceName`; validated against `appSettings.json` before the API call — read-only fields are rejected
- `ParentStoryId` (optional): Parent Story ID (for creation only)
- `FailIfExist` (switch): Create-only mode; fails if bug exists (cannot be used with `-Id`)
- `PatToken` (optional): Override default PAT token

**Behavior:**
- If `-Id` provided: Updates Bug by ID directly (no title-based lookup)
- If `-Id` not provided: UPSERT by Title (updates if exists, creates if not)
  - With `-FailIfExist`: Creates only if title doesn't exist; fails if found
- Returns complete Bug object as JSON

#### `GetAzDoBug.ps1`
Retrieve a Bug work item with all metadata including comments and tags.

```powershell
# Get Bug by ID
$bug = .\GetAzDoBug.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -BugId 789

# Access bug properties
Write-Host "Title: $($bug.fields.'System.Title')"
Write-Host "Priority: $($bug.fields.'Microsoft.VSTS.Common.Priority')"
Write-Host "Repro Steps: $($bug.fields.'Microsoft.VSTS.TCM.ReproSteps')"
Write-Host "System Info: $($bug.fields.'Microsoft.VSTS.TCM.SystemInfo')"
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `BugId` (required): Bug ID to retrieve
- `PatToken` (optional): Override default PAT token

**Output:**
- Complete Bug work item object with all standard AzDo fields plus enriched properties:
  - All fields from `appSettings.json` are added as named properties (label with spaces removed)
  - `AssignedTo` — a `[PSCustomObject]@{ DisplayName; UniqueName }` normalized object (null if unassigned)
  - Priority, ReproSteps, SystemInfo, StoryPoints, FoundInBuild, IntegratedInBuild, comments, and tags

#### `RemoveAzDoBug.ps1`
Delete a Bug work item with optional recursive deletion of child Tasks.

```powershell
# Delete Bug only (child Tasks become orphaned, warning shown if children exist)
$result = .\RemoveAzDoBug.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -BugId 789

# Delete Bug and all child Tasks
$result = .\RemoveAzDoBug.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -BugId 789 `
    -Recursive

# Delete Bug and all child Tasks without confirmation
$result = .\RemoveAzDoBug.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -BugId 789 `
    -Recursive `
    -Force
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `BugId` (required): Bug ID to delete
- `Recursive` (switch): Delete all child Tasks before deleting the Bug
- `Force` (switch): Skip confirmation prompt
- `PatToken` (optional): Override default PAT token

**Behavior:**
- Without `-Recursive`: Deletes only the Bug; warns if child Tasks exist (they become orphaned)
- With `-Recursive`: Deletes all child Tasks first, then the Bug
- Without `-Force`: Prompts for confirmation (requires "YES" response)
- With `-Force`: Deletes immediately without confirmation
- Returns summary hashtable with `Cancelled`, `DeletedCount`, `BugId`, `BugTitle`

#### `GetAzDoWorkItem.ps1`
Retrieve complete work item information. The result is enriched with named properties based on `appSettings.json` field definitions.

```powershell
# Get work item
$workItem = .\GetAzDoWorkItem.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123

# Access raw fields
$title = $workItem.fields['System.Title']
$description = $workItem.fields['System.Description']
$storyPoints = $workItem.fields['Microsoft.VSTS.Scheduling.StoryPoints']

# Access enriched named properties (from appSettings.json field config)
$storyPoints = $workItem.StoryPoints
$assignedTo = $workItem.AssignedTo.DisplayName   # [PSCustomObject]@{ DisplayName; UniqueName }
```

**Output enrichment:**
- For each field defined in `appSettings.json` for the work item type, a named property is added to the result using the field label (with spaces removed) as the property name
- `AssignedTo` is always normalized to a `[PSCustomObject]@{ DisplayName; UniqueName }` object

#### `GetAzDoUserStory.ps1`
Retrieve a User Story with full details or key properties only.

```powershell
# Get User Story with default subset of fields
$story = .\GetAzDoUserStory.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123

# Access story properties
Write-Host "Title: $($story.Title)"
Write-Host "State: $($story.State)"
Write-Host "StoryPoints: $($story.StoryPoints)"
Write-Host "Comments: $($story.Comments.Count)"

# Get complete work item JSON (identical to GetAzDoWorkItem)
$fullStory = .\GetAzDoUserStory.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123 `
    -Full
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `WorkItemId` (required): User Story ID
- `Full` (switch): Return complete work item JSON (equivalent to GetAzDoWorkItem)
- `PatToken` (optional): Override default PAT token

**Output Fields (without -Full):**
- Id, State, Title
- Description, AcceptanceCriteria, ACScenarios
- StoryPoints, ExtraInformation, Tags
- OriginalEstimate, RemainingWork, CompletedWork
- AssignedTo (`[PSCustomObject]@{ DisplayName; UniqueName }`, null if unassigned)
- Comments (array with latest version of each comment including id, createdDate, lastModifiedDate, text, and createdBy.displayName)

#### `UpdateAzDoUserStory.ps1`
Update one or more fields of a User Story via PATCH operation.

```powershell
# Update title
$story = .\UpdateAzDoUserStory.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123 `
    -Title "Updated Story Title"

# Update multiple fields
$story = .\UpdateAzDoUserStory.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123 `
    -Title "New Title" `
    -Description "Updated description" `
    -StoryPoints 8 `
    -State "Under Development" `
    -Tags "feature; important"

# Update acceptance criteria
$story = .\UpdateAzDoUserStory.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123 `
    -AcceptanceCriteria @"
Must do X
Must do Y
Must validate Z
"@
```

**Note:** Only specified fields are updated; others remain unchanged. At least one field must be specified.

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

#### `SetAzDoEffort.ps1`
Update Epic or Feature effort value.

```powershell
$updated = .\SetAzDoEffort.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123 `
    -Effort 21
```

### Field Migration

#### `MoveAzDoWorkItemField.ps1`
Move or copy a field value from one field to another across a work item hierarchy or all project work items. Supports `DryRun` to preview changes without writing to the API, and `ConfirmEachItem` for interactive approval.

**Parameters**

| Parameter | Type | Mandatory | ParameterSet | Description |
|-----------|------|-----------|--------------|-------------|
| Organization | string | Yes | Both | Azure DevOps organization name |
| Project | string | Yes | Both | Azure DevOps project name |
| PatToken | string | No | Both | PAT token (defaults to `$env:GMD_AZDO_MACHINE_WORKITEMSRW`) |
| SourceField | string | Yes | Both | Display label of the field to move/copy from |
| TargetField | string | Yes | Both | Display label of the field to move/copy into |
| WorkItemId | int | Yes | ById | Root work item — processes it and all descendants |
| Global | switch | Yes | Global | Processes every work item in the project via WIQL |
| Copy | switch | No | Both | Keep source field intact (default: clear source after copy) |
| DryRun | switch | No | Both | Preview without making any API changes |
| ConfirmEachItem | switch | No | Both | Prompt before updating each work item |
| WorkItemType | string | No | Both | Restrict to one type: `Epic`, `Feature`, `Story`, `Bug`, `Task`, `Any` (default: `Any`) |
| OverwriteNonEmptyTarget | switch | No | Both | Overwrite target even when it already has a value (default: skip non-empty targets) |
| ValuePreviewLength | int | No | Both | Max characters shown for field value previews in log output (default: `100`, range 10–1000) |
| MinId | int | No | Both | Only process work items with ID ≥ this value; in Global mode also filters the WIQL query (default: `0`, no filter) |
| ChangedSince | datetime | No | Both | Only process work items last changed on or after this date; in Global mode also filters the WIQL query |

```powershell
# Move 'Extra Information' into 'Story Acceptance Tests' for a hierarchy (dry run)
$results = .\MoveAzDoWorkItemField.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 1234 `
    -SourceField "Extra Information" `
    -TargetField "Story Acceptance Tests" `
    -DryRun

# Copy the field globally across all project work items
$results = .\MoveAzDoWorkItemField.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -SourceField "Extra Information" `
    -TargetField "Story Acceptance Tests" `
    -Global `
    -Copy

# Move only on User Stories, overwriting non-empty targets
$results = .\MoveAzDoWorkItemField.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 1234 `
    -SourceField "Extra Information" `
    -TargetField "Story Acceptance Tests" `
    -WorkItemType Story `
    -OverwriteNonEmptyTarget
```

Pipeline output shape per evaluated item:

| Property | Description |
|----------|-------------|
| WorkItemId | Work item ID |
| Title | Work item title |
| WorkItemType | Epic / Feature / User Story / Bug / Task |
| SourceField | Source field display label |
| TargetField | Target field display label |
| Action | `Move`, `Copy`, `Skip`, or `DryRun` |
| Result | `Updated`, `Skipped`, `Declined`, or `Error` |
| Detail | Additional information |

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

#### `UpdateAzDoWorkItemTags.ps1`
Unified CRUD operations for managing work item tags. Replace, add, or remove tags with intuitive parameter names.

```powershell
# Add tags to existing (default when -Replace not specified)
$updated = .\UpdateAzDoWorkItemTags.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123 `
    -Tags @("bug", "urgent")

# Replace all tags with new ones
$updated = .\UpdateAzDoWorkItemTags.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123 `
    -Tags @("backend", "api") `
    -Replace

# Remove all tags
$updated = .\UpdateAzDoWorkItemTags.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123 `
    -Replace

# Remove specific tags (keep others)
$updated = .\UpdateAzDoWorkItemTags.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123 `
    -NotTags @("urgent", "temp")
```
**Note:** `UpdateAzDoWorkItemTags.ps1` is the modern replacement for `SetAzDoWorkItemTags.ps1`, offering cleaner parameter patterns aligned with CRUD naming conventions (Update* for all modification operations).

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `WorkItemId` (required): Work item ID
- `Tags` (required): Array of tags
- `Mode` (optional): 'Add', 'Replace', or 'Remove' (default: 'Replace')
- `PatToken` (optional): Override default PAT token

### Comment Management

#### `NewAzDoComment.ps1`
Add a new comment to a work item.

```powershell
# Create a simple comment
$comment = .\NewAzDoComment.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123 `
    -Content "This is a comment"

# Create a comment with markdown formatting
$comment = .\NewAzDoComment.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123 `
    -Content "**Important**: Please review this carefully"
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `WorkItemId` (required): Work item ID
- `Content` (required): Comment content (supports markdown)
- `PatToken` (optional): Override default PAT token

#### `GetAzDoComments.ps1`
Retrieve all comments from a work item. Useful for auditing, searching discussion history, or verifying comment content.

```powershell
# Get all comments from a work item
$comments = .\GetAzDoComments.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123

# Filter comments by author
$myComments = $comments | Where-Object { $_.createdBy.displayName -eq "John Doe" }

# Check comment count and content
Write-Host "Total comments: $($comments.Count)"
foreach ($comment in $comments) {
    Write-Host "[$($comment.createdDate)] $($comment.text | Truncate -Length 50)"
}
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `WorkItemId` (required): Work item ID
- `PatToken` (optional): Override default PAT token

**Returns:** Array of comment objects (empty array if no comments exist):
- `id`: Comment identifier
- `text`: Comment content (HTML entities decoded)
- `createdDate`: Creation timestamp (ISO 8601 format)
- `modifiedDate`: Last modification timestamp
- `createdBy`: User object with displayName and descriptor
- `modifiedBy`: User object with displayName and descriptor
- `reactions`: Array of reaction objects (if available)

#### `UpdateAzDoComment.ps1`
Update the content of an existing comment on a work item. Useful for fixing typos or revising notes.

```powershell
# Update a comment with plain text
$comment = .\UpdateAzDoComment.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123 `
    -CommentId 456 `
    -Content "Fixed typo in previous comment"

# Update a comment with markdown formatting
$comment = .\UpdateAzDoComment.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123 `
    -CommentId 456 `
    -Content "**Updated note**: Please review this change carefully"
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `WorkItemId` (required): Work item ID
- `CommentId` (required): Comment ID to update
- `Content` (required): New comment content (supports markdown)
- `PatToken` (optional): Override default PAT token

**Returns:** Updated comment object with:
- `id`: Comment identifier (unchanged)
- `text`: Updated comment content
- `version`: Incremented version number
- `createdDate`: Original creation timestamp
- `modifiedDate`: New modification timestamp
- `createdBy`: Original author information
- `modifiedBy`: Updated user who made this change

#### `RemoveAzDoComment.ps1`
Remove a comment from a work item.

```powershell
# Remove comment by ID
$result = .\RemoveAzDoComment.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123 `
    -CommentId 456

# Remove comments matching a regex pattern
$result = .\RemoveAzDoComment.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123 `
    -TextMatchRegex "^TODO:.*" `
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `WorkItemId` (required): Work item ID
- `CommentId` (optional): Specific comment ID to remove
- `TextMatchRegex` (optional): Regular expression to match comments by text (removes latest version of matching comments)
- `PatToken` (optional): Override default PAT token

**Note:** Either `CommentId` or `TextMatchRegex` must be provided.

#### `NewAzDoCommentReaction.ps1`
Add a reaction to a work item comment.

```powershell
# Add a 'like' reaction
$reaction = .\NewAzDoCommentReaction.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123 `
    -CommentId 456 `
    -ReactionType "like"

# Add other reaction types
$reaction = .\NewAzDoCommentReaction.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123 `
    -CommentId 456 `
    -ReactionType "heart"
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `WorkItemId` (required): Work item ID
- `CommentId` (required): Comment ID
- `ReactionType` (required): Type of reaction: `like`, `dislike`, `heart`, `hooray`, `smile`, `confused`
- `PatToken` (optional): Override default PAT token

**Note:** Only one reaction per user per comment per reaction type is allowed. Adding the same reaction twice by the same user will update the count.

#### `GetAzDoCommentReactions.ps1`
Retrieve all reactions for a work item comment.

```powershell
# Get all reactions for a comment
$reactions = .\GetAzDoCommentReactions.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -WorkItemId 123 `
    -CommentId 456

# Filter reactions by type
$likes = $reactions | Where-Object { $_.type -eq "like" }
Write-Host "Likes: $($likes.count)"

# Display all reaction types and counts
foreach ($reaction in $reactions) {
    Write-Host "$($reaction.type): $($reaction.count)"
}
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `WorkItemId` (required): Work item ID
- `CommentId` (required): Comment ID
- `PatToken` (optional): Override default PAT token

**Output Fields:**
- `type`: Reaction type (like, dislike, heart, hooray, smile, confused)
- `count`: Total number of reactions of this type
- `isCurrentUserEngaged`: Whether current user has reacted with this type

### Advanced Operations

#### `GetAzDoHierarchyForEpic.ps1`
Retrieve an Epic with all its Features and their Stories in a hierarchical structure.

```powershell
# Get hierarchy by Epic ID
$hierarchy = .\GetAzDoHierarchyForEpic.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -EpicId 100

# Get hierarchy by Epic title (searches for exact match)
$hierarchy = .\GetAzDoHierarchyForEpic.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -EpicTitle "Platform Modernization"

# Access hierarchy data
Write-Host "Epic: $($hierarchy.Title)"
Write-Host "Effort: $($hierarchy.Effort)"
foreach ($feature in $hierarchy.Features) {
    Write-Host "  Feature: $($feature.Title)"
    foreach ($story in $feature.Stories) {
        Write-Host "    Story: $($story.Title) ($($story.StoryPoints) pts)"
    }
}
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `EpicId` (optional): Epic work item ID
- `EpicTitle` (optional): Epic title to search for
- `PatToken` (optional): Override default PAT token

**Note:** Either `EpicId` or `EpicTitle` must be provided. If both are provided, `EpicId` takes precedence.

**Output Structure:**
```
Epic
├── Id, Title, Description, Effort, Tags
└── Features (array)
    ├── Id, Title, Description, Effort, Tags
    └── Stories (array)
        ├── Id, State, Title, Description
        ├── AcceptanceCriteria, ACScenarios
        ├── StoryPoints, ExtraInformation, Tags
        └── Comments (array with latest version of each comment)
```

**Tags Availability:** All work items in the hierarchy (Epic, Features, Stories) include Tags, ensuring consistent tag retrieval across all hierarchy levels (Story 1588).

**Known Limitations:**
- Comments retrieval is optional and may fail gracefully if the API endpoint is unavailable (returns empty array)
- Getting child work items requires a properly configured WIQL endpoint

#### `GetAzDoHierarchyForFeature.ps1`
Retrieve a Feature with all its Stories and their Tasks in a hierarchical structure.

```powershell
# Get hierarchy by Feature ID
$hierarchy = .\GetAzDoHierarchyForFeature.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -FeatureId 200

# Get hierarchy by Feature title (searches for exact match)
$hierarchy = .\GetAzDoHierarchyForFeature.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -FeatureTitle "User Authentication"

# Access hierarchy data
Write-Host "Feature: $($hierarchy.Title)"
Write-Host "Effort: $($hierarchy.Effort)"
foreach ($story in $hierarchy.Stories) {
    Write-Host "  Story: $($story.Title) ($($story.StoryPoints) pts)"
    foreach ($task in $story.Tasks) {
        Write-Host "    Task: $($task.Title) [$($task.State)]"
    }
}
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `FeatureId` (optional): Feature work item ID
- `FeatureTitle` (optional): Feature title to search for
- `PatToken` (optional): Override default PAT token

**Note:** Either `FeatureId` or `FeatureTitle` must be provided. If both are provided, `FeatureId` takes precedence.

**Output Structure:**
```
Feature
├── Id, Title, Description, Effort, Tags
└── Stories (array)
    ├── Id, State, Title, Description
    ├── AcceptanceCriteria, ACScenarios
    ├── StoryPoints, ExtraInformation, Tags
    └── Tasks (array)
        ├── Id, State, Title, Description, Tags
```

#### `GetAzDoHierarchyForStory.ps1`
Retrieve a User Story with all its Tasks in a hierarchical structure.

```powershell
# Get hierarchy by Story ID
$hierarchy = .\GetAzDoHierarchyForStory.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -StoryId 300

# Get hierarchy by Story title (searches for exact match)
$hierarchy = .\GetAzDoHierarchyForStory.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -StoryTitle "User Login Form"

# Access hierarchy data
Write-Host "Story: $($hierarchy.Title)"
Write-Host "Story Points: $($hierarchy.StoryPoints)"
Write-Host "Tasks: $($hierarchy.Tasks.Count)"
foreach ($task in $hierarchy.Tasks) {
    Write-Host "  Task: $($task.Title) [$($task.State)]"
}
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `StoryId` (optional): Story work item ID
- `StoryTitle` (optional): Story title to search for
- `PatToken` (optional): Override default PAT token

**Note:** Either `StoryId` or `StoryTitle` must be provided. If both are provided, `StoryId` takes precedence.

**Output Structure:**
```
Story
├── Id, State, Title, Description
├── AcceptanceCriteria, ACScenarios
├── StoryPoints, ExtraInformation, Tags
└── Tasks (array)
    ├── Id, State, Title, Description, Tags
```

#### `ConvertHierarchyToMarkdown.ps1`
Export a User Story hierarchy to markdown format with state field and writable state validation.

This script enables the export-modify-reimport workflow by converting a story hierarchy to markdown while respecting the state configuration rules. States that are not in the writable states list are marked as read-only with warning comments.

Usage:
```powershell
# Get story hierarchy
$hierarchy = .\GetAzDoHierarchyForStory.ps1 -StoryId 100

# Export to markdown with state field
$markdown = .\ConvertHierarchyToMarkdown.ps1 `
    -Hierarchy $hierarchy `
    -Organization "falco-it" `
    -Project "GMD"

# Save to file
$markdown | Out-File "story-export.md"

# With custom repository root for state configuration
$markdown = .\ConvertHierarchyToMarkdown.ps1 `
    -Hierarchy $hierarchy `
    -Organization "contoso" `
    -Project "web" `
    -RepositoryRoot "C:\myrepo"
```

**Parameters:**
- `Hierarchy` (required): Story hierarchy object from GetAzDoHierarchyForStory.ps1
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `RepositoryRoot` (optional): Root directory for state configuration files (default: current directory)

**Features:**
- Preserves WorkItemId in markdown metadata for round-trip export-import operations
- Exports state field in markdown metadata (`{State}: [value]`)
- Marks editable states (in writable states list) without warnings
- Marks non-editable states with ⚠️ indicator and HTML warning comment
- Gracefully handles incomplete or missing state configurations using sensible defaults
- Formats tasks and bugs beneath the story
- Preserves all work item metadata (description, acceptance criteria, story points, tags, etc.)
- HTML comments warn users that non-writable state changes will be ignored during reimport

**Output Markdown Structure:**
```markdown
<!-- WARNING: State 'Closed' is NOT in the writable states list...
     During reimport, any state changes will be ignored. Do NOT modify the state field. -->

### Story: Title

{tags}: tag1, tag2
{Story Points}: 5
{State}: Closed ⚠️ (read-only)
{Description}
Story description here...

{Acceptance Criteria}
...

{AC Scenarios}
...

#### Task: Task Title
{State}: Active
{Description}
Task description...
```

#### `NewAzDoHierarchyFromMarkdown.ps1`
Create complete work item hierarchy from markdown file or content string. After creation, **WorkItemId** lines are written back to the file so subsequent runs update existing items instead of creating duplicates.

Markdown format:
```markdown
# Epic: My Epic Title
{WorkItemId}: 100  (written back after first run)
{tags}: tag1, tag2
{Effort}: 10
{Description}
Multi-line epic description

## Feature: Feature Title
{WorkItemId}: 101
{tags}: tag1
{Effort}: 5
{Description}
Feature description

### Story: Story Title
{WorkItemId}: 102
{tags}: tag1
{Story Points}: 5
{Description}
**As a** user
**I want** to do something
**So that** value is delivered

{Acceptance Criteria}
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ☐ | Feature works for happy path |  |  |

{AC Scenarios}
1. **Scenario**: Happy path
   Given setup state
   When action occurs
   Then expected result

{Extra Information}
Additional notes or links

#### Task: Task Title
{tags}: tag1
{Priority}: 2
{Original Estimate}: 4
{Description}
Task details
```

Usage:
```powershell
# Pass file path directly via -MarkdownContent (auto-detected, writes IDs back)
.\NewAzDoHierarchyFromMarkdown.ps1 -MarkdownContent .\my-hierarchy.md

# Or use -MarkdownFile explicitly (also writes IDs back)
.\NewAzDoHierarchyFromMarkdown.ps1 -MarkdownFile ".\my-hierarchy.md"

# Dry run preview
.\NewAzDoHierarchyFromMarkdown.ps1 -MarkdownFile ".\my-hierarchy.md" -DryRun

# Access results
Write-Host "Created: $($result.CreatedItems.Count) items"
```

**Environment Variables Required:**
- `$env:GMD_AZDO_ORGANIZATION`: Azure DevOps organization name
- `$env:GMD_AZDO_PROJECT`: Azure DevOps project name
- `$env:GMD_AZDO_MACHINE_WORKITEMSRW`: Personal Access Token (optional, uses encryption if set)

**Features:**
- Fields mapped to correct Azure DevOps fields: Description (`{Description}`), AcceptanceCriteria (`{Acceptance Criteria}`), AC Scenarios (`{AC Scenarios}`), Extra Information (`{Extra Information}`)
- Bold-formatted lines in descriptions (e.g. `**As a**`) are kept in Description, not treated as metadata
- WorkItemId written back to file after create; second run updates by ID instead of creating duplicates
- Supports optional Epic parent via `-EpicId`
- DryRun mode shows planned operations without creation

#### `RemoveAzDoEpic.ps1`
Delete an Epic, optionally including all child work items (DESTRUCTIVE OPERATION).

```powershell
# Delete Epic only (children become orphaned, warning shown if children exist)
$result = .\RemoveAzDoEpic.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -EpicId 100

# Delete Epic and all children recursively
$result = .\RemoveAzDoEpic.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -EpicId 100 `
    -Recursive

# Delete Epic and all children without confirmation
$result = .\RemoveAzDoEpic.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -EpicId 100 `
    -Recursive `
    -Force

# Check results
$result.DeletedCount   # Number of successfully deleted items
$result.SkippedCount   # Number of items that failed to delete
$result.Cancelled      # Whether user cancelled operation
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `EpicId` (required): Epic ID to delete
- `Recursive` (switch): Delete all child Features, Stories, and Tasks before deleting the Epic
- `Force` (switch): Skip confirmation prompt
- `PatToken` (optional): Override default PAT token

**Behavior:**
- Without `-Recursive`: Deletes only the Epic; warns if child work items exist (they become orphaned)
- With `-Recursive`: Lists all descendants, deletes children first (leaf-to-root), then the Epic
- Without `-Force`: Requires user confirmation (type "YES")
- With `-Force`: Deletes immediately without confirmation
- Returns summary hashtable with `Cancelled`, `DeletedCount`, `SkippedCount`

#### `RemoveAzDoFeature.ps1`
Delete a Feature, optionally including all child work items (DESTRUCTIVE OPERATION).

```powershell
# Delete Feature only (children become orphaned, warning shown if children exist)
$result = .\RemoveAzDoFeature.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -FeatureId 200

# Delete Feature and all children recursively
$result = .\RemoveAzDoFeature.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -FeatureId 200 `
    -Recursive -Force
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `FeatureId` (required): Feature ID to delete
- `Recursive` (switch): Delete all child Stories, Tasks, and Bugs before deleting the Feature
- `Force` (switch): Skip confirmation prompt
- `PatToken` (optional): Override default PAT token

**Behavior:**
- Without `-Recursive`: Deletes only the Feature; warns if child work items exist (they become orphaned)
- With `-Recursive`: Lists all descendants, deletes children first (leaf-to-root), then the Feature
- Returns summary hashtable with `Cancelled`, `DeletedCount`, `SkippedCount`

#### `RemoveAzDoStory.ps1`
Delete a Story, optionally including child Tasks (DESTRUCTIVE OPERATION).

```powershell
# Delete Story only (child Tasks become orphaned, warning shown if children exist)
$result = .\RemoveAzDoStory.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -StoryId 300

# Delete Story and all child Tasks
$result = .\RemoveAzDoStory.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -StoryId 300 `
    -Recursive -Force
```

**Parameters:**
- `Organization` (required): Azure DevOps organization
- `Project` (required): Project name
- `StoryId` (required): Story ID to delete
- `Recursive` (switch): Delete all child Tasks before deleting the Story
- `Force` (switch): Skip confirmation prompt
- `PatToken` (optional): Override default PAT token

**Behavior:**
- Without `-Recursive`: Deletes only the Story; warns if child Tasks exist (they become orphaned)
- With `-Recursive`: Deletes all child Tasks first, then the Story
- Returns summary hashtable with `Cancelled`, `DeletedCount`, `SkippedCount`

## Environment Variables

### Required
- **GMD_AZDO_MACHINE_WORKITEMSRW**: Personal Access Token (recommended: encrypted)

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

## Example Hierarchy

The repository includes an example hierarchy file that matches the parser format used by `NewAzDoHierarchyFromMarkdown.ps1` and demonstrates how to structure Epics, Features, Stories, Acceptance Criteria, AC Scenarios, tags and story points.

See the full example in [example-hierarchy.md](example-hierarchy.md).

## Unified Field and State Configuration

`appSettings.json` is the single source of truth for field definitions and state definitions per organization, project, and work item type. It replaces the older per-org `azdoStateConfig-{org}-{project}.json` approach for state configuration and extends it with full field metadata.

### appSettings.json

Located at the repository root. Structure:

```json
{
  "organizations": {
    "{org}": {
      "projects": {
        "{project}": {
          "fields": {
            "Story": [
              {
                "referenceName": "Microsoft.VSTS.Scheduling.StoryPoints",
                "label": "Story Points",
                "description": "Work item estimation",
                "type": "integer",
                "readOnly": false
              }
            ],
            "Epic": [ ... ],
            "Feature": [ ... ],
            "Task": [ ... ],
            "Bug": [ ... ]
          },
          "states": {
            "Story": [
              { "name": "New",    "category": "Proposed", "readOnly": false },
              { "name": "Active", "category": "InProgress", "readOnly": false },
              { "name": "Closed", "category": "Completed", "readOnly": true }
            ]
          }
        }
      }
    }
  }
}
```

Key rules:
- `readOnly: true` on a **field** means it cannot be passed via `-Fields` to any Upsert script
- `readOnly: true` on a **state** means it is a terminal state and cannot be transitioned to via `-State`
- `System.AssignedTo` is always listed as a writable `identity`-type field; use the dedicated `-AssignedTo` email parameter instead of putting it in `-Fields`

### LoadFieldConfiguration.ps1

Loads field definitions for a given work item type from `appSettings.json`. Called internally by:
- `GetAzDoWorkItem.ps1` — to build named properties on the result object
- `ValidateUpsertFields.ps1` — to check field writeability before any Upsert API call
- `GenerateAzDoMarkdownHierarchyTemplate.ps1` — to append the SUPPORTED FIELDS REFERENCE section

### ValidateUpsertFields.ps1

Provides two pre-flight guard functions called automatically by all five Upsert scripts:

| Function | Purpose |
|---|---|
| `Assert-FieldsNotReadOnly` | Throws if any key in `-Fields` is `readOnly: true` in `appSettings.json` |
| `Assert-StateIsWritable` | Throws if `-State` is a terminal state (`readOnly: true`) in `appSettings.json` |

Both functions are silent no-ops when `appSettings.json` is absent or has no matching entry for the org/project.

### AssignedTo Support

All five Upsert scripts accept an `-AssignedTo <email>` parameter. Before any API call, the email is resolved to an Azure DevOps identity via `ResolveAzDoIdentity.ps1`. If no matching identity is found, the script fails immediately with a descriptive error.

`GetAzDoWorkItem.ps1`, `GetAzDoUserStory.ps1`, and `GetAzDoBug.ps1` all normalize the `System.AssignedTo` field into a `[PSCustomObject]@{ DisplayName; UniqueName }` object on the returned result.

### SyncAppSettingsFields.ps1

Synchronizes the field definitions in `appSettings.json` against the live Azure DevOps project. Queries each work item type via the REST API and adds any fields that are missing from `appSettings.json`. Existing entries are never modified, preserving curated labels, descriptions, and `readOnly` overrides.

Use `-DryRun` to preview changes without writing to disk. Use `-Prune` to also remove entries whose `referenceName` is no longer returned by the API.

**Parameters**

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|-------------|
| Organization | string | No | Azure DevOps organization name (default: `$env:GMD_AZDO_ORGANIZATION`) |
| Project | string | No | Azure DevOps project name (default: `$env:GMD_AZDO_PROJECT`) |
| PatToken | string | No | PAT token (defaults to `$env:GMD_AZDO_MACHINE_WORKITEMSRW`) |
| RepositoryRoot | string | No | Directory containing `appSettings.json` (default: parent of script directory) |
| DryRun | switch | No | Preview additions/removals without writing to disk |
| Prune | switch | No | Remove entries no longer returned by the API (use with caution) |

```powershell
# Preview what fields would be added
.\src\SyncAppSettingsFields.ps1 -DryRun

# Apply additions
.\src\SyncAppSettingsFields.ps1

# Apply additions and remove stale entries
.\src\SyncAppSettingsFields.ps1 -Prune
```

Pipeline output shape per change:

| Property | Description |
|----------|-------------|
| WorkItemType | Epic / Feature / User Story / Bug / Task |
| ReferenceName | Field reference name (e.g. `Custom.ExtraInformation`) |
| Label | Field display name |
| ChangeType | `Add` or `Remove` |

## State Configuration Management

The State Configuration system enables team-specific rules for which work item states are editable during hierarchy exports and reimports. This supports multiple organizations and projects with organization/project-scoped configuration files and sensible defaults.

> **Note:** State configuration is defined inside `appSettings.json` (see [Unified Field and State Configuration](#unified-field-and-state-configuration)). The legacy `azdoStateConfig-{org}-{project}.json` format is no longer used.

### Overview

State configuration defines "writable states" for each work item type, allowing teams to:
- Control which Azure DevOps states can be modified during export-import operations
- Define organization/project-specific state rules
- Use sensible defaults when no configuration is provided
- Store configuration in version control for team collaboration
- Support environment-specific overrides for CI/CD pipelines

### Configuration

Writable states are defined under `organizations.{org}.projects.{project}.states` in `appSettings.json`. Each state entry has a `name`, `category`, and `readOnly` flag. States with `readOnly: false` are writable; `Completed` and `Removed` category states are read-only.

**Example `appSettings.json` states section:**

```json
{
  "organizations": {
    "falco-it": {
      "projects": {
        "GMD": {
          "states": {
            "Story": [
              { "name": "New", "category": "Proposed", "readOnly": false },
              { "name": "Under Development", "category": "InProgress", "readOnly": false },
              { "name": "Released", "category": "Completed", "readOnly": true }
            ]
          }
        }
      }
    }
  }
}
```

### Loading Configuration

Use the `LoadStateConfiguration.ps1` script to load and cache state configuration:

```powershell
# Load configuration for an organization and project
$config = .\LoadStateConfiguration.ps1 -Organization "falco-it" -Project "GMD"
$epicStates = $config.writableStates.Epic

# Alternative: specify custom repository root
$config = .\LoadStateConfiguration.ps1 -Organization "contoso" -Project "web" `
    -RepositoryRoot "C:\myrepo"

# Force reload from file (bypass cache)
$config = .\LoadStateConfiguration.ps1 -Organization "falco-it" -Project "GMD" -Force
```

### Default Behavior

When a configuration file is not found, sensible defaults are automatically applied. Only "New" and "Active" states are writable by default. Terminal states like "Done" and "Closed" should never be modified during export-import operations:

```powershell
# Configuration file azdoStateConfig-temp-test.json not found?
# Default configuration is returned with these states:

@{
    writableStates = @{
        "Epic"    = @("New", "Active")
        "Feature" = @("New", "Active")
        "Story"   = @("New", "Active")
        "Task"    = @("New", "Active")
        "Bug"     = @("New", "Active")
    }
}
```

### Configuration Features

- **Memory Caching**: Configuration is cached after first load to avoid repeated file I/O operations
- **Organization/Project Scoping**: `appSettings.json` supports multiple org/project pairs in one file
- **Version Control**: `appSettings.json` is committed to version control for team collaboration
- **Structure Validation**: Invalid configuration is detected and reported with clear error messages

### Troubleshooting

#### State Configuration Not Found

**Symptom**: `LoadStateConfiguration` returns default states instead of project-specific configuration

**Solution**:
1. Verify the `states` key exists under `organizations.{org}.projects.{project}` in `appSettings.json`
2. Ensure the organization and project names match exactly
3. Verify the file contains valid JSON

```powershell
# Debug: check resolved writable states
$config = .\LoadStateConfiguration.ps1 -Organization "falco-it" -Project "GMD"
$config.writableStates  # Shows writable states per work item type
```

#### Performance/Caching Issues

**Symptom**: Changed configuration is not reflected in subsequent script calls

**Solution**: Use the `-Force` parameter to bypass the in-memory cache and reload from file:

```powershell
# Force reload configuration from file
$config = .\LoadStateConfiguration.ps1 -Organization "falco-it" -Project "GMD" -Force
```

### Best Practices

1. **Store in Version Control**: `appSettings.json` covers both field and state config in one file
2. **Document States**: Keep state definitions accurate and up to date with your AzDo process
3. **Test Configuration**: Verify configuration with small test hierarchies before large exports

## Export-Modify-Reimport Workflow

The Azure DevOps Automator supports a complete export-modify-reimport workflow that enables teams to:
- Export work item hierarchies to markdown for external editing
- Detect changes between original and modified versions
- Apply validated changes back to Azure DevOps with transaction-like safety
- Maintain work item IDs and parent-child relationships throughout the cycle

### Complete Workflow

**Step 1: Export Hierarchy to Markdown**

Use `ConvertHierarchyToMarkdown.ps1` to export a hierarchy with work item IDs and state validation:

```powershell
# Export a Feature hierarchy to markdown
$hierarchy = .\GetAzDoHierarchyForFeature.ps1 `
    -Organization "falco-it" `
    -Project "GMD" `
    -FeatureId 2216

$markdown = .\ConvertHierarchyToMarkdown.ps1 `
    -Hierarchy $hierarchy `
    -ValidateStateChanges

$markdown | Out-File "feature-export.md"
```

The exported markdown includes:
- **WorkItemId** for round-trip identification
- **State** field for writable state validation  
- **Tags** and custom fields
- Read-only warnings for non-writable states

**Step 2: Modify the Markdown File**

Users edit the markdown file externally:
- Change titles, descriptions, story points
- Add new work items (without WorkItemId)
- Update tags and other fields
- The markdown structure preserves parent-child relationships

```markdown
## Feature: Auth Feature
{WorkItemId}: 2216
{State}: Active
{Effort}: 13
{Description}
Authentication module for user management

### Story: Login
{WorkItemId}: 2217
{State}: Active
{Story Points}: 5
{Description}
Implement user login functionality

### Story: Password Reset
{Story Points}: 3
{Description}
Add password recovery feature (no WorkItemId = new item)
```

**Step 3: Parse Modified Markdown**

Use `ConvertMarkdownToHierarchyJson.ps1` to parse the modified markdown:

```powershell
$modifiedContent = Get-Content "feature-export.md" -Raw

$modifiedHierarchy = .\ConvertMarkdownToHierarchyJson.ps1 `
    -MarkdownContent $modifiedContent

# Result: JSON hierarchy with all changes preserved
```

**Step 4: Detect Changes**

Use `DetectHierarchyChanges.ps1` to compare original and modified versions:

```powershell
# Load original hierarchy from export
$originalHierarchy = Get-Content "original-hierarchy.json" | ConvertFrom-Json

# Detect changes with validation
$diff = .\DetectHierarchyChanges.ps1 `
    -OriginalHierarchy $originalHierarchy `
    -ModifiedHierarchy $modifiedHierarchy

if ($diff.validationPassed) {
    Write-Host "Safe to apply: $($diff.operations.Count) changes"
} else {
    Write-Host "Errors: $($diff.errors -join '; ')"
}
```

The diff output includes:
- **Field-level changes** with before/after values
- **New work items** (identified by missing WorkItemId)
- **Hierarchy reorganizations** (parent-child changes)
- **Validation errors** preventing dangerous modifications
- **Dependency order** for safe application

**Step 5: Apply Changes Back**

Use `ApplyValidatedChanges.ps1` to apply changes to Azure DevOps:

```powershell
# First, dry-run to see what would happen
$result = .\ApplyValidatedChanges.ps1 `
    -ValidatedDiff $diff `
    -DryRun

if ($result.success) {
    Write-Host "Dry-run OK. Would apply $($result.appliedChanges) changes"
    
    # Now apply for real
    $actualResult = .\ApplyValidatedChanges.ps1 -ValidatedDiff $diff
    
    if ($actualResult.success) {
        Write-Host "Applied all changes successfully"
        $actualResult.operationsSummary | Format-Table
    } else {
        Write-Host "Failed: $($actualResult.failureReason)"
    }
}
```

### Change Detection Validation

Dangerous modifications are prevented with comprehensive validation:

1. **Deletion Prevention**: Parent items with pending child modifications cannot be deleted
2. **State Validation**: State changes respect configured writable states
3. **Orphan Detection**: Changes that would create orphaned items are rejected
4. **ID Verification**: Existing work item IDs are validated to exist in Azure DevOps
5. **Circular References**: Parent-child cycles are detected and prevented

### Hierarchy Reorganization (Reparenting)

The workflow supports reorganizing work item hierarchies through reparenting—moving work items to different parents while preserving their identity:

**Scenario: Consolidate Stories from Multiple Features**

```powershell
# Export epic with multiple features
$hierarchy = .\GetAzDoHierarchyForEpic.ps1 -Organization "falco-it" -Project "GMD" -EpicId 1577
$exported = .\ConvertHierarchyToMarkdown.ps1 -Hierarchy $hierarchy
$exported | Out-File "epic-export.md"

# Edit markdown to consolidate all stories under one target feature:
# - Move all stories from Feature A to Feature C
# - Move all stories from Feature B to Feature C
# - Keep original features (they become empty)

$modified = Get-Content "epic-export.md" -Raw
$modifiedJson = .\ConvertMarkdownToHierarchyJson.ps1 -MarkdownContent $modified
$original = $exported | ConvertFrom-Json

# Detect the reorganization (will show "Move" operations for each story)
$diff = .\DetectHierarchyChanges.ps1 -OriginalHierarchy $original -ModifiedHierarchy $modifiedJson

# DryRun to preview
$preview = .\ApplyValidatedChanges.ps1 -ValidatedDiff $diff -DryRun

# Apply the reparenting
$result = .\ApplyValidatedChanges.ps1 -ValidatedDiff $diff

# Result in Azure DevOps:
# - All stories now under Feature C
# - Feature A, B, C still exist (A and B as empty)
# - All story IDs and content preserved
```

### Safety Features

- **Transaction-like behavior**: All changes succeed or none do (fail-fast approach)
- **DryRun mode**: Preview changes without applying them
- **Detailed reporting**: Every change is logged with before/after values
- **No silent skips**: Errors halt the entire operation; never skip silently
- **Rollback capability**: If any change fails, remaining changes are not attempted

### Example: Complete Workflow

```powershell
# 1. Export
$feature = .\GetAzDoHierarchyForFeature.ps1 -Organization "falco-it" -Project "GMD" -FeatureId 2216
$original = .\ConvertHierarchyToMarkdown.ps1 -Hierarchy $feature | Out-File "export.md"
$originalJson = .\ConvertMarkdownToHierarchyJson.ps1 -MarkdownFilePath "export.md"

# ... User edits export.md ...

# 2. Reimport
$modified = Get-Content "export.md" -Raw
$modifiedJson = .\ConvertMarkdownToHierarchyJson.ps1 -MarkdownContent $modified

# 3. Detect
$diff = .\DetectHierarchyChanges.ps1 `
    -OriginalHierarchy $originalJson `
    -ModifiedHierarchy $modifiedJson

# 4. Apply
if ($diff.validationPassed) {
    $result = .\ApplyValidatedChanges.ps1 -ValidatedDiff $diff -DryRun
    if ($result.success) {
        $final = .\ApplyValidatedChanges.ps1 -ValidatedDiff $diff
        $final.operationsSummary | Where-Object { $_.status -eq 'Applied' }
    }
}
```

## Download and Compare Workflow

Use this workflow when you have a local markdown plan (e.g. `testEpic.md`) and want to compare it with the current state in Azure DevOps — for example, to see what changed between your plan and what was actually created, or to review differences before applying changes.

### Overview

| Step | Script | Purpose |
|------|--------|---------|
| 1 | `src/tools/ExportAzDoHierarchyToMarkdown.ps1` | Download current AzDo hierarchy to a markdown file |
| 2 | `src/tools/SortMarkdownHierarchy.ps1` | Sort both files by WorkItemId for clean diffing |
| 3 | Diff tool (e.g. `code --diff`) | Side-by-side comparison |

### Step 1: Download Current Hierarchy from Azure DevOps

Use `ExportAzDoHierarchyToMarkdown.ps1` to download an Epic, Feature, or Story hierarchy to a markdown file:

```powershell
# Export an Epic hierarchy
.\src\tools\ExportAzDoHierarchyToMarkdown.ps1 `
    -Organization "falco-it" `
    -Project "GMD" `
    -EpicId 2535 `
    -OutputFile azDoEpic.md

# Export a Feature hierarchy
.\src\tools\ExportAzDoHierarchyToMarkdown.ps1 `
    -Organization "falco-it" `
    -Project "GMD" `
    -FeatureId 2536 `
    -OutputFile azDoFeature.md

# Using environment variables for org/project
$env:GMD_AZDO_ORGANIZATION = "falco-it"
$env:GMD_AZDO_PROJECT = "GMD"
.\src\tools\ExportAzDoHierarchyToMarkdown.ps1 -EpicId 2535 -OutputFile azDoEpic.md
```

**Parameters:**
- `Organization` (optional): Azure DevOps organization. Falls back to `GMD_AZDO_ORGANIZATION` env variable.
- `Project` (optional): Azure DevOps project. Falls back to `GMD_AZDO_PROJECT` env variable.
- `EpicId` / `FeatureId` / `StoryId` (one required): Work item ID to export.
- `OutputFile` (required): Path to write the exported markdown. Overwritten if it exists.
- `RepositoryRoot` (optional): Root directory for state configuration. Default: repository root.
- `PatToken` (optional): PAT token override.

### Step 2: Sort Both Files for Clean Diffing

The local plan and the AzDo export may have work items in different orders. Use `SortMarkdownHierarchy.ps1` to normalize both files by sorting work items by WorkItemId at each level:

```powershell
# Sort both files (outputs testEpic-sorted.md and azDoEpic-sorted.md)
.\src\tools\SortMarkdownHierarchy.ps1 -MarkdownFile testEpic.md -MarkdownFile2 azDoEpic.md

# Specify explicit output paths
.\src\tools\SortMarkdownHierarchy.ps1 `
    -MarkdownFile testEpic.md     -OutputFile testEpic-sorted.md `
    -MarkdownFile2 azDoEpic.md    -OutputFile2 azDoEpic-sorted.md

# Sort a single file only
.\src\tools\SortMarkdownHierarchy.ps1 -MarkdownFile testEpic.md
```

**Parameters:**
- `MarkdownFile` (required): First markdown file to sort.
- `OutputFile` (optional): Output for sorted first file. Default: original name with `-sorted` suffix (e.g. `testEpic.md` → `testEpic-sorted.md`).
- `MarkdownFile2` (optional): Second markdown file to sort in the same call.
- `OutputFile2` (optional): Output for sorted second file.

**Sorting behaviour:**
- Items with a `WorkItemId` are sorted ascending by ID.
- Items without a `WorkItemId` (new items in your plan) are placed after sorted items, ordered alphabetically by title.
- Trailing markdown whitespace (`  `) and state warning HTML comments are stripped for clean comparison.
- Both files are serialized in the same canonical format, making content differences the focus of the diff.

### Step 3: Diff the Sorted Files

```powershell
# VS Code side-by-side diff
code --diff testEpic-sorted.md azDoEpic-sorted.md

# Or use any diff tool
diff testEpic-sorted.md azDoEpic-sorted.md
```

### Complete Workflow Example

```powershell
# 1. Download current AzDo state for Epic 2535
.\src\tools\ExportAzDoHierarchyToMarkdown.ps1 -EpicId 2535 -OutputFile azDoEpic.md

# 2. Sort both files for clean comparison
.\src\tools\SortMarkdownHierarchy.ps1 -MarkdownFile testEpic.md -MarkdownFile2 azDoEpic.md

# 3. Open side-by-side diff in VS Code
code --diff testEpic-sorted.md azDoEpic-sorted.md
```

### What the diff will show

| Difference | Meaning |
|------------|---------|
| `State: New` in AzDo only | AzDo items have state; local plan typically does not |
| Tags with `;` in AzDo vs `,` in local | AzDo uses semicolons as tag separator |
| Work item present in local only (no WorkItemId) | New item in your plan not yet created in AzDo |
| Field value differences | Content was changed in your plan or directly in AzDo |
| Item order differences | Only visible before sorting; sorting normalises this |

## Recipes

### Generate Azure DevOps Hierarchy from Markdown

Use this recipe when you have a markdown file describing your planned work (Epics, Features, Stories, Tasks) and want to create or update the corresponding work items in Azure DevOps in one step.

**Key behaviours:**
- First run: creates all work items and writes the assigned `**WorkItemId**: <id>` back into the markdown file
- Subsequent runs: uses those IDs to **update** existing items — no duplicates are ever created
- DryRun mode lets you preview what will be created or updated before committing

#### Prerequisites

1. Set the required environment variables:

```powershell
$env:GMD_AZDO_ORGANIZATION = "your-org"
$env:GMD_AZDO_PROJECT      = "your-project"
# Store an encrypted PAT (see Setup section)
```

2. Have a markdown hierarchy file ready (use `GenerateAzDoMarkdownHierarchyTemplate.ps1` to scaffold one):

```powershell
# Generate a template to start from
.\src\GenerateAzDoMarkdownHierarchyTemplate.ps1 -IncludeExample > my-hierarchy.md
# Edit my-hierarchy.md with your Epic / Feature / Story titles
```

#### Step 1: Preview what will be created (DryRun)

```powershell
.\src\NewAzDoHierarchyFromMarkdown.ps1 -MarkdownFile ".\my-hierarchy.md" -DryRun
```

The output shows a breakdown of items to create vs. update without touching Azure DevOps.

#### Step 2: Create the hierarchy

```powershell
.\src\NewAzDoHierarchyFromMarkdown.ps1 -MarkdownFile ".\my-hierarchy.md"
```

After this runs, `my-hierarchy.md` is updated in-place with `{WorkItemId}: <id>` lines inserted after each work item header. Example result:

```markdown
# Epic: My Project Epic
{WorkItemId}: 2215
{tags}: myProject
{Description}
Epic description...

## Feature: User Authentication
{WorkItemId}: 2216
...
```

#### Step 3: Update existing items (subsequent runs)

Run the **exact same command** again at any time. The IDs already in the file are used to update the existing work items rather than create new ones:

```powershell
# Same command — updates existing items because WorkItemIds are now in the file
.\src\NewAzDoHierarchyFromMarkdown.ps1 -MarkdownFile ".\my-hierarchy.md"
```

#### Notes

- To nest the hierarchy under an existing Epic pass `-EpicId <id>`
- Use `-UpdateExisting` to enable title-based matching as a fallback for items without a `WorkItemId` in the markdown
- The markdown file is only written when `-MarkdownFile` is used (not when `-MarkdownContent` is passed as a string)

---

### Update Hierarchy Structure in Azure DevOps

This recipe demonstrates how to reorganize your Azure DevOps work item hierarchy. Use this workflow when you need to:
- Move stories from one feature to another
- Consolidate multiple features into one
- Reorganize work items while preserving their identity and metadata
- Make bulk structural changes with full validation and preview

**Overview of the three-step process:**
1. **Export** the hierarchy from Azure DevOps to markdown
2. **Modify** the markdown structure (change parent-child relationships)
3. **Reimport** the changes back to Azure DevOps

#### Step 1: Export Existing Hierarchy to Markdown

Export your current hierarchy from Azure DevOps:

```powershell
# First, find the Epic ID you want to work with
$epic = .\GetAzDoHierarchyForEpic.ps1 `
    -Organization "falco-it" `
    -Project "GMD" `
    -EpicTitle "My Epic Name"

# Export the hierarchy to markdown format
$hierarchy = .\GetAzDoHierarchyForEpic.ps1 `
    -Organization "falco-it" `
    -Project "GMD" `
    -EpicId $epic.Id

$markdown = .\ConvertHierarchyToMarkdown.ps1 -Hierarchy $hierarchy

# Save to file for editing
$markdown | Out-File "hierarchy-export.md" -Encoding UTF8
```

**What the exported markdown looks like:**
```markdown
# Epic: System Architecture Redesign (ID: 1577)

## Feature: API Layer Refactoring (ID: 1578)
- Story: Redesign REST API endpoints (ID: 1579)
- Story: Implement GraphQL support (ID: 1580)

## Feature: Database Optimization (ID: 1581)
- Story: Migrate to NoSQL (ID: 1582)
- Story: Add caching layer (ID: 1583)
```

#### Step 2: Modify the Markdown Structure

Edit the markdown file to reorganize your work items. You can:
- **Move stories** to different features by changing the indentation
- **Change feature order** by reordering sections
- **Keep work item IDs** intact (they're preserved in the markdown)

**Example: Consolidate all stories into a single feature**

Original structure:
```markdown
# Epic: System Redesign (ID: 1577)

## Feature: API Layer (ID: 1578)
- Story: Refactor endpoints (ID: 1579)
- Story: Add GraphQL (ID: 1580)

## Feature: Database (ID: 1581)
- Story: Migrate data (ID: 1582)
- Story: Add caching (ID: 1583)
```

Modified structure (all stories under Feature: Database):
```markdown
# Epic: System Redesign (ID: 1577)

## Feature: API Layer (ID: 1578)
# (now empty)

## Feature: Database (ID: 1581)
- Story: Refactor endpoints (ID: 1579)
- Story: Add GraphQL (ID: 1580)
- Story: Migrate data (ID: 1582)
- Story: Add caching (ID: 1583)
```

**What you can modify:**
- ✅ Move work items to different parents
- ✅ Add new work items (add new story/feature lines)
- ✅ Update descriptions and story points (edit text after the ID)
- ✅ Reorder work items
- ✅ Change field values

**What you cannot modify:**
- ❌ Change work item IDs (they're part of the round-trip mechanism)
- ❌ Change the work item type (Story stays a Story, Feature stays a Feature)

#### Step 3: Reimport Changes Back to Azure DevOps

After modifying the markdown, reimport your changes back to Azure DevOps with full validation and preview:

**Option A: Interactive Script (Recommended)**

Use the interactive script for guided workflow with automatic editor support and safety prompts:

```powershell
# Automatically exports, opens editor, previews, and applies changes
.\src\tools\interactive-update-hierarchy.ps1 `
    -Organization "falco-it" `
    -Project "GMD" `
    -EpicId 1577

# Or with pre-existing markdown file
.\src\tools\interactive-update-hierarchy.ps1 `
    -Organization "falco-it" `
    -Project "GMD" `
    -EpicId 1577 `
    -MarkdownFile "./hierarchy-modified.md"

# Or with debug mode to preview changes without applying
.\src\tools\interactive-update-hierarchy.ps1 `
    -Organization "falco-it" `
    -Project "GMD" `
    -EpicId 1577 `
    -MarkdownFile "./hierarchy-modified.md" `
    -RunAsDebug

# Or with existing original markdown (skip re-fetching from Azure DevOps)
.\src\tools\interactive-update-hierarchy.ps1 `
    -Organization "falco-it" `
    -Project "GMD" `
    -EpicId 1577 `
    -MarkdownFile "./hierarchy-modified.md" `
    -OriginalMarkdownPath "./hierarchy-export-original.md"
```

**interactive-update-hierarchy.ps1 Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Organization` | string | Yes | Azure DevOps organization name |
| `-Project` | string | Yes | Azure DevOps project name |
| `-EpicId` / `-FeatureId` / `-StoryId` | int | Yes (one) | Work item ID to export and modify |
| `-MarkdownFile` | string | No | Path to markdown file with modifications. If omitted, opens editor for you |
| `-OriginalMarkdownPath` | string | No | Path to existing original hierarchy markdown. If provided, skips fetching from Azure DevOps (useful for iterating on changes without repeated API calls) |
| `-SkipEditor` | switch | No | Don't open markdown file in editor (useful for automated workflows) |
| `-RunAsDebug` | switch | No | Debug mode: runs through all steps but stops after preview without applying changes. Skips user confirmation prompt |
| `-RepositoryRoot` | string | No | Root directory for state configuration. Default: current working directory |

**Option B: Manual Step-by-Step**

```powershell
# Step 3a: Get the ORIGINAL hierarchy from Azure DevOps (not from markdown)
$originalHierarchy = .\GetAzDoHierarchyForEpic.ps1 `
    -Organization "falco-it" `
    -Project "GMD" `
    -EpicId 1577

# Step 3b: Read the MODIFIED markdown file
$modifiedMarkdown = Get-Content "hierarchy-export.md" -Raw

# Step 3c: Convert modified markdown to JSON structure
$modifiedHierarchy = .\ConvertMarkdownToHierarchyJson.ps1 `
    -MarkdownContent $modifiedMarkdown

# Step 3d: Detect what changed between original and modified
$diff = .\DetectHierarchyChanges.ps1 `
    -OriginalHierarchy $originalHierarchy `
    -ModifiedHierarchy $modifiedHierarchy

# Step 3e: Preview changes WITH DryRun (always do this first!)
Write-Host "Preview of changes (DRY RUN):" -ForegroundColor Cyan
$preview = .\ApplyValidatedChanges.ps1 `
    -ValidatedDiff $diff `
    -DryRun:$true

Write-Host "Operations to be applied:" -ForegroundColor Yellow
$preview.operations | Format-Table @(
    @{ Label = "Type"; Expression = { $_.operationType } },
    @{ Label = "Item"; Expression = { $_.itemTitle } },
    @{ Label = "Status"; Expression = { $_.status } }
) -AutoSize

# Step 3f: After reviewing preview, apply the changes
$confirm = Read-Host "Apply these changes? (yes/no)"
if ($confirm -eq "yes") {
    Write-Host "`nApplying changes..." -ForegroundColor Cyan
    $result = .\ApplyValidatedChanges.ps1 `
        -ValidatedDiff $diff `
        -DryRun:$false
    Write-Host "✓ Changes applied successfully!" -ForegroundColor Green
}
```

#### Complete Recipe Using Interactive Script

For the easiest workflow, use the interactive script which handles all three steps:

```powershell
# Run the interactive update script
.\src\tools\interactive-update-hierarchy.ps1 `
    -Organization "falco-it" `
    -Project "GMD" `
    -EpicId 1577

# The script will:
# 1. Export the current hierarchy from Azure DevOps
# 2. Open it in your default editor for modification
# 3. Wait for you to finish editing and close the editor
# 4. Show a preview of all changes (DRY RUN)
# 5. Ask for confirmation before applying
# 6. Apply the validated changes
# 7. Show results summary
```

#### Workflow Tips

**Best Practices:**
1. **Always use DryRun first** - Preview changes before applying them
2. **Export first, then modify** - Keep the original exported file as backup
3. **Test with a small hierarchy** - Validate the workflow on simpler structures before complex ones
4. **Validate your markdown** - Use proper formatting (verify indentation and structure)
5. **Preserve work item IDs** - Never manually change the work item ID numbers

**Common Scenarios:**

| Scenario | Steps | Result |
|----------|-------|--------|
| Move stories to different feature | Export → Modify parent → Reimport | Stories reparented, IDs preserved |
| Consolidate features | Export → Move all stories to target feature → Reimport | Empty source features, stories in target |
| Combine two epics | Export first epic → Manually update parent IDs → Reimport | All items now under one epic |
| Add new work items | Export → Add new story/feature lines → Reimport | New items created linked to parents |

**Validation Rules:**
- All work item IDs must be unique
- Parent-child relationships must be valid (Story can't be parent of Feature)
- Work item types cannot change through modifications
- State changes are validated against configured writable states

## MCP Server Integration


The Azure DevOps Automator project includes full Model Context Protocol (MCP) support, enabling all tools to be consumed by AI assistants and automation frameworks over HTTP.

### What is MCP?

Model Context Protocol (MCP) is a standard for AI agents to interact with external tools through a standardized interface. The MCP server exposes all PowerShell scripts as tools that can be:
- Called by AI agents (ChatGPT, Claude, etc.)
- Used in automation workflows
- Integrated with other systems
- Access controlled via HTTP

### MCP Configuration

The `src/mcpConfig.yaml` file defines 33 tools mapped to PowerShell scripts. All tools automatically retrieve organization, project, and authentication details from environment variables:

- `$env:GMD_AZDO_ORGANIZATION`: Azure DevOps organization name
- `$env:GMD_AZDO_PROJECT`: Azure DevOps project name  
- `$env:GMD_AZDO_MACHINE_WORKITEMSRW`: Personal Access Token for authentication

**Tool Categories:**
- **Get Operations** (8): Retrieve work items, comments, hierarchies
- **Set Operations** (6): Update properties (story points, effort, tags, description)
- **New Operations** (2): Create comments and reactions
- **Upsert Operations** (5): Create/update Epics, Features, Stories, Tasks, Bugs — all accept `Fields` (object), `State` (string), and `AssignedTo` (string/email) parameters; tool descriptions inline the list of writable fields from `appSettings.json`
- **Remove Operations** (7): Delete work items and comments (Epic, Feature, Story, Bug, Task, Comment, CommentReaction)
- **Update Operations** (2): Modify existing comments and tags
- **Find Operations** (1): Search for work items by title
- **Generate/Validate** (3):
  - `generate-markdown-hierarchy-template`: Create template with rules and SUPPORTED FIELDS REFERENCE
  - `convert-markdown-to-hierarchy-json`: Validate structure
  - `create-workitems-from-markdown`: Create items in Azure DevOps

### Starting the MCP Server

The `src/tools/runMcpServerHttp.ps1` script starts the MCP server with HTTP configuration:

```powershell
# Start on default port 8081
.\src\tools\runMcpServerHttp.ps1

# Start on custom port
.\src\tools\runMcpServerHttp.ps1 -HttpPort 3000

# Start with verbose logging
.\src\tools\runMcpServerHttp.ps1 -HttpPort 8081 -Verbose
```

The server will be accessible at:
```
http://localhost:8081
```

### MCP Server Files

- **Config**: `src/mcpConfig.yaml` - Tool definitions and mappings
- **Launcher**: `src/tools/runMcpServerHttp.ps1` - Start server script
- **Validator**: `test/ValidateMcpConfigTest.ps1` - Validate config
- **MCP Runtime**: `submodules/Gmd.Tools.McpServerPs/` - MCP server engine

### Validation

The MCP configuration is automatically validated to ensure:
- All tools have unique IDs
- All referenced scripts exist in `src/`
- Tool names follow lowercase verb-noun pattern
- All parameters are properly mapped
- No orphaned configurations

Validate the configuration:

```powershell
.\test\ValidateMcpConfigTest.ps1 -Verbose
```

### Using Tools via MCP

Once the MCP server is running, AI agents and clients can invoke tools:

**Example: Generate markdown template**
```
Tool: generate-markdown-hierarchy-template
Parameters: { IncludeExample: true }
Output: Markdown template with rules and examples
```

**Example: Create work items**
```
Tool: create-workitems-from-markdown
Parameters: {
  Organization: "myorg",
  Project: "myproject",
  MarkdownFilePath: "hierarchy.md",
  DryRun: true
}
Output: Preview of work items to be created
```

### AI Agent Workflow (via MCP)

1. **Agent requests template**: AI calls `generate-markdown-hierarchy-template`
2. **Agent generates plan**: AI creates markdown with rules
3. **Agent validates plan**: AI calls `convert-markdown-to-hierarchy-json`
4. **Agent previews**: AI calls `create-workitems-from-markdown` with `DryRun: true`
5. **Agent creates**: AI calls `create-workitems-from-markdown` (without DryRun)
6. **Agent manages**: AI uses get/set/update tools to manage created items

## Testing

### Unit and Module Tests

Run basic integration tests to verify setup:

```powershell
.\test\BasicIntegrationTest.ps1
```

Tests verify:
- All helper modules load correctly
- All functions are defined
- Constants are properly initialized
- Required scripts exist and are accessible

### Run All Tests - Master Test Runner

Execute all tests with a single command:

```powershell
# Run all tests
.\test\RunAllTests.ps1

# Run with verbose output for debugging
.\test\RunAllTests.ps1 -Verbose

# Skip specific test suites
.\test\RunAllTests.ps1 -SkipBasicTests
.\test\RunAllTests.ps1 -SkipGetAzDoUserStoryTests
.\test\RunAllTests.ps1 -SkipGetAzDoHierarchyTests

# Run against different organization/project
.\test\RunAllTests.ps1 -Organization "my-org" -Project "my-project"
```

**Master Test Runner Output:**
- Colored output showing test pass/fail status
- Detailed execution times for each test suite
- Summary with pass rate percentage
- Detailed error information for failed tests

**Exit Codes:**
- 0: All tests passed
- 1: One or more tests failed

### Integration Tests for New Scripts

Test individual script suites against a live Azure DevOps instance:

```powershell
# Set environment variables
$env:GMD_AZDO_ORGANIZATION = "your-org"
$env:GMD_AZDO_PROJECT = "your-project"

# Run GetAzDoUserStory tests
.\test\GetAzDoUserStoryTest.ps1

# Run GetAzDoHierarchyForEpic tests
.\test\GetAzDoHierarchyForEpicTest.ps1

# Run GetAzDoHierarchyForFeature tests
.\test\GetAzDoHierarchyForFeatureTest.ps1

# Run GetAzDoHierarchyForStory tests
.\test\GetAzDoHierarchyForStoryTest.ps1
```

**Note:** Integration tests create temporary test data (Epic, Features, Stories) and automatically clean up by deleting the test Epic at the end.

### Test Hierarchy Helper

The `CreateTestHierarchy.ps1` helper simplifies creating temporary test hierarchies for export/import testing:

#### Purpose
Factory function for creating test work item hierarchies in Azure DevOps, used by integration tests to verify functionality against real hierarchies.

#### Features
- **Deterministic naming**: Test Epic created with "TEST-\<timestamp\>-\<description\>" prefix
- **Configurable hierarchy**: Define Features → Stories → Tasks structure in code
- **Automatic cleanup**: Built-in cleanup on creation failure with try/finally pattern
- **Tagging**: All created items tagged with "testWi" for easy orphan detection
- **Structured return**: Object with created work item IDs for verification

#### Usage Example

```powershell
# Import the helper
$spec = @{
    features = @(
        @{
            title       = "Auth Feature"
            effort      = 8
            description = "Authentication feature"
            stories     = @(
                @{
                    title        = "Login"
                    storyPoints  = 3
                    description  = "User login"
                    tasks        = @(
                        @{ title = "Setup OAuth"; effort = 2 }
                    )
                }
            )
            tasks       = @()
        }
    )
    bugs = @(
        @{ title = "Login timeout bug"; description = "Session expires too fast" }
    )
}

# Create test hierarchy
$result = ./test/CreateTestHierarchy.ps1 `
    -Organization "falco-it" `
    -Project "GMD" `
    -Description "ExportImportTest" `
    -HierarchySpec $spec

# Use created items for testing
Write-Host "Created Epic: $($result.Epic.Id)"
Write-Host "Features: $($result.Features.Count)"
Write-Host "Stories: $($result.Stories.Count)"
Write-Host "All work items: $($result.AllWorkItemIds -join ',')"

# Verify creation succeeded
if ($result.Success) {
    try {
        # Run your test operations with $result.Epic.Id, etc.
        
        # Validate export contains all items
        # Verify export format
    }
    finally {
        # Cleanup: Delete the test Epic and all children
        ./src/RemoveAzDoEpic.ps1 `
            -Organization "falco-it" `
            -Project "GMD" `
            -EpicId $result.Epic.Id `
            -Recursive `
            -Force
    }
} else {
    Write-Error "Failed to create test hierarchy: $($result.Errors -join '; ')"
}
```

#### Return Object Structure

```powershell
@{
    Success         = $true|$false
    Epic            = @{ Id = 123; Title = "TEST-..."; Url = "..." }
    Features        = @{ "Feature Title" = @{ Id = 456; Title = "..."; Url = "..." }; ... }
    Stories         = @{ "Story Title" = @{ Id = 789; Title = "..."; ParentId = 456; Url = "..." }; ... }
    Tasks           = @{ "Task Title" = @{ Id = 101; Title = "..."; ParentId = 789; Url = "..." }; ... }
    Bugs            = @{ "Bug Title" = @{ Id = 102; Title = "..."; Url = "..." }; ... }
    AllWorkItemIds  = @(123, 456, 789, 101, 102)  # For easy cleanup
    Errors          = @()  # Any errors encountered during creation
}
```

#### Integration Tests Using CreateTestHierarchy

View the story AB#2226 test file for comprehensive examples:

```powershell
.\test\storyAcTests\2226CreateTestHierarchyManagementSystem\2226CreateTestHierarchyTest.ps1
```

These tests demonstrate:
- Creating simple hierarchies and verifying queryability
- Complex hierarchies with multiple levels (1 Epic, 2 Features, 5 Stories, 3 Tasks, 1 Bug)
- Reliable cleanup removing all created items

### Test Markdown Generator

The `CreateTestMarkdown.ps1` helper generates a complete synthetic markdown hierarchy file
without requiring any live Azure DevOps connection. Use it to produce ready-to-consume
markdown input for testing parsers, importers, and other markdown-driven tooling.

#### Purpose

Generates a fully-populated markdown hierarchy (Epic → Features → Stories/Bugs → Tasks)
using made-up but realistic values. All writable fields defined by the markdown template
(`GenerateAzDoMarkdownHierarchyTemplate.ps1`) are populated. Values differ between items
using a timestamp seed so each run produces unique item names.

#### Features

- **No Azure DevOps connection required**: Generates markdown locally
- **All writable fields populated**: tags, Effort, SP, Priority, OriginalEstimate, Description, Acceptance Criteria, AC Scenarios, Extra Information
- **Configurable counts**: Control the number of Features, Stories, Bugs, and Tasks per level
- **Optional no-task items**: `CreateSomeStoriesAndBugsWithoutTasks` creates at least one Story and one Bug per Feature with no Tasks (tests edge-case handling)
- **testWi tag**: All generated items include the `testWi` tag for identification
- **Parser-validated format**: Output passes `ConvertMarkdownToHierarchyJson.ps1` parsing without errors

#### Usage

```powershell
# Generate with defaults (2 Features, 2 Stories/Feature, 2 Bugs/Feature, 2 Tasks each)
.\test\CreateTestMarkdown.ps1 `
    -EpicTitle "My Test Epic" `
    -MdOutputFile ".\tmp\test-hierarchy.md"

# Generate minimal hierarchy (1 Feature, 1 Story, 1 Bug, 1 Task each)
.\test\CreateTestMarkdown.ps1 `
    -EpicTitle "Minimal Test" `
    -MdOutputFile ".\tmp\minimal.md" `
    -FeatureCount 1 -StoryPerFeatureCount 1 -BugPerFeatureCount 1 `
    -TaskPerStory 1 -TaskPerBug 1

# Include items without tasks for edge-case testing
.\test\CreateTestMarkdown.ps1 `
    -EpicTitle "Edge Case Test" `
    -MdOutputFile ".\tmp\edge.md" `
    -CreateSomeStoriesAndBugsWithoutTasks
```

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `-EpicTitle` | string | Yes | — | Title for the single Epic |
| `-MdOutputFile` | string | Yes | — | Output file path (directories created automatically) |
| `-FeatureCount` | int | No | 2 | Number of Features under the Epic |
| `-StoryPerFeatureCount` | int | No | 2 | Number of Stories under each Feature |
| `-BugPerFeatureCount` | int | No | 2 | Number of Bugs under each Feature |
| `-TaskPerStory` | int | No | 2 | Number of Tasks under each Story |
| `-TaskPerBug` | int | No | 2 | Number of Tasks under each Bug |
| `-CreateSomeStoriesAndBugsWithoutTasks` | switch | No | off | Last Story and last Bug in each Feature are created without Tasks |

## Error Handling

All scripts follow strict error handling practices:
- **Fail-fast**: Errors immediately abort execution (no silent failures)
- **Validation first**: Input validation before API calls
- **Clear messages**: Descriptive error messages with context
- **No fallbacks**: No silent error recovery or default behaviors

## Quality Standards

- **PascalCase naming**: All scripts follow `UpsertAzDoFeature` pattern (CRUD operations as unified UPSERT where applicable)
- **Strict mode v3**: Prevents uninitialized variable usage
- **Fail fast**: `$ErrorActionPreference = 'Stop'`
- **No null-forgiving**: No `!` operator without explanation
- **XML documentation**: Complete parameter documentation
- **Logging**: All operations logged via `ssLogIt.ps1`

## File Structure

```
.
├── appSettings.json                          (Unified field and state config per org/project/type)
├── src/
│   ├── AzDoAutomatorConstants.ps1           (Core constants)
│   ├── AzDoPatTokenHelper.ps1               (PAT token management)
│   ├── AzDoApiWrapper.ps1                   (REST API wrapper)
│   ├── AzDoWorkItemHelper.ps1               (Helper functions)
│   ├── LoadFieldConfiguration.ps1           (Load field definitions from appSettings.json)
│   ├── LoadStateConfiguration.ps1           (Load state definitions from appSettings.json)
│   ├── ValidateUpsertFields.ps1             (Pre-flight validation for Fields and State params)
│   ├── ResolveAzDoIdentity.ps1              (Email → AzDo identity resolution)
│   ├── UpsertAzDoEpic.ps1                   (Create/update Epics)
│   ├── UpsertAzDoFeature.ps1                (Create/update Features)
│   ├── UpsertAzDoStory.ps1                  (Create/update Stories)
│   ├── UpsertAzDoBug.ps1                    (Create/update Bugs)
│   ├── UpsertAzDoTask.ps1                   (Create/update Tasks)
│   ├── GetAzDoWorkItem.ps1                  (Retrieve work item with enriched named properties)
│   ├── GetAzDoUserStory.ps1                 (Retrieve User Story with subset or full data)
│   ├── GetAzDoBug.ps1                       (Retrieve Bug with enriched named properties)
│   ├── NewAzDoComment.ps1                   (Add comment to work item)
│   ├── GetAzDoComments.ps1                  (Retrieve all comments from work item)
│   ├── UpdateAzDoComment.ps1                (Update comment content)
│   ├── RemoveAzDoComment.ps1                (Remove comment from work item)
│   ├── NewAzDoCommentReaction.ps1           (Add reaction to comment)
│   ├── GetAzDoCommentReactions.ps1          (Retrieve comment reactions)
│   ├── GetAzDoHierarchyForEpic.ps1          (Retrieve Epic hierarchy with Features and Stories)
│   ├── GetAzDoHierarchyForFeature.ps1       (Retrieve Feature hierarchy with Stories and Tasks)
│   ├── GetAzDoHierarchyForStory.ps1         (Retrieve Story hierarchy with Tasks)
│   ├── SetAzDoWorkItemDescription.ps1       (Set description)
│   ├── SetAzDoAcceptanceCriteria.ps1        (Set acceptance criteria)
│   ├── SetAzDoStoryPoints.ps1               (Set story points)
│   ├── SetAzDoEffort.ps1                    (Set effort for Epic/Feature)
│   ├── MoveAzDoWorkItemField.ps1            (Move/copy field value across hierarchy or project-wide)
│   ├── SyncAppSettingsFields.ps1            (Sync appSettings.json field definitions from live API)
│   ├── SetAzDoWorkItemTags.ps1              (Manage tags)
│   ├── UpdateAzDoWorkItemTags.ps1           (Update/add/remove tags - modern replacement)
│   ├── NewAzDoHierarchyFromMarkdown.ps1     (Create from markdown)
│   ├── RemoveAzDoEpic.ps1                   (Delete Epic, optionally with children)
│   ├── RemoveAzDoFeature.ps1                (Delete Feature, optionally with children)
│   ├── RemoveAzDoStory.ps1                  (Delete Story, optionally with child Tasks)
│   ├── RemoveAzDoBug.ps1                    (Delete Bug, optionally with child Tasks)
│   ├── RunSystemTest.ps1                    (System test suite)
│   └── VerifyAzDoPat.ps1                    (Verify PAT read access)
├── test/
│   ├── BasicIntegrationTest.ps1             (Integration tests)
│   ├── GetAzDoUserStoryTest.ps1             (GetAzDoUserStory tests)
│   ├── Scenario1581Test.ps1                 (UpsertAzDoStory scenario tests)
│   ├── GetAzDoHierarchyForEpicTest.ps1      (GetAzDoHierarchyForEpic tests)
│   ├── GetAzDoHierarchyForFeatureTest.ps1   (GetAzDoHierarchyForFeature tests)
│   ├── GetAzDoHierarchyForStoryTest.ps1     (GetAzDoHierarchyForStory tests)
│   ├── NewAzDoCommentTest.ps1               (NewAzDoComment tests)
│   ├── GetAzDoCommentReactionsTest.ps1      (GetAzDoCommentReactions tests)
│   ├── RemoveAzDoCommentTest.ps1            (RemoveAzDoComment tests)
│   ├── NewAzDoCommentReactionTest.ps1       (NewAzDoCommentReaction tests)
│   ├── storyAcTests/
│   │   ├── 1584GetAzDoCommentsTest.ps1      (GetAzDoComments AC scenario tests)
│   │   ├── 1585UpdateAzDoCommentTest.ps1    (UpdateAzDoComment AC scenario tests)
│   │   ├── 2616ConfigDrivenApiReadWrite/
│   │   │   └── 2616ConfigDrivenApiReadWriteTest.ps1  (ValidateUpsertFields AC scenario tests)
│   │   ├── 2617McpConfigTemplateAllFields/
│   │   │   └── 2617McpConfigTemplateAllFieldsTest.ps1 (Template generator / MCP config tests)
│   │   └── 2618AssignedToByEmail/
│   │       └── 2618AssignedToByEmailTest.ps1  (ResolveAzDoIdentity + AssignedTo AC tests)
│   └── RunAllTests.ps1                      (Master test runner)
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

## Iteration Management

### Overview

Iteration management scripts help automate the creation and management of project iterations (sprints).

#### `GetAzDoIterations.ps1`

Retrieve all iterations from an Azure DevOps project. Iterations are returned in chronological order by start date.

```powershell
# Get all iterations from default organization/project
$iterations = .\GetAzDoIterations.ps1
$iterations | Format-Table -Property name, attributes

# Get iterations from specific organization/project
$iterations = .\GetAzDoIterations.ps1 `
    -Organization "myorg" `
    -Project "myproject"
```

**Parameters:**
- `Organization` (optional): Azure DevOps organization. Uses GMD_AZDO_ORGANIZATION if not provided.
- `Project` (optional): Azure DevOps project. Uses GMD_AZDO_PROJECT if not provided.
- `PatToken` (optional): PAT token for authentication. Uses GMD_AZDO_MACHINE_WORKITEMSRW environment variable if not provided.

**Returns:**
Array of iteration objects containing:
- `id`: Unique iteration identifier
- `name`: Iteration name
- `path`: Iteration path in hierarchy
- `startDate`: Start date
- `finishDate`: End date
- `state`: Current state (e.g., "Active", "Completed", "Future")

#### `CreateAzDoFutureIterations.ps1`

Automatically create iterations starting from a specified date with configurable length and naming template. Supports custom iteration durations (weeks or months) and flexible naming patterns with date formats and optional counter placeholders. Iterations are created under a specified parent path in the iteration hierarchy.

```powershell
# Create monthly iterations starting 2026-01-04 under parent "2026"
.\CreateAzDoFutureIterations.ps1 -ParentPath "2026" -StartAt "2026-01-04"

# Preview with DryRun before creating
.\CreateAzDoFutureIterations.ps1 -ParentPath "2026" -StartAt "2026-01-04" -DryRun

# Create monthly iterations with StopAt date (prevents creating 2027 iterations)
.\CreateAzDoFutureIterations.ps1 `
    -ParentPath "2026" `
    -StartAt "2026-01-04" `
    -StopAt "2026-12-31" `
    -MonthsAhead 12

# Create 2-week iterations with custom counter naming under parent path
.\CreateAzDoFutureIterations.ps1 `
    -ParentPath "2026" `
    -StartAt "2026-01-04" `
    -IterationLength "2w" `
    -IterationNameTemplate "W{counterPadded}" `
    -CounterStart 1

# Create monthly iterations with custom template
.\CreateAzDoFutureIterations.ps1 `
    -ParentPath "2026" `
    -StartAt "2026-01-04" `
    -IterationNameTemplate "Sprint {counterNonPadded}" `
    -CounterStart 1

# Create quarterly iterations
.\CreateAzDoFutureIterations.ps1 `
    -ParentPath "2026" `
    -StartAt "2026-01-04" `
    -IterationLength "3m" `
    -IterationNameTemplate "Q{counterNonPadded} {yyyy}" `
    -CounterStart 1 `
    -MonthsAhead 12

# Create iterations for specific organization/project
.\CreateAzDoFutureIterations.ps1 `
    -ParentPath "2026" `
    -StartAt "2026-01-04" `
    -Organization "myorg" `
    -Project "myproject" `
    -MonthsAhead 12

# View planned iterations without creating
$result = .\CreateAzDoFutureIterations.ps1 -ParentPath "2026" -StartAt "2026-01-04" -DryRun
$result.plannedIterations | Format-Table
```

**Parameters:**
- `ParentPath` (required): Parent path for creating iterations (e.g., "2026", "GMD/2026/Q1"). Defines the iteration hierarchy level where iterations will be created.
- `StartAt` (required): Date to start creating iterations from (format: yyyy-MM-dd, e.g., 2026-01-04).
- `StopAt` (optional): Date to stop creating iterations. Prevents creating iterations that would start on or after this date (format: yyyy-MM-dd, e.g., 2026-12-31). If not specified, iterations are created based on MonthsAhead parameter.
- `IterationLength` (optional, default: "1m"): Iteration duration with unit suffix:
  - "1m", "2m", "3m", etc. for months
  - "1w", "2w", "4w", etc. for weeks
- `IterationNameTemplate` (optional, default: "{yyyy-MM}"): Template for iteration names with support for:
  - Date format specifiers: {yyyy}, {MM}, {dd}, {yyyy-MM}, {yyyy-MM-dd}, etc. (standard .NET date format)
  - {counterNonPadded}: Counter without padding (1, 2, 10)
  - {counterPadded}: Counter with zero-padding (01, 02, 10)
- `CounterStart` (optional): Starting value for counter. Required if template contains counter placeholders, not allowed otherwise.
- `MonthsAhead` (optional, default: 6): Number of iteration periods to create (must be 1-24).
- `Organization` (optional): Azure DevOps organization. Uses GMD_AZDO_ORGANIZATION if not provided.
- `Project` (optional): Azure DevOps project. Uses GMD_AZDO_PROJECT if not provided.
- `PatToken` (optional): PAT token for authentication. Uses GMD_AZDO_MACHINE_WORKITEMSRW environment variable if not provided.
- `DryRun` (optional, switch): Preview planned iterations without creating them.

**Returns:**
Object with summary containing:
- `plannedIterations`: Array of iterations that were created or would be created
- `totalCreated`: Number of iterations created (0 in DryRun)
- `message`: Summary message

**Validation Rules:**
- `ParentPath` is required and cannot be empty
- `StartAt` is required and must be in yyyy-MM-dd format
- `StopAt` (if provided) must be in yyyy-MM-dd format and must be after `StartAt`
- `IterationLength` must match format like "1m", "2w", "3m"
- If `IterationNameTemplate` contains counter placeholders, `CounterStart` is mandatory
- `CounterStart` cannot be specified if template doesn't contain counter placeholders
- If `IterationLength` is not default (1m), `IterationNameTemplate` is required (to avoid ambiguous naming)
- `MonthsAhead` must be between 1 and 24

**Behavior:**
- Creates new iterations starting from the specified `StartAt` date
- Stops creating iterations when start date reaches or exceeds `StopAt` date (if specified)
- Only creates iterations if they don't already exist by name and date range
- Uses fail-fast approach: validates entire structure before creating any items
- Supports flexible iteration naming via template substitution
- Counter values increment for each iteration when template includes counter placeholders
- Iterations are created under the specified parent path in the iteration hierarchy

**Example Workflow:**

```powershell
# Step 1: Verify existing iterations
$iterations = .\GetAzDoIterations.ps1
Write-Host "Found $($iterations.Count) existing iterations"

# Step 2: Preview what will be created with StopAt limit
$preview = .\CreateAzDoFutureIterations.ps1 -ParentPath "2026" -StartAt "2026-01-04" -StopAt "2026-12-31" -DryRun
$preview.plannedIterations | Format-Table -Property name, startDate, endDate

# Step 3: Create iterations
$result = .\CreateAzDoFutureIterations.ps1 -ParentPath "2026" -StartAt "2026-01-04" -StopAt "2026-12-31"
Write-Host $result.message

# Step 4: Verify results
$allIterations = .\GetAzDoIterations.ps1
Write-Host "Now have $($allIterations.Count) total iterations"
```

## Markdown Hierarchy Workflow


This project provides a complete workflow for planning and executing work item hierarchies through markdown files:

```
┌──────────────────────────────────────────────────────────────┐
│ 1. GENERATE MARKDOWN TEMPLATE                                │
│    GenerateAzDoMarkdownHierarchyTemplate.ps1                │
│    → Creates template with embedded rules and examples       │
│    → Helps AI agents create valid markdown                   │
└────────────────┬─────────────────────────────────────────────┘
                 │ (edit and customize markdown)
┌────────────────▼─────────────────────────────────────────────┐
│ 2. VALIDATE MARKDOWN STRUCTURE                               │
│    ConvertMarkdownToHierarchyJson.ps1                        │
│    → Converts markdown to JSON for validation                │
│    → Preview structure before creating work items            │
└────────────────┬─────────────────────────────────────────────┘
                 │ (verify structure is correct)
┌────────────────▼─────────────────────────────────────────────┐
│ 3. CREATE WORK ITEMS IN AZURE DEVOPS                         │
│    NewAzDoHierarchyFromMarkdown.ps1 (create-workitems...)   │
│    → Creates/updates work items from markdown                │
│    → Creates entire hierarchy atomically                     │
│    → Supports DryRun and UpdateExisting modes                │
└──────────────────────────────────────────────────────────────┘
```

### Workflow Tools (MCP Integration)

All tools are available as MCP (Model Context Protocol) tools for AI agents and automation:

| Step | MCP Tool ID | Script | Purpose |
|------|-------------|--------|---------|
| 1 | `generate-markdown-hierarchy-template` | `GenerateAzDoMarkdownHierarchyTemplate.ps1` | Generate template with rules/examples |
| 2 | `convert-markdown-to-hierarchy-json` | `ConvertMarkdownToHierarchyJson.ps1` | Validate/preview hierarchy structure |
| 3 | `create-workitems-from-markdown` | `NewAzDoHierarchyFromMarkdown.ps1` | Create work items in Azure DevOps |

### Quick Start Workflow

Environment setup (required):
```powershell
# Set environment variables for MCP tools
$env:GMD_AZDO_ORGANIZATION = "myorg"
$env:GMD_AZDO_PROJECT = "myproject"
# PAT token is typically pre-configured via environment
```

Workflow:
```powershell
# Step 1: Generate a template for your project
$template = .\src\GenerateAzDoMarkdownHierarchyTemplate.ps1 -IncludeExample
$template | Out-File "my-plan.md"

# Step 2: Validate markdown structure (best before creating items)
$content = Get-Content "my-plan.md" -Raw
$json = .\src\ConvertMarkdownToHierarchyJson.ps1 -MarkdownContent $content
$json | ConvertTo-Json

# Step 3: Preview work items (DryRun mode - no changes to Azure DevOps)
$content = Get-Content "my-plan.md" -Raw
.\src\NewAzDoHierarchyFromMarkdown.ps1 `
    -MarkdownContent $content `
    -DryRun

# Step 4: Create work items (remove -DryRun to actually create)
$content = Get-Content "my-plan.md" -Raw
.\src\NewAzDoHierarchyFromMarkdown.ps1 `
    -MarkdownContent $content
```

## Markdown Hierarchy Template Generation

The `GenerateAzDoMarkdownHierarchyTemplate.ps1` script generates a markdown template with embedded rules from [docs/createMarkdownPlan.md](./docs/createMarkdownPlan.md) and [docs/architecturalRules.md](./docs/architecturalRules.md), and appends a **SUPPORTED FIELDS REFERENCE** section built from `appSettings.json`.

### Features

- **Embedded Rules**: All markdown rules included as inline comments
- **Example Structure**: Shows correct formatting for Epics, Features, and Stories
- **Rule Enforcement**: Guides creation of valid hierarchies (tags, titles, headers)
- **SUPPORTED FIELDS REFERENCE**: Auto-generated section listing all writable fields per work item type with label, referenceName, and type hint — sourced from `appSettings.json` at generation time
- **Best Practices**: Demonstrates proper:
  - Tag naming (camelCase)
  - Story Point estimation
  - Acceptance Criteria definition
  - Gherkin BDD Scenarios
  - Field formatting

### Usage

Generate template to console:
```powershell
.\src\GenerateAzDoMarkdownHierarchyTemplate.ps1
```

Generate template to file (redirect stdout):
```powershell
.\src\GenerateAzDoMarkdownHierarchyTemplate.ps1 > "my-hierarchy.md"
```

Generate template with real-world example:
```powershell
.\src\GenerateAzDoMarkdownHierarchyTemplate.ps1 -IncludeExample > "example.md"
```

### Template Contents

The generated template includes:

1. **Work Item Type Guide**
   - Epic, Feature, Story, Task, Bug requirements
   - Type prefixes and header levels

2. **Formatting Rules**
   - Tag conventions (camelCase)
   - Title rules (no emoticons)
   - Header level requirements
   - Line ending rules

3. **Field Reference**
   - `**tags**`: Comma-separated (camelCase)
   - `**Effort**`: For Epics/Features
   - `**Story Points**`: Story points for Stories/Bugs
   - `**Priority**`: For Tasks/Bugs
   - `**Description****: With user story format

4. **Acceptance Criteria & Scenarios**
   - Checkbox format for criteria
   - Gherkin Given/When/Then structure

5. **SUPPORTED FIELDS REFERENCE** (auto-generated from `appSettings.json`)
   - All writable fields per work item type
   - Each entry shows: label, `referenceName`, and type hint

6. **Complete Example** (with `-IncludeExample`)
   - Real-world "Customer Portal Redesign"
   - Multiple Features and Stories
   - Tasks and Bugs with proper nesting

## Creating Work Item Hierarchies from Markdown

The `NewAzDoHierarchyFromMarkdown.ps1` script allows you to define entire work item hierarchies using a simple markdown format with strict validation:

### Validation Rules

The converter validates your markdown during parsing:

1. **Title Prefixes**: Epic, Feature, and Story titles must start with their type prefix
   - Non-compliant: `# Customer Portal` (missing "Epic: " prefix)
   - Compliant: `# Epic: Customer Portal`

2. **Header Levels in Descriptions**: Headers in descriptions must respect hierarchy levels
   - Level 1-2 headers (`#`, `##`) in Epic/Feature descriptions → Error
   - Level 1-3 headers (`#`, `##`, `###`) in Story descriptions → Error
   - This prevents confusion with work item hierarchy markers

3. **Structure Validation**: Stories must have parent Features, Features must be under Epics or at top level

Example of validation error:
```
Epic: My Epic
Description with a level 2 header:
## Subtopic (ERROR: level 2 headers not allowed in Epic descriptions)
```

Should be:
```
Epic: My Epic
Description with a level 3 header:
### Subtopic (OK: level 3+ headers allowed in Epic descriptions)
```

### Markdown Format Guide

The markdown format supports structured hierarchy with required naming conventions and header level validation:

#### Naming Conventions

All work item titles must include a type prefix to avoid confusion with header levels:

- **Epic** titles must start with `Epic: ` (e.g., `# Epic: Customer Portal Redesign`)
- **Feature** titles must start with `Feature: ` (e.g., `## Feature: User Authentication`)
- **Story** titles must start with `Story: ` (e.g., `### Story: OAuth 2.0 Implementation`)
- **Task** titles must start with `Task: ` (e.g., `#### Task: Setup database schema`) - Level 4 headers under Stories
- **Bug** titles must start with `Bug: ` (e.g., `#### Bug: Login crashes on special characters`) - Level 4 headers under Stories

#### Header Level Requirements

To prevent headers in descriptions from being confused with hierarchy markers:

- **Epic and Feature descriptions**: Must use headers at level 3 (###) or higher
  - Avoid using `#` or `##` in descriptions
  - Example: `### Key Objectives` ✅ (allowed), `## Implementation` ❌ (not allowed)

- **Story descriptions**: Must use headers at level 4 (####) or higher
  - Avoid using `#`, `##`, or `###` in descriptions
  - Example: `#### Scenarios` ✅ (allowed), `### Implementation` ❌ (not allowed)

- **Task and Bug descriptions**: Must use headers at level 5 (#####) or higher
  - Avoid using `#`, `##`, `###`, or `####` in descriptions
  - Example: `##### Details` ✅ (allowed), `#### Context` ❌ (not allowed)

#### Basic Structure

```markdown
# Epic: Epic Title

{tags}: tag1, tag2  
{Effort}: 21  
{Description}  
Multi-line description with headers at level 3 or higher
### Header in Epic Description
More content here

## Feature: Feature Title

{tags}: tag1, tag2  
{Effort}: 13  
{Description}  
Feature description with headers at level 3 or higher
### Implementation Details
Additional context

### Story: Story Title

{tags}: tag1, tag2  
{Story Points}: 5  
{Description}  
Story description with headers at level 4 or higher
{Acceptance Criteria}
- [ ] Criterion 1

{AC Scenarios}
1. **Scenario**: First scenario  
  Given...  
  When...  
  Then...

{Extra Information}
- Additional notes and references
```

#### Formatting Guidelines

**Newlines in Descriptions**: Use 2 spaces (`  `) at the end of lines to enforce newlines:

```markdown
## Feature: Example

{tags}: documentation, guide  
{Description}  
This is the first line  
This is the second line (2 spaces above enforces newline)  
This is the third line  
```

**Supported Properties**

**Acceptance Criteria (AC)** - Use checkbox-style lists:
```markdown
{Acceptance Criteria}
- [ ] First criterion
- [ ] Second criterion
```

**Acceptance Criteria Scenarios (ACS)** - Gherkin-style BDD scenarios:
```markdown
{AC Scenarios}
1. **Scenario**: User logs in  
  Given user is on login page  
  When user enters valid credentials  
  Then user is logged in  
  And dashboard is displayed

2. **Scenario**: Login fails with invalid password  
  Given user is on login page  
  When user enters invalid password  
  Then error message is shown
```

**Story Points (SP)** - Stories and Bugs only (decimals supported, e.g. 0.5, 1.5):
```markdown
{Story Points}: 0.5
```

**Effort** - Epics and Features only (decimals supported, e.g. 2.5):
```markdown
{Effort}: 2.5
```

**Priority** - Features, Stories, Bugs, and Tasks (1=highest, 4=lowest):
```markdown
{Priority}: 2
```

**Original Estimate** - Features, Stories, and Tasks (hours, non-negative number):
```markdown
{Original Estimate}: 8
```

**FixedIn** - Features and Stories (text, version or build where completed):
```markdown
**FixedIn**: 2026.4.1
```

**DeployedToDev / DeployedToStaging / DeployedToProduction** - Features and Stories (boolean):
```markdown
**DeployedToDev**: true
**DeployedToStaging**: false
**DeployedToProduction**: false
```

**Extra Information (EI)**:
```markdown
#### Extra Information
- Reference documentation: https://docs.example.com
- Consider security implications  
- Apply rate limiting on API endpoints
```

**Tags** - Automatically added:
- All work items created include the `generated` tag for tracking
- Additional tags can be added after creation using `SetAzDoWorkItemTags.ps1`

#### Complete Example

See [example-hierarchy.md](./example-hierarchy.md) for a complete, production-ready example demonstrating:
- Epic titles with "Epic: " prefix including emoticons
- Feature titles with "Feature: " prefix
- Story titles with "Story: " prefix
- Multi-level features and stories with proper hierarchy
- Headers in descriptions using correct nesting levels (### in features, #### in stories)
- Acceptance criteria with multiple lines and markdown formatting
- Numbered Gherkin scenarios with proper Given/When/Then structure
- Story points estimation
- Real-world use cases (Customer Portal Redesign with authentication, ticketing, and knowledge base features)
- Trailing 2 space characters for enforcing newlines in markdown
- **Tasks under Stories** - Examples of leaf-level work items

### Special Handling

#### HTML Tags and Angle-Bracket Identifiers

Azure DevOps stores description fields as HTML. Its sanitizer silently strips any tag it does not
recognise — so `<FooBar>` written in a description would disappear. To prevent this,
`NewAzDoHierarchyFromMarkdown.ps1` encodes every `<` that is **not** the start of a standard HTML
element (`<br>`, `<p>`, `<strong>`, etc.) to `&lt;` before writing to Azure DevOps. Recognised
HTML elements are left unchanged so they continue to render correctly in the Azure DevOps UI.

When exporting a hierarchy from Azure DevOps to markdown (`ConvertHierarchyToMarkdown.ps1`), all
`<` characters in field values are encoded as `&lt;`. This ensures that identifiers such as
`<StmtsDir>` or `<AccountName>` that appear as literal text in descriptions are preserved visibly
in markdown renderers instead of being silently hidden as unknown HTML tags.

> Note: Only `<` is encoded on export; `>` at the start of a line is a markdown blockquote
> character and is left unchanged.

### Creating Tasks Within Stories

Tasks are leaf-level work items designed to track individual work items within a Story. Tasks are created automatically with their parent Story as part of the hierarchy markdown processing using `NewAzDoHierarchyFromMarkdown.ps1`.

**Task Field Reference:**

Tasks support the following fields in markdown (no Effort or Acceptance Criteria):
- **Description** - Task description (required)
- **Priority** - Priority level 1-4 (1=Critical, 2=High, 3=Medium, 4=Low)
- **Original Estimate** - Estimated hours to complete (hours)
- **Remaining** - Remaining hours of work (hours)
- **Completed** - Hours of work completed (hours)
- **Tags** - Comma-separated tags (optional)

**Markdown Format for Tasks:**

Tasks are defined as level 4 headers (####) under Stories (level 3 headers ###):

```markdown
### Story: User Profile Page & Preferences

{tags}: user-profile, preferences
{Story Points}: 5
{Description}
Story description...

#### Task: Setup User Profile Database Schema

{Priority}: 2

{Description}: Create database tables for storing user profile information.

{Original Estimate}: 8

{Remaining Work}: 8

{Completed Work}: 0

#### Task: Implement Profile API Endpoints

{Priority}: 1

{Description}: Develop API endpoints for profile CRUD operations.

{Original Estimate}: 13

{Remaining Work}: 13

{Completed Work}: 0
```

**Workflow:**

1. **Define hierarchy with Tasks in markdown** - Include Task sections under Stories with 4-level headers (####)
2. **Run hierarchy creation** - `NewAzDoHierarchyFromMarkdown.ps1` automatically creates Tasks under their Stories
3. **Manage Tasks** - Use `UpsertAzDoTask.ps1` for individual Task creation/updates; `RemoveAzDoTask.ps1` for deletion

**Example: Complete Hierarchy with Tasks**

```powershell
# Create hierarchy from markdown (automatically handles Tasks)
$result = .\NewAzDoHierarchyFromMarkdown.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -MarkdownFilePath ".\hierarchy.md"

# Inspect created items including Tasks
$result.CreatedItems | Where-Object { $_.fields.'System.WorkItemType' -eq 'Task' } | ForEach-Object {
    Write-Host "Task: $($_.fields.'System.Title') (ID: $($_.id))"
}
```

**Programmatic Task Management:**

If you need to create or update Tasks outside of markdown hierarchy:

```powershell
# Create a Task under a Story
$task = .\UpsertAzDoTask.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Title "Implement authentication" `
    -ParentStoryId 789 `
    -Priority 1 `
    -OriginalEstimate 13 `
    -RemainingWork 13

# Update Task progress
$updated = .\UpsertAzDoTask.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Id $task.id `
    -RemainingWork 8 `
    -State "In Progress"

# Delete a Task
.\RemoveAzDoTask.ps1 -Organization "myorg" -Project "myproj" -TaskId $task.id -Force
```

### Creating Bugs Within Stories

Bugs are work items designed to track reported issues and defects within a Story. Bugs support priority levels, reproduction steps, system information, and integration build tracking. Bugs can be created automatically with their parent Story as part of the hierarchy markdown processing using `NewAzDoHierarchyFromMarkdown.ps1`.

**Bug Field Reference:**

Bugs support the following fields in markdown:
- **Description** - Bug description (required)
- **Priority** - Priority level 1-4 (1=Critical, 2=High, 3=Medium, 4=Low) (required)
- **ReproSteps** - Steps to reproduce the bug (optional)
- **SystemInfo** - System and environment information (optional)
- **StoryPoints** - Story points for estimation (optional)
- **FoundInBuild** - Build version where bug was found (optional)
- **IntegratedInBuild** - Build version where fix was integrated (optional)
- **Tags** - Comma-separated tags (optional)

**Markdown Format for Bugs:**

Bugs are defined as level 4 headers (####) under Stories (level 3 headers ###) using "Bug: " prefix:

```markdown
### Story: Authentication System

{tags}: authentication, security
{Story Points}: 8
{Description}
Story description...

#### Bug: Login fails with special characters in password

{Priority}: 1

{Description}: When entering special characters in the password field, the login form crashes.

**ReproSteps**: 1. Open login page
2. Enter special characters in password field (@#$%^&*)
3. Click submit

**SystemInfo**: Windows 11, Chrome 120, Firefox 121

**FoundInBuild**: Build 2026.3.0

**IntegratedInBuild**: Build 2026.3.1

#### Bug: API returns 500 error intermittently

{Priority}: 2

{Description}: API endpoint returns 500 error intermittently when under load.

**ReproSteps**: 1. Send 100 concurrent requests to API endpoint
2. Observe response codes

{Story Points}: 3
```

**Workflow:**

1. **Define hierarchy with Bugs in markdown** - Include Bug sections under Stories with 4-level headers (####) and "Bug: " prefix
2. **Run hierarchy creation** - `NewAzDoHierarchyFromMarkdown.ps1` automatically creates Bugs under their Stories
3. **Manage Bugs** - Use `UpsertAzDoBug.ps1` for individual Bug creation/updates; `RemoveAzDoBug.ps1` for deletion; `GetAzDoBug.ps1` for retrieval

**Example: Complete Hierarchy with Bugs**

```powershell
# Create hierarchy from markdown (automatically handles Bugs)
$result = .\NewAzDoHierarchyFromMarkdown.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -MarkdownFilePath ".\hierarchy.md"

# Inspect created items including Bugs
$result.CreatedItems | Where-Object { $_.fields.'System.WorkItemType' -eq 'Bug' } | ForEach-Object {
    Write-Host "Bug: $($_.fields.'System.Title') (ID: $($_.id), Priority: $($_.fields.'Microsoft.VSTS.Common.Priority'))"
}
```

**Programmatic Bug Management:**

If you need to create or update Bugs outside of markdown hierarchy:

```powershell
# Create a Bug under a Story
$bug = .\UpsertAzDoBug.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Title "User interface freeze on profile load" `
    -ParentStoryId 789 `
    -Priority 1 `
    -ReproSteps "1. Open profile page 2. Wait 5 seconds" `
    -SystemInfo "MacOS, Safari 17" `
    -StoryPoints 5

# Update Bug priority and add reproduction steps
$updated = .\UpsertAzDoBug.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -Id $bug.id `
    -Priority 2 `
    -IntegratedInBuild "Build 2026.3.2"

# Retrieve Bug details
$bugDetails = .\GetAzDoBug.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -BugId $bug.id

# Delete a Bug (and its child Tasks)
.\RemoveAzDoBug.ps1 -Organization "myorg" -Project "myproj" -BugId $bug.id -Recursive -Force
```

### Usage

**Dry Run (Preview)**:
```powershell
# Preview what will be created without making changes
$result = .\NewAzDoHierarchyFromMarkdown.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -MarkdownFilePath ".\hierarchy.md" `
    -DryRun

Write-Host "Would create: $($result.PlannedEpics) epic(s), $($result.PlannedFeatures) feature(s), $($result.PlannedStories) story(ies)"
```

**Create Hierarchy Under Existing Epic**:
```powershell
# Create features and stories under an existing epic
$result = .\NewAzDoHierarchyFromMarkdown.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -MarkdownFilePath ".\hierarchy.md" `
    -EpicId 123
```

**Create Complete Hierarchy with New Epic**:
```powershell
# Create epics, features, and stories
$result = .\NewAzDoHierarchyFromMarkdown.ps1 `
    -Organization "myorg" `
    -Project "myproj" `
    -MarkdownFilePath ".\hierarchy.md"

# Access created work items
$result.CreatedItems | ForEach-Object { 
    Write-Host "$($_.fields.'System.WorkItemType'): $($_.fields.'System.Title') (ID: $($_.id))"
}
```

### Best Practices

1. **Start with DryRun**: Always use `-DryRun` first to validate your markdown structure
2. **Use relative paths**: Keep hierarchy files in the same directory as scripts for easier execution
3. **Include descriptions**: Add context in markdown comments (lines starting with #)
4. **Validate structure**: Run validation before large bulk operations
5. **Track with tags**: The `generated` tag automatically identifies script-created items
6. **Add more details**: Create additional tags after generation for better organization

## Troubleshooting

### "ssLogIt.ps1 not found"
- Ensure helper scripts are in your PATH
- Verify PowerShell Path contains the directory with helper scripts
- Check: `Get-Command ssLogIt.ps1`

### PAT token errors
- Verify `GMD_AZDO_MACHINE_WORKITEMSRW` is set
- Test decryption: `$env:GMD_AZDO_MACHINE_WORKITEMSRW | ssEncryptDecrypt.ps1 -Decrypt`
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
