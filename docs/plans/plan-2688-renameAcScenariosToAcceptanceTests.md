# Epic: Gmd.Tools.AzureDoAutomatorPs
{WorkItemId}: 1577
{State}: New

## Feature: Rename "Acceptance Tests" to "Acceptance Tests" Everywhere
{WorkItemId}: 2688
{State}: New
{tags}: azDoAutomator, rename, cleanup, epicAzDoAutomator
{Effort}: 5
{Priority}: 2

### {Description}
The Azure DevOps field `Custom.AcceptanceTests` already uses label "Acceptance Tests" in  
`appSettings.json`, but the codebase still references the legacy name "Acceptance Tests" in scripts,  
markdown examples, documentation, prompt templates, and test files. This feature aligns all  
references to the canonical label "Acceptance Tests".

### {Acceptance Tests}
- [ ] **Test 1: All scripts use "Acceptance Tests" label consistently**  
  1. Run: `Select-String -Path src\*.ps1 -Pattern "Acceptance Tests" -SimpleMatch`  
  2. Verify zero matches.  

- [ ] **Test 2: Markdown examples parse correctly with new field name**  
  1. Run: `.\src\ConvertMarkdownToHierarchyJson.ps1` against `example-hierarchy.md`.  
  2. Verify "Acceptance Tests" field is populated in output JSON.  
  3. Verify no "Acceptance Tests" key exists in output JSON.  

- [ ] **Test 3: Existing Pester tests pass after rename**  
  1. Run all Pester tests in `test/`.  
  2. Verify zero failures introduced by the rename.  

### Story: Rename SetAzDoAcScenarios.ps1 to SetAzDoAcceptanceTests.ps1
{WorkItemId}: 2689
{State}: Done
{tags}: azDoAutomator, rename, epicAzDoAutomator
{Effort}: 1
{Priority}: 2

#### {Description}
Rename the script file `src/SetAzDoAcScenarios.ps1` to `src/SetAzDoAcceptanceTests.ps1`.  
Update all internal references (parameter names, log messages, comments) and any callers  
across the repository. Update `mcpConfig.yaml` if the script is registered there.

#### {Acceptance Criteria}
| Status | Criteria |
|--------|----------|
| | File `src/SetAzDoAcScenarios.ps1` no longer exists |
| | File `src/SetAzDoAcceptanceTests.ps1` exists and functions identically |
| | All callers updated (grep for "SetAzDoAcScenarios" returns zero matches) |
| | `mcpConfig.yaml` updated if previously referencing old name |
| | Pester tests updated/renamed accordingly |

#### {Acceptance Tests}
```gherkin
Scenario: Renamed script sets Acceptance Tests field
  Given a User Story with a known WorkItemId
  When SetAzDoAcceptanceTests.ps1 is invoked with -WorkItemId and -Value
  Then the Custom.AcceptanceTests field is updated in Azure DevOps
```

### Story: Replace "Acceptance Tests" references in all markdown example files
{WorkItemId}: 2690
{State}: Done
{tags}: azDoAutomator, rename, epicAzDoAutomator
{Effort}: 1
{Priority}: 2

#### {Description}
Replace all occurrences of `{Acceptance Tests}` and `#### Acceptance Tests` with `{Acceptance Tests}`  
in `example-hierarchy.md`, `example-hierarchy2.md`, and `feature-markdown-export-import-plan.md`.

#### {Acceptance Criteria}
| Status | Criteria |
|--------|----------|
| | `example-hierarchy.md` uses `{Acceptance Tests}` |
| | `example-hierarchy2.md` uses `{Acceptance Tests}` (and new curly-brace syntax) |
| | `feature-markdown-export-import-plan.md` uses `{Acceptance Tests}` |
| | `Select-String -Path *.md -Pattern "Acceptance Tests"` returns zero matches in root .md files |

#### {Acceptance Tests}
```gherkin
Scenario: Parser recognizes Acceptance Tests field from example files
  Given example-hierarchy.md uses {Acceptance Tests} marker
  When parsed by ConvertMarkdownToHierarchyJson.ps1
  Then the output JSON contains "Acceptance Tests" field entries
```

### Story: Replace "Acceptance Tests" in parser and export scripts
{WorkItemId}: 2691
{State}: Done
{tags}: azDoAutomator, rename, epicAzDoAutomator
{Effort}: 2
{Priority}: 1

#### {Description}
Update `ConvertMarkdownToHierarchyJson.ps1`, `ConvertHierarchyToMarkdown.ps1`,  
`NewAzDoHierarchyFromMarkdown.ps1`, and `src/tools/SortMarkdownHierarchy.ps1` to use  
"Acceptance Tests" as the field label. Remove legacy `#### Acceptance Tests` header detection  
while keeping backward compatibility during a transition period (emit warning on old syntax).

#### {Acceptance Criteria}
| Status | Criteria |
|--------|----------|
| | `ConvertMarkdownToHierarchyJson.ps1` recognizes `{Acceptance Tests}` |
| | `ConvertHierarchyToMarkdown.ps1` outputs `{Acceptance Tests}` |
| | `NewAzDoHierarchyFromMarkdown.ps1` maps field to `Custom.AcceptanceTests` |
| | `SortMarkdownHierarchy.ps1` uses "Acceptance Tests" heading |
| | Legacy `{Acceptance Tests}` still parsed with deprecation warning |
| | All related Pester tests pass |

#### {Acceptance Tests}
```gherkin
Scenario: Parser handles new Acceptance Tests field name
  Given a markdown file with {Acceptance Tests} field
  When ConvertMarkdownToHierarchyJson.ps1 processes it
  Then the JSON output maps to Custom.AcceptanceTests

Scenario: Legacy Acceptance Tests field emits deprecation warning
  Given a markdown file with {Acceptance Tests} field
  When ConvertMarkdownToHierarchyJson.ps1 processes it
  Then the field is still parsed correctly
  And a deprecation warning is emitted
```

### Story: Update documentation and prompt templates
{WorkItemId}: 2692
{State}: Done
{tags}: azDoAutomator, rename, docs, epicAzDoAutomator
{Effort}: 1
{Priority}: 2

#### {Description}
Update all references to "Acceptance Tests" in:
- `README.md`
- `docs/implementStoryRules.md`
- `docs/promptImplementStory.md`
- `docs/promptImplementStory_ThisProject.md`
- All `docs/prompt*.ps1` scripts (string literals referencing the field name)
- `docs/createStoryRules_General.md` and `docs/createStoryRules_ThisProject.md`

#### {Acceptance Criteria}
| Status | Criteria |
|--------|----------|
| | `Select-String -Path docs\*.md,docs\*.ps1,README.md -Pattern "Acceptance Tests"` returns zero |
| | All prompt templates reference "Acceptance Tests" |
| | README.md sections describing the field use "Acceptance Tests" |
| | `docs/implementStoryRules.md` updated |

#### {Acceptance Tests}
```gherkin
Scenario: Prompt templates use Acceptance Tests terminology
  Given docs/promptImplementStory_ThisProject.md content
  When searching for "Acceptance Tests"
  Then zero matches are found
  And "Acceptance Tests" appears in the verification section
```

### Story: Update plan markdown files to use Acceptance Tests
{WorkItemId}: 2693
{State}: Done
{tags}: azDoAutomator, rename, epicAzDoAutomator
{Effort}: 1
{Priority}: 3

#### {Description}
Update existing plan files in `docs/plans/` and `docs/legacyPlans/` to replace  
"Acceptance Tests" with "Acceptance Tests" where applicable.

#### {Acceptance Criteria}
| Status | Criteria |
|--------|----------|
| | All plan files use "Acceptance Tests" |
| | No plan file contains "Acceptance Tests" |
| | Plans still parse correctly via ConvertMarkdownToHierarchyJson.ps1 |

#### {Acceptance Tests}
```gherkin
Scenario: Updated plans parse without error
  Given all plan files use {Acceptance Tests}
  When ConvertMarkdownToHierarchyJson.ps1 processes any plan
  Then no parse errors occur
```
