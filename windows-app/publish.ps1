<#
Builds the Windows release bundle: publish, optionally sign, package.

    powershell -File publish.ps1              # unsigned bundle (local testing)
    powershell -File publish.ps1 -Sign        # signed bundle (real releases)
    powershell -File publish.ps1 -WithoutAssistantEngine   # a developer's bundle with no llama\ (never with -Sign)
    powershell -File publish.ps1 -CheckLedgerOnly          # only the named-gap check -Sign makes, then stop

Before anything is built it runs NamedGapLedgerTests against <Version> (the
release being built, not the last one shipped). With -Sign or
-CheckLedgerOnly an entry owed by this release or an earlier one REFUSES the
run; without them it is a warning, because an unsigned bundle is a test build
made while that release's work is still open (#862).

Never install an unsigned bundle over a real copy of Plantoir. Since #862 it
carries the number of the release being BUILT (2.0.0 while v2.0.0 is in
progress), and the update check offers only a NEWER version, so that copy
would never be offered the real release of the same number.

Output lands in windows-app\dist\PlantoirSetup.exe and Plantoir-win-x64.zip
with SHA-256 printed for the release notes. The version comes from ONE place:
<Version> in Plantoir\Plantoir.csproj — raised on dev when work on a release
starts (RELEASING.md -> "When the number is raised"), checked at the cut, the
repo tagged to match (v<version>), and this script names everything else
accordingly.

Signing uses Azure Artifact Signing (a.k.a. Trusted Signing) via the
`sign` dotnet tool and expects a prior `az login`. See the signing
runbook for the one-time account setup. The RFC 3161 timestamp is NOT
optional: Artifact Signing certificates live for days, and an
untimestamped signature stops validating when the certificate does.
#>
param(
    [switch]$Sign,
    # A developer's build with no assistant engine (no Vendor\llama). Refused
    # together with -Sign: a signed bundle without llama\ is what 1.9.0 shipped.
    [switch]$WithoutAssistantEngine,
    # Run only the named-gap ledger check, enforced as -Sign enforces it, and
    # stop: how the refusal is proved without a signing login or a build.
    [switch]$CheckLedgerOnly,
    [string]$SigningEndpoint = "https://eus.codesigning.azure.net",
    [string]$SigningAccount  = "plantoir-signing",
    [string]$SigningProfile  = "plantoir-public",
    [string]$TimestampUrl    = "http://timestamp.acs.microsoft.com"
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# ---- The named-gap ledger: nothing owed by this release may still be open --
# Since #862 the ordinary suite compares the ledger with the last release
# Windows SHIPPED (site.json and updates/windows.xml), because <Version> is
# raised on dev when work on a release starts and every entry owed by that
# release is allowed while the work is open. So the cut is checked HERE, in
# the one command every Windows release runs: the same fact, with
# PLANTOIR_LEDGER_BASELINE=build, compares each entry with <Version>.
# Enforced only with -Sign (and -CheckLedgerOnly): an unsigned bundle is the
# documented local test build, and website/shots/capture_windows.py makes one
# too, both while the release's work is still open. Judged by the totals
# (TestRunOutcome.ps1), never the exit code. Rejected: reading
# NamedGapLedger.cs with a regex here (a second reader of C# source, which
# drifts the first time a milestone constant is renamed).
. "$PSScriptRoot\TestRunOutcome.ps1"

# The failing tests of a `dotnet test` transcript: each "Failed <name> [..]"
# with the lines of its "Error Message:" (up to "Stack Trace:"). So a refusal
# for any reason but an owed entry still says WHICH test and WHY (#862 review
# M1: a feed regenerated before a rebuild failed the site-and-feed fact, and
# the refusal named nothing).
function Get-FailedTests([string]$transcript) {
    $failures = @()
    $current = $null
    $inMessage = $false
    foreach ($line in ($transcript -split "`r?`n")) {
        if ($line -match '^\s+Failed (\S+) \[') {
            if ($current) { $failures += $current }
            $current = [pscustomobject]@{ Name = $Matches[1]; Message = @() }
            $inMessage = $false
            continue
        }
        if ($null -eq $current) { continue }
        if ($line -match '^\s+Error Message:\s*$') { $inMessage = $true; continue }
        if ($line -match '^\s+(Stack Trace|Standard Output Messages):\s*$') { $inMessage = $false; continue }
        if ($inMessage -and $line.Trim()) { $current.Message += $line.Trim() }
    }
    if ($current) { $failures += $current }
    ,$failures
}

$enforceLedger = $Sign -or $CheckLedgerOnly
$ledgerLog = Join-Path ([IO.Path]::GetTempPath()) 'plantoir-publish-ledger-check.txt'
Write-Host "Checking the named-gap ledger against this build's <Version> (NamedGapLedgerTests)..." -ForegroundColor Green
Write-Host "  This builds and runs the ledger's tests: about two minutes from a cold build, seconds when warm. Output: $ledgerLog"
$baselineBefore = $env:PLANTOIR_LEDGER_BASELINE
$env:PLANTOIR_LEDGER_BASELINE = 'build'
try {
    $ledgerRun = $null
    Invoke-TestRun -DotnetArguments @('test', 'Plantoir.Tests\Plantoir.Tests.csproj', '--nologo',
                                      '--filter', 'FullyQualifiedName~NamedGapLedgerTests') -Result ([ref]$ledgerRun) | Out-Null
} finally {
    $env:PLANTOIR_LEDGER_BASELINE = $baselineBefore
}
Set-Content -LiteralPath $ledgerLog -Value $ledgerRun.Output -Encoding UTF8
$ledgerOutcome = Get-TestRunOutcome -Output $ledgerRun.Output -ExitCode $ledgerRun.ExitCode
if ($ledgerOutcome.Verdict -ne 'Passed') {
    $owedLines = @($ledgerRun.Output -split "`r?`n" |
                   Where-Object { $_ -match ' is owed by #\d+ on | names the milestone ' } |
                   ForEach-Object { $_.Trim() })
    $failedTests = Get-FailedTests $ledgerRun.Output
    $ledgerMessage = "The named-gap ledger is not clear for this build. $($ledgerOutcome.Summary)"
    if ($failedTests.Count -gt 0) {
        $ledgerMessage += "`nFailing: " + (($failedTests | ForEach-Object { $_.Name }) -join ', ')
    }
    if ($owedLines.Count -gt 0) {
        $ledgerMessage += "`n$($owedLines.Count) ledger entries are owed by this release or an earlier one:`n  " +
                          ($owedLines -join "`n  ")
        $remedy = "A signed release cannot be cut over them: build each, or move its issue and entry to a " +
                  "later milestone with Russell's say-so (contracts/README.md -> `"Named gaps`")."
    } elseif ($ledgerOutcome.Verdict -eq 'Failed') {
        foreach ($failure in $failedTests) {
            $ledgerMessage += "`n$($failure.Name):`n  " + (@($failure.Message | Select-Object -First 4) -join "`n  ")
        }
        $remedy = "No entry is owed: another of the ledger's own tests failed, so read its message above. " +
                  "If it is TheSiteAndTheFeedAgreeOnWhatWindowsLastShipped during a cut, website/updates/windows.xml " +
                  "already carries an item site.json does not: the feed was generated before this rebuild. Restore " +
                  "the committed feed first, then run this again (RELEASING.md -> `"The update feed (Windows)`")."
    } else {
        $buildErrors = @($ledgerRun.Output -split "`r?`n" | Where-Object { $_ -match ': error [A-Z]+\d+' } |
                         ForEach-Object { $_.Trim() } | Select-Object -Unique -First 10)
        if ($buildErrors.Count -gt 0) { $ledgerMessage += "`n  " + ($buildErrors -join "`n  ") }
        $remedy = "No entry is owed: the ledger check did not run to a result. Fix what stopped it " +
                  "(the whole output is in $ledgerLog) and run this again."
    }
    if ($enforceLedger) {
        throw "$ledgerMessage`n$remedy"
    }
    Write-Warning "$ledgerMessage`n$remedy`nThis unsigned bundle is built anyway; publish.ps1 -Sign refuses it."
} else {
    Write-Host "Named-gap ledger: nothing owed by this build. $($ledgerOutcome.Summary)" -ForegroundColor Green
}
if ($CheckLedgerOnly) { return }

# ---- The assistant's engine (llama\): refused when missing ----------------
# The signed 1.9.0 shipped with NO llama\ folder: Plantoir.csproj includes
# Vendor\llama only when it exists, and nothing else looked, so a build on a
# clone where windows-app\Vendor\fetch-llama.ps1 had never run produced an
# installer with no assistant engine, and an upgrade hid it (Inno never
# deletes an older install's llama\ files). Measured 2026-11-12 (#700).
# What llama-server.exe loads, read from its imports and llama.cpp's backend
# loader: its -impl DLL, llama, llama-common, mtmd, ggml, ggml-base, LLVM's
# OpenMP runtime (libomp140.x86_64.dll, which ggml-base and every CPU backend
# import), and at least the Vulkan backend and the generic CPU one (the app
# runs it with --n-gpu-layers 999 and falls back to the CPU). The import tables
# were read from the PE headers of b10435's files (#700 third review).
$AssistantEngineFiles = @('llama-server.exe', 'llama-server-impl.dll', 'llama.dll', 'llama-common.dll', 'mtmd.dll',
                          'ggml.dll', 'ggml-base.dll', 'ggml-vulkan.dll', 'ggml-cpu-x64.dll', 'libomp140.x86_64.dll')
function Get-MissingAssistantEngineFiles([string]$folder) {
    $missing = @()
    foreach ($name in $AssistantEngineFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $folder $name))) { $missing += $name }
    }
    ,$missing
}
if ($Sign -and $WithoutAssistantEngine) {
    throw "-WithoutAssistantEngine is for a developer's build only and is refused with -Sign: a signed release must carry the assistant's engine."
}
if (-not $WithoutAssistantEngine) {
    $missingVendor = Get-MissingAssistantEngineFiles (Join-Path $PSScriptRoot 'Vendor\llama')
    if ($missingVendor.Count -gt 0) {
        throw "windows-app\Vendor\llama is missing $($missingVendor -join ', '). Run windows-app\Vendor\fetch-llama.ps1 first (or pass -WithoutAssistantEngine for a developer's build that is never released)."
    }
}

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
# Restore the MCP server for win-x64 first. Plantoir.csproj publishes it from
# an <MSBuild> task after its own build (PublishMcpBesideApp), and that task
# does not restore, so on a fresh clone or worktree the first publish stopped
# with NETSDK1004 "Assets file ...\Plantoir.Mcp\obj\project.assets.json not
# found" (measured 2026-11-12, #700). A restore that is already done costs
# a second or two.
dotnet restore Plantoir.Mcp\Plantoir.Mcp.csproj -r win-x64
if ($LASTEXITCODE -ne 0) { throw "dotnet restore (Plantoir.Mcp) failed" }
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

# The published folder itself, before anything is signed or packaged: the
# build's Condition="Exists(...)" would leave llama\ out without a word.
if (-not $WithoutAssistantEngine) {
    $missingPublished = Get-MissingAssistantEngineFiles (Join-Path $publishDir 'llama')
    if ($missingPublished.Count -gt 0) {
        throw "The published folder's llama\ is missing $($missingPublished -join ', '), so the installer would have no assistant engine. Run windows-app\Vendor\fetch-llama.ps1 and publish again."
    }
    Write-Host "The assistant's engine is in the published folder (llama\, $($AssistantEngineFiles.Count) files checked)." -ForegroundColor Green
}

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
