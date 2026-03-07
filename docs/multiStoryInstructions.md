If requested to implement all stories in a story, perform the following before/after steps for each story

# A1. Before starting working with the feature
1. Ensure we are in branch `develop`, and create a new branch for the entire feature `ssNewFeatBranch.ps1 -Ticket <featureId> -StoryDesc "<feature title>" -NoFetch -BaseBranch develop`.

# B1. Before starting implementing a story (within the feature)
1. Ensure we are in the base branch of the feature (i.e. not `develop`), e.g. `feat/ab#123-foo`
2. Create a new branch for the story `ssNewFeatBranch.ps1 -Ticket <storyId> -StoryDesc "<story title>" -NoFetch -BaseBranch 'ab#123-foo'`, note that BaseBranch is not `develop` here.

# C1. After implementing a story
1. Stage all changes that are to be committed (i.e. remove temporary test/debug files etc.).
2. Commit the changes with the generated commit message.
3. Generate a commit message by calling `ssAiCommitMsg.ps1` (by default it is copied to clipboard, but it also returned as output).
4. Commit the changes with the generated commit message.
5. Ensure you have verified the ACs, and updated the story in AzureDo (as described in `docs/additionalAgentInstructions.md`, e.g. checking the listed ACs etc.).
5. Checkout the feature branch base (e.g. `feat/ab#123-foo`), and merge with --no-ff. Example: `git checkout feat/ab#123-foo; git merge feat/ab#124-storyTitle --no-fff`;
6. Continue from step B1.

# D1. After implementation of all stories are done
1. No pending changes should exist, and the branch for the feature should be checked out. Let user review changes and perform remaining actions.
