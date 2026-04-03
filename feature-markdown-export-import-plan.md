## Feature: Export and Reimport Azure DevOps Hierarchy with Markdown Modification

**tags**: azdoExportImport, hierarchy, markdown, azdoSync  
**Effort**: 34  
**Description**  
Enable users to export the complete Azure DevOps hierarchy (epics, features, stories, and tasks) to markdown format, make arbitrary modifications including title and description changes, and then reliably resync those changes back to Azure DevOps while preserving work item identity and maintaining data integrity.  

This feature bridges the gap between Azure DevOps and markdown-based workflows, enabling collaboration on work item definitions through familiar markdown editors and version control systems. The implementation prioritizes fail-safe behavior, comprehensive state management, and test coverage to prevent data corruption.  

### Key Objectives

- Export hierarchies with full fidelity including all metadata and custom fields  
- Support arbitrary markdown editing workflows with full round-trip capability  
- Preserve work item identity during modifications to ensure reliable synchronization  
- Provide configurable state management per organization and project  
- Maintain comprehensive test coverage throughout all features  
- Fail fast and prevent any risky data modifications in Azure DevOps  

### Architecture Overview

The feature consists of four main components: export, configuration management, reimport with change detection, and comprehensive test support.  

**Export Pipeline**: Reuses existing `GetAzDoHierarchyFor*.ps1` scripts, serializes to markdown with WorkItem IDs embedded in metadata, preserves all state information.  

**Configuration System**: JSON-based state configuration stored at repository root level, scoped per organization and project, defines writable states with defaults.  

**Reimport Pipeline**: Parses markdown back to work item tree, calculates diffs against original, applies safe changes to Azure DevOps, prevents deletion of parent work items if children are modified.  

**Test Support**: Creates temporary test hierarchies for each test run, cleans up automatically, verifies export/import round-trip integrity.  

### Story: (001) Implement State Configuration Schema and Loader

**tags**: azdoExportImport, configuration  
**SP**: 3  
**Description**  
**As a** system maintainer    
**I want** to load and validate state configuration from JSON files scoped by organization and project    
**So that** each team can define rules for which states are editable in their hierarchy exports    

The configuration system must support multiple organizations and projects, provide sensible defaults, and validate state names against actual Azure DevOps state values.  

#### Configuration Architecture

State configuration files follow the pattern: `azdoStateConfig-{orgName}-{projectName}.json` at repository root.  

```  
azdoStateConfig-falco-it-GMD.json:  
{  
  "organization": "falco-it",  
  "project": "GMD",  
  "writableStates": {  
    "Epic": ["New", "Planning", "Planning Done", "Ready for Development"],  
    "Feature": ["New", "Planning", "Planning Done", "Ready for Development"],  
    "UserStory": ["New", "Planning", "Planning Done", "Ready for Development", "Ready for Sprint"],  
    "Task": ["New", "Planning", "Ready for Development", "In Progress", "Done"],  
    "Bug": ["New", "Planning", "Ready for Development", "In Progress", "Done"]  
  },  
  "defaults": {  
    "newItemState": "New",  
    "templateState": "Planning"  
  }  
}  
```  

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ☐ | Configuration file is located and parsed from repository root using org-project naming pattern |  |  |  
| ☐ | Configuration validates all specified states exist in Azure DevOps for organization and project |  |  |  
| ☐ | If configuration file is missing, sensible defaults are applied |  |  |  
| ☐ | Configuration object is cached in memory after first load to avoid repeated file I/O |  |  |  
| ☐ | Configuration format is documented in README.md with examples |  |  |  
| ☐ | README.md includes troubleshooting section for configuration loading issues |  |  |  

#### AC Scenarios
1. **Scenario**: Configuration file exists and is valid  
   Given repository contains `azdoStateConfig-falco-it-GMD.json`  
   When LoadStateConfiguration is called with org "falco-it" and project "GMD"  
   Then configuration is parsed successfully  
   And writableStates for each work item type are loaded  
   And defaults are accessible  

2. **Scenario**: Configuration file is missing but defaults are available  
   Given repository does not contain configuration file for the organization and project  
   When LoadStateConfiguration is called  
   Then a default configuration is returned  
   And common states are marked as writable  
   And no exception is thrown  

3. **Scenario**: Configuration references invalid state names  
   Given configuration file references state name "ReadyForDev" which doesn't exist in Azure DevOps  
   When LoadStateConfiguration validates against Azure DevOps  
   Then validation fails with clear error message  
   And suggests valid state names similar to the invalid one  

#### Extra Information
- Store configuration files in version control for team collaboration  
- Configuration changes require no code deployment  
- Support environment-specific overrides via environment variables for CI/CD pipelines  

### Story: (002) Support State Field in Export with Writable State Validation

**tags**: azdoExportImport, configuration, export  
**SP**: 3  
**Description**  
**As a** user    
**I want** exported work items to include their current state and only allow modification if the state is in the writable states list    
**So that** I can safely modify states in markdown and know which state changes will be applied    

The export functionality must include state information in markdown metadata and mark which states are editable based on the configuration.  

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ☐ | Exported work items include current State field in markdown metadata |  |  |  
| ☐ | Only states in configuration's writable list are marked as editable |  |  |  
| ☐ | Non-writable states have comment warning users that changes will be ignored |  |  |  
| ☐ | Export completes successfully even if state configuration is incomplete |  |  |  

#### AC Scenarios
1. **Scenario**: Export includes editable state  
   Given a Story with state "New" which is in writableStates list  
   When export is generated  
   Then exported markdown includes `**State**: New`  
   And no warning comment appears  
   And user can safely change state in markdown  

2. **Scenario**: Export warns about non-editable state  
   Given a Story with state "Completed" which is not in writableStates list  
   When export is generated  
   Then exported markdown includes `**State**: Completed`  
   And a comment appears: "<!-- State cannot be modified for this work item type -->"  
   And during reimport, any state change will be ignored  

3. **Scenario**: Export works with incomplete configuration  
   Given state configuration is missing for organization and project  
   When export is generated with default configuration  
   Then export succeeds  
   And common states are marked as editable  
   And export is usable for modification  

#### Extra Information
- State validation must call Azure DevOps API to get legitimate state transitions  
- Some states may be read-only due to Azure DevOps workflow rules  
- Document allowed state transitions per work item type in configuration  

### Story: (003) Export Hierarchy to Markdown with WorkItemId Preservation

**tags**: azdoExportImport, export  
**SP**: 5  
**Description**  
**As a** user    
**I want** to export a complete hierarchy starting from any work item with all child work items, preserving work item IDs in the markdown    
**So that** I can modify the exported markdown and reliably resync changes back to the correct work items    

Extend `ExportAzDoHierarchy.ps1` to include WorkItemId in metadata and ensure all hierarchy levels are properly exported.  

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ☐ | Each work item in exported markdown includes WorkItemId in metadata |  |  |  
| ☐ | Complete hierarchy is exported maintaining all parent-child relationships |  |  |  
| ☐ | All work item fields are included (title, description, state, tags, effort, points) |  |  |  
| ☐ | Export creates valid markdown that can be parsed back to JSON without loss |  |  |  
| ☐ | README.md documents the export feature with usage examples |  |  |  
| ☐ | mcpConfig.yaml is updated with export command definitions if exposed as MCP tools |  |  |  

#### AC Scenarios
1. **Scenario**: Export includes WorkItemId for each work item  
   Given a Story with ID 1234 is being exported  
   When export is generated  
   Then markdown includes `**WorkItemId**: 1234`  
   And during reimport, work item ID is used to update existing item not create new one  

2. **Scenario**: Complete hierarchy with all levels is exported  
   Given Feature contains 2 Stories, one Story contains 2 Tasks, another contains 1 Bug  
   When hierarchy export is generated  
   Then markdown shows Feature at level 2  
   And both Stories appear at level 3 under Feature  
   And Tasks appear at level 4 under their parent Story  
   And Bug appears at level 4 under its parent Story  
   And all relationships are maintained in structure  

3. **Scenario**: Export preserves all metadata fields  
   Given Story has title, description, state, tags, story points, and custom field  
   When export is generated  
   Then exported markdown includes all fields in metadata  
   And description content is preserved with line breaks  
   And tags appear in comma-separated format  
   And story points are visible for reimport validation  

#### Extra Information
- Reuse existing `GetAzDoHierarchyFor*.ps1` scripts for data retrieval  
- WorkItemId must be immutable and always preserved during round-trip export/import  
- Support exporting from any work item type as root  
- Export should not modify any data in Azure DevOps (read-only operation)  

### Story: (004) Support Custom Fields and Extended Metadata in Export

**tags**: azdoExportImport, export, customFields  
**SP**: 3  
**Description**  
**As a** user    
**I want** custom fields to be included in the export so that all relevant work item information is available for modification    
**So that** I have complete context when editing in markdown format    

Extend export to capture custom field values defined in Azure DevOps.  

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ☐ | Custom fields are included in markdown metadata section |  |  |  
| ☐ | Field values are properly escaped for markdown |  |  |  
| ☐ | Unknown or null custom fields do not cause export to fail |  |  |  

#### AC Scenarios
1. **Scenario**: Custom fields are exported and preserved  
   Given Story has custom field "Platform" with value "Web"  
   When export is generated  
   Then markdown includes `**Platform**: Web`  
   And custom field is available for reimport  

2. **Scenario**: Special characters in custom fields are handled  
   Given custom field contains: `Value | with pipes & special chars`  
   When export is generated  
   Then value is properly escaped in markdown  
   And reimport can restore original value without data loss  

### Story: (005) Parse Modified Markdown and Reconstruct Work Item Tree

**tags**: azdoExportImport, reimport, parse  
**SP**: 4  
**Description**  
**As a** system    
**I want** to parse markdown that has been edited and reconstruct the work item hierarchy tree with all changes    
**So that** change detection can compare against the original and apply only safe modifications    

Build a robust parser that handles markdown created and edited by humans, preserving all metadata and structure changes.  

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ☐ | Modified markdown is parsed into complete work item tree preserving all metadata |  |  |  
| ☐ | WorkItemId is correctly extracted from all work items |  |  |  
| ☐ | Title and description changes are captured accurately |  |  |  
| ☐ | Parser fails gracefully with clear error if WorkItemId is missing |  |  |  
| ☐ | Parser validates markdown structure and reports invalid items |  |  |  

#### AC Scenarios
1. **Scenario**: Markdown with title and description changes is parsed correctly  
   Given exported markdown where user changed Story title from "Old Title" to "New Title" and description  
   When markdown is parsed  
   Then parser extracts new title and description  
   And WorkItemId is correctly matched  
   And change is ready for application  

2. **Scenario**: Parser detects missing WorkItemId and prevents implicit updates  
   Given markdown where WorkItemId metadata was removed by user  
   When parser attempts to parse  
   Then parser identifies the problem work item  
   And raises error with clear message: "WorkItemId missing for work item at line X"  
   And import is halted to prevent accidental updates  

3. **Scenario**: Parser handles user who reorganized hierarchy  
   Given exported markdown where user moved Story to different Feature  
   When parsed  
   Then new hierarchy structure is captured  
   And old parent relationship is identified as removed  
   And new parent relationship is identified as added  
   And change diff shows the reorganization clearly  

#### Extra Information
- Leverage existing `ConvertMarkdownToHierarchyJson.ps1` for structured parsing  
- Preserve all original field values that were not explicitly changed  
- Detect when required fields are missing (title, WorkItemId)  
- Support markdown edited in any text editor with no special format  

### Story: (006) Detect and Validate Changes Between Original and Modified Hierarchies

**tags**: azdoExportImport, reimport, changeDiff  
**SP**: 5  
**Description**  
**As a** system    
**I want** to compare original exported hierarchy with modified markdown and detect exactly which fields changed for each work item    
**So that** only safe changes are applied and risky modifications are rejected before hitting Azure DevOps    

Create a comprehensive diff engine that identifies field-level changes and hierarchy reorganization while detecting and preventing dangerous modifications.  

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ☐ | Diff correctly identifies all field changes |  |  |  
| ☐ | Diff detects when parent-child relationships changed |  |  |  
| ☐ | Diff prevents deletion of parent if any children were modified |  |  |  
| ☐ | Diff identifies new work items without WorkItemId |  |  |  
| ☐ | Diff validates state changes respect configured writable states |  |  |  

#### AC Scenarios
1. **Scenario**: Single field change is detected  
   Given original Story has title "Current Title" and modified has "New Title"  
   When diff is calculated  
   Then diff shows: title changed from "Current Title" to "New Title"  
   And other fields show as unchanged  
   And change is marked as safe to apply  

2. **Scenario**: Parent-child reorganization is detected  
   Given original Story is child of Feature A, modified version is child of Feature B  
   When diff is calculated  
   Then diff shows the Story was moved  
   And both old parent (Feature A) and new parent (Feature B) are identified  
   And change requires validation that both features exist in current Azure DevOps state  

3. **Scenario**: Dangerous modification prevents application  
   Given Feature has 3 child Stories, user deleted Feature but only modified 1 child Story  
   When diff is calculated  
   Then diff identifies Feature was deleted  
   And diff identifies 1 Story was modified under that deleted Feature  
   And validation raises error: "Cannot delete Feature 123 because child Story 456 has pending modifications"  

4. **Scenario**: New work items are detected for creation  
   Given modified markdown includes Story with no WorkItemId (newly added)  
   When diff is calculated  
   Then item is marked as new (to create, not update)  
   And all child items under new Story are also marked as new  
   And creation order is validated (parent must create before children)  

#### Extra Information
- Store original hierarchy JSON for efficient diff comparison  
- Diff algorithm should use line-by-line comparison for descriptions  
- Validate all work item identifiers exist in current state before applying  
- Generate detailed diff report showing every change with before/after values  

### Story: (007) Apply Validated Changes Back to Azure DevOps

**tags**: azdoExportImport, reimport, apply  
**SP**: 5  
**Description**  
**As a** system    
**I want** to apply validated changes from reimported markdown back to Azure DevOps with transaction-like safety    
**So that** users' modifications are reliably persisted while maintaining data integrity    

Implement the final stage of the reimport pipeline that applies changes with comprehensive error handling and rollback behavior.  

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ☐ | Field changes are applied to correct work items using WorkItemId |  |  |  
| ☐ | Hierarchy changes are validated and applied safely |  |  |  
| ☐ | New work items are created with correct parent relationships in order |  |  |  
| ☐ | If any change fails, entire operation is halted with error reporting |  |  |  
| ☐ | All changes are validated against current Azure DevOps state before applying |  |  |  
| ☐ | README.md documents complete export-modify-reimport workflow |  |  |  
| ☐ | README.md documents state change restrictions and validation rules |  |  |  
| ☐ | mcpConfig.yaml is updated with reimport and validation command definitions |  |  |  

#### AC Scenarios
1. **Scenario**: Single field update is applied successfully  
   Given validated diff shows Story 1234 title changed to "Updated Title"  
   When change is applied  
   Then Azure DevOps Story 1234 now has title "Updated Title"  
   And other Story fields remain unchanged  
   And state change is verified by querying Azure DevOps  

2. **Scenario**: Multiple changes are applied in dependency order  
   Given diff shows: new Feature to create, new Story to create under Feature, existing Task to update  
   When changes are applied  
   Then Feature is created first and receives new ID  
   Then Story is created with Feature ID as parent  
   Then Task is updated  
   And all three operations complete successfully or all are rolled back  

3. **Scenario**: Change application fails gracefully  
   Given validated diff shows title should update, but during application work item 1234 is deleted in Azure DevOps by another user  
   When change is attempted  
   Then system detects 404 error from Azure DevOps  
   Then all pending changes are halted  
   And user is informed: "Failed to apply changes: Story 1234 no longer exists in Azure DevOps (may have been deleted)"  

#### Extra Information
- Use batch API calls where possible to minimize Azure DevOps API load  
- Log all changes for audit trail  
- Provide summary report of what was applied, created, and any failures  
- Never silently skip changes; always report what happened  

#### Task: Implement work item update via Azure DevOps API

**tags**: azdoExportImport, dev, api  
**Priority**: 1  
**OriginalEstimate**: 8  
**Description**  
Implement PATCH requests to update existing work items and POST requests to create new work items. Handle Azure DevOps field validation and API constraints. Reuse `AzDoApiWrapper.ps1` patterns.  

#### Task: Implement change application ordering and error handling

**tags**: azdoExportImport, dev, logic  
**Priority**: 2  
**OriginalEstimate**: 5  
**Description**  
Orchestrate change application ensuring dependencies are satisfied. Implement comprehensive error reporting and optional rollback.  

### Story: (008) Create Test Hierarchy Management System

**tags**: azdoExportImport, testing  
**SP**: 3  
**Description**  
**As a** test framework    
**I want** to create temporary test hierarchies in Azure DevOps for each test run and clean them up afterwards    
**So that** all export/import tests run against real Azure DevOps data with guaranteed cleanup    

Build helper functions that manage the test lifecycle: create temporary epic with test hierarchy, provide cleanup mechanism, document test patterns.  

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ☐ | New Epic is created with "TEST-" prefix for test runs |  |  |  
| ☐ | Test hierarchy under Epic is created with Features, Stories, Tasks, Bugs |  |  |  
| ☐ | Created work items can be queried back via GetAzDo* scripts |  |  |  
| ☐ | Cleanup function reliably deletes test Epic and all child work items |  |  |  
| ☐ | Test infrastructure fails clearly if creation fails |  |  |  

#### AC Scenarios
1. **Scenario**: Test hierarchy is created and ready for use  
   Given test setup is called with hierarchy specification  
   When CreateTestHierarchy is invoked  
   Then new Epic is created in Azure DevOps  
   And Feature under Epic is created and returned with valid WorkItemId  
   And test can use returned IDs for subsequent operations  

2. **Scenario**: Complex test hierarchy with multiple levels is created  
   Given test specifies: 1 Epic, 2 Features (one with 3 Stories each + Tasks)  
   When CreateTestHierarchy builds the structure  
   Then Epic is created at depth 0  
   And 2 Features are created at depth 1 under Epic  
   And 6 Stories total are created at depth 2  
   And Tasks are created at depth 3 under respective Stories  
   And all work items are queryable immediately  

3. **Scenario**: Cleanup removes all test data  
   Given test created Epic with 5 nested work items  
   When cleanup is called  
   Then Epic is deleted  
   And all 5 child work items are removed  
   And subsequent query for Epic returns 404 or empty  

#### Extra Information
- Test hierarchy IDs must be returned as object with properties for easy access in tests  
- Support specifying custom properties (tags, effort, story points) in test hierarchy definition  
- Document test patterns showing how to create export/import test scenarios  
- Ensure cleanup runs even if test fails (use try/finally pattern)  

#### Task: Implement test hierarchy helper functions

**tags**: azdoExportImport, testing, dev  
**Priority**: 1  
**OriginalEstimate**: 3  
**Description**  
Create PowerShell functions for test setup and cleanup. Functions should support creation of customizable hierarchies and reliable removal of test data.  

### Story: (009) Add Integration Tests for Export-Import Round-Trip

**tags**: azdoExportImport, testing, integration  
**SP**: 4  
**Description**  
**As a** developer    
**I want** to run integration tests that export a hierarchy, modify it, reimport it, and verify the result matches expectations    
**So that** I can be confident the export/import cycle preserves data integrity    

Create comprehensive test cases covering various modification scenarios.  

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ☐ | Export-modify-reimport cycle preserves all work item data |  |  |  
| ☐ | Title changes are correctly applied during reimport |  |  |  
| ☐ | Description changes with line breaks are preserved |  |  |  
| ☐ | State changes to writable states are applied successfully |  |  |  
| ☐ | State changes to non-writable states are rejected during reimport |  |  |  

#### AC Scenarios
1. **Scenario**: Complete round-trip export-modify-reimport preserves data  
   Given test hierarchy with 1 Feature, 2 Stories, 1 Task  
   When hierarchy is exported to markdown  
   And markdown is parsed without modification  
   And parsed hierarchy is reimported to Azure DevOps  
   Then all work items match original values exactly  
   And no unexpected changes were applied  
   And WorkItemIds remain the same  

2. **Scenario**: Title and description modifications survive round-trip  
   Given Story with title "Original Title" and description "Original Description"  
   When exported markdown is modified: title → "Modified Title", description → "New Description"  
   And modified markdown is reimported  
   Then Story in Azure DevOps now has new title and description  
   And other fields (tags, effort) remain unchanged  
   And second export matches the modification  

3. **Scenario**: State property changes respect configuration  
   Given Story in state "New" and writable states include "Planning", "Ready for Development"  
   When exported markdown has state changed to "Planning Done"  
   And reimport is attempted  
   Then reimport detects state "Planning Done" is not in writable list  
   And error is raised with message listing valid states  
   And Azure DevOps Story state remains "New"  

#### Extra Information
- Tests should use the test hierarchy helpers to create data  
- Each test should export original state as baseline for comparison  
- Test multiple types of modifications in single scenario  
- Create separate test cases for negative scenarios (invalid modifications rejected)  

#### Task: Implement integration test suite

**tags**: azdoExportImport, testing, dev  
**Priority**: 1  
**OriginalEstimate**: 5  
**Description**  
Create integration tests in Pester covering export-import scenarios. Tests should verify field changes, state validation, and error handling.  
