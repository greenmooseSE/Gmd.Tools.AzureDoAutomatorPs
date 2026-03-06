# Helper script for temporary testing without updating chassi submodule
$ErrorActionPreference = "Stop";
Set-StrictMode -Version 3;

if (!(Test-Path "submodules/Gmd.Chassi.DotNet")) {
    throw "Expected 'submodules/Gmd.Chassi.DotNet' to exist.";
}

$chassiPath = "";
$testedPath = "$PSScriptRoot"
ssLogit.ps1 "Searching for Gmd.Chassi.DotNet...";
while (!$chassiPath) {
    $testedPath = Split-Path $testedPath -Parent;
    if (!$testedPath) {
        throw "Failed to find path to Gmd.Chassi.DotNet.";
    }
    [string]$pathToTest = "$testedPath/Gmd.Chassi.DotNet";
    if (Test-Path $pathToTest) {
        $chassiPath = $pathToTest;
    }
}
ssLogit.ps1 "Found at $chassiPath.";


ssInvokeExpr.ps1 "robocopy $chassiPath .\submodules\Gmd.Chassi.DotNet\ /xd .git /mir /njh /njs;";
ssInvokeExpr.ps1 ".\submodules\Gmd.Chassi.DotNet\updateFilesFromChassi.ps1 -NoConfirm";
ssInvokeExpr.ps1 ".\tools\docker\dockerBuild.ps1"
