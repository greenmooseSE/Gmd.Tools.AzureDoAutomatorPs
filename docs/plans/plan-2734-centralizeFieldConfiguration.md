# Epic: Gmd.Tools.AzureDoAutomatorPs
{WorkItemId}: 1577
{State}: New

## Feature: Centralize Field Configuration into appSettings.json
{WorkItemId}: 2734
{State}: New

{tags}: azDoAutomator, fieldConfig, maintenance  
{Effort}: 21  
{Description}  
Multiple scripts in the repository hardcode field names, field labels, and field-to-property  
mappings rather than reading them from the centralized `appSettings.json` configuration.  
This creates maintenance burden, inconsistency risks, and makes it impossible to add new  
fields without modifying multiple source files.  

### Problem  
The following scripts contain hardcoded field names or labels that should be  
driven from `appSettings.json`:  
- `src/AzDoAutomatorConstants.ps1` — hardcoded `$script:FIELD_*` constants for all reference names  
- `src/ConvertMarkdownToHierarchyJson.ps1` — hardcoded properties (`storyPoints`, `effort`, etc.) and switch on reference names  
- `src/NewAzDoHierarchyFromMarkdown.ps1` — per-type field builder functions and `_cfgToUpsertParam` mapping  
- `src/ConvertHierarchyToMarkdown.ps1` — `$script:CoreOutputLabels` is a hardcoded array  
- `src/tools/SortMarkdownHierarchy.ps1` — `$script:KnownFields` is a hardcoded set  
- `src/GenerateAzDoMarkdownHierarchyTemplate.ps1` — hardcoded field format comments and example values  

### Solution  
Extend `appSettings.json` field definitions with additional metadata:  
- `markdownLabel` — the label used inside `{...}` in markdown (e.g. "Story Points")  
- `propertyName` — the camelCase property name used in parsed JSON objects (e.g. "storyPoints")  
- `upsertParam` — the parameter name for the Upsert script (e.g. "StoryPoints"), or null if generic -Fields is used  
- `exampleContent` — example value for template generation (e.g. "3" for Story Points)  
- `markdownInstruction` — brief instruction shown in generated templates (e.g. "Number, Stories/Bugs only")  
- `outputOrder` — integer controlling field output order in markdown serialization  
- `isMultiline` — boolean; true for fields that collect multi-line content (Description, AC, etc.)  

All scripts will then read field metadata from `appSettings.json` via `LoadFieldConfiguration.ps1`  
instead of maintaining their own hardcoded lists.  

### Story: Extend appSettings.json field schema with markdown metadata (001)
{WorkItemId}: 2736
{State}: New

{tags}: azDoAutomator, fieldConfig, maintenance  
{Story Points}: 2  
{Description}  
**As a** developer maintaining the AzDo Automator tooling  
**I want** the `appSettings.json` field definitions to include `markdownLabel`, `propertyName`,  
`upsertParam`, `exampleContent`, `markdownInstruction`, `outputOrder`, and `isMultiline` properties  
**So that** all scripts can derive field behavior from a single source of truth  

#### Implementation Details  
Add new optional properties to each field definition object in `appSettings.json`  
under `organizations.{org}.projects.{project}.fields.{type}[]`:  

| Property | Type | Description |  
|----------|------|-------------|  
| `markdownLabel` | string | Label used in `{Label}: value` markdown syntax. Null for fields not shown in markdown. |  
| `propertyName` | string | camelCase name used as the key in parsed work item objects. Null if not parsed into dedicated property. |  
| `upsertParam` | string/null | Named parameter for UpsertAzDo* scripts. Null means field goes to generic `-Fields` hashtable. |  
| `exampleContent` | string/null | Example value used when generating markdown templates. |  
| `markdownInstruction` | string/null | Brief instruction for template generation (e.g. "1-4, 1=highest"). |  
| `outputOrder` | integer/null | Controls ordering when serializing fields to markdown. Lower = earlier. |  
| `isMultiline` | boolean | True if field content spans multiple lines (e.g. Description, Acceptance Tests). Default false. |  

Only writable, markdown-relevant fields need the full set of new properties;  
read-only or system-only fields can leave them null/omitted.  

{Acceptance Criteria}  
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ▢ | Each markdown-relevant field for all 5 work item types has `markdownLabel` populated |  |  |  
| ▢ | Each field that maps to a parsed property has `propertyName` set |  |  |  
| ▢ | Fields with dedicated Upsert parameters have `upsertParam` set |  |  |  
| ▢ | `exampleContent` is populated for fields shown in template generation |  |  |  
| ▢ | `outputOrder` values produce the established ordering (WorkItemId, State, tags, SP/Effort, Priority, ..., Description, AC, Scenarios, Extra Info) |  |  |  
| ▢ | `LoadFieldConfiguration.ps1` still returns all existing properties without breaking |  |  |  
| ▢ | README.md is updated to reflect this story's changes |  |  |  

{Acceptance Tests}  
1. **Scenario**: LoadFieldConfiguration returns new metadata properties  
   Given appSettings.json has been extended with the new schema  
   When `LoadFieldConfiguration.ps1` is called for "User Story" type  
   Then each returned field object contains `markdownLabel`, `propertyName`, `outputOrder`, and `isMultiline` properties  
   And fields like "Story Points" have `exampleContent` = "3" and `markdownInstruction` = "Number, Stories/Bugs only"  

2. **Scenario**: Existing field definitions are backward-compatible  
   Given appSettings.json has the new optional properties added  
   When any existing script calls `LoadFieldConfiguration.ps1`  
   Then the existing `referenceName`, `label`, `description`, `type`, `readOnly` properties are unchanged  
   And no existing test or script breaks  

3. **Scenario**: Output order reflects established field sequence  
   Given fields have `outputOrder` values assigned  
   When fields are sorted by `outputOrder`  
   Then the sequence is: WorkItemId, State, Assigned To, tags, Story Points, Effort, Priority, OriginalEstimate, custom fields, Description, Acceptance Criteria, Acceptance Tests, Extra Information  

### Story: Refactor GenerateAzDoMarkdownHierarchyTemplate to use appSettings.json field metadata (002)
{WorkItemId}: 2737
{State}: New

{tags}: azDoAutomator, fieldConfig, maintenance  
{Story Points}: 2  
{Description}  
**As a** developer generating markdown plan templates  
**I want** `GenerateAzDoMarkdownHierarchyTemplate.ps1` to read field names, example content,  
and instructions from `appSettings.json` instead of hardcoding them  
**So that** adding a new field to `appSettings.json` automatically makes it appear in generated templates  

#### Implementation Details  
- Load field config for each work item type via `LoadFieldConfiguration.ps1`  
- Filter to fields where `markdownLabel` is non-null and `outputOrder` is set  
- Sort by `outputOrder`  
- For the "rules" section, emit `# {Label}: (instruction)` using `markdownInstruction`  
- For the template body, emit `{Label}: exampleContent  ` using `exampleContent`  
- Multi-line fields (`isMultiline = true`) emit `{Label}` on its own line followed by example content on next lines  
- Remove all hardcoded field format comments from the script  

{Acceptance Criteria}  
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ▢ | Generated template includes all fields with non-null `markdownLabel` and `exampleContent` |  |  |  
| ▢ | Field instructions section is generated from `markdownInstruction` values |  |  |  
| ▢ | Adding a new field to appSettings.json causes it to appear in generated templates without script changes |  |  |  
| ▢ | Generated template validates successfully with `ConvertMarkdownToHierarchyJson.ps1` |  |  |  
| ▢ | README.md is updated to reflect this story's changes |  |  |  

{Acceptance Tests}  
1. **Scenario**: Template includes fields from appSettings.json  
   Given appSettings.json defines a field "Priority" with `markdownLabel` = "Priority", `exampleContent` = "3", `markdownInstruction` = "1-4, 1=highest"  
   When `GenerateAzDoMarkdownHierarchyTemplate.ps1` is run  
   Then the output contains a rules comment `# {Priority}: (1-4, 1=highest)`  
   And the template body contains `{Priority}: 3  `  

2. **Scenario**: Multi-line fields generate correct template format  
   Given "Description" has `isMultiline` = true and `exampleContent` = "**As a** [persona]\n**I want** [action]\n**So that** [benefit]"  
   When template is generated for a Story  
   Then `{Description}` appears on its own line  
   And example content lines follow with trailing two-space line breaks  

3. **Scenario**: New field added to appSettings.json appears in template  
   Given a new field "Custom.NewField" is added to appSettings.json with `markdownLabel` = "New Field" and `exampleContent` = "example"  
   When `GenerateAzDoMarkdownHierarchyTemplate.ps1` is run  
   Then the template includes `{New Field}: example  `  

### Story: Refactor ConvertMarkdownToHierarchyJson to derive field parsing from config (003)
{WorkItemId}: 2738
{State}: New

{tags}: azDoAutomator, fieldConfig, maintenance  
{Story Points}: 3  
{Description}  
**As a** developer maintaining the markdown parser  
**I want** `ConvertMarkdownToHierarchyJson.ps1` to derive its field-to-property mapping  
from `appSettings.json` `propertyName` metadata instead of hardcoding a switch statement  
**So that** new config-driven fields automatically parse into the correct object properties  

#### Implementation Details  
- The parser already loads field config and uses it for label resolution  
- Replace the large `switch ($cfgField.referenceName)` block with a data-driven approach:  
  - If `cfgField.propertyName` is set, assign the value to `$currentItem[$cfgField.propertyName]`  
  - Type coercion uses the existing `cfgField.type` (integer, double, string, html, boolean, etc.)  
  - Multi-line fields (`isMultiline` = true) enter collecting mode  
- Remove hardcoded item properties like `storyPoints`, `effort`, `priority`, `originalEstimate`,  
  `fixedIn`, `deployedToDev`, `deployedToStaging`, `deployedToProduction`  
- Instead, initialize the item with only structural properties (`type`, `level`, `title`,  
  `lineNumber`, `workItemId`, `children`) and let all field values live in a `fields` hashtable  
  OR keep backward-compat by populating named properties from config  
- Prefer backward-compatible approach: keep existing properties but populate them via config-driven  
  lookup rather than switch cases  

{Acceptance Criteria}  
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ▢ | All existing test fixtures produce identical parsed output after refactor |  |  |  
| ▢ | The hardcoded switch on reference names is replaced with config-driven dispatch |  |  |  
| ▢ | A new field added to appSettings.json with `propertyName` set is parsed into the item object without code changes |  |  |  
| ▢ | Multi-line fields (html type) still collect content across multiple lines |  |  |  
| ▢ | Inline value fields (integer, double, string, boolean) coerce correctly |  |  |  
| ▢ | README.md is updated to reflect this story's changes |  |  |  

{Acceptance Tests}  
1. **Scenario**: Existing markdown parses identically after refactor  
   Given an existing markdown file with Story Points, Effort, Priority, and custom fields  
   When parsed with the refactored `ConvertMarkdownToHierarchyJson.ps1`  
   Then the output JSON is byte-for-byte identical to pre-refactor output  

2. **Scenario**: New propertyName field parses without code changes  
   Given appSettings.json adds a field with `propertyName` = "riskLevel" and `type` = "string"  
   And a markdown file contains `{Risk Level}: Medium`  
   When parsed with `ConvertMarkdownToHierarchyJson.ps1`  
   Then the item object has property `riskLevel` = "Medium"  

3. **Scenario**: Multi-line html field collects content correctly  
   Given a field has `isMultiline` = true and `type` = "html"  
   And markdown contains the field marker followed by multiple content lines  
   When parsed  
   Then all content lines are collected into the property value  

### Story: Refactor NewAzDoHierarchyFromMarkdown field builders to use config (004)
{WorkItemId}: 2739
{State}: New

{tags}: azDoAutomator, fieldConfig, maintenance  
{Story Points}: 3  
{Description}  
**As a** developer maintaining the hierarchy creation script  
**I want** `NewAzDoHierarchyFromMarkdown.ps1` to replace per-type hardcoded field builder  
functions (`Get-EpicMarkdownFields`, `Get-FeatureMarkdownFields`, etc.) and the `_cfgToUpsertParam`  
mapping with config-driven logic that reads `upsertParam` and `propertyName` from appSettings.json  
**So that** adding a new writable field requires only an appSettings.json change  

#### Implementation Details  
- Replace `Get-EpicMarkdownFields`, `Get-FeatureMarkdownFields`, `Get-StoryMarkdownFields`,  
  `Get-TaskMarkdownFields` with a single generic `Get-WorkItemMarkdownFields` function  
- This function iterates over field config for the given work item type  
- For each field with `propertyName` set: if the item has a non-null value for that property,  
  add `referenceName` → value to the comparison fields hashtable  
- Replace `$script:_cfgToUpsertParam` with a lookup on `upsertParam` from field config  
- `Merge-ConfigFieldsToParams` can use `upsertParam` directly from config instead of maintaining a separate map  
- Remove hardcoded field constants from `AzDoAutomatorConstants.ps1` that are now derivable  
  (keep only truly structural constants like API version strings)  

{Acceptance Criteria}  
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ▢ | Per-type field builder functions are replaced with a single config-driven function |  |  |  
| ▢ | `_cfgToUpsertParam` dictionary is removed; Upsert param mapping comes from config |  |  |  
| ▢ | DryRun output for an existing markdown file is identical before and after refactor |  |  |  
| ▢ | Adding a new writable field to appSettings.json with `upsertParam` set causes it to map to the Upsert script without code changes |  |  |  
| ▢ | Field comparison logic (detecting changed vs unchanged fields) still works correctly |  |  |  
| ▢ | README.md is updated to reflect this story's changes |  |  |  

{Acceptance Tests}  
1. **Scenario**: DryRun produces identical output after refactor  
   Given an existing plan markdown with epics, features, stories, and tasks  
   When `NewAzDoHierarchyFromMarkdown.ps1 -DryRun` is run before and after refactor  
   Then the created/updated/skipped work item report is identical  

2. **Scenario**: New field with upsertParam maps automatically  
   Given appSettings.json adds field "Custom.NewField" with `upsertParam` = "NewField" and `propertyName` = "newField"  
   And a markdown file sets `{New Field}: someValue`  
   When `NewAzDoHierarchyFromMarkdown.ps1` processes the file  
   Then the Upsert call includes `-NewField "someValue"`  

3. **Scenario**: Field without upsertParam falls back to generic -Fields  
   Given a field has `propertyName` = "customThing" but no `upsertParam`  
   When the markdown sets a value for that field  
   Then it is passed to the Upsert script via `-Fields @{ "Custom.Thing" = "value" }`  

### Story: Refactor SortMarkdownHierarchy KnownFields to use config (005)
{WorkItemId}: 2740
{State}: New

{tags}: azDoAutomator, fieldConfig, maintenance  
{Story Points}: 1  
{Description}  
**As a** developer maintaining the sort/diff tooling  
**I want** `SortMarkdownHierarchy.ps1` to derive its `$script:KnownFields` set and field  
output ordering from `appSettings.json` instead of a hardcoded list  
**So that** new fields are automatically handled during sorting and serialization  

#### Implementation Details  
- Replace hardcoded `$script:KnownFields` HashSet with a set built from all fields  
  that have `propertyName` set in config, plus the structural keys (`type`, `title`, `children`, `lineNumber`, `level`)  
- In `Format-ItemAsMarkdown`, use field config ordered by `outputOrder` to emit fields  
  rather than the current hardcoded sequence (WorkItemId, State, tags, SP, Effort, custom, Description, AC, etc.)  
- Load config once at script start via `LoadFieldConfiguration.ps1`  

{Acceptance Criteria}  
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ▢ | `$script:KnownFields` is dynamically built from field config |  |  |  
| ▢ | Field output in sorted markdown follows `outputOrder` from config |  |  |  
| ▢ | Sorting and normalizing an existing markdown file produces equivalent output after refactor |  |  |  
| ▢ | README.md is updated to reflect this story's changes |  |  |  

{Acceptance Tests}  
1. **Scenario**: Sorted output matches established field order  
   Given field config defines `outputOrder` values matching the current hardcoded sequence  
   When `SortMarkdownHierarchy.ps1` sorts an existing hierarchy file  
   Then the field order in the output matches the pre-refactor output  

2. **Scenario**: New field appears in sorted output at correct position  
   Given a new field is added to appSettings.json with `outputOrder` = 50  
   And existing fields have orders 10, 20, 30, 40, 60, 70  
   When a markdown file with the new field is sorted  
   Then the new field appears between the order-40 and order-60 fields  

### Story: Refactor ConvertHierarchyToMarkdown CoreOutputLabels to use config (006)
{WorkItemId}: 2741
{State}: New

{tags}: azDoAutomator, fieldConfig, maintenance  
{Story Points}: 1  
{Description}  
**As a** developer maintaining the hierarchy-to-markdown exporter  
**I want** `ConvertHierarchyToMarkdown.ps1` to derive `$script:CoreOutputLabels` from  
`appSettings.json` field definitions instead of a hardcoded array  
**So that** new fields with dedicated output handling are automatically excluded from  
the config-fields fallback loop  

#### Implementation Details  
- Replace the hardcoded `$script:CoreOutputLabels` array with a set derived from fields  
  that have `propertyName` set (i.e., fields with dedicated properties in the item object)  
- These are the fields handled explicitly in the per-type format logic;  
  they should not also be emitted by `Get-ConfigFieldsMarkdown`  
- Alternatively, if per-type format logic is also made config-driven (leveraging `outputOrder`),  
  `CoreOutputLabels` becomes unnecessary — all fields output in a single ordered loop  

{Acceptance Criteria}  
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ▢ | `$script:CoreOutputLabels` is no longer a hardcoded array |  |  |  
| ▢ | Exported markdown for an existing hierarchy is identical before and after refactor |  |  |  
| ▢ | No duplicate field output occurs (fields are not emitted both as core and as config-driven) |  |  |  
| ▢ | README.md is updated to reflect this story's changes |  |  |  

{Acceptance Tests}  
1. **Scenario**: Export produces identical markdown after refactor  
   Given an Azure DevOps hierarchy with stories containing all standard fields  
   When exported with refactored `ConvertHierarchyToMarkdown.ps1`  
   Then the markdown output is identical to pre-refactor output  

2. **Scenario**: New field with propertyName is excluded from config-driven loop  
   Given a new field added to config with `propertyName` set  
   When a work item is exported to markdown  
   Then the field appears exactly once (not duplicated in both core output and config output)  

### Story: Remove hardcoded field constants from AzDoAutomatorConstants.ps1 (007)
{WorkItemId}: 2742
{State}: New

{tags}: azDoAutomator, fieldConfig, maintenance  
{Story Points}: 1  
{Description}  
**As a** developer maintaining the shared constants module  
**I want** to remove the hardcoded `$script:FIELD_*` constants from `AzDoAutomatorConstants.ps1`  
that are now derivable from `appSettings.json` configuration  
**So that** there is a single source of truth for field reference names  

#### Implementation Details  
- Remove all `$script:FIELD_*` variable declarations that map to fields defined in appSettings.json  
- Keep only truly structural constants (API version, work item type names, query operators)  
- Update all consuming scripts to use a helper function that looks up reference names from config  
  (e.g. `Get-FieldReferenceName -Label "Story Points"` or access `$fieldConfig.referenceName` directly)  
- This story depends on stories 003 and 004 being complete first  

{Acceptance Criteria}  
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ▢ | No `$script:FIELD_*` constants remain for fields defined in appSettings.json |  |  |  
| ▢ | Structural constants (API version, type names, operators) are preserved |  |  |  
| ▢ | All scripts that previously referenced `$script:FIELD_*` still function correctly |  |  |  
| ▢ | All existing Pester tests pass without modification |  |  |  
| ▢ | README.md is updated to reflect this story's changes |  |  |  

{Acceptance Tests}  
1. **Scenario**: Constants file no longer contains field reference name variables  
   Given `AzDoAutomatorConstants.ps1` has been cleaned  
   When inspected  
   Then no `$script:FIELD_DESCRIPTION`, `$script:FIELD_STORY_POINTS`, etc. variables exist  
   And `$script:VALID_WORKITEM_TYPES`, API version constants, and query operators remain  

2. **Scenario**: Scripts still resolve field reference names correctly  
   Given a script needs the reference name for "Acceptance Criteria"  
   When it queries field config for that label  
   Then it receives "Microsoft.VSTS.Common.AcceptanceCriteria"  

3. **Scenario**: All existing tests pass after constant removal  
   Given all `$script:FIELD_*` constants are removed and replaced with config lookups  
   When the full Pester test suite is run  
   Then all tests pass  

### Story: Add exampleContent to appSettings.json for template-generation fields (008)
{WorkItemId}: 2743
{State}: New

{tags}: azDoAutomator, fieldConfig, maintenance  
{Story Points}: 1  
{Description}  
**As a** developer or AI agent generating markdown plan files  
**I want** each field in `appSettings.json` to include `exampleContent` with realistic  
example values and `markdownInstruction` with usage guidance  
**So that** `GenerateAzDoMarkdownHierarchyTemplate.ps1` produces high-quality templates  
that demonstrate exactly how field values should be formatted  

#### Implementation Details  
Populate `exampleContent` and `markdownInstruction` for all writable, markdown-visible  
fields across all 5 work item types. Examples:  

| Label | exampleContent | markdownInstruction |  
|-------|---------------|-------------------|  
| Tags | epicName, feature1, testWi | Comma-separated, camelCase |  
| Story Points | 3 | Estimated working days (0.125-100); Stories/Bugs only |  
| Effort | 13 | Aggregate estimate; Epics/Features only |  
| Priority | 3 | 1-4, 1=highest |  
| Description (Story) | **As a** developer\n**I want** to do X\n**So that** Y | Multi-line; use As a/I want/So that for stories |  
| Acceptance Criteria | \| ✅ \| What is Verified \| Test(s) \| Notes \|\n\|---\|...\| | Markdown table format |  
| Acceptance Tests | 1. **Scenario**: Title\n   Given ...\n   When ...\n   Then ... | Numbered BDD/Gherkin format |  
| OriginalEstimate | 8 | Hours; Tasks/Features/Stories |  
| FixedIn | v2.1.0 | Version/build where completed |  
| DeployedToDev | false | true/false |  

{Acceptance Criteria}  
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ▢ | All writable, markdown-visible fields have `exampleContent` populated |  |  |  
| ▢ | All such fields have `markdownInstruction` populated |  |  |  
| ▢ | Example content for Description fields demonstrates the correct persona format |  |  |  
| ▢ | Example content for AC fields shows the markdown table header |  |  |  
| ▢ | `appSettings.json` remains valid JSON after changes |  |  |  
| ▢ | README.md is updated to reflect this story's changes |  |  |  

{Acceptance Tests}  
1. **Scenario**: Story Points field has realistic example and instruction  
   Given appSettings.json field "Story Points" for "User Story" type  
   When inspected  
   Then `exampleContent` = "3"  
   And `markdownInstruction` = "Estimated working days (0.125-100); Stories/Bugs only"  

2. **Scenario**: Description field has multi-line example demonstrating persona format  
   Given appSettings.json field "Description" for "User Story" type  
   When inspected  
   Then `exampleContent` contains "**As a**", "**I want**", and "**So that**" lines  

3. **Scenario**: appSettings.json is valid JSON after all additions  
   Given all `exampleContent` and `markdownInstruction` values are added  
   When `ConvertFrom-Json` is called on the file  
   Then parsing succeeds without errors  
