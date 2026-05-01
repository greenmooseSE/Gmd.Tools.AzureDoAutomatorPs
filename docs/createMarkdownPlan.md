This is for generating a markdown plan for use with `Gmd.Tools.AzureDoAutomatorPs/src/NewAzDoHiearchyFromMarkdown.ps1`:

# Markdown line break rule (CRITICAL)

**Every non-blank line in the generated markdown file MUST end with two trailing spaces (`  `) before the newline.**  
This is required for correct line-break rendering in all markdown viewers. A bare `\n` without two trailing spaces collapses adjacent lines into the same paragraph.

Applies to:
- All `**Field**: value` metadata lines (e.g. `**State**: Active  `, `**tags**: foo  `)
- All prose / description lines
- The `**As a**`, `**I want**`, `**So that**` story description lines

Does NOT apply to:
- Header lines (`#`, `##`, `###`, …)
- Blank / empty lines
- Table rows (`| ... |`)
- Fenced code block delimiters (` ``` `)

# General rules

* Do not create explicit stories for creating unit tests or BDD tests, rather they should be created as part of each story.
* When story consists adding/modifying properties for db/json etc., ensure that:
- Each added property has a valid BDD/Gherkin scenario which verifies the added property
- For each property, ensure to include nullable, type, length, any inline validations required etc.
* When setting story points, do a realistic estimate of work effort where 1 SP = 1 perfect day of working, for a senior developer.
* Do not create "---" to separate sections (rely on header level usage instead).
* For long texts, consider splitting to multiple lines or paragraphs (use trailing "  " to ensure we get rendered newline).
* Be very explicit in the Acceptance Criterias and Gherkin scenarios, each criteria and scenario should validate only 1 thing.
* Avoid general terms such as "produce an inventory list"

# Tag rules
* Name tags camelCase and not kebab-kase.
* Use shortened keywords (e.g. "prio" instead of "priority").
* Be restrictive in the number of tags to set.

# Title rules
* Avoid emoticons in titles, but use them in other fields if it adds value.
* **Stories must always include a zero-padded three-digit numeric order suffix** to indicate the intended implementation order, e.g. `### Story: My story title (001)`.
  * Number stories sequentially starting at `(001)`, reflecting the order they should be implemented.
  * The order of story blocks in the plan file itself must match the suffix order (i.e. `(001)` appears before `(002)`, etc.).
  * Apply the same suffix convention to epics and features **only when the plan file contains multiple epics or multiple features**.

# General description rules
## Headers inside descriptions
* For epic and feature: Ensure the "top level" start at level 3 ("### Some header")
* For stories, bugs and tasks: start at level 4.

# Story rules
* Each story must be written so that, it can automatically be tested and verified with a BDD/Gherkin scenario, unless story is explicit "manual" (e.g. "Build in CI pipeline").

## Story description rules
* Write user descriptions as below (it is still OK to add headers after this)
```
**As a** persona  
**I want** to do some action  
**So that** I can validate
```


# Epic rules
* Only one epic is allowed per "project"/library, e.g. 1 epic named `Gmd.CsCommon`.
* An epic is a **permanent, long-lived container** that is never closed. It represents the product or library's ongoing evolution. Individual features are planned, delivered, and closed over time, while the epic remains open.
* The epic description itself should contain **high-level, enduring content only**: vision, goals, architecture overview, technology choices, and general constraints. Do NOT put feature-specific details in the epic description.
* Every epic plan should include a long-lived **`## Feature: Maintenance <epic title>`** feature for recurring small bugs and housekeeping stories that do not belong to a dedicated feature. This feature is never closed.
* Use a common tag for all work items named with the epic prefix, e.g. `epicAddUserDashboard` (even though the actual epic is named e.g. `Gmd.CsCommon`).

# Small-scope plan rule

* When the planned feature would result in **only one story** (i.e. the scope is small or trivial), do NOT create a new dedicated feature. Instead, place the story under the epic's `## Feature: Maintenance {epic title}` feature.
* **Before writing the plan**, use `src/FindAzDoItemByTitle.ps1` to search Azure DevOps for an existing Feature with title `Maintenance {epic title}` under the epic (use `-Type Feature -ParentId {epicId}`).
* If the maintenance feature is found in Azure DevOps:
  - Reuse the found feature's work item ID as `{WorkItemId}` in the plan so the new story is appended to the correct existing feature.
  - The plan output should include only the epic header (with its existing `{WorkItemId}`) and the maintenance feature block (with its found `{WorkItemId}`) containing the new story.
  - Save the plan to `docs/plans/plan-{featureId}-featMaintenance{EpicTitle}.md`.
* If no maintenance feature exists in Azure DevOps:
  - Leave `{WorkItemId}` empty for the maintenance feature so it gets created.
  - Create a new file named `docs/plans/plan-tbd-featMaintenance{EpicTitle}.md`.
  - The file should contain the epic header (with the epic's `{WorkItemId}`) and a new `## Feature: Maintenance {epic title}` block with the story inside.

# Work item types
Each work item type must have a prefix and a predefined header level. These are defined as below;
- Epic: "# Epic: {title}"
- Feature: "## Feature: {title}"
- Story: "### Story: {title}"
- Bug with feature as parent: "### Bug: {title}"
- Bug with story as parent: "#### Bug: {title}"
- Task (must have story as parent):  "#### Task: {title}"

# Placeholder rules
* **Never use angle-bracket tags** (e.g. `<SomePlaceholder>`, `<title>`, `<value>`) for placeholder text in the generated plan — they do not render in markdown viewers and can be mistaken for HTML tags.
* Use curly-brace style instead: `{SomePlaceholder}`, `{title}`, `{value}`.
* Use `TODO:` annotations for items that must be filled in by the user before use (e.g. `TODO: describe the goal here`).
