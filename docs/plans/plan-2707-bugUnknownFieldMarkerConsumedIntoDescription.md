# Epic: Gmd.Tools.AzureDoAutomatorPs
{WorkItemId}: 1577
{State}: New

## Feature: Gmd.Tools.AzureDoAutomatorPs Maintenance
{WorkItemId}: 2205
{State}: Active

### Bug: Unknown curly-brace field markers consumed into Description instead of stopping collection
{WorkItemId}: 2707
{State}: New
{tags}: azDoAutomator, bug, parser, epicAzDoAutomator
{Priority}: 1

#### {Description}
When the markdown parser in `ConvertMarkdownToHierarchyJson.ps1` encounters a `{FieldLabel}`
curly-brace marker whose label is **not** defined in `appSettings.json` for the current
work item type, it silently appends the marker line (and all subsequent content) to the
active `descriptionBuffer` instead of stopping description collection. This causes all
content after the unknown marker — including subsequent known field sections — to be
absorbed into `System.Description`.

This was observed with `### Bug:` work items using `{Acceptance Criteria}` and
`{Acceptance Tests}` markers, which are not defined in the Bug field configuration. The
entire table and gherkin block ended up in `System.Description` and the dedicated fields
were never populated in Azure DevOps.

##### Root Cause

In `Parse-MarkdownToWorkItems` (file `ConvertMarkdownToHierarchyJson.ps1`), after the
code-fence check, the parser calls `Get-CurlyFieldMarker`. If the label is found in the
item's field config (`$cfgField` is not null), it correctly stops description collection.
But when the label is NOT in the config (`$cfgField` is null), the `else` branch appends
the marker line to the active buffer instead of stopping it:

```powershell
else {
    # WRONG: the marker line itself goes into description / custom field buffer
    if ($script:collectingCustomField) {
        $script:customFieldBuffer += $line
    }
    elseif ($collectingDescription) {
        $descriptionBuffer += $line   # <-- marker consumed into description!
    }
}
```

Any collection of subsequent lines (the table rows, gherkin fences, etc.) continues in
the same mode, absorbing all content until the item ends or a _known_ marker is reached.

##### Affected Files
- `src/ConvertMarkdownToHierarchyJson.ps1` — `Parse-MarkdownToWorkItems` function

##### Reproduction

```powershell
# Create a plan with a Bug item that has {Acceptance Criteria}:
# ### Bug: My Bug
# {Description}
# Some description text.
# {Acceptance Criteria}           ← not in Bug's appSettings.json field config
# | | Some criterion |
# {Acceptance Tests}
# ...

# Run: .\src\NewAzDoHierarchyFromMarkdown.ps1 -EpicId 1577 -MarkdownFile .\plan.md
# Result: Description contains EVERYTHING including AC table and gherkin block.
# AcceptanceCriteria and AcceptanceTests fields are empty in AzDO.
```

#### {Acceptance Criteria}
| Status | Criteria |
|--------|----------|
| | When an unknown `{label}` marker is encountered, the parser **stops** the active collecting mode (description or custom field) |
| | The unknown field marker line is NOT added to the description buffer |
| | Content after the unknown marker is not consumed into description |
| | A debug-level warning is emitted for unrecognised field labels |
| | Known fields that follow an unknown marker are still correctly populated |
| | Existing behaviour for known field markers is unchanged (no regression) |
| | Re-running the bug plan (with `{Acceptance Criteria}` in a Bug item) correctly populates those fields in AzDO (or skips them cleanly) |
| | All existing Pester tests pass |

#### {Acceptance Tests}
```gherkin
Scenario: Unknown field marker stops description collection
  Given a Bug item in a plan with {Description} followed by {Acceptance Criteria}
  And "Acceptance Criteria" is not in the Bug field config
  When ConvertMarkdownToHierarchyJson.ps1 parses the plan
  Then the Description field contains only the text between {Description} and {Acceptance Criteria}
  And the {Acceptance Criteria} marker line does not appear in Description

Scenario: Known field after unknown field is still populated
  Given a Bug item with {Description}, then {UnknownField}, then {Priority}: 2
  When ConvertMarkdownToHierarchyJson.ps1 parses the plan
  Then Description contains only the text before {UnknownField}
  And Priority is set to 2

Scenario: No regression on items where all fields are known
  Given a User Story with {Description}, {Acceptance Criteria}, {Acceptance Tests}
  When ConvertMarkdownToHierarchyJson.ps1 parses the plan
  Then Description, AcceptanceCriteria, and AcceptanceTests are each populated correctly
```
