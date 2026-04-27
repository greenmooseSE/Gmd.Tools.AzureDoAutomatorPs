## Architectural rules — C# / WebApi additions
These supplement `architecturalRules_General.md` for WebApi / database-backed projects.

* Prefer the smallest, simplest database model needed to enable the feature. Each story should add the minimal schema and be verifiable via integration tests (API) and BDD scenarios.
* Avoid "DB model" stories: do not create stories that only add or alter a database schema without corresponding API endpoints or application logic that consume it — include both in the same story.
