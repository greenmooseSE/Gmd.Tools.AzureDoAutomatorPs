
Set-StrictMode -Version 3
$ErrorActionPreference = 'Stop'

# Decrypt PAT from environment
$pat = $env:GMD_AZDO_MACHINE_WORKITEMSRW | ssEncryptDecrypt.ps1 -Decrypt

# Sanity check: verify PAT is working
Write-Host "Verifying PAT with GetAzDoWorkItem..."
.\src\GetAzDoWorkItem.ps1 -Organization falco-it -Project GMD -WorkItemId 1307 -PatToken $pat | Out-Null
Write-Host "✓ PAT verification passed`n"

# Setup
$org = "falco-it"
$proj = "GMD"
$workItemId = 1307

if (-not $pat) {
    Write-Error "PAT not available. Set `$pat in this session"
    exit 1
}

# Create authorization header
$auth = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))
$headers = @{ Authorization = $auth }

# Fetch comments
Write-Host "Fetching comments for work item $workItemId..."
$commentsUri = "https://dev.azure.com/$org/$proj/_apis/wit/workItems/$workItemId/comments?api-version=7.1-preview.3"
$response = Invoke-RestMethod -Method Get -Uri $commentsUri -Headers $headers -ErrorAction Stop
$comments = $response.comments

if (-not $comments) {
    Write-Host "No comments found"
    exit 0
}

Write-Host "Found $($comments.Count) comments`n"

# Process each comment and fetch reactions
$results = $comments | ForEach-Object {
    $comment = $_
    $commentId = $comment.id
    
    Write-Host "Processing comment $commentId..."
    
    # Fetch reactions for this comment
    # Endpoint: GET /_apis/wit/workItems/{workItemId}/comments/{commentId}/reactions?api-version=7.1-preview.1
    $reactionsUri = "https://dev.azure.com/$org/$proj/_apis/wit/workItems/$workItemId/comments/$commentId/reactions?api-version=7.1-preview.1"
    
    try {
        $reactionsResponse = Invoke-RestMethod -Method Get -Uri $reactionsUri -Headers $headers -ErrorAction Stop
        
        # Response should be a CommentReaction[] array per Microsoft docs
        # Normalize to array
        $reactions = @()
        if ($reactionsResponse -is [System.Array]) {
            $reactions = $reactionsResponse
        }
        elseif ($reactionsResponse.value -is [System.Array]) {
            $reactions = $reactionsResponse.value
        }
        elseif ($null -ne $reactionsResponse -and $reactionsResponse -isnot [System.Collections.Hashtable]) {
            $reactions = @($reactionsResponse)
        }
        
        # Format reactions for display
        $reactionsStr = @()
        if ($reactions.Count -gt 0) {
            $reactionGroups = $reactions | Group-Object -Property type | ForEach-Object {
                "$($_.Name):$($_.Count)"
            }
            $reactionsStr = $reactionGroups -join ', '
        }
        else {
            $reactionsStr = '(no reactions)'
        }
        
        Write-Host "  - Reactions found: $reactionsStr"
    }
    catch {
        Write-Host "  - Error fetching reactions: $($_.Exception.Message)" -ForegroundColor Yellow
        $reactionsStr = '(error fetching)'
    }
    
    # Create output object
    [PSCustomObject]@{
        Id        = $commentId
        Author    = $comment.createdBy.displayName
        Created   = $comment.createdDate
        Comment   = ($comment.text -replace '\r?\n', ' ')
        Reactions = $reactionsStr
    }
}

Write-Host "`n=== Results ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize -Property Id, Author, Created, Comment, Reactions
