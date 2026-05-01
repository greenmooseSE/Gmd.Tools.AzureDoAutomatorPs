# Epic: TimeTracker

{WorkItemId}: 2735  
{State}: New  
{tags}: epicTimeTracker  
{Effort}: 100  
{Description}  
TimeTracker represents the long-term development and continuous evolution of a cross-platform  
solution for simple, reliable, and flexible time tracking. The product is designed to operate  
independently of external systems while offering optional integrations that enhance the user  
experience without creating dependencies.  

TimeTracker provides a unified experience across web and native clients, initially targeting  
Windows and Android through a shared codebase (Blazor Hybrid MAUI), with future expansion to  
iOS and macOS. The application supports offline usage, allowing users to track time locally  
and automatically synchronize their data with the central backend when connectivity is restored.  
All time entries are stored in the TimeTracker backend to ensure consistency, resilience, and  
uninterrupted operation even if external services are unavailable.  

The solution includes built-in reporting capabilities, enabling users to review and analyze  
their logged time directly within the application. An optional Azure DevOps integration allows  
users to browse stories in the current or upcoming sprint, select supported task types, and  
automatically create or update tasks based on configurable rules. TimeTracker manages the logic  
for assigning users, logging time, and determining the appropriate level of granularity for  
task creation and aggregation.  

This epic is a permanent, long-lived container for the overarching purpose, direction, and  
identity of TimeTracker. Individual features are planned, delivered, and closed over time,  
while the epic remains open to represent the product's ongoing evolution.  

### Vision  

Simple, reliable, and flexible time tracking — independent of external systems,  
with optional integrations (starting with Azure DevOps) that enhance workflows  
without creating hard dependencies.  

### Core Feature Areas  

- **Standalone Time Tracking** — Users track time directly against the TimeTracker backend.  
  All entries are stored centrally for long-term reliability and consistency.  
- **Optional Azure DevOps Integration** — Connect an AzDo account, browse sprint stories,  
  configure allowed task types, and auto-create or update tasks from time entries.  
- **Task Creation and Aggregation Logic** — Time is grouped by configurable strategies:  
  single task per story, one per sprint, or one per day.  
- **Offline Mode** — Track time without connectivity; automatic sync on reconnect.  
- **Cross-Platform Availability** — Web (Blazor Server), Windows and Android (Blazor Hybrid MAUI),  
  with future expansion to iOS and macOS.  
- **Reporting and Insights** — Filter summaries by date, story, activity type, or integration source.  
- **Configurable Workflows** — Administrators define allowed task types; users select stories and  
  activities directly from the app.  

### Architecture  

```
┌──────────────────────┐
│  Blazor Web App      │
│  (Server-side)       │
└──────────┬───────────┘
           │
           │  (future: Blazor Hybrid MAUI)
           │
┌──────────▼───────────┐
│  TimeTracker BFF     │
│  ASP.NET Core WebAPI │
│  OpenAPI-specified   │
├──────────────────────┤
│  Auth via            │
│  Gmd.AuthService     │
│  ClientLib (AB#1305) │
└──────────┬───────────┘
           │
    ┌──────┼───────┐
    │      │       │
┌───▼──┐ ┌▼────┐ ┌▼──────────┐
│Time  │ │User │ │AzDo       │
│Entry │ │Prefs│ │Integration│
│Svc   │ │Svc  │ │Svc        │
└──┬───┘ └─┬───┘ └───────────┘
   │       │
┌──▼───────▼──┐
│ SQL Server  │
│ (EF Core)   │
└─────────────┘
```

### Technology Stack  

- **Language**: C# (.NET)  
- **Web UI**: Blazor Server (initial), Blazor Hybrid MAUI (future)  
- **Backend**: ASP.NET Core Web API  
- **Database**: SQL Server via EF Core  
- **Authentication**: Gmd.AuthService (epic AB#1305) — Google OIDC, RS256 JWT  
- **API specification**: OpenAPI (YAML)  
- **Native clients**: Blazor Hybrid MAUI (Windows, Android first; iOS, macOS later)  

### MVP Scope  

The MVP delivers a working web application where authenticated users can create, edit, and  
delete time entries, view their time entry history, and see basic reports.  
Azure DevOps integration, offline mode, and native apps are post-MVP features.  

## Feature: Core Backend API (001)
{WorkItemId}: 2841
{State}: New

{tags}: epicTimeTracker, backend  
{Effort}: 5  
{Priority}: 2  
{Description}  
The foundational backend for TimeTracker: solution structure, domain model, EF Core  
data access with SQL Server, and a RESTful API for time entry management.  
This feature delivers the server-side MVP — a fully functional, authenticated API  
that the web UI and future native clients consume.  

### Story: Scaffold solution and implement time entry CRUD API (001)
{WorkItemId}: 2842
{State}: New

{tags}: epicTimeTracker, backend  
{Story Points}: 2  
{Priority}: 2  
{Description}  
**As a** developer  
**I want** a scaffolded solution with a working time entry CRUD API backed by SQL Server  
**So that** the foundational backend is in place for all clients to consume  

This story creates the full vertical slice: solution structure, domain model,  
EF Core DbContext with SQL Server provider, EF Core migrations, and REST API  
endpoints — all covered by integration tests.  

#### Solution Structure  

```
TimeTracker/
├── src/
│   ├── TimeTracker.Domain/          # Domain entities, enums, interfaces
│   ├── TimeTracker.Infrastructure/  # EF Core, DbContext, migrations
│   └── TimeTracker.WebApi/          # ASP.NET Core Web API host
├── test/
│   ├── TimeTracker.Domain.Tests/
│   ├── TimeTracker.Infrastructure.Tests/
│   └── TimeTracker.WebApi.Tests/
└── TimeTracker.sln
```

#### Domain Model — TimeEntry  

| Property | Type | Nullable | Constraints |  
|----------|------|----------|-------------|  
| Id | Guid | No | Primary key, generated on create |  
| UserId | string | No | Max 128 chars, from JWT `user_id` claim |  
| Description | string | Yes | Max 500 chars |  
| StartTime | DateTimeOffset | No | Must be in the past or present |  
| EndTime | DateTimeOffset | Yes | Must be after StartTime when set |  
| ActivityType | string | Yes | Max 100 chars, free-text for MVP |  
| CreatedAt | DateTimeOffset | No | Set on creation, immutable |  
| UpdatedAt | DateTimeOffset | No | Set on every update |  

#### OpenAPI — Time Entry Endpoints  

```yaml
paths:
  /api/v1/time-entries:
    get:
      summary: List time entries for the authenticated user
      parameters:
        - name: from
          in: query
          schema:
            type: string
            format: date-time
        - name: to
          in: query
          schema:
            type: string
            format: date-time
        - name: page
          in: query
          schema:
            type: integer
            default: 1
        - name: pageSize
          in: query
          schema:
            type: integer
            default: 20
            maximum: 100
      responses:
        '200':
          description: Paginated list of time entries
    post:
      summary: Create a new time entry
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CreateTimeEntryRequest'
      responses:
        '201':
          description: Time entry created
  /api/v1/time-entries/{id}:
    get:
      summary: Get a single time entry by ID
      responses:
        '200':
          description: Time entry details
        '404':
          description: Not found
    put:
      summary: Update an existing time entry
      responses:
        '200':
          description: Updated
        '404':
          description: Not found
    delete:
      summary: Delete a time entry
      responses:
        '204':
          description: Deleted
        '404':
          description: Not found
components:
  schemas:
    CreateTimeEntryRequest:
      type: object
      required: [startTime]
      properties:
        description:
          type: string
          maxLength: 500
        startTime:
          type: string
          format: date-time
        endTime:
          type: string
          format: date-time
        activityType:
          type: string
          maxLength: 100
```

{Acceptance Criteria}  
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ☐ | Solution compiles and all projects reference correctly |  |  |  
| ☐ | EF Core migrations create TimeEntry table in SQL Server |  |  |  
| ☐ | POST /api/v1/time-entries creates a time entry and returns 201 |  |  |  
| ☐ | GET /api/v1/time-entries returns paginated results filtered by date range |  |  |  
| ☐ | GET /api/v1/time-entries/{id} returns 404 for non-existent ID |  |  |  
| ☐ | PUT /api/v1/time-entries/{id} updates fields and sets UpdatedAt |  |  |  
| ☐ | DELETE /api/v1/time-entries/{id} removes the entry and returns 204 |  |  |  
| ☐ | StartTime must not be in the future — returns 400 on violation |  |  |  
| ☐ | EndTime must be after StartTime when provided — returns 400 on violation |  |  |  
| ☐ | Description exceeding 500 chars is rejected with 400 |  |  |  
| ☐ | Users can only access their own time entries (UserId filter enforced) |  |  |  

{Acceptance Tests}  
- [ ] **Scenario 1: Create a time entry with valid data**  
Given the API is running and the user is authenticated  
When POST /api/v1/time-entries is called with a valid StartTime and Description  
Then the response status is 201  
And the response body contains the created time entry with a generated Id  
And CreatedAt and UpdatedAt are set to the current time  

- [ ] **Scenario 2: Create a time entry with StartTime in the future**  
Given the API is running and the user is authenticated  
When POST /api/v1/time-entries is called with StartTime set to tomorrow  
Then the response status is 400  
And the error message indicates StartTime must not be in the future  

- [ ] **Scenario 3: Create a time entry with EndTime before StartTime**  
Given the API is running and the user is authenticated  
When POST /api/v1/time-entries is called with EndTime earlier than StartTime  
Then the response status is 400  
And the error message indicates EndTime must be after StartTime  

- [ ] **Scenario 4: List time entries with date range filter**  
Given the user has time entries on 2026-01-15, 2026-01-20, and 2026-02-01  
When GET /api/v1/time-entries?from=2026-01-10&to=2026-01-25 is called  
Then only the entries from 2026-01-15 and 2026-01-20 are returned  

- [ ] **Scenario 5: List time entries returns paginated results**  
Given the user has 25 time entries  
When GET /api/v1/time-entries?page=2&pageSize=10 is called  
Then 10 entries are returned  
And the response includes pagination metadata indicating page 2 of 3  

- [ ] **Scenario 6: Update a time entry**  
Given the user has a time entry with Description "Meeting"  
When PUT /api/v1/time-entries/{id} is called with Description "Team standup"  
Then the response status is 200  
And Description is "Team standup"  
And UpdatedAt is more recent than CreatedAt  

- [ ] **Scenario 7: Delete a time entry**  
Given the user has a time entry  
When DELETE /api/v1/time-entries/{id} is called  
Then the response status is 204  
And GET /api/v1/time-entries/{id} returns 404  

- [ ] **Scenario 8: User cannot access another user's time entry**  
Given user A has a time entry with a known ID  
When user B calls GET /api/v1/time-entries/{id} with that ID  
Then the response status is 404  

{Extra Information}  
- Use `efAddMigration.ps1` for creating EF Core migrations  
- SQL Server connection string configured via `appsettings.json` / environment variables  
- Follow DDD: domain entities in Domain project, persistence concerns in Infrastructure  

### Story: Integrate Gmd.AuthService for user authentication (002)
{WorkItemId}: 2843
{State}: New

{tags}: epicTimeTracker, backend, auth  
{Story Points}: 1  
{Priority}: 2  
{Description}  
**As a** user  
**I want** the API to require authentication via Gmd.AuthService  
**So that** only authenticated users can access their time entries  

Integrate the `Gmd.AuthService.ClientLib` NuGet package into the TimeTracker BFF backend.  
Configure JWT validation using the JWKS endpoint from Gmd.AuthService.  
All API endpoints must require a valid JWT; the `user_id` claim from the token  
is used to scope time entries to the authenticated user.  

#### Integration Points  

- Install `Gmd.AuthService.ClientLib` NuGet package  
- Configure JWT Bearer authentication with JWKS validation  
- Extract `user_id` claim and use it as the UserId for time entry operations  
- Return 401 for missing/invalid tokens, 403 for insufficient permissions  

{Acceptance Criteria}  
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ☐ | All API endpoints return 401 when no JWT is provided |  |  |  
| ☐ | All API endpoints return 401 when an expired JWT is provided |  |  |  
| ☐ | Valid JWT with user_id claim grants access to the user's time entries |  |  |  
| ☐ | The user_id from the JWT is used as the UserId when creating time entries |  |  |  
| ☐ | Token validation uses the JWKS endpoint from Gmd.AuthService |  |  |  

{Acceptance Tests}  
- [ ] **Scenario 1: Unauthenticated request is rejected**  
Given the API is running  
When GET /api/v1/time-entries is called without an Authorization header  
Then the response status is 401  

- [ ] **Scenario 2: Expired token is rejected**  
Given the API is running  
When GET /api/v1/time-entries is called with an expired JWT  
Then the response status is 401  

- [ ] **Scenario 3: Valid token grants access**  
Given the API is running  
When GET /api/v1/time-entries is called with a valid JWT containing user_id "user-123"  
Then the response status is 200  
And only time entries belonging to "user-123" are returned  

- [ ] **Scenario 4: Created time entry uses user_id from JWT**  
Given the user authenticates with a JWT containing user_id "user-456"  
When POST /api/v1/time-entries is called with valid data  
Then the created time entry has UserId "user-456"  

{Extra Information}  
- Gmd.AuthService is developed under epic AB#1305  
- The AuthService itself is out of scope — this story only integrates its client library  
- For local development, use a test RSA key pair to generate JWTs  

## Feature: Web UI - Time Tracking MVP (002)
{WorkItemId}: 2844
{State}: New

{tags}: epicTimeTracker, webUi  
{Effort}: 5  
{Priority}: 2  
{Description}  
Blazor Server web application providing the user-facing MVP interface for TimeTracker.  
Users can log in, create and manage time entries via a form (manual entry or start/stop timer),  
and view their time entry history in a filterable list.  
The Blazor Server app communicates with the Core Backend API.  

### Story: Blazor web app with time entry management (003)
{WorkItemId}: 2845
{State}: New

{tags}: epicTimeTracker, webUi  
{Story Points}: 3  
{Priority}: 2  
{Description}  
**As a** user  
**I want** a web interface where I can create, view, edit, and delete time entries  
**So that** I can track my time conveniently from any browser  

This story delivers the complete Blazor Server web app MVP:  
- App scaffold with layout, navigation, and authentication flow  
- Time entry form supporting both manual entry and a start/stop timer  
- Time entry list page with date range filtering  
- Edit and delete functionality on existing entries  

#### UI Pages  

| Page | Route | Purpose |  
|------|-------|---------|  
| Login | /login | Redirect to Gmd.AuthService for authentication |  
| Dashboard | / | Shows today's time entries and active timer |  
| Time Entries | /time-entries | Filterable list of all time entries |  
| New Entry | /time-entries/new | Form to create a manual time entry |  
| Edit Entry | /time-entries/{id}/edit | Form to edit an existing time entry |  

{Acceptance Criteria}  
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ☐ | User can log in via Gmd.AuthService and see the dashboard |  |  |  
| ☐ | User can create a manual time entry with description, start time, end time, and activity type |  |  |  
| ☐ | User can start a timer which records StartTime as now |  |  |  
| ☐ | User can stop a running timer which sets EndTime to now and saves the entry |  |  |  
| ☐ | Time entry list displays entries sorted by StartTime descending |  |  |  
| ☐ | Time entry list supports filtering by date range |  |  |  
| ☐ | User can edit an existing time entry's description, times, and activity type |  |  |  
| ☐ | User can delete a time entry with a confirmation dialog |  |  |  
| ☐ | Form validation shows inline errors for invalid inputs (e.g. EndTime before StartTime) |  |  |  

{Acceptance Tests}  
- [ ] **Scenario 1: Create a manual time entry**  
Given the user is on the New Entry page  
When the user fills in Description "Code review", StartTime "09:00", EndTime "10:30", ActivityType "Development"  
And clicks Save  
Then the entry appears in the time entry list  
And a success notification is shown  

- [ ] **Scenario 2: Start and stop a timer**  
Given the user is on the dashboard  
When the user clicks Start Timer  
Then a running timer is displayed with elapsed time  
When the user clicks Stop Timer  
Then a time entry is created with StartTime equal to when the timer started  
And EndTime equal to the current time  

- [ ] **Scenario 3: Edit a time entry**  
Given the user has a time entry with Description "Meeting"  
When the user navigates to the edit page and changes Description to "Sprint planning"  
And clicks Save  
Then the time entry list shows "Sprint planning"  

- [ ] **Scenario 4: Delete a time entry**  
Given the user has a time entry  
When the user clicks Delete and confirms the dialog  
Then the entry is removed from the list  

- [ ] **Scenario 5: Filter time entries by date range**  
Given the user has entries on multiple dates  
When the user sets a date range filter from 2026-01-01 to 2026-01-31  
Then only entries within that range are shown  

- [ ] **Scenario 6: Form validation rejects invalid input**  
Given the user is on the New Entry page  
When the user enters EndTime earlier than StartTime  
And clicks Save  
Then an inline validation error is displayed  
And the entry is not saved  

{Extra Information}  
- The Blazor Server app lives in the `TimeTracker.WebApp` project  
- Reuse Blazor components so they can later be shared with the MAUI Hybrid app  
- Use HttpClient to call the backend API  

## Feature: Reporting and Insights (003)
{WorkItemId}: 2846
{State}: New

{tags}: epicTimeTracker, reporting  
{Effort}: 3  
{Priority}: 3  
{Description}  
Built-in reporting capabilities for TimeTracker. Users can review and analyze  
their logged time with filters for date range, activity type, and other dimensions.  
Reports are accessible via the web UI and the underlying API.  

### Story: Time summary reports with filtering (004)
{WorkItemId}: 2847
{State}: New

{tags}: epicTimeTracker, reporting  
{Story Points}: 2  
{Priority}: 3  
{Description}  
**As a** user  
**I want** to view summarized reports of my tracked time with flexible filters  
**So that** I can analyze how I spend my time and generate overviews for specific periods  

This story adds:  
- A report API endpoint returning aggregated time data  
- A report page in the Blazor web app with date range and activity type filters  
- Summary cards showing total hours, entries count, and breakdown by activity type  

#### OpenAPI — Report Endpoint  

```yaml
paths:
  /api/v1/reports/time-summary:
    get:
      summary: Get time summary for the authenticated user
      parameters:
        - name: from
          in: query
          required: true
          schema:
            type: string
            format: date
        - name: to
          in: query
          required: true
          schema:
            type: string
            format: date
        - name: groupBy
          in: query
          schema:
            type: string
            enum: [day, week, month]
            default: day
      responses:
        '200':
          description: Aggregated time summary
          content:
            application/json:
              schema:
                type: object
                properties:
                  totalHours:
                    type: number
                    format: double
                  entryCount:
                    type: integer
                  byActivityType:
                    type: array
                    items:
                      type: object
                      properties:
                        activityType:
                          type: string
                        totalHours:
                          type: number
                  byPeriod:
                    type: array
                    items:
                      type: object
                      properties:
                        periodStart:
                          type: string
                          format: date
                        totalHours:
                          type: number
```

{Acceptance Criteria}  
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ☐ | GET /api/v1/reports/time-summary returns total hours and entry count for the date range |  |  |  
| ☐ | Report groups time by day, week, or month based on the groupBy parameter |  |  |  
| ☐ | Report includes breakdown by activity type with hours per type |  |  |  
| ☐ | Web UI displays summary cards (total hours, entry count) |  |  |  
| ☐ | Web UI chart or table shows time distribution by period |  |  |  
| ☐ | Both from and to query parameters are required — 400 returned if missing |  |  |  

{Acceptance Tests}  
- [ ] **Scenario 1: Daily grouped report for a week**  
Given the user has time entries on Mon, Tue, and Thu of the same week  
When GET /api/v1/reports/time-summary?from=2026-03-02&to=2026-03-08&groupBy=day is called  
Then totalHours equals the sum of all entries in that week  
And byPeriod contains entries for Mon, Tue, and Thu with their respective hours  

- [ ] **Scenario 2: Activity type breakdown**  
Given the user has 3h of "Development" and 2h of "Meeting" in January  
When GET /api/v1/reports/time-summary?from=2026-01-01&to=2026-01-31 is called  
Then byActivityType contains "Development" with 3.0 hours  
And byActivityType contains "Meeting" with 2.0 hours  
And totalHours equals 5.0  

- [ ] **Scenario 3: Report page displays summary**  
Given the user navigates to the Reports page  
When the user selects date range 2026-01-01 to 2026-01-31 and clicks Generate  
Then summary cards show total hours and entry count  
And a breakdown table/chart by activity type is displayed  

- [ ] **Scenario 4: Missing date range returns 400**  
Given the user is authenticated  
When GET /api/v1/reports/time-summary is called without from and to parameters  
Then the response status is 400  

## Feature: Azure DevOps Integration (004)
{WorkItemId}: 2848
{State}: New

{tags}: epicTimeTracker, azdoSync  
{Effort}: 13  
{Priority}: 3  
{Description}  
Optional integration allowing users to connect their Azure DevOps account,  
browse sprint stories, and automatically create or update tasks with logged time.  
TimeTracker remains the system of record — AzDo sync is one-way (TimeTracker → AzDo)  
and the application continues to function fully when AzDo is unavailable.  

### Story: AzDo connection and sprint story browser (005)
{WorkItemId}: 2849
{State}: New

{tags}: epicTimeTracker, azdoSync  
{Story Points}: 3  
{Priority}: 3  
{Description}  
**As a** user  
**I want** to connect my Azure DevOps account and browse stories from the current or upcoming sprint  
**So that** I can associate my time entries with AzDo work items  

This story delivers:  
- A settings page where users can configure their AzDo organization, project, and PAT  
- Storage of AzDo connection settings per user (PAT encrypted at rest)  
- An API endpoint that lists stories from the current/next sprint using the AzDo REST API  
- A UI page to browse and select stories for time entry association  

#### OpenAPI — AzDo Integration Endpoints  

```yaml
paths:
  /api/v1/azdo/connection:
    put:
      summary: Save or update AzDo connection settings
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [organization, project, pat]
              properties:
                organization:
                  type: string
                  maxLength: 100
                project:
                  type: string
                  maxLength: 100
                pat:
                  type: string
      responses:
        '200':
          description: Connection saved
    get:
      summary: Get current AzDo connection status (no PAT returned)
      responses:
        '200':
          description: Connection info
  /api/v1/azdo/sprint-stories:
    get:
      summary: List stories from the current or next sprint
      parameters:
        - name: sprint
          in: query
          schema:
            type: string
            enum: [current, next]
            default: current
      responses:
        '200':
          description: List of stories
```

{Acceptance Criteria}  
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ☐ | User can save AzDo organization, project, and PAT via the settings page |  |  |  
| ☐ | PAT is encrypted at rest in the database |  |  |  
| ☐ | GET /api/v1/azdo/connection returns organization and project but never the PAT |  |  |  
| ☐ | GET /api/v1/azdo/sprint-stories returns stories from the current sprint |  |  |  
| ☐ | GET /api/v1/azdo/sprint-stories?sprint=next returns stories from the upcoming sprint |  |  |  
| ☐ | When AzDo is unreachable, the endpoint returns a clear error without crashing |  |  |  
| ☐ | User can select a story from the browser to associate with a time entry |  |  |  

{Acceptance Tests}  
- [ ] **Scenario 1: Save AzDo connection**  
Given the user is on the AzDo settings page  
When the user enters organization "contoso", project "MyProject", and a valid PAT  
And clicks Save  
Then the connection is stored  
And the settings page shows "Connected to contoso/MyProject"  

- [ ] **Scenario 2: PAT is not exposed via API**  
Given the user has a saved AzDo connection  
When GET /api/v1/azdo/connection is called  
Then the response contains organization and project  
And the PAT field is absent from the response  

- [ ] **Scenario 3: Browse current sprint stories**  
Given the user has a valid AzDo connection  
When the user navigates to the sprint stories page  
Then stories from the current sprint are displayed with title and state  

- [ ] **Scenario 4: AzDo unreachable returns error**  
Given the user has AzDo settings pointing to an unreachable organization  
When GET /api/v1/azdo/sprint-stories is called  
Then the response status is 502  
And the error message indicates AzDo is unreachable  

{Extra Information}  
- Use Azure DevOps REST API v7.1 for sprint and work item queries  
- Consider caching sprint stories for a short TTL to reduce API calls  

### Story: Task type configuration and creation rules (006)
{WorkItemId}: 2850
{State}: New

{tags}: epicTimeTracker, azdoSync  
{Story Points}: 3  
{Priority}: 3  
{Description}  
**As a** user  
**I want** to configure which AzDo task types are allowed and how time entries  
are aggregated into tasks  
**So that** time synchronization follows my team's workflow conventions  

This story delivers:  
- A configuration UI for selecting allowed AzDo task types (e.g. "Development", "Testing")  
- Aggregation strategy selection: single task per story, one task per sprint, or one task per day  
- Storage of these preferences per user  
- Validation that only configured task types are used during sync  

#### Aggregation Strategies  

| Strategy | Behavior |  
|----------|----------|  
| SingleTask | All time for a story is aggregated into one AzDo task |  
| PerSprint | One AzDo task per sprint per story |  
| PerDay | One AzDo task per day per story |  

{Acceptance Criteria}  
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ☐ | User can select allowed task types from a configurable list |  |  |  
| ☐ | User can choose an aggregation strategy (SingleTask, PerSprint, PerDay) |  |  |  
| ☐ | Configuration is persisted per user |  |  |  
| ☐ | Default aggregation strategy is SingleTask when not configured |  |  |  
| ☐ | Only configured task types are accepted during time sync |  |  |  

{Acceptance Tests}  
- [ ] **Scenario 1: Configure allowed task types**  
Given the user is on the AzDo configuration page  
When the user selects "Development" and "Testing" as allowed task types  
And clicks Save  
Then the configuration is persisted  
And only "Development" and "Testing" are available during sync  

- [ ] **Scenario 2: Select aggregation strategy**  
Given the user is on the AzDo configuration page  
When the user selects "PerDay" as the aggregation strategy  
And clicks Save  
Then the configuration shows "PerDay" as the active strategy  

- [ ] **Scenario 3: Default strategy is SingleTask**  
Given the user has not configured an aggregation strategy  
When the sync configuration is read  
Then the strategy defaults to SingleTask  

### Story: Automatic time synchronization to AzDo tasks (007)
{WorkItemId}: 2851
{State}: New

{tags}: epicTimeTracker, azdoSync  
{Story Points}: 3  
{Priority}: 3  
{Description}  
**As a** user  
**I want** my tracked time to be automatically synchronized to Azure DevOps tasks  
**So that** my AzDo work items reflect the actual time I spent  

This story delivers the sync engine that:  
- Creates or updates AzDo tasks under the selected story based on the configured aggregation strategy  
- Assigns the current user to the created tasks  
- Logs the total time (Completed Work) on the task  
- Tracks sync status per time entry to avoid duplicate syncing  
- Provides a sync history view in the UI  

{Acceptance Criteria}  
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ☐ | Sync creates a new AzDo task when none exists for the aggregation period |  |  |  
| ☐ | Sync updates the Completed Work field on an existing AzDo task |  |  |  
| ☐ | Total hours in AzDo tasks match the total in TimeTracker for the same entries |  |  |  
| ☐ | Each time entry is marked as synced after successful sync |  |  |  
| ☐ | Already-synced entries are not re-synced unless modified |  |  |  
| ☐ | Sync failure for one entry does not prevent syncing of other entries |  |  |  
| ☐ | Sync history page shows timestamp, status, and affected work items |  |  |  

{Acceptance Tests}  
- [ ] **Scenario 1: Sync creates a new task with SingleTask strategy**  
Given the user has 3 time entries linked to story "Implement login" totalling 5h  
And aggregation strategy is SingleTask  
When sync is triggered  
Then one AzDo task is created under "Implement login"  
And Completed Work is set to 5.0 hours  
And all 3 entries are marked as synced  

- [ ] **Scenario 2: Sync updates existing task**  
Given the user already synced 3h to an AzDo task  
And the user has a new 2h time entry linked to the same story  
When sync is triggered  
Then the existing AzDo task is updated with Completed Work = 5.0 hours  
And the new entry is marked as synced  

- [ ] **Scenario 3: PerDay strategy creates daily tasks**  
Given the user has entries on Monday (3h) and Tuesday (2h) for the same story  
And aggregation strategy is PerDay  
When sync is triggered  
Then two AzDo tasks are created — one for Monday (3h) and one for Tuesday (2h)  

- [ ] **Scenario 4: Sync failure is isolated**  
Given the user has 2 time entries linked to different stories  
And AzDo returns an error for the first story  
When sync is triggered  
Then the second entry is synced successfully  
And the first entry remains unsynced with an error status  

- [ ] **Scenario 5: Modified entry is re-synced**  
Given a time entry was previously synced with 2h  
And the user edits the entry to 3h  
When sync is triggered  
Then the AzDo task is updated to reflect 3h  

{Extra Information}  
- Use Azure DevOps REST API to create/update tasks and set Completed Work  
- Store sync state (synced, pending, error) per time entry in the database  
- Consider a manual "Sync now" button and an optional background sync schedule  

## Feature: Cross-Platform and Offline Support (005)
{WorkItemId}: 2852
{State}: New

{tags}: epicTimeTracker, crossPlatform  
{Effort}: 13  
{Priority}: 3  
{Description}  
Extend TimeTracker to native platforms using Blazor Hybrid with .NET MAUI,  
targeting Windows and Android initially. The native app shares the Blazor  
component library with the web app, maximizing code reuse.  
Add offline capabilities so users can track time without connectivity,  
with automatic background synchronization when the connection is restored.  

### Story: Blazor Hybrid MAUI app for Windows and Android (008)
{WorkItemId}: 2853
{State}: New

{tags}: epicTimeTracker, crossPlatform, maui  
{Story Points}: 3  
{Priority}: 3  
{Description}  
**As a** user  
**I want** a native app on Windows and Android that provides the same time tracking experience as the web  
**So that** I can track time conveniently from my desktop or phone  

This story delivers:  
- A .NET MAUI Blazor Hybrid project that hosts the shared Blazor components  
- Extraction of shared Razor components into a `TimeTracker.Shared.UI` class library  
- Platform-specific configuration for Windows and Android  
- The same authentication flow as the web app  

{Acceptance Criteria}  
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ☐ | MAUI app launches on Windows and displays the dashboard |  |  |  
| ☐ | MAUI app launches on Android emulator and displays the dashboard |  |  |  
| ☐ | Shared Razor components from TimeTracker.Shared.UI render correctly in both web and MAUI |  |  |  
| ☐ | User can log in via the same Gmd.AuthService flow |  |  |  
| ☐ | User can create, view, edit, and delete time entries from the MAUI app |  |  |  

{Acceptance Tests}  
- [ ] **Scenario 1: Launch MAUI app on Windows**  
Given the MAUI app is installed on Windows  
When the user launches the app  
Then the login screen is displayed  
And after login, the dashboard shows today's time entries  

- [ ] **Scenario 2: Shared components render consistently**  
Given the time entry form component is defined in TimeTracker.Shared.UI  
When the form is rendered in both the web app and the MAUI app  
Then the same fields and validation rules are applied in both hosts  

- [ ] **Scenario 3: CRUD operations from MAUI app**  
Given the user is logged in on the MAUI app  
When the user creates a new time entry  
Then the entry is saved to the backend  
And appears in both the MAUI app and the web app  

{Extra Information}  
- iOS and macOS are out of scope for this story — future expansion  
- The Shared.UI library should contain only Razor components and shared models  
- Platform services (e.g. local storage) use dependency injection with platform-specific implementations  

### Story: Offline time tracking with background sync (009)
{WorkItemId}: 2854
{State}: New

{tags}: epicTimeTracker, crossPlatform, offline  
{Story Points}: 5  
{Priority}: 3  
{Description}  
**As a** user  
**I want** to track time when I have no internet connection  
**So that** my workflow is not interrupted by connectivity issues  

This story delivers:  
- Local SQLite storage on the device for time entries created while offline  
- Automatic detection of online/offline status  
- Background sync that pushes locally stored entries to the backend when connectivity returns  
- Conflict resolution: server wins for concurrent edits, with user notification  
- Sync status indicator in the UI (synced, pending, conflict)  

{Acceptance Criteria}  
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ☐ | User can create time entries while offline — entries are stored locally |  |  |  
| ☐ | App detects when connectivity is restored and triggers background sync |  |  |  
| ☐ | All locally stored entries are pushed to the backend during sync |  |  |  
| ☐ | Entries created offline appear in the web app after sync completes |  |  |  
| ☐ | If the same entry was edited on another device, server version wins |  |  |  
| ☐ | User is notified of any sync conflicts |  |  |  
| ☐ | UI shows sync status per entry (synced ✅, pending 🔄, conflict ⚠️) |  |  |  

{Acceptance Tests}  
- [ ] **Scenario 1: Create entry while offline**  
Given the device has no internet connectivity  
When the user creates a time entry with Description "Offline work"  
Then the entry is saved to local SQLite storage  
And the entry appears in the local time entry list with a pending sync indicator  

- [ ] **Scenario 2: Background sync on reconnect**  
Given the user created 3 entries while offline  
When internet connectivity is restored  
Then all 3 entries are automatically synced to the backend  
And sync status changes from pending to synced  

- [ ] **Scenario 3: Conflict resolution — server wins**  
Given entry E was created offline on device A  
And the same logical entry was modified on device B and synced to the server  
When device A comes online and syncs  
Then the server version of entry E is kept  
And the user on device A is notified of the conflict  

- [ ] **Scenario 4: No data loss during extended offline period**  
Given the user works offline for 8 hours creating 20 entries  
When connectivity is restored  
Then all 20 entries are synced to the backend without data loss  

{Extra Information}  
- Use SQLite via EF Core for local storage on MAUI  
- Consider using a sync queue with retry logic and exponential backoff  
- Background sync should use .NET MAUI's background task infrastructure  

## Feature: CI/CD Infrastructure (006)
{WorkItemId}: 2855
{State}: New

{tags}: epicTimeTracker, infra  
{Effort}: 1  
{Priority}: 2  
{Description}  
Set up continuous integration and continuous deployment pipelines for the  
TimeTracker solution. This is template-based work using existing CI/CD  
infrastructure patterns — primarily manual configuration.  

### Story: Set up CI and CD pipelines for TimeTracker (010)
{WorkItemId}: 2856
{State}: New

{tags}: epicTimeTracker, infra  
{Story Points}: 0.25  
{Priority}: 2  
{Description}  
**As a** developer  
**I want** CI and CD pipelines configured for the TimeTracker solution  
**So that** code changes are automatically built, tested, and deployable to dev, staging, and production  

This is a manual task using existing pipeline templates.  
CI pipeline: build, run tests, publish artifacts.  
CD pipeline: deploy to dev, staging, and production environments.  

{Acceptance Criteria}  
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ☐ | CI pipeline triggers on push to main and PR branches |  |  |  
| ☐ | CI pipeline builds the solution and runs all tests |  |  |  
| ☐ | CD pipeline deploys to dev environment automatically on main merge |  |  |  
| ☐ | CD pipeline requires manual approval for staging and production |  |  |  

{Acceptance Tests}  
- [ ] **Scenario 1: CI triggers on PR**  
Given a developer creates a pull request  
When the PR is opened  
Then the CI pipeline runs  
And build and test results are reported on the PR  

- [ ] **Scenario 2: CD deploys to dev on merge**  
Given a PR is merged to main  
When the CI pipeline completes successfully  
Then the CD pipeline deploys to the dev environment automatically  

{Extra Information}  
- Use existing Azure Pipeline templates  
- Estimated manual effort: ~2 hours  
- This story does not require automated tests — it is verified by pipeline execution  

## Feature: Maintenance (007)
{WorkItemId}: 2857
{State}: New

{tags}: epicTimeTracker, maintenance  
{Effort}: 0  
{Priority}: 3  
{Description}  
Long-lived maintenance feature for recurring small bugs, housekeeping tasks, dependency updates,  
and minor improvements that do not belong to any dedicated feature.  
This feature is never closed — new stories and bugs are added here on an ongoing basis  
as the product evolves.  

### Purpose  

- Minor bug fixes that do not justify a dedicated feature  
- Dependency version bumps (NuGet, MAUI, .NET SDK)  
- Performance tweaks and observability improvements  
- Documentation and README updates  
- Code cleanup and refactoring not tied to a specific feature  
