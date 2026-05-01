<#
.SYNOPSIS
Generate a markdown hierarchy template for Azure DevOps work items with embedded rules and examples

.DESCRIPTION
Generates a well-structured markdown template that helps AI agents and users create valid
work item hierarchies. The template includes:
- Embedded rules from createMarkdownPlan.md and architecturalRules.md as inline comments
- Example structure showing correct formatting
- Guidance on tags, story points, and acceptance criteria
- Best practices for Gherkin BDD scenarios
- Instructions for each work item type

The generated template follows the exact markdown structure required by
NewAzDoHierarchyFromMarkdown.ps1 for creating work items in Azure DevOps.

Output is always written to stdout, which can be redirected to a file if needed.

.PARAMETER IncludeExample
If specified, includes a complete example hierarchy with explanations. Default is $false.

.OUTPUTS
String containing the markdown template (output to stdout)

.EXAMPLE
Generate template to console:
    .\GenerateAzDoMarkdownHierarchyTemplate.ps1

Generate template to file:
    .\GenerateAzDoMarkdownHierarchyTemplate.ps1 > "my-plan.md"

Generate template with full example:
    .\GenerateAzDoMarkdownHierarchyTemplate.ps1 -IncludeExample > "example-plan.md"

.NOTES
- All generated markdown automatically validates against MCP configuration schema
- Follows createMarkdownPlan.md and architecturalRules.md guidelines
- Use ConvertMarkdownToHierarchyJson.ps1 to validate structure before creating work items
- Use NewAzDoHierarchyFromMarkdown.ps1 to create work items from the markdown
#>

#Requires -Version 7.0

param(
   [switch]$IncludeExample
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$template = @"
# IMPORTANT RULES FOR MARKDOWN HIERARCHY CREATION

# WORK ITEM TYPE PREFIXES AND HEADER LEVELS
# - Epic: "# Epic: <title>"
# - Feature: "## Feature: <title>"
# - Story: "### Story: <title>"
# - Task: "#### Task: <title>" (only under Story)
# - Bug: "#### Bug: <title>" (only under Story)

# TAG RULES
# * Use camelCase tags, NOT kebab-case (e.g., "epicMyProject" not "epic-my-project")
# * Keep tags minimal and focused
# * Common tags: epicName, componentName, feature abbreviations, testWi (for test work items)

# TITLE RULES
# * NO emoticons in titles (use them in descriptions only if they add value)
# * Optional numeric suffix for order: "(001)", "(002)" - helps with sequencing
# * Keep titles clear and concise

# GENERAL MARKDOWN RULES
# * End lines with TWO SPACES to create line breaks
# * Headers inside descriptions:
#   - Epic/Feature: start at level 3 (###)
#   - Story/Task/Bug: start at level 4 (####)
# * No "---" separators; rely on header levels instead

# STORY POINTS & EFFORT RULES
# * Set realistic estimates: 1 SP = 1 perfect day for senior developer
# * Apply only to Stories and Bugs
# * Effort applies to Epics and Features (larger scale estimate)

# TAG FORMAT
# {tags}: tag1, tag2, tag3

# FIELD FORMATS (order matters)
# {tags}: (comma-separated, camelCase)
# {Effort}: (number, Epics/Features only)
# {Story Points}: (number, Stories/Bugs only)
# {Priority}: (1-4, Tasks/Bugs/Features/Stories; 1=highest)
# {OriginalEstimate}: (hours, Tasks/Features/Stories)
# {FixedIn}: (text, Features/Stories; version or build where item was completed)
# {DeployedToDev}: (true/false, Features/Stories)
# {DeployedToStaging}: (true/false, Features/Stories)
# {DeployedToProduction}: (true/false, Features/Stories)
# {Description}
# Multi-line description with proper header levels

# STORY FORMAT - STRUCTURED USER STORY
# **As a** [persona]
# **I want** [action]
# **So that** [benefit/validation]


# ACCEPTANCE CRITERIA
# {Acceptance Criteria}
# | ✅ | What is Verified | Test(s) | Notes |
# |---|-----------------|---------|-------|
# | ☐ | (Describe what is verified) |  |  |
#
# IMPORTANT: The Test(s) and Notes columns start empty. During development:
# - Test(s) column: Add the name or reference to tests that verify each AC
# - Notes column: Add any clarifications about the tests, edge cases, or special considerations

# Acceptance Tests (BDD/GHERKIN)
# {Acceptance Tests}
# 1. **Scenario**: Clear scenario title
#    Given [initial state]
#    When [action performed]
#    Then [expected result]
#
# 2. **Scenario**: Another scenario
#    Given [state]
#    When [action]
#    Then [result]

# EXTRA INFORMATION (optional)
# {Extra Information}
# - Implementation notes
# - References to other work items
# - Constraints and dependencies

# ===== TEMPLATE STARTS HERE =====

# Epic: Your Epic Title (001)

{tags}: epicName, component1, testWi  
{Effort}: 21  
{Description}  
Write a clear, compelling description of what this epic accomplishes.  
This is the high-level strategic goal. Include:  
- What problem does it solve?
- How does it impact users?
- Key objectives

### Architecture/Design Overview
If applicable, describe the technical approach or design patterns.  

## Feature: Your First Feature (001)

{tags}: epicName, feature1  
{Effort}: 8  
{Priority}: 3  
{OriginalEstimate}: 16  
{FixedIn}:   
{DeployedToDev}: false  
{DeployedToStaging}: false  
{DeployedToProduction}: false  
{Description}  
Clear description of the feature's purpose and scope.  
Explain what users can do with this feature.  
Include any key technical decisions or design choices.  

#### Design Notes
- Key consideration 1
- Key consideration 2

### Story: User can perform action (001)

{tags}: epicName, feature1, userFacing  
{Story Points}: 3  
{Priority}: 3  
{OriginalEstimate}: 8  
{FixedIn}:   
{DeployedToDev}: false  
{DeployedToStaging}: false  
{DeployedToProduction}: false  
{Description}  
**As a** [user type/persona]  
**I want** [specific action or capability]  
**So that** [business value or outcome]  

Include additional details about the implementation approach here if needed.  
Keep the description focused on the "what" and "why", not "how".  

{Acceptance Criteria}
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ☐ | Criterion 1 validates one specific behavior |  |  |
| ☐ | Criterion 2 validates another specific behavior |  |  |
| ☐ | Criterion 3 validates the integration or edge case |  |  |

{Acceptance Tests}
1. **Scenario**: Happy path with all inputs valid  
   Given [initial precondition or state]  
   When [user performs action]  
   Then [expected outcome]  
   And [additional assertion if applicable]  

2. **Scenario**: Edge case or alternate path  
   Given [different precondition]  
   When [variation of action]  
   Then [different expected outcome]  

{Extra Information}
- Related stories or work items
- External dependencies
- Performance requirements if applicable

#### Task: Implement core logic

{tags}: epicName, feature1, dev  
{Priority}: 1  
{OriginalEstimate}: 4  
{Description}  
Specific implementation task. Break down the story's work into concrete,  
actionable tasks. Include what needs to be built, modified, or integrated.  

### Story: User can perform alternate action (002)

{tags}: epicName, feature1, userFacing  
{Story Points}: 2  
{Priority}: 3  
{OriginalEstimate}: 4  
{FixedIn}:   
{DeployedToDev}: false  
{DeployedToStaging}: false  
{DeployedToProduction}: false  
{Description}  
**As a** [another persona]  
**I want** [related capability]  
**So that** [related benefit]  

{Acceptance Criteria}
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ☐ | First behavior is correctly implemented |  |  |
| ☐ | Edge cases are handled |  |  |

{Acceptance Tests}
1. **Scenario**: Normal operation  
   Given [precondition]  
   When [action]  
   Then [result]  

## Feature: Your Second Feature (002)

{tags}: epicName, feature2, infrastructure  
{Effort}: 5  
{Priority}: 3  
{OriginalEstimate}: 8  
{FixedIn}:   
{DeployedToDev}: false  
{DeployedToStaging}: false  
{DeployedToProduction}: false  
{Description}  
Features can be created without Stories if they represent infrastructure or  
foundational work. This feature sets up any supporting systems needed.  

### Story: Setup required (001)

{tags}: epicName, feature2  
{Story Points}: 3  
{Priority}: 3  
{OriginalEstimate}: 8  
{FixedIn}:   
{DeployedToDev}: false  
{DeployedToStaging}: false  
{DeployedToProduction}: false  
{Description}  
**As a** [system maintainer]  
**I want** [infrastructure capability]  
**So that** [system can function properly]  

{Acceptance Criteria}
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ☐ | Component is deployed and operational |  |  |
| ☐ | Monitoring and logging are in place |  |  |

{Acceptance Tests}
1. **Scenario**: System starts correctly with new component  
   Given [component installed]  
   When [system starts]  
   Then [component initializes without errors]  

#### Bug: Handle error condition

{tags}: epicName, feature2, bug, priority-high  
{Story Points}: 2  
{Priority}: 1  
{Description}  
**As a** [user/operator]  
**I want** [specific error handled gracefully]  
**So that** [system remains stable]  

{Acceptance Criteria}
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| ☐ | Error is caught and logged |  |  |
| ☐ | User receives helpful error message |  |  |
| ☐ | System does not crash |  |  |

{Acceptance Tests}
1. **Scenario**: Invalid input is provided  
   Given [invalid condition]  
   When [error occurs]  
   Then [error is handled gracefully]  
   And [user is informed]  
"@

if ($IncludeExample) {
   # Add the example from example-hierarchy.md
   $template += @"

# ===== FULL EXAMPLE FROM REAL PROJECT =====

# Epic: 🚀 Customer Portal Redesign - Q1 2024

{tags}: customerPortal, frontend, testWi  
{Effort}: 40  
{Description}  
Complete overhaul of the customer support portal to provide a modern, intuitive interface  
with improved accessibility and mobile responsiveness. This epic encompasses all design,  
development, and testing activities for the new portal experience.  

### Key Objectives
- Modernize the UI with latest design patterns
- Improve mobile experience
- Enhance accessibility compliance
- Reduce page load times by 40%

### Architecture Changes
Our team will implement a microservices backend with a React-based frontend  
to enable faster iteration and better scalability.  

## Feature: 🎨 User Authentication & Profile Management

{tags}: customerPortal, authentication, security, testWi  
{Effort}: 13  
{Description}  
Implement modern OAuth 2.0 authentication with Microsoft Entra ID and allow users  
to manage their profiles, preferences, and security settings. This feature provides  
the foundation for user identity in the new portal.  

### Security Implementation
Multi-factor authentication (MFA) will be enforced with support for authenticator apps,  
SMS, and hardware keys. Password policies comply with NIST 800-63B guidelines.  

### User Profile Management
Users can view their profile, change contact information, update security settings,  
and manage connected applications.  

### Story: Implement OAuth 2.0 with Entra ID

{tags}: customerPortal, authentication, auth-integration  
{Story Points}: 5  
{Description}  
**As a** [application owner]  
**I want** [OAuth 2.0 authentication integrated with Microsoft Entra ID]  
**So that** [users can securely authenticate using corporate credentials]  

{Acceptance Criteria}
- [ ] OAuth 2.0 consent flow is implemented
- [ ] ID tokens are validated correctly
- [ ] Refresh token rotation is working
- [ ] Logout properly revokes tokens

{Acceptance Tests}
1. **Scenario**: User successfully authenticates  
   Given [user opens portal]  
   When [user clicks sign in]  
   Then [user is redirected to Entra ID login]  
   And [after signing in, user sees authenticated dashboard]  

2. **Scenario**: Invalid credentials are rejected  
   Given [login dialog is open]  
   When [user enters wrong password]  
   Then [error message displays]  
   And [user remains on login screen]  

### Story: Implement MFA with Authenticator App Support

{tags}: customerPortal, authentication, mfa, security  
{Story Points}: 3  
{Description}  
**As a** [security-conscious user]  
**I want** [multi-factor authentication with authenticator app support]  
**So that** [my account is protected against unauthorized access]  

{Acceptance Criteria}
- [ ] User can enable MFA in account settings
- [ ] QR code for authenticator app setup is generated
- [ ] Time-based OTP codes are validated correctly
- [ ] Backup codes are provided and tested

{Acceptance Tests}
1. **Scenario**: User enables MFA  
   Given [user is in security settings]  
   When [user clicks enable MFA]  
   Then [QR code is displayed]  
   And [user can scan with authenticator app]  

2. **Scenario**: Login with MFA enabled  
   Given [MFA is enabled for user account]  
   When [user provides valid credentials]  
   Then [user is prompted for OTP]  
   And [valid OTP completes login]  
"@
}

# Append field reference section from appSettings.json
[string]$appSettingsPath = Join-Path $PSScriptRoot '../appSettings.json'
if (-not (Test-Path $appSettingsPath)) {
    $appSettingsPath = Join-Path $PSScriptRoot 'appSettings.json'
}
if (Test-Path $appSettingsPath) {
    try {
        $cfg = Get-Content $appSettingsPath -Raw | ConvertFrom-Json
        $fieldRef = "`n`n# ===== SUPPORTED FIELDS REFERENCE =====`n"
        $fieldRef += "# All writable fields available via -Fields hashtable, keyed by referenceName.`n"
        foreach ($org in $cfg.organizations.PSObject.Properties) {
            foreach ($proj in $org.Value.projects.PSObject.Properties) {
                $fieldsByType = $proj.Value.fields
                if ($null -eq $fieldsByType) { continue }
                foreach ($wiType in $fieldsByType.PSObject.Properties) {
                    $writableFields = @($wiType.Value | Where-Object { $_.readOnly -ne $true })
                    if ($writableFields.Count -eq 0) { continue }
                    $fieldRef += "`n# $($wiType.Name) fields:`n"
                    foreach ($f in $writableFields) {
                        $typeHint = if ($f.PSObject.Properties.Name -contains 'type') { $f.type } else { 'string' }
                        $fieldRef += "#   $($f.label) ($($f.referenceName)) [$typeHint]`n"
                    }
                }
            }
        }
        $template += $fieldRef
    } catch {
        # Field reference generation is best-effort; do not fail the template output
    }
}

# Output to stdout
$template

