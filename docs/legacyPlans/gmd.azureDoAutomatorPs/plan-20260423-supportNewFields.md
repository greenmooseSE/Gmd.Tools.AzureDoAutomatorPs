# Epic: Gmd.Tools.AzureDoAutomatorPs
**WorkItemId**: 1577
**State**: New

**WorkItemId**: 1577  
**State**: New  
**tags**: azDoAutomator, automation, azdo, crudOperations, mcpServer  
**Effort**: 79  
**Description**  
Complete build-out of Azure DevOps work item automation tooling to support full CRUD operations on Epics, Features, User Stories, Bugs, and Tasks. Implement comprehensive comment management with reaction support, tag management, and hierarchical retrieval with all associated metadata. Operations are consolidated into Upsert* scripts with -FailIfExist switch for create/update unification. Culminate in MCP (Model Context Protocol) server integration to expose all operations as standardized tools for AI assistants and automation frameworks.  

## Feature: Support All Azure DevOps Fields with Unified Configuration
**WorkItemId**: 2612
**State**: New

**tags**: azDoAutomator, fieldSupport, epicAzDoAutomator  
**Effort**: 13  
**Priority**: 2  
**Description**  
Introduce comprehensive field support for all Azure DevOps work item types (Epic, Feature, User Story, Bug, Task) — both reading and writing — driven by a centralized configuration file. Replace the per-org/project state config file (`azdoStateConfig-{org}-{project}.json`) with a single unified `appSettings.json` at the repository root. This config stores field definitions (referenceName, label, description, type, readOnly) per work item type and state definitions (name, category, readOnly) per work item type, grouped by organization and project.  

### Goals  
- Every field surfaced by the Azure DevOps REST API for the five work item types must be  
  representable in the configuration and usable in read, write, and markdown workflows.  
- The "SP" shorthand label is replaced everywhere by the official field label "Story Points".  
- Configuration is org/project-scoped so the same tooling works for any Azure DevOps organization  
  and project, not just falco-it / GMD.  

### Verified Fields from Azure DevOps REST API  

**Epic**: Title, Description, State, Tags, AssignedTo, AreaPath, IterationPath, Priority,  
BusinessValue, Risk, ValueArea, TimeCriticality, Effort, StartDate, TargetDate  

**Feature** (adds to Epic): AIImplemented, CodeReviewed, FunctionallyTested, DeployedToDev,  
DeployedToStaging, DeployedToProduction, ExtraInformation, FeatureAcceptanceTests, FixedIn,  
StoryPoints  

**User Story** (adds to Feature): ACScenarios, AcceptanceCriteria, StoryAcceptanceTests,  
ApplicableTo, CodeReviewedBy, TestedBy, OriginalEstimate, RemainingWork, CompletedWork,  
FinishDate (replaces FeatureAcceptanceTests)  

**Bug** (adds to Feature): ReproSteps, SystemInfo, FoundIn, Severity, Activity,  
OriginalEstimate, RemainingWork, CompletedWork (replaces FeatureAcceptanceTests)  

**Task**: Title, Description, State, Tags, AssignedTo, AreaPath, IterationPath, Priority,  
Activity, OriginalEstimate, RemainingWork, CompletedWork, StartDate, FinishDate  

### State Definitions (from REST API)  

| Type | States |
|------|--------|
| Epic | New, Active, Resolved, Closed, Removed |
| Feature | New, Planning, Planning Done, Ready for Development, Active, RTM, Released, Removed |
| User Story | New, Design, Ready for Development, Under Development, CR Pending, CR In Progress, Test Pending, Test In Progress, RTM, Released, Removed |
| Bug | New, Ready for Development, Under Development, CR Pending, CR In Progress, Test Pending, Test In Progress, RTM, Released, Removed |
| Task | New, Active, Closed, Removed |

### Story: Create unified appSettings.json with field and state definitions (001)
**WorkItemId**: 2613
**State**: Done ✅

**tags**: azDoAutomator, fieldSupport, epicAzDoAutomator  
**Story Points**: 2  
**Priority**: 1  
**Description**  
**As a** developer or AI agent using this tooling  
**I want** a single `appSettings.json` at the repository root that defines all supported fields and states per work item type, grouped by organization and project  
**So that** field and state metadata is centralized, extensible to other orgs/projects, and drives all downstream read/write/markdown operations dynamically.  

#### Implementation Details  
- Create `appSettings.json` at the repository root.  
- Structure: `organizations.{org}.projects.{project}.fields.{WorkItemType}` — array of field  
  objects, each with `referenceName`, `label`, `description`, `type`, `readOnly`.  
- Structure: `organizations.{org}.projects.{project}.states.{WorkItemType}` — array of state  
  objects, each with `name`, `category`, `readOnly`.  
- Include `System.Id` as a readOnly pseudo-field for every work item type  
  (label: "WorkItemId", type: "integer", readOnly: true).  
- Populate `falco-it` / `GMD` entries from the REST API field and state data.  
- States that belong to "Completed" or "Removed" categories should be marked `readOnly: true`;  
  all others `readOnly: false`.  
- Update `LoadStateConfiguration.ps1` to read states from the new `appSettings.json` path  
  and structure (org/project grouping, state objects with readOnly) instead of  
  `azdoStateConfig-{org}-{project}.json`.  
- Maintain backward compatibility: if `appSettings.json` is missing, fall back to  
  the legacy `azdoStateConfig-{org}-{project}.json` file if it exists.  
- Expose a helper function (or extend `LoadStateConfiguration.ps1`) to load field definitions  
  from `appSettings.json` for a given org/project/work item type.  

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ✅ | appSettings.json exists at repo root and validates against expected schema | `appSettings.json exists at repo root`, `appSettings.json is valid JSON` |  |
| ✅ | Field definitions for Epic contain at least 15 fields including System.Id | `Epic field list has at least 15 entries including System.Id` |  |
| ✅ | Field definitions for Feature include all Custom.* fields (AIImplemented, CodeReviewed, FunctionallyTested, DeployedToDev, DeployedToStaging, DeployedToProduction, ExtraInformation, FeatureAcceptanceTests, FixedIn) | `Feature field list contains all required Custom.* fields` |  |
| ✅ | Field definitions for User Story include ACScenarios, AcceptanceCriteria, StoryAcceptanceTests, OriginalEstimate, RemainingWork, CompletedWork | `User Story field list contains ...` |  |
| ✅ | Field definitions for Bug include ReproSteps, SystemInfo, FoundIn, Severity | `Bug field list contains ReproSteps, SystemInfo, FoundIn, Severity` |  |
| ✅ | Field definitions for Task include Activity, OriginalEstimate, RemainingWork, CompletedWork | `Task field list contains Activity, OriginalEstimate, RemainingWork, CompletedWork` |  |
| ✅ | Each field object contains referenceName, label, description, type, and readOnly properties | `every field object has referenceName, label, description, type, and readOnly` |  |
| ✅ | State definitions for each work item type match the REST API states with correct readOnly flags | `state definitions exist for all five work item types`, `Feature Released and Removed are readOnly; New is not` |  |
| ✅ | States in "Completed" and "Removed" categories are marked readOnly: true | `states in Completed and Removed categories have readOnly true` |  |
| ✅ | LoadStateConfiguration.ps1 reads writable states from appSettings.json grouped by org/project | `GivenAppSettingsJson_WhenLoadingStates_ItShouldReturnWritableStatesForAllTypes` |  |
| ✅ | LoadStateConfiguration.ps1 falls back to legacy azdoStateConfig file when appSettings.json is absent | `GivenNoAppSettingsJson_WhenLegacyFileExists_ItShouldLoadFromLegacyFile` |  |
| ✅ | System.Id is present as a readOnly field in every work item type with label "WorkItemId" | `System.Id is readOnly integer with label WorkItemId for every work item type` |  |

#### AC Scenarios
1. **Scenario**: Load field definitions for User Story from appSettings.json  
   Given appSettings.json exists at repo root with falco-it/GMD configuration  
   When field definitions are loaded for organization "falco-it", project "GMD", type "User Story"  
   Then the result contains field entries for System.Id, System.Title, Custom.ACScenarios,  
   Microsoft.VSTS.Scheduling.StoryPoints, Microsoft.VSTS.Scheduling.OriginalEstimate  
   And each entry has non-null referenceName, label, type, and readOnly properties  

2. **Scenario**: Load states for Feature with readOnly flags  
   Given appSettings.json exists with falco-it/GMD state configuration  
   When states are loaded for organization "falco-it", project "GMD", type "Feature"  
   Then the result contains states: New, Planning, Planning Done, Ready for Development,  
   Active, RTM, Released, Removed  
   And "Released" has readOnly: true  
   And "Removed" has readOnly: true  
   And "New" has readOnly: false  

3. **Scenario**: Backward compatibility when appSettings.json is missing  
   Given appSettings.json does not exist at repo root  
   And azdoStateConfig-falco-it-GMD.json exists with legacy writableStates format  
   When LoadStateConfiguration.ps1 is invoked for organization "falco-it", project "GMD"  
   Then writable states are loaded from the legacy file without error  

4. **Scenario**: Field definitions include System.Id as readOnly pseudo-field  
   Given appSettings.json is loaded for any work item type  
   When inspecting the field list for "Epic"  
   Then a field with referenceName "System.Id", label "WorkItemId", type "integer",  
   readOnly true is present  

#### Extra Information
- Use the Azure DevOps REST API response from  
  `GET _apis/wit/workitemtypes/{type}?api-version=7.1-preview.2` and  
  `GET _apis/wit/fields?api-version=7.1-preview.2` as the source of truth for populating  
  the initial configuration.  
- The legacy `azdoStateConfig-falco-it-GMD.json` file should NOT be deleted in this story;  
  it remains as a fallback until all consumers have been migrated.  

### Story: Rename "SP" markdown label to "Story Points" (002)
**WorkItemId**: 2614
**State**: Done ✅

**tags**: azDoAutomator, fieldSupport, epicAzDoAutomator  
**Story Points**: 0.5  
**Priority**: 1  
**Description**  
**As a** developer using the markdown hierarchy tooling  
**I want** the markdown field label "SP" replaced by "Story Points" (the official Azure DevOps field label) everywhere in the codebase  
**So that** field labels are consistent with Azure DevOps and the new appSettings.json field definitions.  

#### Implementation Details  
- Replace `**SP**:` with `**Story Points**:` in ConvertMarkdownToHierarchyJson.ps1 (parsing).  
- Replace in ConvertHierarchyToMarkdown.ps1 (generation).  
- Replace in GenerateAzDoMarkdownHierarchyTemplate.ps1 (template comments and output).  
- Replace in NewAzDoHierarchyFromMarkdown.ps1 (field passthrough).  
- Replace in SetAzDoStoryPoints.ps1 if it logs or references "SP".  
- Replace in example-hierarchy.md so the reference document is consistent.  
- Update any Pester test files that reference "SP" as a field label.  

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ✅ | ConvertMarkdownToHierarchyJson.ps1 parses `**Story Points**: 5` and produces the correct JSON property |  |  |
| ✅ | ConvertHierarchyToMarkdown.ps1 outputs `**Story Points**: {value}` instead of `**SP**: {value}` |  |  |
| ✅ | GenerateAzDoMarkdownHierarchyTemplate.ps1 output references "Story Points" and not "SP" |  |  |
| ✅ | NewAzDoHierarchyFromMarkdown.ps1 passes the parsed Story Points value to the Upsert script |  |  |
| ✅ | No occurrences of `**SP**:` remain in any .ps1 or .md file in the repository (except legacy plan files) |  |  |

#### AC Scenarios
1. **Scenario**: Parse markdown with "Story Points" label  
   Given a markdown file containing `**Story Points**: 3`  
   When ConvertMarkdownToHierarchyJson.ps1 processes the file  
   Then the JSON output contains a storyPoints property with value 3  

2. **Scenario**: Generate markdown with "Story Points" label  
   Given a work item hierarchy JSON with storyPoints value 5  
   When ConvertHierarchyToMarkdown.ps1 generates markdown  
   Then the output contains `**Story Points**: 5`  
   And the output does not contain `**SP**:`  

3. **Scenario**: Round-trip markdown preserves Story Points  
   Given a markdown file with `**Story Points**: 8` for a story  
   When the file is parsed to JSON and then regenerated to markdown  
   Then the regenerated markdown contains `**Story Points**: 8`  

### Story: Config-driven field parsing and generation in markdown workflow (003)
**WorkItemId**: 2615
**State**: Done ✅

**tags**: azDoAutomator, fieldSupport, epicAzDoAutomator  
**Story Points**: 3  
**Priority**: 2  
**Description**  
**As a** developer or AI agent authoring work item hierarchies in markdown  
**I want** the markdown parsing and generation scripts to dynamically support all fields defined in appSettings.json  
**So that** newly added fields (e.g., AIImplemented, DeployedToDev, OriginalEstimate) are automatically recognized in markdown without per-field code changes.  

#### Implementation Details  
- Update ConvertMarkdownToHierarchyJson.ps1 to load field definitions from appSettings.json  
  and parse any `**{label}**: {value}` line where `{label}` matches a configured field label.  
- Map parsed values to the correct JSON property name (derived from referenceName or a  
  configurable mapping).  
- Handle type coercion: boolean fields ("true"/"false"), double fields (numeric string),  
  integer fields, dateTime fields (ISO 8601 string), html fields (multiline content),  
  string fields (plain text).  
- Update ConvertHierarchyToMarkdown.ps1 to output all populated fields using their configured  
  label, in a consistent order defined by the config.  
- Update NewAzDoHierarchyFromMarkdown.ps1 to forward all parsed fields to the Upsert scripts.  
- Fields marked readOnly in config should be parsed (for round-trip fidelity) but not sent  
  to the API for writes.  
- Maintain existing parsing for core fields (Title, Description, tags, State, WorkItemId)  
  so backward compatibility is preserved for markdown files that predate appSettings.json.  

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ✅ | Boolean field `**AI Implemented**: true` is parsed to a boolean true value in JSON |  |  |
| ✅ | Double field `**Original Estimate**: 8` is parsed to numeric 8.0 in JSON |  |  |
| ✅ | String field `**Fixed In**: v2.1.0` is parsed to string "v2.1.0" in JSON |  |  |
| ☐ | HTML field `**Extra Information**` followed by multiline content is captured as HTML string |  |  |
| ✅ | ReadOnly fields (e.g., WorkItemId) are parsed from markdown but not included in API write payloads |  |  |
| ✅ | Unknown field labels (not in config) produce a warning but do not cause script failure |  |  |
| ✅ | ConvertHierarchyToMarkdown.ps1 outputs all populated fields using configured labels |  |  |
| ✅ | Field output order in generated markdown follows the order defined in appSettings.json |  |  |
| ✅ | Markdown files without appSettings.json-defined fields are still parsed correctly (backward compatible) |  |  |

#### AC Scenarios
1. **Scenario**: Parse Feature markdown with all custom boolean fields  
   Given a markdown file with a Feature containing:  
   `**AI Implemented**: true`, `**Code Reviewed**: false`, `**Deployed To Dev**: true`  
   When ConvertMarkdownToHierarchyJson.ps1 processes the file  
   Then the JSON output contains aiImplemented: true, codeReviewed: false, deployedToDev: true  

2. **Scenario**: Parse User Story markdown with time-tracking fields  
   Given a markdown file with a Story containing:  
   `**Original Estimate**: 16`, `**Remaining Work**: 8`, `**Completed Work**: 8`  
   When ConvertMarkdownToHierarchyJson.ps1 processes the file  
   Then the JSON output contains originalEstimate: 16.0, remainingWork: 8.0, completedWork: 8.0  

3. **Scenario**: Generate Bug markdown with all populated fields  
   Given a Bug JSON object with reproSteps, systemInfo, severity, fixedIn, and deployedToDev values  
   When ConvertHierarchyToMarkdown.ps1 generates markdown  
   Then the output contains `**Repro Steps**`, `**System Info**`, `**Severity**`,  
   `**Fixed In**`, and `**Deployed To Dev**` labels with correct values  

4. **Scenario**: Round-trip fidelity for a Task with time-tracking fields  
   Given a markdown file with a Task containing  
   `**Original Estimate**: 4`, `**Remaining Work**: 4`, `**Completed Work**: 0`  
   When the file is parsed to JSON and regenerated to markdown  
   Then the regenerated markdown preserves all three time-tracking field values  

5. **Scenario**: Unknown field label produces warning but parsing continues  
   Given a markdown file containing `**Nonexistent Field**: somevalue`  
   When ConvertMarkdownToHierarchyJson.ps1 processes the file  
   Then a warning is logged mentioning "Nonexistent Field"  
   And the remaining fields are parsed successfully  
   And the script completes without error  

#### Extra Information
- The field label in markdown must match the `label` property in appSettings.json  
  (case-insensitive comparison).  
- For html-type fields (Description, Extra Information, AC Scenarios, etc.), the parser  
  should continue reading multiline content until the next recognized field label or  
  header is encountered.  
- Consider adding a `markdownOrder` numeric property to field definitions in appSettings.json  
  to control output ordering, or rely on array position.  

### Story: Config-driven field read and write in API operations (004)
**WorkItemId**: 2616
**State**: Done ✅

**tags**: azDoAutomator, fieldSupport, epicAzDoAutomator  
**Story Points**: 3  
**Priority**: 2  
**Description**  
**As a** developer or AI agent using the Get and Upsert scripts  
**I want** all fields defined in appSettings.json to be readable and writable through the existing API wrapper scripts  
**So that** I can retrieve and update any supported field without needing per-field dedicated scripts.  

#### Implementation Details  
- Update `GetAzDoWorkItem.ps1` to map all fields from the API response to friendly property  
  names using the field definitions from appSettings.json.  
- Update `GetAzDoUserStory.ps1` and `GetAzDoBug.ps1` to include all type-specific fields  
  in their output objects.  
- Update Upsert scripts (`UpsertAzDoEpic.ps1`, `UpsertAzDoFeature.ps1`, `UpsertAzDoStory.ps1`,  
  `UpsertAzDoBug.ps1`, `UpsertAzDoTask.ps1`) to accept a `-Fields` hashtable parameter  
  containing any writable field keyed by referenceName.  
- The `-Fields` parameter is merged with existing explicit parameters (Title, Description,  
  Tags, etc.) — explicit parameters take precedence over `-Fields` entries.  
- Validate that fields passed via `-Fields` are defined in appSettings.json and are not readOnly;  
  fail-fast with a clear error if a readOnly field is passed for writing.  
- Retain existing dedicated parameters (Title, Description, Tags, State, StoryPoints, etc.)  
  for backward compatibility.  

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ✅ | GetAzDoWorkItem.ps1 returns AIImplemented, CodeReviewed, FunctionallyTested for a Feature work item |  |  |
| ✅ | GetAzDoUserStory.ps1 returns OriginalEstimate, RemainingWork, CompletedWork, ACScenarios | GivenUserStoryWithTimeFields_WhenBuildingSubset |  |
| ✅ | GetAzDoBug.ps1 returns ReproSteps, SystemInfo, Severity, FoundIn | GivenBugWithReproSteps_WhenEnriched |  |
| ✅ | GetAzDoWorkItem.ps1 returns the current State value for any work item type |  |  |
| ✅ | UpsertAzDoStory.ps1 -Fields parameter can set OriginalEstimate and RemainingWork |  |  |
| ✅ | UpsertAzDoFeature.ps1 -Fields parameter can set AIImplemented and DeployedToDev |  |  |
| ✅ | UpsertAzDoStory.ps1 -State parameter transitions a story to a writable state (e.g., "Under Development") |  |  |
| ✅ | UpsertAzDoFeature.ps1 -State parameter transitions a feature to a writable state (e.g., "Active") |  |  |
| ✅ | Passing a readOnly state (e.g., "Released") via -State causes a fail-fast error before any API call | GivenReadOnlyStateReleased_WhenValidating |  |
| ✅ | Passing a readOnly field (e.g., System.CreatedDate) in -Fields causes a fail-fast error | GivenReadOnlyFieldSystemId_WhenValidating |  |
| ✅ | Explicit parameters (e.g., -Title) take precedence over -Fields entries for the same field |  |  |
| ✅ | Existing scripts calling Upsert without -Fields continue to work unchanged |  |  |

#### AC Scenarios
1. **Scenario**: Read all custom fields from a Feature work item  
   Given a Feature work item exists in Azure DevOps with AIImplemented=true and FixedIn="v1.0"  
   When GetAzDoWorkItem.ps1 retrieves the work item  
   Then the output object contains property aiImplemented with value true  
   And the output object contains property fixedIn with value "v1.0"  

2. **Scenario**: Write time-tracking fields to a User Story via -Fields  
   Given a User Story work item exists in Azure DevOps  
   When UpsertAzDoStory.ps1 is called with -Fields @{  
   "Microsoft.VSTS.Scheduling.OriginalEstimate" = 16;  
   "Microsoft.VSTS.Scheduling.RemainingWork" = 16 }  
   Then the work item is updated with OriginalEstimate=16 and RemainingWork=16  
   And no error is thrown  

3. **Scenario**: Reject write to readOnly field  
   Given a Bug work item exists in Azure DevOps  
   When UpsertAzDoBug.ps1 is called with -Fields @{ "System.CreatedDate" = "2026-01-01" }  
   Then the script throws an error containing "readOnly"  
   And no API call is made  

4. **Scenario**: Explicit parameter takes precedence over -Fields  
   Given UpsertAzDoStory.ps1 is called with -Title "Explicit Title" and  
   -Fields @{ "System.Title" = "Fields Title" }  
   When the API PATCH request is built  
   Then the title sent is "Explicit Title"  

5. **Scenario**: Read State from a retrieved work item  
   Given a User Story work item exists in Azure DevOps with State "Under Development"  
   When GetAzDoWorkItem.ps1 retrieves the work item  
   Then the output object contains a State property with value "Under Development"  

6. **Scenario**: Transition a User Story to a writable state  
   Given a User Story work item exists in Azure DevOps with State "New"  
   When UpsertAzDoStory.ps1 is called with -State "Under Development"  
   Then the work item State is updated to "Under Development"  
   And no error is thrown  

7. **Scenario**: Reject transition to a readOnly state  
   Given a User Story work item exists in Azure DevOps  
   When UpsertAzDoStory.ps1 is called with -State "Released"  
   Then the script throws an error containing "readOnly" or "not a writable state"  
   And no API call is made  

#### Extra Information
- The `-Fields` parameter should accept a `[hashtable]` keyed by referenceName.  
- Fields that already have dedicated parameters (Title, Description, State, Tags, StoryPoints,  
  Effort, Priority) should be documented as preferred over `-Fields` for those values.  
- State validation must use the writable states loaded from appSettings.json for the given  
  org/project/work item type (same source as `LoadStateConfiguration.ps1`).  
- Consider adding a `-FieldsFromConfig` switch that pre-populates the `-Fields` parameter list  
  from appSettings.json for discoverability.  

### Story: Update MCP config and template generator for all supported fields (005)
**WorkItemId**: 2617
**State**: Done ✅

**tags**: azDoAutomator, fieldSupport, epicAzDoAutomator  
**Story Points**: 1  
**Priority**: 3  
**Description**  
**As a** developer or AI agent consuming tools via MCP  
**I want** the MCP configuration (mcpConfig.yaml) to expose all writable fields as parameters on the Upsert commands, and the template generator to list all fields from appSettings.json  
**So that** MCP clients can discover and set any supported field, and generated templates document the full field inventory.  

#### Implementation Details  
- Update mcpConfig.yaml: for each Upsert command (upsert-epic, upsert-feature, upsert-story,  
  upsert-bug, upsert-task), add a `Fields` parameter of type `object` (hashtable) that accepts  
  field referenceName/value pairs.  
- Add per-command parameter descriptions listing the writable fields for that work item type  
  (sourced from appSettings.json).  
- Update GenerateAzDoMarkdownHierarchyTemplate.ps1 to read field definitions from  
  appSettings.json and output a complete field reference list in the template comments.  
- Validate that every writable field in appSettings.json has a corresponding mention in the  
  MCP command description for its work item type.  

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ✅ | mcpConfig.yaml upsert-story command includes a Fields parameter of type object | GivenMcpConfig_WhenReadUpsertStory_ItShouldHaveFieldsParameter |  |
| ✅ | mcpConfig.yaml upsert-feature command description mentions AIImplemented, DeployedToDev, FixedIn | GivenMcpConfig_WhenReadUpsertFeatureDescription_* |  |
| ✅ | mcpConfig.yaml upsert-bug command description mentions ReproSteps, SystemInfo, Severity | GivenMcpConfig_WhenReadUpsertBugDescription_* |  |
| ✅ | GenerateAzDoMarkdownHierarchyTemplate.ps1 output lists all writable fields per work item type | GivenTemplate_WhenGenerated_ItShouldListAllWritableFieldsForUserStory |  |
| ✅ | Every writable field in appSettings.json for a work item type is mentioned in the corresponding MCP Upsert command description | GivenTemplate_WhenGenerated_ItShouldListAllWritableFieldsForUserStory |  |

#### AC Scenarios
1. **Scenario**: MCP client discovers writable fields for upsert-story  
   Given mcpConfig.yaml is loaded by an MCP client  
   When the client inspects the upsert-story command definition  
   Then a Fields parameter of type object is present  
   And the description mentions OriginalEstimate, RemainingWork, CompletedWork,  
   AIImplemented, and StoryAcceptanceTests  

2. **Scenario**: Generated template includes all fields from appSettings.json  
   Given appSettings.json defines 20+ fields for User Story  
   When GenerateAzDoMarkdownHierarchyTemplate.ps1 is executed  
   Then the output template contains a reference list of all User Story writable fields  
   And each field shows its label and type  

3. **Scenario**: MCP config field coverage matches appSettings.json  
   Given appSettings.json defines writable fields for Bug including ReproSteps,  
   SystemInfo, Severity, FoundIn  
   When comparing mcpConfig.yaml upsert-bug command description against  
   appSettings.json Bug field definitions  
   Then every writable Bug field is mentioned in the upsert-bug description  

### Story: Support AssignedTo field by email address in all Upsert and Get scripts (006)
**WorkItemId**: TBD  
**State**: New

**tags**: azDoAutomator, fieldSupport, epicAzDoAutomator  
**Story Points**: 2  
**Priority**: 2  
**Description**  
**As a** developer or AI agent managing work items  
**I want** to set and read the AssignedTo field using an email address  
**So that** I can assign work items to team members without needing to know internal Azure DevOps identity descriptors.  

#### Implementation Details  
- Add a `-AssignedTo` string parameter (email address) to all Upsert scripts:  
  `UpsertAzDoEpic.ps1`, `UpsertAzDoFeature.ps1`, `UpsertAzDoStory.ps1`,  
  `UpsertAzDoBug.ps1`, `UpsertAzDoTask.ps1`.  
- Resolve the supplied email to an Azure DevOps identity before building the PATCH payload,  
  using `GET _apis/identities?searchFilter=MailAddress&filterValue={email}&api-version=7.1-preview.1`.  
- Fail fast with a clear error if no matching identity is found for the supplied email.  
- Pass the resolved identity (as `{ "displayName": "...", "uniqueName": "..." }` JSON object)  
  to the `System.AssignedTo` field in the API PATCH payload.  
- Update `GetAzDoWorkItem.ps1`, `GetAzDoUserStory.ps1`, and `GetAzDoBug.ps1` to return  
  `AssignedTo` as an object with at minimum `DisplayName` and `UniqueName` (email) properties.  
- Update mcpConfig.yaml: add an `AssignedTo` parameter (type string, description: email address)  
  to all upsert commands.  
- Tag any test work items created during Pester tests with `testWi` and clean up on teardown.  

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ☐ | UpsertAzDoStory.ps1 -AssignedTo with a valid email address assigns the work item correctly |  |  |
| ☐ | UpsertAzDoFeature.ps1 -AssignedTo with a valid email address assigns the work item correctly |  |  |
| ☐ | UpsertAzDoBug.ps1 -AssignedTo with a valid email address assigns the work item correctly |  |  |
| ☐ | UpsertAzDoTask.ps1 -AssignedTo with a valid email address assigns the work item correctly |  |  |
| ☐ | UpsertAzDoEpic.ps1 -AssignedTo with a valid email address assigns the work item correctly |  |  |
| ☐ | Supplying an unknown email address causes a fail-fast error before any PATCH call |  |  |
| ☐ | GetAzDoWorkItem.ps1 returns an AssignedTo object with DisplayName and UniqueName properties |  |  |
| ☐ | GetAzDoUserStory.ps1 returns AssignedTo with the email as UniqueName |  |  |
| ☐ | GetAzDoBug.ps1 returns AssignedTo with the email as UniqueName |  |  |
| ☐ | mcpConfig.yaml upsert commands include an AssignedTo parameter of type string |  |  |
| ☐ | Existing Upsert calls without -AssignedTo continue to work unchanged |  |  |

#### AC Scenarios
1. **Scenario**: Assign a User Story to a team member by email  
   Given a User Story work item exists in Azure DevOps  
   And the email address "user@example.com" belongs to a valid team member  
   When UpsertAzDoStory.ps1 is called with -AssignedTo "user@example.com"  
   Then the work item's AssignedTo is updated to the identity matching that email  
   And GetAzDoWorkItem.ps1 returns AssignedTo.UniqueName equal to "user@example.com"  

2. **Scenario**: Fail fast when email does not resolve to an identity  
   Given a User Story work item exists in Azure DevOps  
   When UpsertAzDoStory.ps1 is called with -AssignedTo "notfound@example.com"  
   Then the script throws an error containing "not found" or the supplied email  
   And no PATCH API call is made  

3. **Scenario**: Read AssignedTo from a retrieved Feature  
   Given a Feature work item exists in Azure DevOps assigned to "user@example.com"  
   When GetAzDoWorkItem.ps1 retrieves the work item  
   Then the output object contains AssignedTo.UniqueName equal to "user@example.com"  
   And AssignedTo.DisplayName is a non-empty string  

4. **Scenario**: Upsert without -AssignedTo leaves the assigned user unchanged  
   Given a User Story work item is currently assigned to "user@example.com"  
   When UpsertAzDoStory.ps1 is called without the -AssignedTo parameter  
   Then the work item's AssignedTo remains "user@example.com"  

#### Extra Information
- Use the Azure DevOps Identities REST API endpoint for email-to-identity resolution:  
  `GET {org}/_apis/identities?searchFilter=MailAddress&filterValue={email}&api-version=7.1-preview.1`  
- The identity resolution call can be extracted into a shared helper function in `AzDoApiWrapper.ps1`  
  or a new `ResolveAzDoIdentity.ps1` script for reuse across all Upsert scripts.  
- The `System.AssignedTo` PATCH payload value must be the full identity JSON object  
  `{ "displayName": "...", "uniqueName": "..." }`, not just the email string.  
- If the Pester test environment does not have a real assignable user, use the  
  PAT token owner's identity (resolved via `GET {org}/_apis/connectionData`) as the test target.  
