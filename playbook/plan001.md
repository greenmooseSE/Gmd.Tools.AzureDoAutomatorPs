# Epic: Gmd.Tools.AzureDoAutomatorPs

**tags**: azDoAutomator, azDo, automation, crudOperations, mcpServer  
**Effort**: 79  
**Description**  
Complete build-out of Azure DevOps work item automation tooling to support full CRUD operations on Epics, Features, User Stories, Bugs, and Tasks. Implement comprehensive comment management with reaction support, tag management, and hierarchical retrieval with all associated metadata. Operations consolidated into Upsert* scripts with -FailIfExist switch for create/update unification. Culminate in MCP (Model Context Protocol) server integration to expose all operations as standardized tools for AI assistants and automation frameworks.

### Feature Summary by Phase

| Phase | Feature | Items | Total SP | Notes |
|-------|---------|-------|----------|-------|
| 1 | Work Item CRUD - Consolidate tok Upsert | 4 stories | 19 | Epics, Features, Stories, Tasks |
| 2 | Bug CRUD Support | 4 stories | 12 | Full CRUD + hierarchy integration (partial done) |
| 3 | Comment Management - Full CRUD | 2 stories | 5 | Read, Update operations |
| 4 | Tag Management - Complete Lifecycle | 2 stories | 5 | Update/Remove, consistency verification |
| 5 | Hierarchy Retrieval with Metadata | 3 stories | 9 | Epic/Feature/Story level + metadata |
| 6 | Comment Reactions - Completion | 2 stories | 5 | Delete, validation & documentation |
| 7 | MCP Server Integration | 4 stories | 12 | Config, tests, VS Code setup, docs |
| 8 | API Request Telemetry | 2 stories | 5 | Request tracking, statistics reporting |
| 9 | Type Parameter Validation | 1 story | 2 | Enum-based type validation for work items |
| 10 | Test Coverage & QA (Pester) | 5 stories | 14 | Migrate to Pester, CI pipeline, all operations |
| 11 | Documentation & Completion | 2 stories | 5 | Feature matrix, API reference |
| | **TOTAL** | **31 stories** | **93 SP** | **~93 working days** |

### Summary of Status

#### ✅ Completed
- **Hierarchical Bug Support**: Partial implementation via markdown parser and hierarchy structures
  - Bugs can be added under Stories via nextPlan.md hierarchy
  - Bug fields parsed: title, tags, description, storyPoints, priority, reproSteps, systemInfo, foundInBuild, integratedInBuild
  - Supports comments and tags on bugs
- **UpdateExisting Switch**: NewAzDoHierarchyFromMarkdown.ps1 can now match existing items by title (ignoring "(001)" suffixes)
- **Epic Read**: GetAzDoWorkItem.ps1
- **Epic Delete**: RemoveAzDoEpic.ps1
- **Story Create**: NewAzDoStory.ps1
- **Story Read**: GetAzDoUserStory.ps1
- **Story Update**: UpdateAzDoUserStory.ps1
- **Comment Create**: NewAzDoComment.ps1
- **Comment Delete**: RemoveAzDoComment.ps1
- **Comment Reactions - Create**: NewAzDoCommentReaction.ps1
- **Comment Reactions - Read**: GetAzDoCommentReactions.ps1
- **Tags - Update**: SetAzDoWorkItemTags.ps1
- **Hierarchy - Epic**: GetAzDoHierarchyForEpic.ps1
- **Helper Scripts**: AzDoApiWrapper, AzDoPatTokenHelper, etc.

#### 🚀 Not Started (Numbered by Priority)


### Notes

- All scripts output JSON unless explicitly documented otherwise
- All parameters follow PowerShell conventions (PascalCase)
- Error handling: fail-fast with proper exception messages
- Logging: use ssLogIt.ps1 for all output messages
- Testing: use NUnit with GmdUnitTest<GmdTestContext> base class
- XML Documentation: required for all public scripts
- Strict Mode: All scripts use `Set-StrictMode -Version 3.0` at top
- **Upsert Pattern**: -FailIfExist switch enforces create-only (error if exists); without switch, true upsert (create or update)
- **Naming Convention**: UpdateAzDo* for field-level updates, UpsertAzDo* for create/update operations

## Feature: Work Item CRUD Operations - Consolidate to Upsert

**tags**: azDoAutomator, epicFeatureStoryTask, crud, upsert, consolidation  
**Effort**: 19  
**Description**  
Consolidate Create and Update operations into unified Upsert scripts with -FailIfExist switch for Epics, Features, Stories, and Tasks. Remove duplicate New* and Update* script pairs, allowing single scripts to handle both create and update scenarios efficiently.

### Story: Consolidate Epic Create/Update to UpsertAzDoEpic (001)

**tags**: azDoAutomator, epic, crud, upsert, consolidation  
**SP**: 4  
**Description**  
As an automation user, I need a unified Epic operation so I can create or update Epics with a single script, without maintaining separate New and Update operations.

#### Acceptance Criteria
- [ ] Create `UpsertAzDoEpic.ps1` that replaces NewAzDoEpic.ps1 + future UpdateAzDoEpic.ps1
- [ ] Supports parameters: -Organization, -Project, -Id (optional), -Title, -Description (optional), -Effort (optional), -State (optional)
- [ ] If -Id is provided AND -FailIfExist is set, errors if Epic already exists
- [ ] If -Id is provided without -FailIfExist, updates existing Epic
- [ ] If -Id is not provided, creates new Epic and returns ID
- [ ] Supports partial updates (only specified fields are changed)
- [ ] Script outputs created/updated Epic object with all current fields as JSON
- [ ] Maintains backward compatibility with existing automation that calls NewAzDoEpic.ps1

#### AC Scenarios
1. **Scenario**: Create new Epic (no ID provided)  
  Given no EpicId is provided  
  When calling UpsertAzDoEpic with Organization, Project, Title  
  Then new Epic is created in Azure DevOps  
  And returned object includes new ID, Title, and metadata

2. **Scenario**: Update existing Epic with ID provided  
  Given Epic with ID 123 exists  
  When calling with -Id 123 -Title "Updated Title"  
  Then Epic is updated (not recreated)  
  And Title is changed, other fields unchanged

3. **Scenario**: Enforce create-only with -FailIfExist  
  Given Epic with ID 123 exists  
  When calling with -Id 123 -FailIfExist  
  Then operation errors with "Epic already exists"  
  And Epic is not modified

#### Extra Information
- Creates: `UpsertAzDoEpic.ps1`
- Deprecate: `NewAzDoEpic.ps1` (can be wrapper or removed after migration)
- Pattern: UPSERT operation with -FailIfExist switch for create-only enforcement
- Output: JSON PSObject with all Epic fields
- Status: Not Started

---

### Story: Consolidate Feature Create/Update to UpsertAzDoFeature (002)

**tags**: azDoAutomator, feature, crud, upsert, consolidation  
**SP**: 4  
**Description**  
As an automation user, I need a unified Feature operation so I can create or update Features with a single script.

#### Acceptance Criteria
- [ ] Create `UpsertAzDoFeature.ps1` that replaces NewAzDoFeature.ps1 + future UpdateAzDoFeature.ps1
- [ ] Supports parameters: -Organization, -Project, -Id (optional), -Title, -Description (optional), -Effort (optional), -State (optional), -ParentEpicId (optional for creation)
- [ ] If -Id is provided AND -FailIfExist is set, errors if Feature already exists
- [ ] If -Id is provided without -FailIfExist, updates existing Feature
- [ ] If -Id is not provided, creates new Feature (optionally linked to ParentEpicId)
- [ ] Script outputs created/updated Feature object with all current fields

#### AC Scenarios
1. **Scenario**: Create new Feature under Epic  
  Given Epic exists with ID 100  
  When calling with -ParentEpicId 100 -Title "New Feature"  
  Then Feature is created and linked to Epic  
  And output includes Feature ID and Epic link

2. **Scenario**: Update Feature properties  
  Given Feature with ID 200 exists  
  When calling with -Id 200 -Title "Updated Title" -Effort 13  
  Then Feature Title and Effort are updated

#### Extra Information
- Creates: `UpsertAzDoFeature.ps1`
- Deprecate: `NewAzDoFeature.ps1` (wrapper or removal after migration)
- Status: Not Started

### Story: Consolidate Story Create/Update to UpsertAzDoStory (003)

**tags**: azDoAutomator, story, crud, upsert, consolidation  
**SP**: 5  
**Description**  
As an automation user, I need a unified Story operation consolidating NewAzDoStory.ps1 and UpdateAzDoUserStory.ps1 for consistent create/update semantics.

#### Acceptance Criteria
- [ ] Create `UpsertAzDoStory.ps1` that replaces NewAzDoStory.ps1 + UpdateAzDoUserStory.ps1
- [ ] Supports parameters: -Organization, -Project, -Id (optional), -Title, -Description (optional), -AcceptanceCriteria (optional), -ACScenarios (optional), -StoryPoints (optional), -State (optional), -ParentFeatureId (optional for creation), -ExtraInformation (optional)
- [ ] If -Id not provided, creates new Story (optionally linked to ParentFeatureId)
- [ ] If -Id provided without -FailIfExist, updates existing Story
- [ ] If -Id provided with -FailIfExist, errors if Story exists
- [ ] Supports partial updates (only specified fields change)
- [ ] All Story-specific fields supported (AcceptanceCriteria, ACScenarios, StoryPoints, ExtraInformation)
- [ ] Script outputs created/updated Story object as JSON

#### AC Scenarios
1. **Scenario**: Create new User Story under Feature  
  Given Feature with ID 456 exists  
  When calling with -ParentFeatureId 456 -Title "Story" -StoryPoints 5 -AcceptanceCriteria "AC text"  
  Then Story is created with all fields populated  
  And Story is linked to Feature

2. **Scenario**: Update Story acceptance criteria  
  Given Story with ID 789 exists  
  When calling with -Id 789 -AcceptanceCriteria "Updated AC"  
  Then only AcceptanceCriteria is updated, other fields unchanged

3. **Scenario**: Fail on double-create attempt  
  Given Story with ID 789 exists  
  When calling with -Id 789 -FailIfExist  
  Then operation errors

#### Extra Information
- Creates: `UpsertAzDoStory.ps1` (consolidates 2 scripts)
- Deprecate: `NewAzDoStory.ps1`, `UpdateAzDoUserStory.ps1`
- Status: Not Started

### Story: Create UpsertAzDoTask & RemoveAzDoTask Operations (004)

**tags**: azDoAutomator, task, crud, upsert, delete  
**SP**: 6  
**Description**  
As an automation user, I need Task create, update, and delete operations to manage Tasks as the leaf-level work items in the hierarchy.

#### Acceptance Criteria
- [ ] Create `UpsertAzDoTask.ps1` for create/update operations
- [ ] Supports: -Organization, -Project, -Id (optional), -Title, -Description (optional), -Effort (optional), -State (optional), -ParentStoryId (optional for creation)
- [ ] Create new Task if -Id not provided
- [ ] Update existing Task if -Id provided (without -FailIfExist or with -FailIfExist=$false)
- [ ] Error if -Id provided with -FailIfExist and Task exists
- [ ] Create `RemoveAzDoTask.ps1` for delete operation
- [ ] RemoveAzDoTask supports: -Organization, -Project, -Id, -Force (optional), output summary
- [ ] All operations output JSON format

#### AC Scenarios
1. **Scenario**: Create new Task under Story  
  When calling UpsertAzDoTask without -Id but with -ParentStoryId  
  Then Task is created and linked  
  And output includes Task ID

2. **Scenario**: Update Task state  
  When calling with -Id and -State "In Progress"  
  Then Task state is updated

3. **Scenario**: Delete Task with confirmation  
  When calling RemoveAzDoTask without -Force  
  Then prompt shows Task details  
  And user can confirm/cancel

4. **Scenario**: Force delete Task  
  When calling RemoveAzDoTask with -Force  
  Then Task is deleted immediately

#### Extra Information
- Creates: `UpsertAzDoTask.ps1`, `RemoveAzDoTask.ps1`
- Status: Not Started

---

## Feature: Bug CRUD Operations - Full Support

**tags**: azDoAutomator, bug, crud, fullSupport  
**Effort**: 12  
**Description**  
Implement complete CRUD operations for Bug work items. Bugs are partially supported via the markdown hierarchy parser (can be added to Stories with all required fields). This feature adds dedicated scripts for create, read, update, and delete operations, plus integration with comment and tag systems.

### Story: Create UpsertAzDoBug Script with Full Fields (023)

**tags**: azDoAutomator, bug, crud, upsert, create  
**SP**: 4  
**Description**  
As an automation user, I need to create and update Bugs so I can manage defects as first-class work items.

#### Acceptance Criteria
- [ ] Create `UpsertAzDoBug.ps1` for create/update operations
- [ ] Supports: -Organization, -Project, -Id (optional), -Title, -Description, -Priority (1-4), -ReproSteps, -SystemInfo (optional), -StoryPoints (optional), -FoundInBuild (optional), -IntegratedInBuild (optional), -ParentStoryId (optional for creation)
- [ ] Create new Bug if -Id not provided
- [ ] Update existing Bug if -Id provided without -FailIfExist
- [ ] Error if -Id provided with -FailIfExist and Bug exists
- [ ] Supports tags and comments on bugs
- [ ] Script outputs Bug object as JSON

#### Extra Information
- Creates: `UpsertAzDoBug.ps1`
- Status: Not Started

### Story: Create GetAzDoBug for Bug Retrieval (024)

**tags**: azDoAutomator, bug, crud, read  
**SP**: 2  
**Description**  
As an automation user, I need to retrieve individual Bug details with all metadata.

#### Acceptance Criteria
- [ ] Create `GetAzDoBug.ps1` to fetch single Bug
- [ ] Supports: -Organization, -Project, -BugId (required)
- [ ] Returns Bug with all fields including comments and tags
- [ ] Script outputs JSON

#### Extra Information
- Creates: `GetAzDoBug.ps1`
- Status: Not Started

### Story: Create RemoveAzDoBug for Bug Deletion (025)

**tags**: azDoAutomator, bug, crud, delete  
**SP**: 2  
**Description**  
As an automation user, I need to delete Bugs when they are no longer relevant.

#### Acceptance Criteria
- [ ] Create `RemoveAzDoBug.ps1` to delete Bug
- [ ] Supports: -Organization, -Project, -BugId (required), -Force (optional)
- [ ] Returns success summary as JSON

#### Extra Information
- Creates: `RemoveAzDoBug.ps1`
- Status: Not Started

### Story: Update Hierarchy Scripts to Include Bugs (026)

**tags**: azDoAutomator, bug, hierarchy, integration  
**SP**: 5  
**Description**  
As an automation user, I need hierarchy retrieval to show Bugs under their parent Stories, and markdown parsing to support creating Bugs from markdown.

#### Acceptance Criteria
- [ ] Update `GetAzDoHierarchyForStory.ps1` to include Bugs array
- [ ] Bugs include all metadata: comments, tags, reproSteps, priority, etc.
- [ ] Update `ConvertMarkdownToHierarchyJson.ps1` to recognize and parse "## Bug:" sections under Stories
- [ ] Bugs in markdown include all fields: title, priority (1-4), reproSteps, systemInfo, storyPoints, foundInBuild, integratedInBuild
- [ ] Bug hierarchy matches Story/Task pattern (nested under story, with own metadata)
- [ ] Dry-run output shows parsed Bugs with correct count
- [ ] API request statistics logged after parsing (see Story 027 for statistics collection)

#### Extra Information
- Updates: GetAzDoHierarchyForStory.ps1, ConvertMarkdownToHierarchyJson.ps1
- Status: Not Started

---

## Feature: API Request Telemetry & Statistics

**tags**: azDoAutomator, telemetry, monitoring, statistics, performance  
**Effort**: 3  
**Description**  
Track and report API request statistics for all Azure DevOps API interactions to enable performance monitoring and quota tracking.

### Story: Implement API Request Statistics Collection & Reporting (027)

**tags**: azDoAutomator, telemetry, statistics, monitoring, api  
**SP**: 3  
**Description**  
As an automation engineer, I need to see how many API requests each script makes so I can monitor quota usage and optimize performance.

#### Acceptance Criteria
- [ ] Create `src/AzDoRequestTracker.ps1` module for tracking requests
- [ ] Track request count per script execution
- [ ] Record request types: GET, PATCH, POST, DELETE
- [ ] Output statistics summary after each script completes
- [ ] Statistics include: total count, breakdown by method, execution timestamp
- [ ] Statistics logged to console at INFO level using ssLogIt.ps1
- [ ] Example output: "API Requests: Total=5 (GET=2, PATCH=2, POST=1)"
- [ ] AzDoApiWrapper.ps1 increments tracker on each request
- [ ] Tracker persists count during session (resets per new PowerShell session)

#### AC Scenarios
1. **Scenario**: Script reports API request statistics  
  Given UpsertAzDoStory.ps1 is executed  
  When script completes  
  Then console output includes "API Requests: Total=X (..."  
  And breakdown shows method distribution

2. **Scenario**: Hierarchy script shows cumulative statistics  
  Given GetAzDoHierarchyForEpic.ps1 retrieves 100+ items  
  When script completes  
  Then statistics show total requests made  
  And breakdown by request type (GET for items, etc.)

#### Extra Information
- Creates: `src/AzDoRequestTracker.ps1`
- Updates: All Upsert/Read/Delete/Hierarchy scripts to call tracker
- Updates: AzDoApiWrapper.ps1 to increment tracker
- Format: "API Requests: Total=N (GET=..., PATCH=..., POST=..., DELETE=...)"
- Status: Not Started

### Story: Add API Request Statistics as Standard AC for All Scripts (028)

**tags**: azDoAutomator, telemetry, standardization, quality  
**SP**: 2  
**Description**  
As a quality engineer, I need all work item scripts to report API request statistics consistently.

#### Acceptance Criteria
- [ ] Add to all Upsert*, Update*, Get*, Remove* scripts: "Script outputs API request statistics at completion"
- [ ] Statistics logged after primary output (so JSON output remains parsing-friendly)
- [ ] Format consistent across all scripts: "API Requests: Total=N (method breakdown)"
- [ ] Applies to: UpsertAzDo*, UpdateAzDo*, RemoveAzDo*, GetAzDo* scripts
- [ ] Hierarchy scripts show cumulative statistics for all nested operations
- [ ] Statistics not added to scripts that are helpers (AzDoApiWrapper, AzDoPatTokenHelper, etc.)

#### AC Scenarios
1. **Scenario**: Every new story script reports API requests  
  When any Upsert/Get/Update/Remove script completes  
  Then statistics are logged  
  And format is consistent with Story 027

#### Extra Information
- Add AC to relevant stories: 001-004, 018, 023-025, 029+ (all work item operations)
- Update: All existing scripts to output statistics
- Status: Applies to All Subsequent Stories

---

## Feature: Type Parameter Validation

**tags**: azDoAutomator, typeValidation, enumeration, parameterValidation, robustness  
**Effort**: 2  
**Description**  
Ensure type parameters for work item operations validate against allowed values instead of accepting arbitrary strings.

### Story: Add Type Enumeration & Validation to Work Item Scripts (029)

**tags**: azDoAutomator, typeValidation, parameterValidation, validation  
**SP**: 2  
**Description**  
As a developer, I need type parameters (e.g., Priority for Bugs) to validate against a list of allowed values so invalid inputs are rejected immediately.

#### Acceptance Criteria
- [ ] Create `src/AzDoWorkItemTypes.ps1` enum/validation module
- [ ] Defines allowed WorkItemTypes: Epic, Feature, UserStory, Task, Bug
- [ ] Defines allowed BugPriority: 1, 2, 3, 4 (instead of arbitrary string)
- [ ] Defines allowed WorkItemStates: New, Active, Resolved, Closed, Removed
- [ ] Each enum exported as ValidateSet attribute helpers
- [ ] UpsertAzDoBug.ps1 -Priority parameter uses ValidateSet [1, 2, 3, 4]
- [ ] UpsertAzDo* scripts validate -State against WorkItemStates enum
- [ ] Scripts error with clear message if invalid type provided (e.g., "Priority must be 1-4")

#### AC Scenarios
1. **Scenario**: Bug Priority validation works  
  Given -Priority parameter  
  When calling with -Priority 5  
  Then script errors: "Priority must be one of: 1, 2, 3, 4"  
  And operation does not proceed

2. **Scenario**: State validation works  
  Given -State parameter  
  When calling with -State "InProgress" (invalid casing/format)  
  Then script errors with valid state options  
  And suggests correct values

#### Extra Information
- Creates: `src/AzDoWorkItemTypes.ps1`
- Applies to: UpsertAzDoBug, UpsertAzDo* (Epic, Feature, Story, Task)
- Update: Bug and Upsert story scripts to add validation
- Status: Not Started

---

## Feature: Comment Management - Full CRUD

**tags**: azDoAutomator, comments, crud, collaboration  
**Effort**: 10  
**Description**  
Implement complete comment lifecycle across all work item types. Currently has Create and Delete; needs Read (list comments) and Update operations. Update operations use UpdateAzDoComment naming pattern.

### Story: Implement Comment Read/List Operation (005)

**tags**: azDoAutomator, comments, crud, read  
**SP**: 3  
**Description**  
As an automation user, I need to retrieve all comments on a work item so I can audit, search, or export discussion history.

#### Acceptance Criteria
- [ ] Create `GetAzDoComments.ps1` to list all comments
- [ ] Supports: -Organization, -Project, -WorkItemId (required)
- [ ] Returns array of comment objects with: Id, Content, Author, CreatedDate, UpdatedDate
- [ ] Includes reaction counts for each comment (not individual reaction objects)
- [ ] Script outputs JSON array of comments
- [ ] Returns empty array if no comments

#### AC Scenarios
1. **Scenario**: List all comments on a work item  
  Given Work Item with ID 100 has 3 comments  
  When calling GetAzDoComments.ps1 with WorkItemId  
  Then all 3 comments are returned with metadata

2. **Scenario**: Empty comment list  
  Given Work Item with no comments  
  When calling script  
  Then returns empty array

#### Extra Information
- Creates: `GetAzDoComments.ps1`
- Status: Not Started

### Story: Implement Comment Update Operation (006)

**tags**: azDoAutomator, comments, crud, update  
**SP**: 2  
**Description**  
As an automation user, I need to update comment content so I can fix typos or revise notes. Uses UpdateAzDoComment naming.

#### Acceptance Criteria
- [ ] Create `UpdateAzDoComment.ps1` (NOT SetAzDoComment) to update comment content
- [ ] Supports: -Organization, -Project, -WorkItemId, -CommentId, -Content (required)
- [ ] Script outputs updated comment object as JSON
- [ ] Returns error if comment not found or permission denied

#### AC Scenarios
1. **Scenario**: Update comment successfully  
  Given comment exists with original content  
  When calling UpdateAzDoComment with new content  
  Then comment is updated in Azure DevOps  
  And updated comment object is returned

#### Extra Information
- Creates: `UpdateAzDoComment.ps1` (note: not SetAzDoComment)
- Status: Not Started

---

## Feature: Tag Management - Complete Lifecycle

**tags**: azDoAutomator, tags, tagOps, updateOps  
**Effort**: 8  
**Description**  
Implement complete tag lifecycle. SetAzDoWorkItemTags.ps1 exists for create/update; needs removal capability and consistent tag retrieval. Update operations use UpdateAzDoWorkItemTags naming.

### Story: Implement Tag Update & Removal (007)

**tags**: azDoAutomator, tags, crud, update, delete  
**SP**: 3  
**Description**  
As an automation user, I need to update and remove tags from work items. Use UpdateAzDoWorkItemTags instead of SetAzDoWorkItemTags for consistency.

#### Acceptance Criteria
- [ ] Rename/refactor `SetAzDoWorkItemTags.ps1` to `UpdateAzDoWorkItemTags.ps1`
- [ ] Supports: -Organization, -Project, -WorkItemId, -Tags (array or string), -Replace (switch, if true, replaces all tags)
- [ ] Create separate `-RemoveTag` mode or use negative parameter pattern
- [ ] Can remove specific tags via `-NotTags` parameter (tags to remove) while keeping others
- [ ] If -Tags empty with -Replace, removes all tags
- [ ] Script outputs updated work item with Tags array as JSON

#### AC Scenarios
1. **Scenario**: Add tags to work item  
  When calling with -Tags "bug", "urgent"  
  Then tags are added to work item

2. **Scenario**: Remove specific tag  
  When calling with -NotTags "bug"  
  Then only "bug" is removed, others kept

3. **Scenario**: Replace all tags  
  When calling with -Tags ["new-tag"] -Replace  
  Then all old tags removed, only "new-tag" remains

#### Extra Information
- Refactor: `SetAzDoWorkItemTags.ps1` -> `UpdateAzDoWorkItemTags.ps1`
- Pattern: Remove "Set" prefix in favor of "Update" for consistency
- Status: Not Started

### Story: Ensure Tag Retrieval Consistency (008)

**tags**: azDoAutomator, tags, crud, read, verify  
**SP**: 2  
**Description**  
As an automation user, I need to reliably retrieve tags when fetching work items so tag data is always available.

#### Acceptance Criteria
- [ ] GetAzDoWorkItem.ps1 always includes Tags array in output
- [ ] GetAzDoUserStory.ps1 always includes Tags array (or GetAzDoComments)
- [ ] UpsertAzDoStory.ps1 (when created) returns Tags in output
- [ ] Tags are returned as array of strings (tag names)
- [ ] If no tags, returns empty array (not null)
- [ ] GetAzDoHierarchyForEpic.ps1 includes Tags on each item

#### AC Scenarios
1. **Scenario**: Get work item with tags  
  Given work item has tags ["feature", "backend"]  
  When calling GetAzDoWorkItem  
  Then output includes Tags: ["feature", "backend"]

2. **Scenario**: Get work item without tags  
  Given work item has no tags  
  When calling script  
  Then output includes Tags: []

#### Extra Information
- Review: GetAzDoWorkItem.ps1, hierarchy scripts
- Verify Tags array format consistency
- Status: Verification Needed

---

## Feature: Hierarchy Retrieval with Full Metadata

**tags**: azDoAutomator, hierarchy, retrieval, metadata  
**Effort**: 11  
**Description**  
Enhance hierarchy retrieval to include all available metadata (fields, tags, comments) for every item in the tree. Currently GetAzDoHierarchyForEpic.ps1 returns basic hierarchy; needs comprehensive metadata inclusion at all levels.

### Story: Enhance Hierarchy to Include Full Metadata (009)

**tags**: azDoAutomator, hierarchy, comments, tags, metadata  
**SP**: 3  
**Description**  
As an automation user, I need hierarchy endpoints to include all metadata (comments and tags) on each work item so I can see complete data without separate calls.

#### Acceptance Criteria
- [ ] Update GetAzDoHierarchyForEpic.ps1 to include Comments array on each item
- [ ] Each comment includes: Id, Content, Author, CreatedDate, UpdatedDate
- [ ] Include reaction counts on each comment (not individual reactions per spec)
- [ ] Tags array included on all work items at all levels
- [ ] Empty collections return as empty arrays (not null)
- [ ] Hierarchy remains valid JSON output

#### AC Scenarios
1. **Scenario**: Epic hierarchy includes nested comments and tags  
  Given Epic with Features/Stories that have comments and tags  
  When calling GetAzDoHierarchyForEpic  
  Then each work item includes Comments array and Tags array  
  And all metadata present regardless of depth

#### Extra Information
- Update: GetAzDoHierarchyForEpic.ps1
- Include comment reactions counts but not individual reaction objects
- Status: Verification Needed

### Story: Support Hierarchy Retrieval from Feature Level (010)

**tags**: azDoAutomator, hierarchy, feature, retrieval  
**SP**: 3  
**Description**  
As an automation user, I need to retrieve hierarchy starting from a Feature (not just Epic) so I can examine Feature with its Stories and Tasks.

#### Acceptance Criteria
- [ ] Create `GetAzDoHierarchyForFeature.ps1`
- [ ] Supports: -Organization, -Project, -FeatureId (or -FeatureTitle if not ID)
- [ ] Returns Feature with all child Stories and Tasks nested correctly
- [ ] Each Story includes its Tasks
- [ ] All items include Comments array and Tags array
- [ ] Output is valid JSON
- [ ] Returns $null if Feature not found

#### AC Scenarios
1. **Scenario**: Get Feature hierarchy by ID  
  Given Feature with 3 Stories (each with Tasks)  
  When calling with -FeatureId  
  Then Feature object returned with full hierarchy  
  And all Stories, Tasks, Comments, Tags included

#### Extra Information
- Creates: `GetAzDoHierarchyForFeature.ps1`
- Pattern matches: `GetAzDoHierarchyForEpic.ps1`
- Status: Not Started

### Story: Support Hierarchy Retrieval from Story Level (011)

**tags**: azDoAutomator, hierarchy, story, retrieval  
**SP**: 3  
**Description**  
As an automation user, I need to retrieve hierarchy starting from a Story (showing all Tasks) so I can examine Story details with its Task children.

#### Acceptance Criteria
- [ ] Create `GetAzDoHierarchyForStory.ps1`
- [ ] Supports: -Organization, -Project, -StoryId (or -StoryTitle)
- [ ] Returns Story with all child Tasks
- [ ] All items include Comments array and Tags array
- [ ] Output is valid JSON

#### AC Scenarios
1. **Scenario**: Get Story hierarchy with Tasks  
  Given Story with 5 Tasks  
  When calling GetAzDoHierarchyForStory with -StoryId  
  Then Story with all 5 Tasks returned  
  And full metadata included for each

#### Extra Information
- Creates: `GetAzDoHierarchyForStory.ps1`
- Status: Not Started

---

## Feature: Comment Reaction Management

**tags**: azDoAutomator, commentReactions, crud  
**Effort**: 5  
**Description**  
Complete comment reaction lifecycle. Currently has Create (NewAzDoCommentReaction.ps1) and Read (GetAzDoCommentReactions.ps1); needs Delete operation.

### Story: Implement Comment Reaction Delete Operation (012)

**tags**: azDoAutomator, reactions, crud, delete  
**SP**: 3  
**Description**  
As an automation user, I need to remove reactions from comments so I can undo accidental or unwanted reactions.

#### Acceptance Criteria
- [ ] Create `RemoveAzDoCommentReaction.ps1` to delete reactions
- [ ] Supports: -Organization, -Project, -WorkItemId, -CommentId, -ReactionType (required)
- [ ] ReactionType values: like, dislike, heart, hooray, smile, confused
- [ ] Script returns success summary in JSON
- [ ] Returns error if reaction not found

#### AC Scenarios
1. **Scenario**: Remove reaction from comment  
  Given comment has a "like" reaction  
  When calling RemoveAzDoCommentReaction  
  Then reaction is removed  
  And success response returned

#### Extra Information
- Creates: `RemoveAzDoCommentReaction.ps1`
- Status: Not Started

### Story: Validate & Document Comment Reactions (013)

**tags**: azDoAutomator, reactions, validation, documentation, qa  
**SP**: 2  
**Description**  
As a developer, I need to verify all comment reaction operations work correctly across all scenarios and are well-documented.

#### Acceptance Criteria
- [ ] NewAzDoCommentReaction.ps1 test coverage: all 6 reaction types
- [ ] GetAzDoCommentReactions.ps1 verified to return reactions correctly
- [ ] RemoveAzDoCommentReaction.ps1 tested for all reaction types
- [ ] Scripts handle invalid reaction types with clear error messages
- [ ] All scripts have proper XML documentation

#### AC Scenarios
1. **Scenario**: Test all reaction types  
  When testing all 6 reaction types  
  Then each type creates, retrieves, and deletes successfully

#### Extra Information
- Test: test suite for reaction operations
- Status: Verification Needed

---

## Feature: MCP Server Integration

**tags**: azDoAutomator, mcpServer, modelContextProtocol, integration, automation  
**Effort**: 15  
**Description**  
Integrate all work item automation scripts as MCP (Model Context Protocol) tools. Create configuration and wrapper infrastructure to expose scripts as standardized tools for AI assistants and automation frameworks.

### Story: Create MCP Configuration File (014)

**tags**: azDoAutomator, mcp, configuration, toolMapping, setup  
**SP**: 3  
**Description**  
As an MCP administrator, I need a configuration file that maps all PowerShell scripts to MCP tool names and descriptions so the MCP server knows which scripts to expose.

#### Acceptance Criteria
- [ ] Create `src/mcpConfig.yaml` (or `.json`) mapping scripts to MCP tools
- [ ] Includes all 25+ scripts as tool definitions
- [ ] Each tool has: name, description, script_path, parameters (required and optional)
- [ ] Tool names follow pattern: lowercase verb-noun (e.g., upsert-epic, list-comments)
- [ ] Clear parameter mapping between tool and script
- [ ] Validates against MCP specification schema

#### AC Scenarios
1. **Scenario**: MCP config defines all operations  
  Given config file exists  
  When MCP server reads config  
  Then all scripts registered as tools  
  And parameters match script signatures

#### Extra Information
- Creates: `src/mcpConfig.yaml` or `.json`
- Include updated UpsertAzDo* and UpdateAzDo* scripts
- Status: Not Started

### Story: Test MCP Tool Availability & Execution (015)

**tags**: azDoAutomator, mcp, testing, integration, qa  
**SP**: 4  
**Description**  
As a developer, I need to verify all MCP-exposed tools execute correctly through the MCP interface so the integration is production-ready.

#### Acceptance Criteria
- [ ] Create integration test: `test/McpServerIntegrationTest.ps1`
- [ ] Test invokes MCP server (stdio mode)
- [ ] Tests each tool category: upsert (create/update), read, delete, hierarchy
- [ ] All invocations return valid JSON
- [ ] Tool errors formatted as MCP error responses

#### AC Scenarios
1. **Scenario**: MCP tools execute and return JSON  
  Given MCP server running  
  When test invokes tools  
  Then all execute without errors  
  And output is valid JSON

#### Extra Information
- Creates: `test/McpServerIntegrationTest.ps1`
- Status: Not Started

### Story: Setup MCP Server in VS Code (016)

**tags**: azDoAutomator, vscode, mcp, setup, configuration  
**SP**: 3  
**Description**  
As a developer, I need the MCP server registered in VS Code so it can be used by Copilot and other MCP clients.

#### Acceptance Criteria
- [ ] Create `.vscode/mcp.json` with MCP server registration
- [ ] Registers `gmd-azdo-automator` server
- [ ] Specifies stdio transport
- [ ] Points to `src/RunMcpServer.ps1` with config path
- [ ] Uses `pwsh` command (PowerShell 7+)

#### AC Scenarios
1. **Scenario**: VS Code discovers MCP server  
  Given `.vscode/mcp.json` configured  
  When workspace opens  
  Then MCP server loads  
  And Copilot can access tools

#### Extra Information
- Creates: `.vscode/mcp.json`
- Status: Not Started

### Story: Document MCP Usage & Examples (017)

**tags**: azDoAutomator, documentation, mcp, examples, userGuide  
**SP**: 2  
**Description**  
As a user, I need clear documentation of how to use the MCP server and available tools.

#### Acceptance Criteria
- [ ] Create or update: README-MCP.md or MCP section in README
- [ ] Lists all exposed tools and purposes
- [ ] Provides examples for each tool category
- [ ] Documents parameter formats and JSON inputs/outputs
- [ ] Explains manual MCP server startup
- [ ] Clear for both developers and users

#### AC Scenarios
1. **Scenario**: User reads MCP documentation  
  Given documentation exists  
  When user reads MCP section  
  Then understands tools, parameters, output formats, setup

#### Extra Information
- Creates: README-MCP.md or updates README.md
- Status: Not Started

---

## Feature: Test Coverage & Quality Assurance

**tags**: azDoAutomator, testing, quality, verification, qa, pester  
**Effort**: 11  
**Description**  
Ensure all new and existing scripts have proper test coverage using Pester testing framework. Implement CI-based test execution and verify JSON output format, error handling, and edge cases.

### Story: Migrate to Pester Testing Framework (019)

**tags**: azDoAutomator, testing, pester, testFramework, refactoring  
**SP**: 4  
**Description**  
As a QA engineer, I need to migrate from custom test scripts to industry-standard Pester framework so tests are maintainable, discoverable, and follow PowerShell conventions.

#### Acceptance Criteria
- [ ] Install Pester v5+ as project dependency (via Directory.Build.props or similar)
- [ ] Refactor existing test files to use Pester Describe/Context/It structure
- [ ] Update test runner script to use Invoke-Pester (not custom RunAllTests.ps1 logic)
- [ ] Test discovery: all .Tests.ps1 files under /test folder recognized automatically
- [ ] Tests output NUnit XML format for CI integration
- [ ] All tests support -Verbose, -Debug flags
- [ ] Tests cover: happy path, error cases, edge cases
- [ ] Deprecate old custom test format (BasicIntegrationTest, VerifyAzDoPat patterns)

#### AC Scenarios
1. **Scenario**: Pester discovers and runs all tests  
  When running `Invoke-Pester ./test -Format NUnit`  
  Then all test files execute  
  And results output in NUnit XML format  
  And exit code 0 on pass, non-zero on fail

2. **Scenario**: Test organization follows Pester conventions  
  Given test file structure  
  When opening test file  
  Then uses Describe/Context/It pattern  
  And mocking uses Mock and Assert-MockCalled

3. **Scenario**: Tests validate API request statistics (from Story 027)  
  When tests run UpsertAzDo* scripts  
  Then Assert output includes API request statistics  
  And statistics format validated

#### Extra Information
- Creates: Pester-based .Tests.ps1 files
- Deprecate: Custom test script patterns
- Dependency: Pester v5+ module
- Status: Not Started

### Story: Implement CI-Based Test Execution Pipeline (020)

**tags**: azDoAutomator, testing, cicd, automation, github-actions  
**SP**: 3  
**Description**  
As a DevOps engineer, I need tests to run automatically in CI pipeline so quality gates are enforced before merge.

#### Acceptance Criteria
- [ ] Add GitHub Actions workflow: `.github/workflows/test-on-pr.yaml`
- [ ] Workflow triggers on: pull requests, commits to main
- [ ] Installs Pester v5+ and dependencies
- [ ] Runs: `Invoke-Pester ./test -Format NUnit -OutputPath test-results.xml`
- [ ] Publishes test results to GitHub (actions/upload-artifact)
- [ ] Fails workflow if any tests fail
- [ ] Test execution under `pwsh` (PowerShell 7+)
- [ ] Logs pass/fail counts and statistics

#### AC Scenarios
1. **Scenario**: CI runs Pester tests on PR  
  Given PR created  
  When workflow triggers  
  Then Pester tests execute  
  And results display in PR checks  
  And PR blocked if tests fail

2. **Scenario**: Test results collected and archived  
  When tests complete  
  Then NUnit XML results published  
  And artifact available for CI review

#### Extra Information
- Creates: `.github/workflows/test-on-pr.yaml`
- Template: Use pwsh @@ setup dependencies, Invoke-Pester call, publish results
- Status: Not Started

### Story: Create Test Scripts for Task Operations (021)

**tags**: azDoAutomator, testing, tasks, pesterTests, qa  
**SP**: 2  
**Description**  
As a QA engineer, I need test scripts for Task CRUD operations so I can verify Task management works correctly using Pester.

#### Acceptance Criteria
- [ ] Create: `test/UpsertAzDoTask.Tests.ps1` (Pester format)
- [ ] Create: `test/RemoveAzDoTask.Tests.ps1` (Pester format)
- [ ] Tests verify: create, update, delete operations
- [ ] Tests handle error cases
- [ ] Tests verify API request statistics are logged (Story 027-028)
- [ ] All tests pass with Pester Invoke-Pester runner

#### AC Scenarios
1. **Scenario**: Task test suite passes  
  When running `Invoke-Pester ./test/UpsertAzDoTask.Tests.ps1`  
  Then all operations pass  
  And edge cases handled correctly  
  And API statistics logged for each test case

#### Extra Information
- Creates: Pester .Tests.ps1 files for Task operations
- Status: Not Started

### Story: Create Tests for Upsert Consolidation (022)

**tags**: azDoAutomator, testing, upsert, pesterTests, qa  
**SP**: 3  
**Description**  
As a QA engineer, I need tests for the new Upsert operations to verify create/update consolidation works correctly using Pester.

#### Acceptance Criteria
- [ ] Create: `test/UpsertAzDoEpic.Tests.ps1` (Pester format)
- [ ] Create: `test/UpsertAzDoFeature.Tests.ps1` (Pester format)
- [ ] Create: `test/UpsertAzDoStory.Tests.ps1` (Pester format)
- [ ] Tests verify create, update, and -FailIfExist scenarios
- [ ] Backward compatibility with old New* scripts verified where applicable
- [ ] Tests verify type validation (Story 029)
- [ ] Tests verify API request statistics

#### AC Scenarios
1. **Scenario**: Upsert operations work correctly  
  When running `Invoke-Pester ./test/UpsertAzDo*.Tests.ps1`  
  Then create, update, and -FailIfExist all tested  
  And statistics collected for each operation

#### Extra Information
- Creates: Pester .Tests.ps1 files for Upsert scripts
- Status: Not Started

### Story: Create Tests for Comment & Tag Operations (023)

**tags**: azDoAutomator, testing, comments, tags, pesterTests, qa  
**SP**: 2  
**Description**  
As a QA engineer, I need test scripts for new Comment and Tag operations using Pester framework.

#### Acceptance Criteria
- [ ] Create: `test/GetAzDoComments.Tests.ps1`
- [ ] Create: `test/UpdateAzDoComment.Tests.ps1`
- [ ] Create: `test/UpdateAzDoWorkItemTags.Tests.ps1`
- [ ] Create: `test/RemoveAzDoCommentReaction.Tests.ps1`
- [ ] All tests pass with Pester
- [ ] Tests verify API request statistics

#### AC Scenarios
1. **Scenario**: Comment and tag tests pass  
  When running tests  
  Then all operations work correctly  
  And API statistics logged

#### Extra Information
- Creates: Pester .Tests.ps1 files for new operations
- Status: Not Started

---

## Feature: Documentation & Project Completion

**tags**: azDoAutomator, documentation, projectCompletion, userGuide, reference  
**Effort**: 5  
**Description**  
Create comprehensive documentation for the entire toolset and summarize new structure with Upsert consolidation, Type validation, and Pester testing.

### Story: Create CRUD Operations Feature Matrix (024)

**tags**: azDoAutomator, documentation, reference, featureMatrix  
**SP**: 2  
**Description**  
As a user, I need a clear matrix showing which CRUD operations are supported for each work item type and consolidation status.

#### Acceptance Criteria
- [ ] Create or update: README.md with CRUD matrix table
- [ ] Rows: Epic, Feature, Story, Task, Bug
- [ ] Columns: Upsert (Create/Update), Read, Delete, Comments, Tags, Reactions, Hierarchy
- [ ] Marks completed operations with ✓
- [ ] Notes consolidation to Upsert* operations
- [ ] Links to relevant scripts
- [ ] Notes tested with Pester framework

#### AC Scenarios
1. **Scenario**: User reviews feature matrix  
  Given matrix shows consolidation  
  When user looks for operations  
  Then sees all available operations  
  And understands Upsert* pattern

#### Extra Information
- Update: README.md
- Include notes about Upsert consolidation and Pester testing
- Status: Not Started

### Story: Create API Reference Documentation (025)

**tags**: azDoAutomator, documentation, apiReference, userGuide  
**SP**: 3  
**Description**  
As a developer, I need API reference documentation for all scripts including Upsert, Update, type validation, and API statistics.

#### Acceptance Criteria
- [ ] Create: API-REFERENCE.md documenting all scripts
- [ ] For each script: Purpose, Parameters, Output format, Examples
- [ ] JSON output examples for key scripts
- [ ] Organized by category: Upsert CRUD, Read, Delete, Hierarchy, Comments, Tags, Reactions
- [ ] Examples of chaining scripts together
- [ ] Document -FailIfExist pattern for Upsert operations
- [ ] Document type validation and allowed values (Story 029)
- [ ] Document API request statistics format (Story 027-028)
- [ ] Include Pester testing patterns and examples

#### AC Scenarios
1. **Scenario**: Developer consults API reference  
  Given documentation exists  
  When developer looks up UpsertAzDoEpic  
  Then finds description, parameters, examples, -FailIfExist usage  
  And type validation rules documented  
  And API statistics format shown

#### Extra Information
- Creates: API-REFERENCE.md
- Include: Example outputs with API statistics
- Status: Not Started

