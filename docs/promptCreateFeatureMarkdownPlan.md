## Instructions

- Modify plan `feature-plan.md` (create a new file), following the rules in `docs/createMarkdownPlan.md`, following instructions for the feature below.
- Important: We only want 1 feature (MVP) in the new plan, containing all the required stories.

### Resources
- **Example plan**: See `example-hierarchy.md` for reference formatting
- **Template generator**: Use `src/GenerateAzDoMarkdownHierarchyTemplate.ps1` to generate a markdown template to modify

### Story Design Principles
- See `docs\createStoryRules.md` for rules to follow when creating stories.
- Each story must represent a complete vertical slice (silo) from UI to backend when possible
- Do not create stories that only modify backend or database structure without corresponding presentation layer changes that actually use those modifications—include both in the same story
- Design stories as minimum viable chunks (MVP)—smallest acceptable unit that delivers value

### Output Format
- Improve and refine the feature content/description; format it consistently and professionally for use as the actual feature description in Azure DevOps
- Follow the formatting and structure defined in `docs/createMarkdownPlan.md`

## Azure DevOps Configuration
- **Organization**: falco-it
- **Project**: GMD
- **Epic ID**: AB#1305
- **PAT Token**: `($env:GMD_AZDO_MACHINE_WORKITEMSRW | ssEncryptDecrypt.ps1 -Decrypt)`
- **Scripts location**: `src/`

## Feature Specifications

### Goal
Build an auth service net 8 web api MVP, using SqlServer db as backend. Read the existing epic and features to get the idea. Some additions worth mentioning:
- Have 1 admin login seeded in db with password; We need a simple way to create a hash that we can seed with, e.g. just a Nunit test that creates a hash for a hardcoded string (that we temporarily change manually to create a hash).
- If we have the Family todo website as an example, a user should be able to login to that website using Google OpenID Connect.
- The goal of the AuthService is just to let users authenticate, not authorize, with a central auth service provider. Then each app can then tie custom roles within each app domain, but we want to avoid users having to register passwords in each separate app, hence the need of AuthService.
- Keep this MVP, do not create stories for testing/pipeline/logging/deploying. Assume all this is already set up, and each story should have its dedicating testing and db structure as a silo according to the rules.
- Include story for creating a simple demo web app do demonstrate usage of the auth service.
