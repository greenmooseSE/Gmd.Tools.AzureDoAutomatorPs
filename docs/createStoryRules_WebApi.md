## Acceptance Criteria — additions for C# / WebApi
- **Do NOT include** criteria that are implicit for all C# work:
  - `Code should compile` (always expected)
  - `Should have no warnings` (implicit code quality rule)
  - `Should have no compiler errors` (always expected)

## Story Points — C# / WebApi examples
These supplement the estimation examples in `createStoryRules_General.md`.

| Task | Agent Does | Human Does | Points |
|------|---------|--------|--------|
| Move 3 classes, update imports | Move files, fix imports | Review changes, verify builds | 0.5 |
| Add validation to existing endpoint | Generate skeleton + boilerplate | Implement logic, write tests, verify | 2 |
| Create new endpoint (simple) | Scaffold handler, routing | Write logic, test integration | 1 |
| Complex feature with unknowns | Write code per Human's design | Architect solution, make decisions, review | 5+ |

## Story details — C# / WebApi
### REST endpoints
- Each REST endpoint should be specified with a detailed and complete OpenAPI v3 spec, including example strings, formats, status codes, etc.

### Database
- Use detailed schema suitable for SqlServer: table names, column names, column types, indexes, and a short description.
- Assume the latest version of Entity Framework is used to map C# objects to the database — include any required EF configuration details or attribute usage.
