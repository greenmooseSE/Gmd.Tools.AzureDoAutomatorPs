# Epic: Gmd.Tools.AzureDoAutomatorPs

{WorkItemId}: 1577  
{State}: New  

## Feature: Sync AzDo Hierarchy to Plan Markdown

{WorkItemId}: 2858  
{State}: Active  
{tags}: azDoAutomator, epicAzDoAutomator, syncMarkdown  
{Effort}: 5  
{Priority}: 2  
{OriginalEstimate}: 16  
{FixedIn}:  
{DeployedToDev}: false  
{DeployedToStaging}: false  
{DeployedToProduction}: false  
{Description}  
Provide two companion scripts to streamline round-trip plan management between  
Azure DevOps and local plan markdown files:  

- **`ExportAzDoToMarkdown.ps1`** — Exports any Epic, Feature, or Story hierarchy  
  from Azure DevOps to a new plan file on disk, following the standard naming  
  convention (`plan-{id}-{type}{CamelTitle}.md`). Wraps the existing  
  `GetAzDoHierarchyFor{Type}.ps1` + `ConvertHierarchyToMarkdown.ps1` pipeline  
  and eliminates manual file naming and piping.  

- **`SyncMarkdownFromAzDo.ps1`** — Refreshes an existing plan file by fetching  
  the current state of each work item from Azure DevOps and overwriting the  
  local markdown. Items that have a `{WorkItemId}` are updated in-place; items  
  that are missing a `{WorkItemId}` are logged as a warning and skipped (or  
  matched by title when `-MatchExistingByTitle` is supplied). Handles the  
  case where the top-level node has no ID by detecting the parent from its  
  children's work item links.  

### Scope  

The existing `NewAzDoHierarchyFromMarkdown.ps1` already covers the  
**markdown → AzDo** direction. This feature adds the **AzDo → markdown**  
direction and is intentionally kept orthogonal to that script.  

### Stories  

This feature is delivered in two end-to-end stories:  

- **(001)** Create `ExportAzDoToMarkdown.ps1` — export a work item hierarchy  
  to a new plan file with automatic naming.  
- **(002)** Create `SyncMarkdownFromAzDo.ps1` — update an existing plan file  
  from Azure DevOps, with warnings for unmatched items and optional  
  title-based matching.  

### Story: Export AzDo work item hierarchy to a new plan file (001)

{WorkItemId}: 2859  
{State}: RTM  
{tags}: azDoAutomator, epicAzDoAutomator, syncMarkdown  
{Story Points}: 0.75  

#### {Description}

**As a** developer maintaining a project plan  
**I want** to run a single script with a work item ID and have it download the  
full hierarchy and save it as a correctly named plan markdown file  
**So that** I can quickly bootstrap or snapshot a plan without manually composing  
`GetAzDoHierarchyFor*.ps1 | ConvertHierarchyToMarkdown.ps1 | Out-File` pipelines  

#### Script Interface  

**Script:** `src/ExportAzDoToMarkdown.ps1`  

| Parameter | Type | Mandatory | Description |
|---|---|---|---|
| `-WorkItemId` | `[int]` | Yes | ID of the Epic, Feature, or Story to export |
| `-Organization` | `[string]` | No | AzDo org; defaults to env/constants if omitted |
| `-Project` | `[string]` | No | AzDo project; defaults to env/constants if omitted |
| `-Pat` | `[string]` | No | PAT token; auto-retrieved from encrypted env var if omitted |
| `-OutputPath` | `[string]` | No | Full output file path; if omitted, auto-generated (see below) |
| `-Overwrite` | `[switch]` | No | Allow overwriting an existing file; throws if absent and file exists |

**Auto-naming convention** (used when `-OutputPath` is not supplied):  
`docs/plans/plan-{id}-{type}{CamelCaseTitle}.md`  
where `{type}` is `epic`, `feat`, or `story` and `{CamelCaseTitle}` is the  
work item title converted to PascalCase with non-alphanumeric characters removed.  
Example: work item 1577 of type Epic titled `Gmd.Tools.AzureDoAutomatorPs`  
→ `docs/plans/plan-1577-epicGmdToolsAzureDoAutomatorPs.md`  

**Pipeline output:** The resolved output file path as a `[string]`, written to  
the success pipeline so callers can chain further operations.  

#### Scope of Work  

**Step 1 — Detect work item type**  
Call `GetAzDoWorkItem.ps1 -WorkItemId {id}` and read `System.WorkItemType`.  
Supported types: `Epic`, `Feature`, `User Story`. Throw a descriptive error  
for any other type.  

**Step 2 — Fetch the full hierarchy**  
Dispatch to `GetAzDoHierarchyForEpic.ps1`, `GetAzDoHierarchyForFeature.ps1`,  
or `GetAzDoHierarchyForStory.ps1` based on the detected type.  

**Step 3 — Convert to markdown**  
Pipe the hierarchy object to `ConvertHierarchyToMarkdown.ps1` using the same  
`-Organization` and `-Project` parameters.  

**Step 4 — Resolve output path**  
If `-OutputPath` was not provided, build the auto-named path:  
strip non-alphanumeric chars from the title (keep letters and digits),  
PascalCase each word boundary, prepend the type prefix (`epic`/`feat`/`story`),  
and combine with `docs/plans/plan-{id}-{type}{title}.md`.  
If the resolved or provided path already exists and `-Overwrite` is not set,  
throw with message: `"Output file already exists: '{path}'. Use -Overwrite to replace."`.  

**Step 5 — Write file and emit path**  
Write the markdown string to the resolved path using `Set-Content`.  
Emit the resolved path to the pipeline.  

**Step 6 — Add Pester tests**  
Create `test/ExportAzDoToMarkdownTests/ExportAzDoToMarkdownTest.ps1`.  
Cover the scenarios described in the Acceptance Tests section below.  

#### {Acceptance Criteria}

| ✅ | What is Verified | Test(s) | Notes |
|---|---|---|---|
| ✅ | Given work item of type Epic, script calls `GetAzDoHierarchyForEpic.ps1` | Pester — `ExportAzDoToMarkdownTest.ps1` | |
| ✅ | Given work item of type Feature, script calls `GetAzDoHierarchyForFeature.ps1` | Pester — `ExportAzDoToMarkdownTest.ps1` | |
| ✅ | Given work item of type User Story, script calls `GetAzDoHierarchyForStory.ps1` | Pester — `ExportAzDoToMarkdownTest.ps1` | |
| ✅ | Unsupported work item type (e.g. Task) causes the script to throw a descriptive error | Pester — `ExportAzDoToMarkdownTest.ps1` | |
| ✅ | When `-OutputPath` is not supplied, the output file is named `plan-{id}-{type}{CamelTitle}.md` under `docs/plans/` | Pester — `ExportAzDoToMarkdownTest.ps1` | |
| ✅ | When `-OutputPath` is not supplied and title contains dots and spaces, they are stripped and the remainder is PascalCased | Pester — `ExportAzDoToMarkdownTest.ps1` | e.g. `Gmd.Tools AzDo` → `GmdToolsAzDo` |
| ✅ | When target file already exists and `-Overwrite` is not set, the script throws with a message containing the file path | Pester — `ExportAzDoToMarkdownTest.ps1` | |
| ✅ | When target file already exists and `-Overwrite` is set, the script overwrites without error | Pester — `ExportAzDoToMarkdownTest.ps1` | |
| ✅ | Script outputs the resolved file path string to the pipeline | Pester — `ExportAzDoToMarkdownTest.ps1` | |
| ✅ | `README.md` is updated to document `ExportAzDoToMarkdown.ps1` parameters and behavior | Manual verify | |

#### {Acceptance Tests}

- [x] **Scenario 1: Export an Epic hierarchy to a new plan file**  
  Given work item 1577 is of type Epic and titled `Gmd.Tools.AzureDoAutomatorPs`  
  And no `-OutputPath` is supplied  
  And `docs/plans/plan-1577-epicGmdToolsAzureDoAutomatorPs.md` does not exist  
  When `ExportAzDoToMarkdown.ps1 -WorkItemId 1577` is invoked  
  Then `GetAzDoHierarchyForEpic.ps1` is called with `-EpicId 1577`  
  And `ConvertHierarchyToMarkdown.ps1` is called with the returned hierarchy  
  And the output file `docs/plans/plan-1577-epicGmdToolsAzureDoAutomatorPs.md` is created  
  And the script outputs the path `docs/plans/plan-1577-epicGmdToolsAzureDoAutomatorPs.md`  

- [x] **Scenario 2: Export a Feature hierarchy using an explicit output path**  
  Given work item 2000 is of type Feature  
  And `-OutputPath "C:/tmp/my-plan.md"` is supplied  
  When `ExportAzDoToMarkdown.ps1 -WorkItemId 2000 -OutputPath "C:/tmp/my-plan.md"` is invoked  
  Then `GetAzDoHierarchyForFeature.ps1` is called with `-FeatureId 2000`  
  And the file `C:/tmp/my-plan.md` is created with the converted markdown  
  And the script outputs the path `C:/tmp/my-plan.md`  

- [x] **Scenario 3: Existing file blocks export without -Overwrite**  
  Given `docs/plans/plan-1577-epicGmdToolsAzureDoAutomatorPs.md` already exists  
  And `-Overwrite` is not supplied  
  When `ExportAzDoToMarkdown.ps1 -WorkItemId 1577` is invoked  
  Then the script throws an error containing the existing file path  
  And the existing file is not modified  

- [x] **Scenario 4: Unsupported work item type throws a descriptive error**  
  Given work item 9999 is of type Task  
  When `ExportAzDoToMarkdown.ps1 -WorkItemId 9999` is invoked  
  Then the script throws an error containing the unsupported type name `"Task"`  

### Story: Sync existing plan markdown file from Azure DevOps (002)

{WorkItemId}: 2860  
{State}: RTM  
{tags}: azDoAutomator, epicAzDoAutomator, syncMarkdown  
{Story Points}: 2  

#### {Description}

**As a** developer with an existing plan file that may be partially out of date  
**I want** to run a sync script against that file so that every work item that has  
a `{WorkItemId}` is refreshed with the latest state from Azure DevOps  
**So that** my local plan reflects the current titles, states, story points, and  
field values without having to re-export and lose any in-progress additions  

#### Script Interface  

**Script:** `src/SyncMarkdownFromAzDo.ps1`  

| Parameter | Type | Mandatory | Description |
|---|---|---|---|
| `-PlanFilePath` | `[string]` | Yes | Path to the existing plan markdown file to sync |
| `-Organization` | `[string]` | No | AzDo org; defaults to env/constants if omitted |
| `-Project` | `[string]` | No | AzDo project; defaults to env/constants if omitted |
| `-Pat` | `[string]` | No | PAT token; auto-retrieved from encrypted env var if omitted |
| `-MatchExistingByTitle` | `[switch]` | No | When set, items without a `{WorkItemId}` are matched against the fetched AzDo hierarchy by title (case-insensitive, scoped to parent container) |

**Pipeline output:** The resolved `PlanFilePath` as a `[string]`, confirming the  
file that was updated.  

#### Scope of Work  

**Step 1 — Parse the existing plan**  
Call `ConvertMarkdownToHierarchyJson.ps1 -MarkdownContent (Get-Content -Raw)` to  
obtain the structured hierarchy. Read the `{WorkItemId}` from the top-level node.  

**Step 2 — Resolve the top-level work item ID**  
Three cases, evaluated in order:  

- **Case A — Top-level node has a WorkItemId:** Use it directly to fetch the  
  full hierarchy from AzDo via `GetAzDoHierarchyForEpic/Feature/Story.ps1`.  

- **Case B — Top-level node has no WorkItemId but at least one child has one:**  
  Fetch the first child's work item from AzDo and traverse its parent link  
  (`System.LinkTypes.Hierarchy-Reverse`) to resolve the parent ID. Log a warning:  
  `"Top-level node '{title}' has no WorkItemId — parent ID {parentId} detected from child {childId}."`.  
  Use the detected parent ID to fetch the full hierarchy.  

- **Case C — No WorkItemId found anywhere in the plan:**  
  Throw with message: `"Cannot sync: no WorkItemId found in plan file. At least one work item must have a {WorkItemId} to anchor the sync."`.  

**Step 3 — Merge plan items with fetched AzDo hierarchy**  
For each item in the parsed plan:  

- **Has a WorkItemId:** Locate the matching item in the fetched AzDo hierarchy  
  and replace the plan item's fields with AzDo values.  
  If the ID is not found in the fetched hierarchy log a warning:  
  `"Work item {id} ('{title}') was not found in the fetched hierarchy and will be skipped."`.  

- **No WorkItemId, `-MatchExistingByTitle` not set:** Log a warning:  
  `"Item '{title}' has no WorkItemId and will be skipped. Use -MatchExistingByTitle to attempt a title-based match."`.  

- **No WorkItemId, `-MatchExistingByTitle` set:** Search for a work item with  
  the same title (case-insensitive) within the same parent container in the  
  fetched AzDo hierarchy. If found, log an info message with the matched ID  
  and update the plan item including setting its `{WorkItemId}`.  
  If not found, log a warning: `"No title match found for '{title}' within parent '{parentTitle}'."`.  

**Step 4 — Regenerate and write the updated markdown**  
Call `ConvertHierarchyToMarkdown.ps1` on the merged hierarchy object to produce  
the updated markdown string. Overwrite the original plan file with `Set-Content`.  

**Step 5 — Emit the file path**  
Output the resolved `PlanFilePath` to the pipeline.  

**Step 6 — Add Pester tests**  
Create `test/SyncMarkdownFromAzDoTests/SyncMarkdownFromAzDoTest.ps1`.  
Cover the scenarios described in the Acceptance Tests section below.  

#### {Acceptance Criteria}

| ✅ | What is Verified | Test(s) | Notes |
|---|---|---|---|
| ✅ | Items with a `{WorkItemId}` in the plan are updated with values fetched from AzDo | Pester — `SyncMarkdownFromAzDoTest.ps1` | |
| ✅ | An item with a `{WorkItemId}` not present in the fetched hierarchy logs a warning containing the work item ID | Pester — `SyncMarkdownFromAzDoTest.ps1` | |
| ✅ | Items without a `{WorkItemId}` and without `-MatchExistingByTitle` produce a warning log containing the item title | Pester — `SyncMarkdownFromAzDoTest.ps1` | |
| ✅ | With `-MatchExistingByTitle`, an item without a `{WorkItemId}` whose title matches a sibling in AzDo gets its `{WorkItemId}` populated | Pester — `SyncMarkdownFromAzDoTest.ps1` | Match is scoped to the same parent container |
| ✅ | With `-MatchExistingByTitle`, an item whose title matches nothing in the same container logs a warning containing the unmatched title | Pester — `SyncMarkdownFromAzDoTest.ps1` | |
| ✅ | When top-level node has no `{WorkItemId}` but a child has one, the parent ID is auto-detected from the child's parent link, and a warning is logged | Pester — `SyncMarkdownFromAzDoTest.ps1` | |
| ✅ | When no `{WorkItemId}` exists anywhere in the plan the script throws with a message indicating the anchor requirement | Pester — `SyncMarkdownFromAzDoTest.ps1` | |
| ✅ | The plan file is overwritten with the updated markdown after a successful sync | Pester — `SyncMarkdownFromAzDoTest.ps1` | |
| ✅ | Script outputs the resolved plan file path to the pipeline | Pester — `SyncMarkdownFromAzDoTest.ps1` | |
| ✅ | `README.md` is updated to document `SyncMarkdownFromAzDo.ps1` parameters and behavior | Manual verify | |

#### {Acceptance Tests}

- [x] **Scenario 1: Items with WorkItemIds are refreshed from AzDo**  
  Given a plan file where the top-level Epic has `{WorkItemId}: 1577`  
  And the plan contains two stories — one with `{WorkItemId}: 100` and one without  
  When `SyncMarkdownFromAzDo.ps1 -PlanFilePath "plan.md"` is invoked  
  Then the story with ID 100 has its fields updated to match the current AzDo values  
  And a warning is logged for the story without a `{WorkItemId}`  
  And the plan file is overwritten with the refreshed content  

- [x] **Scenario 2: Top-level node ID is detected from a child**  
  Given a plan file where the top-level Epic has no `{WorkItemId}`  
  And the plan contains a story with `{WorkItemId}: 200`  
  And work item 200 has a parent link pointing to Epic ID 1577  
  When `SyncMarkdownFromAzDo.ps1 -PlanFilePath "plan.md"` is invoked  
  Then a warning is logged containing `"parent ID 1577 detected from child 200"`  
  And the full Epic hierarchy is fetched using ID 1577  
  And the plan file is overwritten with the refreshed content  

- [x] **Scenario 3: No WorkItemId anywhere throws an error**  
  Given a plan file with no `{WorkItemId}` on any work item  
  When `SyncMarkdownFromAzDo.ps1 -PlanFilePath "plan.md"` is invoked  
  Then the script throws an error whose message contains `"no WorkItemId found in plan file"`  
  And the plan file is not modified  

- [x] **Scenario 4: -MatchExistingByTitle fills in WorkItemId for matching item**  
  Given a plan file with Epic `{WorkItemId}: 1577`  
  And a story titled `"My Feature Story"` with no `{WorkItemId}`  
  And the AzDo hierarchy for Epic 1577 contains a story with the same title and ID 300  
  When `SyncMarkdownFromAzDo.ps1 -PlanFilePath "plan.md" -MatchExistingByTitle` is invoked  
  Then the story in the refreshed plan file has `{WorkItemId}: 300`  
  And no warning about a missing ID is emitted for that story  

- [x] **Scenario 5: -MatchExistingByTitle logs warning for unmatched title**  
  Given a plan file with Epic `{WorkItemId}: 1577`  
  And a story titled `"Nonexistent Story"` with no `{WorkItemId}`  
  And no story with that title exists under Epic 1577 in AzDo  
  When `SyncMarkdownFromAzDo.ps1 -PlanFilePath "plan.md" -MatchExistingByTitle` is invoked  
  Then a warning is logged containing `"No title match found for 'Nonexistent Story'"`  
  And the story item in the output has no `{WorkItemId}`  

