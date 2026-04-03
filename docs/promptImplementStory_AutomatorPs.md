Implement the story following ALL rules in C:\Dev\own\GDrive\Privat\Dev\gh\Gmd.Tools.AzureDoAutomatorPs-1\docs\implementStoryRules.md, Do not ask me to confirm.

**CRITICAL:** Always fetch the latest story details and acceptance criteria from Azure DevOps. Do NOT use embedded story content or memory — retrieve the story from AzDo first and verify the current state before implementing. When done always update the story in azureDo and verify each AC and scenario and once verified check them with ✅ in AzureDO. Use the available scripts in src/ for updating stories in AzureDo.

## Required Process
1. **Read and apply implementStoryRules.md** — understand branching strategy, work item cleanup, TDD cycle, testing, and documentation requirements
2. **Setup** — create feature branch (if on develop), verify environment, understand parent feature/epic context
3. **Implement** — follow TDD cycle, check off Acceptance Criteria as completed, write automated tests for AC Scenarios
4. **Verify** — ensure all tests pass, validate AC items are testable and verified, check off AC Scenarios with test method names
5. **Document** — update README.md if applicable, add summary comment to the story with test table
6. **Validate** — provide a checklist showing ✓/✗ for compliance with each rule from the file

## Azure DevOps Configuration
- Org: falco-it | Proj: GMD
- PAT: `$env:GMD_AZDO_MACHINE_WORKITEMSRW | ssEncryptDecrypt.ps1 -Decrypt`
- Scripts location: C:\Dev\own\GDrive\Privat\Dev\gh\Gmd.Tools.AzureDoAutomatorPs-1\src

## Story Context
- Story ID: AB#TBD

## Implementation Approach
- Use Test-Driven Development (TDD) cycle when implementing
- Prefer automated tests over manual verification
- Group related test files in folders by functionality
 - For .NET projects: ensure `dotnet build -c Release` succeeds without errors.
 - If a `dev.runsettings` file exists at the repository root, run tests with `dotnet test -s dev.runsettings` instead of plain `dotnet test`.

## Acceptance Criteria Verification
- For each AC item, implement code to satisfy the criterion
- Verify with automated test when possible
- Check off the item (`✅`) in the story with test method name suffix (e.g., `GivenInputIsInvalid_ItShouldThrowException`), and any notes if adding value
- If an AC item cannot be implemented, update with strike-through and comment explaining why

## AC Scenarios Verification
- For each Gherkin/BDD scenario, write an automated integration test, preferably with ReqNRoll (if such project exists).
- Check off the scenario (`✅`) with test method name suffix
- Format: `- ✅ Scenario: [title] 🧪 [TestMethodName]`
- Ensure test files are organized in test folders grouped by functionality

## Documentation & Completion
- Check if README.md needs updates based on implementation
- Add ONE comment to the story with:
  - Brief summary of what was implemented
  - Table of test files/methods that verify the AC Scenarios
- Update existing comment instead of adding new ones
- Do NOT commit changes (user must do this manually)

## Validation Checklist
- [ ] All AC items are checked off in AzureDO story field (or marked as not implemented with explanation)
- [ ] All AC Scenarios are checked off in AzureDO story field with test method name suffix
- [ ] All automated tests pass
- [ ] No compiler warnings in implemented code
- [ ] No test work items left behind (verified cleanup)
- [ ] Created feature branch if on develop
- [ ] README.md updated (if applicable)
- [ ] Story comment added with implementation summary and test table
- [ ] All external-facing types/members have XML documentation comments
- [ ] The functionality has been implemented and verified for  all work item types (epic/feature/story/task/bug), in all related scripts utilizing these types.
