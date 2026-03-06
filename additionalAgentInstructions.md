* If current branch is develop, start with creating a new branch via helper `ssNewFeatBranch.ps1 -Ticket 1580 -StoryDesc "Consolidate Feature Create/Update to UpsertAzDoFeature" -NoFetch -BaseBranch develop` , this will properly crate a new feature branch for tracking purposes (helper it exists in path, can be found via Get-Command)
* Check for the parent feature and parent epic to better understand the context.
* When implementing a story, try to do TDD cycle as much as possible.
* Don't forget to update Readme.md when needed.
* Mark the "Acceptance Criteria" checkboxes as you go along, you don't have to wait for entire work to complete before checking them.
* Ensure that each "Acceptance Criteria" is covered in a test script (when possible)
* Ensure each AC BDD Scenario ("AC Scenarios") is marked with ✅, but only after you have verified we have such test (and it is passing).
* Avoid Write-Error and Write-Host statements, prefer using ssLogIt.ps1 (can be found via Get-Command).
* Ensure that any work items created during tests are deleted during test teardown (even if test fails).
* When you have completed implementing the story, add a comment to the story with a short summary and a table of tests you crated to verify the BDD scenarios.
