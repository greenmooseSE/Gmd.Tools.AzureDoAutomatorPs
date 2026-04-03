# Epic: 🚀 Customer Portal Redesign - Q1 2024

**WorkItemId**: 2215
**State**: Active
**tags**: customerPortal, frontend, testWi\
**Effort**: 40
**Description**\
Complete overhaul of the customer support portal to provide a modern, intuitive interface\
with improved accessibility and mobile responsiveness. This epic encompasses all design,\
development, and testing activities for the new portal experience.

### Key Objectives
- Modernize the UI with latest design patterns
- Improve mobile experience
- Enhance accessibility compliance
- Reduce page load times by 40%

### Architecture Changes
Our team will implement a microservices backend with a React-based frontend\
to enable faster iteration and better scalability.

```
┌────────────────────────┐
│  React Portal (Web)    │
│  Mobile Responsive     │
└────────────┬───────────┘
             │
     ┌───────▼────────┐
     │  API Gateway   │
     ├────────────────┤
     │  Auth / Rate   │
     │  Limiting      │
     └───────┬────────┘
             │
    ┌────────┼────────┐
    │        │        │
┌───▼──┐ ┌──▼───┐ ┌──▼────┐
│User  │ │Auth  │ │Ticket │
│Svc   │ │Svc   │ │Svc    │
└───┬──┘ └──┬───┘ └──┬────┘
    │       │        │
    └───────┴────────┘
          │
    ┌─────▼─────┐
    │  Database │
    └───────────┘
```

## Feature: 🎨 User Authentication & Profile Management

**WorkItemId**: 2216
**State**: Under Development
**tags**: authentication, security, testWi\
**Effort**: 13
**Description**\
Implement modern OAuth 2.0 authentication with Microsoft Entra ID and allow users\
to manage their profiles, preferences, and security settings. This feature provides\
the foundation for user identity in the new portal.

### Security Implementation
Multi-factor authentication (MFA) will be enforced with support for authenticator apps,\
SMS, and hardware keys. Password policies comply with NIST 800-63B guidelines.

### User Profile Management
Users can view and edit their profile information including name, email, phone, and\
communication preferences. All changes are audited and logged for compliance.

### Story: 🔐 Implement OAuth 2.0 with Microsoft Entra ID

**WorkItemId**: 2217
**State**: Committed
**tags**: authentication, entraId, testWi\
**SP**: 8\
**Description**\
As a developer, I need to implement OAuth 2.0 authentication integration with Microsoft\
Entra ID so that users can securely log in with their organizational credentials.

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|------------------|---------|-------|
| ⏹️ | Users can log in with Entra ID credentials using OAuth 2.0 flow |  |  |
| ⏹️ | Access token is valid for 1 hour and refresh token extends session |  |  |
| ⏹️ | Failed login attempts are logged for security auditing |  |  |
| ⏹️ | Login page displays appropriate error messages for invalid credentials |  |  |
| ⏹️ | Session is cleared when user logs out or token expires |  |  |

#### AC Scenarios
1. **Scenario**: User successfully logs in with valid Entra ID credentials\
  Given user is on the login page\
  When user enters valid Entra ID email and password\
  Then user is redirected to dashboard with valid session\
  And user can access protected resources\
  And session cookie is set with secure flag

2. **Scenario**: User authentication fails with invalid credentials\
  Given user is on the login page\
  When user enters incorrect password\
  Then authentication fails\
  And error message displays "Invalid credentials"\
  And login attempt is logged with timestamp

3. **Scenario**: Session expires and user is redirected to login\
  Given user has active session for 65 minutes\
  When access token expires at 60-minute mark\
  Then refresh token is used to extend session\
  And if refresh token also expired, user is returned to login page

#### Extra Information
- Reference MSAL.js documentation for implementation: https://github.com/AzureAD/microsoft-authentication-library-for-js
- Ensure compliance with OAuth 2.0 Best Current Practice (RFC 8252)
- Test with both work and personal Microsoft accounts
- Configure separate Entra ID app registrations for dev, staging, and production

### Story: 👤 User Profile Page & Preferences

**tags**: userProfile, ux, testWi\
**SP**: 5\
**Description**\
As a user, I want to view and manage my profile information and preferences so that\
my account reflects my current details and communication preferences.

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|------------------|---------|-------|
| ⏹️ | User profile page displays name, email, phone, and account creation date |  |  |
| ⏹️ | Users can edit name and email with confirmation dialog |  |  |
| ⏹️ | Users can update communication preferences (email notifications, frequency) |  |  |
| ⏹️ | All profile changes are audited with change timestamp and actor |  |  |
| ⏹️ | New email requires verification via confirmation link |  |  |

#### AC Scenarios
1. **Scenario**: User updates profile name successfully\
  Given user is logged in on profile page\
  When user edits name field and clicks save\
  Then profile name is updated in database\
  And change audit trail shows update with timestamp\
  And success notification appears

2. **Scenario**: User changes email address with verification\
  Given user is on profile page\
  When user enters new email and submits\
  Then confirmation email is sent to new address\
  And old email remains active until verification\
  And verification link contains one-time token

#### Extra Information
- Email validation should support i18n characters
- Apply rate limiting on profile API endpoints (10 requests/minute per user)
- Store profile pictures in CDN with 1-year cache

### 📝 Tasks for "User Profile Page & Preferences" Story

These tasks are created as part of the hierarchy under their parent Story:

#### Task: Setup User Profile Database Schema

**tags**: testWi  

**Priority**: 2

**Description**: Create database tables and indexes for storing user profile information including name, email, phone, preferences, and audit trail.

**Original Estimate**: 8

**Remaining**: 8

**Completed**: 0

#### Task: Implement Profile API Endpoints

**tags**: testWi  
**Priority**: 1

**Description**: Develop RESTful API endpoints for profile CRUD operations with proper validation and error handling.

**Original Estimate**: 13

**Remaining**: 13

**Completed**: 0

#### Task: Build Profile UI Components

**tags**: testWi  
**Priority**: 2

**Description**: Implement React components for profile page with forms for editing name, email, and preferences.

**Original Estimate**: 10

**Remaining**: 10

**Completed**: 0

#### Task: Add Profile Audit Logging

**tags**: testWi  
**Priority**: 3

**Description**: Implement comprehensive audit trail for all profile changes with UI to display history.

**Original Estimate**: 5

**Remaining**: 5

**Completed**: 0

#### Task: Write Profile Integration Tests

**tags**: testWi  
**Priority**: 2

**Description**: Create comprehensive test suite for profile functionality covering happy path and edge cases.

**Original Estimate**: 8

**Remaining**: 8

**Completed**: 0

## Feature: 📊 Support Ticket Management System

**tags**: ticketing, support, testWi\
**Effort**: 11
**Description**\
Complete overhaul of the support ticket system with real-time updates, intelligent\
routing to support agents, and self-service capabilities. Users can create, track,\
and manage support tickets with full visibility into resolution progress.

### AI-Powered Triage
The system will use AI to automatically categorize tickets and suggest relevant\
knowledge base articles to users before escalation to human support agents.

### Real-time Collaboration
Support agents and customers can communicate through integrated chat within the ticket,\
with attachments, screen captures, and video call capabilities.

### Story: 🎫 Create Support Ticket Form

**tags**: ticketing, ui, testWi\
**SP**: 3\
**Description**\
As a customer, I want to easily create a support ticket by filling out a simple form\
so that I can quickly request help from the support team.

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|------------------|---------|-------|
| ⏹️ | Form includes required fields: Title, Description, Category, Priority |  |  |
| ⏹️ | Form validation provides real-time feedback on invalid inputs |  |  |
| ⏹️ | File upload allows up to 5 attachments (10MB per file, 50MB total) |  |  |
| ⏹️ | Form submission sends confirmation email with ticket number |  |  |
| ⏹️ | Estimated response time is displayed based on priority and queue |  |  |

#### AC Scenarios
1. **Scenario**: User creates ticket with valid information\
  Given user is in the create ticket form\
  When user fills in all required fields and clicks submit\
  Then ticket is created in database\
  And confirmation email contains ticket number and link\
  And ticket appears in user's dashboard

2. **Scenario**: User tries to submit incomplete form\
  Given user is in the create ticket form\
  When user clicks submit with empty title field\
  Then validation error appears under title field\
  And form is not submitted\
  And error message shows "Title is required"

#### Extra Information
- Apply progressive enhancement for offline support
- Support markdown formatting in description field
- Implement debouncing on category suggestions (300ms delay)

### Story: 🔔 Real-time Ticket Status Updates

**tags**: realTime, notifications, testWi\
**SP**: 8\
**Description**\
As a customer, I want to receive real-time notifications when my support ticket status\
changes so I'm always informed about the progress of my issue resolution.

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|------------------|---------|-------|
| ⏹️ | Ticket status changes trigger WebSocket notifications to connected clients |  |  |
| ⏹️ | Users receive desktop and email notifications based on preference settings |  |  |
| ⏹️ | Notification includes updated status, timestamp, and agent comment (if applicable) |  |  |
| ⏹️ | User can customize which status changes trigger notifications |  |  |
| ⏹️ | Notifications appear within 2 seconds of status change |  |  |

#### AC Scenarios
1. **Scenario**: Ticket is assigned to support agent and user is notified\
  Given ticket is in "Open" status\
  When support agent clicks assign button\
  Then ticket status changes to "Assigned"\
  And real-time notification sent to customer\
  And notification shows assigned agent name\
  And customer sees notification in portal within 2 seconds

2. **Scenario**: User disables email notifications but keeps in-app\
  Given user has disabled email notifications for status updates\
  When ticket status changes\
  Then in-app notification appears\
  And no email is sent\
  And notification persists in notification center

#### Extra Information
- Use Azure SignalR for scalable real-time communication
- Implement exponential backoff for WebSocket reconnection (1s, 2s, 4s, 8s)
- Archive notifications after 90 days

## Feature: 📚 Knowledge Base & Self-Service

**tags**: knowledgeBase, ai, testWi\
**Effort**: 8
**Description**\
Build an intelligent knowledge base system with full-text search, AI-powered suggestions,\
and community-contributed content. Users can search for solutions before creating tickets\
and contribute their own solutions to help other users.

### Story: 🔍 Full-Text Search with AI Suggestions

**tags**: search, ai, testWi\
**SP**: 5\
**Description**\
Implement a full-text search engine that returns relevant knowledge base articles\
with AI-suggested related articles based on semantic similarity.

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|------------------|---------|-------|
| ⏹️ | Search index supports 50,000+ articles with sub-second response times |  |  |
| ⏹️ | Search results ranked by relevance with relevance score displayed |  |  |
| ⏹️ | AI suggestions return 3-5 semantically similar articles |  |  |
| ⏹️ | Search supports filtering by category and date authored |  |  |
| ⏹️ | Faceted search shows article counts by category |  |  |

#### AC Scenarios
1. **Scenario**: User searches for articles about billing issues\
  Given user enters "how to dispute a charge" in search box\
  When search results load\
  Then top results match billing dispute topics\
  And AI-suggested articles appear in sidebar\
  And user can filter results by "Billing" category

2. **Scenario**: Empty search returns helpful suggestions\
  Given user clicks search box without typing\
  When search page loads\
  Then trending articles are displayed\
  And categories are shown as browse options\
  And recent articles appear in a sidebar

#### Extra Information
- Use Azure Cognitive Search for full-text capabilities
- Implement semantic search using embeddings (OpenAI API)
- Cache frequently accessed articles in CDN with 24-hour TTL
- Log all searches anonymously for analytics (no user PII)

### Story: 👥 Community-Contributed Solutions

**tags**: community, crowdsourcing
**SP**: 3\
**Description**\
Allow users to contribute their own solutions to common issues, with community voting\
and moderation to ensure quality content.

#### Acceptance Criteria
| ✅ | What is Verified | Test(s) | Notes |
|---|------------------|---------|-------|
| ⏹️ | Users can submit solutions to existing articles with title and detailed steps |  |  |
| ⏹️ | Solutions are marked as "Pending Review" until moderated by staff |  |  |
| ⏹️ | Community members can vote solutions helpful/unhelpful |  |  |
| ⏹️ | Solutions with 20+ helpful votes appear above original article content |  |  |
| ⏹️ | Inappropriate content is hidden after 5 unhelpful votes and reviewed |  |  |

#### AC Scenarios
1. **Scenario**: User submits helpful solution to popular article\
  Given user reads an article and has a solution\
  When user clicks "Add Solution" and fills in details\
  Then solution is submitted with "Pending Review" status\
  And confirmation email is sent to user\
  And solution appears after moderation approval

#### Extra Information
- Send weekly digest emails to top contributors
- Implement spam filtering on submitted content
- Display contributor reputation badge (bronze/silver/gold based on helpful votes)
