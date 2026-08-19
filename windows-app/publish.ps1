<#
Builds the Windows release bundle: publish, optionally sign, package.

    powershell -File publish.ps1              # unsigned bundle (local testing)
    powershell -File publish.ps1 -Sign        # signed bundle (real releases)

Output lands in windows-app\dist\PlantoirSetup.exe and Plantoir-win-x64.zip
with SHA-256 printed for the release notes. The version comes from ONE place:
<Version> in Plantoir\Plantoir.csproj — bump it there, tag the repo to
match (v<version>), and this script names everything else accordingly.

Signing uses Azure Artifact Signing (a.k.a. Trusted Signing) via the
`sign` dotnet tool and expects a prior `az login`. See the signing
runbook for the one-time account setup. The RFC 3161 timestamp is NOT
optional: Artifact Signing certificates live for days, and an
untimestamped signature stops validating when the certificate does.
#>
param(
    [switch]$Sign,
    [string]$SigningEndpoint = "https://eus.codesigning.azure.net",
    [string]$SigningAccount  = "plantoir-signing",
    [string]$SigningProfile  = "plantoir-public",
    [string]$TimestampUrl    = "http://timestamp.acs.microsoft.com"
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# ---- Signing preflight: fail in seconds, not after a minutes-long build ----
if ($Sign) {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw "Azure CLI not found. One-time install:  winget install --exact --id Microsoft.AzureCLI  (then open a NEW terminal)"
    }
    if (-not (Get-Command sign -ErrorAction SilentlyContinue)) {
        throw "The 'sign' tool is not installed. One-time install:  dotnet tool install --global sign --prerelease"
    }
    az account show --output none 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Not signed in to Azure. Run:  az login  (sign in as the Azure signing account) and retry."
    }
    Write-Host "Signing preflight OK: az CLI, sign tool, and an active az login." -ForegroundColor Green
}

# ---- Version, from the csproj alone ----------------------------------------
$csproj = [xml](Get-Content "Plantoir\Plantoir.csproj")
$version = ($csproj.Project.PropertyGroup.Version | Where-Object { $_ }) | Select-Object -First 1
if (-not $version) { throw "No <Version> found in Plantoir.csproj" }
Write-Host "Publishing Plantoir $version" -ForegroundColor Green

# ---- Publish ----------------------------------------------------------------
dotnet publish Plantoir\Plantoir.csproj -c Release -r win-x64
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }
$publishDir = "Plantoir\bin\Release\net9.0-windows10.0.19041.0\win-x64\publish"
$pri = "Plantoir\bin\Release\net9.0-windows10.0.19041.0\win-x64\Plantoir.pri"
if (Test-Path $pri) {
    Copy-Item $pri "$publishDir\resources.pri" -Force
    Copy-Item $pri "$publishDir\Plantoir.pri" -Force
}

# ---- The MCP server, into the same folder -----------------------------------
# A second binary, deliberately: Claude Code launches plantoir-mcp.exe itself,
# as a stdio subprocess, so it has to stay a plain console app with a path of
# its own. Folding it into Plantoir.exe would boot the whole WinUI runtime to
# speak JSON-RPC, and would break the Claude Code integration outright.
#
# Shipping it in the SAME folder is what keeps distribution one zip: the app
# looks beside itself first, and teachers never learn there are two files.
# Without this step the assistant reports that Plantoir's own tools cannot be
# found -- on a teacher's machine only, which is the worst place to find out.
dotnet publish Plantoir.Mcp\Plantoir.Mcp.csproj -c Release -r win-x64
if ($LASTEXITCODE -ne 0) { throw "dotnet publish (Plantoir.Mcp) failed" }
$mcpExe = "Plantoir.Mcp\bin\Release\net9.0\win-x64\publish\plantoir-mcp.exe"
if (-not (Test-Path $mcpExe)) { throw "plantoir-mcp.exe not found at $mcpExe" }
Copy-Item $mcpExe $publishDir -Force
Write-Host "Bundled plantoir-mcp.exe ($('{0:N1} MB' -f ((Get-Item $mcpExe).Length / 1MB)))" -ForegroundColor Green

# ---- Sign (our own binaries; third-party DLLs carry their makers' signatures)
if ($Sign) {
    # plantoir-mcp.exe is ours too, and an unsigned executable sitting beside
    # signed ones is exactly what SmartScreen complains about.
    $targets = @("$publishDir\Plantoir.exe", "$publishDir\Plantoir.dll", "$publishDir\Plantoir.Core.dll",
                 "$publishDir\plantoir-mcp.exe")
    if (Test-Path "$publishDir\llama\llama-server.exe") {
        $targets += "$publishDir\llama\llama-server.exe"
    }
    Write-Host "Signing $($targets.Count) binaries via $SigningAccount/$SigningProfile" -ForegroundColor Green
    # --azure-credential-type azure-cli: the default DefaultAzureCredential
    # probes the VM-only IMDS endpoint (169.254.169.254) first, and on a dev
    # machine that probe's failure aborts the chain before it reaches az login.
    sign code trusted-signing `
        --trusted-signing-endpoint $SigningEndpoint `
        --trusted-signing-account $SigningAccount `
        --trusted-signing-certificate-profile $SigningProfile `
        --azure-credential-type azure-cli `
        --timestamp-url $TimestampUrl `
        @targets
    if ($LASTEXITCODE -ne 0) { throw "signing failed (is 'az login' current?)" }

    # A signature without a timestamp dies with the short-lived certificate.
    $sig = Get-AuthenticodeSignature "$publishDir\Plantoir.exe"
    if ($sig.Status -ne 'Valid') { throw "Plantoir.exe signature is $($sig.Status)" }
    if (-not $sig.TimeStamperCertificate) { throw "Plantoir.exe signature has NO TIMESTAMP - do not ship this" }
    Write-Host "Signature valid and timestamped." -ForegroundColor Green
} else {
    Write-Host "Skipping signing (-Sign not given) - fine for local testing only." -ForegroundColor Yellow
}

# ---- Package: Inno Setup Installer & Portable Zip ---------------------------
New-Item -ItemType Directory -Force "dist" | Out-Null

# The publish tree holds 100+ toolchain files whose full paths exceed MAX_PATH
# from this repo's depth (the root alone is ~142 chars), and both ISCC and
# Compress-Archive fail on them. Map the folder to a free drive letter so every
# source path is short; the finally below unmaps it even if packaging throws.
$publishFull = (Resolve-Path $publishDir).Path
$substDrive = $null
foreach ($code in 90..71) {   # Z: down to G:
    $candidate = "$([char]$code):"
    if (-not (Test-Path "$candidate\")) {
        subst $candidate $publishFull
        if ($LASTEXITCODE -eq 0) { $substDrive = $candidate; break }
    }
}
if (-not $substDrive) { throw "No free drive letter to map the publish folder for packaging" }
Write-Host "Mapped $substDrive -> publish folder (long-path workaround)" -ForegroundColor Green

try {

# 1. Inno Setup Installer (Primary teacher distribution)
# No `?.` here: this script documents `powershell -File`, and Windows
# PowerShell 5.1 cannot PARSE the null-conditional operator — the whole
# script fails to start, not just this line.
$isccCommand = Get-Command iscc -ErrorAction SilentlyContinue
$iscc = if ($isccCommand) { $isccCommand.Source } else { $null }
if (-not $iscc) {
    # winget installs per-user (no admin rights) to LOCALAPPDATA; an elevated
    # install lands in Program Files (x86). Check both before giving up.
    $possiblePaths = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    )
    foreach ($possiblePath in $possiblePaths) {
        if (Test-Path $possiblePath) { $iscc = $possiblePath; break }
    }
}

if ($iscc) {
    Write-Host "Compiling Inno Setup installer via $iscc..." -ForegroundColor Green
    & $iscc "/DAppVersion=$version" "/DPublishDir=$substDrive" "installer.iss"
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed" }

    $installer = "dist\PlantoirSetup.exe"
    if ($Sign -and (Test-Path $installer)) {
        Write-Host "Signing $installer via $SigningAccount/$SigningProfile..." -ForegroundColor Green
        sign code trusted-signing `
            --trusted-signing-endpoint $SigningEndpoint `
            --trusted-signing-account $SigningAccount `
            --trusted-signing-certificate-profile $SigningProfile `
            --azure-credential-type azure-cli `
            --timestamp-url $TimestampUrl `
            $installer
        if ($LASTEXITCODE -ne 0) { throw "Installer signing failed" }
    }

    if (Test-Path $installer) {
        $instHash = (Get-FileHash $installer -Algorithm SHA256).Hash.ToLower()
        $instSize = '{0:N1} MB' -f ((Get-Item $installer).Length / 1MB)
        Write-Host ""
        Write-Host "Installer: $installer ($instSize)" -ForegroundColor Green
        Write-Host "SHA-256:   $instHash"
    }
} else {
    Write-Host "Inno Setup (iscc) not found - skipping installer compilation. (Install: winget install --exact --id JRSoftware.InnoSetup)" -ForegroundColor Yellow
}

# 2. Portable Zip
$zip = "dist\Plantoir-win-x64.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path "$substDrive\*" -DestinationPath $zip

} finally {
    subst $substDrive /D | Out-Null
}

$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
$size = '{0:N1} MB' -f ((Get-Item $zip).Length / 1MB)

Write-Host ""
Write-Host "Bundle:    $zip ($size)" -ForegroundColor Green
Write-Host "SHA-256:   $hash"
Write-Host ""
Write-Host "Next: tag v$version, create the GitHub release, attach the installer and zip."
