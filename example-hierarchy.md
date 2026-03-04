# Example Work Item Hierarchy

This markdown file demonstrates the format for creating Azure DevOps work item hierarchies using the `NewAzDoHierarchyFromMarkdown.ps1` script.

## Features Demonstrated
## Epic Title (optional)
**tags**: autogen, some-epic\
**Description**\
The epic description here
with **markdown support**
## Feature 1 Title
**tags**: autogen, some-feature\
**Description**\
A long feature desc
with **markdown support**
and newlines should be replaced with ``` `r`n ``` when sent with API.
### Story 1 with title
**tags**: autogen, some-story **SP**: 3\
**Description**\
As a developer
I want to do this
So that we validate those things
  
#### Acceptance Criteria
- [ ] Should not throw.
- [ ] Documented

#### AC Scenarios
1. **Scenario**: User can log in\
  Given Start page yada\
  When yadaya\
  Then foo
1. **Scenario*: User can log out\
  Given Start page yada\
  When yadaya\
  Then foo
#### Extra Information
* Login should follow standards at http://microsoft.com/...
    -Mode Replace
