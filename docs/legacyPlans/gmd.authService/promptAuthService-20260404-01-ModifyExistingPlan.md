## Instructions

- Modify plan `docs\legacyPlans\gmd.authService\plan-azdoHierarchy-20260404-01.md` (create a new file in same dir), following the rules in `docs/createMarkdownPlan.md` and `docs/createStoryRules.md`.
- Create **ONE feature (MVP)** containing all core stories needed for a functional authentication service, reusing/modify existing stories where possible. This is the minimum viable scope—avoid stories for deployment, logging, monitoring, or testing infrastructure (assumed to exist).
- You are only allowed to modify stories with state NEW. If you need to change a story that is released, a new story to modify the behavior is required.

### Resources
- **Example plan**: See `example-hierarchy.md` for reference formatting
- **Template generator**: Use `src/GenerateAzDoMarkdownHierarchyTemplate.ps1` to generate a markdown template to modify
- **Story rules**: See `docs/createStoryRules.md` for general story field guidelines
- **Plan structure rules**: See `docs/createMarkdownPlan.md` for markdown formatting

### Story Design Principles
- **Follow `docs/createStoryRules.md`** — this file defines all general rules for story structure, fields, and estimation.
- For a **backend service** (like AuthService), each story represents a complete vertical slice **from API contract to database and back**. Unlike UI-driven features, this service doesn't have a presentation layer; instead, vertical slices are defined by API endpoints or complete feature workflows:
  - Each story should include: API endpoint implementation, business logic, database schema/migrations, and automated tests (unit + integration)
  - Stories may span multiple related endpoints if they represent a single logical unit (e.g., "Login + Refresh Token" can be one story)
- Design stories as **minimum viable chunks**—smallest independently testable unit that delivers value
- **Avoid stories for infrastructure only**: Testing, CI/CD pipelines, logging frameworks, and deployment are assumed to exist; include testing and DB validation as part of each story instead

## Azure DevOps Configuration
- **Organization**: falco-it
- **Project**: GMD
- **Epic ID**: AB#1305
- **PAT Token**: `($env:GMD_AZDO_MACHINE_WORKITEMSRW | ssEncryptDecrypt.ps1 -Decrypt)`
- **Scripts location**: `src/`

## Feature Specifications

### Overview: AuthService MVP
Build a **Net 8 Web API** using **SQL Server** as the backend that provides a centralized authentication service. This service:
- Authenticates users via **Google OpenID Connect** only (no password-based authentication)
- Issues **RS256-signed JWT tokens** containing `user_id` and `email` claims
- Provides a **JWKS endpoint** for public key distribution (for token validation by consuming services)
- Manages **refresh token lifecycle** with rotation and revocation
- Exposes **REST API endpoints** that consuming BFF backends call (e.g., Family Todo website)
- Publishes a rest api client lib for BFF backends to use (generated from open api yaml contracts).

### Key Principles
- **Scope is BACK-END ONLY** — No web UI required. This is an API service consumed by other backends/BFFs.
- **Central Authentication Provider** — Goal is to let users authenticate once and be recognized across multiple apps. Authorization (roles, permissions) remains per-app.
- **Avoid Password Management** — Users log in with their existing Google account; this service never stores user passwords.
- **Include Testing & DB per Story** — Each story must include: database schema (migrations), business logic, API endpoints, and automated tests (unit + integration/BDD).
- **No Infrastructure Stories** — Skip stories for: CI/CD pipelines, logging frameworks, deployment infrastructure, or general testing setup. Assume these exist; focus on feature business logic.

### Required Stories (MVP Scope)
The following are the **core story categories** for the MVP. Each should be independently testable and include database schema, business logic, endpoints, and automated tests:

- **Database Schema (EF Core Migration)**  
  The initial database schema should be created via EF Core migrations in a story "EF Core migration creates MVP schema" (or already exists). This includes: `Users` table, `RefreshTokens` table, and any supporting tables. Verify this story already covers the necessary schema; if not, prioritize it.
  
- **Admin User Seeding**  
  Create mechanism to generate password hashes (e.g., NUnit test utility that outputs hash for a hardcoded password). Seed **exactly one hardcoded admin user** into the database. This admin account is for system initialization only.
  
- **Google OpenID Connect Authentication**  
  Implement login endpoint that: receives a Google-signed ID token → validates the signature → extracts `user_id` from Google account → issues JWT + refresh token to calling BFF. Enforce that only verified Google emails (`email_verified = true`) are accepted.
  
- **JWT Token Generation & JWKS Distribution**  
  Implement endpoint to issue RS256-signed JWT tokens containing `user_id` and `email` claims (sufficient to identify the same user in consuming systems; no additional claims required for MVP). Implement JWKS endpoint for consuming services to download the public key and validate tokens independently.
  
- **Refresh Token Lifecycle**  
  Implement endpoint to refresh expired access tokens: accept a refresh token → validate it (check expiry, revocation status) → issue a new access token. Refresh tokens are stored as SHA-256 hashes (never plain text), with an expiration policy and revocation flag. Replace or rotate the refresh token as appropriate (agent should use best judgment if not specified).
  
- **Demo/Example Web App**  
  Create a simple ASP.NET web app with a basic UI that demonstrates AuthService integration: user clicks "Login via AuthService" → is redirected to Google login → returns to app authenticated → displays user info (user_id, email). The frontend **never communicates directly with AuthService**; all calls originate from the app's backend.

### Feature Description (for Azure DevOps)
When writing the feature summary in the markdown output, include:
- Clear explanation of what the feature delivers (authentication via Google, JWT tokens, refresh handling)
- Why it matters (centralized auth across multiple apps, no per-app password management)
- High-level architecture or data flow if helpful
- Reference to the auth service's role (backend-only API consumed by BFFs, never by client code)

### AI Agent Best-Effort Decisions
For any architectural or implementation decisions **not explicitly covered** in this prompt or in `docs/createStoryRules.md`, the AI agent should:
- Make reasonable, sensible choices aligned with industry best practices and the MVP scope
- Document those choices in code comments or commit messages if significant
- Prioritize simplicity and correctness over premature optimization
- When in doubt, follow patterns already established in related projects (e.g., `Gmd.Chassi.DotNet` submodule) for consistency
