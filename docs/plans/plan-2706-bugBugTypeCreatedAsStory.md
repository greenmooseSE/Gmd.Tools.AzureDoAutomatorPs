# Epic: Gmd.Tools.AzureDoAutomatorPs
{WorkItemId}: 1577
{State}: New

## Feature: Gmd.Tools.AzureDoAutomatorPs Maintenance
{WorkItemId}: 2205
{State}: Active

### Bug: "Bug:" heading in plan creates a User Story instead of Bug work item
{WorkItemId}: 2706
{State}: New
{tags}: azDoAutomator, bug, hierarchy, epicAzDoAutomator
{Priority}: 1

#### {Description}
When a plan markdown contains a `### Bug: <title>` heading at story level, the resulting
work item in Azure DevOps is created as a **User Story** instead of a **Bug**.

##### Root Cause

The `Convert-WorkItemsToLegacyFormat` / `Convert-HierarchyStory` pipeline in
`NewAzDoHierarchyFromMarkdown.ps1` collapses both `Story` and `Bug` nodes into the
same legacy `feature.stories` list using `Convert-HierarchyStory`. The original `type`
field is not preserved in the returned hashtable — it is silently dropped.

All creation loops subsequently call `$script:WORKITEM_TYPE_STORY` and
`UpsertAzDoStory.ps1` unconditionally, regardless of whether the source item
was parsed as a Bug.

##### Affected Locations in `NewAzDoHierarchyFromMarkdown.ps1`

| Location | Problem |
|----------|---------|
| `Convert-HierarchyStory` | Returns hashtable without `type` key — Bug type is lost |
| `Convert-HierarchyFeature` (line ~678) | Groups Bug nodes into `feature.stories` via `Convert-HierarchyStory`, discarding type |
| Creation loop (line ~1157 / ~1218 / ~1451 / ~1511) | Always passes `Type = $script:WORKITEM_TYPE_STORY` and calls `UpsertAzDoStory.ps1` |
| DryRun analysis (line ~520 / ~576) | Counts Bug nodes as `StoriesCreate`, not `BugsCreate` |

##### Reproduction

```powershell
# Add a Bug heading at story level in a plan and run:
.\src\NewAzDoHierarchyFromMarkdown.ps1 -EpicId 1577 -MarkdownFile .\docs\plans\plan-with-bug-heading.md
# Result: work item created with type "User Story" instead of "Bug"
```

#### {Acceptance Criteria}
| Status | Criteria |
|--------|----------|
| | `Convert-HierarchyStory` preserves `type` field in returned hashtable (e.g. `type = 'Bug'` or `type = 'Story'`) |
| | Creation loop checks `story.type` and calls `UpsertAzDoBug.ps1` when type is `Bug` |
| | Creation loop uses `$script:WORKITEM_TYPE_BUG` (or equivalent constant) when type is `Bug` |
| | `Find-ExistingWorkItemByTitle` called with correct type (`Bug` vs `User Story`) |
| | DryRun analysis counts Bug nodes in `BugsCreate` / `BugsUpdate` counters, not `StoriesCreate` |
| | DryRun output reports `Bugs to create:` separately from `Stories to create:` |
| | `### Bug: <title>` in a plan creates a work item of type Bug in AzDO |
| | `### Story: <title>` in a plan still creates a User Story (no regression) |
| | All existing Pester tests pass |

#### {Acceptance Tests}
```gherkin
Scenario: Bug heading creates Bug work item
  Given a plan markdown with "### Bug: My Bug Title" under a feature
  When NewAzDoHierarchyFromMarkdown.ps1 processes the plan
  Then a work item of type "Bug" is created in Azure DevOps
  And the work item title matches "My Bug Title"

Scenario: Story heading still creates User Story
  Given a plan markdown with "### Story: My Story Title" under a feature
  When NewAzDoHierarchyFromMarkdown.ps1 processes the plan
  Then a work item of type "User Story" is created in Azure DevOps

Scenario: DryRun counts bugs separately from stories
  Given a plan markdown with 2 stories and 1 bug under a feature
  When NewAzDoHierarchyFromMarkdown.ps1 runs with -DryRun
  Then the output reports "Stories to create: 2"
  And the output reports "Bugs to create: 1"

Scenario: Existing Bug found by correct type on re-run
  Given a Bug work item 9999 already exists in AzDO
  And the plan contains "### Bug: My Bug Title" with {WorkItemId}: 9999
  When NewAzDoHierarchyFromMarkdown.ps1 processes the plan
  Then the existing Bug 9999 is updated (not a new User Story created)
```
