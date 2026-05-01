### Story: Ensure scripts are setting AI related fields
{WorkItemId}: 2631  
{tags}: aiWorkflow; gmdAzureDoAutomator; maintenance  
{Story Points}: 3  
{State}: New  
{Description}  
As an AI agent or developer driving story implementation through automation prompts,I want the orchestration prompts and scripts to automatically set AI-tracking fields (AI Designed, AI Implemented, Assigned To, and State) on work items at the correct lifecycle moments,So that the backlog accurately reflects AI involvement, ownership, and implementation state without requiring manual field updates.  

{Acceptance Criteria}  
| ✅ | What is Verified | Notes |
|---|-----------------|-------|
| ▢ | When AI begins implementation planning, \\Assigned To\\ is set to the machine account before any work starts | Machine account email is read from appSettings.json — not hardcoded |
| ▢ | When AI begins implementation planning, \\State\\ is set to the configured start state (e.g. \\Under Development\\) | Value is read from appSettings.json keyed by work item type |
| ▢ | When AI generates a plan (creates stories/features in hierarchy), \\AI Designed\\ is set to \\	rue\\ on each created work item | |
| ▢ | When AI begins implementing a story/bug, \\AI Implemented\\ is set to \\	rue\\ on the work item | |
| ▢ | When AI completes implementation of a story/bug, \\State\\ is set to the configured done state (e.g. \\RTM\\) | Value is read from appSettings.json keyed by work item type |
| ▢ | Start and done state values are configurable per work item type in appSettings.json — changing them requires no prompt or script edits | |
| ▢ | Machine account (\\Assigned To\\) is configurable in appSettings.json — changing it requires no prompt or script edits | |

{Extra Information}  
Notes: Custom.AIDesigned exists in Azure DevOps but is not yet declared in appSettings.json. Add it to the User Story, Feature, and Bug field lists (type: boolean) before implementing the plan-generation step. State values for start/done should be added to appSettings.json (e.g. a new aiWorkflow key per type) so prompts read them without hardcoding. Affected files: implementation prompt templates under docs/, any hierarchy-creation wrappers, and agent implementation instructions.  

