## Tags
- **For test work items:** Use `testWi` tag to mark any work items created for testing purposes (helps identify orphan items later).

## Acceptance Criteria — PowerShell-specific
- **Do NOT include** criteria that are implicit for all PS1 work in this project:
  - `Script should execute without errors` (always expected)
  - `Script should produce no PSScriptAnalyzer warnings` (implicit code quality rule)
  - `Parameters should have help text` (always expected for public scripts)
- **DO include** explicit, story-specific behavioral criteria, e.g.:
  - A specific parameter value produces a specific AzDo API call
  - Output written to the pipeline matches a specific object shape
  - A specific error/exception is thrown for invalid input
- **Always add a README AC item** when the story adds or modifies scripts, parameters, output shapes, config formats, or MCP tool parameters: `README.md is updated to reflect this story's changes`
- For data format requirements, follow the general data format and encoding rules in `createStoryRules_General.md`. For PowerShell specifically: always specify `ISO 8601 UTC` for dates — `ConvertFrom-Json` auto-converts date strings to `[DateTime]` objects which stringify with the local culture when not explicitly formatted.

## Story details (PowerShell)
### Script interface
- Document the public script interface explicitly: parameter names, types, mandatory/optional, and any `[Validate*()]` attributes.
- Describe expected pipeline output: object type, properties, or plain string output as relevant.
- If the script wraps an Azure DevOps API call, specify the endpoint, HTTP method, and key request/response fields.

### Pester tests
- Reference the Pester test file name and path in the AC.
- Use `Describe`/`Context`/`It` naming that reflects the Acceptance Test being verified.
- Prefer integration-level Pester tests that call the script with real (or mocked) AzDo responses over unit-testing internal helpers in isolation.
