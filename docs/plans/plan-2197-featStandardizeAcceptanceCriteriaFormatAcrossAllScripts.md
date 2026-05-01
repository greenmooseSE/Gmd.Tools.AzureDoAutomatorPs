## Feature: Standardize Acceptance Criteria Format Across All Scripts
{WorkItemId}: 2197  
{State}: New  
{Description}  
**As a** development team  
**I want** all PowerShell scripts in Gmd.Tools.AzureDoAutomatorPs to have Acceptance Criteria documented in markdown table format  
**So that** requirements are clear, testable, and follow organizational standards for all 39 scripts  

## Overview
Standardize Acceptance Criteria documentation across the entire script library using markdown table format: | ✅ | What is Verified | Test(s) | Notes |

## Scope
All 39 PowerShell scripts organized by operation categories:  
- Get Operations (8 scripts)
- Set Operations (7 scripts)
- Upsert Operations (5 scripts)
- New/Remove/Update/Find/Convert Operations (19+ scripts)

## Success Criteria
- 100% of scripts have AC in table format
- Each AC is testable with automated tests
- All scripts follow standardized AC documentation format

### Story: Audit and Standardize AC Format - All Scripts
{WorkItemId}: 2202  
{Story Points}: 3  
{State}: New  
{Description}  
**As a** developer  
**I want** to standardize Acceptance Criteria format to markdown tables across all scripts  
**So that** requirements are consistent and testable across the codebase  

## Implementation
Audit all 39 scripts and convert/add Acceptance Criteria to use markdown table format: | ✅ | What is Verified | Test(s) | Notes |

## Deliverables
- All scripts categorized by operation type
- AC documented in table format for each script
- Each AC linked to automated tests

{Acceptance Criteria}  
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| [ ] | All 39 scripts are identified and categorized by operation type | Manual audit of src/ directory | Excludes helper modules |
| [ ] | Each script has Acceptance Criteria in markdown table format | Review of all work items | Format: ✅ \| What is Verified \| Test(s) \| Notes |
| [ ] | Each AC item is testable with automated tests | Validation that test scripts exist | Tests located in test/ directory |
| [ ] | No missing ACs for public-facing scripts | Code review of complex scripts | Focus on scripts with multiple parameters |
| [ ] | AC documentation is clear and specific | Visual inspection | Each AC describes one testable condition |

{Acceptance Tests}  
- [ ] **Scenario 1: Audit and Categorize**
  Given all 39 scripts  
  When I review each script's documentation  
  Then I identify exact AC requirements and categorize by operation type  

- [ ] **Scenario 2: Standardize Format**
  Given AC requirements are identified  
  When I convert to markdown table format  
  Then all ACs use consistent columns: ✅ \| What is Verified \| Test(s) \| Notes

- [ ] **Scenario 3: Verify Test Coverage**
  Given all ACs are documented  
  When I cross-reference with test scripts  
  Then each AC is covered by at least one automated test  

### Story: Document Set Operations Acceptance Criteria
{WorkItemId}: 2204  
{Story Points}: 2  
{State}: New  
{Description}  
**As a** developer using Set operations  
**I want** clear Acceptance Criteria for all Set scripts  
**So that** I understand what fields each modification function affects and validates  

## Implementation
Document AC for SetAzDoAcceptanceCriteria, SetAzDoAcScenarios, SetAzDoStoryPoints, SetAzDoEffort, SetAzDoWorkItemDescription, SetAzDoExtraInformation, SetAzDoWorkItemTags (7 total).  

## Deliverables
- AC for each Set script specifying field modifications
- AC referencing existing or new tests
- Validation of input constraints and error handling

{Acceptance Criteria}  
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| [ ] | SetAzDoAcceptanceCriteria updates AC field | SetAzDoAcceptanceCriteriaTest | Markdown format support |
| [ ] | SetAzDoAcScenarios updates with BDD format | Test coverage | Gherkin validation |
| [ ] | SetAzDoStoryPoints updates points correctly | StoryPointsTest | Integer validation |
| [ ] | SetAzDoEffort updates effort with valid values | EffortTest | Non-negative check |
| [ ] | SetAzDoWorkItemDescription updates description | DescriptionTest | Markdown support |
| [ ] | SetAzDoWorkItemTags modifies tags correctly | TagsTest.ps1 | camelCase format |
| [ ] | All Set operations handle errors gracefully | Error scenarios | Invalid input rejection |

{Acceptance Tests}  
- [ ] **Scenario 1: Field Update Success**
  Given a valid work item ID and field value  
  When I call SetAzDo* script  
  Then the field updates successfully  

- [ ] **Scenario 2: Invalid Input Handling**
  Given invalid parameter values  
  When I call SetAzDo* script  
  Then it rejects with appropriate error  

- [ ] **Scenario 3: Update Verification**
  Given a field is updated  
  When I retrieve the work item  
  Then the field value matches what was set  

### Story: Document Get Operations Acceptance Criteria
{WorkItemId}: 2203  
{Story Points}: 2  
{State}: New  
{Description}  
**As a** developer using Get operations  
**I want** clear Acceptance Criteria for all Get scripts  
**So that** I understand what each retrieval function returns and validates  

## Implementation
Document AC for GetAzDoWorkItem, GetAzDoUserStory, GetAzDoBug, GetAzDoComments, GetAzDoCommentReactions, and Hierarchy retrieval scripts (8 total).  

## Deliverables
- AC for each Get script specifying retrieval scope
- AC referencing existing or new tests
- Validation of field coverage and nesting relationships

{Acceptance Criteria}  
| ✅ | What is Verified | Test(s) | Notes |
|---|-----------------|---------|-------|
| [ ] | GetAzDoWorkItem retrieves by ID with full metadata | GetAzDoWorkItemTest | -Full switch support |
| [ ] | GetAzDoUserStory returns story fields correctly | GetAzDoUserStoryTest.ps1 | Both -Full and subset modes |
| [ ] | GetAzDoBug retrieves bug-specific fields | UpsertAzDoBugTest.ps1 | Bug type validation |
| [ ] | GetAzDoComments returns comment data | GetAzDoCommentReactionsTest.ps1 | Comment structure validation |
| [ ] | Hierarchy functions return complete nesting | GetAzDoHierarchyFor*Test.ps1 | Epic/Feature/Story/Task levels |

{Acceptance Tests}  
- [ ] **Scenario 1: Retrieval Success**
  Given a valid work item ID  
  When I call GetAzDo* script  
  Then it returns the work item with all expected fields  

- [ ] **Scenario 2: Error Handling**
  Given an invalid work item ID  
  When I call GetAzDo* script  
  Then it returns null or appropriate error  

- [ ] **Scenario 3: Hierarchy Completeness**
  Given a parent work item  
  When I call GetAzDoHierarchyFor*  
  Then it returns complete hierarchy with all children  


