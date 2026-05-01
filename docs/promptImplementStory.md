Implement the story following ALL rules in C:\Dev\own\GDrive\Privat\Dev\gh\Gmd.Tools.AzureDoAutomatorPs-1\docs\implementStoryRules.md.

**CRITICAL:** Always fetch the latest story details and acceptance criteria from Azure DevOps. Do NOT use embedded story content or memory — retrieve story AB#TBD from AzDo first and verify the current state before implementing.

## Required Process
1. **Read and apply implementStoryRules.md** — understand branching strategy, work item cleanup, TDD cycle, testing, and documentation requirements
2. **Setup** — create feature branch (if on develop), verify environment, understand parent feature/epic context
3. **Implement** — follow TDD cycle, check off Acceptance Criteria as completed, write automated tests for Acceptance Tests
4. **Verify** — ensure all tests pass, validate AC items are testable and verified, check off Acceptance Tests with test method names
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
- Create feature branch if on develop branch: `ssNewFeatBranch.ps1 -Ticket <workItemId> -Description "<story title>" -NoFetch -BaseBranch develop -IsStory`
- Prefer automated tests over manual verification
- Group related test files in folders by functionality
 - For .NET projects: ensure `dotnet build -c Release` succeeds without errors.
 - If a `dev.runsettings` file exists at the repository root, run tests with `dotnet test -s dev.runsettings` instead of plain `dotnet test`.

## Acceptance Criteria Verification
- For each AC item, implement code to satisfy the criterion
- Verify with automated test when possible
- Check off the item (`[x]`) in the story with test method name suffix (e.g., `GivenInputIsInvalid_ItShouldThrowException`)
- If an AC item cannot be implemented, update with strike-through and comment explaining why

## Acceptance Tests Verification
- For each Gherkin/BDD scenario, write an automated integration test, preferably with ReqNRoll (if such project exists).
- Check off the scenario (`- [x]`) with test method name suffix
- Format: `- [x] Scenario: [title] 🧪 [TestMethodName]`
- Ensure test files are organized in test folders grouped by functionality


## Documentation & Completion
- Check if README.md needs updates based on implementation
- Add ONE comment to the story with:
  - Brief summary of what was implemented
  - Table of test files/methods that verify the Acceptance Tests
- Update existing comment instead of adding new ones

## Validation Checklist
- [ ] All AC items are checked off (or marked as not implemented with explanation)
- [ ] All Acceptance Tests are checked off with test method name suffix
- [ ] All automated tests pass
- [ ] No compiler warnings in implemented code
- [ ] No test work items left behind (verified cleanup)
- [ ] Created feature branch if on develop
- [ ] README.md updated (if applicable)
- [ ] Story comment added with implementation summary and test table
- [ ] All external-facing types/members have XML documentation comments
