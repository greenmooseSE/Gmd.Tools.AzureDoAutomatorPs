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
* To indicate an order of implementation, you may add numeric suffix e.g. `(001)` in the title, but it is optional.

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
* Only one epic is only allowed per "project"/library, e.g. 1 epic named Gmd.CsCommon.
* When creating a plan for a "epic" with many features, have one single "meta feature" (prefixed `## Feature: Meta - `) which contains the info you normally would write into the epic.
* Use a common tag for all work items to named with epic prefix, e.g. `epicAddUserDashboard` (even though actual epic is named e.g. `Gmd.CsCommon`).

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
