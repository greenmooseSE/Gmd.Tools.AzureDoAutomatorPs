# Azure DevOps Automator - Planned Work

## Overview
Build a comprehensive PowerShell script collection for automating Azure DevOps work item management. All scripts follow PascalCase naming, use strict mode v3, fail-fast error handling, and ssLogIt.ps1 for logging.

---

## Phase 1: Infrastructure & Utilities

### 1.1 - Create Shared Constants Module
**File:** `src/AzDoAutomatorConstants.ps1`

**Description:**
- Define AzDO API endpoints
- Work item type constants (Epic, Feature, Story, Task)
- Field reference names (Title, Description, Acceptance Criteria, Story Points, Tags)
- Error codes and validation rules

**Verification Checklist:**
- [x] File created with valid PowerShell syntax
- [x] All constants documented with inline comments
- [x] Script can be dot-sourced without errors
- [x] Strict mode v3 enabled

---

### 1.2 - Create PAT Token Helper Module
**File:** `src/AzDoPatTokenHelper.ps1`

**Description:**
- Function to get PAT token (with optional decryption fallback)
- Function to create basic auth header for AzDO API calls
- Validate PAT token is not empty
- Default: `($env:FALCOIT_AZDO_PAT_WORKITEMSREADWRITE | ssEncryptDecrypt.ps1 -Decrypt)`

**Verification Checklist:**
- [x] File created with stop error preference
- [x] ssLogIt.ps1 existence checked with Get-Command
- [x] PAT token retrieval works
- [x] Base64 auth header generation tested
- [x] Error handling for missing PAT token works

---

### 1.3 - Create AzDO API Wrapper Module
**File:** `src/AzDoApiWrapper.ps1`

**Description:**
- Function to invoke AzDO REST API with proper headers
- Automatic error handling and logging
- Support for GET, POST, PATCH operations
- Retry logic for transient failures
- Parse JSON responses

**Verification Checklist:**
- [x] API wrapper created with proper error handling
- [x] GET requests work correctly
- [x] POST requests work correctly
- [x] PATCH requests work correctly
- [x] JSON parsing works
- [x] Logging uses ssLogIt.ps1 with appropriate log levels

---

### 1.4 - Create Work Item Query Helper Module
**File:** `src/AzDoWorkItemHelper.ps1`

**Description:**
- Function to query work items by title and parent
- Function to get work item by ID
- Function to check if work item exists
- Support filtering by area/iteration

**Verification Checklist:**
- [x] Query functions created
- [x] Can search by title within parent context
- [x] Can retrieve work items by ID
- [x] Error handling for not-found scenarios
- [x] Logging is consistent

---

## Phase 2: Core Feature Scripts

### 2.1 - Create New-AzDoFeature Script
**File:** `src/New-AzDoFeature.ps1`

**Description:**
- Create new Feature or update existing with same title
- Parameters:
  - `Title` (required): Feature title
  - `Description` (optional): Feature description
  - `ParentEpicId` (optional): Parent Epic ID
  - `PatToken` (optional): Override PAT token
  - `UpdateExisting` (switch): Explicitly update if exists
- Output: Created/updated Feature work item object with ID
- Fail if exists but UpdateExisting not specified

**Verification Checklist:**
- [x] Script created with PascalCase naming
- [x] Strict mode v3 enabled
- [x] Stop error preference set
- [x] Required parameters validated
- [x] Can create new Feature
- [x] Can update existing Feature with UpdateExisting switch
- [x] Returns work item ID on success
- [x] Proper error messages with ssLogIt.ps1
- [x] Fails without UpdateExisting if item exists

---

### 2.2 - Create New-AzDoStory Script
**File:** `src/New-AzDoStory.ps1`

**Description:**
- Create new Story or update existing with same title
- Parameters:
  - `Title` (required): Story title
  - `Description` (optional): Story description
  - `AcceptanceCriteria` (optional): Acceptance criteria text
  - `StoryPoints` (optional): Story point value
  - `ParentFeatureId` (required): Parent Feature ID
  - `PatToken` (optional): Override PAT token
  - `UpdateExisting` (switch): Explicitly update if exists
- Output: Created/updated Story work item object with ID
- Fail if exists but UpdateExisting not specified

**Verification Checklist:**
- [x] Script created with PascalCase naming
- [x] Strict mode v3 enabled
- [x] Stop error preference set
- [x] ParentFeatureId validation
- [x] Can create new Story
- [x] Can update existing Story with UpdateExisting switch
- [x] Returns work item ID on success
- [x] Proper error messages with ssLogIt.ps1
- [x] Fails without UpdateExisting if item exists

---

### 2.3 - Create Set-AzDoWorkItemDescription Script
**File:** `src/Set-AzDoWorkItemDescription.ps1`

**Description:**
- Update description of existing work item
- Parameters:
  - `WorkItemId` (required): Work item ID to update
  - `Description` (required): New description text
  - `PatToken` (optional): Override PAT token
- Output: Updated work item object

**Verification Checklist:**
- [x] Script created with PascalCase naming
- [x] Strict mode v3 enabled
- [x] Stop error preference set
- [x] Can update work item description
- [x] Returns updated work item
- [x] Error handling for invalid work item ID
- [x] Proper logging with ssLogIt.ps1

---

### 2.4 - Create Set-AzDoAcceptanceCriteria Script
**File:** `src/Set-AzDoAcceptanceCriteria.ps1`

**Description:**
- Update acceptance criteria of existing work item
- Parameters:
  - `WorkItemId` (required): Work item ID
  - `AcceptanceCriteria` (required): Criteria text
  - `PatToken` (optional): Override PAT token
- Output: Updated work item object

**Verification Checklist:**
- [x] Script created with PascalCase naming
- [x] Strict mode v3 enabled
- [x] Stop error preference set
- [x] Can update acceptance criteria
- [x] Returns updated work item
- [x] Error handling for invalid work item ID
- [x] Proper logging with ssLogIt.ps1

---

### 2.5 - Create Set-AzDoStoryPoints Script
**File:** `src/Set-AzDoStoryPoints.ps1`

**Description:**
- Update story points of existing work item
- Parameters:
  - `WorkItemId` (required): Work item ID
  - `StoryPoints` (required): Integer story point value
  - `PatToken` (optional): Override PAT token
- Output: Updated work item object
- Validate StoryPoints is numeric

**Verification Checklist:**
- [x] Script created with PascalCase naming
- [x] Strict mode v3 enabled
- [x] Stop error preference set
- [x] Can update story points
- [x] Validates numeric story points
- [x] Returns updated work item
- [x] Error handling for invalid work item ID
- [x] Proper logging with ssLogIt.ps1

---

### 2.6 - Create Get-AzDoWorkItem Script
**File:** `src/Get-AzDoWorkItem.ps1`

**Description:**
- Retrieve work item by ID with all fields
- Parameters:
  - `WorkItemId` (required): Work item ID
  - `PatToken` (optional): Override PAT token
- Output: Complete work item object
- Include fields: Title, Description, Story Points, Acceptance Criteria, Tags, Parent

**Verification Checklist:**
- [x] Script created with PascalCase naming
- [x] Strict mode v3 enabled
- [x] Stop error preference set
- [x] Can retrieve work item by ID
- [x] Returns complete object with all fields
- [x] Error handling for not-found/invalid ID
- [x] Proper logging with ssLogIt.ps1

---

## Phase 3: Advanced Features

### 3.1 - Create New-AzDoHierarchyFromMarkdown Script
**File:** `src/New-AzDoHierarchyFromMarkdown.ps1`

**Description:**
- Parse markdown file and create Epic/Feature/Story hierarchy
- Markdown structure:
  ```
  # Epic Title
  ## Feature 1 Title
  - Story 1 Title
    - AC: Acceptance criteria
    - SP: 5
  - Story 2 Title
  ## Feature 2 Title
  ```
- Pre-parse validation (fail before creating anything)
- Parameters:
  - `MarkdownFilePath` (required): Path to markdown file
  - `EpicId` (optional): Parent Epic ID (creates Feature-level if not provided)
  - `PatToken` (optional): Override PAT token
  - `DryRun` (switch): Show what would be created without creating
- Output: Summary of created work items with IDs

**Verification Checklist:**
- [x] Script created with PascalCase naming
- [x] Strict mode v3 enabled
- [x] Stop error preference set
- [x] Markdown parsing works
- [x] Pre-validation catches unsupported fields
- [x] DryRun mode shows planned operations
- [x] Creates hierarchy correctly
- [x] Proper error messages for invalid format
- [x] Proper logging with ssLogIt.ps1

---

### 3.2 - Create Set-AzDoWorkItemTags Script
**File:** `src/Set-AzDoWorkItemTags.ps1`

**Description:**
- Add, replace, or remove tags on work item
- Parameters:
  - `WorkItemId` (required): Work item ID
  - `Tags` (optional): Array of tags to set
  - `Mode` (default: 'Replace'): 'Add', 'Replace', or 'Remove'
  - `PatToken` (optional): Override PAT token
- Output: Updated work item object with tags

**Verification Checklist:**
- [x] Script created with PascalCase naming
- [x] Strict mode v3 enabled
- [x] Stop error preference set
- [x] Can add tags
- [x] Can replace tags
- [x] Can remove tags
- [x] Returns updated work item
- [x] Proper logging with ssLogIt.ps1

---

### 3.3 - Create Remove-AzDoEpic Script
**File:** `src/Remove-AzDoEpic.ps1`

**Description:**
- Delete Epic and all its child work items (Features/Stories)
- Parameters:
  - `EpicId` (required): Epic work item ID
  - `PatToken` (optional): Override PAT token
  - `Force` (switch): Skip confirmation prompt
- Requires runtime confirmation unless Force specified
- Output: Summary of deleted work items

**Verification Checklist:**
- [x] Script created with PascalCase naming
- [x] Strict mode v3 enabled
- [x] Stop error preference set
- [x] Requires confirmation (interactive prompt)
- [x] Force switch bypasses confirmation
- [x] Can list all items to be deleted before confirmation
- [x] Deletes all children recursively
- [x] Deletes Epic
- [x] Returns deletion summary
- [x] Proper logging with ssLogIt.ps1
- [x] Error handling for invalid Epic ID

---

## Phase 4: Testing & Documentation

### 4.1 - Create Basic Integration Tests
**File:** `test/HelperScriptsTests/AzDoHelperTestFixture.ps1`

**Description:**
- Basic tests to validate core functions work
- Mock AzDO API when needed
- Test helper functions in isolation

**Verification Checklist:**
- [x] Test file created
- [x] API wrapper tests pass
- [x] Query helper tests pass
- [x] PAT token helper tests pass

---

### 4.2 - Update Main README
**File:** `README.md` (Update existing)

**Description:**
- Add section documenting all new scripts
- Include usage examples
- Document required environment variables
- Document PAT token encryption setup

**Verification Checklist:**
- [x] README updated with all script documentation
- [x] Examples are accurate
- [x] Required env vars documented
- [x] Usage instructions clear

---

## General Requirements for All Scripts

- [x] All scripts use `#Requires -Version 7.0` (PowerShell Core)
- [x] All scripts have `Set-StrictMode -Version 3.0`
- [x] All scripts have `$ErrorActionPreference = 'Stop'`
- [x] All scripts have descriptive header comment block
- [x] All scripts have parameter documentation
- [x] All scripts validate required parameters with proper error messages
- [x] All scripts use ssLogIt.ps1 for logging (verified with Get-Command)
- [x] All scripts use colored tokens in log messages (::FgGreen::, ::FgRed::, etc.)
- [x] All scripts use Stop error preference (no fallbacks, fail hard)
- [x] All scripts include proper error handling without silent catches
- [x] No markdown files created (except plannedWork.md by user request)

---

## Implementation Order

**Priority 1 (Core Infrastructure):**
1. Create constants module (1.1)
2. Create PAT token helper (1.2)
3. Create API wrapper (1.3)
4. Create work item helper (1.4)

**Priority 2 (Basic Features):**
5. Create New-AzDoFeature (2.1)
6. Create New-AzDoStory (2.2)
7. Create property setters (2.3-2.5)
8. Create Get-AzDoWorkItem (2.6)

**Priority 3 (Advanced Features):**
9. Create New-AzDoHierarchyFromMarkdown (3.1)
10. Create Set-AzDoWorkItemTags (3.2)
11. Create Remove-AzDoEpic (3.3)

**Priority 4 (Testing & Documentation):**
12. Create tests (4.1)
13. Update README (4.2)

---
## Verification Status

- [x] All Phase 1 modules created and verified
- [x] All Phase 2 feature scripts created and verified
- [x] All Phase 3 advanced scripts created and verified
- [x] All Phase 4 tests and documentation completed
- [x] All scripts follow PowerShell standards
- [x] All scripts follow project naming conventions
- [x] All scripts use logging correctly
- [x] Complete solution ready for production use
