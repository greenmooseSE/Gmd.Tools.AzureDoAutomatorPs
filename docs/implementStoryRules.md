# Org/Proj/PAT
* Use `$env:GMD_AZDO_ORGANIZATION`, `$env:GMD_AZDO_PROJECT`, and `$env:GMD_AZDO_MACHINE_WORKITEMSRW | ssEncryptDecrypt.ps1 -Decrypt`.

# General rules
* If current branch is develop, start with creating a new branch via helper e.g. `ssNewFeatBranch.ps1 -Ticket <workItemId> -StoryDesc "<story title>" -NoFetch -BaseBranch develop`.
* Do NOT commit anything, this should be manually done by user, unless you are explicitly instructed to create commits.
* Check for the parent feature and parent epic to better understand the context.
* When implementing a story, do the TDD cycle as much as possible.
* Avoid Write-Error and Write-Host statements, prefer using ssLogIt.ps1 (can be found via Get-Command).
* Ensure that any work items created during tests are deleted during test teardown (even if tests fail). Tests must not leave persistent work items in the Azure DevOps project.
* Agents and test scripts that create work items must track the IDs of created items and remove them as part of teardown. If an automated agent detects leftover work items it created, the agent must attempt cleanup and report the cleanup status in the test output.
* Prefer grouping scenario test files in folders named/group by the functionality being tested.
* If we need explicit test file for a specific story, include story title as camelCase in the test file name, along with story id, and put them in a directory named `test/storyAcTests`.
* Avoid using "#<number>" in an azDo comment, unless it is referencing a work item ID, escape it if not referencing a work item (e.g. "\#1").
* When creating work item for testing purposes (explicit or implicit via tests), ensure we add tag `testWi` to easy find any orphan test work items later if needed (not applicable if we need to explicitly test creating work item without tags).

## Story field "Acceptance Criteria" 
* Check off the items (`[x]`) as you implement them. Validate that you only check those items you are confident to have fixed/implemented/verified.
* Each item should be verified in a test script (when possible).
* If we have a test for it, also write the test method name suffix e.g. "(`GivenEmailIsInvalid_ItShouldThrowException`)".
* If an AC item is not implemented, do not check off that checkbox but instead indicate this with update with strike-through and a comment, e.g. `- [ ] ~~AC item~~ (*Comment of why it was not implemented*).`.

## Story field  "AC Scenarios" (Gherkin/BDD scenarios)
* Ensure each scenario is implemented in tests, check off the the items (`- [x]` or `✅`) and update scenario with suffix of test name (e.g. `- [x] Scenario: User logs in 🧪 ``GivenStartPage_WhenUserLogsIn_SystemUpdatesDbWithUserSession`` ` )

## When completed implementing a story
* Always update README.md when applicable.
* Add a comment to the story with a short summary and a table of tests you crated to verify the BDD scenarios. But ensure you only have one comment per work item for this. Update existing instead of adding a new comment.

