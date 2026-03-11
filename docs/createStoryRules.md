# General rules
- **One story should contain the full scope for a unit of work:** All layers needed for a feature to be testable and complete (db/backend/validation/frontend/unit tests/bdd tests).
- This ensures stories are independently verifiable and don't create dependencies between stories.
- A story should NOT be split across multiple epics or "wait for another story" to be testable.

# Story fields to set
- All fields should be written with multi-line markdown.

## Description
- Should contain 3-line persona layout (`**As a** ... **I want** ... **So that** ...`)
- May contain headers with content e.g. `### Problem` and `## Solution`.


## Acceptance Criteria
- Acceptance Criteria **must be written as a markdown table** with 4 columns:
  | ✅ | What is Verified | Test(s) | Notes |
  |---|-----------------|---------|-------|
  | [ ] | (Describe what is verified) | (Test name or method) | (Any notes) |
- Prefer items that can be verified automatically; only diverge if the story nature doesn't allow it (e.g., "Create CI pipeline").
- Include ONLY explicit criteria specific to this story's business logic or requirements.
- **Do NOT include general criteria** such as:
  - `Code should compile` (implicit in all work)
  - `Code should be performant` (vague; add specific performance benchmarks if required)
  - `Should have no warnings` (implicit code quality rule)
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
1. Identify what the Agent will do: Move files, generate code, update imports, write boilerplate, scaffold tests
2. Identify what the Human will do: Review PR, validate test logic, make architectural decisions, verify compilations, write/debug complex business logic
3. **The Human's time = the story points estimate.** Do NOT include Agent coding time.

### Examples for Clarity
| Task | Agent Does | Human Does | Points |
|------|---------|--------|--------|
| Move 3 classes, update imports | Move files, fix imports | Review changes, verify builds | 0.5 |
| Add validation function | Generate skeleton + boilerplate | Implement logic, write tests, verify | 2 |
| Create new endpoint (simple) | Scaffold handler, routing | Write logic, test integration | 1 |
| Complex feature with unknowns | Write code per Human's design | Architect solution, make decisions, review | 5+ |

## Tags
- Should be in format `camelCase`.
- Always include a tag indicating which epic it belongs to (should also exist in epic).
- If feature is not a "maintenance" feature, use a tag to "group" stories per epic.
- Shorten long words e.g., `prio` instead of `priority`.
