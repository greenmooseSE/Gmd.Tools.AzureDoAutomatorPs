# General rules
* If current branch is develop, start with creating a new branch via helper `ssNewFeatBranch.ps1 -Ticket 1580 -StoryDesc "Consolidate Feature Create/Update to UpsertAzDoFeature" -NoFetch -BaseBranch develop` , this will properly crate a new feature branch for tracking purposes (helper it exists in path, can be found via Get-Command)
* Check for the parent feature and parent epic to better understand the context.
* When implementing a story, try to do TDD cycle as much as possible.
* Don't forget to update Readme.md when needed.
* Mark the "Acceptance Criteria" checkboxes as you go along, you don't have to wait for entire work to complete before checking them.
* Ensure that each "Acceptance Criteria" is covered in a test script (when possible)
* Ensure each AC BDD Scenario ("AC Scenarios") is marked with ✅, you must not mark ACS as checked if they have been skipped or not implemented.
* Avoid Write-Error and Write-Host statements, prefer using ssLogIt.ps1 (can be found via Get-Command).
* Ensure that any work items created during tests are deleted during test teardown (even if tests fail). Tests must not leave persistent work items in the Azure DevOps project.
* Agents and test scripts that create work items must track the IDs of created items and remove them as part of teardown. If an automated agent detects leftover work items it created, the agent must attempt cleanup and report the cleanup status in the test output.
* Prefer grouping scenario test files in folders named/group by the functionality being tested.
* If we need explicit test file for a specific story, include story title as camelCase in the test file name, along with story id, and put them in a directory named `test/storyAcTests`.
* If an AC item is not implemented, indicate this with update with strikethrough and a comment, e.g. "- [ ] ~~AC item~~ (*Comment of why it was not implemented*)."
* Avoid using "#<number>" in an azDo comment, unless it is referencing a work item ID, escape it if not referencing a work item (e.g. "\#1").
* When creating work item for testing purposes (explicit or implicit via tests), ensure we add tag `testWi` to easy find any orphan test work items later if needed (not applicable if we need to explicitly test creating work item without tags).

# Work item comment rules
* When you have completed implementing the story, add a comment to the story with a short summary and a table of tests you crated to verify the BDD scenarios. But ensure you only have one comment per work item for this. Update existing instead of adding a new comment.
