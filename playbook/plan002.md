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

### TDD Approach
- Write tests first (failing)
- Implement minimal code to pass (green)
- Refactor for clarity and reusability
- Proceed to next test

### State Constants
- Valid states: New, Active, Resolved, Closed, Under Development
- Reference: AzDoWorkItemTypes.ps1 from nextPlan.md Story 029
- Case-insensitive handling in all comparisons

### Backward Compatibility
- No state rules defined = process all items (existing behavior)
- Existing scripts unaffected by state rules
- Optional: Modify only NewAzDoHierarchyFromMarkdown.ps1

### API Statistics
- All SetAzDoState scripts log API request statistics (per nextPlan Story 027-028)
- Example: "API Requests: Total=1 (GET=0, PATCH=1, POST=0, DELETE=0)"

### Error Handling
- State validation errors = fail-fast (invalid state)
- State rule skip = warning, non-breaking
- Missing item = error (item should exist for update)

## Feature: Set State Scripts for All Work Item Types

**tags**: azDoAutomator, stateManagement, crud, setState  
**Effort**: 12  
**Description**  
Create dedicated scripts to update and retrieve the state of Epics, Features, Stories, Tasks, and Bugs. These scripts provide the foundation for state-based workflow management.

### Story: Create SetAzDoState Script for Epic State Updates (001)

**tags**: azDoAutomator, epic, state, update, crud  
**SP**: 3  
**Description**  
As an automation user, I need to update an Epic's state so I can control workflow progression from automation scripts.

#### Acceptance Criteria
- [ ] Create `SetAzDoEpicState.ps1` to update Epic state
- [ ] Supports: -Organization, -Project, -EpicId (required), -State (required), -PatToken (optional)
- [ ] Valid states: New, Active, Resolved, Closed, Under Development (Azure DevOps default states)
- [ ] Validates state against allowed values before API call
- [ ] Returns updated Epic object with new state as JSON
- [ ] Errors with clear message if state invalid or Epic not found

#### Test Cases (TDD)
- **Test 1 - New Epic State**: Verify Epic can transition to "Active" state
- **Test 2 - Invalid State**: Verify error when attempting invalid state "InvalidState123"
- **Test 3 - Nonexistent Epic**: Verify error when Epic ID does not exist
- **Test 4 - State Transition**: Verify state change is reflected in returned object

#### AC Scenarios
1. **Scenario**: Update Epic to Active  
  Given Epic with ID 100 exists in "New" state  
  When calling SetAzDoEpicState with -State "Active"  
  Then Epic state is changed to "Active"  
  And returned object shows new state

2. **Scenario**: Reject invalid state  
  Given Epic exists  
  When calling with -State "BadState"  
  Then operation errors with "Invalid state: BadState"  
  And Epic state unchanged

#### Extra Information
- Creates: `SetAzDoEpicState.ps1`
- Uses: AzDoApiWrapper, SetAzDoWorkItemDescription pattern for reference
- Output: JSON PSObject with updated Epic
- Status: Not Started

---

### Story: Create SetAzDoState Script for Feature State Updates (002)

**tags**: azDoAutomator, feature, state, update  
**SP**: 3  
**Description**  
As an automation user, I need to update a Feature's state so I can manage workflow progression.

#### Acceptance Criteria
- [ ] Create `SetAzDoFeatureState.ps1` to update Feature state
- [ ] Supports: -Organization, -Project, -FeatureId (required), -State (required)
- [ ] Validates state before update (same state list as Story 001)
- [ ] Returns updated Feature as JSON
- [ ] Clear error messages for invalid states or nonexistent Features

#### Test Cases (TDD)
- **Test 1 - Transition Feature State**: Feature moves from New to Active
- **Test 2 - Invalid State Validation**: Rejects unsupported states
- **Test 3 - Feature Not Found**: Proper error on missing Feature
- **Test 4 - State Persists**: Verify state change saved to Azure DevOps

#### AC Scenarios
1. **Scenario**: Update Feature state successfully  
  Given Feature with ID 200  
  When calling with -State "Resolved"  
  Then Feature state updates and returns new state

#### Extra Information
- Creates: `SetAzDoFeatureState.ps1`
- Pattern: Mirrors SetAzDoEpicState.ps1
- Status: Not Started

---

### Story: Create SetAzDoState Script for Story State Updates (003)

**tags**: azDoAutomator, story, state, update  
**SP**: 3  
**Description**  
As an automation user, I need to update Story state.

#### Acceptance Criteria
- [ ] Create `SetAzDoStoryState.ps1` to update User Story state
- [ ] Supports: -Organization, -Project, -StoryId (required), -State (required)
- [ ] Validates state
- [ ] Returns updated Story as JSON

#### Test Cases (TDD)
- **Test 1 - Story State Transition**
- **Test 2 - Invalid State Handling**
- **Test 3 - Story Not Found Error**
- **Test 4 - State Persisted**

#### Extra Information
- Creates: `SetAzDoStoryState.ps1`
- Status: Not Started

---

### Story: Create SetAzDoState Scripts for Bug & Task (004)

**tags**: azDoAutomator, bug, task, state, update  
**SP**: 3  
**Description**  
As an automation user, I need to update Bug and Task state.

#### Acceptance Criteria
- [ ] Create `SetAzDoBugState.ps1` for Bug state updates
- [ ] Create `SetAzDoTaskState.ps1` for Task state updates
- [ ] Both support: -Organization, -Project, -Id (required), -State (required)
- [ ] Both validate state and return updated objects as JSON
- [ ] Clear error messages for both scripts

#### Test Cases (TDD)
- **Test 1 - Bug State Update**
- **Test 2 - Task State Update**
- **Test 3 - Invalid States for Both**
- **Test 4 - Nonexistent Items**

#### Extra Information
- Creates: `SetAzDoBugState.ps1`, `SetAzDoTaskState.ps1`
- Status: Not Started

---

## Feature: Markdown State Rules Parser

**tags**: azDoAutomator, markdown, parser, stateRules, configuration  
**Effort**: 7  
**Description**  
Parse and validate state rules defined at the top of markdown hierarchy files. Support WriteableStates and ReadOnlyStates parameters to control work item eligibility for updates.

### Story: Parse WriteableStates & ReadOnlyStates from Markdown (005)

**tags**: azDoAutomator, markdown, parser, stateRules  
**SP**: 4  
**Description**  
As a markdown file author, I need to define state rules at the top of my hierarchy file so the update process respects state-based filtering.

#### Acceptance Criteria
- [ ] Create `ParseMarkdownStateRules.ps1` module function
- [ ] Parse `**WriteableStates**: New, Active` format from markdown header section
- [ ] Parse `**ReadOnlyStates**: Closed, Resolved` format from markdown header section
- [ ] Support comma-separated state lists
- [ ] Trim whitespace from state values
- [ ] Return PSObject with $WriteableStates array and $ReadOnlyStates array
- [ ] Both can be null if not specified (default: no filtering)
- [ ] Validate parsed states against known state list
- [ ] Error if unknown state in rules

#### Test Cases (TDD)
- **Test 1 - Parse WriteableStates Only**: "**WriteableStates**: New, Active, Under Development"
- **Test 2 - Parse ReadOnlyStates Only**: "**ReadOnlyStates**: Closed, Resolved"
- **Test 3 - Parse Both**: WriteableStates and ReadOnlyStates both present
- **Test 4 - Empty Markdown**: No state rules returns null/empty arrays
- **Test 5 - Whitespace Handling**: "New, Active , Under Development" trims correctly
- **Test 6 - Invalid State Detection**: Rejects unknown state "InvalidState" with error
- **Test 7 - Case Sensitivity**: States case-insensitive (e.g., "new" matches "New")

#### AC Scenarios
1. **Scenario**: Parse WriteableStates rule  
  Given markdown with `**WriteableStates**: New, Active`  
  When calling ParseMarkdownStateRules  
  Then returns object with WriteableStates = @("New", "Active")  
  And ReadOnlyStates = $null

2. **Scenario**: Parse ReadOnlyStates rule  
  Given markdown with `**ReadOnlyStates**: Closed`  
  When parsing  
  Then ReadOnlyStates = @("Closed")  
  And WriteableStates = $null

3. **Scenario**: Reject invalid state  
  Given markdown with `**WriteableStates**: New, BadState`  
  When parsing  
  Then error: "Unknown state: BadState"

#### Extra Information
- Creates: `ParseMarkdownStateRules.ps1` function/module
- Uses: AzDoWorkItemTypes.ps1 (from nextPlan story 029 for state enums)
- Location: Included in NewAzDoHierarchyFromMarkdown.ps1 or separate module
- Output: PSObject with WriteableStates, ReadOnlyStates arrays
- Status: Not Started

---

### Story: Create State Rule Validator & State Check Function (006)

**tags**: azDoAutomator, stateRules, validation  
**SP**: 3  
**Description**  
Create utility functions to check if a work item's current state allows updates based on parsed rules.

#### Acceptance Criteria
- [ ] Create `CheckStateAllowed` function for update eligibility
- [ ] Function parameters: -CurrentState, -WriteableStates, -ReadOnlyStates
- [ ] Returns $true if state allows updates, $false otherwise
- [ ] Logic: If WriteableStates defined, state MUST be in list (inclusive filter)
- [ ] Logic: If ReadOnlyStates defined, state MUST NOT be in list (exclusive filter)
- [ ] Logic: If neither defined, always allow (default behavior)
- [ ] Logic: If both defined, WriteableStates takes precedence (AND condition)
- [ ] Include reason for rejection in return object

#### Test Cases (TDD)
- **Test 1 - WriteableStates Allow**: CurrentState "New" with WriteableStates ["New", "Active"] returns true
- **Test 2 - WriteableStates Deny**: CurrentState "Closed" with WriteableStates ["New", "Active"] returns false
- **Test 3 - ReadOnlyStates Allow**: CurrentState "Active" with ReadOnlyStates ["Closed"] returns true
- **Test 4 - ReadOnlyStates Deny**: CurrentState "Closed" with ReadOnlyStates ["Closed", "Resolved"] returns false
- **Test 5 - Both Defined (AND)**: WriteableStates takes priority
- **Test 6 - Case Insensitive**: "new" matches "New" in filters
- **Test 7 - No Rules**: Always returns true

#### AC Scenarios
1. **Scenario**: WriteableStates allows New items  
  Given WriteableStates = @("New")  
  When checking item with state "New"  
  Then returns true (allow update)

2. **Scenario**: ReadOnlyStates blocks Closed items  
  Given ReadOnlyStates = @("Closed")  
  When checking item with state "Closed"  
  Then returns false (skip update)

#### Extra Information
- Creates: `CheckStateAllowed` function in ParseMarkdownStateRules.ps1 or utility module
- Return: PSObject { Allowed=$bool, Reason=$string }
- Status: Not Started

---

## Feature: Hierarchy Update Rules Engine

**tags**: azDoAutomator, hierarchy, updateRules, engine  
**Effort**: 10  
**Description**  
Integrate state rules into hierarchy update logic. Apply state filters during NewAzDoHierarchyFromMarkdown.ps1 processing to skip updates for blocked items.

### Story: Apply State Rules to Hierarchy Updates (007)

**tags**: azDoAutomator, hierarchy, stateRules, integration  
**SP**: 5  
**Description**  
As an automation user with state rules defined, I need the hierarchy update process to respect state constraints so read-only work items are not modified.

#### Acceptance Criteria
- [ ] Update `NewAzDoHierarchyFromMarkdown.ps1` to call ParseMarkdownStateRules
- [ ] Extract WriteableStates and ReadOnlyStates from markdown header
- [ ] Before updating each work item (Epic, Feature, Story, Bug), call CheckStateAllowed
- [ ] If state check fails, SKIP update but DO NOT error (continue processing)
- [ ] Log warning for skipped items with reason: "Skipped: Item in ReadOnly state 'Closed'"
- [ ] Track count of skipped items per work item type
- [ ] Return summary with skipped counts in final output

#### Test Cases (TDD)
- **Test 1 - Respect WriteableStates**: Only "New" items updated, "Active" items skipped
- **Test 2 - Respect ReadOnlyStates**: "Closed" items skipped, others updated
- **Test 3 - No Rules**: All items updated regardless of state
- **Test 4 - Partial Updates**: Mixed states result in partial processing
- **Test 5 - Child Items Not Updated**: If parent skipped, children also skipped

#### AC Scenarios
1. **Scenario**: Update hierarchy with state filter  
  Given markdown with WriteableStates: New, Active  
  And Epic "X" is in "New" state, Feature "Y" is in "Closed"  
  When processing hierarchy  
  Then Epic "X" updated  
  And Feature "Y" skipped with warning  
  And processing continues

2. **Scenario**: ReadOnly state blocks all updates  
  Given ReadOnlyStates: Closed, Resolved  
  And all items in "Closed" state  
  When processing  
  Then all items skipped with warnings  
  And summary shows: "Skipped: 5 items"

#### Extra Information
- Updates: `NewAzDoHierarchyFromMarkdown.ps1`
- Calls: ParseMarkdownStateRules, CheckStateAllowed
- Behavior: Non-breaking (warnings not errors)
- Status: Not Started

---

### Story: Implement State Check with Detailed Logging (008)

**tags**: azDoAutomator, logging, diagnostics  
**SP**: 5  
**Description**  
As a user debugging hierarchy updates, I need detailed logging of which items were updated vs. skipped due to state rules.

#### Acceptance Criteria
- [ ] When item skipped by state check, log at INFO level: "Skipped Epic 'Title' (ID:123): State 'Closed' not in WriteableStates [New, Active]"
- [ ] Count skipped items by type (Epic, Feature, Story, Task, Bug)
- [ ] At end of processing, output summary: "Summary: 5 updated, 3 skipped (2 Epic, 1 Feature)"
- [ ] Include skipped reason in each log entry
- [ ] Use ssLogIt.ps1 for all logging
- [ ] Debug level logs show all state checks performed

#### Test Cases (TDD)
- **Test 1 - Log Format**: Verify message contains item type, title, state, rule info
- **Test 2 - Count Accuracy**: Correct counts for each type
- **Test 3 - Summary Output**: Final summary includes all counts
- **Test 4 - Multiple Skips**: Multiple items skipped logged correctly
- **Test 5 - No Skips**: Summary shows "0 skipped"

#### AC Scenarios
1. **Scenario**: Detailed skip logging  
  Given 2 items skipped due to state  
  When processing  
  Then each skip logged with reason  
  And summary shows correct count

#### Extra Information
- Updates: NewAzDoHierarchyFromMarkdown.ps1
- Logging: ssLogIt.ps1 INFO level for skips, DEBUG for detail
- Status: Not Started

---

## Feature: Warning & Logging for Skipped Items

**tags**: azDoAutomator, logging, warnings, diagnostics  
**Effort**: 6  
**Description**  
Implement comprehensive warning and logging for state-filtered updates, providing clear diagnostics without breaking workflow.

### Story: Create SkipReason & SkipLog Tracking (009)

**tags**: azDoAutomator, logging, diagnostics, tracking  
**SP**: 3  
**Description**  
As an automation engineer, I need to track which items were skipped during hierarchy updates and why so I can audit and troubleshoot processing.

#### Acceptance Criteria
- [ ] Track skip reason for each item skipped during update
- [ ] Create `SkipLog` array in final return object
- [ ] Each log entry: { ItemType, ItemId, ItemTitle, CurrentState, SkipReason, Timestamp }
- [ ] Return full skip log in processing summary output
- [ ] Optional: export to CSV or JSON for audit trail

#### Test Cases (TDD)
- **Test 1 - Single Skip Logged**: One item skipped, appears in SkipLog
- **Test 2 - Multiple Skips**: All skipped items in log with correct details
- **Test 3 - Skip Log Structure**: All required fields present
- **Test 4 - Timestamp Present**: Each log entry has timestamp

#### Extra Information
- Creates: Skip tracking in NewAzDoHierarchyFromMarkdown.ps1 return object
- Status: Not Started

---

### Story: Implement Non-Breaking Workflow Warning Messages (010)

**tags**: azDoAutomator, warnings, workflow, messaging  
**SP**: 3  
**Description**  
As a user running bulk updates, I need clear warnings when items are skipped so I understand what happened without the process failing.

#### Acceptance Criteria
- [ ] All state-based skips treated as warnings, NOT errors
- [ ] Process continues after skips
- [ ] Warning messages formatted: "[WARNING] Item type 'Feature' title 'X' (ID 123) not updated: State 'Closed' in ReadOnlyStates"
- [ ] Option: Log warnings to stderr but continue stdout JSON output
- [ ] Final exit code 0 even with skips (success with warnings)
- [ ] Option: -WarningsAsErrors switch to treat skips as errors (if needed)

#### Test Cases (TDD)
- **Test 1 - Warnings Not Errors**: Script succeeds despite skips
- **Test 2 - Exit Code 0**: Process completes with exit code 0
- **Test 3 - Messages Clear**: User understands what was skipped
- **Test 4 - Stderr vs Stdout**: Warnings separate from JSON output

#### AC Scenarios
1. **Scenario**: Graceful skip with warning  
  Given items skipped due to state  
  When processing  
  Then warnings logged  
  But process completes successfully  
  And exit code 0

#### Extra Information
- Updates: NewAzDoHierarchyFromMarkdown.ps1
- Behavior: Non-breaking by default
- Status: Not Started

---

## Feature: Integration & Comprehensive Testing

**tags**: azDoAutomator, testing, integration, pester  
**Effort**: 12  
**Description**  
End-to-end testing of state management features with TDD approach. Implement Pester tests for all state functionality.

### Story: Create Pester Tests for SetAzDoState Scripts (011)

**tags**: azDoAutomator, testing, pester, state  
**SP**: 4  
**Description**  
As a QA engineer, I need comprehensive Pester tests for all state update scripts.

#### Acceptance Criteria
- [ ] Create Pester test files for SetAzDoEpicState, SetAzDoFeatureState, SetAzDoStoryState, SetAzDoBugState, SetAzDoTaskState
- [ ] Tests use Pester Describe/Context/It structure
- [ ] Mock Azure DevOps API calls
- [ ] Test valid state transitions
- [ ] Test invalid state rejection
- [ ] Test nonexistent item handling
- [ ] All tests pass (green)

#### Test Cases (TDD)
- **Test 1 - Valid State Update**: Successful transition logged
- **Test 2 - Invalid State Rejected**: Error raised
- **Test 3 - Item Not Found**: Proper error handling
- **Test 4 - API Called Correctly**: Verify REST call parameters
- **Test 5 - Return Object Format**: JSON output validated

#### Extra Information
- Creates: `test/SetAzDoEpicState.Tests.ps1`, etc.
- Framework: Pester v5+
- Mocking: Mock Azure DevOps API responses
- Status: Not Started

---

### Story: Create Pester Tests for ParseMarkdownStateRules (012)

**tags**: azDoAutomator, testing, pester, markdown  
**SP**: 4  
**Description**  
As a QA engineer, I need tests for markdown parsing and state rule validation.

#### Acceptance Criteria
- [ ] Create: `test/ParseMarkdownStateRules.Tests.ps1`
- [ ] Test WriteableStates parsing
- [ ] Test ReadOnlyStates parsing
- [ ] Test both present simultaneously
- [ ] Test invalid state detection
- [ ] Test whitespace handling
- [ ] Test case-insensitivity
- [ ] All tests pass

#### Test Cases (TDD)
- **Test 1 - Parse WriteableStates**
- **Test 2 - Parse ReadOnlyStates**
- **Test 3 - Parse Both**
- **Test 4 - Invalid State Reject**
- **Test 5 - Whitespace Trim**
- **Test 6 - Case Insensitive**

#### Extra Information
- Creates: `test/ParseMarkdownStateRules.Tests.ps1`
- Framework: Pester v5+
- Status: Not Started

---

### Story: Create End-to-End Integration Test (013)

**tags**: azDoAutomator, testing, integration, e2e  
**SP**: 4  
**Description**  
As a QA engineer, I need end-to-end tests for state-aware hierarchy updates.

#### Acceptance Criteria
- [ ] Create: `test/NewAzDoHierarchyFromMarkdownStateRulesIntegrationTest.ps1`
- [ ] Full hierarchy update with state rules
- [ ] Verify state rules enforced
- [ ] Verify skips tracked
- [ ] Verify warnings logged
- [ ] Verify exit code 0 on success
- [ ] Test multiple scenarios (WriteableStates, ReadOnlyStates, mixed states)

#### Test Cases (TDD)
- **Test 1 - Full Hierarchy with WriteableStates**: Only eligible items updated
- **Test 2 - Mixed State Items**: Some updated, some skipped
- **Test 3 - All Items Blocked**: All skipped, process succeeds
- **Test 4 - Skip Count Accurate**: Correct number of items skipped

#### AC Scenarios
1. **Scenario**: End-to-end hierarchy update with state filtering  
  Given markdown with WriteableStates and mixed items  
  When processing full hierarchy  
  Then eligible items updated  
  And ineligible items skipped with warnings  
  And exit code 0  
  And skip log complete

#### Extra Information
- Creates: Integration test file
- Framework: Pester v5+
- Status: Not Started


