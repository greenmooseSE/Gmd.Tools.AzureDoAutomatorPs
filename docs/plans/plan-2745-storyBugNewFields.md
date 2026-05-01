# Epic: Gmd.Tools.AzureDoAutomatorPs

{WorkItemId}: 1577
{State}: New

## Feature: Gmd.Tools.AzureDoAutomatorPs Maintenance

{WorkItemId}: 2205
{State}: Active

### Story: Full rich-text field support for Bug work items in plan files
{WorkItemId}: 2745
{State}: New

{tags}: azDoAutomator, bug, description, epicAzDoAutomator
{Story Points}: 2

#### {Description}

**As a** developer authoring a `### Bug:` item in a markdown plan file  
**I want** to use all rich-text Bug fields (`{Description}`, `{Repro Steps}`,  
`{Expected Result}`, `{Actual Result}`, `{System Info}`, `{Extra Information}`)  
**So that** every relevant Bug field is written to Azure DevOps from the plan,  
giving reviewers full defect context without leaving the plan file  

#### Field Inventory

The following six fields are in scope. Two are new to `appSettings.json`; four  
already exist but need verification and description-text sync.  

| Markdown field | AzDo reference name | Current status |
|---|---|---|
| `{Description}` | `System.Description` | In `appSettings.json`; pipeline wired, untested end-to-end |
| `{Repro Steps}` | `Microsoft.VSTS.TCM.ReproSteps` | In `appSettings.json`; description text needs sync |
| `{Expected Result}` | TBD — confirm from AzDo project | **New** — not yet in `appSettings.json` |
| `{Actual Result}` | TBD — confirm from AzDo project | **New** — not yet in `appSettings.json` |
| `{System Info}` | `Microsoft.VSTS.TCM.SystemInfo` | In `appSettings.json`; description text needs sync |
| `{Extra Information}` | `Custom.ExtraInformation` | In `appSettings.json`; description text needs sync |

#### How the Pipeline Works (context for implementer)

`ConvertMarkdownToHierarchyJson.ps1` handles `{Description}` via a dedicated  
`System.Description` switch case that stores the block in `$item.description`.  
All other html-type fields from `appSettings.json` land in `$item.configFields`  
keyed by their reference name.  

`NewAzDoHierarchyFromMarkdown.ps1` passes `$item.description` as `-Description`  
explicitly, and calls `Merge-ConfigFieldsToParams` for the rest. Fields not listed  
in `$script:_cfgToUpsertParam` are forwarded via the `-Fields` hashtable to  
`UpsertAzDoBug.ps1`, which merges them directly into the AzDo PATCH payload.  

This means adding any new html-type field to `appSettings.json` is sufficient  
for it to flow through to AzDo — **no core script changes are required** for  
`{Expected Result}` and `{Actual Result}` beyond the appSettings.json entry,  
once their AzDo reference names are confirmed.  

#### Scope of Work

**Step 1 — Identify reference names for new fields**  
Inspect the AzDo project's Bug work item type (via the AzDo REST API or the  
process template editor) to confirm the reference names for "Expected Result"  
and "Actual Result". Common candidates:  
- `Custom.ExpectedResult` / `Custom.ActualResult` (custom fields)  
- `Microsoft.VSTS.TCM.ExpectedResults` / similar TCM fields  
Document the confirmed names before proceeding.  

**Step 2 — Update `appSettings.json`**  
- Add `{Expected Result}` and `{Actual Result}` entries to the `Bug` field array  
  with `"type": "html"` and the confirmed reference names.  
- Update the `"description"` metadata text for `{Repro Steps}`, `{System Info}`,  
  and `{Extra Information}` to match the AzDo field descriptions.  

**Step 3 — Verify end-to-end for all six fields**  
- Create a test Bug plan item containing all six fields.  
- Run `NewAzDoHierarchyFromMarkdown.ps1 -DryRun` — confirm no "unknown field"  
  warnings.  
- Run without `-DryRun` and inspect the created AzDo Bug to confirm all six  
  fields are populated.  

**Step 4 — Add Pester tests**  
- `ConvertMarkdownToHierarchyJson.ps1`: confirm each field parses correctly  
  into the expected property (`description` for Description; `configFields` for  
  all others).  
- `NewAzDoHierarchyFromMarkdown.ps1`: confirm `Merge-ConfigFieldsToParams`  
  forwards the configFields values to `UpsertAzDoBug.ps1` via `-Fields`.  

**Step 5 — Update documentation**  
- `example-hierarchy.md`: add/update the `### Bug:` example to show all six  
  fields in use.  
- `docs/createPlanBugPromptTemplate.md`: update the field table to include  
  `{Expected Result}` and `{Actual Result}`, and confirm correct field  
  descriptions for all six.  

#### {Acceptance Criteria}

| ✅ | What is Verified | Test(s) | Notes |
|---|---|---|---|
| ▢ | Reference names for `{Expected Result}` and `{Actual Result}` are confirmed from AzDo | Manual inspect | Required before Step 2 |
| ▢ | `appSettings.json` Bug config contains entries for `{Expected Result}` and `{Actual Result}` with type "html" | DryRun — no unknown-field warnings | |
| ▢ | `appSettings.json` description text for `{Repro Steps}`, `{System Info}`, `{Extra Information}` matches AzDo field descriptions | Manual verify | |
| ▢ | `ConvertMarkdownToHierarchyJson.ps1` parses `{Description}` into `$item.description` for a Bug item | Pester test | |
| ▢ | `ConvertMarkdownToHierarchyJson.ps1` parses `{Expected Result}` into `$item.configFields` keyed by the confirmed reference name | Pester test | |
| ▢ | `ConvertMarkdownToHierarchyJson.ps1` parses `{Actual Result}` into `$item.configFields` keyed by the confirmed reference name | Pester test | |
| ▢ | `Merge-ConfigFieldsToParams` forwards `{Expected Result}` and `{Actual Result}` via `-Fields` to `UpsertAzDoBug.ps1` | Pester test | |
| ▢ | A Bug created from a plan containing all six fields has all six fields populated in AzDo | Live end-to-end test | |
| ▢ | A Bug plan item with none of the optional fields creates without error | Pester test | |
| ▢ | `example-hierarchy.md` `### Bug:` example demonstrates all six fields | Manual verify | |
| ▢ | `docs/createPlanBugPromptTemplate.md` field table is accurate and complete | Manual verify | |

#### {Acceptance Tests}

- [ ] **Scenario 1: Description parsed from Bug plan item**  
  Given a `### Bug:` item in a plan with a `{Description}` block  
  When `ConvertMarkdownToHierarchyJson.ps1` parses the content  
  Then `$item.description` contains the block content  

- [ ] **Scenario 2: Expected Result and Actual Result parsed into configFields**  
  Given a `### Bug:` item with `{Expected Result}` and `{Actual Result}` blocks  
  When `ConvertMarkdownToHierarchyJson.ps1` parses the content  
  Then `$item.configFields` contains entries keyed by the confirmed reference names  
  And each entry contains the corresponding block content  

- [ ] **Scenario 3: All six fields forwarded to UpsertAzDoBug on create**  
  Given a parsed Bug item with all six fields populated  
  And the Bug does not yet exist in AzDo  
  When `NewAzDoHierarchyFromMarkdown.ps1` processes the plan  
  Then `UpsertAzDoBug.ps1` is called with `-Description` set  
  And `-Fields` contains entries for the remaining five fields  

- [ ] **Scenario 4: All six fields written to AzDo in live run**  
  Given a plan with a `### Bug:` item using all six rich-text fields  
  When `NewAzDoHierarchyFromMarkdown.ps1` runs without `-DryRun`  
  Then the created AzDo Bug has all six fields populated with the plan content  

- [ ] **Scenario 5: Bug with no optional fields creates without error**  
  Given a `### Bug:` item that specifies only `{tags}`, `{Story Points}`, and `{Priority}`  
  When `NewAzDoHierarchyFromMarkdown.ps1` processes the plan  
  Then the Bug is created without error  
  And all six optional fields are empty or not set in AzDo  
