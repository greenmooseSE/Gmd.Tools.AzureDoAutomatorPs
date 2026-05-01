# Epic: Gmd.Tools.AzureDoAutomatorPs

{WorkItemId}: 1577  
{State}: New  

## Feature: Relational Link Fields Support in Plan Markdown
{WorkItemId}: 2747
{State}: New

{tags}: azDoAutomator, epicAzDoAutomator, relationalLinks  
{Effort}: 8  
{Priority}: 2  
{OriginalEstimate}: 16  
{FixedIn}:  
{DeployedToDev}: false  
{DeployedToStaging}: false  
{DeployedToProduction}: false  
{Description}  
Enable authoring, applying, and exporting relational work item link fields directly  
from plan markdown files. The five supported link types are:  

| Markdown field | AzDo link type | Relationship |
|---|---|---|
| `{Predecessor}` | `Microsoft.VSTS.Common.Predecessor` (Reverse) | This item depends on the linked item(s) |
| `{Successor}` | `Microsoft.VSTS.Common.Predecessor` (Forward) | The linked item(s) depend on this item |
| `{Related}` | `System.LinkTypes.Related` | Bidirectional relationship |
| `{Duplicate}` | `System.LinkTypes.Duplicate` (Reverse) | The linked item(s) are duplicates of this item |
| `{DuplicateOf}` | `System.LinkTypes.Duplicate` (Forward) | This item is a duplicate of the linked item(s) |

### Markdown Format  

Each field holds a comma-separated list of work item IDs.  
An optional quoted title may follow each ID for human readability — it is  
metadata only and is **ignored** when applying the plan to Azure DevOps:  

```
{Related}: 123 "Fetch user profile story", 456
{Predecessor}: 789
{DuplicateOf}: 1000 "Original story"
```

### Parent and Child Links  

Parent and Child links are **not** included as explicit relational fields.  
The markdown hierarchy structure (header nesting) already encodes parent-child  
relationships unambiguously. Duplicating them as fields would create ambiguity  
and potential conflict during apply.  

### Link Diffing and Staleness  

When a plan is applied, the set of IDs in each link field is treated as the  
desired state. If an ID present in Azure DevOps is absent from the markdown,  
that link is removed. This is consistent with how scalar fields are treated.  
The Stale Markdown Guard (Feature 2722) applies to link fields as well.  

### Summary Table  

A new `Links` column is added to the `NewAzDoHierarchyFromMarkdown.ps1`  
summary table, showing `+n/-n` for added/removed links per work item.  
A work item with only link changes (no scalar field changes) reports  
status `Update`, not `NoChange`, to ensure changes are visible.  

### Stories  

This feature is delivered in two end-to-end stories:  

- **(001)** Parse link fields from plan markdown and apply them to Azure DevOps,  
  including the summary table `Links` column update.  
- **(002)** Export relational links when reading a hierarchy from Azure DevOps  
  back to markdown, including link titles for human readability.  

### Story: Parse and apply relational link fields from plan markdown (001)
{WorkItemId}: 2748
{State}: New

{tags}: azDoAutomator, epicAzDoAutomator, relationalLinks  
{Story Points}: 3  

#### {Description}

**As a** developer authoring a plan markdown file  
**I want** to specify `{Predecessor}`, `{Successor}`, `{Related}`, `{Duplicate}`,  
and `{DuplicateOf}` fields on any work item in the plan  
**So that** those relational links are created, updated, or removed in Azure DevOps  
when the plan is applied with `NewAzDoHierarchyFromMarkdown.ps1`  

#### Scope of Work  

**Step 1 — Define link field types in `appSettings.json`**  
Add entries for the five link fields to all relevant work item type arrays  
(Epic, Feature, User Story, Bug) with `"type": "linkSet"` and the AzDo  
reference name / direction as metadata. Example entry:  

```json
{
  "referenceName": "Microsoft.VSTS.Common.Predecessor-Reverse",
  "label": "Predecessor",
  "description": "IDs of work items that must be completed before this item.",
  "type": "linkSet",
  "direction": "Reverse",
  "linkTypeFamily": "Microsoft.VSTS.Common.Predecessor",
  "readOnly": false
}
```

The `linkSet` type signals to the parser and applier that this field holds  
a list of work item IDs rather than a scalar value.  

**Step 2 — Parse link fields in `ConvertMarkdownToHierarchyJson.ps1`**  
For any field with `"type": "linkSet"`, parse the value as a comma-separated  
list of entries, each with the form `<id>` or `<id> "title"`.  
Store the result in `$item.linkFields` as an array of objects:  
`@{ id = 123; title = "optional title or empty" }`.  
Title is stored for round-trip fidelity only — it must not influence apply.  

**Step 3 — Add `Set-AzDoWorkItemRelations` to `AzDoApiWrapper.ps1`**  
Implement a function that accepts:  
- `Organization`, `Project`, `PatToken`  
- `WorkItemId` — the target work item  
- `AddRelations` — array of `@{ rel = "...; url = "..." }` objects to add  
- `RemoveRelations` — array of existing relation objects to remove  

The function builds a JSON Patch document with `add` and `remove` operations  
against `/relations/-` or the specific relation index, and calls  
`PATCH https://dev.azure.com/{org}/{proj}/_apis/wit/workitems/{id}?api-version=7.1`.  

**Step 4 — Apply link changes in `NewAzDoHierarchyFromMarkdown.ps1`**  
After applying scalar fields for each work item:  
- Fetch the current relations from the live AzDo work item.  
- For each `linkSet` field, compute the desired set of IDs from the parsed plan.  
- Diff desired vs current: IDs present in desired but not in AzDo → add;  
  IDs present in AzDo but not in desired → remove.  
- Call `Set-AzDoWorkItemRelations` with the add/remove lists.  
- Track link changes in a per-item `linksAdded` / `linksRemoved` counter.  

**Step 5 — Update summary table with `Links` column**  
In `Write-PlainTextSummary`, add a `Links` column after `NoChange`.  
Display `+n/-n` where `n` is the count of added/removed links.  
If a work item has link changes but no scalar field changes, force its  
status to `Update` (not `NoChange`).  
A `Links` value of `+0/-0` displays as `-` for visual clarity.  

**Step 6 — Update `example-hierarchy.md`**  
Add a `### Story:` example demonstrating all five link fields, including  
entries with and without optional titles.  

**Step 7 — Add Pester tests**  
Cover the scenarios described in the AC Scenarios section below.  

#### {Acceptance Criteria}

| ✅ | What is Verified | Test(s) | Notes |
|---|---|---|---|
| ▢ | `appSettings.json` contains `linkSet` entries for all 5 link fields on all applicable work item types | Pester — parse appSettings | |
| ▢ | `ConvertMarkdownToHierarchyJson.ps1` parses `{Related}: 123 "title", 456` into `$item.linkFields['Related']` with two entries | Pester | Title stored, not applied |
| ▢ | `ConvertMarkdownToHierarchyJson.ps1` parses `{Predecessor}: 789` into `$item.linkFields['Predecessor']` with one entry and empty title | Pester | |
| ▢ | `ConvertMarkdownToHierarchyJson.ps1` treats `{DuplicateOf}: 100 "title"` title as metadata — `id` is 100 and `title` is "title" | Pester | |
| ▢ | `Set-AzDoWorkItemRelations` issues a PATCH request that adds a `System.LinkTypes.Related` relation when a Related link is new | Pester with mock API | |
| ▢ | `Set-AzDoWorkItemRelations` issues a PATCH request that removes a relation when an ID is absent from the markdown | Pester with mock API | |
| ▢ | `NewAzDoHierarchyFromMarkdown.ps1 -DryRun` shows planned link additions and removals without calling the API | Pester / DryRun inspection | |
| ▢ | A work item with only link changes (no field changes) reports status `Update` in the summary, not `NoChange` | Pester — summary output check | |
| ▢ | Summary table `Links` column shows `+1/-0` when one link is added and none removed | Pester — summary output check | |
| ▢ | Summary table `Links` column shows `-` when no link changes occur | Pester — summary output check | |
| ▢ | `example-hierarchy.md` includes a `### Story:` example with all five link fields | Manual verify | |
| ▢ | `README.md` is updated to reflect this story's changes | Manual verify | |

#### {Acceptance Tests}

- [ ] **Scenario 1: Related links are parsed and applied**  
  Given a plan markdown with `{Related}: 123, 456` on a Story  
  And the story has no current Related links in AzDo  
  When `NewAzDoHierarchyFromMarkdown.ps1` runs (non-DryRun)  
  Then `Set-AzDoWorkItemRelations` is called with `AddRelations` containing  
  two `System.LinkTypes.Related` entries pointing to IDs 123 and 456  
  And no `RemoveRelations` entries are sent  

- [ ] **Scenario 2: Removed Related link triggers relation removal**  
  Given a plan markdown with `{Related}: 123` on a Story  
  And the story currently has Related links to IDs 123 and 456 in AzDo  
  When `NewAzDoHierarchyFromMarkdown.ps1` runs (non-DryRun)  
  Then `Set-AzDoWorkItemRelations` is called with `RemoveRelations` containing  
  one entry for ID 456  
  And `AddRelations` is empty  

- [ ] **Scenario 3: Predecessor link maps to correct AzDo relation type**  
  Given a plan markdown with `{Predecessor}: 789` on a Story  
  And the story has no current Predecessor links in AzDo  
  When `NewAzDoHierarchyFromMarkdown.ps1` runs  
  Then `Set-AzDoWorkItemRelations` is called with a relation of type  
  `Microsoft.VSTS.Common.Predecessor-Reverse` pointing to work item 789  

- [ ] **Scenario 4: DryRun reports planned link changes without API calls**  
  Given a plan markdown with `{Successor}: 500` on a Story  
  And the story has no current Successor links in AzDo  
  When `NewAzDoHierarchyFromMarkdown.ps1 -DryRun` runs  
  Then the summary output shows `+1/-0` in the `Links` column  
  And no PATCH request is issued to the AzDo API  

- [ ] **Scenario 5: Work item with only link changes shows Update status**  
  Given a plan markdown where all scalar fields match AzDo exactly  
  And the plan adds one new `{Related}` link  
  When `NewAzDoHierarchyFromMarkdown.ps1` runs  
  Then the summary row for that work item shows status `Update`  
  And the `Links` column shows `+1/-0`  

- [ ] **Scenario 6: Link field with optional title — title ignored on apply**  
  Given a plan markdown with `{Related}: 123 "My story title"`  
  When `ConvertMarkdownToHierarchyJson.ps1` parses the plan  
  Then `$item.linkFields['Related'][0].id` is `123`  
  And `$item.linkFields['Related'][0].title` is `"My story title"`  
  And only ID 123 is used when constructing the AzDo PATCH body  

### Story: Export relational link fields when reading hierarchy to markdown (002)
{WorkItemId}: 2749
{State}: New

{tags}: azDoAutomator, epicAzDoAutomator, relationalLinks  
{Story Points}: 1  

#### {Description}

**As a** developer exporting a work item hierarchy to a plan markdown file  
**I want** `ConvertHierarchyToMarkdown.ps1` to include `{Predecessor}`,  
`{Successor}`, `{Related}`, `{Duplicate}`, and `{DuplicateOf}` fields  
with the linked work item IDs and their titles  
**So that** the exported plan gives a complete, human-readable snapshot of  
relational links that can be reviewed and round-tripped back to Azure DevOps  

#### Scope of Work  

**Step 1 — Extract relational links from AzDo work item `relations`**  
In `GetAzDoUserStory.ps1`, `GetAzDoHierarchyForFeature.ps1`, and  
`GetAzDoHierarchyForEpic.ps1`, after building each work item object, inspect  
`$workItem.relations` and collect entries whose `rel` value matches one of  
the five link type families. Exclude hierarchy relations  
(`System.LinkTypes.Hierarchy-Forward` / `System.LinkTypes.Hierarchy-Reverse`).  
Store the collected links in `$item.linkFields` as an array of `@{ rel; id }`.  

**Step 2 — Resolve linked work item titles**  
For each collected link, extract the work item ID from the relation `url`  
(e.g. `.../workitems/123`). Batch-fetch titles using `Get-AzDoWorkItemById`  
for all linked IDs. Cache results to avoid redundant calls when the same  
ID appears under multiple link types or multiple work items.  

**Step 3 — Serialize link fields in `ConvertHierarchyToMarkdown.ps1`**  
In `Get-ConfigFieldsMarkdown` (or equivalent), output each populated link field  
as a single line with comma-separated `<id> "<title>"` entries:  

```
{Related}: 123 "Fetch user profile story", 456 "Auth token refresh"  
{Predecessor}: 789 "Database schema migration"  
```

Emit only fields that have at least one link. Omit empty link fields entirely.  

**Step 4 — Add Pester tests**  
Cover the scenarios described in the AC Scenarios section below.  

#### {Acceptance Criteria}

| ✅ | What is Verified | Test(s) | Notes |
|---|---|---|---|
| ▢ | `GetAzDoUserStory.ps1` output object contains `linkFields` with `Related` entries when the AzDo item has `System.LinkTypes.Related` relations | Pester with mock API | |
| ▢ | `GetAzDoUserStory.ps1` excludes `System.LinkTypes.Hierarchy-*` relations from `linkFields` | Pester | |
| ▢ | `GetAzDoHierarchyForFeature.ps1` and `GetAzDoHierarchyForEpic.ps1` propagate `linkFields` on each child work item | Pester | |
| ▢ | `ConvertHierarchyToMarkdown.ps1` emits `{Related}: 123 "Title"` when a Story has a Related link to work item 123 with title "Title" | Pester snapshot | |
| ▢ | `ConvertHierarchyToMarkdown.ps1` does not emit a link field line when the work item has no links of that type | Pester | |
| ▢ | Title resolution is cached: multiple links to the same ID result in only one `Get-AzDoWorkItemById` call | Pester with call-count verification | |
| ▢ | Round-trip: a plan exported from AzDo and re-imported produces no link changes (no add/remove) | Pester integration scenario | |
| ▢ | `README.md` is updated to reflect this story's changes | Manual verify | |

#### {Acceptance Tests}

- [ ] **Scenario 1: Related link exported with title**  
  Given an AzDo Story with a `System.LinkTypes.Related` relation to work item 123  
  And work item 123 has title "Auth token refresh"  
  When `GetAzDoUserStory.ps1` fetches the story  
  And `ConvertHierarchyToMarkdown.ps1` converts it to markdown  
  Then the markdown contains `{Related}: 123 "Auth token refresh"`  

- [ ] **Scenario 2: Multiple link types exported as separate fields**  
  Given an AzDo Story with a Predecessor link to ID 789 and a Related link to ID 100  
  When the story is exported to markdown  
  Then the markdown contains a `{Predecessor}:` line with ID 789  
  And a `{Related}:` line with ID 100 on a separate line  

- [ ] **Scenario 3: Hierarchy relations excluded from link fields**  
  Given an AzDo Story that has a `System.LinkTypes.Hierarchy-Reverse` relation (parent) and a Related link to ID 200  
  When the story is exported to markdown  
  Then the markdown does NOT contain a `{Parent}:` or hierarchy-type field line  
  And the markdown contains `{Related}: 200 "{title}"`  

- [ ] **Scenario 4: Empty link type produces no output line**  
  Given an AzDo Story with no Predecessor, Successor, Duplicate, or DuplicateOf links  
  When the story is exported to markdown  
  Then the markdown does not contain `{Predecessor}:`, `{Successor}:`,  
  `{Duplicate}:`, or `{DuplicateOf}:` lines  

- [ ] **Scenario 5: Round-trip produces no spurious link changes**  
  Given an AzDo Story with a Related link to ID 456 titled "Related story"  
  When the story is exported to markdown via `ConvertHierarchyToMarkdown.ps1`  
  And the exported markdown is re-imported via `NewAzDoHierarchyFromMarkdown.ps1 -DryRun`  
  Then the `Links` column in the summary shows `-` (no changes)  
  And no add or remove relation calls are planned  
