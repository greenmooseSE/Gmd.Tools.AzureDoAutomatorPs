Create a story in Azure DevOps following ALL rules in C:\Dev\own\GDrive\Privat\Dev\gh\Gmd.Tools.AzureDoAutomatorPs-1\docs\createStoryRules.md.

**CRITICAL:** Always fetch the latest work item context from Azure DevOps (parent feature, parent epic, existing stories) using the scripts provided. Do NOT rely on memory or previous context from earlier conversations.

## Required Process
1. **Read and summarize createStoryRules.md** — output a brief summary of each field requirement (Description format, Acceptance Criteria format, Acceptance Tests format, Story Points, Extra Information, Tags)
2. **Create the story** with all fields populated per the rules
3. **Validate** — provide a checklist showing ✓/✗ for compliance with each rule from the file

## Azure DevOps Configuration
- Org: falco-it | Proj: GMD | Parent ID: AB#TBD
- PAT: `($env:GMD_AZDO_MACHINE_WORKITEMSRW | ssEncryptDecrypt.ps1 -Decrypt)`
- Scripts: C:\Dev\own\GDrive\Privat\Dev\gh\Gmd.Tools.AzureDoAutomatorPs-1\src

## Story Content
- Create according rules and the todo items context

## Other
- Projects dirs you can check for contexts: TBD
- Update specified todo items with todo items referencing the created story title and id, in format `//TODO: (AB#123) - Story Title`.
