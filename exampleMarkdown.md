# Epic: Epic Title 
**tags**: tbd\
**Effort**: 21\
**Description**\
### The epic subtitle 1
The epic description here\
with **markdown support**

### The epic subtitle 2 - architecture

```
          │
    ┌─────▼─────┐
    │  Database │
    └───────────┘
```

## Feature: 🏗️ CI Pipeline & Build (001)

**tags**: infrastructure, ciPipeline, build\
**Effort**: 2\
**Description**\
Ensure the solution builds, all tests pass, and artifacts are published in the CI pipeline.\
The Azure DevOps pipeline template is already referenced; this feature validates the end-to-end flow.\
This must be green before any other work begins.

### Story: 🔧 CI pipeline builds solution and runs tests (001)

**tags**: ci, build, pipeline\
**SP**: 2\
**Description**\
As a developer\
I want the CI pipeline to build the solution and run all tests\
So that every commit is validated automatically.

#### Acceptance Criteria
- [ ] `dotnet build TheSln.sln` completes without errors
- [ ] `dotnet test TheSln.sln` runs all NUnit tests and reports results
- [ ] Pipeline YAML (`ci-azure-pipeline.yaml`) is configured with correct solution path
- [ ] Test results are published as pipeline artifacts
- [ ] All introduced code has unit/integration test coverage

#### AC Scenarios
1. **Scenario**: Solution builds successfully\
   Given the CI pipeline triggers on a commit\
   When `dotnet build TheSln.sln` executes\
   Then the build should complete with exit code 0\
   And no compiler warnings should be present

2. **Scenario**: All tests pass in CI\
   Given the CI pipeline has built the solution\
   When `dotnet test TheSln.sln` executes\
   Then all tests should pass\
   And test results should be published as pipeline artifacts

#### Extra Information
- The CI template `base-ci-dotnet-web.yaml` from `buildTemplates` is already referenced.
- `paramSlnFile: TheSln.sln` is set.
- Verify `paramPublishBuildArtifacts: true` produces the expected API artifact for CD.
