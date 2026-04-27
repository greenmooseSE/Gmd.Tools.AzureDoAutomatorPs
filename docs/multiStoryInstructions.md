If requested to implement all stories in a feature, perform the following before/after steps for each story

# A1. Before starting working with the feature
1. Ensure we are in branch `develop`, and create a new branch for the entire feature `ssNewFeatBranch.ps1 -Ticket <featureId> -Description "<feature title>" -NoFetch -BaseBranch develop`.
   Branch naming: `feat/ab#<featureId>-<title>`

# B1. Before starting implementing a story (within the feature)
1. Ensure we are in the base branch of the feature (i.e. not `develop`), e.g. `feat/ab#123-foo`
2. Create a new branch for the story `ssNewFeatBranch.ps1 -Ticket <storyId> -Description "<story title>" -IsStory -NoFetch -BaseBranch 'ab#123-foo'`, note that BaseBranch is not `develop` here.
   Branch naming: `story/ab#<storyId>-<title>`

# C1. After implementing a story
1. Stage all changes that are to be committed (i.e. remove temporary test/debug files etc.).
2. Generate a commit message by calling `ssAiCommitMsg.ps1` (by default it is copied to clipboard, but it also returned as output).
3. Commit the changes with the generated commit message.
4. Ensure you have verified the ACs, and updated the story in AzureDo (as described in `docs/additionalAgentInstructions.md`, e.g. checking the listed ACs etc.).
5. Checkout the feature branch base (e.g., `feat/ab#123-foo`), and merge with --no-ff. Example: `git checkout feat/ab#123-foo; git merge story/ab#124-storyTitle --no-ff`;
6. Continue from step B1.

# D1. After implementation of all stories are done
1. No pending changes should exist, and the branch for the feature should be checked out. Let user review changes and perform remaining actions.
