# Epic: Gmd.AuthService
**WorkItemId**: 1305  
**tags**: clientLib; gmdAuthSvc; googleOpenId; jwt; mvp  
**Effort**: 40  
**State**: New  
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
- &#128260; Refresh token lifecycle with rotation
- &#127973; Health endpoints for load balancers
- &#128674; Deployed to dev/staging/prod with metrics and DB migrations (infrastructure already available via library)
- &#128683; No UI required
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

### Summary


| # | Feature | Story Count | Total SP |

|---|---------|-------------|----------|

| 1 | &#127959;️ CI Pipeline &amp; Build | 1 | 2 |

| 2 | &#128452;️ Database Schema &amp; Migrations | 2 | 3 |

| 3 | &#127973; Health Check Endpoints | 2 | 0.75 |

| 4 | ⚠️ Global Exception Handling | 1 | 1 |

| 5 | &#128272; Google OpenID Connect Authentication | 2 | 6 |

| 6 | &#127903;️ JWT Token Generation &amp; JWKS | 2 | 4 |

| 7 | &#128260; Refresh Token Lifecycle | 1 | 3 |

| 8 | &#128230; Client Library — NuGet Package | 4 | 8 |

| 9 | &#128674; Deployment Pipeline | 1 | 2 |

| 10 | &#128202; Metrics &amp; Observability | 1 | 1 |

| 11 | &#128274; API Security — BFF-Only Access | 1 | 2 |

| 12 | &#128203; OpenAPI Specification | 1 | 1 |

| **Total** | **12 Features** | **19 Stories** | **~34 SP** |

  

**Estimated Total Duration (Senior Dev)**: ~34 working days (~7 weeks at 5 days/week)  

## Feature: 🔄 Refresh Token Lifecycle (007)
**WorkItemId**: 1322  
**tags**: gmdAuthSvc; refreshToken; session; tokenRotation  
**Effort**: 3  
**State**: New  
**Description**  
### Overview
**As a** developer    
**I want** to implement complete refresh token lifecycle management    
**So that** users can extend sessions without re-authenticating    

### Refresh Token Flow
1. **Issue** - After successful login, issue refresh token and store it
2. **Refresh** - Exchange refresh token for new access token
3. **Revoke** - Invalidate refresh token on logout or security event
4. **Validate** - Ensure token not expired or revoked before accepting

### Refresh Token Properties
- Stored as SHA-256 hash (never store plain token in database)
- Issued to user after successful authentication
- Expires after 30 days
- Can be revoked (IsRevoked flag)
- Can be rotated (issue new token with each refresh)

### Story: 🔄 Revoke refresh token on logout (002)
**WorkItemId**: 1703  
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
#### Revoke Refresh Token
**As a** user    
**I want** my refresh token to be revoked when I logout    
**So that** I cannot extend my session after logout    

**Revocation Details:**  
- Find RefreshToken record by TokenHash
- Set IsRevoked = 1
- Record revocation timestamp for audit
- Prevent future token exchanges with revoked token

#### Acceptance Criteria  
- [ ] Logout endpoint accepts refresh token or user ID
- [ ] RefreshToken.IsRevoked is set to 1 upon logout
- [ ] Revoked tokens are no longer accepted for refresh requests
- [ ] Query for active tokens excludes revoked tokens
- [ ] Revocation is idempotent (revoking already-revoked token succeeds)
- [ ] Unit test verifies token revocation

#### Acceptance Tests  
1. **Scenario**: Refresh token is revoked on logout
   Given a user has an active refresh token  
   When the user calls logout with their refresh token  
   Then the refresh token is marked as revoked  
   And subsequent refresh requests with that token fail  

2. **Scenario**: Revoked tokens cannot be used for refresh
   Given a refresh token has been revoked  
   When attempting to exchange it for new access token  
   Then HTTP 401 Unauthorized is returned  

### Story: 🔃 Exchange refresh token for new access token (002)
**WorkItemId**: 1704  
**SP**: 2  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: Valid refresh token returns new access token
   Given a valid, non-revoked refresh token
   And token has not expired
   When POST /auth/refresh is called
   Then HTTP 200 OK is returned
   And response includes new access token (JWT)
   And new token has same user claims (sub, aud)

2. **Scenario**: Expired refresh token is rejected
   Given a refresh token that has expired
   When POST /auth/refresh is called
   Then HTTP 401 Unauthorized is returned

3. **Scenario**: Revoked refresh token is rejected
   Given a refresh token that has been revoked
   When POST /auth/refresh is called
   Then HTTP 401 Unauthorized is returned  
**Description**  
#### Exchange Refresh Token
**As a** developer    
**I want** the refresh endpoint to exchange a valid refresh token for a new access token    
**So that** users can extend their session without re-authenticating    

**Refresh Endpoint Details:**  
- POST `/auth/refresh`
- Accepts refresh token (usually from HttpOnly cookie)
- Returns new JWT access token
- Validates token not expired
- Validates token not revoked

#### Acceptance Criteria  
- [ ] POST `/auth/refresh` endpoint exists
- [ ] Accepts refresh token (bearer token or cookie)
- [ ] Validates token exists in database
- [ ] Validates token hash matches stored hash
- [ ] Validates token not expired (ExpiresAtUtc &gt; now)
- [ ] Validates token not revoked (IsRevoked = 0)
- [ ] Returns new access token with same user claims
- [ ] Returns HTTP 401 if token invalid or expired
- [ ] Returns HTTP 401 if token revoked
- [ ] Unit test verifies token exchange with various state

#### Acceptance Tests  
1. **Scenario**: Valid refresh token returns new access token
   Given a valid, non-revoked refresh token  
   And token has not expired  
   When POST /auth/refresh is called  
   Then HTTP 200 OK is returned  
   And response includes new access token (JWT)  
   And new token has same user claims (sub, aud)  

2. **Scenario**: Expired refresh token is rejected
   Given a refresh token that has expired  
   When POST /auth/refresh is called  
   Then HTTP 401 Unauthorized is returned  

3. **Scenario**: Revoked refresh token is rejected
   Given a refresh token that has been revoked  
   When POST /auth/refresh is called  
   Then HTTP 401 Unauthorized is returned  

### Story: 🔄 Persist and validate refresh tokens (011)
**WorkItemId**: 1323  
**tags**: gmdAuthSvc; refreshToken; tokenRotation  
**SP**: 3  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: Valid refresh token returns new token pair\
   Given the API is running\
   And a user authenticated via Google and received a refresh token\
   When I POST to `/v1/auth/refresh` with the valid refresh token\
   Then the response status code should be 200\
   And the response should contain a new `accessToken`\
   And the response should contain a new `refreshToken` different from the original\
   And the response should contain `expiresAtUtc`
2. **Scenario**: Used refresh token is rejected (rotation enforcement)\
   Given the API is running\
   And a refresh token has already been used once to obtain new tokens\
   When I POST to `/v1/auth/refresh` with the same refresh token again\
   Then the response status code should be 400\
   And the response body should contain `&quot;Refresh token revoked&quot;`
3. **Scenario**: Expired refresh token is rejected\
   Given the API is running\
   And a user has a refresh token that has expired\
   When I POST to `/v1/auth/refresh` with the expired token\
   Then the response status code should be 400\
   And the response body should contain `&quot;Refresh token expired&quot;`  
**Custom.ExtraInformation**: - Refresh token is a cryptographically random 256-bit value, Base64Url-encoded.
- Only the SHA-256 hash is stored in the database; the plaintext is returned to the caller once.
- Consider a periodic cleanup job for expired/revoked refresh tokens (post-MVP).  
**Description**  
As a BFF backend\  
I want to use a refresh token to obtain a new access token\  
So that the user stays authenticated without re-triggering the Google sign-in flow.  

#### Acceptance Criteria  
- [ ] Refresh tokens are stored in the `RefreshTokens` table with columns: `Id`, `TokenHash` (SHA-256), `UserId`, `ExpiresAtUtc`, `CreatedAtUtc`, `IsRevoked`
- [ ] `POST /v1/auth/refresh` accepts `{ refreshToken }` and validates against the database
- [ ] On success, a new access token and **new** refresh token are issued (token rotation)
- [ ] The old refresh token is marked as revoked (`IsRevoked = true`) after use
- [ ] Expired refresh tokens return 400 with `&quot;Refresh token expired&quot;`
- [ ] Already-revoked refresh tokens return 400 with `&quot;Refresh token revoked&quot;`
- [ ] Default refresh token lifetime: 7 days (configurable via `Jwt:RefreshTokenLifetimeDays`)
- [ ] The endpoint is publicly accessible (`[AllowAnonymous]`) since the refresh token itself is the credential
- [ ] Tests cover: successful refresh, expired token, revoked token, rotation

#### Acceptance Tests  
1. **Scenario**: Valid refresh token returns new token pair\
   Given the API is running\  
   And a user authenticated via Google and received a refresh token\  
   When I POST to `/v1/auth/refresh` with the valid refresh token\  
   Then the response status code should be 200\  
   And the response should contain a new `accessToken`\  
   And the response should contain a new `refreshToken` different from the original\  
   And the response should contain `expiresAtUtc`  
2. **Scenario**: Used refresh token is rejected (rotation enforcement)\
   Given the API is running\  
   And a refresh token has already been used once to obtain new tokens\  
   When I POST to `/v1/auth/refresh` with the same refresh token again\  
   Then the response status code should be 400\  
   And the response body should contain `&quot;Refresh token revoked&quot;`  
3. **Scenario**: Expired refresh token is rejected\
   Given the API is running\  
   And a user has a refresh token that has expired\  
   When I POST to `/v1/auth/refresh` with the expired token\  
   Then the response status code should be 400\  
   And the response body should contain `&quot;Refresh token expired&quot;`  

#### Extra Information  
- Refresh token is a cryptographically random 256-bit value, Base64Url-encoded.
- Only the SHA-256 hash is stored in the database; the plaintext is returned to the caller once.
- Consider a periodic cleanup job for expired/revoked refresh tokens (post-MVP).


## Feature: 📊 Metrics & Observability Integration (010)
**WorkItemId**: 1331  
**tags**: gmdAuthSvc; logging; metrics; observability  
**Effort**: 1  
**State**: New  
**Description**  
Integrate structured logging and request metrics using the chassi library's existing infrastructure.\  
Ensure the AuthService emits telemetry for monitoring and alerting.  

### Story: 📈 Structured logging and request metrics (017)
**WorkItemId**: 1332  
**tags**: gmdAuthSvc; logging; metrics; observability  
**SP**: 1  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: Google authentication success is logged\
   Given the API is running with structured logging enabled\
   When a BFF backend successfully authenticates via Google\
   Then a log entry should be emitted with level `Information`\
   And the log entry should contain the user's ID\
   And the log entry should not contain the Google ID token or access token
2. **Scenario**: Google authentication failure is logged\
   Given the API is running with structured logging enabled\
   When a BFF backend sends an invalid Google ID token\
   Then a log entry should be emitted with level `Warning`\
   And the log entry should contain the failure reason\
   And the log entry should not contain the invalid token  
**Description**  
As an operations engineer\  
I want structured logging and HTTP request metrics emitted by the AuthService\  
So that I can monitor service health, latency, and error rates.  

#### Acceptance Criteria  
- [ ] Structured logging (Serilog or equivalent from chassi library) is configured at startup
- [ ] All API requests log: HTTP method, path, status code, duration
- [ ] Google authentication events log: success/failure, user ID (on success), failure reason (on failure)
- [ ] Refresh token events log: success/failure
- [ ] Sensitive data (tokens, secrets) is never logged
- [ ] Log level is configurable per environment via `appsettings.json`
- [ ] Tests verify no sensitive data appears in log output

#### Acceptance Tests  
1. **Scenario**: Google authentication success is logged\
   Given the API is running with structured logging enabled\  
   When a BFF backend successfully authenticates via Google\  
   Then a log entry should be emitted with level `Information`\  
   And the log entry should contain the user's ID\  
   And the log entry should not contain the Google ID token or access token  
2. **Scenario**: Google authentication failure is logged\
   Given the API is running with structured logging enabled\  
   When a BFF backend sends an invalid Google ID token\  
   Then a log entry should be emitted with level `Warning`\  
   And the log entry should contain the failure reason\  
   And the log entry should not contain the invalid token  


## Feature: 🔐 Google OpenID Connect Authentication (005)
**WorkItemId**: 1316  
**tags**: authentication; core; gmdAuthSvc; googleOidc; openIdConnect  
**Effort**: 8  
**State**: New  
**Description**  
### Overview
**As a** developer    
**I want** to integrate Google OpenID Connect (OIDC) authentication    
**So that** users can authenticate using their Google accounts    

### OIDC Flow
The implementation follows the standard OAuth 2.0 Authorization Code flow:  
1. **Authorization Request** - Redirect user to Google login
2. **Authorization Code** - User authorizes, Google redirects back with code
3. **Token Exchange** - Service exchanges code for ID token and access token
4. **ID Token Validation** - Verify token signature and claims
5. **User Creation/Update** - Create or update user record based on GoogleSubjectId

### Configuration
- Google OAuth 2.0 credentials (Client ID, Secret)
- OIDC Discovery endpoint: `https://accounts.google.com/.well-known/openid-configuration`
- Authorization endpoint: `https://accounts.google.com/o/oauth2/v2/auth`
- Token endpoint: `https://oauth2.googleapis.com/token`

### Story: ⚙️ Configure Google OIDC discovery (001)
**WorkItemId**: 1701  
**SP**: 2  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: OIDC discovery is fetched and validated on startup
   Given Google OAuth 2.0 credentials are configured
   When the service initializes
   Then OIDC discovery endpoint is fetched from Google
   And discovery metadata is validated (issuer, algorithms, endpoints)
   And service starts successfully

2. **Scenario**: Service fails if OIDC credentials are missing
   Given Google OAuth 2.0 credentials are not configured
   When the service initializes
   Then initialization fails with clear error message
   And service does not start

3. **Scenario**: Discovery metadata is cached to reduce external calls
   Given the service has fetched discovery metadata
   When multiple requests occur
   Then cached metadata is reused
   And Google API is not called for every request  
**Description**  
#### OIDC Configuration &amp; Discovery
**As a** developer    
**I want** to configure Google OIDC credentials and fetch discovery endpoint    
**So that** the service can initiate the authentication flow    

**Configuration Details:**  
- Store Google Client ID and Client Secret securely
- Load OIDC discovery metadata from Google
- Validate issuer and supported algorithms
- Cache discovery metadata with TTL

#### Acceptance Criteria  
- [ ] Google OAuth 2.0 credentials configured (Client ID, Secret)
- [ ] OIDC Discovery endpoint is fetched successfully
- [ ] Discovery metadata includes required fields (issuer, authorization_endpoint, token_endpoint)
- [ ] Issuer is verified to be Google (`https://accounts.google.com` or `https://accounts.google.com/`)
- [ ] Supported algorithms include RS256
- [ ] JWKS URI is retrieved from discovery
- [ ] Discovery metadata is cached with appropriate TTL (e.g., 24 hours)
- [ ] Configuration fails fast if credentials are missing
- [ ] Unit test verifies discovery fetch and validation

#### Acceptance Tests  
1. **Scenario**: OIDC discovery is fetched and validated on startup
   Given Google OAuth 2.0 credentials are configured  
   When the service initializes  
   Then OIDC discovery endpoint is fetched from Google  
   And discovery metadata is validated (issuer, algorithms, endpoints)  
   And service starts successfully  

2. **Scenario**: Service fails if OIDC credentials are missing
   Given Google OAuth 2.0 credentials are not configured  
   When the service initializes  
   Then initialization fails with clear error message  
   And service does not start  

3. **Scenario**: Discovery metadata is cached to reduce external calls
   Given the service has fetched discovery metadata  
   When multiple requests occur  
   Then cached metadata is reused  
   And Google API is not called for every request  

### Story: 🔑 Authenticate via Google ID token (007)
**WorkItemId**: 1317  
**tags**: authentication; gmdAuthSvc; googleOidc; tokenExchange  
**SP**: 5  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: New user authenticates with valid Google ID token\
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
2. **Scenario**: Returning user authenticates with valid Google ID token\
   Given the API is running\
   And a user already exists with a known Google subject ID\
   When a BFF backend sends `POST /v1/auth/google` with a valid Google ID token for that subject\
   Then the response status code should be 200\
   And no new user should be created\
   And the response `userId` should match the existing user's ID
3. **Scenario**: Google token with email_verified=false is rejected\
   Given the API is running\
   When a BFF backend sends `POST /v1/auth/google` with a Google ID token where `email_verified` is `false`\
   Then the response status code should be 400\
   And the response body should contain `&quot;Email not verified by Google&quot;`
4. **Scenario**: Invalid or expired Google token is rejected\
   Given the API is running\
   When a BFF backend sends `POST /v1/auth/google` with an invalid or expired Google ID token\
   Then the response status code should be 401\
   And the response body should contain `&quot;Invalid Google token&quot;`  
**Custom.ExtraInformation**: - Use the `Google.Apis.Auth` NuGet package (`GoogleJsonWebSignature.ValidateAsync`) for token validation.
- In integration tests, mock the Google token validation to avoid external dependencies.
- The Google ID token contains claims: `sub`, `email`, `email_verified`, `name`, `picture`, `iss`, `aud`.
- The `aud` claim must match the configured Google Client ID for the AuthService.
- Google Client ID should be configurable via `appsettings.json` under `Authentication:Google:ClientId`.  
**Description**  
As a BFF backend\  
I want to exchange a Google ID token for AuthService JWT tokens\  
So that I can identify and authenticate the user in my application.  

#### Acceptance Criteria  
- [ ] `POST /v1/auth/google` accepts `{ googleIdToken }` in the request body
- [ ] The service validates the Google ID token using Google's public keys (via `Google.Apis.Auth` library or manual JWKS validation)
- [ ] If `email_verified` is `false` in the Google token claims, the request is rejected with 400 and message `&quot;Email not verified by Google&quot;`
- [ ] If the `GoogleSubjectId` (Google `sub` claim) already exists in the database, the existing user is resolved
- [ ] If the `GoogleSubjectId` does not exist, a new `User` record is created with `GoogleSubjectId`, `Email`, and `DisplayName` (from Google `name` claim)
- [ ] On success, returns 200 with `{ accessToken, refreshToken, expiresAtUtc, userId }`
- [ ] The `accessToken` is a valid RS256-signed JWT containing claims: `sub` (AuthService `user_id`), `email`, `jti`, `iat`, `exp`, `iss`
- [ ] If Google token validation fails (expired, invalid signature), return 401 with `&quot;Invalid Google token&quot;`
- [ ] Tests cover: new user creation, existing user resolution, rejected unverified email, invalid token

#### Acceptance Tests  
1. **Scenario**: New user authenticates with valid Google ID token\
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
2. **Scenario**: Returning user authenticates with valid Google ID token\
   Given the API is running\  
   And a user already exists with a known Google subject ID\  
   When a BFF backend sends `POST /v1/auth/google` with a valid Google ID token for that subject\  
   Then the response status code should be 200\  
   And no new user should be created\  
   And the response `userId` should match the existing user's ID  
3. **Scenario**: Google token with email_verified=false is rejected\
   Given the API is running\  
   When a BFF backend sends `POST /v1/auth/google` with a Google ID token where `email_verified` is `false`\  
   Then the response status code should be 400\  
   And the response body should contain `&quot;Email not verified by Google&quot;`  
4. **Scenario**: Invalid or expired Google token is rejected\
   Given the API is running\  
   When a BFF backend sends `POST /v1/auth/google` with an invalid or expired Google ID token\  
   Then the response status code should be 401\  
   And the response body should contain `&quot;Invalid Google token&quot;`  

#### Extra Information  
- Use the `Google.Apis.Auth` NuGet package (`GoogleJsonWebSignature.ValidateAsync`) for token validation.
- In integration tests, mock the Google token validation to avoid external dependencies.
- The Google ID token contains claims: `sub`, `email`, `email_verified`, `name`, `picture`, `iss`, `aud`.
- The `aud` claim must match the configured Google Client ID for the AuthService.
- Google Client ID should be configurable via `appsettings.json` under `Authentication:Google:ClientId`.

### Story: ⚙️ Google OAuth configuration (008)
**WorkItemId**: 1318  
**tags**: configuration; gmdAuthSvc; googleOidc  
**SP**: 1  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: Service starts successfully with valid Google Client ID\
   Given `appsettings.json` has `Authentication:Google:ClientId` set to a valid value\
   When the API starts\
   Then the service should start successfully\
   And the Google authentication endpoint should be available
2. **Scenario**: Service fails fast when Google Client ID is missing\
   Given `appsettings.json` does not have `Authentication:Google:ClientId` configured\
   When the API attempts to start\
   Then the startup should fail with an exception\
   And the error message should indicate the missing Google Client ID configuration  
**Description**  
As a deployer\  
I want the Google OAuth Client ID to be configurable per environment\  
So that dev/staging/prod use separate Google projects.  

#### Acceptance Criteria  
- [ ] `appsettings.json` contains section `Authentication:Google:ClientId`
- [ ] The Google Client ID is read from configuration at startup and injected into the validation service
- [ ] If `Authentication:Google:ClientId` is missing or empty, the service fails fast at startup with a clear error message
- [ ] `appsettings.Development.json` contains a placeholder or local Client ID
- [ ] Tests verify fail-fast behavior on missing configuration

#### Acceptance Tests  
1. **Scenario**: Service starts successfully with valid Google Client ID\
   Given `appsettings.json` has `Authentication:Google:ClientId` set to a valid value\  
   When the API starts\  
   Then the service should start successfully\  
   And the Google authentication endpoint should be available  
2. **Scenario**: Service fails fast when Google Client ID is missing\
   Given `appsettings.json` does not have `Authentication:Google:ClientId` configured\  
   When the API attempts to start\  
   Then the startup should fail with an exception\  
   And the error message should indicate the missing Google Client ID configuration  


## Feature: 🏗️ CI Pipeline & Build (001)
<!-- WARNING: State 'Released' is NOT in the writable states list for Feature items.
     Writable states: New, Planning, Planning Done, Ready for Development, Active
     During reimport, any state changes will be ignored. Do NOT modify the state field. -->

**WorkItemId**: 1306  
**tags**: build; ciPipeline; gmdAuthSvc; infrastructure  
**Effort**: 2  
**State**: Released ⚠️ (read-only)  
**Description**  
Ensure the solution builds, all tests pass, and artifacts are published in the CI pipeline.\  
The Azure DevOps pipeline template is already referenced; this feature validates the end-to-end flow.\  
This must be green before any other work begins.  

### Story: 🔧 CI pipeline builds solution and runs tests (001)
<!-- WARNING: State 'Released' is NOT in the writable states list for Story items.
     Writable states: New, Active, Design, Ready for Development, Under Development
     During reimport, any state changes will be ignored. Do NOT modify the state field. -->

**WorkItemId**: 1307  
**tags**: build; ci; gmdAuthSvc; pipeline  
**SP**: 0.5  
**State**: Released ⚠️ (read-only)  
**Custom.ACScenarios**: 1. **Scenario**: Solution builds successfully\
   Given the CI pipeline triggers on a commit\
   When `dotnet build TheSln.sln` executes\
   Then the build should complete with exit code 0\
   And no compiler warnings should be present
2. **Scenario**: All tests pass in CI\
   Given the CI pipeline has built the solution\
   When `dotnet test TheSln.sln` executes\
   Then all tests should pass\
   And test results should be published as pipeline artifacts  
**Custom.ExtraInformation**: - The CI template `base-ci-dotnet-web.yaml` from `buildTemplates` is already referenced.
- `paramSlnFile: TheSln.sln` is set.
- Verify `paramPublishBuildArtifacts: true` produces the expected API artifact for CD.  
**Description**  
As a developer\nI want the CI pipeline to build the solution and run all tests\nSo that every commit is validated automatically.  

#### Acceptance Criteria  
- [ ] `dotnet build TheSln.sln` completes without errors
- [ ] `dotnet test TheSln.sln` runs all NUnit tests and reports results
- [ ] Pipeline YAML (`ci-azure-pipeline.yaml`) is configured with correct solution path
- [ ] Test results are published as pipeline artifacts
- [ ] All introduced code has unit/integration test coverage

#### Acceptance Tests  
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


## Feature: 🗄️ Database Schema & Migrations (002)
**WorkItemId**: 1308  
**tags**: database; efcore; gmdAuthSvc; migrations; schema  
**Effort**: 3  
**State**: New  
**Description**  
### Overview
**As a** developer    
**I want** to set up the EF Core data model and database migrations for the authentication service MVP    
**So that** user records, signing keys, and refresh tokens are persisted with proper schema and validation    

### Architecture
The authentication service uses SQL Server with Entity Framework Core. The MVP requires three main tables:  
- **Users**: Core user identity linked to Google OAuth
- **SigningKeys**: RSA key pairs for JWT token signing
- **RefreshTokens**: Token state management for session handling

Migrations apply automatically at startup via `Database.Migrate()` when `EnableDbMigrationsAtStartup` is configured. The chassis library provides mutex-based guards for scaled-out deployments.  

### Implementation Notes
- SQL Server provider configured via `DbContextSqlServer`
- `DesignTimeDbContextFactory` uses `(localdb)\MSSQLLocalDB` for tooling
- All migrations are idempotent and can be safely re-applied

### Story: 🗃️ EF Core migration creates MVP schema (002)
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

#### Acceptance Tests  
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

#### Extra Information  
- `DesignTimeDbContextFactory` uses `(localdb)\MSSQLLocalDB` for migration tooling.
- The chassi library provides mutex-based migration guard for scaled-out deployments.

### Story: 🔄 Create RefreshTokens table for session management (004)
**WorkItemId**: 1698  
**SP**: 2  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: RefreshTokens table is created with correct structure
   Given a fresh SQL Server database with no tables
   When the EF Core migration is applied
   Then the `RefreshTokens` table should exist in the database
   And the table should have exactly 6 columns with correct names and types
   And `TokenHash` unique index should exist
   And composite index on (UserId, IsRevoked) should exist

2. **Scenario**: TokenHash uniqueness is enforced
   Given the RefreshTokens table exists
   When inserting a record with TokenHash = &quot;abc123xyz&quot;
   Then the first insert succeeds
   And a second insert with the same TokenHash fails with constraint violation

3. **Scenario**: Foreign key constraint on UserId is enforced
   Given the RefreshTokens table exists
   When inserting a record with UserId = 999 (non-existent user)
   Then the insert fails with foreign key constraint violation

4. **Scenario**: IsRevoked default value is applied
   Given the RefreshTokens table exists
   When inserting a record without specifying IsRevoked
   Then IsRevoked should default to 0 (not revoked/active)

5. **Scenario**: Timestamps are automatically populated
   Given the RefreshTokens table exists
   When inserting a record with CreatedAtUtc not specified
   Then CreatedAtUtc should be populated with current UTC time

6. **Scenario**: QueryPerformance with composite index
   Given the RefreshTokens table has 1000 records
   When querying for all active (not revoked) tokens for a specific user
   Then the query should use the composite index on (UserId, IsRevoked)
   And the query should complete efficiently (execution plan should indicate index seek)

7. **Scenario**: Migration is idempotent
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
- [ ] Migration creates `RefreshTokens` table with exact schema (6 columns as specified)
- [ ] `Id` is PRIMARY KEY with IDENTITY(1,1)
- [ ] `TokenHash` VARCHAR(512) with UNIQUE constraint (prevents duplicate tokens)
- [ ] `UserId` BIGINT with NOT NULL constraint
- [ ] `ExpiresAtUtc` DATETIME2(7) with NOT NULL constraint
- [ ] `CreatedAtUtc` DATETIME2(7) with default GETUTCDATE()
- [ ] `IsRevoked` BIT field with default 0
- [ ] Foreign key constraint exists from `UserId` to `Users.Id`
- [ ] Unique index on `TokenHash` exists
- [ ] Non-unique index on `UserId` exists
- [ ] Non-unique index on `IsRevoked` exists
- [ ] Composite index on (UserId, IsRevoked) exists for efficient queries
- [ ] Unit test verifies table structure matches schema
- [ ] Migration is idempotent

#### Acceptance Tests  
1. **Scenario**: RefreshTokens table is created with correct structure
   Given a fresh SQL Server database with no tables  
   When the EF Core migration is applied  
   Then the `RefreshTokens` table should exist in the database  
   And the table should have exactly 6 columns with correct names and types  
   And `TokenHash` unique index should exist  
   And composite index on (UserId, IsRevoked) should exist  

2. **Scenario**: TokenHash uniqueness is enforced
   Given the RefreshTokens table exists  
   When inserting a record with TokenHash = &quot;abc123xyz&quot;  
   Then the first insert succeeds  
   And a second insert with the same TokenHash fails with constraint violation  

3. **Scenario**: Foreign key constraint on UserId is enforced
   Given the RefreshTokens table exists  
   When inserting a record with UserId = 999 (non-existent user)  
   Then the insert fails with foreign key constraint violation  

4. **Scenario**: IsRevoked default value is applied
   Given the RefreshTokens table exists  
   When inserting a record without specifying IsRevoked  
   Then IsRevoked should default to 0 (not revoked/active)  

5. **Scenario**: Timestamps are automatically populated
   Given the RefreshTokens table exists  
   When inserting a record with CreatedAtUtc not specified  
   Then CreatedAtUtc should be populated with current UTC time  

6. **Scenario**: QueryPerformance with composite index
   Given the RefreshTokens table has 1000 records  
   When querying for all active (not revoked) tokens for a specific user  
   Then the query should use the composite index on (UserId, IsRevoked)  
   And the query should complete efficiently (execution plan should indicate index seek)  

7. **Scenario**: Migration is idempotent
   Given the RefreshTokens table already exists  
   When the EF Core migration is applied again  
   Then the migration completes successfully  
   And no duplicate tables or indexes are created  

### Story: 🔐 Create SigningKeys table for JWT token signing (003)
**WorkItemId**: 1310  
**tags**: gmdAuthSvc; rsa; signingKey; startup  
**SP**: 1  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: SigningKeys table is created with correct structure
   Given a fresh SQL Server database with no tables
   When the EF Core migration is applied
   Then the `SigningKeys` table should exist
   And the table should have exactly 7 columns
   And `KeyId` unique index should exist
   And `IsActive` index should exist

2. **Scenario**: KeyId uniqueness is enforced
   Given the SigningKeys table exists
   When inserting a record with KeyId = &quot;signing-key-001&quot;
   Then the first insert succeeds
   And a second insert with the same KeyId fails with constraint violation

3. **Scenario**: IsActive default value is applied
   Given the SigningKeys table exists
   When inserting a record without specifying IsActive
   Then IsActive should default to 1 (true/active)

4. **Scenario**: Timestamps are automatically populated
   Given the SigningKeys table exists
   When inserting a record with CreatedAtUtc and ExpiresAtUtc not specified
   Then CreatedAtUtc should be populated with current UTC time
   And ExpiresAtUtc should be NULL

5. **Scenario**: Large PEM-encoded keys can be stored
   Given the SigningKeys table exists
   When inserting a record with a full 2048-bit RSA key pair (approximately 3KB for both keys)
   Then the insert succeeds
   And both PublicKey and PrivateKey fields store the complete keys

6. **Scenario**: Migration is idempotent
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
- [ ] Migration creates `SigningKeys` table with exact schema (7 columns as specified)
- [ ] `Id` is PRIMARY KEY with IDENTITY(1,1)
- [ ] `KeyId` VARCHAR(100) with UNIQUE constraint
- [ ] `PublicKey` TEXT field (can hold full PEM-encoded RSA public keys)
- [ ] `PrivateKey` TEXT field (can hold full PEM-encoded RSA private keys)
- [ ] `IsActive` BIT field with default 1
- [ ] `CreatedAtUtc` DATETIME2(7) with default GETUTCDATE()
- [ ] `ExpiresAtUtc` DATETIME2(7) nullable with default NULL
- [ ] Unique index on `KeyId` exists
- [ ] Non-unique index on `IsActive` exists
- [ ] Unit test verifies table structure matches schema
- [ ] Migration is idempotent

#### Acceptance Tests  
1. **Scenario**: SigningKeys table is created with correct structure
   Given a fresh SQL Server database with no tables  
   When the EF Core migration is applied  
   Then the `SigningKeys` table should exist  
   And the table should have exactly 7 columns  
   And `KeyId` unique index should exist  
   And `IsActive` index should exist  

2. **Scenario**: KeyId uniqueness is enforced
   Given the SigningKeys table exists  
   When inserting a record with KeyId = &quot;signing-key-001&quot;  
   Then the first insert succeeds  
   And a second insert with the same KeyId fails with constraint violation  

3. **Scenario**: IsActive default value is applied
   Given the SigningKeys table exists  
   When inserting a record without specifying IsActive  
   Then IsActive should default to 1 (true/active)  

4. **Scenario**: Timestamps are automatically populated
   Given the SigningKeys table exists  
   When inserting a record with CreatedAtUtc and ExpiresAtUtc not specified  
   Then CreatedAtUtc should be populated with current UTC time  
   And ExpiresAtUtc should be NULL  

5. **Scenario**: Large PEM-encoded keys can be stored
   Given the SigningKeys table exists  
   When inserting a record with a full 2048-bit RSA key pair (approximately 3KB for both keys)  
   Then the insert succeeds  
   And both PublicKey and PrivateKey fields store the complete keys  

6. **Scenario**: Migration is idempotent
   Given the SigningKeys table already exists  
   When the EF Core migration is applied again  
   Then the migration completes successfully  
   And no duplicate tables or indexes are created  


## Feature: 🔒 API Security — BFF-Only Access (011)
**WorkItemId**: 1333  
**tags**: apiSecurity; authorization; bffOnly; gmdAuthSvc  
**Effort**: 2  
**State**: New  
**Description**  
Ensure only authorized BFF backends can call the AuthService API.\  
Implement API key or shared secret authentication for the AuthService endpoints\  
(except health and JWKS which remain public). This prevents arbitrary clients from calling the service.  

### Story: 🔐 API key authentication for BFF backends (018)
**WorkItemId**: 1334  
**tags**: apiKey; bffAuth; gmdAuthSvc; security  
**SP**: 2  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: Valid API key grants access to auth endpoint\
   Given the API is running with `ApiSecurity:ApiKey` set to `&quot;my-secret-key&quot;`\
   When a request to `POST /v1/auth/google` includes header `X-Api-Key: my-secret-key`\
   Then the request should proceed to the endpoint handler
2. **Scenario**: Missing API key returns 401\
   Given the API is running\
   When a request to `POST /v1/auth/google` does not include an `X-Api-Key` header\
   Then the response status code should be 401\
   And the response body should contain `&quot;Invalid or missing API key&quot;`
3. **Scenario**: JWKS endpoint is accessible without API key\
   Given the API is running\
   When a request to `GET /v1/auth/jwks` is made without an `X-Api-Key` header\
   Then the response status code should be 200
4. **Scenario**: Health endpoint is accessible without API key\
   Given the API is running\
   When a request to `GET /v1/health` is made without an `X-Api-Key` header\
   Then the response status code should be 200  
**Description**  
As the AuthService\  
I want to authenticate incoming requests from BFF backends via an API key\  
So that only authorized backends can exchange tokens.  

#### Acceptance Criteria  
- [ ] A middleware or filter validates the `X-Api-Key` header on protected endpoints (`/v1/auth/google`, `/v1/auth/refresh`)
- [ ] The expected API key is configurable via `ApiSecurity:ApiKey` in `appsettings.json`
- [ ] Requests without a valid API key return 401 with `&quot;Invalid or missing API key&quot;`
- [ ] Health (`/v1/health`) and JWKS (`/v1/auth/jwks`) endpoints do **not** require an API key
- [ ] If `ApiSecurity:ApiKey` is not configured, the service fails fast at startup
- [ ] Tests cover: valid key accepted, missing key rejected, wrong key rejected, public endpoints accessible

#### Acceptance Tests  
1. **Scenario**: Valid API key grants access to auth endpoint\
   Given the API is running with `ApiSecurity:ApiKey` set to `&quot;my-secret-key&quot;`\  
   When a request to `POST /v1/auth/google` includes header `X-Api-Key: my-secret-key`\  
   Then the request should proceed to the endpoint handler  
2. **Scenario**: Missing API key returns 401\
   Given the API is running\  
   When a request to `POST /v1/auth/google` does not include an `X-Api-Key` header\  
   Then the response status code should be 401\  
   And the response body should contain `&quot;Invalid or missing API key&quot;`  
3. **Scenario**: JWKS endpoint is accessible without API key\
   Given the API is running\  
   When a request to `GET /v1/auth/jwks` is made without an `X-Api-Key` header\  
   Then the response status code should be 200  
4. **Scenario**: Health endpoint is accessible without API key\
   Given the API is running\  
   When a request to `GET /v1/health` is made without an `X-Api-Key` header\  
   Then the response status code should be 200  


## Feature: 🏥 Health Check Endpoints (003)
**WorkItemId**: 1311  
**tags**: gmdAuthSvc; health; monitoring; observability  
**Effort**: 1  
**State**: New  
**Description**  
### Overview
**As a** DevOps engineer    
**I want** comprehensive health check endpoints for monitoring    
**So that** load balancers, orchestrators, and monitoring systems can verify service health    

### Endpoints
The service exposes two health check endpoints:  
- `/health` - Liveness probe (is the service running?)
- `/health/ready` - Readiness probe (are dependencies ready?)

### Health Response
Both endpoints return HTTP 200 with detailed component status:  
- Service status (running/ready)
- Database connectivity
- Signing keys availability
- Any critical dependencies

### Use Cases
- Kubernetes liveness/readiness probes
- Load balancer health checks
- Monitoring system ping endpoints

### Story: 🫀 HEAD health endpoint for lightweight probes (005)
**WorkItemId**: 1313  
**tags**: gmdAuthSvc; health; probe  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: HEAD health returns 204\
   Given the API is running\
   When I make a HEAD request to `/v1/health`\
   Then the response status code should be 204\
   And the response body should be empty  
**Description**  
As a load balancer\  
I want a HEAD health endpoint that returns 204\  
So that I can perform fast health probes without body parsing.  

#### Acceptance Criteria  
- [ ] `HEAD /v1/health` returns 204 No Content
- [ ] No response body is returned
- [ ] Integration test verifies the endpoint

#### Acceptance Tests  
1. **Scenario**: HEAD health returns 204\
   Given the API is running\  
   When I make a HEAD request to `/v1/health`\  
   Then the response status code should be 204\  
   And the response body should be empty  

### Story: 💓 GET health endpoint returns status (004)
**WorkItemId**: 1312  
**tags**: api; gmdAuthSvc; health  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: GET health returns healthy status\
   Given the API is running\
   When I make a GET request to `/v1/health`\
   Then the response status code should be 200\
   And the response body should contain a `status` field with value `&quot;healthy&quot;`\
   And the response body should contain a `timestampUtc` field  
**Description**  
As an infrastructure operator\  
I want a GET health endpoint that returns the service status\  
So that I can monitor whether the API is operational.  

#### Acceptance Criteria  
- [ ] `GET /v1/health` returns 200 with JSON body `{ status, timestampUtc }`
- [ ] The `status` field value is `&quot;healthy&quot;`
- [ ] Response content type is `application/json`
- [ ] Integration test verifies the endpoint

#### Acceptance Tests  
1. **Scenario**: GET health returns healthy status\
   Given the API is running\  
   When I make a GET request to `/v1/health`\  
   Then the response status code should be 200\  
   And the response body should contain a `status` field with value `&quot;healthy&quot;`\  
   And the response body should contain a `timestampUtc` field  

### Story: 🔍 Implement liveness probe /health endpoint (001)
**WorkItemId**: 1699  
**SP**: 1  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: Liveness probe returns 200 when service is running
   Given the service is running
   When GET /health is called
   Then HTTP 200 OK is returned
   And response time is &lt; 10ms
   And response contains `{ &quot;status&quot;: &quot;healthy&quot; }`

2. **Scenario**: Liveness probe works even if database is down
   Given the service is running but database is unreachable
   When GET /health is called
   Then HTTP 200 OK is returned
   (Database connectivity should not affect liveness)

3. **Scenario**: Liveness probe requires no authentication
   Given the service is running
   When GET /health is called without authentication token
   Then HTTP 200 OK is returned
   And the endpoint is accessible by orchestrators  
**Description**  
#### Liveness Probe
**As a** DevOps engineer    
**I want** a basic `/health` liveness endpoint    
**So that** orchestrators know if the service process is running    

**Endpoint Details:**  
- HTTP GET `/health`
- Returns 200 OK immediately if service is running
- Response time &lt; 10ms
- No dependency checks on liveness probe
- JSON response: `{ &quot;status&quot;: &quot;healthy&quot; }`

#### Acceptance Criteria  
- [ ] GET `/health` endpoint exists and is accessible
- [ ] Returns HTTP 200 OK when service is running
- [ ] Response time is &lt; 10ms (liveness should be fast)
- [ ] Response body contains JSON with status field
- [ ] No database queries or dependency checks in liveness probe
- [ ] Endpoint works even if database is down
- [ ] Works without authentication/authorization
- [ ] Unit test verifies endpoint response and timing

#### Acceptance Tests  
1. **Scenario**: Liveness probe returns 200 when service is running
   Given the service is running  
   When GET /health is called  
   Then HTTP 200 OK is returned  
   And response time is &lt; 10ms  
   And response contains `{ &quot;status&quot;: &quot;healthy&quot; }`  

2. **Scenario**: Liveness probe works even if database is down
   Given the service is running but database is unreachable  
   When GET /health is called  
   Then HTTP 200 OK is returned  
   (Database connectivity should not affect liveness)  

3. **Scenario**: Liveness probe requires no authentication
   Given the service is running  
   When GET /health is called without authentication token  
   Then HTTP 200 OK is returned  
   And the endpoint is accessible by orchestrators  

### Story: 🟢 Implement readiness probe /health/ready endpoint (002)
**WorkItemId**: 1700  
**SP**: 1  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: Readiness probe returns 200 when all dependencies are ready
   Given the service is running with full initialization
   And database is accessible
   And active signing keys exist in database
   When GET /health/ready is called
   Then HTTP 200 OK is returned
   And response includes component statuses (db: ready, keys: ready)

2. **Scenario**: Readiness probe returns 503 if database is unreachable
   Given the service is running
   And database is unreachable
   When GET /health/ready is called
   Then HTTP 503 Service Unavailable is returned
   And response indicates database connectivity issue

3. **Scenario**: Readiness probe returns 503 if no signing keys exist
   Given the service is running
   And database is accessible
   And SigningKeys table is empty
   When GET /health/ready is called
   Then HTTP 503 Service Unavailable is returned
   And response indicates missing signing keys

4. **Scenario**: Readiness probe prevents traffic to unprepared service
   Given a freshly started service before initialization
   When load balancer calls GET /health/ready
   Then HTTP 503 Service Unavailable is returned
   And traffic is not routed to this instance  
**Description**  
#### Readiness Probe
**As a** DevOps engineer    
**I want** a `/health/ready` readiness endpoint that checks dependencies    
**So that** the load balancer knows if the service is ready to accept traffic    

**Endpoint Details:**  
- HTTP GET `/health/ready`
- Returns 200 OK only if all required services are ready
- Checks: Database connectivity, signing keys exist, core features initialized
- Returns 503 Service Unavailable if any checks fail
- Response time &lt; 2 seconds (reasonable for dependency checks)

#### Acceptance Criteria  
- [ ] GET `/health/ready` endpoint exists
- [ ] Returns HTTP 200 OK when all dependencies are ready
- [ ] Returns HTTP 503 Service Unavailable if database is down
- [ ] Returns HTTP 503 if no SigningKeys exist in database
- [ ] Checks database connectivity with a simple query
- [ ] Checks that at least one active signing key exists
- [ ] Response time is &lt; 2 seconds
- [ ] Response includes detailed component status
- [ ] Works without authentication/authorization
- [ ] Unit test verifies readiness checks

#### Acceptance Tests  
1. **Scenario**: Readiness probe returns 200 when all dependencies are ready
   Given the service is running with full initialization  
   And database is accessible  
   And active signing keys exist in database  
   When GET /health/ready is called  
   Then HTTP 200 OK is returned  
   And response includes component statuses (db: ready, keys: ready)  

2. **Scenario**: Readiness probe returns 503 if database is unreachable
   Given the service is running  
   And database is unreachable  
   When GET /health/ready is called  
   Then HTTP 503 Service Unavailable is returned  
   And response indicates database connectivity issue  

3. **Scenario**: Readiness probe returns 503 if no signing keys exist
   Given the service is running  
   And database is accessible  
   And SigningKeys table is empty  
   When GET /health/ready is called  
   Then HTTP 503 Service Unavailable is returned  
   And response indicates missing signing keys  

4. **Scenario**: Readiness probe prevents traffic to unprepared service
   Given a freshly started service before initialization  
   When load balancer calls GET /health/ready  
   Then HTTP 503 Service Unavailable is returned  
   And traffic is not routed to this instance  


## Feature: 📦 AuthService Client Library — NuGet Package (008)
**WorkItemId**: 1324  
**tags**: bffIntegration; clientLib; gmdAuthSvc; nuget; reusable  
**Effort**: 8  
**State**: New  
**Description**  
A reusable NuGet package `Gmd.AuthService.ClientLib` that consuming BFF backends reference to interact with the AuthService.\  
Encapsulates all HTTP communication, Google-token-to-AuthService-JWT exchange, automatic refresh token handling,\  
and JWT validation via JWKS. This ensures no consuming application duplicates AuthService integration logic.  

### Story: 🔄 Automatic token refresh middleware (014)
**WorkItemId**: 1327  
**tags**: clientLib; gmdAuthSvc; middleware; tokenRefresh  
**SP**: 3  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: Token manager returns cached non-expired token\
   Given the token manager holds a valid access token expiring in 5 minutes\
   When `GetValidAccessTokenAsync()` is called\
   Then the existing access token should be returned\
   And no refresh HTTP call should be made
2. **Scenario**: Token manager auto-refreshes near-expiry token\
   Given the token manager holds an access token expiring in 20 seconds\
   When `GetValidAccessTokenAsync()` is called\
   Then the token manager should call `RefreshTokenAsync` on the AuthService client\
   And return the new access token\
   And store the new refresh token
3. **Scenario**: Token manager throws when refresh token is invalid\
   Given the token manager holds an expired access token\
   And the refresh token is revoked or expired\
   When `GetValidAccessTokenAsync()` is called\
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

#### Acceptance Tests  
1. **Scenario**: Token manager returns cached non-expired token\
   Given the token manager holds a valid access token expiring in 5 minutes\  
   When `GetValidAccessTokenAsync()` is called\  
   Then the existing access token should be returned\  
   And no refresh HTTP call should be made  
2. **Scenario**: Token manager auto-refreshes near-expiry token\
   Given the token manager holds an access token expiring in 20 seconds\  
   When `GetValidAccessTokenAsync()` is called\  
   Then the token manager should call `RefreshTokenAsync` on the AuthService client\  
   And return the new access token\  
   And store the new refresh token  
3. **Scenario**: Token manager throws when refresh token is invalid\
   Given the token manager holds an expired access token\  
   And the refresh token is revoked or expired\  
   When `GetValidAccessTokenAsync()` is called\  
   Then an `AuthServiceTokenExpiredException` should be thrown  

### Story: 📦 Create client library project structure (012)
**WorkItemId**: 1325  
**tags**: clientLib; gmdAuthSvc; projectSetup  
**SP**: 1  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: Client library project compiles\
   Given the `Gmd.AuthService.ClientLib` project exists under `src/`\
   When I run `dotnet build TheSln.sln`\
   Then the build should complete successfully\
   And `Gmd.AuthService.ClientLib.dll` should be in the build output
2. **Scenario**: Client library has no forbidden dependencies\
   Given the `Gmd.AuthService.ClientLib` project file exists\
   When I inspect its `ProjectReference` and `PackageReference` items\
   Then it should not reference `Gmd.AuthService.WebApi`\
   And it should not reference `Gmd.AuthService.DbContext`  
**Description**  
As a developer\  
I want the `Gmd.AuthService.ClientLib` project created with proper structure\  
So that it can be packaged as a NuGet and consumed by BFF backends.  

#### Acceptance Criteria  
- [ ] A new class library project `Gmd.AuthService.ClientLib` is created under `src/`
- [ ] The project targets `net8.0` (or matching the solution's target framework)
- [ ] The `.csproj` contains NuGet packaging metadata: `PackageId`, `Version`, `Description`, `Authors`
- [ ] The project is added to `TheSln.sln`
- [ ] The project compiles without errors
- [ ] No dependency on `Gmd.AuthService.WebApi` or `Gmd.AuthService.DbContext` (the client lib is independent)

#### Acceptance Tests  
1. **Scenario**: Client library project compiles\
   Given the `Gmd.AuthService.ClientLib` project exists under `src/`\  
   When I run `dotnet build TheSln.sln`\  
   Then the build should complete successfully\  
   And `Gmd.AuthService.ClientLib.dll` should be in the build output  
2. **Scenario**: Client library has no forbidden dependencies\
   Given the `Gmd.AuthService.ClientLib` project file exists\  
   When I inspect its `ProjectReference` and `PackageReference` items\  
   Then it should not reference `Gmd.AuthService.WebApi`\  
   And it should not reference `Gmd.AuthService.DbContext`  

### Story: 🔌 AuthService HTTP client service (013)
**WorkItemId**: 1326  
**tags**: clientLib; gmdAuthSvc; httpClient; serviceInterface  
**SP**: 2  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: BFF registers and resolves the AuthService client\
   Given a BFF backend calls `services.AddAuthServiceClient(opts =&gt; opts.BaseUrl = &quot;https://auth.example.com&quot;)`\
   When the `IAuthServiceClient` is resolved from the DI container\
   Then a valid `AuthServiceClient` instance should be returned\
   And its underlying `HttpClient.BaseAddress` should be `&quot;https://auth.example.com&quot;`
2. **Scenario**: Client exchanges Google token for AuthService JWT\
   Given the AuthService is reachable at the configured base URL\
   When the BFF calls `AuthenticateWithGoogleAsync` with a valid Google ID token\
   Then the client should POST to `/v1/auth/google` with the token\
   And return the deserialized `AuthTokenResponse`
3. **Scenario**: Client refreshes tokens\
   Given the AuthService is reachable at the configured base URL\
   When the BFF calls `RefreshTokenAsync` with a valid refresh token\
   Then the client should POST to `/v1/auth/refresh`\
   And return the deserialized `AuthTokenResponse` with new tokens  
**Description**  
As a BFF backend developer\  
I want a typed HTTP client (`IAuthServiceClient`) in the client library\  
So that I can call AuthService endpoints in a strongly-typed manner.  

#### Acceptance Criteria  
- [ ] Interface `IAuthServiceClient` is defined with methods:
  - `Task AuthenticateWithGoogleAsync(string googleIdToken, CancellationToken ct)`
  - `Task RefreshTokenAsync(string refreshToken, CancellationToken ct)`
  - `Task GetJwksAsync(CancellationToken ct)`
- [ ] Implementation `AuthServiceClient` uses `HttpClient` to call AuthService REST endpoints
- [ ] `AuthServiceClientOptions` class configurable via `IOptions` pattern: `BaseUrl` (required)
- [ ] DI extension method `AddAuthServiceClient(this IServiceCollection, Action)` registers the typed client
- [ ] HttpClient is registered via `IHttpClientFactory` for proper lifecycle management
- [ ] Unit tests verify DI registration and HTTP calls (using mock HTTP handler)

#### Acceptance Tests  
1. **Scenario**: BFF registers and resolves the AuthService client\
   Given a BFF backend calls `services.AddAuthServiceClient(opts =&gt; opts.BaseUrl = &quot;https://auth.example.com&quot;)`\  
   When the `IAuthServiceClient` is resolved from the DI container\  
   Then a valid `AuthServiceClient` instance should be returned\  
   And its underlying `HttpClient.BaseAddress` should be `&quot;https://auth.example.com&quot;`  
2. **Scenario**: Client exchanges Google token for AuthService JWT\
   Given the AuthService is reachable at the configured base URL\  
   When the BFF calls `AuthenticateWithGoogleAsync` with a valid Google ID token\  
   Then the client should POST to `/v1/auth/google` with the token\  
   And return the deserialized `AuthTokenResponse`  
3. **Scenario**: Client refreshes tokens\
   Given the AuthService is reachable at the configured base URL\  
   When the BFF calls `RefreshTokenAsync` with a valid refresh token\  
   Then the client should POST to `/v1/auth/refresh`\  
   And return the deserialized `AuthTokenResponse` with new tokens  

### Story: ✅ JWT validation helper using JWKS (015)
**WorkItemId**: 1328  
**tags**: clientLib; gmdAuthSvc; jwks; jwtValidation  
**SP**: 2  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: Valid AuthService JWT is accepted\
   Given the JWKS endpoint returns the signing public key\
   And a valid RS256-signed JWT is presented\
   When `ValidateTokenAsync` is called with the token\
   Then a `ClaimsPrincipal` should be returned\
   And the principal should have a `sub` claim with the user's ID\
   And the principal should have an `email` claim
2. **Scenario**: Expired JWT is rejected\
   Given the JWKS endpoint returns the signing public key\
   And an expired RS256-signed JWT is presented\
   When `ValidateTokenAsync` is called with the token\
   Then an `AuthServiceTokenValidationException` should be thrown
3. **Scenario**: JWT with wrong issuer is rejected\
   Given a valid RS256-signed JWT with `iss = &quot;WrongIssuer&quot;`\
   When `ValidateTokenAsync` is called with the token\
   Then an `AuthServiceTokenValidationException` should be thrown
4. **Scenario**: JWKS is cached and not fetched on every call\
   Given the JWKS has been fetched within the last hour\
   When `ValidateTokenAsync` is called\
   Then the cached JWKS should be used\
   And no HTTP request to the JWKS endpoint should be made  
**Description**  
As a BFF backend developer\  
I want the client library to validate AuthService JWTs using the JWKS endpoint\  
So that I can trust the `user_id` and `email` claims in incoming tokens.  

#### Acceptance Criteria  
- [ ] A service `IAuthServiceJwtValidator` provides method `Task ValidateTokenAsync(string accessToken, CancellationToken ct)`
- [ ] Validation fetches the JWKS from the AuthService (with a configurable cache duration, default 1 hour)
- [ ] Validation checks: RS256 signature, `iss = &quot;GmdAuthService&quot;`, token not expired
- [ ] Invalid or expired tokens throw `AuthServiceTokenValidationException`
- [ ] Successfully validated tokens return a `ClaimsPrincipal` with `sub` (user_id) and `email` claims accessible
- [ ] DI extension method registers the validator
- [ ] Unit tests verify validation with mock JWKS, valid/invalid/expired tokens

#### Acceptance Tests  
1. **Scenario**: Valid AuthService JWT is accepted\
   Given the JWKS endpoint returns the signing public key\  
   And a valid RS256-signed JWT is presented\  
   When `ValidateTokenAsync` is called with the token\  
   Then a `ClaimsPrincipal` should be returned\  
   And the principal should have a `sub` claim with the user's ID\  
   And the principal should have an `email` claim  
2. **Scenario**: Expired JWT is rejected\
   Given the JWKS endpoint returns the signing public key\  
   And an expired RS256-signed JWT is presented\  
   When `ValidateTokenAsync` is called with the token\  
   Then an `AuthServiceTokenValidationException` should be thrown  
3. **Scenario**: JWT with wrong issuer is rejected\
   Given a valid RS256-signed JWT with `iss = &quot;WrongIssuer&quot;`\  
   When `ValidateTokenAsync` is called with the token\  
   Then an `AuthServiceTokenValidationException` should be thrown  
4. **Scenario**: JWKS is cached and not fetched on every call\
   Given the JWKS has been fetched within the last hour\  
   When `ValidateTokenAsync` is called\  
   Then the cached JWKS should be used\  
   And no HTTP request to the JWKS endpoint should be made  


## Feature: 📋 OpenAPI Specification (012)
**WorkItemId**: 1335  
**tags**: apiDocs; gmdAuthSvc; openApi; swagger  
**Effort**: 1  
**State**: New  
**Description**  
Generate and serve an OpenAPI specification for all MVP endpoints.\  
Swagger UI should be available in development mode for manual exploration.  

### Story: 📄 Swagger/OpenAPI document is served (019)
**WorkItemId**: 1336  
**tags**: gmdAuthSvc; openApi; swagger  
**SP**: 1  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: OpenAPI spec is accessible in development\
   Given the API is running in Development mode\
   When I request `/swagger/v1/swagger.json`\
   Then the response status code should be 200\
   And the response should contain the title `&quot;GMD Auth Service API&quot;`\
   And the paths section should contain `/v1/auth/google`\
   And the paths section should contain `/v1/auth/refresh`\
   And the paths section should contain `/v1/auth/jwks`\
   And the paths section should contain `/v1/health`  
**Description**  
As an API consumer\  
I want to access the OpenAPI specification\  
So that I can understand and integrate with the AuthService MVP API.  

#### Acceptance Criteria  
- [ ] Swagger UI is enabled in Development environment at `/swagger`
- [ ] OpenAPI JSON is served at `/swagger/v1/swagger.json`
- [ ] The document title is `&quot;GMD Auth Service API&quot;` and version is `&quot;v1&quot;`
- [ ] All MVP endpoints are documented: `/v1/health`, `/v1/auth/google`, `/v1/auth/refresh`, `/v1/auth/jwks`
- [ ] Request/response schemas include examples
- [ ] Security scheme `apiKeyAuth` (header `X-Api-Key`) is documented
- [ ] Integration test verifies the spec is served and contains all endpoints

#### Acceptance Tests  
1. **Scenario**: OpenAPI spec is accessible in development\
   Given the API is running in Development mode\  
   When I request `/swagger/v1/swagger.json`\  
   Then the response status code should be 200\  
   And the response should contain the title `&quot;GMD Auth Service API&quot;`\  
   And the paths section should contain `/v1/auth/google`\  
   And the paths section should contain `/v1/auth/refresh`\  
   And the paths section should contain `/v1/auth/jwks`\  
   And the paths section should contain `/v1/health`  


## Feature: 🚢 Deployment Pipeline — Dev/Staging/Prod (009)
**WorkItemId**: 1329  
**tags**: cdPipeline; deployment; environments; gmdAuthSvc  
**Effort**: 2  
**State**: New  
**Description**  
Set up the continuous deployment pipeline to deploy the AuthService to dev, staging, and production environments.\  
Metrics and DB migration infrastructure is already available from a library;\  
this feature ensures the pipeline correctly deploys the API and runs migrations per environment.  

### Story: 🚀 CD pipeline deploys to dev, staging, and prod (016)
**WorkItemId**: 1330  
**tags**: cdPipeline; deployment; gmdAuthSvc  
**SP**: 2  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: Dev environment is deployed automatically after CI\
   Given the CI pipeline has published a successful build artifact\
   When the CD pipeline triggers for the `dev` stage\
   Then the API should be deployed to the dev environment\
   And the health endpoint should return 200 after deployment
2. **Scenario**: Production deployment requires approval\
   Given the staging deployment has completed successfully\
   When the CD pipeline reaches the `prod` stage\
   Then it should pause and wait for manual approval\
   And only proceed after approval is granted  
**Custom.ExtraInformation**: - The CD template is already referenced in `cd-azure-pipeline.yaml`.
- Separate `appsettings.Development.json`, `appsettings.Staging.json`, and `appsettings.Production.json` should be maintained.
- Google Client IDs per environment should be stored as pipeline secrets or Azure Key Vault references.  
**Description**  
As a DevOps engineer\  
I want the CD pipeline to deploy the AuthService to dev, staging, and production\  
So that each environment runs the latest validated build.  

#### Acceptance Criteria  
- [ ] `cd-azure-pipeline.yaml` defines stages for `dev`, `staging`, and `prod`
- [ ] Each stage deploys the API artifact published by the CI pipeline
- [ ] Database migrations run automatically in each environment (controlled by `EnableDbMigrationsAtStartup`)
- [ ] Environment-specific `appsettings.{Environment}.json` files are used for configuration (database connection strings, Google Client IDs)
- [ ] Production deployment requires manual approval gate
- [ ] Health endpoint is checked post-deployment to verify the service is running

#### Acceptance Tests  
1. **Scenario**: Dev environment is deployed automatically after CI\
   Given the CI pipeline has published a successful build artifact\  
   When the CD pipeline triggers for the `dev` stage\  
   Then the API should be deployed to the dev environment\  
   And the health endpoint should return 200 after deployment  
2. **Scenario**: Production deployment requires approval\
   Given the staging deployment has completed successfully\  
   When the CD pipeline reaches the `prod` stage\  
   Then it should pause and wait for manual approval\  
   And only proceed after approval is granted  

#### Extra Information  
- The CD template is already referenced in `cd-azure-pipeline.yaml`.
- Separate `appsettings.Development.json`, `appsettings.Staging.json`, and `appsettings.Production.json` should be maintained.
- Google Client IDs per environment should be stored as pipeline secrets or Azure Key Vault references.


## Feature: ⚠️ Global Exception Handling (004)
**WorkItemId**: 1314  
**tags**: errorHandling; exceptions; gmdAuthSvc; middleware  
**Effort**: 1  
**State**: New  
**Description**  
The `ExceptionMiddleware` catches all unhandled exceptions and returns standardized JSON error responses.\  
Business logic errors return 400, auth errors return 401, and unexpected errors return 500 with no leaked details.  

### Story: 🛡️ Exception middleware returns structured error responses (006)
**WorkItemId**: 1315  
**tags**: errorHandling; gmdAuthSvc; middleware  
**SP**: 1  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: Business logic error returns 400\
   Given the API is running\
   When I make a request that triggers an `InvalidOperationException`\
   Then the response status code should be 400\
   And the response body should contain an `error` field with descriptive message
2. **Scenario**: Unexpected exception returns 500 without stack trace\
   Given the API is running\
   When an unhandled exception occurs during request processing\
   Then the response status code should be 500\
   And the response body should contain `error` field with a generic message\
   And the response body should not contain a stack trace  
**Description**  
As an API consumer\  
I want standardized error responses in JSON format\  
So that I can programmatically handle errors from the API.  

#### Acceptance Criteria  
- [ ] `InvalidOperationException` returns 400 with `{ error: &quot;&quot; }`
- [ ] `UnauthorizedAccessException` returns 401 with `{ error: &quot;&quot; }`
- [ ] Unhandled exceptions return 500 with a generic error message (no stack trace leaked)
- [ ] All error responses have `Content-Type: application/json`
- [ ] Integration tests cover each error category

#### Acceptance Tests  
1. **Scenario**: Business logic error returns 400\
   Given the API is running\  
   When I make a request that triggers an `InvalidOperationException`\  
   Then the response status code should be 400\  
   And the response body should contain an `error` field with descriptive message  
2. **Scenario**: Unexpected exception returns 500 without stack trace\
   Given the API is running\  
   When an unhandled exception occurs during request processing\  
   Then the response status code should be 500\  
   And the response body should contain `error` field with a generic message\  
   And the response body should not contain a stack trace  


## Feature: 🎟️ JWT Token Generation & JWKS (006)
**WorkItemId**: 1319  
**tags**: gmdAuthSvc; jwks; jwt; rs256; tokenGeneration  
**Effort**: 5  
**State**: New  
**Description**  
### Overview
**As a** developer    
**I want** to generate JWT access tokens and publish signing key metadata    
**So that** client applications can verify token authenticity    

### JWT Access Token
- **Header**: typ=JWT, alg=RS256
- **Claims**: iss (issuer), sub (Google subject), aud (audience), iat (issued at), exp (expiration), scope
- **Signature**: RS256 with signing key from database
- **TTL**: 1 hour (3600 seconds)

### JWKS Endpoint
- **Path**: `GET /.well-known/jwks.json`
- **Content**: JSON Web Key Set with all active signing keys
- **Format**: Standard JWK format with kid, kty, use, n, e (RSA public key)
- **Caching**: Cache-Control: public, max-age=3600
- **Public**: No authentication required

### Token Verification
Clients verify tokens by:  
1. Fetch JWKS from `/.well-known/jwks.json`
2. Get token from Authorization header: `Authorization: Bearer `
3. Verify signature using matching key from JWKS

### Story: 🔏 Generate RS256-signed JWT access tokens (009)
**WorkItemId**: 1320  
**tags**: gmdAuthSvc; jwt; rs256; tokenGeneration  
**SP**: 3  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: Generated JWT contains required claims\
   Given a user exists in the database\
   When the JWT service generates an access token for the user\
   Then the token should be a valid RS256-signed JWT\
   And the token should contain `sub` claim equal to the user's ID\
   And the token should contain `email` claim equal to the user's email\
   And the token should contain `iss` claim equal to `&quot;GmdAuthService&quot;`\
   And the token should contain `exp` claim approximately 60 minutes from now
2. **Scenario**: JWT is verifiable with the public key\
   Given the JWT service generated an access token\
   When the token is validated using the public key from the signing key\
   Then validation should succeed without errors  
**Description**  
As the AuthService\  
I want to generate RS256-signed JWT access tokens\  
So that consuming services can cryptographically verify tokens using the public key.  

#### Acceptance Criteria  
- [ ] JWT is signed with the active RSA private key from the `SigningKeys` table
- [ ] JWT header contains `alg: RS256` and `kid` matching the signing key's `KeyId`
- [ ] JWT payload contains: `sub` (user ID as GUID), `email`, `jti` (unique token ID), `iat` (issued at), `exp` (expiry), `iss` (issuer = `&quot;GmdAuthService&quot;`)
- [ ] Default access token lifetime is 60 minutes (configurable via `Jwt:AccessTokenLifetimeMinutes`)
- [ ] JWT can be validated using the public key from the JWKS endpoint
- [ ] Unit tests verify token structure, claims, and signature validation

#### Acceptance Tests  
1. **Scenario**: Generated JWT contains required claims\
   Given a user exists in the database\  
   When the JWT service generates an access token for the user\  
   Then the token should be a valid RS256-signed JWT\  
   And the token should contain `sub` claim equal to the user's ID\  
   And the token should contain `email` claim equal to the user's email\  
   And the token should contain `iss` claim equal to `&quot;GmdAuthService&quot;`\  
   And the token should contain `exp` claim approximately 60 minutes from now  
2. **Scenario**: JWT is verifiable with the public key\
   Given the JWT service generated an access token\  
   When the token is validated using the public key from the signing key\  
   Then validation should succeed without errors  

### Story: 🔑 Publish JWKS endpoint for token verification (003)
**WorkItemId**: 1702  
**SP**: 1  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: JWKS endpoint returns active signing keys
   Given the service has active signing keys in database
   When GET /.well-known/jwks.json is called
   Then HTTP 200 OK is returned
   And response contains JWK array with all active keys
   And each JWK includes kid, kty=RSA, use=sig, n (modulus), e (exponent)

2. **Scenario**: JWKS endpoint excludes inactive keys
   Given the service has 3 signing keys (2 active, 1 inactive)
   When GET /.well-known/jwks.json is called
   Then response includes only 2 keys (the active ones)

3. **Scenario**: JWKS endpoint is cached to avoid database queries
   Given the service has cached the JWKS response
   When GET /.well-known/jwks.json is called multiple times
   Then database is queried only once or at specified cache interval
   And response includes Cache-Control header with appropriate TTL  
**Description**  
#### Publish JWKS Endpoint
**As a** client application    
**I want** to fetch the service''s public signing keys    
**So that** I can verify JWT tokens signed by the service    

**JWKS Endpoint Details:**  
- `GET /.well-known/jwks.json`
- Returns only active (IsActive=1) signing keys
- Format: Standard JSON Web Key Set (RFC 7517)
- Cache-Control header: public, max-age=3600
- No authentication required

#### Acceptance Criteria  
- [ ] Endpoint `GET /.well-known/jwks.json` exists and is accessible
- [ ] Returns HTTP 200 OK with JSON Web Key Set
- [ ] Response includes only active signing keys (IsActive=1)
- [ ] Each key includes: kid (key ID from database), kty=RSA, use=sig, alg=RS256
- [ ] Public key (n, e) is correctly extracted from PEM-encoded public key
- [ ] Response includes Cache-Control: public, max-age=3600 header
- [ ] Response is not authenticated (publicly accessible)
- [ ] Endpoint works even without user authentication
- [ ] Valid JWK format per RFC 7517
- [ ] Unit test verifies JWKS format and content

#### Acceptance Tests  
1. **Scenario**: JWKS endpoint returns active signing keys
   Given the service has active signing keys in database  
   When GET /.well-known/jwks.json is called  
   Then HTTP 200 OK is returned  
   And response contains JWK array with all active keys  
   And each JWK includes kid, kty=RSA, use=sig, n (modulus), e (exponent)  

2. **Scenario**: JWKS endpoint excludes inactive keys
   Given the service has 3 signing keys (2 active, 1 inactive)  
   When GET /.well-known/jwks.json is called  
   Then response includes only 2 keys (the active ones)  

3. **Scenario**: JWKS endpoint is cached to avoid database queries
   Given the service has cached the JWKS response  
   When GET /.well-known/jwks.json is called multiple times  
   Then database is queried only once or at specified cache interval  
   And response includes Cache-Control header with appropriate TTL  

### Story: 🌐 JWKS endpoint exposes public signing keys (010)
**WorkItemId**: 1321  
**tags**: gmdAuthSvc; jwks; publicKey; tokenValidation  
**SP**: 1  
**State**: New  
**Custom.ACScenarios**: 1. **Scenario**: JWKS returns RSA public keys\
   Given the API is running and a signing key exists\
   When I make a GET request to `/v1/auth/jwks`\
   Then the response status code should be 200\
   And the response should contain a `keys` array with at least one entry\
   And each key should have `kty` equal to `&quot;RSA&quot;`\
   And each key should have `alg` equal to `&quot;RS256&quot;`\
   And each key should have non-empty `n` and `e` values
2. **Scenario**: JWKS endpoint is publicly accessible\
   Given the API is running\
   When I make a GET request to `/v1/auth/jwks` without any authentication header\
   Then the response status code should be 200  
**Description**  
As a BFF backend (or its client library)\  
I want to fetch the public signing keys from the JWKS endpoint\  
So that I can validate JWT tokens issued by the AuthService.  

#### Acceptance Criteria  
- [ ] `GET /v1/auth/jwks` returns 200 with `{ keys: [...] }`
- [ ] Each key contains `kty`, `use`, `kid`, `n`, `e`, `alg` fields
- [ ] `kty` is `&quot;RSA&quot;`, `use` is `&quot;sig&quot;`, `alg` is `&quot;RS256&quot;`
- [ ] The endpoint is publicly accessible (`[AllowAnonymous]`)
- [ ] At least one active key is always present
- [ ] Integration test verifies JWKS response structure

#### Acceptance Tests  
1. **Scenario**: JWKS returns RSA public keys\
   Given the API is running and a signing key exists\  
   When I make a GET request to `/v1/auth/jwks`\  
   Then the response status code should be 200\  
   And the response should contain a `keys` array with at least one entry\  
   And each key should have `kty` equal to `&quot;RSA&quot;`\  
   And each key should have `alg` equal to `&quot;RS256&quot;`\  
   And each key should have non-empty `n` and `e` values  
2. **Scenario**: JWKS endpoint is publicly accessible\
   Given the API is running\  
   When I make a GET request to `/v1/auth/jwks` without any authentication header\  
   Then the response status code should be 200  



