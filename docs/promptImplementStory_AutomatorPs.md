## Work Item Cleanup Rules
- Any work items created during testing must be deleted during teardown (even if tests fail)
- Track created work item IDs and delete in cleanup phase
- Add tag `testWi` to test work items for easy identification later
- Tests must never leave persistent work items in Azure DevOps

## Validation Checklist
- [ ] `ssLogIt.ps1` used for all logging (no Write-Host/Write-Error)
