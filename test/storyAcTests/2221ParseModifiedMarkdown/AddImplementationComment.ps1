$pat = $env:GMD_AZDO_MACHINE_WORKITEMSRW | &(Get-Command ssEncryptDecrypt.ps1).Source -Decrypt
$org = $env:GMD_AZDO_ORGANIZATION
$project = $env:GMD_AZDO_PROJECT

$headers = @{
    "Authorization" = "Basic $(([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$pat"))))"
    "Content-Type" = "application/json"
}

$comment = @"
## Implementation Summary - AB#2221: Parse Modified Markdown (Unified Parser)

### ✅ Functionality Consolidated Into Unified Parser

**Note:** Story AB#2221 was originally based on a separate parser for modified markdown with required WorkItemId. During consolidation, this functionality was merged into a unified ConvertMarkdownToHierarchyJson.ps1 parser that supports both cases:
- WorkItemId is now OPTIONAL (null for new items)
- Type prefixes (Epic:, Feature:, etc.) are optional and stripped
- State field is supported
- Handles both new and modified hierarchies

**Test Results (Updated for unified parser):**
- ✅ GivenExportedMarkdownWithChanges_WhenParsed_ThenExtractNewTitleAndDescription
- ✅ GivenMarkdownWithMissingWorkItemId_WhenParsed_ThenParseSuccessfullyWithNullId
- ✅ GivenMarkdownWithReorganizedHierarchy_WhenParsed_ThenCaptureNewStructure
- ✅ GivenInvalidMarkdownStructure_WhenParsed_ThenReportValidationErrors
- ✅ GivenMarkdownWithMultipleWorkItemTypes_WhenParsed_ThenExtractAllWorkItemIds

### Deliverables
- **Unified Parser:** src/ConvertMarkdownToHierarchyJson.ps1 (replaced separate parsers)
- **Tests:** test/storyAcTests/2221ParseModifiedMarkdown/2221ParseModifiedMarkdownTest.ps1
- **Status:** All tests passing | Refactored for maintainability | No build warnings
"@

$body = @{
    text = $comment
} | ConvertTo-Json -Depth 10

$url = "https://dev.azure.com/$org/$project/_apis/wit/workitems/2221/comments?api-version=7.0-preview"

try {
    Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body $body | Out-Null
    Write-Host "✓ Added implementation summary comment to AB#2221" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed to add comment: $_" -ForegroundColor Red
    exit 1
}
