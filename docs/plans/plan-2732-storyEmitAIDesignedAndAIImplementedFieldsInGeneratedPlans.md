## Feature: Maintenance Gmd.Tools.AzureDoAutomatorPs
{WorkItemId} 2205  

### Story: Emit {AI Designed} and {AI Implemented} fields in generated plans
{WorkItemId}: 2732  
{tags}: azDoAutomator; epicAzDoAutomator; promptGen  
{Story Points}: 0.5  
{State}: New  
{Description}  
**As a** developer generating a plan file from the hierarchy template    
**I want** `{AI Designed}` and `{AI Implemented}` fields to appear in the generated plan    
**So that** each work item records whether it was AI-designed (default `true`) and whether    
AI was used for implementation, and these values round-trip correctly to and from Azure DevOps    
  
#### Implementation Details  
  
`Custom.AIDesigned` and `Custom.AIImplemented` are already registered as writable boolean fields    
in `appSettings.json` with labels `AI Designed` and `AI Implemented`. The curly-brace parser in    
`ConvertMarkdownToHierarchyJson.ps1` already resolves `{AI Designed}` and `{AI Implemented}` via    
those labels — no parser changes are needed.    
  
Changes required:    
  
1. **`GenerateAzDoMarkdownHierarchyTemplate.ps1`** — add `{AI Designed}: true` and  
   `{AI Implemented}: false` to the Feature and Story template sections, placed alongside    
   the existing deployment boolean fields. Also add them to the `# FIELD FORMATS` comment    
   block.    
2. **`ConvertHierarchyToMarkdown.ps1`** — emit `{AI Designed}` and `{AI Implemented}` in the  
   output for Features and Stories, sourced from the `Custom.AIDesigned` /    
   `Custom.AIImplemented` fields in the hierarchy data.  

{Acceptance Criteria}  
| ✅ | What is Verified | Test(s) | Notes |  
|---|-----------------|---------|-------|  
| ☐ | `GenerateAzDoMarkdownHierarchyTemplate.ps1` emits `{AI Designed}: true` for Feature and Story sections | | Default value is `true` |  
| ☐ | `GenerateAzDoMarkdownHierarchyTemplate.ps1` emits `{AI Implemented}: false` for Feature and Story sections | | Default value is `false` |  
| ☐ | `ConvertHierarchyToMarkdown.ps1` emits `{AI Designed}` value for each Feature/Story sourced from `Custom.AIDesigned` | | |  
| ☐ | `ConvertHierarchyToMarkdown.ps1` emits `{AI Implemented}` value for each Feature/Story sourced from `Custom.AIImplemented` | | |  
| ☐ | Round-trip: a plan file with `{AI Designed}: true` is correctly written to `Custom.AIDesigned = true` in AzDo | | Verified via existing parser + `NewAzDoHierarchyFromMarkdown.ps1` |  
| ☐ | README.md is updated to reflect the two new fields | | |

{Acceptance Tests}  
1. **Scenario**: Template generator includes AI fields with correct defaults  
   Given `GenerateAzDoMarkdownHierarchyTemplate.ps1` is invoked    
   When the output is inspected    
   Then a Feature section contains `{AI Designed}: true` and `{AI Implemented}: false`    
   And a Story section contains `{AI Designed}: true` and `{AI Implemented}: false`    
  
2. **Scenario**: Hierarchy export emits AI field values  
   Given a Feature with `Custom.AIDesigned = true` and `Custom.AIImplemented = false`    
   When `ConvertHierarchyToMarkdown.ps1` is invoked    
   Then the output contains `{AI Designed}: true` and `{AI Implemented}: false` for that feature    
  
3. **Scenario**: Plan file AI Designed value round-trips to AzDo  
   Given a plan file with `{AI Designed}: true` on a story    
   When `NewAzDoHierarchyFromMarkdown.ps1` is invoked    
   Then `Custom.AIDesigned` is set to `true` on the work item in Azure DevOps  

{Extra Information}  
- Field labels in `appSettings.json`: `&quot;AI Designed&quot;` (Custom.AIDesigned) and `&quot;AI Implemented&quot;` (Custom.AIImplemented)  
- Both are `type: boolean`, `readOnly: false` — no appSettings.json changes needed  
- Place the two fields after `{DeployedToProduction}` in the template output order

