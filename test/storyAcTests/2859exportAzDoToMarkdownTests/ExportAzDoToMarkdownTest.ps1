#Requires -Version 7.0

<#
.SYNOPSIS
AC tests for Story 2859: Export AzDo work item hierarchy to a new plan file.
Validates <see cref="ExportAzDoToMarkdown.ps1"/> behavior against the live AzDo API.

.DESCRIPTION
Integration-level Pester tests that exercise ExportAzDoToMarkdown.ps1 against the
live Azure DevOps API. Tests cover:
- Correct hierarchy script dispatched based on work item type
- Auto-naming convention when -OutputPath is omitted
- PascalCase title conversion including dots/spaces
- Error thrown when target file exists without -Overwrite
- Overwrite allowed when -Overwrite is supplied
- Unsupported work item type causes descriptive error
- Pipeline output is the resolved file path

Run with:
    Invoke-Pester .\test\storyAcTests\2859exportAzDoToMarkdownTests\ExportAzDoToMarkdownTest.ps1
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

[string]$REPO_ROOT = Resolve-Path (Join-Path $PSScriptRoot '../../../')
[string]$SRC_DIR   = Join-Path $REPO_ROOT 'src'

# Stub ssLogIt.ps1 if not in PATH (keeps tests runnable in isolation)
if (-not (Get-Command 'ssLogIt.ps1' -ErrorAction SilentlyContinue)) {
    function global:ssLogIt.ps1 {
        param(
            [string]$Level,
            [string]$Message,
            [object]$Exception,
            [switch]$PushStackLevel,
            [switch]$PopStackLevel,
            [switch]$NoExtra
        )
    }
}

Describe 'ExportAzDoToMarkdown - Story 2859' {

    # -------------------------------------------------------------------------
    # Use Feature 2858 for most tests (smaller than Epic 1577)
    # Only use Epic 1577 for the auto-naming dot/space test
    # -------------------------------------------------------------------------

    # -------------------------------------------------------------------------
    # Scenario 1: Export a Feature hierarchy to an explicit output path
    # -------------------------------------------------------------------------
    Context 'Given Feature work item 2858 with an explicit -OutputPath' {

        It 'GivenFeatureWorkItem_WhenExportedWithExplicitPath_ItShouldCreateFile' {
            $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) "test-export-2859-feat-$([System.Guid]::NewGuid().ToString('N')).md"
            try {
                $result = & (Join-Path $SRC_DIR 'ExportAzDoToMarkdown.ps1') `
                    -WorkItemId 2858 `
                    -OutputPath $tmpFile
                Test-Path $tmpFile | Should Be $true
            } finally {
                if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }
            }
        }

        It 'GivenFeatureWorkItem_WhenExportedWithExplicitPath_ItShouldOutputThePath' {
            $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) "test-export-2859-feat-$([System.Guid]::NewGuid().ToString('N')).md"
            try {
                $result = & (Join-Path $SRC_DIR 'ExportAzDoToMarkdown.ps1') `
                    -WorkItemId 2858 `
                    -OutputPath $tmpFile
                $result | Should Be $tmpFile
            } finally {
                if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }
            }
        }

        It 'GivenFeatureWorkItem_WhenExported_PlanFileShouldContainWorkItemId' {
            $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) "test-export-2859-feat-$([System.Guid]::NewGuid().ToString('N')).md"
            try {
                & (Join-Path $SRC_DIR 'ExportAzDoToMarkdown.ps1') `
                    -WorkItemId 2858 `
                    -OutputPath $tmpFile | Out-Null
                $content = Get-Content $tmpFile -Raw
                ($content -match '\{WorkItemId\}:\s*2858') | Should Be $true
            } finally {
                if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }
            }
        }
    }

    # -------------------------------------------------------------------------
    # Scenario 2: Auto-naming with Feature 2858
    # -------------------------------------------------------------------------
    Context 'Given Feature work item 2858 and no -OutputPath' {

        It 'GivenFeatureWorkItem_WhenNoOutputPath_ItShouldCreateAutoNamedFile' {
            # Feature 2858 titled "Sync AzDo Hierarchy to Plan Markdown"
            # -> plan-2858-featSyncAzDoHierarchyToPlanMarkdown.md
            $result = & (Join-Path $SRC_DIR 'ExportAzDoToMarkdown.ps1') `
                -WorkItemId 2858
            try {
                Test-Path $result | Should Be $true
                # Verify auto-name pattern
                (Split-Path $result -Leaf) | Should Match '^plan-2858-feat'
            } finally {
                if ($null -ne $result -and (Test-Path $result)) { Remove-Item $result -Force }
            }
        }
    }

    # -------------------------------------------------------------------------
    # Scenario 3: Existing file blocks export without -Overwrite
    # -------------------------------------------------------------------------
    Context 'Given target file already exists and no -Overwrite' {

        It 'GivenExistingFile_WhenNoOverwrite_ItShouldThrow' {
            $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) "test-export-2859-exists-$([System.Guid]::NewGuid().ToString('N')).md"
            Set-Content -Path $tmpFile -Value 'existing content' -Encoding UTF8
            $threw = $false
            try {
                & (Join-Path $SRC_DIR 'ExportAzDoToMarkdown.ps1') `
                    -WorkItemId 2858 `
                    -OutputPath $tmpFile
            } catch {
                $threw = $true
            } finally {
                if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }
            }
            $threw | Should Be $true
        }

        It 'GivenExistingFile_WhenNoOverwrite_ItShouldNotModifyTheFile' {
            $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) "test-export-2859-exists-$([System.Guid]::NewGuid().ToString('N')).md"
            Set-Content -Path $tmpFile -Value 'existing content' -Encoding UTF8
            try {
                try {
                    & (Join-Path $SRC_DIR 'ExportAzDoToMarkdown.ps1') `
                        -WorkItemId 2858 `
                        -OutputPath $tmpFile
                } catch { }
                $content = Get-Content $tmpFile -Raw
                ($content -match 'existing content') | Should Be $true
            } finally {
                if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }
            }
        }
    }

    # -------------------------------------------------------------------------
    # Scenario 3b: -Overwrite allows writing to existing file
    # -------------------------------------------------------------------------
    Context 'Given target file already exists and -Overwrite is set' {

        It 'GivenExistingFile_WhenOverwrite_ItShouldSucceed' {
            $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) "test-export-2859-overwrite-$([System.Guid]::NewGuid().ToString('N')).md"
            Set-Content -Path $tmpFile -Value 'existing content' -Encoding UTF8
            $threw = $false
            try {
                & (Join-Path $SRC_DIR 'ExportAzDoToMarkdown.ps1') `
                    -WorkItemId 2858 `
                    -OutputPath $tmpFile `
                    -Overwrite | Out-Null
            } catch {
                $threw = $true
            } finally {
                if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }
            }
            $threw | Should Be $false
        }

        It 'GivenExistingFile_WhenOverwrite_FileShouldContainNewContent' {
            $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) "test-export-2859-overwrite-$([System.Guid]::NewGuid().ToString('N')).md"
            Set-Content -Path $tmpFile -Value 'existing content' -Encoding UTF8
            try {
                $null = & (Join-Path $SRC_DIR 'ExportAzDoToMarkdown.ps1') `
                    -WorkItemId 2858 `
                    -OutputPath $tmpFile `
                    -Overwrite
                $content = Get-Content $tmpFile -Raw
                ($content -match '\{WorkItemId\}:\s*2858') | Should Be $true
            } finally {
                if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }
            }
        }
    }

    # -------------------------------------------------------------------------
    # Scenario 4: Unsupported work item type throws a descriptive error
    # -------------------------------------------------------------------------
    Context 'Given a Task work item (ID 2230 - known Task in AzDo)' {

        It 'GivenTaskWorkItemType_WhenExported_ItShouldThrowWithTypeName' {
            # Work item 2230 is a Task
            $caught = $null
            try {
                & (Join-Path $SRC_DIR 'ExportAzDoToMarkdown.ps1') `
                    -WorkItemId 2230 `
                    -OutputPath (Join-Path ([System.IO.Path]::GetTempPath()) "test-2859-task.md")
            } catch {
                $caught = $_
            }

            $caught | Should Not BeNullOrEmpty
            ($caught.ToString() -match 'Task') | Should Be $true
        }
    }

    # -------------------------------------------------------------------------
    # Auto-naming: PascalCase title for Feature 2858 "Sync AzDo Hierarchy to Plan Markdown"
    # Expected: plan-2858-featSyncAzDoHierarchyToPlanMarkdown.md
    # -------------------------------------------------------------------------
    Context 'Auto-naming PascalCase title conversion for Feature with spaces' {

        It 'GivenFeatureTitleWithSpaces_WhenAutoNaming_ItShouldProducePascalCasedFileName' {
            $expectedFileName = 'plan-2858-featSyncAzDoHierarchyToPlanMarkdown.md'
            $expectedPath = Join-Path $REPO_ROOT "docs/plans/$expectedFileName"
            if (Test-Path $expectedPath) { Remove-Item $expectedPath -Force }

            $result = & (Join-Path $SRC_DIR 'ExportAzDoToMarkdown.ps1') `
                -WorkItemId 2858

            if (Test-Path $expectedPath) { Remove-Item $expectedPath -Force }
            $result | Should Be $expectedPath
        }
    }
}
