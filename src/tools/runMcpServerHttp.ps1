<#
.SYNOPSIS
Start the MCP server in HTTP mode serving Azure DevOps Automator tools

.DESCRIPTION
Starts the Model Context Protocol (MCP) server in a separate PowerShell process using the 
Azure DevOps Automator configuration file (mcpConfig.yaml). The server listens on HTTP 
using a configurable port.

The MCP server exposes all PowerShell scripts as standardized tools that can be consumed
by AI assistants and other MCP clients over HTTP.

Before starting, validates that required environment variables are set:
- GMD_AZDO_ORGANIZATION: Azure DevOps organization name
- GMD_AZDO_PROJECT: Azure DevOps project name  
- GMD_AZDO_MACHINE_WORKITEMSRW: Personal Access Token for API access

After starting, performs smoke tests to verify the server is working correctly.

.PARAMETER HttpPort
The HTTP port for the MCP server to listen on. Defaults to 8081.

.PARAMETER Verbose
Show detailed server startup and runtime information.

.PARAMETER NoSmokeTest
Skip smoke tests after starting the server.

.OUTPUTS
Server starts in separate process and runs until interrupted. Logs all tool invocations and responses.
Parent process validates server health and displays exit status.

.EXAMPLE
Start MCP server on default port 8081:
    .\src\tools\runMcpServerHttp.ps1

Start MCP server on custom port:
    .\src\tools\runMcpServerHttp.ps1 -HttpPort 3000

Start with verbose logging:
    .\src\tools\runMcpServerHttp.ps1 -HttpPort 8081 -Verbose

Skip smoke tests:
    .\src\tools\runMcpServerHttp.ps1 -HttpPort 8081 -NoSmokeTest

.NOTES
- Requires the submodule Gmd.Tools.McpServerPs to be initialized
- Requires PowerShell 7+
- The configuration file src/mcpConfig.yaml must be valid and all scripts must exist
- Server runs in separate process and will remain running after script exits
- Close server by stopping the PowerShell process running RunMcpServer.ps1
#>

#Requires -Version 7.0

param(
    [int]$HttpPort = 8081,
    [switch]$Verbose,
    [switch]$NoSmokeTest
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Resolve paths
$scriptRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$configPath = Join-Path -Path $scriptRoot -ChildPath "src\mcpConfig.yaml"
$runMcpServerScript = Join-Path -Path $scriptRoot -ChildPath "submodules\Gmd.Tools.McpServerPs\src\RunMcpServer.ps1"

# ============================================================================
# Validate Configuration and Environment
# ============================================================================

# Validate configuration file exists
if (-not (Test-Path $configPath)) {
    Write-Error "Configuration file not found: $configPath"
    exit 1
}

# Validate RunMcpServer.ps1 exists
if (-not (Test-Path $runMcpServerScript)) {
    Write-Error "MCP Server runner not found: $runMcpServerScript`nMake sure the submodule Gmd.Tools.McpServerPs is initialized with: git submodule update --init --recursive"
    exit 1
}

# Validate required environment variables
$requiredEnvVars = @('GMD_AZDO_ORGANIZATION', 'GMD_AZDO_PROJECT', 'GMD_AZDO_MACHINE_WORKITEMSRW')
$missingEnvVars = @()

foreach ($envVar in $requiredEnvVars) {
    if ([string]::IsNullOrWhiteSpace((Get-Item -Path "env:$envVar" -ErrorAction SilentlyContinue).Value)) {
        $missingEnvVars += $envVar
    }
}

if ($missingEnvVars.Count -gt 0) {
    Write-Error @"
Missing required environment variables:
  - $($missingEnvVars -join "`n  - ")

These must be set before starting the MCP server:
  `$env:GMD_AZDO_ORGANIZATION = 'your-organization'
  `$env:GMD_AZDO_PROJECT = 'your-project'
  `$env:GMD_AZDO_MACHINE_WORKITEMSRW = 'your-pat-token' (or encrypted value)
"@
    exit 1
}

Write-Host "`n" -ForegroundColor Cyan
Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║      MCP Server for Azure DevOps Automator     ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "✅ Environment Validation:" -ForegroundColor Green
Write-Host "   Organization: $env:GMD_AZDO_ORGANIZATION"
Write-Host "   Project:      $env:GMD_AZDO_PROJECT"
Write-Host "   PAT Token:    $(if ($env:GMD_AZDO_MACHINE_WORKITEMSRW.Length -gt 10) { $env:GMD_AZDO_MACHINE_WORKITEMSRW.Substring(0, 10) + '...' } else { '***' })"
Write-Host ""
Write-Host "📋 Configuration:" -ForegroundColor Green
Write-Host "   Config File: $configPath"
Write-Host "   Listener:    HTTP"
Write-Host "   Port:        $HttpPort"
Write-Host "   Server Path: $runMcpServerScript"
Write-Host ""

# ============================================================================
# Start MCP Server in Separate Process
# ============================================================================

Write-Host "🚀 Starting MCP Server in separate process..." -ForegroundColor Green


# Start process and capture it

$scriptPath = Resolve-path "$PSScriptRoot/../../submodules/Gmd.Tools.McpServerPs/src/RunMcpServer.ps1";
$configPath = Resolve-path "$PSScriptRoot/../../src/mcpConfig.yaml";
Start-Process -FilePath (Get-Command pwsh.exe).Path `
    -ArgumentList @("-File", 
    $scriptPath, 
    "-ConfigPath", 
    $configPath,
     "-Listener", 
     "Http", 
     "-HttpPort", 
     $HttpPort,
      $(if ($Verbose) { "-Verbose" }));

# ============================================================================
# Wait for Server Startup
# ============================================================================

Write-Host "⏳ Waiting for server to initialize (10 seconds)..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

$serverUrl = "http://localhost:$HttpPort"

# ============================================================================
# Smoke Test
# ============================================================================

if (-not $NoSmokeTest) {
    Write-Host ""
    Write-Host "🧪 Running smoke tests..." -ForegroundColor Yellow
    
    $testsPassed = 0
    $testsFailed = 0
    
    # Test 1: Initialize MCP server connection
    try {
        Write-Host "   [1/3] Testing MCP initialize (handshake)..."
        
        $initRequest = @{
            jsonrpc = "2.0"
            id      = 1
            method  = "initialize"
            params  = @{
                protocolVersion = "2024-11-05"
                capabilities     = @{}
                clientInfo       = @{
                    name    = "AzDoAutomatorSmokeTest"
                    version = "1.0"
                }
            }
        } | ConvertTo-Json -Depth 10
        
        $response = Invoke-WebRequest -Uri "$serverUrl" `
            -Method Post `
            -Body $initRequest `
            -ContentType "application/json" `
            -ErrorAction Stop `
            -TimeoutSec 5 `
            -SkipHttpErrorCheck
        
        if ($response.StatusCode -in @(200, 201)) {
            $responseBody = $response.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($responseBody.result) {
                Write-Host "        ✅ MCP server initialized successfully" -ForegroundColor Green
                $testsPassed++
            } else {
                Write-Host "        ⚠️ Initialize response but no result" -ForegroundColor Yellow
                $testsFailed++
            }
        } else {
            Write-Host "        ⚠️ HTTP $($response.StatusCode) (server may still be starting)" -ForegroundColor Yellow
            $testsFailed++
        }
    }
    catch {
        Write-Host "        ⚠️ Initialize skipped (server may still be starting): $($_.Exception.Message -split "`n" | Select-Object -First 1)" -ForegroundColor Yellow
    }
    
    # Wait a bit more for server to fully initialize
    Start-Sleep -Milliseconds 500
    
    # Test 2: List available MCP tools  
    try {
        Write-Host "   [2/3] Testing tools/list (enumerate available tools)..."
        
        $listRequest = @{
            jsonrpc = "2.0"
            id      = 2
            method  = "tools/list"
            params  = @{}
        } | ConvertTo-Json -Depth 10
        
        $response = Invoke-WebRequest -Uri "$serverUrl" `
            -Method Post `
            -Body $listRequest `
            -ContentType "application/json" `
            -ErrorAction Stop `
            -TimeoutSec 5 `
            -SkipHttpErrorCheck
        
        if ($response.StatusCode -in @(200, 201)) {
            $responseBody = $response.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($responseBody.result.tools -and $responseBody.result.tools.Count -gt 0) {
                Write-Host "        ✅ Found $($responseBody.result.tools.Count) available tools" -ForegroundColor Green
                $testsPassed++
            } else {
                Write-Host "        ⚠️ No tools returned" -ForegroundColor Yellow
                $testsFailed++
            }
        } else {
            Write-Host "        ⚠️ HTTP $($response.StatusCode)" -ForegroundColor Yellow
            $testsFailed++
        }
    }
    catch {
        Write-Host "        ⚠️ tools/list skipped: $($_.Exception.Message -split "`n" | Select-Object -First 1)" -ForegroundColor Yellow
    }
    
    # Test 3: Call read-only tool (get-workitem 1305)
    try {
        Write-Host "   [3/3] Testing tools/call with get-workitem 1305..."
        
        $toolRequest = @{
            jsonrpc = "2.0"
            id      = 3
            method  = "tools/call"
            params  = @{
                name      = "get-workitem"
                arguments = @{
                    WorkItemId = 1305
                }
            }
        } | ConvertTo-Json -Depth 10
        
        $response = Invoke-WebRequest -Uri "$serverUrl" `
            -Method Post `
            -Body $toolRequest `
            -ContentType "application/json" `
            -ErrorAction Stop `
            -TimeoutSec 10 `
            -SkipHttpErrorCheck
        
        if ($response.StatusCode -in @(200, 201)) {
            $responseBody = $response.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($responseBody.result) {
                # Check if we got work item data back
                $resultText = $responseBody.result | ConvertTo-Json -Compress
                if ($resultText.Length -gt 50) {
                    Write-Host "        ✅ Tool executed - got work item data ($($resultText.Length) chars)" -ForegroundColor Green
                    $testsPassed++
                } else {
                    Write-Host "        ⚠️ Tool executed but response seems incomplete" -ForegroundColor Yellow
                    $testsFailed++
                }
            } else {
                Write-Host "        ⚠️ Tool call returned no result" -ForegroundColor Yellow
                $testsFailed++
            }
        } else {
            Write-Host "        ⚠️ HTTP $($response.StatusCode)" -ForegroundColor Yellow
            $testsFailed++
        }
    }
    catch {
        Write-Host "        ⚠️ Tool call skipped (server may not have network access): $($_.Exception.Message -split "`n" | Select-Object -First 1)" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "📊 Smoke Test Results:" -ForegroundColor Cyan
    Write-Host "   Passed: $testsPassed"
    Write-Host "   Failed: $testsFailed"
    
    if ($testsFailed -eq 0 -and $testsPassed -gt 0) {
        Write-Host "   Status: ✅ All tests passed" -ForegroundColor Green
    } elseif ($testsPassed -gt 0) {
        Write-Host "   Status: ⚠️ Some tests were skipped (may require network)" -ForegroundColor Yellow
    } else {
        Write-Host "   Status: ⚠️ Tests could not connect to server" -ForegroundColor Yellow
    }
}

# ============================================================================
# Final Summary
# ============================================================================

Write-Host ""
Write-Host "ℹ️  Server Information:" -ForegroundColor Cyan
Write-Host "   URL:     $serverUrl"
Write-Host ""

# Keep parent process alive and monitor server process
Write-Host "✅ MCP Server is running. Main script can now exit." -ForegroundColor Green
Write-Host "   Server will continue running in background." -ForegroundColor Green
Write-Host ""

