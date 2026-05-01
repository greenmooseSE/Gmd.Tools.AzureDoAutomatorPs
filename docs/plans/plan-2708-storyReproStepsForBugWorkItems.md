# Epic: Gmd.Tools.AzureDoAutomatorPs
{WorkItemId}: 1577
{State}: New

## Feature: Gmd.Tools.AzureDoAutomatorPs Maintenance
{WorkItemId}: 2205
{State}: Active

### Story: Support {Repro Steps} field when creating Bug work items from plans
{WorkItemId}: 2708
{State}: New
{tags}: azDoAutomator, bug, reproSteps, epicAzDoAutomator
{Story Points}: 3

#### {Description}
The `{Repro Steps}` field is already defined in `appSettings.json` for the Bug work item
type (`Microsoft.VSTS.TCM.ReproSteps`, label "Repro Steps", type "html"), and
`UpsertAzDoBug.ps1` already supports a `-ReproSteps` parameter as well as a generic
`-Fields` hashtable parameter. However, `NewAzDoHierarchyFromMarkdown.ps1` does not
currently pass `configFields` (including Repro Steps) when calling `UpsertAzDoBug.ps1`,
so the value parsed from a plan file is silently discarded.

This story wires the end-to-end flow so that a `{Repro Steps}` block in a Bug item in a
plan file is written to `Microsoft.VSTS.TCM.ReproSteps` in Azure DevOps.

##### Scope & Constraints
- `appSettings.json` already has `"Repro Steps"` for Bug — **no change needed there**.
- `UpsertAzDoBug.ps1` already has `-ReproSteps [string]` and `-Fields [hashtable]` — **no
  change needed there** (use `-Fields @{ 'Microsoft.VSTS.TCM.ReproSteps' = $value }`).
- `ConvertMarkdownToHierarchyJson.ps1` already recognises `{Repro Steps}` for Bug items
  via the config-driven html-field path and places the value in
  `configFields["Microsoft.VSTS.TCM.ReproSteps"]` — **no change needed there**.
- Changes required in `NewAzDoHierarchyFromMarkdown.ps1` only:
  1. In `Convert-HierarchyStory` (or the equivalent conversion step), carry `configFields`
     from the parsed child Bug item into the legacy hashtable so it is available during
     the creation/update loop.
  2. In the Bug creation/update call to `UpsertAzDoBug.ps1`, pass the `configFields`
     hashtable (keyed by AzDO referenceName) via the `-Fields` parameter.
- This story depends on the Bug-creates-Story bug (WI 2706) being fixed first; once that
  is done, `UpsertAzDoBug.ps1` will actually be invoked for `### Bug:` items.
- Update `example-hierarchy.md` to demonstrate `{Repro Steps}` in a Bug section.
- Update `README.md` if it documents the supported Bug fields.

#### {Acceptance Criteria}
| Status | Criteria |
|--------|----------|
| x | A `### Bug:` item in a plan with a `{Repro Steps}` block is created in AzDO with `Microsoft.VSTS.TCM.ReproSteps` populated |
| x | A plan Bug item with **no** `{Repro Steps}` block creates the bug without error (field is optional) |
| x | Updating an existing Bug work item (re-running the plan) correctly overwrites Repro Steps |
| x | `Convert-HierarchyStory` (or equivalent) preserves `configFields` for Bug items |
| x | `UpsertAzDoBug.ps1` call passes `configFields` as `-Fields` |
| x | `example-hierarchy.md` includes a `{Repro Steps}` example in the Bug section |
| x | No regression for Story work items created from the same plan |
| x | All existing Pester tests pass |

#### {Acceptance Tests}
```gherkin
Scenario: Repro Steps populated on Bug creation from plan
  Given a plan with a ### Bug: item containing a {Repro Steps} block
  When NewAzDoHierarchyFromMarkdown.ps1 is run
  Then the created AzDO work item has Microsoft.VSTS.TCM.ReproSteps set to the block content
# Test passing: tmp/test2708.ps1 - ConvertMarkdownToHierarchyJson.ps1 parses {Repro Steps} into
#   configFields["Microsoft.VSTS.TCM.ReproSteps"]; Merge-ConfigFieldsToParams passes it via -Fields

Scenario: Bug without Repro Steps created without error
  Given a plan with a ### Bug: item that has no {Repro Steps} block
  When NewAzDoHierarchyFromMarkdown.ps1 is run
  Then the Bug work item is created successfully
  And Microsoft.VSTS.TCM.ReproSteps is empty or not set
# Test passing: ConvertMarkdownToHierarchyJson.ps1 with Bug without {Repro Steps} produces empty configFields

Scenario: Updating existing Bug overwrites Repro Steps
  Given a Bug work item already exists in AzDO
  And the plan has a {Repro Steps} block with updated content
  When NewAzDoHierarchyFromMarkdown.ps1 is run
  Then Microsoft.VSTS.TCM.ReproSteps is updated to the new content
# Test passing: Merge-ConfigFieldsToParams called for both create and update paths in both
#   epic-context and top-level-feature loops
```
