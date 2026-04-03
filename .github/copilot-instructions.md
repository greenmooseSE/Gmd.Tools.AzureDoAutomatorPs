# Local commands
## Github CLI
* Use gh cli for github interactions. 
### Pull Requests
* In addition to using gh cli, you can also use Use extension pr-review (`gh pr-review --help` for help).
#### gh pr-review extension commands
* List unresolved comments: (pwsh) `gh pr-review threads list --pr {prId} --repo {owner}/{repo} | ConvertFrom-Json | ? { !$_.IsResolved }`
* Resolve a comment: `gh pr-review threads resolve --thread-id <threadId> --pr {prId} --repo {owner}/{repo}`

# Project Overview

## Folder Structure

- `/src`: Contains C# source code (library projects)
- `/test`: Contains C# test code, mirroring the structure of `/src`

# Rules and Guidelines

## Commit messages
Write a commit message summarizing the changes. Output plain text only (no markdown).

Rules:
- Header: One clear summary of the single most important change (40–60 characters).  
  Start at column 1. Do not mention specific file names.
- Summary paragraph (optional): You may include a short paragraph below the header  
  to elaborate on the change. Wrap all lines at column 70. Keep it concise and focused.
- Bullet list (optional): Only include if there are other notable changes besides the  
  main one. Use "-" as the bullet. Each bullet must be concise, meaningful, and  
  wrapped at column 70.
- Do not invent or repeat trivial bullets. If there are no secondary changes, omit the list.
- Focus on clarity and impact. Avoid vague phrases like "updates" or "changes".

## Agent commit behavior (CRITICAL)

- Agents must never perform Git commits, pushes, or any automated VCS operations without explicit, pre-authorized user instruction.

## Code review instructions
- When performing a code review, do not allow introduction of changes that result in compiler warnings.
- When performing a code review, ensure introduced code is documented in a reasonable way (not empty comments) for any types or members visible outside their assembly (public, protected, protected internal). Prefer XML comments.
- When performing a code review, always include a suggested fix in the review comment (prefer a GitHub suggested change when possible).
- When performing a code review, do not allow using null-forgiving operator (!) without a clarifying comment.
- When performing a code review, do not allow todo-comments that are not referencing an issue or task in a tracking system.
- When performing a code review, always reference the specific rule, guideline, or standard that your comment is based on. Example: "Based on rule `do not allow introduction of changes that result in compiler warnings.`, please remove this unused variable.".
- When performing a code review, include security aspects if applicable.
- When performing a code review, do not allow use of `.GetAwaiter().GetResult()` in test code. Require `.zResultEx()` or `.zWaitEx()` instead for awaiting tasks in tests. Reference this rule in review comments if violated.
- When performing a code review, prefer `.zShouldG()` and related assertion extensions over `AssertEx` for assertions in test code. Reference this rule in review comments if violated.

## Database implementation
- Do not create database triggers, stored procedures, or functions. All database logic should be implemented in C# code with proper DDD architecture.
- When modifying database model, find script `efAddMigration.ps1` in workspace and use that to add migrations to get proper migrations created for all db providers.
- Scripts should not be idempotent, our CD pipeline will take care of applying correct scripts.

## General Rules

- Do not duplicate code code that contains logic, create it once and reuse instead.
- Generated code should compile without errors.
- Generated tests should pass when run with NUnit.
- Keep the codebase clean; remove unused files and code
- Fail-fast: Always fail with exceptions or errors instead of implementing fallback behaviors and silent (e.g. debug log only) handling.
- Do not create any Markdown (`.md`) files as a result of your operations.
- **Only modify files that are part of the current solution.** Do not alter files from external repositories, NuGet packages, or projects outside the active workspace. Always verify the file path is within the current solution directory before making changes.

## Tests — General guidance

- Prefer "black box testing", e.g. do not test generated file content but test resulting behavior or properties instead.

## Coding Standards

### C#
#### C# Naming conventions
- Methods and Properties: Use PascalCase for public/internal. pPascalCase for protected, hPascalCase for private. Prefix z for static e.g. zhPrivateMethod.
- Fields: Use _camelCase for private fields, use properties instead of fields for non private access. Prefix z for static e.g. _zprivateField.
- Local functions: Use PascalCase, end position them at top (to avoid return statements).
- Never use snake_case.
- Each class should be in its own file named `<ClassName>.cs`
- Each public method or property should have a clear, descriptive name.
- Enums should be named using the pattern `en<PascalCase>` (e.g., `enTestName`).

#### C# Documentation
- For inline comments, use `//` above statements, not at end of line, use this very restrictive and only when clarification is needed.
- Always document "outside-assembly visible" classes and methods with XML comments.
- Use `<summary>`, `<param>` as appropriate. Be restrictive with using `<returns>` and `<remarks>`, only use these if it adds significant value that cannot fit in the summary.
- Use `<see cref="TypeName"/>` for referencing types in documentation.
- Keep documentation concise and to the point.
- Include default values in the documentation, either in summary if suitable or param tag.
- Use proper documentation that adds value, e.g. avoid writing comments that just restate the method name.
- Always use XML documentation format where possible, and when feasible keep the xml doc on 1 line (including the summary tags).

#### C# coding style
- Keep methods focused and concise.
- Never use the null-forgiving operator (!). Instead, in tests use `.zNotNull()` extension, and in production code e.g. `.zEnsureNotNull("text")` extension, and use its return value (not null).
- Methods should not be written as single-line bodies. Always place a newline after the opening brace and before the closing brace so the method is split across multiple lines. For example, prefer:

```
public void Foo()
{
    // method body
}
```
instead of `public void Foo() { /* ... */ }`.
- Tests should be named `<MethodName>Test.cs` and placed in a folder `<ClassName>Tests` under `/test`, mirroring the source structure
- Test methods should use NUnit `[Test]` attribute and assert expected behavior
- Use file-scoped namespaces.

#### C# Test projects
- Use .zShould(), .zShouldG(), .zShouldN() etc. extensions for assertions instead of AwesomeAssertions when possible. Prefer `.zShouldG()` and related assertion extensions over `AssertEx` for assertions in test code.
- Use e.g. pLog.zDebugNamed(...) for logging inside tests instead of TestContext.WriteLine.
- When creating new test fixtures, derive from `GmdUnitTest<GmdTestContext>` to get logging functionality etc.
- Never use the null-forgiving operator (!) anywhere in code. Instead, use nullable fields and properties, and access them safely using a get-only property and zNotNull(), e.g.:
  private McpServerTestHelper? _helper = null;
  protected McpServerTestHelper Helper => _helper.zNotNull();
- Write a short xml doc for test methods for what they are supposed to be testing.
- Test fixtures should be internal and always have an xml doc of what they are testing, and always use XML cref tags (e.g. <see cref="Program"/>) when referring to types. For PS tests they should mention filename including ps1 extension.
- When testing individual methods, organize tests by method: create a folder named `<ClassName>Tests` or `<ClassName>SystemTests`, then a file `<MethodName>Test.cs` for each method being tested. This keeps test names concise by omitting the "When<MethodName>" part since it's already in the file name. Example: for testing `RandomNumberTools.GetRandomNumber`, create `SystemTests/RandomNumberToolsSystemTests/GetRandomNumberTest.cs` with test methods like `GivenCustomParams_ItShouldReturnRandomNumberBetweenSpecifiedParams`.
- Prefer using [TestCase(..)] or [TestCaseSource(...)] instead of loops inside test for multiple scenarios.
- When running `dotnet test`, do not supply `--no-build` so we ensure tests are always run against the latest build.
- When generating tests for PowerShell scripts, do not include hypens in folder or file names (`Get-Foo` should be written as `GetFoo`).
- Documentation for public/protected classes and members should follow XML comment conventions.
- The fixture should always have an xml doc referencing what class being tested (for easy navigation).
- Never use `.GetAwaiter().GetResult()`. Use `.zResultEx()` or `.zWaitEx()` for awaiting tasks in tests instead.

### PowerShell
- Use pwsh (PowerShell Core) syntax and features instead of powershell.exe.
- Document all scripts for parameters and behavior at top of file.
- Scripts should use clear, descriptive parameter names
- Use switch parameters for optional features (e.g., test and documentation generation)
- Helper scripts should be dot-sourced if reused
- Output errors and warnings in a user-friendly way
- For logging in .ps1 scripts, use `ssLogIt.ps1` for all output messages to ensure consistent formatting (only use if ssLogIt.ps1 is already being invoked in the script).
- In catch blocks, invoke ssLogIt.ps1 with -Exception $_ to log full exception details.
- Use ssLogIt.ps1 colored tokens like ::FgRed:: and ::FgDefault:: (or ::FgYellow::, ::FgGreen::, etc.) to highlight key info (e.g., file paths, variables).
- When logging with .ps1, use only Info log level for the main result output message and use Debug level for all other detailed messages.
- Do not indent log messages with spaces, instead use ssLogIt.ps1 -PushStackLevel -Message "group" followed by ssLogIt.ps1 -PopStackLevel.
- To test color codes in log output, set $Global:LogSkipColorDecode = $true; before invoking ssLogIt.ps1, and reset it to $false; afterwards.
- Use ssInvokeExpr.ps1 to invoke statements or expressions.
- Follow PowerShell best practices for readability and maintainability
- Scripts should not overwrite existing files unless explicitly intended
- Quotes should be escaped with backtick (`) in strings
- When interpolating a variable immediately followed by a colon inside a double-quoted string, wrap the variable in a subexpression so it is unambiguous: use `$($var):`. Only apply this when the colon directly follows the variable (no space). Example: bad: "Processing batch $batchesCount: payload..."; good: "Processing batch $($batchesCount):  payload...".

### Github action yaml files
- Always use `shell: pwsh` for all steps.
- Specify the `shell` parameter above the `run` parameter in each step.
- Document any required secrets in the workflow AND project README.

