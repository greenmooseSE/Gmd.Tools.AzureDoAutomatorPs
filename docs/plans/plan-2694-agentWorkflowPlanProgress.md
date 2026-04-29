# Epic: Gmd.Tools.AzureDoAutomatorPs
{WorkItemId}: 1577
{State}: New

## Feature: AI Agent Plan-Progress Workflow Scripts
{WorkItemId}: 2694
{State}: New
{tags}: azDoAutomator, agentWorkflow, planProgress, epicAzDoAutomator
{Effort}: 21
{Priority}: 1

### {Description}
AI agents frequently skip mandatory steps when implementing stories: they modify plan markdown  
directly (introducing formatting errors or incorrect state transitions), skip git branching,  
forget to mark ACs as completed, or skip test verification. This feature introduces a strict  
set of helper scripts in `src/agentWorkflow/` that enforce the correct lifecycle. AI agents  
are instructed to use ONLY these scripts and never modify plan files or run git commands directly.

#### Goals
- Prevent AI agents from manually editing plan markdown files  
- Enforce correct git branching workflow  
- Enforce AC/Acceptance-Test verification before marking stories complete  
- Provide test coverage verification before completion  
- Provide markdown integrity validation  
- Enable selective AzureDO sync (single story, not entire hierarchy)  

#### Script Overview (`src/agentWorkflow/`)

| Script | Purpose |
|--------|---------|
| `StartStory.ps1` | Create story branch, update plan state/assignee, sync to AzDO |
| `MarkACCompleted.ps1` | Mark one or multiple ACs as completed/warning/skipped in plan |
| `MarkAcceptanceTestCompleted.ps1` | Mark acceptance test done with test file path verification |
| `RunStoryTests.ps1` | Run tests with coverage, report missing lines, fail if coverage decreases |
| `CompleteStory.ps1` | Verify all ACs/tests done, merge to feature branch, sync state to AzDO |
| `ValidatePlanIntegrity.ps1` | Detect unauthorized manual plan modifications |
| `UpdateStoryInPlan.ps1` | Safely update a specific story in a plan markdown by WorkItemId |
| `SyncStoryToAzDo.ps1` | Sync a single story (by WorkItemId) from plan to AzDO, not entire hierarchy |

#### Markdown Parsing Helpers (in same folder)

| Script | Purpose |
|--------|---------|
| `GetStoryFromPlan.ps1` | Extract a single story block from a plan by WorkItemId |
| `SetStoryFieldInPlan.ps1` | Update a specific field value for a story in plan markdown |
| `ComparePlanChecksum.ps1` | Compare plan file checksum against stored baseline to detect tampering |

### {Feature Acceptance Tests}
- [ ] **Test 1: Full story lifecycle via scripts (happy path)**  
  1. Create a test plan markdown with one feature and two stories.  
  2. Run `StartStory.ps1` for story 1 — verify branch created, state updated.  
  3. Run `MarkACCompleted.ps1` for each AC — verify plan updated.  
  4. Run `MarkAcceptanceTestCompleted.ps1` with a valid test file.  
  5. Run `RunStoryTests.ps1` — verify coverage check passes.  
  6. Run `CompleteStory.ps1` — verify merge to feature branch, AzDO sync.  

- [ ] **Test 2: CompleteStory fails if ACs not all marked**  
  1. Start a story, mark only 1 of 2 ACs.  
  2. Run `CompleteStory.ps1`.  
  3. Verify it fails with a clear error listing unmarked ACs.  

- [ ] **Test 3: ValidatePlanIntegrity detects manual modification**  
  1. Run `StartStory.ps1` (which stores a checksum).  
  2. Manually edit the plan file.  
  3. Run `ValidatePlanIntegrity.ps1`.  
  4. Verify it fails with a message indicating unauthorized modification.  

- [ ] **Test 4: SyncStoryToAzDo updates only the targeted story**  
  1. Create a plan with 2 stories.  
  2. Modify fields for story 1 only.  
  3. Run `SyncStoryToAzDo.ps1 -WorkItemId {story1Id}`.  
  4. Verify only story 1 is updated in AzDO; story 2 is unchanged.  

---

### Story: Implement StartStory.ps1
{WorkItemId}: 2695
{State}: New

{tags}: azDoAutomator, agentWorkflow, epicAzDoAutomator
{Effort}: 3
{Priority}: 1

#### {Description}
Create `src/agentWorkflow/StartStory.ps1` that performs the following steps when an AI agent  
begins implementing a story:  
1. Validate current branch is the feature branch (or create story branch from feature branch).  
2. Create a story branch named `story/ab#<WorkItemId>-<camelCaseTitle>` from feature branch.  
3. Update the plan markdown: set `{State}: Active`, set `{Assigned To}: <identity>`.  
4. Store a checksum of the plan file for integrity validation.  
5. Sync the story state to Azure DevOps via existing scripts.  

Parameters:
- `-PlanFile` (mandatory): Path to the plan markdown.
- `-WorkItemId` (mandatory): The story's work item ID.
- `-AssignedTo` (optional): Identity to assign. Default: current user from PAT.
- `-FeatureBranch` (optional): Feature branch name. Auto-detected if on one.

#### {Acceptance Criteria}
| Status | Criteria |
|--------|----------|
| | Script creates story branch from feature branch |
| | Script fails if not on feature branch and -FeatureBranch not specified |
| | Plan file state is updated to Active |
| | Plan file Assigned To is updated |
| | Checksum file is stored (e.g., `.planstate/<WorkItemId>.checksum`) |
| | Story state is synced to Azure DevOps |
| | Script uses ssLogIt.ps1 for all output |
| | Script fails fast if story WorkItemId not found in plan |

#### {Acceptance Tests}
```gherkin
Scenario: Start story creates branch and updates plan
  Given a plan file with story 9999 in state New
  And the current branch is feat/ab#1234-someFeature
  When StartStory.ps1 -PlanFile plan.md -WorkItemId 9999
  Then branch story/ab#9999-storyTitle is created
  And plan file shows {State}: Active for story 9999
  And .planstate/9999.checksum exists

Scenario: Start story fails when not on feature branch
  Given the current branch is develop
  When StartStory.ps1 -PlanFile plan.md -WorkItemId 9999
  Then the script throws an error about feature branch requirement
```

---

### Story: Implement MarkACCompleted.ps1
{WorkItemId}: 2696
{State}: New

{tags}: azDoAutomator, agentWorkflow, epicAzDoAutomator
{Effort}: 2
{Priority}: 1

#### {Description}
Create `src/agentWorkflow/MarkACCompleted.ps1` that marks one or multiple Acceptance Criteria  
items as completed, with optional warnings or skipped status, in the plan markdown file.

Parameters:
- `-PlanFile` (mandatory): Path to plan markdown.
- `-WorkItemId` (mandatory): The story's work item ID.
- `-ACIndex` (mandatory): 1-based index (or array of indices) of the AC rows to update.
- `-Status` (optional): One of `Completed`, `Warning`, `Skipped`. Default: `Completed`.
- `-Note` (optional): Text appended to the AC row (e.g., test name or skip reason).

The script updates the AC table row(s) setting the Status column to the appropriate marker  
(✅ for Completed, ⚠️ for Warning, ⏭️ for Skipped) and appending the note.

#### {Acceptance Criteria}
| Status | Criteria |
|--------|----------|
| | Script updates AC table status column in plan markdown |
| | Supports marking multiple ACs in a single invocation |
| | Validates ACIndex is within range |
| | Validates plan integrity (checksum) before modifying |
| | Updates checksum after modification |
| | Supports Completed/Warning/Skipped statuses |
| | Note text is appended to the criteria cell |
| | Script fails if story not found in plan |

#### {Acceptance Tests}
```gherkin
Scenario: Mark single AC as completed
  Given a plan with story 9999 having 3 ACs all unmarked
  When MarkACCompleted.ps1 -PlanFile plan.md -WorkItemId 9999 -ACIndex 2 -Note "TestName"
  Then AC row 2 shows ✅ status and contains "TestName"
  And AC rows 1 and 3 remain unmarked

Scenario: Mark AC as skipped with reason
  Given a plan with story 9999 having 3 ACs
  When MarkACCompleted.ps1 -PlanFile plan.md -WorkItemId 9999 -ACIndex 1 -Status Skipped -Note "Not applicable for PS"
  Then AC row 1 shows ⏭️ status and contains "Not applicable for PS"

Scenario: Invalid ACIndex fails
  Given a plan with story 9999 having 3 ACs
  When MarkACCompleted.ps1 -PlanFile plan.md -WorkItemId 9999 -ACIndex 5
  Then the script throws an error about invalid AC index
```

---

### Story: Implement MarkAcceptanceTestCompleted.ps1
{WorkItemId}: 2697
{State}: New

{tags}: azDoAutomator, agentWorkflow, epicAzDoAutomator
{Effort}: 2
{Priority}: 1

#### {Description}
Create `src/agentWorkflow/MarkAcceptanceTestCompleted.ps1` that marks an acceptance test  
scenario as completed, verifying the test file actually exists and the test passes.

Parameters:
- `-PlanFile` (mandatory): Path to plan markdown.
- `-WorkItemId` (mandatory): The story's work item ID.
- `-TestIndex` (mandatory): 1-based index of the acceptance test scenario to mark.
- `-TestFile` (mandatory): Full path to the test file containing the test.
- `-TestName` (optional): Name of the specific test/It block. If provided, verifies it exists in file.
- `-SkipExecution` (switch): Skip actually running the test (useful if already run by RunStoryTests).

The script:
1. Validates plan integrity checksum.
2. Verifies `-TestFile` exists on disk.
3. Optionally verifies `-TestName` exists in the test file.
4. Optionally runs the test and verifies it passes.
5. Updates the acceptance test entry in the plan with ✅ and test file reference.
6. Updates checksum.

#### {Acceptance Criteria}
| Status | Criteria |
|--------|----------|
| | Script verifies test file exists on disk |
| | Script fails if test file does not exist |
| | Script optionally verifies test name exists in file content |
| | Script optionally runs the test and fails if test fails |
| | Updates acceptance test entry with ✅ and test path |
| | Validates and updates plan checksum |
| | Fails if TestIndex out of range |

#### {Acceptance Tests}
```gherkin
Scenario: Mark acceptance test with valid test file
  Given a plan with story 9999 having 2 acceptance tests
  And a test file exists at test/SomeTests/SomeTest.ps1
  When MarkAcceptanceTestCompleted.ps1 -PlanFile plan.md -WorkItemId 9999 -TestIndex 1 -TestFile test/SomeTests/SomeTest.ps1
  Then acceptance test 1 shows ✅ with file path reference
  And plan checksum is updated

Scenario: Fails when test file does not exist
  Given a plan with story 9999 having 2 acceptance tests
  When MarkAcceptanceTestCompleted.ps1 -PlanFile plan.md -WorkItemId 9999 -TestIndex 1 -TestFile test/NonExistent.ps1
  Then the script throws an error about missing test file
```

---

### Story: Implement RunStoryTests.ps1
{WorkItemId}: 2698
{State}: New

{tags}: azDoAutomator, agentWorkflow, epicAzDoAutomator
{Effort}: 3
{Priority}: 1

#### {Description}
Create `src/agentWorkflow/RunStoryTests.ps1` that runs tests relevant to the current story  
with coverage analysis. It uses an external helper script for coverage measurement and reports  
missing coverage lines.

Parameters:
- `-PlanFile` (mandatory): Path to plan markdown.
- `-WorkItemId` (mandatory): The story's work item ID.
- `-TestPath` (optional): Explicit test path(s). If omitted, auto-detect from plan test references.
- `-CoverageBaseline` (optional): Path to baseline coverage file. If provided, fails on decrease.
- `-CoverageScript` (optional): Path to external coverage helper script. Default: well-known location.

The script:
1. Discovers or accepts test paths.
2. Runs tests via `Invoke-Pester` with coverage enabled.
3. Compares coverage to baseline (if provided).
4. Reports uncovered lines to stdout in a structured format.
5. Fails if coverage decreases below baseline.
6. Returns structured result (pass/fail, coverage %, uncovered files/lines).

#### {Acceptance Criteria}
| Status | Criteria |
|--------|----------|
| | Runs Pester tests with -CodeCoverage |
| | Reports coverage percentage |
| | Reports uncovered lines per file |
| | Fails if coverage decreases vs baseline |
| | Accepts explicit test paths or auto-detects from plan |
| | Output uses ssLogIt.ps1 |
| | Returns structured object with results |

#### {Acceptance Tests}
```gherkin
Scenario: Tests pass with adequate coverage
  Given a story with tests that cover 90% of new code
  And baseline coverage is 85%
  When RunStoryTests.ps1 -PlanFile plan.md -WorkItemId 9999
  Then the script succeeds
  And reports coverage at 90%

Scenario: Tests fail when coverage decreases
  Given a story with tests that cover 70% of new code
  And baseline coverage is 85%
  When RunStoryTests.ps1 -PlanFile plan.md -WorkItemId 9999 -CoverageBaseline baseline.xml
  Then the script fails
  And reports which lines are not covered
```

---

### Story: Implement CompleteStory.ps1
{WorkItemId}: 2699
{State}: New

{tags}: azDoAutomator, agentWorkflow, epicAzDoAutomator
{Effort}: 3
{Priority}: 1

#### {Description}
Create `src/agentWorkflow/CompleteStory.ps1` that finalizes a story implementation:
1. Validates ALL ACs are marked (Completed or Skipped — not unmarked).
2. Validates ALL Acceptance Tests are marked.
3. Validates tests pass (calls RunStoryTests.ps1 internally or accepts -SkipTests).
4. Updates plan state to Resolved.
5. Syncs the story to Azure DevOps (state, AC checkmarks, acceptance test checkmarks).
6. Merges story branch back to feature branch.
7. Deletes the story branch.

Parameters:
- `-PlanFile` (mandatory): Path to plan markdown.
- `-WorkItemId` (mandatory): The story's work item ID.
- `-SkipTests` (switch): Skip test execution (if already verified).
- `-SkipMerge` (switch): Skip the git merge step (useful for dry-run).

#### {Acceptance Criteria}
| Status | Criteria |
|--------|----------|
| | Fails if any AC is not marked (Completed, Warning, or Skipped) |
| | Fails if any Acceptance Test is not marked |
| | Runs tests unless -SkipTests specified |
| | Updates plan state to Resolved |
| | Syncs story to AzDO via SyncStoryToAzDo.ps1 |
| | Merges story branch to feature branch |
| | Deletes story branch after merge |
| | Provides clear error messages listing what is incomplete |

#### {Acceptance Tests}
```gherkin
Scenario: Complete story succeeds when all checks pass
  Given a story with all ACs marked ✅ and all tests marked ✅
  And all Pester tests pass
  When CompleteStory.ps1 -PlanFile plan.md -WorkItemId 9999
  Then plan state is Resolved
  And story branch is merged to feature branch
  And story is synced to AzDO

Scenario: Complete story fails with unmarked ACs
  Given a story with 1 of 3 ACs unmarked
  When CompleteStory.ps1 -PlanFile plan.md -WorkItemId 9999
  Then the script fails
  And error message lists the unmarked AC
```

---

### Story: Implement ValidatePlanIntegrity.ps1
{WorkItemId}: 2700
{State}: New

{tags}: azDoAutomator, agentWorkflow, epicAzDoAutomator
{Effort}: 2
{Priority}: 2

#### {Description}
Create `src/agentWorkflow/ValidatePlanIntegrity.ps1` that detects unauthorized plan  
modifications by comparing the current file hash against the stored checksum.

Parameters:
- `-PlanFile` (mandatory): Path to plan markdown.
- `-WorkItemId` (optional): If specified, only validate checksum for that story's last operation.
- `-Strict` (switch): When set, ANY change outside agentWorkflow scripts is treated as a failure.

The script:
1. Reads stored checksum from `.planstate/<WorkItemId>.checksum` (or global plan checksum).
2. Computes current file hash.
3. Compares and reports match/mismatch.
4. In -Strict mode, fails on mismatch.
5. In non-strict mode, warns but continues.

#### {Acceptance Criteria}
| Status | Criteria |
|--------|----------|
| | Detects plan modifications since last agentWorkflow operation |
| | Uses SHA256 hash comparison |
| | Stores checksums in .planstate/ directory |
| | -Strict mode fails on mismatch |
| | Non-strict mode emits warning on mismatch |
| | Reports which story was being worked on when baseline was set |

#### {Acceptance Tests}
```gherkin
Scenario: Clean plan passes validation
  Given StartStory.ps1 was run and no manual edits occurred
  When ValidatePlanIntegrity.ps1 -PlanFile plan.md -WorkItemId 9999
  Then validation passes

Scenario: Modified plan fails in strict mode
  Given StartStory.ps1 was run and the plan was manually edited
  When ValidatePlanIntegrity.ps1 -PlanFile plan.md -WorkItemId 9999 -Strict
  Then the script fails with integrity violation message
```

---

### Story: Implement GetStoryFromPlan.ps1 and SetStoryFieldInPlan.ps1
{WorkItemId}: 2701
{State}: New

{tags}: azDoAutomator, agentWorkflow, markdownParsing, epicAzDoAutomator
{Effort}: 2
{Priority}: 1

#### {Description}
Create markdown parsing helpers in `src/agentWorkflow/`:

**GetStoryFromPlan.ps1**: Extract a single story's complete markdown block from a plan file.
- `-PlanFile` (mandatory): Path to plan markdown.
- `-WorkItemId` (mandatory): Work item ID to locate.
- Returns: The raw markdown text for that story (from header to next sibling/parent header).

**SetStoryFieldInPlan.ps1**: Update a specific field value for a story in the plan.
- `-PlanFile` (mandatory): Path to plan markdown.
- `-WorkItemId` (mandatory): Work item ID of the story.
- `-FieldName` (mandatory): Field label (e.g., "State", "Assigned To").
- `-Value` (mandatory): New field value.
- Updates the field in-place. Fails if field not found for that story.

These helpers are used internally by other agentWorkflow scripts and not directly by AI agents.

#### {Acceptance Criteria}
| Status | Criteria |
|--------|----------|
| | GetStoryFromPlan extracts correct story block by WorkItemId |
| | GetStoryFromPlan fails gracefully if WorkItemId not found |
| | SetStoryFieldInPlan updates existing field value in-place |
| | SetStoryFieldInPlan fails if field does not exist for the story |
| | SetStoryFieldInPlan preserves all other content unchanged |
| | Both scripts handle multi-line field values (Description, AC) |

#### {Acceptance Tests}
```gherkin
Scenario: Extract story from plan by WorkItemId
  Given a plan with stories 1001, 1002, 1003
  When GetStoryFromPlan.ps1 -PlanFile plan.md -WorkItemId 1002
  Then the output contains only story 1002's markdown block
  And does not contain content from stories 1001 or 1003

Scenario: Update state field in plan
  Given a plan with story 1002 having {State}: New
  When SetStoryFieldInPlan.ps1 -PlanFile plan.md -WorkItemId 1002 -FieldName "State" -Value "Active"
  Then the plan file shows {State}: Active for story 1002
  And all other content is unchanged
```

---

### Story: Implement SyncStoryToAzDo.ps1
{WorkItemId}: 2702
{State}: New

{tags}: azDoAutomator, agentWorkflow, epicAzDoAutomator
{Effort}: 2
{Priority}: 1

#### {Description}
Create `src/agentWorkflow/SyncStoryToAzDo.ps1` that syncs a single story from a plan to  
Azure DevOps, without syncing the entire hierarchy.

Parameters:
- `-PlanFile` (mandatory): Path to plan markdown.
- `-WorkItemId` (mandatory): Work item ID to sync.
- `-DryRun` (switch): Show what would be synced without making changes.
- `-Fields` (optional): Array of field labels to sync. Default: all mapped fields.

The script:
1. Extracts the story from the plan (via GetStoryFromPlan.ps1).
2. Parses its fields.
3. Maps fields to Azure DevOps field references via appSettings.json configuration.
4. Calls the appropriate Upsert/Set scripts to update only the targeted work item.
5. Reports what was synced.

#### {Acceptance Criteria}
| Status | Criteria |
|--------|----------|
| | Only syncs the specified WorkItemId, not siblings or parent |
| | Maps plan field labels to AzDO reference names via appSettings.json |
| | Updates State, Assigned To, Acceptance Criteria, Acceptance Tests, Description |
| | DryRun mode shows diff without making API calls |
| | Fails gracefully if WorkItemId not found in plan |
| | Logs each field update via ssLogIt.ps1 |

#### {Acceptance Tests}
```gherkin
Scenario: Sync single story updates only that work item
  Given a plan with stories 1001 and 1002
  And story 1001 has local changes
  When SyncStoryToAzDo.ps1 -PlanFile plan.md -WorkItemId 1001
  Then story 1001 is updated in Azure DevOps
  And story 1002 is not modified in Azure DevOps

Scenario: DryRun shows planned changes
  Given a plan with story 1001 having State: Active
  And AzDO story 1001 has State: New
  When SyncStoryToAzDo.ps1 -PlanFile plan.md -WorkItemId 1001 -DryRun
  Then output shows "State: New -> Active" without making API calls
```

---

### Story: Update prompt templates and README to enforce agentWorkflow usage
{WorkItemId}: 2703
{State}: New

{tags}: azDoAutomator, agentWorkflow, docs, epicAzDoAutomator
{Effort}: 2
{Priority}: 1

#### {Description}
Update all AI agent prompt templates and README.md to:
1. Clearly instruct agents to use `src/agentWorkflow/` scripts for ALL plan modifications.
2. Explicitly forbid direct plan file edits.
3. Explicitly forbid direct git commands (branch, merge, push).
4. Document the full workflow lifecycle using the scripts.
5. Provide a quick-reference table of scripts and when to use them.

Files to update:
- `docs/promptImplementStory.md`
- `docs/promptImplementStory_ThisProject.md`
- `docs/promptImplementFeature_ThisProject.ps1`
- `docs/promptImplementFeature_WebApiCs.ps1`
- `docs/implementStoryRules.md`
- `docs/implementStoryRules_ThisProject.md`
- `docs/multiStoryInstructions.md`
- `README.md` (add new section documenting agentWorkflow scripts)
- `.github/copilot-instructions.md` (add agentWorkflow rules)

#### {Acceptance Criteria}
| Status | Criteria |
|--------|----------|
| | All prompt templates instruct agents to use agentWorkflow scripts |
| | All prompt templates explicitly forbid manual plan edits |
| | All prompt templates explicitly forbid direct git branch/merge/push commands |
| | README.md documents the agentWorkflow folder and all scripts |
| | README.md includes usage examples for each script |
| | copilot-instructions.md includes agentWorkflow rules |
| | docs/multiStoryInstructions.md references agentWorkflow lifecycle |

#### {Acceptance Tests}
```gherkin
Scenario: Prompt templates reference agentWorkflow scripts
  Given docs/promptImplementStory_ThisProject.md
  When searching for "agentWorkflow"
  Then at least 3 references to agentWorkflow scripts are found
  And the text "NEVER modify plan files directly" appears

Scenario: README documents all agentWorkflow scripts
  Given README.md
  When searching for each script name (StartStory, MarkACCompleted, etc.)
  Then all 8 main scripts are documented with parameter descriptions
```

---

### Story: Implement ComparePlanChecksum.ps1
{WorkItemId}: 2704
{State}: New

{tags}: azDoAutomator, agentWorkflow, epicAzDoAutomator
{Effort}: 1
{Priority}: 2

#### {Description}
Create `src/agentWorkflow/ComparePlanChecksum.ps1` as a standalone utility to compare  
plan checksums. This is a lightweight wrapper used by other scripts and can also be called  
directly by agents to verify plan state before proceeding.

Parameters:
- `-PlanFile` (mandatory): Path to plan markdown.
- `-WorkItemId` (optional): Specific story context. If omitted, uses global plan checksum.
- `-Update` (switch): Update the stored checksum to current state (after verified operations).

Returns: Object with `IsValid` (bool), `StoredHash`, `CurrentHash`, `Message`.

#### {Acceptance Criteria}
| Status | Criteria |
|--------|----------|
| | Computes SHA256 of plan file |
| | Compares against stored hash in .planstate/ |
| | Returns structured result object |
| | -Update switch stores new hash |
| | Creates .planstate/ directory if missing |
| | Works with both per-story and global checksums |

#### {Acceptance Tests}
```gherkin
Scenario: Checksum matches after agentWorkflow operation
  Given a checksum was stored by StartStory.ps1
  And no manual edits occurred
  When ComparePlanChecksum.ps1 -PlanFile plan.md -WorkItemId 9999
  Then result.IsValid is true

Scenario: Update stores new checksum
  Given an outdated checksum
  When ComparePlanChecksum.ps1 -PlanFile plan.md -Update
  Then the stored hash matches the current file hash
```

