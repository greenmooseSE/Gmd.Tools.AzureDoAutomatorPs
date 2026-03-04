param(
    [string]$SlnFile = "",
    [string]$PublishProject = "",
    [switch]$NoPublish)
$ErrorActionPreference = "Stop";
Set-StrictMode -Version 3;

$publishProj = "";
[string]$slnFileRelPath = $null;
$currDir = (Get-Item ./).FullName;

function makeRelative([string]$filePath) {
    $res = $filePath.Replace($currDir, "") -ireplace "^[/\\]+", "";
    return $res;
}

if (!$publishProj -and !$NoPublish) {
    $webApis = @(Get-ChildItem src -Filter *WebApi -Directory);
    if ($webApis.Count -eq 1) {
        $publishProj = makeRelative -filePath ($webApis[0]).FullName;
        Write-Host "Using project for publish: $publishProj"; 
    }
    else {
        Write-Host "No projects found for publish.";
    }
}


if (!$SlnFile) {
    $slnFiles = @(Get-Item *.sln | ? { !($_.Name -imatch "NoTests"); });
    if ($slnFiles.Count -ne 1) {
        throw "Expected 1 sln file, found $($slnFiles.Count).";
    }
    $SlnFile = $slnFiles[0].FullName;
}
$slnFileRelPath = makeRelative -filePath $SlnFile;

#--progress=plain ensure we get output from the commands

# Copy csproj/sln files to output
$sourceDir = (Get-Item ./).FullName
$dstDirPath = Join-Path $sourceDir ".build";
$dstDirRel = makeRelative -filePath $dstDirPath;
$nugetPwdFile = New-TemporaryFile;
try {
    #We include .gitignore so we can use it as filter when echoing directory content in dockerfile (for troubleshooting).
    $includeFiles = @(
        ".gitignore",
        "*.csproj",
        "Directory.Build.props",
        "global.json", 
        "nuget.config",
        "packages.lock.json",
        "*.targets"
    );
    $files = @(Get-ChildItem -Path $sourceDir/src -Include $includeFiles -Recurse);
    $files += @(Get-ChildItem -Path $sourceDir/test -Include $includeFiles -Recurse);
    $files += @( $includeFiles | % { if (test-path $_) { Get-Item $_ } } );
    # $files += @(Get-ChildItem -Path $sourceDir/test -Include *.csproj, packages.lock.json, Directory.Build.props -Recurse);

    foreach ($file in ($files | % { $_.FullName; } | Sort-Object)) {
        $relPath = makeRelative -filePath $file;
        $fullDstPath = Join-Path $dstDirPath $relpath;
        $dstDir = makeRelative -filePath (Split-Path $fullDstPath -Parent);
        Write-Host "Copying $relPath => $dstDir.";
        if (!(Test-Path $dstDir -PathType Container)) {
            New-Item $dstDir -ItemType Directory | Out-Null;
        }
        Copy-Item $relPath $dstDir
    }
    Write-Host "Copying $slnFileRelPath => $dstDirRel.";
    Copy-Item $slnFileRelPath $dstDirRel;

    [string]$nugetPwd = $env:NUGET_PASSWRD;

    Set-Content -Path $nugetPwdFile -Value $nugetPwd;
    $buildArgs = @("RESTORE_DIR=$dstDirRel", 
        "NUGET_USERNAME=$($env:NUGET_USER)", 
        "SLN_FILE=$slnFileRelPath"
    );
    if ($publishProj) {
        $buildArgs += "PROJECT_TO_PUBLISH=$publishProj";
    }
    $dockerTag = "temp-build"
    
    [string[]]$params = @("build --build-arg " + @($buildArgs -join " --build-arg ") + (" -t $dockerTag -f runTestAndPublish.dockerfile --progress=plain" -split " "));
    # --secret is part of BuildKit. We use it to avoid the pwd to be echoed during build.
    $params += @("--secret", "id=nuget_password,src=`"$nugetPwdFile`"", ".");

    Write-Host "docker $($params -join " ")".Replace("$nugetPwd", "***");
    $proc = Start-Process -FilePath (get-command docker).Path -ArgumentList $params -NoNewWindow -PassThru -Wait;
    Write-Host "Exit code: $($proc.ExitCode)";
}
catch {
    Write-Host -ForegroundColor Red "Error: $($_.Exception.Message)";
    Write-Host -ForegroundColor DarkGray $_.ScriptStackTrace;
    exit 1;
}
finally {
    Remove-Item $nugetPwdFile;
    Remove-Item $dstDirPath -Recurse -Force;
}
