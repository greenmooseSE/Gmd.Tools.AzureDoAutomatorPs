# Epic: Gmd.Tools.AzureDoAutomatorPs
**WorkItemId**: 1577
**State**: New

**WorkItemId**: 1577  
**State**: New  
**tags**: azDoAutomator, automation, azdo, crudOperations, mcpServer  
**Effort**: 79  
**Description**  
Complete build-out of Azure DevOps work item automation tooling to support full CRUD operations on  
Epics, Features, User Stories, Bugs, and Tasks. Implement comprehensive comment management with  
reaction support, tag management, and hierarchical retrieval with all associated metadata. Operations  
are consolidated into Upsert* scripts with -FailIfExist switch for create/update unification.  
Culminate in MCP (Model Context Protocol) server integration to expose all operations as standardized  
tools for AI assistants and automation frameworks.  

## Feature: Unambiguous {Field Name} Syntax for Markdown Hierarchy Files
**WorkItemId**: 2628
**State**: New

**tags**: azDoAutomator, markdownSyntax, epicAzDoAutomator  
**Effort**: 3  
**Priority**: 2  
**Feature Acceptance Tests**  
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

**Description**  
The current markdown hierarchy format uses two inconsistent syntaxes for field markers,  
causing fields placed after `**Description**` to be silently captured as description text.  

### The Core Problem  

The parser enters "description-collecting mode" when it sees `**Description**`.  
Once in that mode, every subsequent line — including `**Field Name**: value` metadata lines —  
is treated as description content. The only lines that can terminate description mode are:  

- A new work item header (`### Story:`, `## Feature:`, etc.)  
- One of three hardcoded header patterns: `#### Acceptance Criteria`, `#### AC Scenarios`,  
  `#### Extra Information`  

All other fields (`**Story Acceptance Tests**`, `**Feature Acceptance Tests**`, any future  
HTML field) are silently swallowed into the description if placed after `**Description**`.  

### Current Workaround and Its Limits  

Placing HTML fields (e.g. `**Story Acceptance Tests**`) *before* `**Description**` works  
because the parser is not yet in description mode. However:  

- It forces an unnatural author order (tests before description).  
- It does not help with `**Feature Acceptance Tests**` on a Feature, because Features  
  often have lengthy descriptions with rich internal headers — any field marker inside  
  those headers is consumed as description.  
- Any new HTML field added to `appSettings.json` silently breaks unless authors know  
  to place it before `**Description**`.  

### Proposed Solution: `{Field Name}` Syntax  

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

#### Rules  

- `{FieldLabel}` at the start of a line (optionally followed by `: value`) is always  
  a field marker, regardless of what collecting mode the parser is in.  
- A field marker with an inline value (`{tags}: foo, bar`) stores the value immediately  
  (single-line fields).  
- A field marker with no inline value (`{Description}`) starts multi-line collection;  
  content is collected until the next `{...}` marker, a work item header, or EOF.  
- Multi-line collection means `**bold**`, `### headers`, tables, and code fences inside  
  a field value are all valid and unambiguous — they can never be mistaken for field markers.  

#### Benefits Over Current Format  

- Authors can freely use `**bold**` text and `###` headers inside any field without  
  worrying about the parser misinterpreting them.  
- No hardcoded list of "special section headers" in the parser — any field label from  
  `appSettings.json` can appear after Description.  
- The generator output becomes consistent: one syntax for all fields, no mix of  
  `**bold**` and `####` headers.  
- Adding a new HTML field to `appSettings.json` automatically works without parser changes.  

### Story: Support {Field Name} markers in ConvertMarkdownToHierarchyJson.ps1 (001)
**WorkItemId**: 2629
**State**: Under Development
**Assigned To**: gmd.machine@gmail.com
**tags**: azDoAutomator, markdownSyntax, epicAzDoAutomator  
**Story Points**: 1  
**Story Acceptance Tests**  
- [ ] **Scenario 1: Single-line field with curly-brace syntax is parsed correctly**  
  Given a markdown story with `{tags}: foo, bar` and `{Story Points}: 3`  
  When `ConvertMarkdownToHierarchyJson.ps1` parses the file  
  Then `tags` equals `"foo, bar"` and `storyPoints` equals `3`  

- [ ] **Scenario 2: Multi-line description field terminates at next {Field Name} marker**  
  Given a story with `{Description}` followed by three lines of prose,  
  then `{Acceptance Criteria}` followed by a table  
  When `ConvertMarkdownToHierarchyJson.ps1` parses the file  
  Then `description` contains only the three prose lines  
  And `configFields["Custom.AcceptanceCriteria"]` contains only the table content  

- [ ] **Scenario 3: {Field Name} inside description content is treated as a field boundary**  
  Given a story where `{Description}` is followed by several lines,  
  then `{Story Acceptance Tests}` with test content  
  When `ConvertMarkdownToHierarchyJson.ps1` parses the file  
  Then `description` does NOT contain the text after `{Story Acceptance Tests}`  
  And `configFields["Custom.StoryAcceptanceTests"]` contains the test content  

- [ ] **Scenario 4: Bold headers inside a {Description} block are captured as description content**  
  Given a story with `{Description}` followed by `### Some Internal Header` and prose  
  When `ConvertMarkdownToHierarchyJson.ps1` parses the file  
  Then `description` contains `### Some Internal Header` and the prose  
  And no separate field is created for the header  

- [ ] **Scenario 5: Unknown {Field Label} emits a warning but does not fail**  
  Given a story with `{NonExistentField}: value`  
  When `ConvertMarkdownToHierarchyJson.ps1` parses the file  
  Then a warning is logged mentioning `NonExistentField`  
  And parsing of the remaining fields completes without error  

**Description**  
**As a** developer or AI agent authoring work item hierarchies in markdown  
**I want** `ConvertMarkdownToHierarchyJson.ps1` to recognize `{Field Name}` as a field  
boundary delimiter — regardless of the current collecting state  
**So that** any field can be placed in any order without accidentally merging into the  
description or a preceding field.  

#### Implementation Notes  
- Add a new regex at the top of `Parse-MarkdownToWorkItems`:  
  `[string]$curlyFieldRegex = '^\{([^}]+)\}(?::\s*(.*))?$'`  
- In the main line-processing loop, check `$curlyFieldRegex` BEFORE the existing  
  description/custom-field collecting branches. If matched:  
  - Finalize any current collecting state (description or custom field).  
  - Resolve the label against `appSettings.json` field config.  
  - If the inline value is present, store immediately (same coercion logic as now).  
  - If no inline value, enter collecting mode (same as html-type field handling).  
- Remove the `$isHashHeaderField` flag — it is no longer needed.  
- Remove the `Get-SpecialSectionName` function and all `**Field Name**` metadata handling.  

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ▢ | `{tags}: foo, bar` is parsed to tags = "foo, bar" | | |
| ▢ | `{Story Points}: 3` is parsed to storyPoints = 3.0 | | |
| ▢ | `{Description}` followed by content is collected until next `{...}` marker | | |
| ▢ | A `{Field Name}` line inside description-collecting mode terminates the description | | |
| ▢ | A `{Field Name}` line inside custom-field-collecting mode terminates that field | | |
| ▢ | Content between `{Description}` and `{Acceptance Criteria}` is stored in description only | | |
| ▢ | `{Story Acceptance Tests}` after description stores content in `Custom.StoryAcceptanceTests` | | |
| ▢ | `{Feature Acceptance Tests}` after description stores content in `Custom.FeatureAcceptanceTests` | | |
| ▢ | Unknown `{FieldLabel}` emits a warning and is stored as a custom field | | |
| ▢ | Pester tests in `test/ConvertMarkdownToHierarchyJsonTests/CurlyFieldSyntaxTest.ps1` all pass | | |

#### Extra Information  
- Pester test file: `test/ConvertMarkdownToHierarchyJsonTests/CurlyFieldSyntaxTest.ps1`  
- Use `testWi`-tagged work items for any integration test fixtures.  

### Story: Emit {Field Name} syntax from ConvertHierarchyToMarkdown.ps1 and update template (002)
**WorkItemId**: 2630
**State**: New

**tags**: azDoAutomator, markdownSyntax, epicAzDoAutomator  
**Story Points**: 1  
**Story Acceptance Tests**  
- [ ] **Scenario 1: Generator outputs {Field Name} for all metadata fields**  
  Given a Story object with tags, storyPoints, state, description, and acceptanceCriteria  
  When `ConvertHierarchyToMarkdown.ps1` generates markdown for the story  
  Then the output contains `{tags}: ...` instead of `**tags**: ...`  
  And the output contains `{Story Points}: ...` instead of `**Story Points**: ...`  
  And the output contains `{Description}` instead of `**Description**`  
  And the output contains `{Acceptance Criteria}` instead of `#### Acceptance Criteria  `  

- [ ] **Scenario 2: Generator places all fields in appSettings.json order, regardless of type**  
  Given a Story with description, acceptanceCriteria, storyAcceptanceTests, and extraInformation  
  When `ConvertHierarchyToMarkdown.ps1` generates markdown  
  Then all four fields appear in the order defined in appSettings.json  
  And none of them are embedded inside any other field's content  

- [ ] **Scenario 3: Round-trip — parse generated output and compare to original**  
  Given a Story with description, acceptanceCriteria, and storyAcceptanceTests  
  When `ConvertHierarchyToMarkdown.ps1` generates markdown  
  And the generated markdown is then parsed by `ConvertMarkdownToHierarchyJson.ps1`  
  Then description, acceptanceCriteria, and storyAcceptanceTests all match the originals  

- [ ] **Scenario 4: Template generator uses {Field Name} syntax in template output**  
  When `GenerateAzDoMarkdownHierarchyTemplate.ps1` is executed  
  Then the generated template uses `{Field Name}` syntax for all field placeholders  
  And the comments still explain the available fields and their types  

- [ ] **Scenario 5: example-hierarchy.md uses {Field Name} syntax**  
  When `example-hierarchy.md` is opened  
  Then all field markers use `{Field Name}` syntax  
  And the file is still parseable by `ConvertMarkdownToHierarchyJson.ps1` producing the correct JSON  

**Description**  
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
- In `ConvertTo-StoryMarkdown`:  
  - Change `"**WorkItemId**: $Id  `n"` → `"{WorkItemId}: $Id  `n"`  
  - Change `"**tags**: ...  `n"` → `"{tags}: ...  `n"`  
  - Change `"**Story Points**: ...  `n"` → `"{Story Points}: ...  `n"`  
  - Change `"**State**: ...  `n"` → `"{State}: ...  `n"`  
  - Change `"**Description**  `n"` → `"{Description}  `n"`  
  - Change `` "`n#### Acceptance Criteria  `n" `` → `` "`n{Acceptance Criteria}  `n" ``  
  - Change `` "`n#### AC Scenarios  `n" `` → `` "`n{AC Scenarios}  `n" ``  
  - Change `` "`n#### Extra Information  `n" `` → `` "`n{Extra Information}  `n" ``  
- Apply equivalent changes in `ConvertTo-FeatureMarkdown` and `ConvertTo-EpicMarkdown`.  

##### GenerateAzDoMarkdownHierarchyTemplate.ps1  
- Update template comments and example output to use `{Field Name}` syntax.  
- Update the `# STORY FORMAT` section to show `{Description}` instead of `**Description**`.  
- Update all example lines in the template to use curly-brace syntax.  

##### example-hierarchy.md  
- Replace all `**Field Name**: value` markers with `{Field Name}: value`.  
- Replace all `**Description**` with `{Description}`.  
- Replace all `#### Acceptance Criteria`, `#### AC Scenarios`, `#### Extra Information`  
  with `{Acceptance Criteria}`, `{AC Scenarios}`, `{Extra Information}`.  

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ▢ | Generator outputs `{tags}:` instead of `**tags**:` for story tags | | |
| ▢ | Generator outputs `{Description}` instead of `**Description**` | | |
| ▢ | Generator outputs `{Acceptance Criteria}` instead of `#### Acceptance Criteria  ` | | |
| ▢ | Generator outputs `{Story Acceptance Tests}` when the field is populated | | |
| ▢ | Generator outputs `{Feature Acceptance Tests}` on Features when the field is populated | | |
| ▢ | `Get-ConfigFieldsMarkdown` uses `{label}:` for non-html fields and `{label}` for html fields | | |
| ▢ | Round-trip parse of generated output matches original field values | | |
| ▢ | `GenerateAzDoMarkdownHierarchyTemplate.ps1` output uses `{Field Name}` syntax | | |
| ▢ | `example-hierarchy.md` uses `{Field Name}` syntax throughout | | |
| ▢ | `example-hierarchy.md` is parseable by `ConvertMarkdownToHierarchyJson.ps1` without errors | | |
| ▢ | README.md is updated to reflect this story's changes | | |
| ▢ | Pester tests in `test/ConvertHierarchyToMarkdownTests/CurlyFieldOutputTest.ps1` all pass | | |

#### Extra Information  
- Pester test file: `test/ConvertHierarchyToMarkdownTests/CurlyFieldOutputTest.ps1`  
- No changes to `NewAzDoHierarchyFromMarkdown.ps1` are required — it delegates parsing to  
  `ConvertMarkdownToHierarchyJson.ps1`.  
