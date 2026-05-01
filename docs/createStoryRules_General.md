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

## Acceptance Tests
- Write Gherkin/BDD scenarios in bullet list format `- [ ] **Scenario 1: Scenario title**  \nGiven ...  \nWhen ...  \nThen ...`.
- The scenarios should be explicit enough so they can be written as automated (integration) tests.

## Relationship Between AC Criteria and Acceptance Tests
- **AC Criteria** test individual conditions, properties, or validations in isolation (e.g., "Invalid email input should reject").
- **Acceptance Tests** test complete user workflows using Given-When-Then (Gherkin/BDD format).
- Typically, one Acceptance Test exercises multiple AC Criteria; they should complement—not duplicate—each other.
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


