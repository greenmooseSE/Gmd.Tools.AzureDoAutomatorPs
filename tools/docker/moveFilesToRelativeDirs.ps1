$ErrorActionPreference = "Stop";
Set-StrictMode -Version Latest;
$projects = dotnet sln list | Select-Object -Skip 2
foreach ($project in $projects) {
    $target = $project
    $dir = Split-Path -Path $target -Parent
    $file = Split-Path -Path $target -Leaf
    if (!(Test-Path -Path $dir)) {
        Write-Host "New-Item -ItemType Directory -Path $dir";
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    Write-Host "Move-Item -Path $file -Destination $target";
}
