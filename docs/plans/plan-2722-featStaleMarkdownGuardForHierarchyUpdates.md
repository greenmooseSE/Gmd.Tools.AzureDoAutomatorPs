## Feature: Stale Markdown Guard for Hierarchy Updates
{WorkItemId}: 2722  
{tags}: azDoAutomator; epicAzDoAutomator; staleguard  
{Effort}: 3  
{State}: New  
{Description}  
Prevent `NewAzDoHierarchyFromMarkdown.ps1` from overwriting Azure DevOps work items when the  
local markdown plan file is outdated relative to the live work item state. The script already  
writes `{WorkItemId}` back into the file after creation; this feature adds a `{LastChangedDate}`  
field that is similarly written back. On subsequent runs the script compares the stored  
`{LastChangedDate}` against the live `System.ChangedDate` from Azure DevOps and aborts if the  
remote item was modified after the markdown was last synced — unless the caller explicitly passes  
`-Force`.  
  
### Design  
  
The `{LastChangedDate}` field is a **local metadata marker** stored in the markdown file. It is  
NOT an Azure DevOps field to write — it mirrors the read-only `System.ChangedDate` from the API  
response at the moment the item was last persisted (created or updated) by the script. The field  
starts empty in new plan files and is populated automatically alongside `{WorkItemId}`.  
  
### Flow  
  
1. Parse markdown — extract `{WorkItemId}` and `{LastChangedDate}` per work item.  
2. For items with both values present, fetch live `System.ChangedDate` from AzDo API.  
3. Compare: if live date > stored date, the item is stale.  
4. If any item is stale and `-Force` is NOT specified → abort with descriptive error listing  
   all stale items (ID, title, stored date, live date).  
5. If `-Force` is specified → log a warning per stale item and proceed.  
6. After successful create/update → write the new `System.ChangedDate` from the API response  
   back into the markdown file as `{LastChangedDate}: <ISO8601>`.  

### Story: Add staleness detection to NewAzDoHierarchyFromMarkdown.ps1 (001)
{WorkItemId}: 2723  
{tags}: azDoAutomator; epicAzDoAutomator; staleguard  
{Story Points}: 2  
{State}: New  
{Description}  
**As a** developer using `NewAzDoHierarchyFromMarkdown.ps1`  
**I want** the script to detect when a work item in Azure DevOps has been modified since  
my markdown file was last synced  
**So that** I do not accidentally overwrite newer changes made directly in AzDo  
  
#### Implementation Details  
  
The script must:  
- Recognize `{LastChangedDate}` as a local metadata field during markdown parsing  
- After creating or updating a work item, write `{LastChangedDate}: <ISO8601>` into the  
  markdown file on the line following `{WorkItemId}: <id>` (same write-back mechanism)  
- Before updating an existing work item (one that has both `{WorkItemId}` and  
  `{LastChangedDate}`), fetch its current `System.ChangedDate` from the AzDo API  
- If live `System.ChangedDate` > stored `{LastChangedDate}` → item is stale  
- Collect all stale items; if any exist and `-Force` is not specified, abort the entire  
  operation before making any changes (fail-fast)  
- If `-Force` is specified, log a warning per stale item and continue  
- New items (no `{WorkItemId}`) skip staleness check entirely  
- Items with `{WorkItemId}` but no `{LastChangedDate}` skip staleness check (backwards  
  compatibility with existing plan files)  
  
#### Script Interface Changes  
  
| Parameter | Type   | Mandatory | Description                                          |  
|-----------|--------|-----------|------------------------------------------------------|  
| Force     | switch | No        | Overwrite stale items instead of aborting             |  
  
#### Markdown Field Format  
  
```
 Story: My Story Title  
  
{WorkItemId}: 2630  
{LastChangedDate}: 2026-04-28T19:19:15.407Z  
{tags}: azDoAutomator  
```
  
The `{LastChangedDate}` value is always ISO 8601 UTC.  

{Acceptance Criteria}  
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ☐ | Script writes `{LastChangedDate}` into markdown after creating a new work item | | Value matches `System.ChangedDate` from create response |  
| ☐ | Script writes `{LastChangedDate}` into markdown after updating an existing work item | | Value matches `System.ChangedDate` from update response |  
| ☐ | Script aborts with descriptive error when a work item is stale and `-Force` is not set | | Error lists all stale items with IDs, titles, dates |  
| ☐ | Script proceeds with warning when a work item is stale and `-Force` IS set | | Warning logged per stale item via ssLogIt.ps1 |  
| ☐ | Items without `{WorkItemId}` (new items) skip staleness check | | No API call made for new items |  
| ☐ | Items with `{WorkItemId}` but missing `{LastChangedDate}` skip staleness check | | Backwards compatibility |  
| ☐ | `{LastChangedDate}` is placed directly after `{WorkItemId}` line in write-back | | Consistent ordering |  
| ☐ | DryRun mode still performs staleness check but does not abort | | Reports stale items in dry-run output |  
| ☐ | README.md is updated to reflect this story's changes | | New `-Force` parameter documented |

{Acceptance Tests}  
1. **Scenario**: Work item is stale and Force is not specified  
   Given a markdown file with `{WorkItemId}: 100` and `{LastChangedDate}: 2026-04-01T00:00:00Z`  
   And the live work item 100 has `System.ChangedDate` of `2026-04-15T12:00:00Z`  
   When `NewAzDoHierarchyFromMarkdown.ps1` is invoked without `-Force`  
   Then the script throws a terminating error before any updates  
   And the error message contains work item ID 100, stored date, and live date  
  
2. **Scenario**: Work item is stale and Force IS specified  
   Given a markdown file with `{WorkItemId}: 100` and `{LastChangedDate}: 2026-04-01T00:00:00Z`  
   And the live work item 100 has `System.ChangedDate` of `2026-04-15T12:00:00Z`  
   When `NewAzDoHierarchyFromMarkdown.ps1` is invoked with `-Force`  
   Then a warning is logged listing work item 100 as stale  
   And the update proceeds normally  
   And `{LastChangedDate}` in the file is updated to the new `System.ChangedDate` from the response  
  
3. **Scenario**: Work item is not stale  
   Given a markdown file with `{WorkItemId}: 100` and `{LastChangedDate}: 2026-04-15T12:00:00Z`  
   And the live work item 100 has `System.ChangedDate` of `2026-04-15T12:00:00Z`  
   When `NewAzDoHierarchyFromMarkdown.ps1` is invoked  
   Then the update proceeds without warning  
   And `{LastChangedDate}` is updated to the response's `System.ChangedDate`  
  
4. **Scenario**: New work item has no WorkItemId  
   Given a markdown file with a story that has no `{WorkItemId}` line  
   When `NewAzDoHierarchyFromMarkdown.ps1` is invoked  
   Then the script creates the item without performing staleness check  
   And writes both `{WorkItemId}` and `{LastChangedDate}` into the file  
  
5. **Scenario**: Existing item has WorkItemId but no LastChangedDate (legacy file)  
   Given a markdown file with `{WorkItemId}: 200` but no `{LastChangedDate}` line  
   When `NewAzDoHierarchyFromMarkdown.ps1` is invoked  
   Then the script skips staleness check for that item  
   And still writes `{LastChangedDate}` after update completes  
  
6. **Scenario**: Multiple items where only some are stale  
   Given a markdown file with items 100 (stale) and 200 (not stale)  
   When `NewAzDoHierarchyFromMarkdown.ps1` is invoked without `-Force`  
   Then the error message lists item 100 as stale  
   And no updates are performed for either item  
  
7. **Scenario**: DryRun with stale items  
   Given a markdown file with stale item 100  
   When `NewAzDoHierarchyFromMarkdown.ps1` is invoked with `-DryRun`  
   Then the output reports item 100 as stale  
   And the script does NOT throw an error  
   And no changes are made to AzDo or the file  

{Extra Information}  
- `System.ChangedDate` is a read-only datetime field in AzDo, set automatically on any modification  
- The AzDo REST API returns this field in ISO 8601 format (e.g., `2026-04-28T19:19:15.407Z`)  
- The `ConvertMarkdownToHierarchyJson.ps1` parser already supports `{Field}` curly-brace syntax  
- The markdown write-back logic in `NewAzDoHierarchyFromMarkdown.ps1` already handles `{WorkItemId}`  
  insertion; `{LastChangedDate}` follows the same pattern  
- Test file: `test/NewAzDoHierarchyFromMarkdownTests/StalenessDetectionTest.ps1`

### Story: Support {LastChangedDate} in markdown parser and hierarchy export (002)
{WorkItemId}: 2724  
{tags}: azDoAutomator; epicAzDoAutomator; staleguard  
{Story Points}: 1  
{State}: New  
{Description}  
**As a** developer exporting hierarchy from AzDo to markdown  
**I want** `ConvertHierarchyToMarkdown.ps1` to emit `{LastChangedDate}` for each work item  
**So that** exported markdown files are immediately usable with the staleness guard without  
requiring a separate sync step  
  
#### Implementation Details  
  
- `ConvertHierarchyToMarkdown.ps1` must emit `{LastChangedDate}: <ISO8601>` for each work item,  
  sourced from the `System.ChangedDate` field in the hierarchy data  
- The field should be placed directly after `{WorkItemId}` in the output  
- `ConvertMarkdownToHierarchyJson.ps1` must parse `{LastChangedDate}` as a recognized local  
  metadata field (not mapped to an AzDo writable field) and include it in the parsed output  
  so that downstream scripts can access it  
- `GenerateAzDoMarkdownHierarchyTemplate.ps1` should include `{LastChangedDate}` in its  
  template comments to document the field's purpose  

{Acceptance Criteria}  
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ✅ | `ConvertHierarchyToMarkdown.ps1` emits `{LastChangedDate}` after `{WorkItemId}` for each item | LastChangedDateOutputTest.ps1 | Value sourced from `System.ChangedDate` |  
| ✅ | `ConvertMarkdownToHierarchyJson.ps1` parses `{LastChangedDate}` and includes it in output JSON | LastChangedDateParseTest.ps1 | Field preserved as string, not written to AzDo |  
| ✅ | Round-trip: export → re-import preserves `{LastChangedDate}` values | LastChangedDateParseTest.ps1 | No data loss |  
| ✅ | `GenerateAzDoMarkdownHierarchyTemplate.ps1` documents `{LastChangedDate}` in template | | Explains purpose and format |  
| ✅ | Items without `System.ChangedDate` in source data omit the field (no empty line) | LastChangedDateOutputTest.ps1 | Graceful handling |  
| ✅ | README.md is updated to reflect this story's changes | | New field documented |

{Acceptance Tests}  
1. **Scenario**: Export hierarchy emits LastChangedDate  
   Given a work item hierarchy where item 100 has `System.ChangedDate` of `2026-04-15T12:00:00Z`  
   When `ConvertHierarchyToMarkdown.ps1` is invoked  
   Then the output contains `{LastChangedDate}: 2026-04-15T12:00:00Z` after `{WorkItemId}: 100`  
  
2. **Scenario**: Parse markdown with LastChangedDate  
   Given markdown content containing `{LastChangedDate}: 2026-04-15T12:00:00Z`  
   When `ConvertMarkdownToHierarchyJson.ps1` is invoked  
   Then the parsed item object includes a `lastChangedDate` property with value `2026-04-15T12:00:00Z`  
  
3. **Scenario**: Round-trip preserves LastChangedDate  
   Given a markdown file exported from AzDo with `{LastChangedDate}` values  
   When the file is parsed and re-exported  
   Then all `{LastChangedDate}` values are preserved unchanged  
  
4. **Scenario**: Item without ChangedDate in source data  
   Given a work item hierarchy where item 300 has no `System.ChangedDate` value  
   When `ConvertHierarchyToMarkdown.ps1` is invoked  
   Then the output for item 300 does NOT contain a `{LastChangedDate}` line  

{Extra Information}  
- `System.ChangedDate` is available in all work item API responses under `fields`  
- The `{LastChangedDate}` field is purely local metadata — it must NOT be sent to AzDo  
  as a field update (it is read-only on the server side)  
- Test file: `test/ConvertHierarchyToMarkdownTests/LastChangedDateOutputTest.ps1`  
  and `test/ConvertMarkdownToHierarchyJsonTests/LastChangedDateParseTest.ps1`  


