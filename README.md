# Azure DevOps Automator - PowerShell Scripts

Comprehensive PowerShell script collection for automating Azure DevOps work item management. All scripts follow strict quality standards including PascalCase naming, strict mode v3, fail-fast error handling, and consistent logging using `ssLogIt.ps1`.

## Overview

This project provides a complete automation toolkit for Azure DevOps work item lifecycle management including:

- **Creating/Updating** Epics, Features, Stories, and Tasks
- **Getting/Setting** work item properties (description, acceptance criteria, story points, effort)
- **Managing Tags** (add, replace, remove)
- **Generating hierarchies** from markdown files
- **Deleting** work items (Epics with cascading children, or individual Tasks) with safety confirmations

## Table of Contents

- [Prerequisites](#prerequisites)
- [Setup](#setup)
  - [Configure PAT Token](#1-configure-pat-token)
  - [Verify Helper Scripts](#2-verify-helper-scripts)
- [Module Architecture](#module-architecture)
- [Automation Scripts](#automation-scripts)
- [Creating Work Item Hierarchies from Markdown](#creating-work-item-hierarchies-from-markdown)
- [Creating Tasks Within Stories](#creating-tasks-within-stories)
- [Example Hierarchy](#example-hierarchy)
- [Testing](#testing)
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
- `Effort` (optional): Effort value in story points (non-negative integer)
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
- `Effort` (optional): Effort value (non-negative integer)
- `State` (optional): Task state (e.g., "To Do", "In Progress", "Done")
- `ParentStoryId` (optional): Parent Story ID (for creation only)
- `FailIfExist` (switch): Create-only mode; fails if title exists (cannot be used with `-Id`)
- `PatToken` (optional): Override default PAT token

**Behavior:**
- If `-Id` provided: Updates Task by ID directly (no title-based lookup)
- If `-Id` not provided: UPSERT by Title (updates if exists, creates if not)
  - With `-FailIfExist`: Creates only if title doesn't exist; fails if found

#### `RemoveAzDoTask.ps1`
Delete a Task work item with optional confirmation prompt.

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
├── Id, Title, Description, Effort
└── Features (array)
    ├── Id, Title, Description, Effort
    └── Stories (array)
        ├── Id, State, Title, Description
        ├── AcceptanceCriteria, ACScenarios
        ├── StoryPoints, ExtraInformation, Tags
        └── Comments (array with latest version of each comment)
```

**Known Limitations:**
- Comments retrieval is optional and may fail gracefully if the API endpoint is unavailable (returns empty array)
- Getting child work items requires a properly configured WIQL endpoint

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

# Run UpsertAzDoStory BDD scenario tests
.\test\Scenario1581Test.ps1

# Run GetAzDoHierarchyForEpic tests
.\test\GetAzDoHierarchyForEpicTest.ps1
```

**Note:** Integration tests create temporary test data (Epic, Features, Stories) and automatically clean up by deleting the test Epic at the end.

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
├── src/
│   ├── AzDoAutomatorConstants.ps1           (Core constants)
│   ├── AzDoPatTokenHelper.ps1               (PAT token management)
│   ├── AzDoApiWrapper.ps1                   (REST API wrapper)
│   ├── AzDoWorkItemHelper.ps1               (Helper functions)
│   ├── UpsertAzDoEpic.ps1                   (Create/update Epics)
│   ├── UpsertAzDoFeature.ps1                (Create/update Features)
│   ├── UpsertAzDoStory.ps1                  (Create/update Stories)
│   ├── GetAzDoWorkItem.ps1                  (Retrieve work item)
│   ├── GetAzDoUserStory.ps1                 (Retrieve User Story with subset or full data)
│   ├── NewAzDoComment.ps1                   (Add comment to work item)
│   ├── GetAzDoComments.ps1                  (Retrieve all comments from work item)
│   ├── UpdateAzDoComment.ps1                (Update comment content)
│   ├── RemoveAzDoComment.ps1                (Remove comment from work item)
│   ├── NewAzDoCommentReaction.ps1           (Add reaction to comment)
│   ├── GetAzDoCommentReactions.ps1          (Retrieve comment reactions)
│   ├── GetAzDoHierarchyForEpic.ps1          (Retrieve Epic hierarchy with Features and Stories)
│   ├── SetAzDoWorkItemDescription.ps1       (Set description)
│   ├── SetAzDoAcceptanceCriteria.ps1        (Set acceptance criteria)
│   ├── SetAzDoStoryPoints.ps1               (Set story points)
│   ├── SetAzDoEffort.ps1                    (Set effort for Epic/Feature)
│   ├── SetAzDoWorkItemTags.ps1              (Manage tags)
│   ├── UpdateAzDoWorkItemTags.ps1           (Update/add/remove tags - modern replacement)
│   ├── NewAzDoHierarchyFromMarkdown.ps1     (Create from markdown)
│   ├── RemoveAzDoEpic.ps1                   (Delete Epic and children)
│   ├── RunSystemTest.ps1                    (System test suite)
│   └── VerifyAzDoPat.ps1                    (Verify PAT read access)
├── test/
│   ├── BasicIntegrationTest.ps1             (Integration tests)
│   ├── GetAzDoUserStoryTest.ps1             (GetAzDoUserStory tests)
│   ├── Scenario1581Test.ps1                 (UpsertAzDoStory scenario tests)
│   ├── GetAzDoHierarchyForEpicTest.ps1      (GetAzDoHierarchyForEpic tests)
│   ├── NewAzDoCommentTest.ps1               (NewAzDoComment tests)
│   ├── GetAzDoCommentReactionsTest.ps1      (GetAzDoCommentReactions tests)
│   ├── RemoveAzDoCommentTest.ps1            (RemoveAzDoComment tests)
│   ├── NewAzDoCommentReactionTest.ps1       (NewAzDoCommentReaction tests)
│   ├── storyAcTests/
│   │   ├── 1584GetAzDoCommentsTest.ps1      (GetAzDoComments AC scenario tests)
│   │   └── 1585UpdateAzDoCommentTest.ps1    (UpdateAzDoComment AC scenario tests)
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

#### Header Level Requirements

To prevent headers in descriptions from being confused with hierarchy markers:

- **Epic and Feature descriptions**: Must use headers at level 3 (###) or higher
  - Avoid using `#` or `##` in descriptions
  - Example: `### Key Objectives` ✅ (allowed), `## Implementation` ❌ (not allowed)

- **Story descriptions**: Must use headers at level 4 (####) or higher
  - Avoid using `#`, `##`, or `###` in descriptions
  - Example: `#### Scenarios` ✅ (allowed), `### Implementation` ❌ (not allowed)

#### Basic Structure

```markdown
# Epic: Epic Title

**tags**: tag1, tag2\
**Effort**: 21\
**Description**\
Multi-line description with headers at level 3 or higher
### Header in Epic Description
More content here

## Feature: Feature Title

**tags**: tag1, tag2\
**Effort**: 13\
**Description**\
Feature description with headers at level 3 or higher
### Implementation Details
Additional context

### Story: Story Title

**tags**: tag1, tag2\
**SP**: 5\
**Description**\
Story description with headers at level 4 or higher
#### Acceptance Criteria
- [ ] Criterion 1

#### AC Scenarios
1. **Scenario**: First scenario\
  Given...\
  When...\
  Then...

#### Extra Information
- Additional notes and references
```

#### Formatting Guidelines

**Newlines in Descriptions**: Use trailing backslash (`\`) at the end of lines to enforce newlines:

```markdown
## Feature: Example

**tags**: documentation, guide\
**Description**\
This is the first line\
This is the second line (backslash above enforces newline)\
This is the third line
```

**Supported Properties**

**Acceptance Criteria (AC)** - Use checkbox-style lists:
```markdown
#### Acceptance Criteria
- [ ] First criterion
- [ ] Second criterion
```

**Acceptance Criteria Scenarios (ACS)** - Gherkin-style BDD scenarios:
```markdown
#### AC Scenarios
1. **Scenario**: User logs in\
  Given user is on login page\
  When user enters valid credentials\
  Then user is logged in\
  And dashboard is displayed

2. **Scenario**: Login fails with invalid password\
  Given user is on login page\
  When user enters invalid password\
  Then error message is shown
```

**Story Points (SP)**:
```markdown
**SP**: 8
```

**Effort** - Available for Epics and Features (non-negative integer):
```markdown
**Effort**: 21
```

**Extra Information (EI)**:
```markdown
#### Extra Information
- Reference documentation: https://docs.example.com
- Consider security implications\
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
- Trailing backslashes for enforcing newlines in markdown
- **Tasks under Stories** - Examples of leaf-level work items

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

**tags**: user-profile, preferences
**SP**: 5
**Description**
Story description...

#### Task: Setup User Profile Database Schema

**Priority**: 2

**Description**: Create database tables for storing user profile information.

**Original Estimate**: 8

**Remaining**: 8

**Completed**: 0

#### Task: Implement Profile API Endpoints

**Priority**: 1

**Description**: Develop API endpoints for profile CRUD operations.

**Original Estimate**: 13

**Remaining**: 13

**Completed**: 0
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
