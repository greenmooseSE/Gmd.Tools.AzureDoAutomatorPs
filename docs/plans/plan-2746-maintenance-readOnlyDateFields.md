# Epic: Gmd.Tools.AzureDoAutomatorPs

{WorkItemId}: 1577  
{State}: New  

## Feature: Gmd.Tools.AzureDoAutomatorPs Maintenance

{WorkItemId}: 2205  
{State}: Active  

### Story: Read-only date metadata fields in markdown export/import
{WorkItemId}: 2746
{State}: New

{tags}: azDoAutomator, epicAzDoAutomator, maintenance, readOnlyFields  
{Story Points}: 1  

#### {Description}

**As a** developer working with Azure DevOps plan files  
**I want** the date metadata fields Created Date, Activated Date, Resolved Date, and  
Closed Date to appear in exported markdown and to be silently ignored when re-importing  
**So that** I have informational context about work item lifecycle in the plan file  
without accidentally overwriting AzDo-managed date fields  

#### Background

Azure DevOps populates `System.CreatedDate`, `Microsoft.VSTS.Common.ActivatedDate`,  
`Microsoft.VSTS.Common.ResolvedDate`, and `Microsoft.VSTS.Common.ClosedDate`  
automatically via workflow state transitions — they are read-only AzDo metadata.  

Currently in `appSettings.json` the first three of these four fields are  
inconsistently flagged: `System.CreatedDate` already has `"readOnly": true`,  
but `ActivatedDate`, `ResolvedDate`, and `ClosedDate` are `"readOnly": false`.  
If a developer edits any of these values in a plan file and runs  
`NewAzDoHierarchyFromMarkdown.ps1`, the script will attempt to write them to  
the AzDo API. Azure DevOps silently ignores or rejects such writes, making the  
behaviour undefined and potentially confusing.  

Additionally, the four date fields are currently **not** included in the  
markdown produced by `GetAzDoHierarchyFor*.ps1` → `ConvertHierarchyToMarkdown.ps1`,  
so they provide no informational value in exported plan files today.  

#### Relationship to Feature 2722 (Stale Markdown Guard)

Feature 2722 introduces `{LastChangedDate}` — a *local file metadata marker*  
that mirrors `System.ChangedDate` at the time the script last wrote the file.  
That field is not an AzDo field label; it exists only to detect staleness.  

The four date fields in this story (`{Created Date}`, `{Activated Date}`,  
`{Resolved Date}`, `{Closed Date}`) are distinct: they use the standard  
`appSettings.json` label-based field mechanism, appear as informational  
metadata in the plan file, and are filtered at the apply stage by the  
`readOnly` flag — they do **not** participate in the stale-guard flow.  

#### Scope of Work

**Step 1 — Fix `appSettings.json` readOnly flags**  
For every work item type (Epic, Feature, User Story, Bug, Task), ensure  
`"readOnly": true` for the following reference names:  
- `Microsoft.VSTS.Common.ActivatedDate`  
- `Microsoft.VSTS.Common.ResolvedDate`  
- `Microsoft.VSTS.Common.ClosedDate`  
(`System.CreatedDate` already has `"readOnly": true` — verify, do not change.)    

**Step 2 — Filter readOnly fields in `Merge-ConfigFieldsToParams`**  
In `NewAzDoHierarchyFromMarkdown.ps1`, load the field configuration for the  
relevant work item type and skip any `configField` whose reference name  
resolves to `readOnly: true` in `appSettings.json`. This ensures date  
values present in the markdown are never forwarded to the AzDo API PATCH body.  
Log a `Debug`-level message for each skipped field so the behavior is visible  
with `-Verbose`/debug logging.  

**Step 3 — Include date fields in hierarchy export output**  
In `GetAzDoHierarchyForEpic.ps1`, `GetAzDoHierarchyForFeature.ps1`, and  
`GetAzDoHierarchyForStory.ps1`, add the four date field values from the AzDo  
API response into the `configFields` hashtable of the output object:  
- `System.CreatedDate` → label `Created Date`  
- `Microsoft.VSTS.Common.ActivatedDate` → label `Activated Date`  
- `Microsoft.VSTS.Common.ResolvedDate` → label `Resolved Date`  
- `Microsoft.VSTS.Common.ClosedDate` → label `Closed Date`  
Only emit a field if its value is non-null in the API response.    
`ConvertHierarchyToMarkdown.ps1` already calls `Get-ConfigFieldsMarkdown`  
which iterates `configFields` — no changes required to the markdown  
serialization layer.  

**Step 4 — Add Pester tests**  
- `Merge-ConfigFieldsToParams`: confirm no readOnly date field is forwarded  
  to the Upsert `-Fields` hashtable when `readOnly: true`.  
- `GetAzDoHierarchyForFeature/Story/Epic.ps1`: confirm all four date fields  
  appear in `configFields` of the returned object when the API returns them.  
- `ConvertHierarchyToMarkdown.ps1`: confirm exported markdown for a Story  
  with all four date fields populated renders them as `{Created Date}: ...`,  
  `{Activated Date}: ...`, etc.  
- `ConvertMarkdownToHierarchyJson.ps1`: confirm the four date fields round-trip  
  (parsed into `configFields`) but are filtered during apply.  

#### {Acceptance Criteria}

| ✅ | What is Verified | Test(s) | Notes |
|---|---|---|---|
| ▢ | `appSettings.json` has `"readOnly": true` for `ActivatedDate`, `ResolvedDate`, `ClosedDate` on all five work item types | Pester / manual inspect | `CreatedDate` already correct — verify only |
| ▢ | `Merge-ConfigFieldsToParams` skips a configField whose reference name is `readOnly: true` in appSettings | Pester — `NewAzDoHierarchyFromMarkdown` unit test | Log debug message on skip |
| ▢ | Running `NewAzDoHierarchyFromMarkdown.ps1` with a markdown that contains `{Activated Date}` does NOT include that field in the AzDo API PATCH body | Pester / DryRun | |
| ▢ | `GetAzDoHierarchyForFeature.ps1` output object contains `configFields` entries for all non-null date fields from the API response | Pester | |
| ▢ | `GetAzDoHierarchyForStory.ps1` output object contains `configFields` entries for all non-null date fields from the API response | Pester | |
| ▢ | `GetAzDoHierarchyForEpic.ps1` output object contains `configFields` entries for all non-null date fields from the API response | Pester | |
| ▢ | `ConvertHierarchyToMarkdown.ps1` includes `{Created Date}`, `{Activated Date}`, `{Resolved Date}`, `{Closed Date}` lines in markdown when those fields are populated | Pester snapshot test | |
| ▢ | A work item with only `{Created Date}` set (others null) produces markdown with only that one date field | Pester | |

#### {Acceptance Tests}

- [ ] **Scenario 1: readOnly date field is silently dropped by Merge-ConfigFieldsToParams**  
  Given a parsed Story item with `{Activated Date}: 2026-01-01` in `configFields`  
  And `Microsoft.VSTS.Common.ActivatedDate` is `readOnly: true` in appSettings  
  When `Merge-ConfigFieldsToParams` processes the item  
  Then `$Params['Fields']` does not contain `Microsoft.VSTS.Common.ActivatedDate`  
  And a Debug log entry is emitted for the skipped field  

- [ ] **Scenario 2: readOnly date field is silently dropped for all four date fields**  
  Given a parsed Story item with all four date fields in `configFields`  
  And all four are `readOnly: true` in appSettings  
  When `Merge-ConfigFieldsToParams` processes the item  
  Then none of the four reference names appear in `$Params['Fields']`  

- [ ] **Scenario 3: Exported Feature markdown includes populated date fields**  
  Given an AzDo Feature work item where `System.CreatedDate` and  
  `Microsoft.VSTS.Common.ActivatedDate` are set, and `ResolvedDate` and  
  `ClosedDate` are null  
  When `GetAzDoHierarchyForFeature.ps1` fetches the item  
  And `ConvertHierarchyToMarkdown.ps1` converts it to markdown  
  Then the markdown contains `{Created Date}: {date value}`  
  And the markdown contains `{Activated Date}: {date value}`  
  And the markdown does NOT contain `{Resolved Date}` or `{Closed Date}`  

- [ ] **Scenario 4: Exported Story markdown includes populated date fields**  
  Given an AzDo User Story work item where all four date fields are set  
  When `GetAzDoHierarchyForStory.ps1` fetches the item  
  And `ConvertHierarchyToMarkdown.ps1` converts it to markdown  
  Then the markdown contains all four date field lines  

- [ ] **Scenario 5: Round-trip preserves date field display without writing to AzDo**  
  Given a plan file exported from AzDo that contains `{Created Date}` and  
  `{Activated Date}` for a Story  
  When `NewAzDoHierarchyFromMarkdown.ps1 -DryRun` processes the plan  
  Then no `System.CreatedDate` or `Microsoft.VSTS.Common.ActivatedDate` key  
  appears in the computed PATCH body for that Story  
