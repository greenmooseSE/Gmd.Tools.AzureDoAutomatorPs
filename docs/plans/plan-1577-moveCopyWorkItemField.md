# Epic: Gmd.Tools.AzureDoAutomatorPs
{WorkItemId}: 1577
{State}: New
{tags}: azDoAutomator, automation, azdo, crudOperations, mcpServer
{Effort}: 79
{Description}
Complete build-out of Azure DevOps work item automation tooling to support full CRUD operations on  
Epics, Features, User Stories, Bugs, and Tasks. Implement comprehensive comment management with  
reaction support, tag management, and hierarchical retrieval with all associated metadata. Operations  
are consolidated into Upsert* scripts with -FailIfExist switch for create/update unification.  
Culminate in MCP (Model Context Protocol) server integration to expose all operations as standardized  
tools for AI assistants and automation frameworks.  

## Feature: Move/Copy Work Item Field Values
{WorkItemId}: 2619
{State}: New
{tags}: azDoAutomator, fieldMgmt, epicAzDoAutomator
{Effort}: 5
{Priority}: 2
### {Feature Acceptance Tests}
- [ ] **Test 1: Move field value within a feature hierarchy (WorkItemId scope)**  
  1. Pick a Feature in AzDo that has 2–3 child stories.  
  2. Ensure at least 2 stories have a non-empty "Extra Information" field and at least 1 has it empty.  
  3. Run: `.\src\MoveAzDoWorkItemField.ps1 -WorkItemId {featureId} -SourceField "Extra Information" -TargetField "Story Acceptance Tests"`  
  4. Open the updated stories in AzDo — verify "Story Acceptance Tests" now contains the original "Extra Information" text.  
  5. Verify "Extra Information" is cleared on the same stories.  
  6. Verify the story with the empty "Extra Information" was not modified.  
  7. Verify the console summary reports: 2 updated, 1 skipped.  

- [ ] **Test 2: Copy field value preserves source (WorkItemId scope)**  
  1. Pick a User Story with a non-empty "Extra Information" field.  
  2. Run: `.\src\MoveAzDoWorkItemField.ps1 -WorkItemId {storyId} -SourceField "Extra Information" -TargetField "Story Acceptance Tests" -Copy`  
  3. Open the story in AzDo — verify "Story Acceptance Tests" contains the copied text.  
  4. Verify "Extra Information" still contains the original text (not cleared).  

- [ ] **Test 3: DryRun shows impact without making changes (WorkItemId scope)**  
  1. Pick a Feature with 2+ stories that have a non-empty source field.  
  2. Run: `.\src\MoveAzDoWorkItemField.ps1 -WorkItemId {featureId} -SourceField "Extra Information" -TargetField "Story Acceptance Tests" -DryRun`  
  3. Verify the console output lists the items that would be updated.  
  4. Open those work items in AzDo — verify no fields were changed.  

- [ ] **Test 4: ConfirmEachItem pauses and respects decline**  
  1. Pick a Feature with 2 stories that have non-empty source field.  
  2. Run with `-ConfirmEachItem`: `.\src\MoveAzDoWorkItemField.ps1 -WorkItemId {featureId} -SourceField "Extra Information" -TargetField "Story Acceptance Tests" -ConfirmEachItem`  
  3. For the first story prompt, enter "Y" to confirm.  
  4. For the second story prompt, enter "N" to decline.  
  5. Verify the first story was updated in AzDo and the second was not modified.  
  6. Verify the summary shows 1 updated, 1 declined.  

- [ ] **Test 5: Global scope with DryRun shows project-wide impact**  
  1. Run: `.\src\MoveAzDoWorkItemField.ps1 -Global -SourceField "Extra Information" -TargetField "Story Acceptance Tests" -DryRun`  
  2. Verify the console output lists all work items that would be updated.  
  3. Verify items of types that do not have "Extra Information" (e.g., Task) appear as skipped.  
  4. Open several of the listed work items in AzDo — verify no fields were changed.  
  5. Verify the summary reports a total count, updated count, and skipped count.  

- [ ] **Test 6: Global scope performs project-wide move**  
  1. Set up 2 stories in AzDo with a known value in "Extra Information".  
  2. Run: `.\src\MoveAzDoWorkItemField.ps1 -Global -SourceField "Extra Information" -TargetField "Story Acceptance Tests"`  
  3. Verify the 2 prepared stories have "Story Acceptance Tests" updated and "Extra Information" cleared.  
  4. Verify no other work items were unexpectedly modified.  

- [ ] **Test 7: Invalid field label produces a clear error**  
  1. Run: `.\src\MoveAzDoWorkItemField.ps1 -WorkItemId {storyId} -SourceField "NonExistentField" -TargetField "Story Acceptance Tests"`  
  2. Verify the script terminates with a clear error message identifying "NonExistentField" as invalid.  
  3. Verify no work items were modified.  

### {Description}
Add a new PowerShell script `MoveAzDoWorkItemField.ps1` that moves or copies the value of one  
field to another field across a set of Azure DevOps work items. The script supports two scoping  
modes: by WorkItemId (processes the specified item and all its hierarchical descendants) or Global  
(processes every work item in the project, including closed items).  

### Key Capabilities  
- **Move** (default): copies the source field value to the target field, then clears the source field.  
- **Copy** (`-Copy` switch): copies the source field value to the target field without clearing the source.  
- **Dry run** (`-DryRun` switch): previews the impact — shows which items would be updated and how many — without making any API changes.  
- **Per-item confirmation** (`-ConfirmEachItem` switch): pauses before each operation (including in DryRun mode) so the operator can sanity-check individual items before committing to a full batch.  
- **Field-type awareness**: resolves field labels to API reference names via `LoadFieldConfiguration.ps1` and skips items where the source field does not exist on the work item type.  
- **Summary output**: after completion, logs a summary showing total items evaluated, items updated, items skipped (empty source or field not applicable), and errors.  

### Design Notes  
- Reuses existing infrastructure: `AzDoApiWrapper.ps1` (`Invoke-AzDoWiql`, `Invoke-AzDoApiRequest`),  
  `LoadFieldConfiguration.ps1`, `GetAzDoWorkItem.ps1`, `GetAzDoHierarchyForEpic.ps1`,  
  `GetAzDoHierarchyForFeature.ps1`, `GetAzDoHierarchyForStory.ps1`.  
- Field resolution is driven by `appSettings.json` — both source and target must be valid,  
  non-readOnly field labels for the given work item type.  
- Pipeline output emits one PSObject per processed item (properties: WorkItemId, Title,  
  WorkItemType, SourceField, TargetField, Action, Result) so downstream tooling can filter or  
  aggregate results.  

### Story: Implement MoveAzDoWorkItemField.ps1 with WorkItemId scope (001) ✅
{WorkItemId}: 2620
{State}: Done
{tags}: azDoAutomator, fieldMgmt, epicAzDoAutomator
{Story Points}: 2
{Story Acceptance Tests}
- [ ] **Scenario 1: Move field value for a single work item**  
  Given a User Story with a non-empty "Extra Information" field  
  When `MoveAzDoWorkItemField.ps1 -WorkItemId {storyId} -SourceField "Extra Information" -TargetField "Story Acceptance Tests"` is run  
  Then the Story Acceptance Tests field contains the original Extra Information value  
  And the Extra Information field is cleared  
  And the pipeline output shows Action = "Move" and Result = "Updated"  

- [ ] **Scenario 2: Copy field value preserves source**  
  Given a User Story with a non-empty "Extra Information" field with value "test content"  
  When `-Copy` is specified  
  Then the Story Acceptance Tests field contains "test content"  
  And the Extra Information field still contains "test content"  
  And the pipeline output shows Action = "Copy" and Result = "Updated"  

- [ ] **Scenario 3: Empty source field is skipped**  
  Given a User Story where "Extra Information" is empty  
  When `MoveAzDoWorkItemField.ps1` is run with SourceField "Extra Information"  
  Then no PATCH request is made for this item  
  And the pipeline output shows Action = "Skip" and Result = "Skipped"  
  And Detail contains "Source field is empty"  

- [ ] **Scenario 4: Feature hierarchy processes all descendants**  
  Given a Feature (ID = {featureId}) with 3 child stories (2 have non-empty source, 1 empty)  
  When `-WorkItemId {featureId}` is specified  
  Then the feature itself and all 3 stories are evaluated  
  And 2 items show Result = "Updated" and 1 shows Result = "Skipped"  
  And the summary log reports: total = 4, updated = 2, skipped = 2  

- [ ] **Scenario 5: DryRun previews without changes**  
  Given a User Story with a non-empty source field  
  When `-DryRun` is specified  
  Then no API PATCH is made  
  And the pipeline output shows Action = "DryRun" and Result = "Updated"  

- [ ] **Scenario 6: ConfirmEachItem declined skips the item**  
  Given a User Story with a non-empty source field  
  When `-ConfirmEachItem` is specified and the user inputs "N"  
  Then no PATCH is made for that item  
  And the pipeline output shows Result = "Declined"  

- [ ] **Scenario 7: Source field not available on work item type is skipped**  
  Given an Epic work item  
  When SourceField is "AC Scenarios" (which does not exist on Epic type)  
  Then the Epic is skipped  
  And Detail contains "Source field not available on Epic"  

- [ ] **Scenario 8: Invalid field label throws terminating error**  
  Given SourceField = "NonExistentFieldLabel"  
  When the script is invoked  
  Then a terminating error is thrown before any work items are processed  
  And the error message identifies the invalid field label  

{Description}
**As a** DevOps engineer or AI agent  
**I want** a script that moves or copies a field value from one field to another for a specified  
work item and all its hierarchical descendants  
**So that** I can migrate or restructure field data across work items in batch without manual editing.  

#### Script Interface  
**File**: `src/MoveAzDoWorkItemField.ps1`  

| Parameter | Type | Mandatory | ParameterSet | Description |  
|-----------|------|-----------|--------------|-------------|  
| Organization | string | No (env var fallback) | Both | Azure DevOps organization name |  
| Project | string | No (env var fallback) | Both | Azure DevOps project name |  
| PatToken | string | No (env var fallback) | Both | PAT token for authentication |  
| SourceField | string | Yes | Both | Field label as defined in appSettings.json |  
| TargetField | string | Yes | Both | Field label as defined in appSettings.json |  
| WorkItemId | int | Yes | ById | Root work item ID; processes this item and all descendants |  
| Copy | switch | No | Both | Copies value without clearing the source field |  
| DryRun | switch | No | Both | Previews operations without making API changes |  
| ConfirmEachItem | switch | No | Both | Prompts Y/N before each operation |  

#### Pipeline Output  
Each processed item emits a PSObject with these properties:  

| Property | Type | Description |  
|----------|------|-------------|  
| WorkItemId | int | The work item ID |  
| Title | string | Work item title |  
| WorkItemType | string | Epic, Feature, User Story, Bug, or Task |  
| SourceField | string | Source field label |  
| TargetField | string | Target field label |  
| Action | string | Move, Copy, Skip, or DryRun |  
| Result | string | Updated, Skipped, Declined, or Error |  
| Detail | string | Reason for skip or error message |  

#### Hierarchy Resolution Logic  
- Determines the root work item type via `GetAzDoWorkItem.ps1`.  
- Epic → calls `GetAzDoHierarchyForEpic.ps1` and flattens all descendants (features, stories, tasks, bugs).  
- Feature → calls `GetAzDoHierarchyForFeature.ps1` and flattens all descendants (stories, tasks, bugs).  
- User Story → calls `GetAzDoHierarchyForStory.ps1` and flattens descendants (tasks, bugs).  
- Bug or Task → processes only that single item.  

#### Field Resolution  
- Uses `LoadFieldConfiguration.ps1` per work item type to resolve label → `referenceName`.  
- If the source field label does not exist on the item's type, the item is skipped with  
  Result = "Skipped" and Detail = "Source field not available on {type}".  
- If the target field is readOnly on the item's type, the item is skipped with  
  Detail = "Target field is readOnly on {type}".  

#### Move vs Copy  
- **Move** (default): PATCH the work item with two operations — set target field to source value,  
  set source field to empty string.  
- **Copy** (`-Copy`): PATCH with one operation — set target field to source value.  

{Acceptance Criteria}
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ▢ | Source field label is resolved to API referenceName via LoadFieldConfiguration.ps1 | | |
| ▢ | Target field label is resolved to API referenceName via LoadFieldConfiguration.ps1 | | |
| ▢ | When source field value is empty/null on a work item, the item is skipped | | |
| ▢ | When source field does not exist on the work item type, the item is skipped | | |
| ▢ | When target field is readOnly on the work item type, the item is skipped | | |
| ▢ | Move operation writes source value to target and clears source field via a single PATCH | | |
| ▢ | Copy operation writes source value to target and leaves source field unchanged | | |
| ▢ | When -DryRun is specified, no API PATCH calls are made | | |
| ▢ | When -ConfirmEachItem is specified and user declines, the item is skipped with Result "Declined" | | |
| ▢ | When -WorkItemId points to a feature, all descendant stories/tasks/bugs are also processed | | |
| ▢ | Pipeline output contains one PSObject per processed item with all documented properties | | |
| ▢ | Summary log line shows counts: total items, updated, skipped, errors | | |
| ▢ | Invalid SourceField or TargetField label throws a terminating error | | |
| ▢ | README.md is updated to reflect this story's changes | | |

{Extra Information}
- Use the same PAT token resolution pattern as other scripts (`AzDoPatTokenHelper.ps1`).  
- The PATCH endpoint is `PATCH https://dev.azure.com/{org}/{project}/_apis/wit/workitems/{id}?api-version=7.1`  
  with Content-Type `application/json-patch+json`.  
- For `-ConfirmEachItem`, use `$Host.UI.PromptForChoice` or `Read-Host` with a clear prompt  
  showing the work item ID, title, source value preview (truncated to 80 chars), and the action  
  (Move/Copy).  
- Pester test file: `test/MoveAzDoWorkItemFieldTests/MoveAzDoWorkItemFieldTest.ps1`  

### Story: Add Global scope to MoveAzDoWorkItemField.ps1 (002) ✅
{WorkItemId}: 2621
{State}: Done
{tags}: azDoAutomator, fieldMgmt, epicAzDoAutomator
{Story Points}: 1
{Story Acceptance Tests}
- [ ] **Scenario 1: Global scope processes all project work items**  
  Given a project with work items of types Epic, Feature, User Story, Bug, and Task  
  When `-Global -SourceField "Extra Information" -TargetField "Description"` is run  
  Then every work item in the project is evaluated  
  And items where "Extra Information" does not exist on the type (e.g., Task) are skipped  
  And items with non-empty source are updated  
  And the summary reflects correct counts  

- [ ] **Scenario 2: Global with DryRun makes no changes**  
  Given a project with 20 work items, 5 with non-empty source field  
  When `-Global -DryRun` is specified  
  Then 0 API PATCH requests are made  
  And the summary reports 5 items that would be updated and 15 skipped  

- [ ] **Scenario 3: Mutually exclusive parameter sets**  
  Given both `-Global` and `-WorkItemId 123` are specified  
  When the script is invoked  
  Then PowerShell throws a parameter binding error before any processing begins  

- [ ] **Scenario 4: Progress logging during large batch**  
  Given a project with 100 work items  
  When `-Global` is specified  
  Then progress messages are logged at items 25, 50, 75, and 100  

{Description}
**As a** DevOps engineer or AI agent  
**I want** a `-Global` switch on `MoveAzDoWorkItemField.ps1` that processes all work items  
in the project including closed items  
**So that** I can perform project-wide field migrations without specifying individual work item IDs.  

#### Script Interface Changes  
Adds a new parameter and ParameterSet:  

| Parameter | Type | Mandatory | ParameterSet | Description |  
|-----------|------|-----------|--------------|-------------|  
| Global | switch | Yes | Global | Queries all work items in the project via WIQL |  

`-Global` and `-WorkItemId` are mutually exclusive via ParameterSet definitions.  

#### WIQL Query  
The WIQL query retrieves all work items in the project regardless of state:  
```
SELECT [System.Id], [System.WorkItemType]
FROM WorkItems
WHERE [System.TeamProject] = @project
ORDER BY [System.Id] ASC
```

#### Batch Processing  
- Iterates each work item ID returned by the WIQL query.  
- For each item, determines its work item type and checks if SourceField exists on that type.  
- Applies the same move/copy logic as in Story 001.  
- Logs progress every 25 items: `"Processing {current}/{total}..."` via ssLogIt.ps1 at Debug level.  
- Emits one PSObject per item to the pipeline (same shape as Story 001).  
- Logs final summary at Info level:  
  `"✅ Global field {action} complete: {total} items evaluated, {updated} updated, {skipped} skipped, {errors} errors"`  

{Acceptance Criteria}
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ▢ | -Global switch is mutually exclusive with -WorkItemId | | |
| ▢ | WIQL query returns all work items in the project including closed/resolved states | | |
| ▢ | Items where source field does not exist on the work item type are skipped | | |
| ▢ | Progress is logged every 25 items during processing | | |
| ▢ | Final summary log includes total, updated, skipped, and error counts | | |
| ▢ | Pipeline output contains one PSObject per evaluated item | | |
| ▢ | -DryRun combined with -Global previews all items without API changes | | |
| ▢ | -ConfirmEachItem combined with -Global prompts before each item | | |
| ▢ | README.md is updated to reflect this story's changes | | |

{Extra Information}
- The `Invoke-AzDoWiql` function in `AzDoApiWrapper.ps1` already supports WIQL queries  
  and should be used for the global query.  
- Consider API rate limits: the Azure DevOps REST API throttles at ~200 requests/minute  
  for PAT-based auth. For very large projects, the script may need to pace itself.  
  This is acceptable as a known limitation for MVP — document it in README.  
- Pester test file: `test/MoveAzDoWorkItemFieldTests/GlobalScopeTest.ps1`  
