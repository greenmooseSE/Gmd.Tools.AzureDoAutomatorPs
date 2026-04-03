## Instructions

Create a markdown plan for a feature and its child stories, following the rules in `docs/createMarkdownPlan.md`.

### Resources
- **Example plan**: See `example-hierarchy.md` for reference formatting
- **Template generator**: Use `src/GenerateAzDoMarkdownHierarchyTemplate.ps1` to generate a markdown template to modify

### Story Design Principles
- Each story must represent a complete vertical slice (silo) from UI to backend when possible
- Do not create stories that only modify backend or database structure without corresponding presentation layer changes that actually use those modifications—include both in the same story
- Design stories as minimum viable chunks (MVP)—smallest acceptable unit that delivers value

### Output Format
- Improve and refine the feature content/description; format it consistently and professionally for use as the actual feature description in Azure DevOps
- Follow the formatting and structure defined in `docs/createMarkdownPlan.md`

## Azure DevOps Configuration
- **Organization**: falco-it
- **Project**: GMD
- **Epic ID**: AB# (specify the work item ID)
- **PAT Token**: `($env:GMD_AZDO_MACHINE_WORKITEMSRW | ssEncryptDecrypt.ps1 -Decrypt)`
- **Scripts location**: `src/`

## Feature Specifications

### Goal
Enable exporting the Azure DevOps hierarchy (epics, features, stories, and tasks) to markdown format, allowing modification of any content, then resyncing the changes back to Azure DevOps.

### Architecture Principles
- Reuse existing scripts (e.g., `GetAzDoHierarchyFor*.ps1`) when possible; modify them as needed
- Fail fast—never risk corrupting data in Azure DevOps

### Functionality Requirements
- **State field support**: Support the State field for work items
  - Define a list of "writable" states with defaults: New, Planning, Planning Done, Ready for Development
  - States must be configurable via a JSON configuration file at the repository root level
  - Mapping should be per organization and project to allow different projects to define different states
- **WorkItemId preservation**: Support WorkItemId so titles can be changed while still matching the correct work item during synchronization
- **Test coverage**: Create tests that verify the behavior by:
  - Creating a temporary new epic with a hierarchy in the test setup
  - Running tests against this test data
  - Cleaning up (removing the epic) during teardown

## Implementation Notes
- After creating stories, update any existing TODO comments in the codebase that reference this feature or stories. Use the format: `//TODO: (AB#123) - Story Title`
- Refer to related documentation for additional context: `docs/createMarkdownPlan.md` and `docs/implementStoryRules.md`
