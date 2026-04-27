# Create Feature Plan — AB#1577

> **Before proceeding, read the copilot instructions at `.github/copilot-instructions.md`.**  
> This file contains important project-specific rules and coding conventions that must be followed.

## Task

Create a feature plan markdown file for the feature described in the **Feature Specifications** section below.

**Required process:**
1. Fetch the latest context from Azure DevOps — read the parent epic (and feature, if provided) using the scripts in `src/`. Do NOT rely on memory or previous context from earlier conversations.
2. Use `src/GenerateAzDoMarkdownHierarchyTemplate.ps1` to generate a markdown starting template.
3. Refer to `example-hierarchy.md` for reference formatting.
4. Apply all rules from the sections below when designing stories and writing the plan.
5. Save the plan as a new markdown file in `docs/plans/` (create the folder if it does not exist).

## Azure DevOps Configuration

- **Organization**: falco-it
- **Project**: GMD
- **PAT Token**: `($env:GMD_AZDO_MACHINE_WORKITEMSRW | ssEncryptDecrypt.ps1 -Decrypt)`
- **Epic ID**: AB#1577
- **Scripts location**: `src/`

## Feature Specifications

- **Goal**: Support all fields in AzureDo for the different work item types.
- **Scope**: Support for org falco-it and proj GMD, but functionality should also work for other orgs/projects with other field definitions.
- **Special considerations**:
- All fields in Epic/Feature/Story/Bug/Task in AzureDO should be supported for both reading and updating
- Store all fields that we support in a json config file at root, with their name, label, desc and type, and if they are readonly or not. Also include work item id as a field even though its not a field per se.
- Remove "SP" and instead use actual field label name "Story Points".
- Adjust `azdoStateConfig-falco-it-GMD.json` to be only one appSettings.json, and structure its content so it can be grouped by org/project instead of its filename.
- Adjust the appSettings.json to have a states array, where each work item type has an object array of states including if they are readOnly or not, instead of current just writing the "writable" states. This will help us to update states to proper values.
- Fields that you should not miss including, but use rest api to verify which work item types they belong to: AI Implemented, Functionality Tested, Code Reviewed, Fixed In, Deployed to dev, deployed to staging, deployed to production, feature acceptance tests, story acceptance tests, extra information, system info, original estimate (hours), remaining work (hours), completed work (hours)
- Generated plan output file: `docs\legacyPlans\gmd.azureDoAutomatorPs\plan-20260423-supportNewFields.md`

## Plan Creation Rules

This is for generating a markdown plan for use with `Gmd.Tools.AzureDoAutomatorPs/src/NewAzDoHiearchyFromMarkdown.ps1`:

# General rules

* Do not create explicit stories for creating unit tests or BDD tests, rather they should be created as part of each story.
* When story consists adding/modifying properties for db/json etc., ensure that:
- Each added property has a valid BDD/Gherkin scenario which verifies the added property
- For each property, ensure to include nullable, type, length, any inline validations required etc.
* When setting story points, do a realistic estimate of work effort where 1 SP = 1 perfect day of working, for a senior developer.
* Do not create "---" to separate sections (rely on header level usage instead).
* End each line with "  " to create newline in markdown rendering.
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

## Story Rules

# General rules
- **One story should contain the full scope for a unit of work:** All layers needed for a feature to be testable and complete (e.g. logic, validation, tests, documentation).
- This ensures stories are independently verifiable and don't create dependencies between stories.
- A story should NOT be split across multiple epics or "wait for another story" to be testable.

# Story fields to set
- All fields should be written with multi-line markdown.

## Read-only story fields
- **State**: Should only reflect state from AzureDO, new stories may leave this empty.
- **WorkItemId**: Should only reflect identifier from AzureDO for existing stories, should NEVER be generated. For new stories this should be left empty.

## Description
- Should contain 3-line persona layout (`**As a** ... **I want** ... **So that** ...`)
- May contain headers with content e.g. `### Problem` and `## Solution`.


## Acceptance Criteria
- Acceptance Criteria **must be written as a markdown table** with 4 columns:
  | ✅ | What is Verified | Test(s) | Notes |
  |---|-----------------|---------|-------|
  | ▢ | (Describe what should be verified) | (Test name or method, filled in after implementation) | (Any notes, filled in after implementation) |
- Prefer items that can be verified automatically; only diverge if the story nature doesn't allow it (e.g., "Create CI pipeline").
- Include ONLY explicit criteria specific to this story's business logic or requirements.
- **Do NOT include general criteria** such as:
  - Implicit quality expectations that are always required (e.g. code executes without errors, no linting warnings) — state only explicit, story-specific requirements
  - Vague performance criteria without specific, measurable benchmarks (e.g. "should be performant")
  - Negated criteria like `We should NOT add property X` (state the positive requirement instead)
- Focus on what the user/feature MUST do or behave like when this story is complete.
- Each AC item should be testable with an automated test (unit, integration, or snapshot).

## AC Scenarios
- Write Gherkin/BDD scenarios in bullet list format `- [ ] **Scenario 1: Scenario title**  \nGiven ...  \nWhen ...  \nThen ...`.
- The scenarios should be explicit enough so they can be written as automated (integration) tests.

## Relationship Between AC Criteria and AC Scenarios
- **AC Criteria** test individual conditions, properties, or validations in isolation (e.g., "Invalid email input should reject").
- **AC Scenarios** test complete user workflows using Given-When-Then (Gherkin/BDD format).
- Typically, one AC Scenario exercises multiple AC Criteria; they should complement—not duplicate—each other.
- Example: If AC says "System validates email format", the Scenario might be "Given invalid email | When user submits | Then system shows error".

## Extra Information
Optional additional info if for context, might be links, notes about known issues etc.

## Story Points
Story points value is estimated **working days a human needs to spend**, assuming AI agents handle coding tasks when possible.

Possible values: 0, 0.125, 0.25, 0.375, 0.5, 0.75, 1, 2, 3, 5, 8, 13, 20, 40, 100.

### How to Estimate
1. Identify what the Agent will do: Move/rename files, generate code, update references, write boilerplate, scaffold tests
2. Identify what the Human will do: Review PR, validate test logic, make architectural decisions, verify behavior, write/debug complex business logic
3. **The Human's time = the story points estimate.** Do NOT include Agent coding time.

### Examples for Clarity
| Task | Agent Does | Human Does | Points |
|------|---------|--------|--------|
| Refactor/rename across files | Update references, fix call sites | Review changes, verify behavior | 0.5 |
| Add validation to existing function | Generate boilerplate, scaffold tests | Implement logic, write tests, verify | 2 |
| Add a new simple function/command | Scaffold structure, write boilerplate | Write logic, test, verify | 1 |
| Complex feature with unknowns | Write code per Human's design | Architect solution, make decisions, review | 5+ |

## Tags
- Should be in format `camelCase`.
- Always include a tag indicating which epic it belongs to (should also exist in epic).
- If feature is not a "maintenance" feature, use a tag to "group" stories per epic.
- Shorten long words e.g., `prio` instead of `priority`.
## Project-Specific Story Rules

## Tags
- **For test work items:** Use `testWi` tag to mark any work items created for testing purposes (helps identify orphan items later).

## Acceptance Criteria — PowerShell-specific
- **Do NOT include** criteria that are implicit for all PS1 work in this project:
  - `Script should execute without errors` (always expected)
  - `Script should produce no PSScriptAnalyzer warnings` (implicit code quality rule)
  - `Parameters should have help text` (always expected for public scripts)
- **DO include** explicit, story-specific behavioral criteria, e.g.:
  - A specific parameter value produces a specific AzDo API call
  - Output written to the pipeline matches a specific object shape
  - A specific error/exception is thrown for invalid input

## Story details (PowerShell)
### Script interface
- Document the public script interface explicitly: parameter names, types, mandatory/optional, and any `[Validate*()]` attributes.
- Describe expected pipeline output: object type, properties, or plain string output as relevant.
- If the script wraps an Azure DevOps API call, specify the endpoint, HTTP method, and key request/response fields.

### Pester tests
- Reference the Pester test file name and path in the AC.
- Use `Describe`/`Context`/`It` naming that reflects the AC scenario being verified.
- Prefer integration-level Pester tests that call the script with real (or mocked) AzDo responses over unit-testing internal helpers in isolation.
## Architectural Rules

* Prefer end-to-end, self-contained stories.
* Avoid "infrastructure-only" stories: when an AI agent proposes work-items, prefer the smallest, simplest change needed to enable the feature. Each story should add the minimal scope and be independently verifiable via automated tests and BDD scenarios.

## Output Requirements

- Create the plan as a new markdown file (e.g. `docs/plans/plan-{number}-{featureTitle}.md`).
- The plan must contain exactly **1 feature** (MVP) with all required stories.
- Follow `example-hierarchy.md` for structure and formatting.
- Improve and refine the feature description — format it consistently and professionally for use as the feature description in Azure DevOps.
- Mark each story with realistic story points following the estimation guidelines in the Story Rules section.

---

*Generated by `docs/promptCreatePlanFeatureMarkdownThisProject.ps1` — 2026-04-23 07ː34*
