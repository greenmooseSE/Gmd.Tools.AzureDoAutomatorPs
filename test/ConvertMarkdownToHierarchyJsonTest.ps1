#Requires -Version 7.0

<#
.SYNOPSIS  
Tests for ConvertMarkdownToHierarchyJson parsing logic demonstrating the fix for issue:
- Parser now recognizes descriptions WITHOUT colons: **Description**
- Parser also supports backward compatibility with inline format: **Description**: content
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Setup: Ensure ssLogIt.ps1 can be called (mock it if needed)
if (-not (Get-Command 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    function ssLogIt.ps1 {
        param([string]$Level, [string]$Message, [object]$Exception)
        # Silent mock for testing
    }
}

Describe "ConvertMarkdownToHierarchyJson parser" {
    
    Context "Description format recognition (REGRESSION BUG FIX)" {
        
        It "should recognize description markers WITHOUT colons (standard format from exampleMarkdown)" {
            # Arrange: Create markdown with **Description** (NO colon) - the standard format
            # This is the format used in exampleMarkdown.md which was NOT working before the fix
            [string]$markdown = @"
# Epic: Test Epic
**tags**: test
**Description**
This is the epic description without a colon marker

## Feature: Test Feature
**tags**: test
**Description**
This is the feature description without a colon marker

### Story: Test Story
**tags**: test
**SP**: 3
**Description**
This is the story description without a colon marker
"@

            # Create temp file
            $markdownPath = [System.IO.Path]::GetTempFileName() + ".md"
            $markdown | Set-Content -LiteralPath $markdownPath
            
            try {
                # Act
                $result = & "$PSScriptRoot/../src/ConvertMarkdownToHierarchyJson.ps1" -MarkdownFilePath $markdownPath
                
                # Assert: Descriptions SHOULD BE populated (this was the bug - they were null before)
                $result.epics.Count | Should -Be 1
                $result.epics[0].description | Should -Not -BeNullOrEmpty
                $result.epics[0].description | Should -Be "This is the epic description without a colon marker"
                Write-Host "✓ Epic description correctly recognized: $($result.epics[0].description)"
                
                $result.epics[0].features.Count | Should -Be 1
                $result.epics[0].features[0].description | Should -Not -BeNullOrEmpty
                $result.epics[0].features[0].description | Should -Be "This is the feature description without a colon marker"
                Write-Host "✓ Feature description correctly recognized: $($result.epics[0].features[0].description)"
                
                $result.epics[0].features[0].stories.Count | Should -Be 1
                $result.epics[0].features[0].stories[0].description | Should -Not -BeNullOrEmpty
                $result.epics[0].features[0].stories[0].description | Should -Be "This is the story description without a colon marker"
                Write-Host "✓ Story description correctly recognized: $($result.epics[0].features[0].stories[0].description)"
            }
            finally {
                Remove-Item -LiteralPath $markdownPath -ErrorAction SilentlyContinue
            }
        }

        It "should recognize titles and tags in standard format" {
            # Arrange
            [string]$markdown = @"
# Epic: Management System
**tags**: core, platform
**Description**
Main management epic

## Feature: User Authentication
**tags**: security, authentication
**Description**
User login and session management
"@

            $markdownPath = [System.IO.Path]::GetTempFileName() + ".md"
            $markdown | Set-Content -LiteralPath $markdownPath
            
            try {
                # Act
                $result = & "$PSScriptRoot/../src/ConvertMarkdownToHierarchyJson.ps1" -MarkdownFilePath $markdownPath
                
                # Assert
                $result.epics[0].title | Should -Be "Management System"
                $result.epics[0].tags | Should -Contain "core"
                $result.epics[0].tags | Should -Contain "platform"
                Write-Host "✓ Epic title and tags recognized correctly"
                
                $result.epics[0].features[0].title | Should -Be "User Authentication"
                $result.epics[0].features[0].tags | Should -Contain "security"
                $result.epics[0].features[0].tags | Should -Contain "authentication"
                Write-Host "✓ Feature title and tags recognized correctly"
            }
            finally {
                Remove-Item -LiteralPath $markdownPath -ErrorAction SilentlyContinue
            }
        }

        It "should also support descriptions WITH colons (backward compatibility)" {
            # Arrange: Create markdown with **Description**: (WITH colon, inline)
            # This is the older format that should still work
            [string]$markdown = @"
# Epic: Legacy Format
**tags**: test
**Description**: This is an inline description with colon

## Feature: Legacy Feature
**tags**: test
**Description**: Feature description inline
"@

            $markdownPath = [System.IO.Path]::GetTempFileName() + ".md"
            $markdown | Set-Content -LiteralPath $markdownPath
            
            try {
                # Act
                $result = & "$PSScriptRoot/../src/ConvertMarkdownToHierarchyJson.ps1" -MarkdownFilePath $markdownPath
                
                # Assert: Both formats should work
                $result.epics[0].description | Should -Be "This is an inline description with colon"
                Write-Host "✓ Epic description with colon (backward compat) works"
                
                $result.epics[0].features[0].description | Should -Be "Feature description inline"
                Write-Host "✓ Feature description with colon (backward compat) works"
            }
            finally {
                Remove-Item -LiteralPath $markdownPath -ErrorAction SilentlyContinue
            }
        }

        It "mixed formats should both work in same file" {
            # Arrange: Mix both formats in one file
            [string]$markdown = @"
# Epic: Mixed Format
**tags**: test
**Description**
This is without colon

## Feature: With Colon
**tags**: test
**Description**: This is with colon

### Story: Another Without
**tags**: test
**SP**: 3
**Description**
Without colon again
"@

            $markdownPath = [System.IO.Path]::GetTempFileName() + ".md"
            $markdown | Set-Content -LiteralPath $markdownPath
            
            try {
                # Act
                $result = & "$PSScriptRoot/../src/ConvertMarkdownToHierarchyJson.ps1" -MarkdownFilePath $markdownPath
                
                # Assert: Both formats should work in the same file
                $result.epics[0].description | Should -Be "This is without colon"
                $result.epics[0].features[0].description | Should -Be "This is with colon"
                $result.epics[0].features[0].stories[0].description | Should -Be "Without colon again"
                Write-Host "✓ All mixed formats recognized correctly"
            }
            finally {
                Remove-Item -LiteralPath $markdownPath -ErrorAction SilentlyContinue
            }
        }
    }
}
