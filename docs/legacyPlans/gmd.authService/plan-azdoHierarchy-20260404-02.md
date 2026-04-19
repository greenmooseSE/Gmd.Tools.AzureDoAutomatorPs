# Epic: Gmd.AuthService
**WorkItemId**: 1305  
**tags**: clientLib; gmdAuthSvc; googleOpenId; jwt; mvp  
**Effort**: 40  
**State**: New  
**Description**  
Deliver a minimal viable authentication service that supports **Google OpenID Connect** as the sole identity provider.\  
The AuthService authenticates users via their Google account, creates/resolves a global `user_id`, and issues signed RS256 JWT access tokens\  
containing `user_id` and `email`. A reusable NuGet client library (`Gmd.AuthService.ClientLib`) encapsulates all interaction\  
with the AuthService — including token exchange, refresh-token handling, and JWT validation via JWKS — so that consuming BFF backends\  
(e.g. the Family Todo website) never duplicate this logic. **No end-user client ever contacts the AuthService directly**;\  
all calls originate from BFF backends using the client library.  
### Key Objectives
- &#128272; Google OpenID Connect authentication (reject `email_verified = false`)
- &#127903;️ RS256-signed JWT with `user_id` + `email` claims
- &#128273; JWKS endpoint for public key distribution
- &#128230; Reusable NuGet client library for consuming BFF backends
- &#128260; Refresh token lifecycle with rotation and revocation
- &#128683; No UI required on AuthService side
### Architecture Overview
```  
┌──────────────┐      ┌────────────────────┐      ┌──────────────────┐  
│  User Client │─────▶│  BFF Backend       │─────▶│  AuthService API │  
│  (Browser)   │      │  (Family Todo)     │      │  (this service)  │  
└──────────────┘      │                    │      │                  │  
                      │  Uses:             │      │  ─ Google OIDC   │  
                      │  Gmd.AuthService   │      │  ─ JWT signing   │  
                      │  .ClientLib NuGet  │      │  ─ JWKS endpoint │  
                      └────────────────────┘      │  ─ Refresh tokens│  
                                                  └──────────────────┘  
```  

## Feature: AuthService MVP (001)
**tags**: core; gmdAuthSvc; mvp  
**Effort**: 33  
**Description**  
### Overview
**As a** developer  
  
**I want** a complete, minimal-viable authentication service backed by SQL Server,  
using Google OpenID Connect as the sole identity provider  
  
**So that** users can authenticate once via Google and be recognized across multiple consuming apps  
  

### What This Feature Delivers
This feature covers the entire vertical slice from database schema to REST API to NuGet client library,  
including a demo app that exercises the end-to-end flow. The AuthService is a **backend-only API**;  
no end-user code ever calls it directly — all calls originate from BFF backends using the client library.  

### Data Flow
1. User clicks "Login with Google" on a BFF frontend
2. BFF backend obtains Google ID token on behalf of the user
3. BFF calls `POST /v1/auth/google` with the Google ID token
4. AuthService validates the token, resolves or creates the user record, and returns a JWT + refresh token
5. BFF stores the tokens (e.g. in HttpOnly cookies) and treats the user as authenticated
6. Subsequent requests: BFF validates the JWT via cached JWKS, or refreshes via `POST /v1/auth/refresh`

### Story Scope Summary
| # | Story | SP |
|---|-------|----|
| 001 | EF Core migration creates MVP schema | 2 (Released) |
| 002 | Create SigningKeys table for JWT signing | 1 |
| 003 | Create RefreshTokens table for session management | 2 |
| 004 | Seed initial admin user for system initialization | 0.5 |
| 005 | Google OAuth configuration | 1 |
| 006 | Authenticate via Google ID token | 5 |
| 007 | Generate RS256-signed JWT access tokens | 3 |
| 008 | JWKS endpoint exposes public signing keys | 1 |
| 009 | Persist and validate refresh tokens | 3 |
| 010 | Revoke refresh token on logout | 1 |
| 011 | API key authentication for BFF backends | 2 |
| 012 | Create client library project structure | 1 |
| 013 | AuthService HTTP client service | 2 |
| 014 | Automatic token refresh middleware | 3 |
| 015 | JWT validation helper using JWKS | 2 |
| 016 | Demo ASP.NET web app with Google login via AuthService | 3 |
| **Total** | | **32.5** |

### Story: EF Core migration creates MVP schema (001)
<!-- WARNING: State 'Released' is NOT in the writable states list for Story items.
     Writable states: New, Active, Design, Ready for Development, Under Development
     During reimport, any state changes will be ignored. Do NOT modify the state field. -->

**WorkItemId**: 1309  
**tags**: database; gmdAuthSvc; migration; p4; schema  
**SP**: 2  
**State**: Released ⚠️ (read-only)  
**Custom.ACScenarios**: - [x] **Scenario 1: Fresh database migration creates Users table with correct structure**
  Given a fresh database with no migrations
  When EF Core migration 'CreateUsersTable' is applied
  Then the Users table exists with all 7 columns (Id, GoogleSubjectId, Email, DisplayName, CreatedAtUtc, UpdatedAtUtc)
  Test: EfCoreMigrationCreatesMvpSchema1309Test verification + DbSet access

- [x] **Scenario 2: GoogleSubjectId uniqueness constraint is enforced**
  Given an existing user with GoogleSubjectId 'google123'
  When attempting to add a second user with the same GoogleSubjectId
  Then the database rejects the insert with DbUpdateException
  Test: BddScenario_GoogleSubjectIdUniqueness_GivenExistingUserWithSubjectId_WhenInsertingDuplicateSubjectIdThenExceptionIsThrown

- [x] **Scenario 3: Email uniqueness constraint is enforced**
  Given an existing user with email 'user@example.com'
  When attempting to add a second user with the same email
  Then the database rejects the insert with DbUpdateException
  Test: BddScenario_EmailUniqueness_GivenExistingUserWithEmail_WhenInsertingDuplicateEmailThenExceptionIsThrown

- [x] **Scenario 4: Timestamps are auto-set by database and CreatedAtUtc remains immutable**
  Given a new User entity without pre-set timestamp values
  When the user is saved to the database
  Then both CreatedAtUtc and UpdatedAtUtc are automatically set to current UTC time
  And when the user is later updated, CreatedAtUtc does not change
  Tests: BddScenario_DefaultTimestamps, BddScenario_CreatedAtUtcImmutable, BddScenario_UpdatedAtUtcIsActuallyUpdated

- [x] **Scenario 5: Timestamps are stored with proper precision across all database providers**
  Given a user with timestamp values saved to database
  When the user is retrieved from database
  Then timestamps are stored and retrieved as valid UTC DateTime values with precision preserved
  And the same behavior is consistent for SQLite, SQL Server, and SQL Server LocalDb
  Test: BddScenario_TimestampDateTimeKind_GivenPersistedUser_WhenRetrievedThenTimestampsAreUtc (parameterized across 5 provider fixtures)

- [ ] **Scenario 6: Migration is idempotent and can be safely applied multiple times**
  Given DbContext initialization in a clean state
  When EF Core migration is applied for the first, second, and third time
  Then no errors occur and the schema remains consistent
  Status: PENDING IMPLEMENTATION  
**Custom.ExtraInformation**: - `DesignTimeDbContextFactory` uses `(localdb)\MSSQLLocalDB` for migration tooling.
- The chassi library provides mutex-based migration guard for scaled-out deployments.  
**Description**  
#### Users Table Schema
**As a** developer  
  
**I want** the Users table to capture Google OAuth identity and profile information  
  
**So that** user sessions can be maintained and users identified across requests  
  

**Fields Required:**
  
- `Id` (BIGINT, PRIMARY KEY, IDENTITY, NOT NULL) - Auto-incrementing unique identifier
- `GoogleSubjectId` (VARCHAR(255), UNIQUE, NOT NULL) - OAuth subject identifier from Google
- `Email` (VARCHAR(255), UNIQUE, NOT NULL) - User email address
- `DisplayName` (VARCHAR(255), NULL, default: NULL) - User's display name
- `CreatedAtUtc` (DATETIME2(7), NOT NULL, default: GETUTCDATE()) - Record creation timestamp
- `UpdatedAtUtc` (DATETIME2(7), NOT NULL, default: GETUTCDATE()) - Last update timestamp

**Indexes Required:**
  
- Unique index on `GoogleSubjectId`
- Unique index on `Email`

#### Acceptance Criteria  
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ✅ | User entity has 7 properties (Id, GoogleSubjectId, Email, DisplayName, CreatedAtUtc, UpdatedAtUtc) | GivenUserEntity_WhenQueried_ThenAllSevenPropertiesExist | Via reflection |
| ✅ | Id is long (64-bit) for auto-increment | GivenUserEntity_WhenQueried_ThenIdPropertyIsLong | Large sequences |
| ✅ | GoogleSubjectId: non-nullable string, max 255 chars | GivenUserEntity_WhenQueried_ThenGoogleSubjectIdIsNonNullableString | OAuth subject, NOT NULL |
| ✅ | Email: non-nullable string, max 255 chars | GivenUserEntity_WhenQueried_ThenEmailIsNonNullableString | Email address, NOT NULL |
| ✅ | DisplayName: nullable string, max 255 chars | GivenUserEntity_WhenQueried_ThenDisplayNameIsNullableString | Optional user name |
| ✅ | CreatedAtUtc immutable on updates | BddScenario_CreatedAtUtcIsActuallyCreated, BddScenario_UpdatedAtUtcIsActuallyUpdated | Set at insert, never changes |
| ✅ | UpdatedAtUtc modified on updates | BddScenario_UpdatedAtUtcIsActuallyUpdated | Updated by database on each modification |
| ✅ | DbContext.Users DbSet configured | GivenGmdAuthServiceWebApiDbContext_WhenQueried_ThenUsersDbSetIsConfigured | Enables CRUD operations |
| ✅ | Primary key on Id property | GivenGmdAuthServiceWebApiDbContext_WhenQueried_ThenUserEntityHasPrimaryKeyConfigured | Auto-increment identity |
| ✅ | GoogleSubjectId unique index | GivenDuplicateGoogleSubjectId_WhenAddedToDatabase_ThenThrowsDbUpdateException | Prevents duplicate subjects |
| ✅ | Email unique index | GivenDuplicateEmail_WhenAddedToDatabase_ThenThrowsDbUpdateException | Prevents duplicate emails |
| ✅ | Database defaults for timestamps | BddScenario_DefaultValuesBothExist | GETUTCDATE for SQL Server, datetime('now') for SQLite |
| ✅ | Migrations for all 3 database providers | AllProviderMigrationsValidated | SQL Server, SQL Server LocalDb, SQLite |

#### AC Scenarios  
- [x] **Scenario 1: Fresh database migration creates Users table with correct structure**
  Given a fresh database with no migrations
  
  When EF Core migration 'CreateUsersTable' is applied
  
  Then the Users table exists with all 7 columns (Id, GoogleSubjectId, Email, DisplayName, CreatedAtUtc, UpdatedAtUtc)
  
  Test: EfCoreMigrationCreatesMvpSchema1309Test verification + DbSet access
  

- [x] **Scenario 2: GoogleSubjectId uniqueness constraint is enforced**
  Given an existing user with GoogleSubjectId 'google123'
  
  When attempting to add a second user with the same GoogleSubjectId
  
  Then the database rejects the insert with DbUpdateException
  
  Test: BddScenario_GoogleSubjectIdUniqueness_GivenExistingUserWithSubjectId_WhenInsertingDuplicateSubjectIdThenExceptionIsThrown
  

- [x] **Scenario 3: Email uniqueness constraint is enforced**
  Given an existing user with email 'user@example.com'
  
  When attempting to add a second user with the same email
  
  Then the database rejects the insert with DbUpdateException
  
  Test: BddScenario_EmailUniqueness_GivenExistingUserWithEmail_WhenInsertingDuplicateEmailThenExceptionIsThrown
  

- [x] **Scenario 4: Timestamps are auto-set by database and CreatedAtUtc remains immutable**
  Given a new User entity without pre-set timestamp values
  
  When the user is saved to the database
  
  Then both CreatedAtUtc and UpdatedAtUtc are automatically set to current UTC time
  
  And when the user is later updated, CreatedAtUtc does not change
  
  Tests: BddScenario_DefaultTimestamps, BddScenario_CreatedAtUtcImmutable, BddScenario_UpdatedAtUtcIsActuallyUpdated
  

- [x] **Scenario 5: Timestamps stored with proper precision across all database providers**
  Given a user with timestamp values saved to database
  
  When the user is retrieved from database
  
  Then timestamps are stored and retrieved as valid UTC DateTime values with precision preserved
  
  Test: BddScenario_TimestampDateTimeKind_GivenPersistedUser_WhenRetrievedThenTimestampsAreUtc
  

- [ ] **Scenario 6: Migration is idempotent and can be safely applied multiple times**
  Given DbContext initialization in a clean state
  
  When EF Core migration is applied for the first, second, and third time
  
  Then no errors occur and the schema remains consistent
  

#### Extra Information  
- `DesignTimeDbContextFactory` uses `(localdb)\MSSQLLocalDB` for migration tooling.
- The chassi library provides mutex-based migration guard for scaled-out deployments.

### Story: Create SigningKeys table for JWT token signing (002)
**WorkItemId**: 1310  
**tags**: gmdAuthSvc; rsa; signingKey; startup  
**SP**: 1  
**State**: New  
**Custom.ACScenarios**:  
1. ▢ **Scenario**: SigningKeys table is created with correct structure  
   Given a fresh SQL Server database with no tables  
   When the EF Core migration is applied  
   Then the `SigningKeys` table should exist  
   And the table should have exactly 7 columns  
   And `KeyId` unique index should exist  
   And `IsActive` index should exist
2. ▢ **Scenario**: KeyId uniqueness is enforced  
   Given the SigningKeys table exists  
   When inserting a record with KeyId = "signing-key-001"  
   Then the first insert succeeds  
   And a second insert with the same KeyId fails with constraint violation
3. ▢ **Scenario**: IsActive default value is applied  
   Given the SigningKeys table exists  
   When inserting a record without specifying IsActive  
   Then IsActive should default to 1 (true/active)
4. ▢ **Scenario**: Timestamps are automatically populated  
   Given the SigningKeys table exists  
   When inserting a record with CreatedAtUtc and ExpiresAtUtc not specified  
   Then CreatedAtUtc should be populated with current UTC time  
   And ExpiresAtUtc should be NULL
5. ▢ **Scenario**: Large PEM-encoded keys can be stored  
   Given the SigningKeys table exists  
   When inserting a record with a full 2048-bit RSA key pair (approximately 3KB for both keys)  
   Then the insert succeeds  
   And both PublicKey and PrivateKey fields store the complete keys
6. ▢ **Scenario**: Migration is idempotent  
   Given the SigningKeys table already exists  
   When the EF Core migration is applied again  
   Then the migration completes successfully  
   And no duplicate tables or indexes are created  
**Description**  
#### SigningKeys Table Schema
**As a** developer  
  
**I want** the SigningKeys table to store RSA key pairs for JWT token signing  
  
**So that** tokens can be signed and verified with cryptographic integrity  
  

**Fields Required:**
  
- `Id` (BIGINT, PRIMARY KEY, IDENTITY, NOT NULL) - Auto-incrementing identifier
- `KeyId` (VARCHAR(100), UNIQUE, NOT NULL) - External key identifier for JWT header
- `PublicKey` (TEXT, NOT NULL) - PEM-encoded RSA public key
- `PrivateKey` (TEXT, NOT NULL) - PEM-encoded RSA private key (2048-bit)
- `IsActive` (BIT, NOT NULL, default: 1) - Flag indicating if key is currently active
- `CreatedAtUtc` (DATETIME2(7), NOT NULL, default: GETUTCDATE()) - Key creation timestamp
- `ExpiresAtUtc` (DATETIME2(7), NULL, default: NULL) - Optional key expiration time

**Indexes Required:**
  
- Unique index on `KeyId`
- Index on `IsActive` for quick lookups of active keys

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ▢ | Migration creates `SigningKeys` table with exact schema (7 columns as specified) |  |  |
| ▢ | `Id` is PRIMARY KEY with IDENTITY(1,1) |  |  |
| ▢ | `KeyId` VARCHAR(100) with UNIQUE constraint |  |  |
| ▢ | `PublicKey` TEXT field (can hold full PEM-encoded RSA public keys) |  |  |
| ▢ | `PrivateKey` TEXT field (can hold full PEM-encoded RSA private keys) |  |  |
| ▢ | `IsActive` BIT field with default 1 |  |  |
| ▢ | `CreatedAtUtc` DATETIME2(7) with default GETUTCDATE() |  |  |
| ▢ | `ExpiresAtUtc` DATETIME2(7) nullable with default NULL |  |  |
| ▢ | Unique index on `KeyId` exists |  |  |
| ▢ | Non-unique index on `IsActive` exists |  |  |
| ▢ | Unit test verifies table structure matches schema |  |  |
| ▢ | Migration is idempotent |  |  |

#### AC Scenarios  
1. ▢ **Scenario**: SigningKeys table is created with correct structure
   Given a fresh SQL Server database with no tables
  
   When the EF Core migration is applied
  
   Then the `SigningKeys` table should exist
  
   And the table should have exactly 7 columns
  
   And `KeyId` unique index should exist
  
   And `IsActive` index should exist
  

2. ▢ **Scenario**: Large PEM-encoded keys can be stored
   Given the SigningKeys table exists
  
   When inserting a record with a full 2048-bit RSA key pair
  
   Then the insert succeeds
  
   And both PublicKey and PrivateKey fields store the complete keys
  

3. ▢ **Scenario**: Migration is idempotent
   Given the SigningKeys table already exists
  
   When the EF Core migration is applied again
  
   Then the migration completes successfully
  
   And no duplicate tables or indexes are created  

### Story: Create RefreshTokens table for session management (003)
**WorkItemId**: 1698  
**tags**: database; gmdAuthSvc; refreshToken; schema  
**SP**: 2  
**State**: New  
**Custom.ACScenarios**:  
1. ▢ **Scenario**: RefreshTokens table is created with correct structure  
   Given a fresh SQL Server database with no tables  
   When the EF Core migration is applied  
   Then the `RefreshTokens` table should exist in the database  
   And the table should have exactly 6 columns with correct names and types  
   And `TokenHash` unique index should exist  
   And composite index on (UserId, IsRevoked) should exist
2. ▢ **Scenario**: TokenHash uniqueness is enforced  
   Given the RefreshTokens table exists  
   When inserting a record with TokenHash = "abc123xyz"  
   Then the first insert succeeds  
   And a second insert with the same TokenHash fails with constraint violation
3. ▢ **Scenario**: Foreign key constraint on UserId is enforced  
   Given the RefreshTokens table exists  
   When inserting a record with UserId = 999 (non-existent user)  
   Then the insert fails with foreign key constraint violation
4. ▢ **Scenario**: IsRevoked default value is applied  
   Given the RefreshTokens table exists  
   When inserting a record without specifying IsRevoked  
   Then IsRevoked should default to 0 (not revoked/active)
5. ▢ **Scenario**: Timestamps are automatically populated  
   Given the RefreshTokens table exists  
   When inserting a record with CreatedAtUtc not specified  
   Then CreatedAtUtc should be populated with current UTC time
6. ▢ **Scenario**: Migration is idempotent  
   Given the RefreshTokens table already exists  
   When the EF Core migration is applied again  
   Then the migration completes successfully  
   And no duplicate tables or indexes are created  
**Description**  
#### RefreshTokens Table Schema
**As a** developer  
  
**I want** the RefreshTokens table to store refresh token state for session management  
  
**So that** users can obtain new access tokens without re-authenticating  
  

**Fields Required:**
  
- `Id` (BIGINT, PRIMARY KEY, IDENTITY, NOT NULL) - Auto-incrementing unique identifier
- `TokenHash` (VARCHAR(512), UNIQUE, NOT NULL) - SHA-256 hash of the actual refresh token
- `UserId` (BIGINT, NOT NULL, FOREIGN KEY) - Reference to Users.Id
- `ExpiresAtUtc` (DATETIME2(7), NOT NULL) - Token expiration timestamp
- `CreatedAtUtc` (DATETIME2(7), NOT NULL, default: GETUTCDATE()) - Token creation timestamp
- `IsRevoked` (BIT, NOT NULL, default: 0) - Flag indicating if token has been revoked

**Indexes Required:**
  
- Unique index on `TokenHash` (for lookups, never store plain token)
- Non-unique index on `UserId` (for user-scoped queries)
- Non-unique index on `IsRevoked` (for active token queries)
- Composite index on (UserId, IsRevoked) for efficient lookup of active tokens per user

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ▢ | Migration creates `RefreshTokens` table with exact schema (6 columns as specified) |  |  |
| ▢ | `Id` is PRIMARY KEY with IDENTITY(1,1) |  |  |
| ▢ | `TokenHash` VARCHAR(512) with UNIQUE constraint (prevents duplicate tokens) |  |  |
| ▢ | `UserId` BIGINT with NOT NULL constraint |  |  |
| ▢ | `ExpiresAtUtc` DATETIME2(7) with NOT NULL constraint |  |  |
| ▢ | `CreatedAtUtc` DATETIME2(7) with default GETUTCDATE() |  |  |
| ▢ | `IsRevoked` BIT field with default 0 |  |  |
| ▢ | Foreign key constraint exists from `UserId` to `Users.Id` |  |  |
| ▢ | Unique index on `TokenHash` exists |  |  |
| ▢ | Non-unique index on `UserId` exists |  |  |
| ▢ | Composite index on (UserId, IsRevoked) exists for efficient queries |  |  |
| ▢ | Unit test verifies table structure matches schema |  |  |
| ▢ | Migration is idempotent |  |  |

#### AC Scenarios  
1. ▢ **Scenario**: RefreshTokens table is created with correct structure
   Given a fresh SQL Server database with no tables
  
   When the EF Core migration is applied
  
   Then the `RefreshTokens` table should exist in the database
  
   And the table should have exactly 6 columns with correct names and types
  
   And `TokenHash` unique index should exist
  
   And composite index on (UserId, IsRevoked) should exist
  

2. ▢ **Scenario**: TokenHash uniqueness is enforced
   Given the RefreshTokens table exists
  
   When inserting two records with identical TokenHash values
  
   Then the second insert fails with a constraint violation
  

3. ▢ **Scenario**: Foreign key constraint on UserId is enforced
   Given the RefreshTokens table exists
  
   When inserting a record with UserId = 999 (non-existent user)
  
   Then the insert fails with foreign key constraint violation
  

4. ▢ **Scenario**: Migration is idempotent
   Given the RefreshTokens table already exists
  
   When the EF Core migration is applied again
  
   Then the migration completes successfully
  
   And no duplicate tables or indexes are created  

### Story: Seed initial admin user for system initialization (004)
**tags**: adminSeed; gmdAuthSvc; seeding  
**SP**: 0.5  
**State**: New  
**Custom.ACScenarios**:  
1. ▢ **Scenario**: Admin user is seeded on first startup  
   Given a clean database with no users  
   And `Seed:AdminUser:Email` is configured in appsettings  
   When the application starts  
   Then a user record exists in the Users table with the configured email  
   And `DisplayName` is set to "Admin"  
   And `GoogleSubjectId` is set to a placeholder value (empty string or configurable)
2. ▢ **Scenario**: Seeding is idempotent  
   Given the admin user already exists in the Users table  
   When the application starts again  
   Then no duplicate user record is created  
   And the existing record is not modified
3. ▢ **Scenario**: Startup fails fast when admin email is not configured  
   Given `Seed:AdminUser:Email` is missing or empty in appsettings  
   When the application attempts to start  
   Then startup fails with a clear error message indicating the missing configuration
4. ▢ **Scenario**: SHA-256 hash utility produces deterministic output  
   Given a test token string "test-refresh-token-abc123"  
   When the `TokenHashHelper.ComputeSha256Hash` method is called  
   Then the returned hash is the SHA-256 hex string of the input  
   And calling it twice with the same input returns the same hash  
**Custom.ExtraInformation**: - The `GoogleSubjectId` for the seeded admin user will be empty string initially and will be populated when the admin first authenticates via Google.
- The seeder is registered as a hosted service or equivalent startup hook using the chassi library pattern.
- `TokenHashHelper` is a static utility class in the test project providing SHA-256 hash generation for use in integration test data setup (seeds, refresh token fixtures).  
**Description**  
**As a** deployment engineer  
  
**I want** an initial admin user to be pre-seeded in the database on first startup  
  
**So that** the system has at least one registered user identity available upon deployment,  
and integration tests can reference a known user without going through Google authentication  
  

#### Implementation Details
- Register a `IHostedService` (or startup extension) that runs after EF migrations
- Check if `Users` table contains a record with `Email = adminEmail` (from config)
- If not found, insert a new `User` record with: `Email`, `DisplayName = "Admin"`, `GoogleSubjectId = ""`
- Read admin email from `Seed:AdminUser:Email` in `appsettings.json`; fail fast if missing or empty
- Provide a static `TokenHashHelper.ComputeSha256Hash(string input)` utility accessible in test projects  
for generating SHA-256 hash strings used in integration test data setup (e.g., seeding test refresh tokens)

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ▢ | Admin user is created with configured email on first startup |  |  |
| ▢ | Admin user `DisplayName` is "Admin" |  |  |
| ▢ | Seeding is idempotent — no duplicate on restart |  |  |
| ▢ | Startup fails if `Seed:AdminUser:Email` is missing |  |  |
| ▢ | `TokenHashHelper.ComputeSha256Hash` returns consistent SHA-256 hex |  |  |

#### AC Scenarios
1. ▢ Scenario: Admin user is seeded on first startup
  Given a clean database with no users  
  And `Seed:AdminUser:Email` is set to "admin@example.com" in appsettings  
  When the application starts  
  Then a user record exists in the `Users` table with `Email = "admin@example.com"`  
  And `DisplayName = "Admin"`  
  And `GoogleSubjectId = ""`  

2. ▢ Scenario: Seeding is idempotent
  Given the admin user already exists in the `Users` table  
  When the application starts again  
  Then no duplicate user record is created  
  And the total count of users with the admin email remains 1  

3. ▢ Scenario: Startup fails fast when admin email is not configured
  Given `Seed:AdminUser:Email` is missing from appsettings  
  When the application attempts to start  
  Then an exception is thrown with a message indicating the missing configuration  

4. ▢ Scenario: TokenHashHelper produces deterministic SHA-256 output
  Given the input string "test-token-abc123"  
  When `TokenHashHelper.ComputeSha256Hash` is called  
  Then the output is the expected SHA-256 hex string  
  And calling it again with the same input returns the identical hash  

### Story: Google OAuth configuration (005)
**WorkItemId**: 1318  
**tags**: configuration; gmdAuthSvc; googleOidc  
**SP**: 1  
**State**: New  
**Custom.ACScenarios**:  
1. ▢ **Scenario**: Service starts successfully with valid Google Client ID  
   Given `appsettings.json` has `Authentication:Google:ClientId` set to a valid value  
   When the API starts  
   Then the service should start successfully  
   And the Google authentication endpoint should be available
2. ▢ **Scenario**: Service fails fast when Google Client ID is missing  
   Given `appsettings.json` does not have `Authentication:Google:ClientId` configured  
   When the API attempts to start  
   Then the startup should fail with an exception  
   And the error message should indicate the missing Google Client ID configuration  
**Description**  
As a deployer\  
I want the Google OAuth Client ID to be configurable per environment\  
So that dev/staging/prod use separate Google projects.  

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ▢ | `appsettings.json` contains section `Authentication:Google:ClientId` |  |  |
| ▢ | The Google Client ID is read from configuration at startup and injected into the validation service |  |  |
| ▢ | If `Authentication:Google:ClientId` is missing or empty, the service fails fast at startup with a clear error message |  |  |
| ▢ | `appsettings.Development.json` contains a placeholder or local Client ID |  |  |
| ▢ | Tests verify fail-fast behavior on missing configuration |  |  |

#### AC Scenarios  
1. ▢ **Scenario**: Service starts successfully with valid Google Client ID  
   Given `appsettings.json` has `Authentication:Google:ClientId` set to a valid value\  
   When the API starts\  
   Then the service should start successfully\  
   And the Google authentication endpoint should be available  
2. ▢ **Scenario**: Service fails fast when Google Client ID is missing  
   Given `appsettings.json` does not have `Authentication:Google:ClientId` configured\  
   When the API attempts to start\  
   Then the startup should fail with an exception\  
   And the error message should indicate the missing Google Client ID configuration  

### Story: Authenticate via Google ID token (006)
**WorkItemId**: 1317  
**tags**: authentication; gmdAuthSvc; googleOidc; tokenExchange  
**SP**: 5  
**State**: New  
**Custom.ACScenarios**:  
1. ▢ **Scenario**: New user authenticates with valid Google ID token  
   Given the API is running  
   And no user exists with the Google subject ID from the token  
   When a BFF backend sends `POST /v1/auth/google` with a valid Google ID token where `email_verified` is `true`  
   Then the response status code should be 200  
   And a new user should be created in the database with the Google subject ID  
   And the response should contain a non-empty `accessToken`  
   And the response should contain a non-empty `refreshToken`  
   And the response should contain a `userId` matching the new user's ID  
   And the `accessToken` decoded should contain `sub` equal to the new user's ID  
   And the `accessToken` decoded should contain `email` equal to the Google email
2. ▢ **Scenario**: Returning user authenticates with valid Google ID token  
   Given the API is running  
   And a user already exists with a known Google subject ID  
   When a BFF backend sends `POST /v1/auth/google` with a valid Google ID token for that subject  
   Then the response status code should be 200  
   And no new user should be created  
   And the response `userId` should match the existing user's ID
3. ▢ **Scenario**: Google token with email_verified=false is rejected  
   Given the API is running  
   When a BFF backend sends `POST /v1/auth/google` with a Google ID token where `email_verified` is `false`  
   Then the response status code should be 400  
   And the response body should contain "Email not verified by Google"
4. ▢ **Scenario**: Invalid or expired Google token is rejected  
   Given the API is running  
   When a BFF backend sends `POST /v1/auth/google` with an invalid or expired Google ID token  
   Then the response status code should be 401  
   And the response body should contain "Invalid Google token"  
**Custom.ExtraInformation**: - Use the `Google.Apis.Auth` NuGet package (`GoogleJsonWebSignature.ValidateAsync`) for token validation.
- In integration tests, mock the Google token validation to avoid external dependencies.
- The Google ID token contains claims: `sub`, `email`, `email_verified`, `name`, `picture`, `iss`, `aud`.
- The `aud` claim must match the configured Google Client ID for the AuthService.
- Google Client ID should be configurable via `appsettings.json` under `Authentication:Google:ClientId`.  
**Description**  
As a BFF backend\  
I want to exchange a Google ID token for AuthService JWT tokens\  
So that I can identify and authenticate the user in my application.  

#### REST Endpoint
```yaml
POST /v1/auth/google
Content-Type: application/json
X-Api-Key: {bff-api-key}

Request:
  { "googleIdToken": "eyJ..." }

Response 200:
  {
    "accessToken": "eyJ...",
    "refreshToken": "dGVzdA==",
    "expiresAtUtc": "2026-04-04T15:00:00Z",
    "userId": 42
  }

Response 400:
  { "error": "Email not verified by Google" }

Response 401:
  { "error": "Invalid Google token" }
```

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ▢ | `POST /v1/auth/google` accepts `{ googleIdToken }` in the request body |  |  |
| ▢ | The service validates the Google ID token using `Google.Apis.Auth` (`GoogleJsonWebSignature.ValidateAsync`) |  |  |
| ▢ | If `email_verified` is `false` in the Google token claims, the request is rejected with 400 and message "Email not verified by Google" |  |  |
| ▢ | If the `GoogleSubjectId` (Google `sub` claim) already exists in the database, the existing user is resolved |  |  |
| ▢ | If the `GoogleSubjectId` does not exist, a new `User` record is created with `GoogleSubjectId`, `Email`, and `DisplayName` (from Google `name` claim) |  |  |
| ▢ | On success, returns 200 with `{ accessToken, refreshToken, expiresAtUtc, userId }` |  |  |
| ▢ | The `accessToken` is a valid RS256-signed JWT containing claims: `sub` (AuthService `user_id`), `email`, `jti`, `iat`, `exp`, `iss` |  |  |
| ▢ | If Google token validation fails (expired, invalid signature), return 401 with "Invalid Google token" |  |  |
| ▢ | Tests cover: new user creation, existing user resolution, rejected unverified email, invalid token |  |  |

#### AC Scenarios  
1. ▢ **Scenario**: New user authenticates with valid Google ID token  
   Given the API is running\  
   And no user exists with the Google subject ID from the token\  
   When a BFF backend sends `POST /v1/auth/google` with a valid Google ID token where `email_verified` is `true`\  
   Then the response status code should be 200\  
   And a new user should be created in the database with the Google subject ID\  
   And the response should contain a non-empty `accessToken`\  
   And the response should contain a non-empty `refreshToken`\  
   And the response should contain a `userId` matching the new user's ID\  
   And the `accessToken` decoded should contain `sub` equal to the new user's ID\  
   And the `accessToken` decoded should contain `email` equal to the Google email  
2. ▢ **Scenario**: Returning user authenticates with valid Google ID token  
   Given the API is running\  
   And a user already exists with a known Google subject ID\  
   When a BFF backend sends `POST /v1/auth/google` with a valid Google ID token for that subject\  
   Then the response status code should be 200\  
   And no new user should be created\  
   And the response `userId` should match the existing user's ID  
3. ▢ **Scenario**: Google token with email_verified=false is rejected  
   Given the API is running\  
   When a BFF backend sends `POST /v1/auth/google` with a Google ID token where `email_verified` is `false`\  
   Then the response status code should be 400\  
   And the response body should contain "Email not verified by Google"  
4. ▢ **Scenario**: Invalid or expired Google token is rejected  
   Given the API is running\  
   When a BFF backend sends `POST /v1/auth/google` with an invalid or expired Google ID token\  
   Then the response status code should be 401\  
   And the response body should contain "Invalid Google token"  

#### Extra Information  
- Use the `Google.Apis.Auth` NuGet package (`GoogleJsonWebSignature.ValidateAsync`) for token validation.
- In integration tests, mock the Google token validation to avoid external dependencies.
- The Google ID token contains claims: `sub`, `email`, `email_verified`, `name`, `picture`, `iss`, `aud`.
- The `aud` claim must match the configured Google Client ID for the AuthService.
- Google Client ID should be configurable via `appsettings.json` under `Authentication:Google:ClientId`.

### Story: Generate RS256-signed JWT access tokens (007)
**WorkItemId**: 1320  
**tags**: gmdAuthSvc; jwt; rs256; tokenGeneration  
**SP**: 3  
**State**: New  
**Custom.ACScenarios**:  
1. ▢ **Scenario**: Generated JWT contains required claims  
   Given a user exists in the database  
   When the JWT service generates an access token for the user  
   Then the token should be a valid RS256-signed JWT  
   And the token should contain `sub` claim equal to the user's ID  
   And the token should contain `email` claim equal to the user's email  
   And the token should contain `iss` claim equal to "GmdAuthService"  
   And the token should contain `exp` claim approximately 60 minutes from now
2. ▢ **Scenario**: JWT is verifiable with the public key  
   Given the JWT service generated an access token  
   When the token is validated using the public key from the signing key  
   Then validation should succeed without errors
3. ▢ **Scenario**: Service generates RSA signing key pair on first startup  
   Given the `SigningKeys` table is empty  
   When the service starts  
   Then a new 2048-bit RSA key pair is generated and stored in the `SigningKeys` table  
   And `IsActive = 1`  
**Description**  
As the AuthService\  
I want to generate RS256-signed JWT access tokens\  
So that consuming services can cryptographically verify tokens using the public key.  

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ▢ | JWT is signed with the active RSA private key from the `SigningKeys` table |  |  |
| ▢ | JWT header contains `alg: RS256` and `kid` matching the signing key's `KeyId` |  |  |
| ▢ | JWT payload contains: `sub` (user ID), `email`, `jti` (unique token ID), `iat` (issued at), `exp` (expiry), `iss` (issuer = "GmdAuthService") |  |  |
| ▢ | Default access token lifetime is 60 minutes (configurable via `Jwt:AccessTokenLifetimeMinutes`) |  |  |
| ▢ | If no active signing key exists, a new 2048-bit RSA key pair is generated and stored at startup |  |  |
| ▢ | JWT can be validated using the public key from the JWKS endpoint |  |  |
| ▢ | Unit tests verify token structure, claims, and signature validation |  |  |

#### AC Scenarios  
1. ▢ **Scenario**: Generated JWT contains required claims  
   Given a user exists in the database\  
   When the JWT service generates an access token for the user\  
   Then the token should be a valid RS256-signed JWT\  
   And the token should contain `sub` claim equal to the user's ID\  
   And the token should contain `email` claim equal to the user's email\  
   And the token should contain `iss` claim equal to "GmdAuthService"\  
   And the token should contain `exp` claim approximately 60 minutes from now  
2. ▢ **Scenario**: JWT is verifiable with the public key  
   Given the JWT service generated an access token\  
   When the token is validated using the public key from the signing key\  
   Then validation should succeed without errors  
3. ▢ **Scenario**: Service generates RSA key pair on first startup if none exists  
   Given the `SigningKeys` table is empty\  
   When the service starts\  
   Then a new 2048-bit RSA key pair is generated and stored in the `SigningKeys` table\  
   And `IsActive = 1`  

### Story: JWKS endpoint exposes public signing keys (008)
**WorkItemId**: 1321  
**tags**: gmdAuthSvc; jwks; publicKey; tokenValidation  
**SP**: 1  
**State**: New  
**Custom.ACScenarios**:  
1. ▢ **Scenario**: JWKS returns RSA public keys  
   Given the API is running and a signing key exists  
   When I make a GET request to `/v1/auth/jwks`  
   Then the response status code should be 200  
   And the response should contain a `keys` array with at least one entry  
   And each key should have `kty` equal to "RSA"  
   And each key should have `alg` equal to "RS256"  
   And each key should have non-empty `n` and `e` values
2. ▢ **Scenario**: JWKS endpoint is publicly accessible  
   Given the API is running  
   When I make a GET request to `/v1/auth/jwks` without any authentication header  
   Then the response status code should be 200
3. ▢ **Scenario**: JWKS only returns active signing keys  
   Given the service has 3 signing keys (2 active, 1 inactive)  
   When GET /v1/auth/jwks is called  
   Then response includes only 2 keys (the active ones)  
**Description**  
As a BFF backend (or its client library)\  
I want to fetch the public signing keys from the JWKS endpoint\  
So that I can validate JWT tokens issued by the AuthService.  

#### REST Endpoint
```yaml
GET /v1/auth/jwks
No authentication required

Response 200:
  {
    "keys": [
      {
        "kty": "RSA",
        "use": "sig",
        "alg": "RS256",
        "kid": "key-2026-04-01",
        "n": "syfFyH...",
        "e": "AQAB"
      }
    ]
  }
```

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ▢ | `GET /v1/auth/jwks` returns 200 with `{ keys: [...] }` |  |  |
| ▢ | Each key contains `kty`, `use`, `kid`, `n`, `e`, `alg` fields |  |  |
| ▢ | `kty` is "RSA", `use` is "sig", `alg` is "RS256" |  |  |
| ▢ | The endpoint is publicly accessible (`[AllowAnonymous]`) |  |  |
| ▢ | Only active signing keys (`IsActive = true`) are returned |  |  |
| ▢ | Response includes `Cache-Control: public, max-age=3600` header |  |  |
| ▢ | Integration test verifies JWKS response structure |  |  |

#### AC Scenarios  
1. ▢ Scenario: JWKS returns RSA public keys
   Given the API is running and a signing key exists\  
   When I make a GET request to `/v1/auth/jwks`\  
   Then the response status code should be 200\  
   And the response should contain a `keys` array with at least one entry\  
   And each key should have `kty` equal to "RSA"\  
   And each key should have `alg` equal to "RS256"\  
   And each key should have non-empty `n` and `e` values  
2. ▢ Scenario: JWKS endpoint is publicly accessible
   Given the API is running\  
   When I make a GET request to `/v1/auth/jwks` without any authentication header\  
   Then the response status code should be 200  
3. ▢ Scenario: JWKS only returns active signing keys
   Given the service has signing keys with mixed IsActive values\  
   When GET /v1/auth/jwks is called\  
   Then only keys with `IsActive = true` are included in the response  

### Story: Persist and validate refresh tokens (009)
**WorkItemId**: 1323  
**tags**: gmdAuthSvc; refreshToken; tokenRotation  
**SP**: 3  
**State**: New  
**Custom.ACScenarios**:  
1. ▢ **Scenario**: Valid refresh token returns new token pair  
   Given the API is running  
   And a user authenticated via Google and received a refresh token  
   When I POST to `/v1/auth/refresh` with the valid refresh token  
   Then the response status code should be 200  
   And the response should contain a new `accessToken`  
   And the response should contain a new `refreshToken` different from the original  
   And the response should contain `expiresAtUtc`
2. ▢ **Scenario**: Used refresh token is rejected (rotation enforcement)  
   Given the API is running  
   And a refresh token has already been used once to obtain new tokens  
   When I POST to `/v1/auth/refresh` with the same refresh token again  
   Then the response status code should be 400  
   And the response body should contain "Refresh token revoked"
3. ▢ **Scenario**: Expired refresh token is rejected  
   Given the API is running  
   And a user has a refresh token that has expired  
   When I POST to `/v1/auth/refresh` with the expired token  
   Then the response status code should be 400  
   And the response body should contain "Refresh token expired"  
**Custom.ExtraInformation**: - Refresh token is a cryptographically random 256-bit value, Base64Url-encoded.
- Only the SHA-256 hash is stored in the database; the plaintext is returned to the caller once.
- Consider a periodic cleanup job for expired/revoked refresh tokens (post-MVP).  
**Description**  
As a BFF backend\  
I want to use a refresh token to obtain a new access token\  
So that the user stays authenticated without re-triggering the Google sign-in flow.  

#### REST Endpoint
```yaml
POST /v1/auth/refresh
Content-Type: application/json
X-Api-Key: {bff-api-key}

Request:
  { "refreshToken": "dGVzdA==" }

Response 200:
  {
    "accessToken": "eyJ...",
    "refreshToken": "bmV3VG9rZW4=",
    "expiresAtUtc": "2026-04-04T16:00:00Z",
    "userId": 42
  }

Response 400:
  { "error": "Refresh token expired" }
  { "error": "Refresh token revoked" }
```

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ▢ | Refresh tokens are stored in the `RefreshTokens` table with columns: `Id`, `TokenHash` (SHA-256), `UserId`, `ExpiresAtUtc`, `CreatedAtUtc`, `IsRevoked` |  |  |
| ▢ | `POST /v1/auth/refresh` accepts `{ refreshToken }` and validates against the database |  |  |
| ▢ | On success, a new access token and **new** refresh token are issued (token rotation) |  |  |
| ▢ | The old refresh token is marked as revoked (`IsRevoked = true`) after use |  |  |
| ▢ | Expired refresh tokens return 400 with "Refresh token expired" |  |  |
| ▢ | Already-revoked refresh tokens return 400 with "Refresh token revoked" |  |  |
| ▢ | Default refresh token lifetime: 7 days (configurable via `Jwt:RefreshTokenLifetimeDays`) |  |  |
| ▢ | The endpoint is publicly accessible (`[AllowAnonymous]`) since the refresh token itself is the credential |  |  |
| ▢ | X-Api-Key header is still required (BFF-to-AuthService call, not user-facing) |  |  |
| ▢ | Tests cover: successful refresh, expired token, revoked token, rotation |  |  |

#### AC Scenarios  
1. ▢ **Scenario**: Valid refresh token returns new token pair  
   Given the API is running\  
   And a user authenticated via Google and received a refresh token\  
   When I POST to `/v1/auth/refresh` with the valid refresh token\  
   Then the response status code should be 200\  
   And the response should contain a new `accessToken`\  
   And the response should contain a new `refreshToken` different from the original\  
   And the response should contain `expiresAtUtc`  
2. ▢ **Scenario**: Used refresh token is rejected (rotation enforcement)  
   Given the API is running\  
   And a refresh token has already been used once to obtain new tokens\  
   When I POST to `/v1/auth/refresh` with the same refresh token again\  
   Then the response status code should be 400\  
   And the response body should contain "Refresh token revoked"  
3. ▢ **Scenario**: Expired refresh token is rejected  
   Given the API is running\  
   And a user has a refresh token that has expired\  
   When I POST to `/v1/auth/refresh` with the expired token\  
   Then the response status code should be 400\  
   And the response body should contain "Refresh token expired"  

#### Extra Information  
- Refresh token is a cryptographically random 256-bit value, Base64Url-encoded.
- Only the SHA-256 hash is stored in the database; the plaintext is returned to the caller once.
- Consider a periodic cleanup job for expired/revoked refresh tokens (post-MVP).

### Story: Revoke refresh token on logout (010)
**WorkItemId**: 1703  
**tags**: gmdAuthSvc; logout; refreshToken; revocation  
**SP**: 1  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: Refresh token is revoked on logout  
   Given a user has an active refresh token  
   When the user calls logout with their refresh token  
   Then the refresh token is marked as revoked  
   And subsequent refresh requests with that token fail
2. **Scenario**: Revoked tokens cannot be used for refresh  
   Given a refresh token has been revoked  
   When attempting to exchange it for new access token  
   Then HTTP 401 Unauthorized is returned  
**Description**  
**As a** user  
  
**I want** my refresh token to be revoked when I logout  
  
**So that** I cannot extend my session after logout  
  

#### REST Endpoint
```yaml
POST /v1/auth/logout
Content-Type: application/json
X-Api-Key: {bff-api-key}

Request:
  { "refreshToken": "dGVzdA==" }

Response 200:
  { }

Response 400:
  { "error": "Refresh token not found" }
```

#### Revocation Details
  
- Find `RefreshToken` record by `TokenHash` (SHA-256 of submitted token)
- Set `IsRevoked = true`
- Prevent future token exchanges with revoked token
- Revocation is idempotent (revoking an already-revoked token returns 200)

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ▢ | `POST /v1/auth/logout` endpoint accepts `{ refreshToken }` in the request body |  |  |
| ▢ | `RefreshToken.IsRevoked` is set to `true` upon logout |  |  |
| ▢ | Revoked tokens are no longer accepted for refresh requests (return 400) |  |  |
| ▢ | Query for active tokens excludes revoked tokens |  |  |
| ▢ | Revocation is idempotent (revoking already-revoked token succeeds without error) |  |  |
| ▢ | X-Api-Key header is required |  |  |
| ▢ | Unit test verifies token revocation |  |  |

#### AC Scenarios  
1. ▢ **Scenario**: Refresh token is revoked on logout
   Given a user has an active refresh token
  
   When the user calls `POST /v1/auth/logout` with their refresh token
  
   Then the refresh token is marked as revoked in the database
  
   And subsequent `POST /v1/auth/refresh` requests with that token return 400
  

2. ▢ **Scenario**: Revoked tokens cannot be used for refresh
   Given a refresh token has been revoked
  
   When attempting to exchange it for new access token via `POST /v1/auth/refresh`
  
   Then the response status code should be 400
  
   And the response body should contain "Refresh token revoked"
  

3. ▢ **Scenario**: Logout revocation is idempotent
   Given a refresh token that is already revoked
  
   When `POST /v1/auth/logout` is called again with the same token
  
   Then the response status code should be 200
  
   And no error is returned  

### Story: API key authentication for BFF backends (011)
**WorkItemId**: 1334  
**tags**: apiKey; bffAuth; gmdAuthSvc; security  
**SP**: 2  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: Valid API key grants access to auth endpoint  
   Given the API is running with `ApiSecurity:ApiKey` set to "my-secret-key"  
   When a request to `POST /v1/auth/google` includes header `X-Api-Key: my-secret-key`  
   Then the request should proceed to the endpoint handler
2. **Scenario**: Missing API key returns 401  
   Given the API is running  
   When a request to `POST /v1/auth/google` does not include an `X-Api-Key` header  
   Then the response status code should be 401  
   And the response body should contain "Invalid or missing API key"
3. **Scenario**: JWKS endpoint is accessible without API key  
   Given the API is running  
   When a request to `GET /v1/auth/jwks` is made without an `X-Api-Key` header  
   Then the response status code should be 200
4. **Scenario**: Service fails fast when API key is not configured  
   Given `ApiSecurity:ApiKey` is missing from appsettings  
   When the API attempts to start  
   Then startup fails with a clear error message  
**Description**  
As the AuthService\  
I want to authenticate incoming requests from BFF backends via an API key\  
So that only authorized backends can exchange tokens.  

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ▢ | A middleware or filter validates the `X-Api-Key` header on protected endpoints (`/v1/auth/google`, `/v1/auth/refresh`, `/v1/auth/logout`) |  |  |
| ▢ | The expected API key is configurable via `ApiSecurity:ApiKey` in `appsettings.json` |  |  |
| ▢ | Requests without a valid API key return 401 with "Invalid or missing API key" |  |  |
| ▢ | The JWKS endpoint (`/v1/auth/jwks`) does **not** require an API key |  |  |
| ▢ | If `ApiSecurity:ApiKey` is not configured, the service fails fast at startup |  |  |
| ▢ | Tests cover: valid key accepted, missing key rejected, wrong key rejected, JWKS accessible without key |  |  |

#### AC Scenarios  
1. ▢ **Scenario**: Valid API key grants access to auth endpoint  
   Given the API is running with `ApiSecurity:ApiKey` set to "my-secret-key"\  
   When a request to `POST /v1/auth/google` includes header `X-Api-Key: my-secret-key`\  
   Then the request should proceed to the endpoint handler  
2. ▢ **Scenario**: Missing API key returns 401  
   Given the API is running\  
   When a request to `POST /v1/auth/google` does not include an `X-Api-Key` header\  
   Then the response status code should be 401\  
   And the response body should contain "Invalid or missing API key"  
3. ▢ **Scenario**: JWKS endpoint is accessible without API key  
   Given the API is running\  
   When a request to `GET /v1/auth/jwks` is made without an `X-Api-Key` header\  
   Then the response status code should be 200  
4. ▢ **Scenario**: Service fails fast when API key is not configured  
   Given `ApiSecurity:ApiKey` is missing from appsettings\  
   When the API attempts to start\  
   Then startup fails with a configuration error  

### Story: Create client library project structure (012)
**WorkItemId**: 1325  
**tags**: clientLib; gmdAuthSvc; projectSetup  
**SP**: 1  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: Client library project compiles  
   Given the `Gmd.AuthService.ClientLib` project exists under `src/`  
   When I run `dotnet build TheSln.sln`  
   Then the build should complete successfully  
   And `Gmd.AuthService.ClientLib.dll` should be in the build output
2. **Scenario**: Client library has no forbidden dependencies  
   Given the `Gmd.AuthService.ClientLib` project file exists  
   When I inspect its `ProjectReference` and `PackageReference` items  
   Then it should not reference `Gmd.AuthService.WebApi`  
   And it should not reference `Gmd.AuthService.DbContext`  
**Description**  
As a developer\  
I want the `Gmd.AuthService.ClientLib` project created with proper structure\  
So that it can be packaged as a NuGet and consumed by BFF backends.  

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ▢ | A new class library project `Gmd.AuthService.ClientLib` is created under `src/` |  |  |
| ▢ | The project targets `net8.0` (or matching the solution's target framework) |  |  |
| ▢ | The `.csproj` contains NuGet packaging metadata: `PackageId`, `Version`, `Description`, `Authors` |  |  |
| ▢ | The project is added to `TheSln.sln` |  |  |
| ▢ | The project compiles without errors |  |  |
| ▢ | No dependency on `Gmd.AuthService.WebApi` or `Gmd.AuthService.DbContext` (the client lib is independent) |  |  |

#### AC Scenarios  
1. ▢ **Scenario**: Client library project compiles  
   Given the `Gmd.AuthService.ClientLib` project exists under `src/`\  
   When I run `dotnet build TheSln.sln`\  
   Then the build should complete successfully\  
   And `Gmd.AuthService.ClientLib.dll` should be in the build output  
2. ▢ **Scenario**: Client library has no forbidden dependencies  
   Given the `Gmd.AuthService.ClientLib` project file exists\  
   When I inspect its `ProjectReference` and `PackageReference` items\  
   Then it should not reference `Gmd.AuthService.WebApi`\  
   And it should not reference `Gmd.AuthService.DbContext`  

### Story: AuthService HTTP client service (013)
**WorkItemId**: 1326  
**tags**: clientLib; gmdAuthSvc; httpClient; serviceInterface  
**SP**: 2  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: BFF registers and resolves the AuthService client  
   Given a BFF backend calls `services.AddAuthServiceClient(opts => opts.BaseUrl = "https://auth.example.com")`  
   When the `IAuthServiceClient` is resolved from the DI container  
   Then a valid `AuthServiceClient` instance should be returned  
   And its underlying `HttpClient.BaseAddress` should be "https://auth.example.com"
2. **Scenario**: Client exchanges Google token for AuthService JWT  
   Given the AuthService is reachable at the configured base URL  
   When the BFF calls `AuthenticateWithGoogleAsync` with a valid Google ID token  
   Then the client should POST to `/v1/auth/google` with the token  
   And return the deserialized `AuthTokenResponse`
3. **Scenario**: Client refreshes tokens  
   Given the AuthService is reachable at the configured base URL  
   When the BFF calls `RefreshTokenAsync` with a valid refresh token  
   Then the client should POST to `/v1/auth/refresh`  
   And return the deserialized `AuthTokenResponse` with new tokens  
**Description**  
As a BFF backend developer\  
I want a typed HTTP client (`IAuthServiceClient`) in the client library\  
So that I can call AuthService endpoints in a strongly-typed manner.  

#### Acceptance Criteria  
- [ ] Interface `IAuthServiceClient` is defined with methods:
  - `Task<AuthTokenResponse> AuthenticateWithGoogleAsync(string googleIdToken, CancellationToken ct)`
  - `Task<AuthTokenResponse> RefreshTokenAsync(string refreshToken, CancellationToken ct)`
  - `Task LogoutAsync(string refreshToken, CancellationToken ct)`
  - `Task<JwksResponse> GetJwksAsync(CancellationToken ct)`
- [ ] Implementation `AuthServiceClient` uses `HttpClient` to call AuthService REST endpoints
- [ ] `AuthServiceClientOptions` class configurable via `IOptions` pattern: `BaseUrl` (required), `ApiKey` (required for protected endpoints)
- [ ] DI extension method `AddAuthServiceClient(this IServiceCollection, Action<AuthServiceClientOptions>)` registers the typed client
- [ ] HttpClient is registered via `IHttpClientFactory` for proper lifecycle management
- [ ] Unit tests verify DI registration and HTTP calls (using mock HTTP handler)

#### AC Scenarios  
1. **Scenario**: BFF registers and resolves the AuthService client  
   Given a BFF backend calls `services.AddAuthServiceClient(opts => opts.BaseUrl = "https://auth.example.com")`\  
   When the `IAuthServiceClient` is resolved from the DI container\  
   Then a valid `AuthServiceClient` instance should be returned\  
   And its underlying `HttpClient.BaseAddress` should be "https://auth.example.com"  
2. **Scenario**: Client exchanges Google token for AuthService JWT  
   Given the AuthService is reachable at the configured base URL\  
   When the BFF calls `AuthenticateWithGoogleAsync` with a valid Google ID token\  
   Then the client should POST to `/v1/auth/google` with the token\  
   And return the deserialized `AuthTokenResponse`  
3. **Scenario**: Client refreshes tokens  
   Given the AuthService is reachable at the configured base URL\  
   When the BFF calls `RefreshTokenAsync` with a valid refresh token\  
   Then the client should POST to `/v1/auth/refresh`\  
   And return the deserialized `AuthTokenResponse` with new tokens  

### Story: Automatic token refresh middleware (014)
**WorkItemId**: 1327  
**tags**: clientLib; gmdAuthSvc; middleware; tokenRefresh  
**SP**: 3  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: Token manager returns cached non-expired token  
   Given the token manager holds a valid access token expiring in 5 minutes  
   When `GetValidAccessTokenAsync()` is called  
   Then the existing access token should be returned  
   And no refresh HTTP call should be made
2. **Scenario**: Token manager auto-refreshes near-expiry token  
   Given the token manager holds an access token expiring in 20 seconds  
   When `GetValidAccessTokenAsync()` is called  
   Then the token manager should call `RefreshTokenAsync` on the AuthService client  
   And return the new access token  
   And store the new refresh token
3. **Scenario**: Token manager throws when refresh token is invalid  
   Given the token manager holds an expired access token  
   And the refresh token is revoked or expired  
   When `GetValidAccessTokenAsync()` is called  
   Then an `AuthServiceTokenExpiredException` should be thrown  
**Description**  
As a BFF backend developer\  
I want the client library to automatically refresh expired access tokens\  
So that I don't have to implement refresh logic in every consuming application.  

#### Acceptance Criteria  
- [ ] A token manager service (`IAuthTokenManager`) stores the current access token and refresh token (in-memory per session)
- [ ] Method `GetValidAccessTokenAsync()` returns the current token if not expired, or silently refreshes and returns the new token
- [ ] Token expiry is checked with a configurable buffer (default: 30 seconds before actual expiry)
- [ ] If refresh fails (revoked, expired refresh token), the method throws `AuthServiceTokenExpiredException` signaling the user must re-authenticate
- [ ] DI extension method `AddAuthServiceTokenManagement(this IServiceCollection)` registers the token manager
- [ ] Unit tests cover: returns cached token, refreshes expired token, throws on failed refresh

#### AC Scenarios  
1. **Scenario**: Token manager returns cached non-expired token  
   Given the token manager holds a valid access token expiring in 5 minutes\  
   When `GetValidAccessTokenAsync()` is called\  
   Then the existing access token should be returned\  
   And no refresh HTTP call should be made  
2. **Scenario**: Token manager auto-refreshes near-expiry token  
   Given the token manager holds an access token expiring in 20 seconds\  
   When `GetValidAccessTokenAsync()` is called\  
   Then the token manager should call `RefreshTokenAsync` on the AuthService client\  
   And return the new access token\  
   And store the new refresh token  
3. **Scenario**: Token manager throws when refresh token is invalid  
   Given the token manager holds an expired access token\  
   And the refresh token is revoked or expired\  
   When `GetValidAccessTokenAsync()` is called\  
   Then an `AuthServiceTokenExpiredException` should be thrown  

### Story: JWT validation helper using JWKS (015)
**WorkItemId**: 1328  
**tags**: clientLib; gmdAuthSvc; jwks; jwtValidation  
**SP**: 2  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: Valid AuthService JWT is accepted  
   Given the JWKS endpoint returns the signing public key  
   And a valid RS256-signed JWT is presented  
   When `ValidateTokenAsync` is called with the token  
   Then a `ClaimsPrincipal` should be returned  
   And the principal should have a `sub` claim with the user's ID  
   And the principal should have an `email` claim
2. **Scenario**: Expired JWT is rejected  
   Given the JWKS endpoint returns the signing public key  
   And an expired RS256-signed JWT is presented  
   When `ValidateTokenAsync` is called with the token  
   Then an `AuthServiceTokenValidationException` should be thrown
3. **Scenario**: JWT with wrong issuer is rejected  
   Given a valid RS256-signed JWT with `iss = "WrongIssuer"`  
   When `ValidateTokenAsync` is called with the token  
   Then an `AuthServiceTokenValidationException` should be thrown
4. **Scenario**: JWKS is cached and not fetched on every call  
   Given the JWKS has been fetched within the last hour  
   When `ValidateTokenAsync` is called  
   Then the cached JWKS should be used  
   And no HTTP request to the JWKS endpoint should be made  
**Description**  
As a BFF backend developer\  
I want the client library to validate AuthService JWTs using the JWKS endpoint\  
So that I can trust the `user_id` and `email` claims in incoming tokens.  

#### Acceptance Criteria  
- [ ] A service `IAuthServiceJwtValidator` provides method `Task<ClaimsPrincipal> ValidateTokenAsync(string accessToken, CancellationToken ct)`
- [ ] Validation fetches the JWKS from the AuthService (with a configurable cache duration, default 1 hour)
- [ ] Validation checks: RS256 signature, `iss = "GmdAuthService"`, token not expired
- [ ] Invalid or expired tokens throw `AuthServiceTokenValidationException`
- [ ] Successfully validated tokens return a `ClaimsPrincipal` with `sub` (user_id) and `email` claims accessible
- [ ] DI extension method registers the validator
- [ ] Unit tests verify validation with mock JWKS, valid/invalid/expired tokens

#### AC Scenarios  
1. **Scenario**: Valid AuthService JWT is accepted  
   Given the JWKS endpoint returns the signing public key\  
   And a valid RS256-signed JWT is presented\  
   When `ValidateTokenAsync` is called with the token\  
   Then a `ClaimsPrincipal` should be returned\  
   And the principal should have a `sub` claim with the user's ID\  
   And the principal should have an `email` claim  
2. **Scenario**: Expired JWT is rejected  
   Given the JWKS endpoint returns the signing public key\  
   And an expired RS256-signed JWT is presented\  
   When `ValidateTokenAsync` is called with the token\  
   Then an `AuthServiceTokenValidationException` should be thrown  
3. **Scenario**: JWT with wrong issuer is rejected  
   Given a valid RS256-signed JWT with `iss = "WrongIssuer"`\  
   When `ValidateTokenAsync` is called with the token\  
   Then an `AuthServiceTokenValidationException` should be thrown  
4. **Scenario**: JWKS is cached and not fetched on every call  
   Given the JWKS has been fetched within the last hour\  
   When `ValidateTokenAsync` is called\  
   Then the cached JWKS should be used\  
   And no HTTP request to the JWKS endpoint should be made  

### Story: Demo ASP.NET web app with Google login via AuthService (016)
**tags**: demo; demoApp; gmdAuthSvc; integration  
**SP**: 3  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: User logs in via Google through demo app  
   Given the demo app is running and the AuthService is running  
   And the user navigates to the demo app home page  
   When the user clicks "Login with Google"  
   Then the browser is redirected to Google OAuth consent screen  
   And after the user grants consent, Google redirects back to the demo app  
   And the demo app backend obtains the Google ID token from the OAuth callback  
   And the demo app backend calls the AuthService `POST /v1/auth/google` with the token  
   And the demo app stores the JWT and refresh token in a secure HttpOnly session cookie  
   And the user is redirected to the profile page
2. **Scenario**: Authenticated user sees their info  
   Given the user is authenticated in the demo app  
   When the user visits the profile page  
   Then the page displays the `user_id` from the JWT `sub` claim  
   And the page displays the `email` from the JWT `email` claim
3. **Scenario**: User logs out and session is cleared  
   Given the user is authenticated in the demo app  
   When the user clicks "Logout"  
   Then the demo app backend calls AuthService `POST /v1/auth/logout`  
   And the session cookie is cleared  
   And the user is redirected to the home page as unauthenticated
4. **Scenario**: Unauthenticated access to protected page redirects to login  
   Given the user is not authenticated  
   When the user navigates to the profile page  
   Then the user is redirected to the login/home page  
**Custom.ExtraInformation**: - The demo app uses `Microsoft.AspNetCore.Authentication.Google` for initiating the Google OAuth flow.
- `options.SaveTokens = true` is set so that the Google `id_token` is accessible via `HttpContext.GetTokenAsync("id_token")`.
- The demo app calls the AuthService via `Gmd.AuthService.ClientLib` (`IAuthServiceClient`); it never calls Google APIs directly from the profile page.
- JWT and refresh token are stored in ASP.NET Core session (backed by `IDistributedCache` in-memory for the demo; for production a persistent cache would be used).
- The demo app has its own Google OAuth client credentials (separate from AuthService), configured via `Authentication:Google:ClientId` and `Authentication:Google:ClientSecret`.
- The AuthService URL and API key for the demo app are configured via `AuthService:BaseUrl` and `AuthService:ApiKey` in appsettings.  
**Description**  
**As a** developer  
  
**I want** a demo ASP.NET web app that integrates with the AuthService via the client library  
  
**So that** the full Google → AuthService → JWT → BFF flow can be validated end-to-end  
  

#### Architecture
- New ASP.NET Core (Razor Pages) project: `Gmd.AuthService.DemoApp`
- Added to solution `TheSln.sln`
- References `Gmd.AuthService.ClientLib` (no direct AuthService API calls)
- Does **not** communicate directly with Google on the "profile page" — only the backend calls the AuthService

#### Flow Diagram
```
Browser              Demo App Backend          AuthService
   │                       │                       │
   │── "Login with Google" ──▶                     │
   │                       │──── Google OAuth ────▶│
   │◀──── Google redirect ─│                       │
   │── Google callback ───▶│                       │
   │                       │── POST /v1/auth/google ▶│
   │                       │◀── JWT + refresh token ─│
   │◀── Set cookie, redirect profile page ──       │
   │── GET /profile ───────▶                       │
   │                       │  (validates JWT locally from cookie)
   │◀── Display user_id + email ──                 │
```

#### Implementation Details
- `GET /` — Home page with "Login with Google" button (if not authenticated) or link to profile
- `GET /profile` — Protected page showing `userId` and `email` from JWT claims; redirects to home if not authenticated
- `GET /auth/google-callback` — OAuth callback handler: extracts id_token, calls AuthService, stores tokens in session
- `POST /auth/logout` — Calls AuthService logout, clears session, redirects to home
- JWT stored in ASP.NET Core in-memory session; extracted and validated client-side via `IAuthServiceJwtValidator`

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ▢ | Demo app project exists and compiles as part of solution | DemoAppBuildTest | `dotnet build TheSln.sln` succeeds |
| ▢ | Home page renders a login button when unauthenticated | GivenUnauthenticated_WhenHomePageLoaded_ThenLoginButtonPresent | Integration test |
| ▢ | After Google callback, demo app calls AuthService and stores JWT in session | GivenValidGoogleCallback_WhenProcessed_ThenJwtStoredInSession | Mock AuthService in test |
| ▢ | Profile page displays `userId` and `email` from JWT | GivenAuthenticatedSession_WhenProfilePageLoaded_ThenUserIdAndEmailDisplayed | Integration test |
| ▢ | Logout clears session and calls AuthService logout | GivenAuthenticatedUser_WhenLogout_ThenSessionClearedAndAuthServiceLogoutCalled | Integration test |
| ▢ | Profile page redirects to home when unauthenticated | GivenUnauthenticated_WhenProfilePageRequested_ThenRedirectToHome | Integration test |
| ▢ | Demo app uses `IAuthServiceClient` (not raw HttpClient to AuthService) | N/A — code review | Architecture constraint |

#### AC Scenarios
- [ ] **Scenario 1: User logs in via Google through demo app**  
  Given the demo app and AuthService are running  
  And the user navigates to the demo app home page  
  When the user clicks "Login with Google"  
  Then the browser is redirected to Google OAuth  
  And after consent, the demo app backend calls `POST /v1/auth/google` with the Google ID token  
  And the JWT and refresh token are stored in the session  
  And the user is redirected to the profile page  

- [ ] **Scenario 2: Authenticated user sees their info on profile page**  
  Given the user is authenticated in the demo app  
  When the user visits the profile page  
  Then the page displays the `user_id` from the JWT `sub` claim  
  And the page displays the `email` from the JWT `email` claim  

- [ ] **Scenario 3: User logs out and session is cleared**  
  Given the user is authenticated in the demo app  
  When the user clicks "Logout"  
  Then the demo app backend calls `POST /v1/auth/logout` on the AuthService  
  And the session cookie is cleared  
  And the user is redirected to the home page as unauthenticated  

- [ ] **Scenario 4: Unauthenticated access to profile page redirects to login**  
  Given the user is not authenticated  
  When the user navigates to `/profile`  
  Then the user is redirected to the home page  
