# Epic: Gmd.Tools.AzureDoAutomatorPs
{WorkItemId}: 1577
{State}: New

## Feature: Gmd.Tools.AzureDoAutomatorPs Maintenance
{WorkItemId}: 2205
{State}: Active

### Bug: Scripts emit legacy asterisk field syntax instead of curly-brace syntax
{WorkItemId}: 2705
{State}: New
{tags}: azDoAutomator, bug, markdownSyntax, epicAzDoAutomator
{Priority}: 1

#### {Description}
Several scripts still emit the legacy `**FieldName**:` asterisk-based markdown syntax  
instead of the current `{FieldName}:` curly-brace syntax introduced by feature 2628.  

When `NewAzDoHierarchyFromMarkdown.ps1` writes back WorkItemId and State values after  
creating work items, it inserts `**WorkItemId**: <id>` and `**State**: <state>` lines.  
Because the detection logic also only checks for the asterisk pattern, it fails to recognize  
that `{WorkItemId}:` already exists in the file and inserts duplicate lines, corrupting the  
plan file.

##### Affected Scripts

| Script | Problem |
|--------|---------|
| `NewAzDoHierarchyFromMarkdown.ps1` | `Update-MarkdownWithWorkItemIds` function writes `**WorkItemId**:` and `**State**:`, only detects asterisk existing lines — fails to see `{WorkItemId}:` and inserts duplicates |
| `SortMarkdownHierarchy.ps1` | Emits `**WorkItemId**:`, `**State**:`, `**tags**:`, `**Story Points**:`, `**Effort**:`, `**Description**` in asterisk syntax |
| `GenerateAzDoMarkdownHierarchyTemplate.ps1` | Generates template examples with `**Description**` and other fields in asterisk syntax |
| `AzDoAutomatorConstants.ps1` | Contains unused legacy regex constants (`REGEX_MARKDOWN_TAGS`, `REGEX_MARKDOWN_DESCRIPTION_START`, `REGEX_MARKDOWN_EFFORT`, `REGEX_MARKDOWN_PRIORITY`) matching asterisk syntax |
| `ConvertMarkdownToHierarchyJson.ps1` | Comment block / synopsis documentation still shows asterisk syntax examples |

##### Reproduction
```powershell
# Create a plan file using {FieldName}: curly-brace syntax, then run:
.\src\NewAzDoHierarchyFromMarkdown.ps1 -EpicId 1577 -MarkdownFile .\docs\plans\plan-with-curly-fields.md
# Result: **WorkItemId**: and **State**: lines inserted ABOVE existing {WorkItemId}: lines
```

##### Root Cause
The `Update-MarkdownWithWorkItemIds` function in `NewAzDoHierarchyFromMarkdown.ps1`:
1. Checks next line with regex `^\*\*WorkItemId\*\*:` — misses `{WorkItemId}:` lines
2. Writes `"**WorkItemId**: $foundId"` — uses asterisk syntax
3. Checks next line with regex `^\*\*State\*\*:` — misses `{State}:` lines
4. Writes `"**State**: $foundState"` — uses asterisk syntax

#### {Acceptance Criteria}
| Status | Criteria |
|--------|----------|
| x | `NewAzDoHierarchyFromMarkdown.ps1` `Update-MarkdownWithWorkItemIds` writes `{WorkItemId}: <id>` instead of `**WorkItemId**: <id>` |
| x | `NewAzDoHierarchyFromMarkdown.ps1` `Update-MarkdownWithWorkItemIds` writes `{State}: <state>` instead of `**State**: <state>` |
| x | `NewAzDoHierarchyFromMarkdown.ps1` detection logic recognizes BOTH `{WorkItemId}:` and `**WorkItemId**:` existing lines to avoid duplicates |
| x | `NewAzDoHierarchyFromMarkdown.ps1` detection logic recognizes BOTH `{State}:` and `**State**:` existing lines to avoid duplicates |
| x | `SortMarkdownHierarchy.ps1` emits `{WorkItemId}:`, `{State}:`, `{tags}:`, `{Story Points}:`, `{Effort}:`, `{Description}` in curly-brace syntax |
| x | `GenerateAzDoMarkdownHierarchyTemplate.ps1` generates templates using curly-brace syntax |
| x | `AzDoAutomatorConstants.ps1` unused legacy regex constants removed (`REGEX_MARKDOWN_TAGS`, `REGEX_MARKDOWN_DESCRIPTION_START`, `REGEX_MARKDOWN_EFFORT`, `REGEX_MARKDOWN_PRIORITY`) |
| x | `ConvertMarkdownToHierarchyJson.ps1` comment/synopsis documentation updated to show curly-brace syntax |
| x | `NewAzDoHierarchyFromMarkdown.ps1` comment/synopsis documentation updated to show curly-brace syntax |
| x | Running `Select-String -Path src\*.ps1,src\tools\*.ps1 -Pattern '\*\*WorkItemId\*\*|\*\*State\*\*|\*\*tags\*\*|\*\*Effort\*\*|\*\*Priority\*\*|\*\*Description\*\*|\*\*Story Points\*\*'` returns zero matches (excluding test files) |
| x | Re-running `NewAzDoHierarchyFromMarkdown.ps1` on a curly-brace plan does not produce duplicate lines |
| x | All existing Pester tests pass |

#### {Acceptance Tests}
```gherkin
Scenario: Write-back uses curly-brace syntax on new plan
  Given a plan markdown using {FieldName}: syntax without WorkItemId
  When NewAzDoHierarchyFromMarkdown.ps1 creates items and writes back IDs
  Then the plan contains {WorkItemId}: <id> lines (not **WorkItemId**: <id>)
  And the plan contains {State}: <state> lines (not **State**: <state>)
# Test passing: ConvertMarkdownToHierarchyJsonTests/CurlyFieldSyntaxTest.ps1 (parser round-trip), DryRun on plan-2705 verified correct output format

Scenario: Write-back detects existing curly-brace WorkItemId
  Given a plan markdown with existing {WorkItemId}: 1234 lines
  When NewAzDoHierarchyFromMarkdown.ps1 runs (items already exist)
  Then no duplicate WorkItemId lines are inserted
# Test passing: Update-MarkdownWithWorkItemIds detects both {WorkItemId}: and **WorkItemId**: patterns

Scenario: Write-back detects existing curly-brace State
  Given a plan markdown with existing {State}: Active lines
  When NewAzDoHierarchyFromMarkdown.ps1 runs
  Then no duplicate State lines are inserted
# Test passing: Update-MarkdownWithWorkItemIds detects both {State}: and **State**: patterns

Scenario: SortMarkdownHierarchy emits curly-brace syntax
  Given a parsed hierarchy with WorkItemId, State, tags, Effort
  When SortMarkdownHierarchy.ps1 formats the output
  Then all field markers use {FieldName}: syntax
# Test passing: ConvertHierarchyToMarkdownTests/CurlyFieldOutputTest.ps1 (all scenarios pass)

Scenario: Idempotent re-run produces no changes
  Given a plan already processed by NewAzDoHierarchyFromMarkdown.ps1 (curly-brace output)
  When NewAzDoHierarchyFromMarkdown.ps1 is run again on the same plan
  Then the plan file content is identical before and after
# Test passing: DryRun on existing plan-2705 (with WorkItemId/State already set) shows no duplicate lines
```
