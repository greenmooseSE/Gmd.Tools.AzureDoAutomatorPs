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

## Feature: Unambiguous {Field Name} Syntax for Markdown Hierarchy Files
{WorkItemId}: 2628
{State}: New
{tags}: azDoAutomator, markdownSyntax, epicAzDoAutomator
{Effort}: 3
{Priority}: 2

### {Description}
The current markdown hierarchy format uses two inconsistent syntaxes for field markers,  
causing fields placed after `**Description**` to be silently captured as description text.  

#### The Core Problem  

The parser enters "description-collecting mode" when it sees `**Description**`.  
Once in that mode, every subsequent line — including `**Field Name**: value` metadata lines —  
is treated as description content. The only lines that can terminate description mode are:  

- A new work item header (`### Story:`, `## Feature:`, etc.)  
- One of three hardcoded header patterns: `#### Acceptance Criteria`, `#### Acceptance Tests`,  
  `#### Extra Information`  

All other fields (`**Story Acceptance Tests**`, `**Feature Acceptance Tests**`, any future  
HTML field) are silently swallowed into the description if placed after `**Description**`.  

#### Current Workaround and Its Limits  

Placing HTML fields (e.g. `**Story Acceptance Tests**`) *before* `**Description**` works  
because the parser is not yet in description mode. However:  

- It forces an unnatural author order (tests before description).  
- It does not help with `**Feature Acceptance Tests**` on a Feature, because Features  
  often have lengthy descriptions with rich internal headers — any field marker inside  
  those headers is consumed as description.  
- Any new HTML field added to `appSettings.json` silently breaks unless authors know  
  to place it before `**Description**`.  

#### Proposed Solution: `{Field Name}` Syntax  

Replace all field markers with a new unambiguous delimiter — a field label wrapped in  
curly braces at the start of a line:  

```
{tags}: foo, bar
{Story Points}: 2
{Description}
**As a** developer...

### Some Heading in Description

More description...

{Acceptance Criteria}
| ✅ | ... |

{Story Acceptance Tests}
- [ ] **Test 1: ...**

{Extra Information}
See also: ...
```  

##### Rules  

- `{FieldLabel}` at the start of a line (optionally followed by `: value`) is always  
  a field marker, regardless of what collecting mode the parser is in.  
- A field marker with an inline value (`{tags}: foo, bar`) stores the value immediately  
  (single-line fields).  
- A field marker with no inline value (`{Description}`) starts multi-line collection;  
  content is collected until the next `{...}` marker, a work item header, or EOF.  
- Multi-line collection means `**bold**`, `### headers`, tables, and code fences inside  
  a field value are all valid and unambiguous — they can never be mistaken for field markers.  

##### Benefits Over Current Format  

- Authors can freely use `**bold**` text and `###` headers inside any field without  
  worrying about the parser misinterpreting them.  
- No hardcoded list of "special section headers" in the parser — any field label from  
  `appSettings.json` can appear after Description.  
- The generator output becomes consistent: one syntax for all fields, no mix of  
  `**bold**` and `####` headers.  
- Adding a new HTML field to `appSettings.json` automatically works without parser changes.  

### {Feature Acceptance Tests}
- [ ] **Test 1: Round-trip a story with fields placed after a multi-line description**  
  1. Create a markdown file using the new `{Field Name}` syntax containing a story with a  
     multi-line description, then `{Acceptance Criteria}`, `{Story Acceptance Tests}`, and  
     `{Extra Information}` — all after the description block.  
  2. Parse it with `ConvertMarkdownToHierarchyJson.ps1`.  
  3. Verify that the description, acceptanceCriteria, storyAcceptanceTests, and extraInformation  
     properties each contain only their own content (no cross-contamination).  
  4. Feed the parsed JSON to `ConvertHierarchyToMarkdown.ps1`.  
  5. Verify the generated markdown uses `{Field Name}` syntax for all field markers.  
  6. Parse the generated markdown again and compare the JSON — all values should be identical.  

- [ ] **Test 2: `{Acceptance Criteria}` replaces `#### Acceptance Criteria` in generator output**  
  1. Export a story from Azure DevOps using `ConvertHierarchyToMarkdown.ps1`.  
  2. Verify the output markdown uses `{Acceptance Criteria}` rather than `#### Acceptance Criteria`.  

### Story: Support {Field Name} markers in ConvertMarkdownToHierarchyJson.ps1 (001)
{WorkItemId}: 2629
{State}: Under Development
{Assigned To}: gmd.machine@gmail.com
{tags}: azDoAutomator, markdownSyntax, epicAzDoAutomator
{Story Points}: 1
{Story Acceptance Tests}
- [x] **Scenario 1: Single-line field with curly-brace syntax is parsed correctly**  
  Given a markdown story with `{tags}: foo, bar` and `{Story Points}: 3`  
  When `ConvertMarkdownToHierarchyJson.ps1` parses the file  
  Then `tags` equals `"foo, bar"` and `storyPoints` equals `3`  

- [x] **Scenario 2: Multi-line description field terminates at next {Field Name} marker**  
  Given a story with `{Description}` followed by three lines of prose,  
  then `{Acceptance Criteria}` followed by a table  
  When `ConvertMarkdownToHierarchyJson.ps1` parses the file  
  Then `description` contains only the three prose lines  
  And `configFields["Custom.AcceptanceCriteria"]` contains only the table content  

- [x] **Scenario 3: {Field Name} inside description content is treated as a field boundary**  
  Given a story where `{Description}` is followed by several lines,  
  then `{Story Acceptance Tests}` with test content  
  When `ConvertMarkdownToHierarchyJson.ps1` parses the file  
  Then `description` does NOT contain the text after `{Story Acceptance Tests}`  
  And `configFields["Custom.StoryAcceptanceTests"]` contains the test content  

- [x] **Scenario 4: Bold headers inside a {Description} block are captured as description content**  
  Given a story with `{Description}` followed by `### Some Internal Header` and prose  
  When `ConvertMarkdownToHierarchyJson.ps1` parses the file  
  Then `description` contains `### Some Internal Header` and the prose  
  And no separate field is created for the header  

- [x] **Scenario 5: Unknown {Field Label} is treated as literal text, not a field marker**  
  Given a story collecting `{Description}` and the next line is `{NonExistentField}: value`  
  When `ConvertMarkdownToHierarchyJson.ps1` parses the file  
  Then `{NonExistentField}: value` is stored literally in the description content  
  And no separate field is created for `NonExistentField`  

- [x] **Scenario 6: Bold-wrapped `**{FieldName}**` syntax is recognized as a field marker**  
  Given a story with `**{Story Points}**: 5` and `**{Description}**` followed by prose  
  When `ConvertMarkdownToHierarchyJson.ps1` parses the file  
  Then `storyPoints` equals `5.0`  
  And `description` contains the prose  

- [x] **Scenario 7: Header-style `## {FieldName}` syntax is recognized as a field marker**  
  Given a story with `## {Description}` followed by prose  
  When `ConvertMarkdownToHierarchyJson.ps1` parses the file  
  Then `description` contains the prose  

- [x] **Scenario 8: All field handling is data-driven from appSettings.json**  
  Given a story with `{WorkItemId}: 123`, `{State}: Active`, `{tags}: foo`, `{Story Points}: 3`  
  When `ConvertMarkdownToHierarchyJson.ps1` parses the file  
  Then `workItemId` equals `123`, `state` equals `"Active"`, `tags` equals `"foo"`, `storyPoints` equals `3.0`  
  And all field resolution flows through appSettings.json — no hardcoded field names in the parser  

{Description}
**As a** developer or AI agent authoring work item hierarchies in markdown  
**I want** `ConvertMarkdownToHierarchyJson.ps1` to recognize `{Field Name}` as an unambiguous  
field boundary delimiter in three forms: bare (`{Field Name}`), bold-wrapped (`**{Field Name}**`),  
or header-style (`## {Field Name}`) — regardless of the current collecting state —  
with all field names resolved exclusively through `appSettings.json` (no hardcoded names)  
**So that** any field can appear in any order, unknown labels are treated as literal text  
(not warnings or custom fields), and adding a new HTML field to `appSettings.json` requires  
no parser changes.  

#### Implementation Notes  
- Replace the single curly-brace regex with **three start-of-line patterns**, checked in  
  order before any other content processing:  
  - Bare: `^\{([^}]+)\}(?::\s*(.*))?$`  
  - Bold-wrapped: `^\*\*\{([^}]+)\}\*\*(?::\s*(.*))?$`  
  - Header-style: `^#{1,5}\s+\{([^}]+)\}(?::\s*(.*))?$`  
- After extracting the label from whichever pattern matched, look it up in the full  
  `appSettings.json` field config for the current work item type via  
  `Get-WorkItemFieldConfigLookup` (pre-loaded per work item type).  
- **If the label is not found** in `appSettings.json` for the current work item type:  
  treat the entire line as literal content and append it to the current collecting buffer  
  (description or custom field). Do NOT emit a warning. Do NOT create a custom field.  
- **If the label is found**: finalize any current collecting state, then process the field  
  based on its `referenceName`:  
  - `System.Id` → `$currentItem.workItemId` (integer)  
  - `System.State` → `$currentItem.state` (string)  
  - `System.AssignedTo` → `$currentItem.assignedTo` (string)  
  - `System.Tags` → `$currentItem.tags` (string)  
  - `System.Description` → description buffer (multi-line collecting mode)  
  - `Microsoft.VSTS.Scheduling.StoryPoints` → `$currentItem.storyPoints` (double)  
  - `Microsoft.VSTS.Scheduling.Effort` → `$currentItem.effort` (double)  
  - `Microsoft.VSTS.Common.Priority` → `$currentItem.priority` (integer)  
  - `Microsoft.VSTS.Scheduling.OriginalEstimate` → `$currentItem.originalEstimate` (double)  
  - All other config fields → `$currentItem.configFields[referenceName]`  
  - For html-type fields with no inline value: enter multi-line collecting mode with  
    key `"__cfg:{referenceName}"` (reuse existing `Save-CollectedField` logic).  
  - For non-html fields with an inline value: coerce via `Convert-ConfigFieldValue` and store.  
- Remove `Get-MetadataField`, `Get-SpecialSectionName`, `$metadataLineRegex`,  
  `$isHashHeaderField`, the `$coreLabels` exclusion list, and all  
  `**Field Name**` / `**Field Name**: value` parsing branches.  
- Remove the `$isHashHeaderField` flag — it is no longer needed.  

{Acceptance Criteria}
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ✅ | `{tags}: foo, bar` (bare form) is parsed to tags = "foo, bar" | `GivenBareTagsAndStoryPoints_WhenParsing_ItShouldParseTagsAndStoryPoints` | |
| ✅ | `**{tags}**: foo, bar` (bold-wrapped form) is parsed to tags = "foo, bar" | `GivenBoldWrappedFieldMarkers_WhenParsing_ItShouldParseCorrectly` | |
| ✅ | `{Story Points}: 3` is parsed to storyPoints = 3.0 | `GivenBareTagsAndStoryPoints_WhenParsing_ItShouldParseTagsAndStoryPoints` | |
| ✅ | `{Description}` (bare) followed by content is collected until next known-field `{...}` marker | `GivenDescriptionFollowedByAcceptanceCriteria_WhenParsing_ItShouldNotCrossContaminate` | |
| ✅ | `**{Description}**` (bold-wrapped) followed by content is collected until next known-field `{...}` marker | `GivenBoldWrappedFieldMarkers_WhenParsing_ItShouldParseCorrectly` | |
| ✅ | `## {Description}` (header-style) followed by content is collected until next known-field `{...}` marker | `GivenHeaderStyleFieldMarker_WhenParsing_ItShouldParseDescription` | |
| ✅ | A known-field `{Field Name}` line inside description-collecting mode terminates the description | `GivenDescriptionThenStoryAcceptanceTests_WhenParsing_ItShouldSeparateFields` | |
| ✅ | A known-field `{Field Name}` line inside custom-field-collecting mode terminates that field | `GivenKnownFieldInsideCustomFieldCollection_WhenParsing_ItShouldTerminateCollection` | |
| ✅ | Content between `{Description}` and `{Acceptance Criteria}` is stored in description only | `GivenDescriptionFollowedByAcceptanceCriteria_WhenParsing_ItShouldNotCrossContaminate` | |
| ✅ | `{Story Acceptance Tests}` after description stores content in `Custom.StoryAcceptanceTests` | `GivenStoryAcceptanceTestsAfterDescription_WhenParsing_ItShouldBeInConfigFields` | |
| ✅ | `{Feature Acceptance Tests}` after description stores content in `Custom.FeatureAcceptanceTests` | `GivenFeatureAcceptanceTestsAfterDescription_WhenParsing_ItShouldBeInConfigFields` | |
| ✅ | Unknown `{FieldLabel}` on its own line is stored literally in the current collecting buffer | `GivenUnknownCurlyLabel_WhenInDescription_ItShouldBeStoredLiterallyInDescription` | |
| ✅ | `{WorkItemId}: 123` is resolved through appSettings.json (not a hardcoded check) | `GivenWorkItemIdField_WhenParsing_ItShouldSetWorkItemIdProperty` | |
| ✅ | No hardcoded field name logic remains — all field dispatch is config-driven via referenceName | `GivenMultipleCoreFields_WhenParsing_ItShouldResolveAllThroughConfig` | |
| ✅ | Pester tests in `test/ConvertMarkdownToHierarchyJsonTests/CurlyFieldSyntaxTest.ps1` all pass | All 12 tests pass | |

{Extra Information}
- Pester test file: `test/ConvertMarkdownToHierarchyJsonTests/CurlyFieldSyntaxTest.ps1`  
- Use `testWi`-tagged work items for any integration test fixtures.  

### Story: Emit {Field Name} syntax from ConvertHierarchyToMarkdown.ps1 and update template (002)
{WorkItemId}: 2630
{State}: New
{tags}: azDoAutomator, markdownSyntax, epicAzDoAutomator
{Story Points}: 1
#### {Story Acceptance Tests}:
- [x] **Scenario 1: Generator outputs {Field Name} for all metadata fields**  
  Given a Story object with tags, storyPoints, state, description, and acceptanceCriteria  
  When `ConvertHierarchyToMarkdown.ps1` generates markdown for the story  
  Then the output contains `{tags}: ...` instead of `**tags**: ...`  
  And the output contains `{Story Points}: ...` instead of `**Story Points**: ...`  
  And the output contains `{Description}` instead of `**Description**`  
  And the output contains `{Acceptance Criteria}` instead of `#### Acceptance Criteria  `  

- [x] **Scenario 2: Generator places all fields in appSettings.json order, regardless of type**  
  Given a Story with description, acceptanceCriteria, storyAcceptanceTests, and extraInformation  
  When `ConvertHierarchyToMarkdown.ps1` generates markdown  
  Then all four fields appear in the order defined in appSettings.json  
  And none of them are embedded inside any other field's content  

- [x] **Scenario 3: Round-trip — parse generated output and compare to original**  
  Given a Story with description, acceptanceCriteria, and storyAcceptanceTests  
  When `ConvertHierarchyToMarkdown.ps1` generates markdown  
  And the generated markdown is then parsed by `ConvertMarkdownToHierarchyJson.ps1`  
  Then description, acceptanceCriteria, and storyAcceptanceTests all match the originals  

- [x] **Scenario 4: Template generator uses {Field Name} syntax in template output**  
  When `GenerateAzDoMarkdownHierarchyTemplate.ps1` is executed  
  Then the generated template uses `{Field Name}` syntax for all field placeholders  
  And the comments still explain the available fields and their types  

- [x] **Scenario 5: example-hierarchy.md uses {Field Name} syntax**  
  When `example-hierarchy.md` is opened  
  Then all field markers use `{Field Name}` syntax  
  And the file is still parseable by `ConvertMarkdownToHierarchyJson.ps1` producing the correct JSON  

{Description}
**As a** developer or AI agent reading or generating markdown hierarchy files  
**I want** `ConvertHierarchyToMarkdown.ps1` to emit `{Field Name}` syntax for all field markers,  
and `GenerateAzDoMarkdownHierarchyTemplate.ps1` to produce templates in the new syntax  
**So that** generated and hand-authored files share one consistent, unambiguous format.  

#### Implementation Notes  

##### ConvertHierarchyToMarkdown.ps1  
- Replace all occurrences of `` "**$($fd.label)**: $escaped  `n" `` with  
  `` "{$($fd.label)}: $escaped  `n" `` in `Get-ConfigFieldsMarkdown`.  
- For html-type fields in `Get-ConfigFieldsMarkdown`, replace the current  
  `` "**$($fd.label)**  `n" `` header output with `` "{$($fd.label)}  `n" `` (no colon).  
- Replace the hardcoded per-field output blocks in `ConvertTo-StoryMarkdown`,  
  `ConvertTo-FeatureMarkdown`, and `ConvertTo-EpicMarkdown` with a unified loop that  
  iterates the fields from `appSettings.json` in declaration order and outputs  
  `{label}: value` (non-html) or `{label}` (html, entering multi-line block) for each  
  non-null field. The handful of structural fields that have dedicated output properties  
  (`workItemId` → `System.Id`, `state` → `System.State`, `tags` → `System.Tags`,  
  `storyPoints` → `Microsoft.VSTS.Scheduling.StoryPoints`, etc.) are matched by their  
  `referenceName` and emitted in appSettings.json order alongside config fields.  
- The work item type header line (`# Epic: …`, `## Feature: …`, etc.) remains unchanged —  
  it is structural, not a field marker.  
- Remove any remaining hardcoded `**FieldName**` or `#### Section` output strings from  
  all `ConvertTo-*` functions.  

##### GenerateAzDoMarkdownHierarchyTemplate.ps1  
- Update template comments and example output to use `{Field Name}` syntax.  
- Update the `# STORY FORMAT` section to show `{Description}` instead of `**Description**`.  
- Update all example lines in the template to use curly-brace syntax.  

##### example-hierarchy.md  
- Replace all `**Field Name**: value` markers with `{Field Name}: value`.  
- Replace all `**Description**` with `{Description}`.  
- Replace all `#### Acceptance Criteria`, `#### Acceptance Tests`, `#### Extra Information`  
  with `{Acceptance Criteria}`, `{Acceptance Tests}`, `{Extra Information}`.  

{Acceptance Criteria}
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ✅ | Generator outputs `{tags}:` instead of `**tags**:` for story tags | `GivenStoryWithTagsAndStoryPoints_WhenGenerating_ItShouldUseCurlyBraceFormat` | |
| ✅ | Generator outputs `{Description}` instead of `**Description**` | `GivenStoryWithDescriptionAndAC_WhenGenerating_ItShouldUseCurlyBraceFormat` | |
| ✅ | Generator outputs `{Acceptance Criteria}` instead of `#### Acceptance Criteria  ` | `GivenStoryWithDescriptionAndAC_WhenGenerating_ItShouldUseCurlyBraceFormat` | |
| ✅ | Generator outputs `{Story Acceptance Tests}` when the field is populated | `GivenStoryWithConfigFieldsOfDifferentTypes_WhenGenerating_ItShouldFormatCorrectly` (2615 AC7) | |
| ✅ | Generator outputs `{Feature Acceptance Tests}` on Features when the field is populated | `GivenMultipleConfigFields_WhenGenerating_ItShouldOutputInConfigOrder` (2615 AC8) | |
| ✅ | `Get-ConfigFieldsMarkdown` uses `{label}:` for non-html fields and `{label}` for html fields | `GivenStoryWithConfigFieldsOfDifferentTypes_WhenGenerating_ItShouldFormatCorrectly` | |
| ✅ | No hardcoded `**FieldName**` or `#### Section` output strings remain in any `ConvertTo-*` function | `GivenStoryWithAllCoreFields_WhenGenerating_ItShouldHaveNoBoldFieldMarkers` | |
| ✅ | All fields are emitted in the order declared in appSettings.json for the work item type | `GivenMultipleConfigFields_WhenGenerating_ItShouldOutputInConfigOrder` (2615 AC8) | |
| ✅ | Round-trip parse of generated output matches original field values | `GivenStoryWithDescriptionAndAC_WhenRoundTripped_ItShouldPreserveValues` | |
| ✅ | `GenerateAzDoMarkdownHierarchyTemplate.ps1` output uses `{Field Name}` syntax | `GivenTemplateGenerator_WhenExecuted_ItShouldNotContainBoldFieldMarkers` | |
| ✅ | `example-hierarchy.md` uses `{Field Name}` syntax throughout | `GivenExampleHierarchyFile_WhenParsed_ItShouldReturnWorkItems` | |
| ✅ | `example-hierarchy.md` is parseable by `ConvertMarkdownToHierarchyJson.ps1` without errors | `GivenExampleHierarchyFile_WhenParsedWithOrgProject_ItShouldReturnEpic` | |
| ✅ | README.md is updated to reflect this story's changes | Manual verification | |
| ✅ | Pester tests in `test/ConvertHierarchyToMarkdownTests/CurlyFieldOutputTest.ps1` all pass | All 10 tests pass | |

{Extra Information}
- Pester test file: `test/ConvertHierarchyToMarkdownTests/CurlyFieldOutputTest.ps1`  
- No changes to `NewAzDoHierarchyFromMarkdown.ps1` are required — it delegates parsing to  
  `ConvertMarkdownToHierarchyJson.ps1`.  
