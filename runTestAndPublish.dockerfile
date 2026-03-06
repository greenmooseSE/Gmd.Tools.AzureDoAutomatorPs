# escape=`

# We need the below

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build-env
WORKDIR /app

# Needs to be after FROM
ARG NUGET_USERNAME
ARG PROJECT_TO_PUBLISH
ARG SLN_FILE

# Temporary dir we use as base to do a nuget restore with
ARG RESTORE_DIR

SHELL ["pwsh", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

RUN if ([string]::IsNullOrEmpty($env:NUGET_USERNAME)) { Write-Host "NUGET_USERNAME is not set, exiting"; exit 1; }

COPY $RESTORE_DIR .

# For troubleshooting restore
RUN $matchPattern = ( (Get-Content .\.gitignore | Select-String -Pattern '^[^!\*]+/$' | ?{ $_ } | % { $_.Matches[0].Value.TrimEnd('/') }) -join '|'); Get-ChildItem -recurse -file | ? { !($_.FullName -imatch $matchPattern) } | % { $_.FullName };

# Add NuGet source with username and password
RUN --mount=type=secret,id=nuget_password `
    [string]$thePwd = (Get-Content /run/secrets/nuget_password | Out-String).Trim(); `
    dotnet nuget update source gmdTiny --username $env:NUGET_USERNAME `
    --password $thePwd --store-password-in-clear-text `
    --configfile ./nuget.config

RUN dotnet restore

# Copy the rest of the solution files, we avoid including other root files to have the build layer cachable.
COPY src ./src
COPY test ./test

# We have to use build without --no-restore to avoid error in "ResolvePackageAssets task".
RUN dotnet build $env:SLN_FILE -c Release

COPY ci.runsettings ./

# For troubleshooting test issues with unexpected filenames/casing etc.
RUN $matchPattern = ( (Get-Content .\.gitignore | Select-String -Pattern '^[^!\*]+/$' | ?{ $_ } | % { $_.Matches[0].Value.TrimEnd('/') }) -join '|'); Get-ChildItem -recurse -file | ? { !($_.FullName -imatch $matchPattern) } | % { $_.FullName };


RUN dotnet test $env:SLN_FILE --no-restore --no-build -c Release --verbosity normal -s ci.runsettings

# Check if PROJECT_TO_PUBLISH is set, if not exit
RUN if ([string]::IsNullOrEmpty($env:PROJECT_TO_PUBLISH)) { Write-Host "PROJECT_TO_PUBLISH is not set, exiting."; exit 1; }

# Publish
RUN dotnet publish --no-restore --no-build -c Release -o publishOut $env:PROJECT_TO_PUBLISH

# Start a new stage to create the final image
FROM mcr.microsoft.com/dotnet/aspnet:8.0
# Set the working directory in the Docker container
WORKDIR /app
# Copy the build output from the previous stage
COPY --from=build-env /app/publishOut .
# Set the command that will be run when the Docker container starts
ENTRYPOINT ["dotnet", "Gmd.ChangeTracker.WebApi.dll"]
