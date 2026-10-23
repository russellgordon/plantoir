<#
.SYNOPSIS
    Every destination, and every pairing, published for real and fetched back.
    The Windows counterpart of verify-deploy.sh.

.DESCRIPTION
    WHY THIS EXISTS AND WHY IT IS SEPARATE FROM THE SUITE
    =====================================================
    `verify.sh` is bash and does not run on Windows, and `verify-deploy.sh` is
    bash too â€” so until now the PowerShell half of publishing had NO automated
    gate of any kind. That is not a theoretical gap. It is exactly how
    `deploy.ps1` came to contain a check that was true for every site with two
    or more pages, which made publishing to a folder impossible on this
    platform and was found only by publishing by hand (GUI-IMPROVEMENTS row
    410).

    Like its mac sibling this is opt-in and never wired into anything: it needs
    credentials, it needs the network, and it CREATES REAL SITES on real
    accounts. Run it when the publishing path changes.

    WHAT IT IS GUARDING AGAINST, SPECIFICALLY
    =========================================
    Both of these shipped on one platform or the other, and neither was caught
    by a unit test:

      * A preview build reaching a published site. Serve mode bakes a
        live-reload client into every page; on a published site that script
        makes a student's browser ask permission to "access other apps and
        services on this device".
      * A publish that reported success and copied the wrong thing â€” or
        nothing at all.

    Both are invisible to any check that does not publish and then LOOK at what
    came out. That is this script's whole job.

    A NOTE ON WHAT "SKIP" MEANS HERE
    ================================
    A destination with no credentials on this machine is SKIPPED, loudly, and
    the run can still pass. A destination that is configured and then fails is
    a FAILURE. The distinction matters: a script that quietly passes because it
    ran nothing is the failure mode this whole file exists to prevent.

.PARAMETER WorkingFolder
    A Plantoir working folder. Defaults to a copy made for testing, never a
    teacher's own.

.PARAMETER FirstPublish
    Publish as a FIRST publish (#123, #623): the saved surname and the
    section's Netlify and Cloudflare site records are moved aside (renamed,
    never deleted) once the run has started,
    a random letters-only surname is given when deploy.py asks for one, and so
    each host gets a NEW site with a name nobody has. Everything moved aside is
    put back on every exit path from then on, Ctrl+C included (a run killed
    outright is put right by the next run's preflight), and the records this
    run wrote are deleted, so the
    course points at its own sites again. The sites it made are listed in the
    Result block; nothing deletes them. Without it, the run publishes to the
    sites the section already has and asks nothing.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File verify-deploy.ps1 `
        -WorkingFolder "C:\Users\me\Desktop\plantoir-test" -Course ICS3U -Section 1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File verify-deploy.ps1 -FirstPublish
#>
[CmdletBinding()]
param(
    [string]$WorkingFolder = "$env:USERPROFILE\Desktop\plantoir-deploy-verify",
    [string]$Course = "ICS3U",
    [int]$Section = 1,
    [switch]$FirstPublish
)

$ErrorActionPreference = 'Continue'
$script:Pass = 0
$script:Fail = 0
$script:Skip = 0
$script:Failures = @()
$script:ReachedTheEnd = $false

function Hdr([string]$text) {
    Write-Host ""
    Write-Host "== $text" -ForegroundColor Cyan
}
function Ok([string]$text) { $script:Pass++; Write-Host "  [ok]   $text" -ForegroundColor DarkGray }
function No([string]$text) { $script:Fail++; $script:Failures += $text; Write-Host "  [FAIL] $text" -ForegroundColor Red }
function Skipped([string]$text) { $script:Skip++; Write-Host "  [skip] $text" -ForegroundColor Yellow }

# ------------------------------------------------------------------ preflight
Hdr "Preflight - refuse clearly rather than half-running"

$config = Join-Path $WorkingFolder "courses\$Course\course_config.json"
if (-not (Test-Path $config)) {
    Write-Host "No course at $config" -ForegroundColor Red
    Write-Host "Point -WorkingFolder at a working folder that has one." -ForegroundColor Red
    exit 1
}
Ok "course found: $Course section $Section in $WorkingFolder"

# The course's own settings are restored on every exit path, including Ctrl+C.
$originalConfig = Get-Content -LiteralPath $config -Raw -Encoding UTF8
$work = Join-Path ([IO.Path]::GetTempPath()) ("plantoir-deploy-verify-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$folderTarget = Join-Path $work "published"

# ------------------------------------------- the runtime the launchers build with
# REQUIRED, and defaulted to this checkout's own (#630). With no
# PLANTOIR_RUNTIME the launchers fall back to the INSTALLED app's runtime,
# which is whatever release was installed last: at the 1.8.5 cut that one had
# no vendor\pyodide, so every engine check failed and read as a product
# failure. A teacher never meets this - the app sets its own runtime - so this
# is the harness's to get right. Exported so PtyDriver, cmd and the launcher
# all inherit it.
if (-not $env:PLANTOIR_RUNTIME) {
    $env:PLANTOIR_RUNTIME = Join-Path $PSScriptRoot "windows-app\Vendor\runtime"
    $runtimeSaid = "defaulted to this checkout's"
} else { $runtimeSaid = "from PLANTOIR_RUNTIME" }
$script:Runtime = $env:PLANTOIR_RUNTIME
if (-not (Test-Path (Join-Path $script:Runtime 'manifest.json')) -or -not (Test-Path (Join-Path $script:Runtime 'vendor\pyodide'))) {
    Write-Host "The runtime at $($script:Runtime) has no manifest.json or no vendor\pyodide." -ForegroundColor Red
    Write-Host "Run windows-app\Vendor\fetch-runtime.ps1, or set PLANTOIR_RUNTIME to a runtime that has them." -ForegroundColor Red
    exit 1
}
$script:RuntimePython = Join-Path $script:Runtime 'python\python.exe'
Ok "runtime ($runtimeSaid): $($script:Runtime)"

# Anything else that might rewrite this folder's .toolchain while the run is
# using it. A WARNING, not a refusal: a running Plantoir or plantoir-mcp
# usually serves a different working folder (the director's session runs
# one), and only a person can say which.
$others = @(Get-Process -Name Plantoir, plantoir-mcp -ErrorAction SilentlyContinue)
foreach ($other in $others) {
    $path = try { $other.Path } catch { "" }
    Write-Host "  [warn] $($other.ProcessName) is running (pid $($other.Id)$(if ($path) { ", $path" })). If it serves $WorkingFolder it can rewrite .toolchain under this run." -ForegroundColor Yellow
}

# ------------------------------------- the recipe the launchers run, mirrored
# The checks below read THIS checkout's contracts/, so the launchers must run
# THIS checkout's recipe (#630). They run whatever the folder's .toolchain\
# last received, and nothing refreshes it but the app: at the 1.8.5 cut the
# mirror dated from a week before, 79 files under scripts\ differed, and a run
# gave 59 passed, 89 failed - against a product that was fine.
#
# MIRRORED rather than refused, because mirroring is exactly what the app does
# to a folder it touches (ToolchainMirror.RefreshLaunchers/RefreshToolchain),
# and a refusal would only hand the person running this the robocopy remedy
# every time. A TRUE mirror, as ToolchainMirror.SyncDirectory is: a file the
# checkout no longer has is deleted, or a removed script would go on running.
# From the WORKING TREE, not `git archive HEAD` (the screenshot harness's
# choice): the checks read the working tree's contracts, so a HEAD recipe
# would recreate the mismatch this exists to remove. Which tree it was is
# printed in the Result block.
$script:RecipeRootFiles = @('Dockerfile', 'setup.sh', 'preview.sh', 'deploy.sh',
                            'setup.bat', 'preview.bat', 'deploy.bat', 'setup.ps1', 'preview.ps1', 'deploy.ps1')
$script:Launchers = @('setup.ps1', 'preview.ps1', 'deploy.ps1', 'setup.bat', 'preview.bat', 'deploy.bat')
$script:MirrorChanged = @()
function Sync-RecipeFile([string]$Source, [string]$Destination) {
    $src = Get-Item -LiteralPath $Source
    $dst = Get-Item -LiteralPath $Destination -ErrorAction SilentlyContinue
    if ($dst -and $dst.Length -eq $src.Length) {
        if ([Math]::Abs(($src.LastWriteTimeUtc - $dst.LastWriteTimeUtc).TotalSeconds) -lt 0.002) { return }
        if ((Get-FileHash -LiteralPath $Source).Hash -eq (Get-FileHash -LiteralPath $Destination).Hash) {
            $dst.LastWriteTimeUtc = $src.LastWriteTimeUtc
            return
        }
    }
    $folder = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Force -Path $folder | Out-Null }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    (Get-Item -LiteralPath $Destination).LastWriteTimeUtc = $src.LastWriteTimeUtc
    $script:MirrorChanged += $Destination.Substring($WorkingFolder.TrimEnd('\').Length + 1)
}
function Sync-RecipeFolder([string]$Source, [string]$Destination) {
    $wanted = @{}
    foreach ($file in Get-ChildItem -LiteralPath $Source -Recurse -File -Force) {
        $relative = $file.FullName.Substring($Source.Length + 1)
        # Python's caches are made by running the tests; the app bundles none.
        if ($relative -match '(^|\\)__pycache__\\' -or $relative -like '*.pyc') { continue }
        $wanted[$relative.ToLowerInvariant()] = $true
        Sync-RecipeFile $file.FullName (Join-Path $Destination $relative)
    }
    if (Test-Path -LiteralPath $Destination) {
        foreach ($file in Get-ChildItem -LiteralPath $Destination -Recurse -File -Force) {
            $relative = $file.FullName.Substring($Destination.Length + 1)
            if ($wanted.ContainsKey($relative.ToLowerInvariant())) { continue }
            # The launchers run Python FROM .toolchain, so it makes caches of
            # its own there. Deleting them would count as a change on every
            # run and force a --full-rebuild each time (measured: the second
            # run "mirrored" 22 files, every one a .pyc).
            if ($relative -match '(^|\\)__pycache__\\' -or $relative -like '*.pyc') { continue }
            Remove-Item -LiteralPath $file.FullName -Force
            $script:MirrorChanged += "$($Destination.Substring($WorkingFolder.TrimEnd('\').Length + 1))\$relative (deleted)"
        }
    }
}
try {
    $toolchainRoot = Join-Path $WorkingFolder ".toolchain"
    foreach ($name in $script:Launchers) { Sync-RecipeFile (Join-Path $PSScriptRoot $name) (Join-Path $WorkingFolder $name) }
    foreach ($name in $script:RecipeRootFiles) { Sync-RecipeFile (Join-Path $PSScriptRoot $name) (Join-Path $toolchainRoot $name) }
    $recipeFolders = (Get-Content -LiteralPath (Join-Path $PSScriptRoot "contracts\toolchain.json") -Raw -Encoding UTF8 | ConvertFrom-Json).recipeFolders.folders
    foreach ($folder in $recipeFolders) { Sync-RecipeFolder (Join-Path $PSScriptRoot $folder) (Join-Path $toolchainRoot $folder) }
} catch {
    Write-Host "The recipe could not be mirrored into $WorkingFolder : $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Refusing to run: the checks would judge this checkout against whatever the folder had before." -ForegroundColor Red
    exit 1
}
if ($script:MirrorChanged.Count -eq 0) { Ok "the folder already runs this checkout's recipe (launchers and .toolchain, nothing differed)" }
else {
    Ok "mirrored this checkout's recipe into the folder: $($script:MirrorChanged.Count) file(s) changed, the first: $((@($script:MirrorChanged) | Select-Object -First 5) -join ', ')"
}
$script:Commit = (& git -C $PSScriptRoot rev-parse --short HEAD 2>$null)
$script:Dirty = @(& git -C $PSScriptRoot status --porcelain 2>$null).Count

# ------------------------------------------------- a FIRST publish (#123, #623)
# What a first publish reads, moved aside so deploy.py asks for a surname and
# names new sites: the saved surname (and its pre-.internal location), the
# section's Netlify record (and its legacy per-section one) and its
# Cloudflare record.
#
# THE ORIGINALS ARE NEVER DELETED, only renamed to <path>.verify-deploy-hidden,
# and the sentinel records, path by path and AFTER each step, whether that
# path's original was hidden or absent. Restoring deletes what is at a path
# only when its original is safe beside it (hidden) or there never was one
# (absent): then it is a record deploy.py wrote for the test's site. Anything
# else - a move that failed, a kill between a move and the sentinel - is left
# alone, and a hidden original is always moved back. So a run killed half way
# is put right by the NEXT run's preflight, and no failure on the way can cost
# the course its real records. (The first version wrote every path into the
# sentinel before moving anything and then deleted whatever stood at each: a
# move that failed would have deleted the real record. Opus review.)
$script:FirstPublishState = @(
    (Join-Path $WorkingFolder "courses\.internal\profile.json"),
    (Join-Path $WorkingFolder "courses\_secrets\profile.json"),
    (Join-Path $WorkingFolder "courses\$Course\.netlify_sites\section$Section.json"),
    (Join-Path $WorkingFolder "courses\$Course\.cloudflare_sites\section$Section.json"),
    (Join-Path $WorkingFolder "courses\$Course\section$Section\.netlify_site.json")
)
$script:Sentinel = Join-Path $WorkingFolder "courses\.verify-deploy-first-publish.json"
$script:SitesWritten = @()
$script:HideRecord = @{}
function Write-HideSentinel {
    $entries = @(foreach ($key in $script:HideRecord.Keys) { @{ path = $key; original = $script:HideRecord[$key] } })
    [IO.File]::WriteAllText($script:Sentinel, (ConvertTo-Json -InputObject @{ entries = $entries } -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
}
function Test-AnythingHidden {
    if (Test-Path -LiteralPath $script:Sentinel) { return $true }
    foreach ($path in $script:FirstPublishState) { if (Test-Path -LiteralPath "$path.verify-deploy-hidden") { return $true } }
    return $false
}
function Restore-FirstPublishState {
    if (-not (Test-AnythingHidden)) { return }
    $recorded = @{}
    if (Test-Path -LiteralPath $script:Sentinel) {
        try {
            $said = Get-Content -LiteralPath $script:Sentinel -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($entry in @($said.entries)) { if ($entry.path) { $recorded[[string]$entry.path] = [string]$entry.original } }
        } catch { }
    }
    foreach ($path in $script:FirstPublishState) {
        $hidden = "$path.verify-deploy-hidden"
        $originalIsSafe = Test-Path -LiteralPath $hidden
        $thereWasNone = $recorded[$path] -eq 'absent'
        if ((Test-Path -LiteralPath $path) -and ($originalIsSafe -or $thereWasNone)) {
            # What deploy.py wrote for the test's site. Its name is kept for
            # the Result block, then the record goes.
            try {
                $record = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
                $kind = if ($path -like '*cloudflare_sites*') { 'Cloudflare Pages project' } elseif ($path -like '*netlify*') { 'Netlify site' } else { '' }
                if ($kind -and $record.name) { $script:SitesWritten += "$kind $($record.name)" }
            } catch { }
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
        if ($originalIsSafe) {
            try { Move-Item -LiteralPath $hidden -Destination $path -Force -ErrorAction Stop }
            catch { Write-Host "  [warn] could not put $path back from $hidden - move it back by hand: $($_.Exception.Message)" -ForegroundColor Yellow; return }
        } elseif ($recorded[$path] -eq 'hidden') {
            Write-Host "  [warn] $path was recorded as moved aside but $hidden is not there; left as it is" -ForegroundColor Yellow
        }
    }
    Remove-Item -LiteralPath $script:Sentinel -Force -ErrorAction SilentlyContinue
    $script:HideRecord = @{}
    Write-Host "  put the saved surname and the section's own site records back" -ForegroundColor DarkGray
}
# Moving them aside happens INSIDE the run's try (below), so the finally that
# puts them back covers every exit path after it, Ctrl+C included.
function Hide-FirstPublishState {
    Write-HideSentinel
    foreach ($path in $script:FirstPublishState) {
        if (Test-Path -LiteralPath $path) {
            try { Move-Item -LiteralPath $path -Destination "$path.verify-deploy-hidden" -Force -ErrorAction Stop }
            catch { return "could not move $path aside: $($_.Exception.Message)" }
            $script:HideRecord[$path] = 'hidden'
        } else {
            $script:HideRecord[$path] = 'absent'
        }
        Write-HideSentinel
    }
    return ""
}
if (Test-AnythingHidden) {
    Restore-FirstPublishState
    Ok "a FIRST-publish run before this one was stopped half way: its surname and site records were put back first"
    $script:SitesWritten = @()
}
$script:Surname = 'Testing'
if ($FirstPublish) {
    $letters = 'abcdefghijklmnopqrstuvwxyz'.ToCharArray()
    $script:Surname = 'vd' + (-join (1..8 | ForEach-Object { $letters | Get-Random }))
}

# A page of runnable code and a formula (#455, #494, #583), borrowed into the
# section so every destination carries the Python engine, the site's own
# KaTeX and the isolation headers; removed on EVERY exit path (the finally at
# the bottom). The same page as verify-deploy.sh's, Swift fence included:
# since v1.8.6 (#570) Windows compiles Swift too, so the preview gets Swift
# ready on this PC the way a teacher's first Swift preview does (the product
# path, preview.ps1 -> swift_windows_fetch.py: about 2.3 GB the first time,
# nothing after) and every site must carry the page's compiled program.
$runnerPage = Join-Path $WorkingFolder "courses\$Course\section$Section\Runner Deploy Check.md"
$runnerPageText = @'
---
title: Runner Deploy Check
codeRunner: true
---
A page of runnable code borrowed by verify-deploy.ps1 (plantoir-runner-deploy-7f3a), and a formula: $\frac{a}{b} = c^2$.

```python run stdin
name = input("Name? ")
print("Hello,", name)
```

```swift run
print("What is your name?")
let name = readLine() ?? ""
print("Hello, \(name)!")
```
'@
function Remove-RunnerPage {
    if (Test-Path -LiteralPath $runnerPage) {
        Remove-Item -LiteralPath $runnerPage -Force -ErrorAction SilentlyContinue
        Write-Host "  took the borrowed page of runnable code away" -ForegroundColor DarkGray
    }
}

# UTF-8 with NO byte-order mark, always. Windows PowerShell 5.1's
# `-Encoding UTF8` writes a BOM, and `build_site.py` reads course_config.json
# as plain utf-8 and dies on it: "Unexpected UTF-8 BOM (decode using
# utf-8-sig)". Every publish in the first run of this script failed that way,
# and the failure looked exactly like a broken product rather than a broken
# test. The app itself never writes the file this way; only a script would.
$script:NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-Utf8NoBom([string]$path, [string]$text) {
    [IO.File]::WriteAllText($path, $text, $script:NoBom)
}

function Restore-Config {
    if ($originalConfig) { Write-Utf8NoBom $config $originalConfig }
}

# Kill a process AND ITS CHILDREN.
#
# `$process.Kill($true)` is what this used to call, and under Windows
# PowerShell 5.1 it does not exist: System.Diagnostics.Process there offers
# only `Kill()` â€” the boolean overload is .NET Core 3 and later. The call threw
# and an empty catch swallowed it, so a timed-out launcher was never stopped at
# all. Two runs of this script left a powershell.exe and its python.exe child
# sitting at a prompt for forty-five minutes because of it.
#
# `Kill()` alone would not be enough either: it ends the shell and leaves the
# Python and node underneath it running, which is the very orphaning this
# repository's stop-preview work is about. taskkill /T walks the tree.
function Stop-Tree([int]$processId) {
    try { & taskkill.exe /PID $processId /T /F *> $null } catch { }
}

# The preview launched below, so it can be stopped on EVERY exit path.
$script:PreviewProcess = $null
function Stop-AnyPreview {
    if ($script:PreviewProcess -and -not $script:PreviewProcess.HasExited) {
        Stop-Tree $script:PreviewProcess.Id
    }
    # And the section's own processes, through the launcher's own stop mode -
    # the same sweep the app uses, so a run that dies early does not leave a
    # preview serving for the next one to trip over.
    try {
        & cmd.exe /c "cd /d `"$WorkingFolder`" && .\preview.bat $Course $Section --stop" *> $null
    } catch { }
}

# Credentials decide what can be exercised. Read through the same Credential
# Manager target names deploy.ps1 uses, and never printed.
function Has-Credential([string]$target) {
    $listed = cmdkey /list:$target 2>&1 | Out-String
    return -not ($listed -match 'NONE' -or $listed -match 'Cannot find')
}
$haveNetlify = Has-Credential 'containerized-quartz-netlify'
$haveCloudflare = (Has-Credential 'containerized-quartz-cloudflare') -and (Has-Credential 'containerized-quartz-cloudflare-account')
if ($haveNetlify) { Ok "Netlify credentials present" } else { Skipped "no Netlify credentials - those cases will be skipped, not failed" }
if ($haveCloudflare) { Ok "Cloudflare credentials present" } else { Skipped "no Cloudflare credentials - those cases will be skipped, not failed" }

# PtyDriver, which is what answers the launcher's questions.
#
# BUILT HERE rather than assumed present: it is a project in the solution and
# nothing else in this script would notice a stale or missing binary. A build
# failure is a FAILURE and not a skip - a harness that quietly stops answering
# prompts is a harness that silently goes back to the thing this replaced,
# which took every default in silence and covered the first-publish path with
# nothing at all.
$ptyProject = Join-Path $PSScriptRoot "windows-app\PtyDriver\PtyDriver.csproj"
$ptyBuild = & dotnet build $ptyProject -c Debug --nologo 2>&1 | Out-String
$script:PtyDriver = Join-Path $PSScriptRoot "windows-app\PtyDriver\bin\Debug\net9.0\PtyDriver.exe"
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $script:PtyDriver)) {
    Write-Host $ptyBuild -ForegroundColor DarkGray
    Write-Host "PtyDriver could not be built, and it is what answers the launcher's questions." -ForegroundColor Red
    Write-Host "Refusing to run: without it every prompt would go unanswered and the run would hang." -ForegroundColor Red
    exit 1
}
Ok "PtyDriver built - the launcher's questions will be answered by prompt text"

# ------------------------------------------------------------------- helpers
function Set-Destination {
    param([string]$Primary, [string]$FolderPath = "", [string]$AdditionalJson = "")
    $json = Get-Content -LiteralPath $config -Raw -Encoding UTF8 | ConvertFrom-Json
    $json.deploy_target = $Primary
    if ($json.PSObject.Properties.Name -contains 'deploy_folder_path') { $json.deploy_folder_path = $FolderPath }
    else { $json | Add-Member -NotePropertyName deploy_folder_path -NotePropertyValue $FolderPath }
    if ($AdditionalJson) {
        $json | Add-Member -NotePropertyName additional_deploy_targets -NotePropertyValue (ConvertFrom-Json $AdditionalJson) -Force
    } elseif ($json.PSObject.Properties.Name -contains 'additional_deploy_targets') {
        $json.PSObject.Properties.Remove('additional_deploy_targets')
    }
    Write-Utf8NoBom $config ($json | ConvertTo-Json -Depth 30)
}


# Every prompt this harness is willing to answer, and what it answers.
#
# ANSWERING BY PROMPT TEXT rather than feeding blind newlines, which is what
# the mac's verify-deploy.sh has done for months through `expect`. Its own
# comment carries the reason: "a blind feed of newlines cannot tell one prompt
# from another and was tried first, and failed." This side redirected stdin
# from a file instead, which made `sys.stdin.isatty()` false so deploy.py
# asked NOTHING and took every default silently - so the first-publish path
# was covered by no automated check at all (GitHub issue #123).
#
# THE REGEXES ARE ANCHORED, AND THAT IS THE WHOLE SAFETY STORY. PtyDriver
# matches the last non-empty line and the first rule wins, so a loose pattern
# answers a question it was not written for. That matters more here than
# anywhere else in this repository: `deploy.py` says it plainly at the site
# prompt - "This name is shared globally with all users across the world" - so
# a wrong answer does not clutter an account, it CLAIMS a global address.
#
# The failure modes are asymmetric, which is why these are few and tight. A
# rule that does not match is safe: PtyDriver waits, times out, kills, and the
# run is reported as a hang. A rule that matches too eagerly is the expensive
# one.
#
# NO `(y/n)` CATCH-ALL, which the mac's block does carry. On this platform
# nothing in the publish path asks one: the only [Y/n] is deploy.ps1's
# course-code guard, and it cannot fire for a code that does not end in a
# digit-zero. A catch-all answering "yes" to any future question is a bet on
# nobody ever adding a destructive one.
#
# `{ENTER}` accepts the offered default rather than typing a name, which is
# the conservative choice and the mac's. On a name CONFLICT that means
# accepting `<base>-01`: deliberately matching macOS (Russell, 2026-09-09)
# rather than answering 'q' to cancel, which was the other candidate.
$script:PromptRules = @(
    @{ Pattern = 'last name.*:$';                       Reply = $script:Surname },
    @{ Pattern = 'letters only for your last name.*:$'; Reply = $script:Surname },
    @{ Pattern = 'Enter Netlify site name.*\]:$';       Reply = '{ENTER}'  },
    @{ Pattern = 'different Netlify site name.*\]:$';   Reply = '{ENTER}'  }
)

function Run-Launcher {
    param([string]$Script, [string[]]$LauncherArgs, [string]$LogFile, [int]$TimeoutSeconds = 900)

    # Refuse in a way that COUNTS, rather than letting Start-Process throw.
    #
    # This is not defensive padding. The first run of the rewritten harness put
    # the PtyDriver path in $script:PtyDriver in the preflight and then wiped it
    # a few lines later with a leftover initialiser, so every launcher call died
    # on a parameter-binding error - and the run ended with no Result block and
    # EXIT CODE 0. A harness that stops half way and reports success is the
    # failure this whole file exists to prevent, and it took the harness itself
    # to demonstrate it.
    if (-not $script:PtyDriver -or -not (Test-Path $script:PtyDriver)) {
        No "PtyDriver is not available, so no launcher question could be answered"
        return @{ ExitCode = 125; Log = "" }
    }

    Remove-Item $LogFile -ErrorAction SilentlyContinue
    $quoted = ($LauncherArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '

    # The launcher is still run from a generated .cmd, and that is now doing
    # MORE work than it was: it keeps every argument quoted in a file rather
    # than threaded through two more layers of command line, and it records the
    # launcher's own errorlevel.
    #
    # WHAT CHANGED: it no longer redirects output to $LogFile. It must not -
    # PtyDriver is the thing reading the output now, and a redirect would send
    # the prompts to a file where nothing can see them to answer. The log comes
    # from PtyDriver's --raw-log instead.
    $codeFile = Join-Path $work ("code-" + [Guid]::NewGuid().ToString('N').Substring(0,6) + ".txt")
    $runner = Join-Path $work ("run-" + [Guid]::NewGuid().ToString('N').Substring(0,6) + ".cmd")
    Write-Utf8NoBom $runner (@(
        "@echo off",
        "call .\$Script $quoted",
        "echo %ERRORLEVEL% > `"$codeFile`""
    ) -join "`r`n")

    # --raw-log, NOT --log. PtyDriver's --log is a TranscriptBuilder view: it
    # DROPS PLANTOIR_HEALTH: lines, and past MaximumRetainedLines it used to
    # stop writing altogether. Every assertion below reads this file, and one
    # of them ("Killed existing process on port") reports Ok when its line is
    # ABSENT - so a truncated log would turn a real regression into a pass.
    $rawLog = $LogFile

    # ONE STRING, every argument quoted by hand. `Start-Process -ArgumentList`
    # joins an ARRAY with spaces and quotes NOTHING, so `last name.*:$` arrived
    # as two arguments and every rule after it shifted by one - measured while
    # writing this, against a stub, which is why no real site paid for it.
    # TrimEnd on the separator before quoting: a folder path ending in a
    # backslash makes the closing quote an escaped one (\"), which corrupts
    # argv for everything after it.
    $parts = @('--cwd', ('"' + $WorkingFolder.TrimEnd('\','/') + '"'),
               '--raw-log', ('"' + $rawLog + '"'),
               '--settle', '600',
               '--timeout', "$TimeoutSeconds")
    foreach ($rule in $script:PromptRules) {
        $parts += '--rule'
        $parts += ('"' + $rule.Pattern + '=>' + $rule.Reply + '"')
    }
    $parts += @('--', 'cmd.exe', '/c', ('"' + $runner + '"'))

    # NOT redirected, and that is load-bearing. PtyDriver captured NOTHING when
    # its own stdout was redirected - not from PowerShell and not from a shell -
    # which is the same shape as issue #89, "starting the Windows app with
    # redirected output makes every launcher fail silently". It reads its child
    # through a pseudoconsole, so it needs no console of its own; it needs its
    # stdout left alone. The log is a FILE, so nothing is lost by that.
    $process = Start-Process -FilePath $script:PtyDriver -ArgumentList ($parts -join ' ') `
                             -WorkingDirectory $WorkingFolder -PassThru -WindowStyle Hidden
    if (-not $process.WaitForExit(($TimeoutSeconds + 60) * 1000)) {
        Stop-Tree $process.Id
        $partial = if (Test-Path $rawLog) { Get-Content $rawLog -Raw } else { "" }
        # 124 is "timed out", kept distinct from any code the launcher itself
        # can return, so a hang never reads as a refusal.
        return @{ ExitCode = 124; Log = $partial }
    }
    try { $process.WaitForExit() } catch { }

    $text = if (Test-Path $rawLog) { Get-Content $rawLog -Raw } else { "" }

    # A HANG STILL READS AS 124, which it had stopped doing. PtyDriver's own
    # --timeout is $TimeoutSeconds and the wait below it is $TimeoutSeconds+60,
    # so PtyDriver always fires first: it kills the tree, cmd.exe comes back
    # 0xFFFFFFFF, and both the .cmd's errorlevel and PtyDriver's exit are -1.
    # The console then said "exited -1" and only the log carried the reason -
    # so a hang read as an ordinary refusal, which is the distinction this
    # script's own comment says must never blur. Its own transcript is the one
    # place that knows, so it is read.
    if ($text -match '(?m)^# (TIMEOUT|SAFETY VALVE)') {
        return @{ ExitCode = 124; Log = $text }
    }
    # The launcher's OWN errorlevel, from the .cmd, in preference to
    # PtyDriver's. PtyDriver returns the child's code faithfully, but the
    # .cmd's record is the one this script has trusted since a measured bug
    # (Start-Process reporting an empty ExitCode) made two real Netlify
    # publishes read as failures while the sites they had just created
    # answered 200.
    $code = -1
    if (Test-Path $codeFile) {
        $raw = (Get-Content $codeFile -Raw).Trim()
        if ($raw -match '^-?\d+$') { $code = [int]$raw }
    }
    if ($code -eq -1) { $code = $process.ExitCode }

    Assert-OnlyExpectedPromptsWereAnswered $text
    return @{ ExitCode = $code; Log = $text }
}

# Every question this run answered was one it meant to answer.
#
# THE FIRST VERSION OF THIS WAS A TAUTOLOGY, and it is worth saying so where
# the next person will read it. It re-tested each answered prompt against
# $script:PromptRules - the very list PtyDriver had just matched to decide to
# answer. PtyDriver only replies when a rule matches, and the "# prompt:" line
# it writes is that same matched string, so every prompt matched by
# construction and the check could not fail. It was claimed to turn an
# over-eager rule into a failed run. It did nothing of the kind. Found by
# adversarial review, 2026-09-09.
#
# What gives it teeth is being STRICTER than the matching rules: these are the
# exact sentences deploy.py prints, anchored at both ends. A rule that matched
# something else still answers it - nothing can prevent that - but the run then
# FAILS instead of passing green with a stranger's address taken.
#
# Copied from scripts/deploy.py: :336 and :339 (the surname and its retry),
# :381 rendering "Enter Netlify site name [<default>]: ", and :488 the
# conflict. Kept as anchored patterns rather than literals because the default
# inside the brackets varies with the course.
$script:ExpectedQuestions = @(
    '^First time setup\.\.\. what is your last name\? \(letters only\):$',
    "^Please enter letters only for your last name \(e\.g\., 'Gordon'\):$",
    '^Enter Netlify site name \[[^\]]*\]:$',
    "^Choose a different Netlify site name \(or 'q' to cancel\) \[[^\]]*\]:$"
)

function Assert-OnlyExpectedPromptsWereAnswered([string]$log) {
    if (-not $log) { return }
    $conflicts = 0
    foreach ($line in ($log -split "`r?`n")) {
        if ($line -notmatch '^# prompt:\s*(.+)$') { continue }
        $asked = $Matches[1].Trim()

        $known = $false
        foreach ($pattern in $script:ExpectedQuestions) {
            if ($asked -match $pattern) { $known = $true; break }
        }
        if (-not $known) {
            No "the harness answered a question deploy.py does not ask: `"$asked`" - a rule matched something it was not written for"
        }
        if ($asked -match 'different Netlify site name') { $conflicts++ }
    }

    # A name conflict means the address was taken and the run accepted
    # <base>-01, then -02... Each is a real global address. deploy.py returns at
    # the first success so one leg creates at most one site, but a run walking
    # several suffixes is worth knowing about rather than passing silently.
    if ($conflicts -gt 2) {
        No "the harness accepted $conflicts fallback site names in one leg - addresses are being taken faster than expected"
    }
}

function Check-Folder {
    param([string]$What, [string]$Path)
    if (-not (Test-Path (Join-Path $Path "index.html"))) { No "$What - no front page was written"; return }
    $pages = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Filter *.html -ErrorAction SilentlyContinue)
    if ($pages.Count -eq 0) { No "$What - nothing was published"; return }
    Ok "$What - $($pages.Count) pages written, front page present"
    $dirty = @($pages | Select-String -Pattern "ws://localhost:" -List | Select-Object -First 1)
    if ($dirty.Count -gt 0) { No "$What - the published site carries the preview's live-reload client" }
    else { Ok "$What - no page carries the live-reload client" }
}

# ------------------------------------------- page addresses on Netlify (#628, #657)
# verify-deploy.sh's check_page_links, run here as the SAME program: it is
# read out of verify-deploy.sh at run time (the heredoc inside
# check_page_links) rather than copied, so the two platforms judge links by
# one text and cannot drift. Ported to PowerShell it would resolve links with
# .NET's Uri, whose escaping differs from urllib's exactly where this check
# looks (`%2C`). It is run by the runtime's own Python, which the preflight
# has already required. What it asks of each host is in verify-deploy.sh's
# comment above check_page_links and in contracts/shared-rules.json ->
# netlifyPageAddresses.
#
# Output goes through a FILE: Windows PowerShell 5.1 reads a child's stdout
# through $OutputEncoding, which is ASCII, and the program prints link text.
$script:PageLinksProgram = $null
function Get-PageLinksProgram {
    if ($script:PageLinksProgram) { return $script:PageLinksProgram }
    $sh = Get-Content -LiteralPath (Join-Path $PSScriptRoot "verify-deploy.sh") -Raw -Encoding UTF8
    # Anchored to the function: from its opening line, through lines that
    # are not its closing `}` at column 0, to its OWN heredoc - so a reshaped
    # function cannot make this pick up the next <<'PY' in the file.
    $found = [regex]::Match(($sh -replace "`r", ""), "(?m)^check_page_links\(\) \{[^\n]*\n(?:(?!\}\n)[^\n]*\n)*?[^\n]*<<'PY'\n((?:(?!PY\n)[^\n]*\n)*?)PY\n")
    if (-not $found.Success) { return $null }
    $path = Join-Path $work "check_page_links.py"
    [IO.File]::WriteAllText($path, $found.Groups[1].Value + "`n", (New-Object System.Text.UTF8Encoding($false)))
    $script:PageLinksProgram = $path
    return $path
}
function Check-PageLinks([string]$What, [string]$Base, [string]$Kind) {
    $program = Get-PageLinksProgram
    if (-not $program) { No "$What's page links could not be checked: check_page_links's program was not found in verify-deploy.sh"; return }
    $out = Join-Path $work ("page-links-" + [Guid]::NewGuid().ToString('N').Substring(0,6) + ".txt")
    $err = "$out.err"
    $env:PYTHONUTF8 = '1'; $env:PYTHONIOENCODING = 'utf-8'
    try {
        $p = Start-Process -FilePath $script:RuntimePython -ArgumentList @('-X', 'utf8', '-I', ('"' + $program + '"'), ('"' + $Base + '"'), $Kind) `
                           -NoNewWindow -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    } finally { Remove-Item Env:PYTHONUTF8, Env:PYTHONIOENCODING -ErrorAction SilentlyContinue }
    $said = if (Test-Path -LiteralPath $out) { @(Get-Content -LiteralPath $out -Encoding UTF8) } else { @() }
    $summary = ($said | Where-Object { $_ -like 'SUMMARY *' } | Select-Object -First 1)
    if ($p.ExitCode -ne 0 -or -not $summary) {
        $why = if (Test-Path -LiteralPath $err) { (Get-Content -LiteralPath $err -Raw -Encoding UTF8) } else { "" }
        No "$What's page links could not be checked (exit $($p.ExitCode)) $why"
        return
    }
    $problems = @($said | Where-Object { $_ -like 'PROBLEM *' })
    if ($problems.Count -gt 0) {
        No "$What's page links: $($summary.Substring(8))"
        foreach ($problem in $problems) { Write-Host "         $($problem.Substring(8))" -ForegroundColor Red }
    } else { Ok "$What's page links: $($summary.Substring(8))" }
}

# A folder publish is sent the build's bytes: no marker, links as built. Run
# on all three folder legs here (the mac runs it on two), so it is a superset.
function Check-NoMarkerFolder([string]$What, [string]$Site) {
    $marked = @(Get-ChildItem -LiteralPath $Site -Recurse -File -ErrorAction SilentlyContinue |
                Select-String -Pattern 'data-plantoir-paths' -SimpleMatch -List | Select-Object -First 1)
    if ($marked.Count -gt 0) { No "$What carries data-plantoir-paths, which only a Netlify publish adds (#628)" }
    else { Ok "$What carries the build's links as built, with no Netlify marker (#628)" }
}

# The build's own half of #628 reached a Windows-built site: the router, the
# link previews and the search previews each follow the marker, so the built
# postscript.js names plantoirPaths exactly three times
# (build_site._wire_served_case, which only WARNS when an anchor has moved -
# so this is the one place a moved anchor fails anything). Read from a folder
# publish because the build keeps no scaffold to inspect.
function Check-ServedCase([string]$What, [string]$Site) {
    $script = Join-Path $Site "postscript.js"
    if (-not (Test-Path -LiteralPath $script)) { No "$What has no postscript.js"; return }
    $count = [regex]::Matches((Get-Content -LiteralPath $script -Raw -Encoding UTF8), 'plantoirPaths').Count
    if ($count -eq 3) { Ok "$What's postscript.js follows the Netlify marker in all three places (plantoirPaths x3)" }
    else { No "$What's postscript.js names plantoirPaths $count time(s), not 3 - an anchor in _wire_served_case moved" }
}

# Cloudflare's production address serves the NEW deployment only after it
# has propagated (#630's second comment): at the 1.8.5 cut a single
# Cloudflare leg was judged while production still served the deployment
# before it, eight checks failed, and two minutes later all of them passed.
# Wait for production's front page to be byte for byte the index.html this
# leg uploaded (the folder deploy.py names in "Deploying from local build:"),
# for at most 120 s. Not reaching it is a FAILURE - the run then judges what
# production is serving, and says so - never a skip.
function Wait-CloudflareProduction([string]$What, [string]$Log, [string]$Url) {
    $built = [regex]::Match($Log, '(?m)Deploying from local build: (.+?)\s*$')
    if (-not $built.Success) { No "$What - no 'Deploying from local build:' line, so what was uploaded is unknown"; return }
    $index = Join-Path $built.Groups[1].Value "index.html"
    if (-not (Test-Path -LiteralPath $index)) { No "$What - the uploaded build has no index.html at $index"; return }
    $want = (Get-FileHash -LiteralPath $index).Hash
    $fetched = Join-Path $work "cf-front-page.html"
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while ($clock.Elapsed.TotalSeconds -lt 120) {
        Remove-Item -LiteralPath $fetched -ErrorAction SilentlyContinue
        & $script:Curl -s -L --max-time 20 -H "Cache-Control: no-cache" -o $fetched "$($Url.TrimEnd('/'))/" 2>$null
        if ((Test-Path -LiteralPath $fetched) -and (Get-FileHash -LiteralPath $fetched).Hash -eq $want) {
            Ok "$What - production serves this deployment's front page (after $([int]$clock.Elapsed.TotalSeconds) s)"
            return
        }
        Start-Sleep -Seconds 5
    }
    No "$What - production did not serve this deployment's front page within 120 s; judging what it does serve"
}

# Every address a publish answered at, for the Result block: a FIRST-publish
# run creates them, and nothing deletes them.
$script:SitesUsed = @()
function Note-Site([string]$Url) { if ($Url -and $script:SitesUsed -notcontains $Url) { $script:SitesUsed += $Url } }

# Which host a published address belongs to. A publish is only proved by an
# address of the RIGHT KIND: the first version of this script checked a
# netlify.app URL and called it a Cloudflare pass.
function Expected-Host([string]$destination) {
    if ($destination -eq 'cloudflare_pages') { return 'pages.dev' }
    return 'netlify.app'
}

function Check-Url {
    param([string]$What, [string]$Url, [int]$Attempts = 12, [string]$MustEndWith = "")
    # A site created moments ago does not answer immediately - the first run of
    # this script reported a 404 for a Netlify site that answered 200 a few
    # minutes later in the very next case. A publish is not wrong because DNS
    # is slow, so this waits rather than judging on the first try.
    $response = $null
    foreach ($attempt in 1..$Attempts) {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 60
            if ($response.StatusCode -eq 200) { break }
        } catch { $response = $null }
        if ($attempt -lt $Attempts) { Start-Sleep -Seconds 20 }
    }
    try {
        if ($null -eq $response) { No "$What could not be fetched after $Attempts tries"; return }
        if ($response.StatusCode -ne 200) { No "$What answered HTTP $($response.StatusCode)"; return }
        # The address must belong to the host this case is about. Without this,
        # a leg that silently published somewhere ELSE passes: the Cloudflare
        # cases did exactly that, verifying a netlify.app address three times
        # over and reporting three green Cloudflare publishes.
        if ($MustEndWith -and -not ($Url -match ([regex]::Escape($MustEndWith) + '(/|$)'))) {
            No "$What answered, but at $Url - that is not a $MustEndWith address, so this destination did not publish"
            return
        }
        Ok "$What answered HTTP 200"
        if ($response.Content -match 'ws://localhost:') { No "$What is serving the preview's live-reload client" }
        else { Ok "$What carries no live-reload client" }
    } catch { No "$What could not be fetched: $($_.Exception.Message)" }
}

function Url-FromLog([string]$log) {
    # PREFER the production address over a deployment-specific one. Cloudflare
    # prints both - "https://21a7e1ae.mcr3u-....pages.dev" for that particular
    # deployment and "https://mcr3u-....pages.dev" for the site itself - and
    # taking the first match took the hashed one. On a project's FIRST publish
    # that subdomain needs longer to resolve than the site does, so a real,
    # successful publish was reported as "could not be fetched after 6 tries"
    # while the site itself was already serving. It is also simply the wrong
    # thing to check: the production address is the one a teacher gives out.
    $all = [regex]::Matches($log, 'https://[^\s""]+\.(?:netlify\.app|pages\.dev)') |
           ForEach-Object { $_.Value } | Select-Object -Unique
    if (-not $all) { return "" }
    $plain = $all | Where-Object {
        $hostName = ([Uri]$_).Host
        # A deployment-specific Cloudflare address has one extra label in front
        # of the project name: <hash>.<project>.pages.dev is four labels,
        # <project>.pages.dev is three.
        -not ($hostName -like "*.pages.dev" -and ($hostName.Split(".").Count -gt 3))
    }
    if ($plain) { return @($plain)[0] }
    return @($all)[0]
}

# ------------------------------------------- runnable code and KaTeX (#455)
# The Windows counterpart of verify-deploy.sh's check_engine and
# check_engine_folder (#568): every host must send the engine's files with
# types a browser will run - .wasm as application/wasm
# (WebAssembly.instantiateStreaming refuses anything else), .mjs and the
# workers as JavaScript - and any CSP it sends must let wasm compile
# ('unsafe-eval' or 'wasm-unsafe-eval'); KaTeX's stylesheet and a face come
# back from the site itself, and no CSP names the CDN. The page of runnable
# code is isolated (COOP + COEP), the engine folders carry COEP, and the
# front page carries neither (contracts/shared-rules.json ->
# codeRunnerBlocks.loading, .isolation). curl.exe by full path, as the mac
# uses curl: Invoke-WebRequest under 5.1 follows redirects without saying
# which headers were the last response's.
$script:Curl = Join-Path $env:SystemRoot "System32\curl.exe"
$script:Measured = @()
$script:ContractsDir = Join-Path $PSScriptRoot "contracts"

# The LAST response's status and headers (after any redirects when -Follow),
# names lower-cased.
function Get-Response([string]$Url, [switch]$Follow, [string]$SaveTo = "NUL") {
    $arguments = @('-s', '-D', '-', '-o', $SaveTo, '--max-time', '30')
    if ($Follow) { $arguments += '-L' }
    $raw = (& $script:Curl @arguments $Url 2>$null) -join "`n"
    $blocks = @(($raw -replace "`r", "") -split "`n`n" | Where-Object { $_ -match '^HTTP/' })
    $result = @{ Code = 0; Headers = @{} }
    if ($blocks.Count -eq 0) { return $result }
    $lines = $blocks[-1] -split "`n"
    if ($lines[0] -match '^HTTP/\S+\s+(\d{3})') { $result.Code = [int]$Matches[1] }
    foreach ($line in $lines | Select-Object -Skip 1) {
        if ($line -match '^([^:]+):\s*(.*)$') { $result.Headers[$Matches[1].ToLowerInvariant()] = $Matches[2] }
    }
    return $result
}

function Check-Engine([string]$What, [string]$Base) {
    foreach ($name in @('pyodide.asm.wasm', 'pyodide.asm.mjs', 'pyodide.mjs', 'plantoir-worker.js', 'python_stdlib.zip', 'pyodide-lock.json')) {
        $r = Get-Response "${Base}static/pyodide/$name"
        $type = ([string]$r.Headers['content-type']).ToLowerInvariant()
        $want = if ($name -like '*.wasm') { 'application/wasm' } elseif ($name -like '*.mjs' -or $name -like '*.js') { 'javascript' } else { '' }
        if ($r.Code -ne 200) { No "$What answered HTTP $($r.Code) for static/pyodide/$name" }
        elseif ($want -and -not $type.Contains($want)) { No "$What sends static/pyodide/$name as '$type', which a browser will not run as $want" }
        else { Ok "$What sends static/pyodide/$name (HTTP 200, $type)" }
    }
    $csp = [string](Get-Response "${Base}static/pyodide/plantoir-worker.js").Headers['content-security-policy']
    if (-not $csp -or $csp -match "'(unsafe-eval|wasm-unsafe-eval)'") { Ok "$What's worker may compile WebAssembly ($(if ($csp) { 'CSP allows it' } else { 'no CSP' }))" }
    else { No "$What's worker CSP allows no wasm: $csp" }

    # Hosts answer the .html address with a redirect to the pretty one
    # (Netlify 301, Cloudflare 308), so the page is fetched following it.
    $pageFile = Join-Path $work "runner-page.html"
    $r = Get-Response "${Base}Runner-Deploy-Check" -Follow -SaveTo $pageFile
    $html = if (Test-Path $pageFile) { Get-Content -LiteralPath $pageFile -Raw -Encoding UTF8 } else { "" }
    if ($r.Code -eq 200 -and $html -match 'class="plantoir-runner"') { Ok "$What's page of runnable code carries its runnable block" }
    else { No "$What's page of runnable code answered HTTP $($r.Code) or carries no runnable block" }

    # Runnable Swift (#493, #570): the thread and its WASI shim, and the
    # page's compiled program, checked as verify-deploy.sh checks them.
    foreach ($name in @('plantoir-swift-worker.js', 'plantoir-wasi.mjs')) {
        $r = Get-Response "${Base}static/swift/$name"
        $type = ([string]$r.Headers['content-type']).ToLowerInvariant()
        if ($r.Code -eq 200 -and $type.Contains('javascript')) { Ok "$What sends static/swift/$name (HTTP 200, $type)" }
        else { No "$What answered HTTP $($r.Code), '$type' for static/swift/$name (a module worker needs JavaScript)" }
    }
    $program = [regex]::Match($html, 'data-runner-wasm="(static/swift-wasm/[0-9a-f]{64}\.wasm)"')
    if (-not $program.Success) { No "$What's page of runnable code carries no Swift program" }
    else {
        $programFile = Join-Path $work "program.wasm"
        $r = Get-Response "${Base}$($program.Groups[1].Value)" -SaveTo $programFile
        $head = if (Test-Path -LiteralPath $programFile) { [IO.File]::ReadAllBytes($programFile) | Select-Object -First 4 } else { @() }
        if ($r.Code -eq 200 -and (($head | ForEach-Object { $_.ToString('x2') }) -join '') -eq '0061736d') {
            Ok "$What sends the page's Swift program (HTTP 200, $([string]$r.Headers['content-type']), $((Get-Item -LiteralPath $programFile).Length) bytes)"
        } else { No "$What answered HTTP $($r.Code) for $($program.Groups[1].Value), or not a WebAssembly program" }
    }

    # Live input (#583), following the host's redirect (Netlify answers an
    # address with capitals with a 301 to its lower-case form).
    $r = Get-Response "${Base}Runner-Deploy-Check" -Follow
    if ($r.Headers['cross-origin-opener-policy'] -match '^same-origin' -and $r.Headers['cross-origin-embedder-policy'] -match '^require-corp') {
        Ok "$What isolates the page of runnable code (COOP same-origin, COEP require-corp), so it asks for input as it runs"
    } else { No "$What does not send COOP and COEP on the page of runnable code, so it keeps the input box" }
    if ($r.Headers['content-security-policy'] -match 'jsdelivr') { No "$What's CSP still names cdn.jsdelivr.net" }
    else { Ok "$What's CSP names no CDN for the maths" }
    foreach ($name in @('pyodide/pyodide.mjs', 'pyodide/plantoir-worker.js', 'swift/plantoir-wasi.mjs', 'swift/plantoir-swift-worker.js')) {
        $r = Get-Response "${Base}static/$name"
        if ($r.Headers['cross-origin-embedder-policy'] -match '^require-corp') { Ok "$What sends COEP on static/$name" }
        else { No "$What sends no COEP on static/$name, which an isolated page's worker needs" }
    }
    $r = Get-Response $Base -Follow
    if ($r.Headers.ContainsKey('cross-origin-embedder-policy')) { No "$What sends COEP on the front page, which has no runnable code - its frames would break" }
    else { Ok "$What sends no COEP on the front page, which has no runnable code" }

    $r = Get-Response "${Base}static/katex/katex.min.css"
    if ($r.Code -eq 200 -and ([string]$r.Headers['content-type']) -match '^text/css') { Ok "$What serves KaTeX's stylesheet itself (text/css)" }
    else { No "$What does not serve static/katex/katex.min.css as text/css" }
    $r = Get-Response "${Base}static/katex/fonts/KaTeX_Main-Regular.woff2"
    if ($r.Code -eq 200) { Ok "$What serves KaTeX's faces itself" } else { No "$What answered HTTP $($r.Code) for a KaTeX face" }
}

# The pinned engine files, byte for byte, in a folder publish.
function Check-EngineFolder([string]$What, [string]$Site) {
    $pins = @{}
    foreach ($pin in (Get-Content -LiteralPath (Join-Path $script:ContractsDir "toolchain.json") -Raw -Encoding UTF8 | ConvertFrom-Json).pins) { $pins[$pin.pin] = $pin }
    $problems = @()
    foreach ($entry in $pins['pyodide'].files.PSObject.Properties) {
        $path = Join-Path $Site "static\pyodide\$($entry.Name)"
        if (-not (Test-Path -LiteralPath $path) -or (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ne $entry.Value) { $problems += "static/pyodide/$($entry.Name)" }
    }
    foreach ($entry in $pins['katex'].files.PSObject.Properties) {
        $relative = $entry.Name -replace '^dist/', ''
        $path = Join-Path $Site ("static\katex\" + $relative.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $path) -or (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ne $entry.Value) { $problems += "static/katex/$relative" }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $Site "static\pyodide\plantoir-worker.js"))) { $problems += "static/pyodide/plantoir-worker.js" }
    # Swift's thread, as it is in support/gated/swift, and the page's program.
    foreach ($item in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot "support\gated\swift") -File) {
        $copy = Join-Path $Site "static\swift\$($item.Name)"
        if (-not (Test-Path -LiteralPath $copy) -or (Get-FileHash -LiteralPath $copy).Hash -ne (Get-FileHash -LiteralPath $item.FullName).Hash) { $problems += "static/swift/$($item.Name)" }
    }
    if ($problems.Count -eq 0) { Ok "$What carries the pinned Python engine, KaTeX and Swift's thread, byte for byte" }
    else { No "$What lacks or changed: $($problems -join ', ')" }
    $programs = @(Get-ChildItem -LiteralPath (Join-Path $Site "static\swift-wasm") -Filter '*.wasm' -File -ErrorAction SilentlyContinue)
    $notPrograms = @($programs | Where-Object { ((([IO.File]::ReadAllBytes($_.FullName) | Select-Object -First 4) | ForEach-Object { $_.ToString('x2') }) -join '') -ne '0061736d' })
    if ($programs.Count -gt 0 -and $notPrograms.Count -eq 0) { Ok "$What carries the page's Swift program in static/swift-wasm ($($programs.Count))" }
    else { No "$What carries no Swift program in static/swift-wasm, or one that is not a WebAssembly program" }
}

# The borrowed page's Swift fence was made ready to run (#570): the build's
# count says so, and no `plantoir: error:` line or swiftCouldNotBePrepared
# folder problem names it.
function Check-SwiftWasMadeReady([string]$What, [string]$Log) {
    if ($Log -match 'Swift programs? on this site ready to run' -and $Log -notmatch '0 of \d+ Swift program') { Ok "$What made the page's Swift program ready to run" }
    else { No "$What did not make the page's Swift program ready to run" }
    $line = ($Log -split "`r?`n" | Where-Object { $_ -match '^plantoir: error: .*Runner Deploy Check\.md: swift block' } | Select-Object -First 1)
    if ($line) { No "$What said the Swift block is not ready: $line" }
    elseif ($Log -match 'PLANTOIR_HEALTH: \{"name": "swiftCouldNotBePrepared"') { No "$What reported the swiftCouldNotBePrepared folder problem" }
    else { Ok "$What said nothing is wrong with the Swift block" }
}

# How long a publish takes and how many bytes it sends: seconds around the
# launcher, and the SentBytes delta of the interface the default route uses
# (read on a quiet machine, or it counts everything else too).
function Get-SentBytes {
    try {
        # The route Windows actually takes: route metric PLUS interface metric.
        # Sorting on RouteMetric alone picked a Wi-Fi beside a wired adapter on
        # the build PC (both 0) and read a counter that never moved: 0 KiB.
        $alias = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
            Sort-Object { $_.RouteMetric + (Get-NetIPInterface -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4).InterfaceMetric } |
            Select-Object -First 1).InterfaceAlias
        return @{ Alias = $alias; Bytes = [int64](Get-NetAdapterStatistics -Name $alias -ErrorAction Stop).SentBytes }
    } catch { return @{ Alias = '?'; Bytes = [int64]0 } }
}
function Measure-Deploy([string]$Label, [string]$Script, [string[]]$LauncherArgs, [string]$LogFile) {
    $before = Get-SentBytes
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $run = Run-Launcher -Script $Script -LauncherArgs $LauncherArgs -LogFile $LogFile
    $seconds = [int]$clock.Elapsed.TotalSeconds
    $after = Get-SentBytes
    $files = [regex]::Matches([string]$run.Log, 'Netlify requires \d+ file|Uploaded \d+ files \(\d+ already uploaded\)') | Select-Object -Last 1
    $count = if ($files) { $files.Value } else { "no upload count" }
    $script:Measured += "${Label}: $seconds s, $count, $([int](($after.Bytes - $before.Bytes) / 1024)) KiB sent on $($after.Alias)"
    return $run
}

# Everything from here is wrapped so the course's own settings are put back on
# EVERY exit path. It used to rely on `trap`, which does not run on Ctrl+C -
# so interrupting a run left the course pointed at whichever destination the
# script had been testing at the time.
try {

if ($FirstPublish) {
    $hideProblem = Hide-FirstPublishState
    if ($hideProblem) {
        No "FIRST publish: $hideProblem - refusing to publish, and putting back what was moved"
        Restore-FirstPublishState
        $script:ReachedTheEnd = $true
        exit 1
    }
    Ok "FIRST publish: the surname and the section's site records are moved aside; deploy.py will be told '$($script:Surname)'"
}

# --------------------------------------------------- the preview, and the race
Hdr "Preview - serve mode, which is what a teacher actually uses"
# --full-rebuild when the mirror above changed anything: some of build_site's
# edits run only when the Quartz scaffold is first copied, so a section built
# by the folder's previous recipe keeps them until it is rebuilt from scratch
# (#630; the 1.8.5 cut's remedy was deleting the builds folder by hand).
if ($script:MirrorChanged.Count -gt 0) { Ok "the recipe changed, so the preview rebuilds the section from scratch (--full-rebuild)" }
[IO.File]::WriteAllText($runnerPage, ($runnerPageText -replace "`r`n", "`n"), $script:NoBom)
Ok "a page of runnable code borrowed into section $Section (removed on any exit)"
$previewLog = Join-Path $work "preview.log"
$previewProcess = Start-Process -FilePath "cmd.exe" `
    -ArgumentList "/c", ".\preview.bat $Course $Section$(if ($script:MirrorChanged.Count -gt 0) { ' --full-rebuild' }) > `"$previewLog`" 2>&1" `
    -WorkingDirectory $WorkingFolder -PassThru -WindowStyle Hidden
$script:PreviewProcess = $previewProcess

$port = $null
$deadline = (Get-Date).AddMinutes(10)
while ((Get-Date) -lt $deadline -and -not $port) {
    Start-Sleep -Seconds 5
    if (Test-Path $previewLog) {
        $text = Get-Content $previewLog -Raw -ErrorAction SilentlyContinue
        if ($text -match 'available at: http://localhost:(\d+)') { $port = $Matches[1] }
    }
}
if (-not $port) {
    No "the preview never announced an address"
} else {
    Ok "the preview announced port $port"
    $served = $false
    foreach ($i in 1..40) {
        try {
            $r = Invoke-WebRequest "http://localhost:$port/" -UseBasicParsing -TimeoutSec 5
            if ($r.StatusCode -eq 200) { $served = $true; break }
        } catch { }
        Start-Sleep -Seconds 5
    }
    if (-not $served) { No "the preview never answered" }
    else {
        Ok "the preview serves its front page"
        if ($r.Content -match 'ws://localhost') { Ok "the preview carries the live-reload client, as a preview should" }
        else { No "the preview has no live-reload client - serve mode may not be running" }
        # The preview's own server sends the isolation headers by the same
        # rule (build_site._wire_isolation_serve on the section's copy of
        # Quartz's handlers.js, which the native preview runs - #591).
        Check-Engine "the preview" "http://localhost:$port/"
        Check-SwiftWasMadeReady "the preview" (Get-Content -LiteralPath $previewLog -Raw -Encoding UTF8)
    }
}

# Killing the LAUNCHER is what a teacher closing a window does, and it does NOT
# stop the preview: the node server and its Python parent outlive it, and the
# parent's sync watcher goes on mirroring the SERVE build into the section's
# build directory about once a second. The next case publishes into exactly
# that state.
#
# THIS ONE KILL MUST NOT WALK THE TREE, and that is the whole case. It briefly
# used Stop-Tree, which is taskkill /T, and taskkill /T takes the node server
# and the Python down with the launcher - so there was no orphaned preview
# left, nothing for the publish to stop, and the assertion below failed
# claiming the race was back. The harness had quietly stopped reproducing its
# own precondition. Killing ONLY this process is what leaves the preview
# serving, which is the state a teacher is really in.
if ($previewProcess -and -not $previewProcess.HasExited) {
    try { Stop-Process -Id $previewProcess.Id -Force -ErrorAction Stop } catch { }
}
Start-Sleep -Seconds 3

Hdr "Publishing straight after a preview must not ship the live-reload client"
Remove-Item -Recurse -Force $folderTarget -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $folderTarget | Out-Null
Set-Destination -Primary "local_folder" -FolderPath $folderTarget
$afterPreview = Run-Launcher -Script "deploy.bat" -LauncherArgs @($Course, "$Section", "--to-folder", $folderTarget) -LogFile (Join-Path $work "deploy-after-preview.log")
if ($afterPreview.ExitCode -ne 0) { No "publishing after a preview exited $($afterPreview.ExitCode)" }
else { Ok "publishing after a preview exited 0" }
# Asserted, not skipped. A preview WAS left serving above, so if nothing was
# stopped the race is back - and a check that can only pass or be skipped
# proves nothing.
if ($afterPreview.Log -match 'Stopped the preview that was still serving this section') {
    Ok "the rebuild stopped the preview still serving THIS section, so it could not overwrite"
} else {
    No "nothing stopped the preview that was still serving - the race is back"
}
if ($afterPreview.Log -match 'Killed existing process on port') {
    No "a preview was stopped BY PORT, which takes down other sections' previews"
} else {
    Ok "no preview was stopped by port"
}
Check-Folder "folder (after a preview)" (Join-Path $folderTarget "section$Section")
# The publish that REBUILDS (the preview's site is never shipped), so the one
# that says what its build found; the folder publish below reuses that build.
Check-SwiftWasMadeReady "the publish after a preview" $afterPreview.Log

# ----------------------------------------------- each destination on its own
Hdr "Destination 1 of 3 - a folder on this PC"
Remove-Item -Recurse -Force $folderTarget -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $folderTarget | Out-Null
Set-Destination -Primary "local_folder" -FolderPath $folderTarget
$folderRun = Run-Launcher -Script "deploy.bat" -LauncherArgs @($Course, "$Section", "--to-folder", $folderTarget) -LogFile (Join-Path $work "deploy-folder.log")
if ($folderRun.ExitCode -eq 0) { Ok "publish to a folder exited 0" } else { No "publish to a folder exited $($folderRun.ExitCode)" }
Check-Folder "folder" (Join-Path $folderTarget "section$Section")
Check-EngineFolder "the folder" (Join-Path $folderTarget "section$Section")
Check-NoMarkerFolder "the folder" (Join-Path $folderTarget "section$Section")
Check-ServedCase "the folder" (Join-Path $folderTarget "section$Section")

Hdr "Destination 2 of 3 - Netlify"
if ($haveNetlify) {
    Set-Destination -Primary "netlify"
    $netlifyRun = Measure-Deploy "Netlify, first publish with the engine" "deploy.bat" @($Course, "$Section") (Join-Path $work "deploy-netlify.log")
    if ($netlifyRun.ExitCode -eq 0) { Ok "publish to Netlify exited 0" } else { No "publish to Netlify exited $($netlifyRun.ExitCode)" }
    $netlifyUrl = Url-FromLog $netlifyRun.Log
    if ($netlifyUrl) {
        Note-Site $netlifyUrl
        Check-Url "Netlify" $netlifyUrl -MustEndWith "netlify.app"
        Check-Engine "Netlify" "$($netlifyUrl.TrimEnd('/'))/"
        Check-PageLinks "Netlify" "$($netlifyUrl.TrimEnd('/'))/" netlify
    } else { No "no Netlify address in the output" }
} else { Skipped "Netlify (no credentials)" }

Hdr "Destination 3 of 3 - Cloudflare Pages"
if ($haveCloudflare) {
    Set-Destination -Primary "cloudflare_pages"
    # --target is REQUIRED: deploy.ps1 defaults $TARGET to netlify and never
    # reads deploy_target from the configuration. Setting the config key alone
    # published to Netlify while this script reported a Cloudflare pass.
    $cloudflareRun = Measure-Deploy "Cloudflare, first publish with the engine" "deploy.bat" @($Course, "$Section", "--target", "cloudflare") (Join-Path $work "deploy-cloudflare.log")
    if ($cloudflareRun.ExitCode -eq 0) { Ok "publish to Cloudflare exited 0" } else { No "publish to Cloudflare exited $($cloudflareRun.ExitCode)" }
    if ($cloudflareRun.Log -match '(?i)cloudflare|wrangler|pages\.dev') { Ok "the launcher really went to Cloudflare" }
    else { No "the Cloudflare leg's output never mentions Cloudflare - it published somewhere else" }
    $cloudflareUrl = Url-FromLog $cloudflareRun.Log
    if ($cloudflareUrl) {
        Note-Site $cloudflareUrl
        Check-Url "Cloudflare Pages" $cloudflareUrl -MustEndWith "pages.dev"
        Wait-CloudflareProduction "Cloudflare Pages" $cloudflareRun.Log $cloudflareUrl
        Check-Engine "Cloudflare Pages" "$($cloudflareUrl.TrimEnd('/'))/"
        Check-PageLinks "Cloudflare Pages" "$($cloudflareUrl.TrimEnd('/'))/" cloudflare
    } else { No "no Cloudflare address in the output" }
} else { Skipped "Cloudflare Pages (no credentials)" }

# ------------------------------------------------------------- the pairings
# Run as the APP runs them: the primary first, then each additional, one
# launcher call apiece. `additional_deploy_targets` is not handled by the
# launcher at all - the app loops - so this exercises the launcher half the way
# the app drives it. That the app produces exactly these argument lists is a
# separate question, already pinned by app-rules.json -> deployArguments.
Hdr "Pairing 1 of 3 - Netlify primary, a folder also"
if ($haveNetlify) {
    Remove-Item -Recurse -Force $folderTarget -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $folderTarget | Out-Null
    Set-Destination -Primary "netlify" -AdditionalJson "[{`"type`":`"local_folder`",`"folder_path`":`"$($folderTarget.Replace('\','\\'))`"}]"
    $legOne = Run-Launcher -Script "deploy.bat" -LauncherArgs @($Course, "$Section") -LogFile (Join-Path $work "pair1-netlify.log")
    $legTwo = Run-Launcher -Script "deploy.bat" -LauncherArgs @($Course, "$Section", "--to-folder", $folderTarget) -LogFile (Join-Path $work "pair1-folder.log")
    if ($legOne.ExitCode -eq 0 -and $legTwo.ExitCode -eq 0) { Ok "both legs exited 0" }
    else { No "a leg failed (netlify $($legOne.ExitCode), folder $($legTwo.ExitCode))" }
    $u = Url-FromLog $legOne.Log
    if ($u) {
        Note-Site $u
        Check-Url "Netlify (paired)" $u -MustEndWith "netlify.app"
        Check-PageLinks "Netlify (paired with a folder)" "$($u.TrimEnd('/'))/" netlify
    } else { No "no Netlify address in the paired output" }
    Check-Folder "folder (paired)" (Join-Path $folderTarget "section$Section")
    Check-EngineFolder "the folder (paired with Netlify)" (Join-Path $folderTarget "section$Section")
    Check-NoMarkerFolder "the folder (paired with Netlify)" (Join-Path $folderTarget "section$Section")
    Check-ServedCase "the folder (paired with Netlify)" (Join-Path $folderTarget "section$Section")
} else { Skipped "Netlify + folder (no Netlify credentials)" }

Hdr "Pairing 2 of 3 - Cloudflare primary, a folder also"
if ($haveCloudflare) {
    Remove-Item -Recurse -Force $folderTarget -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $folderTarget | Out-Null
    Set-Destination -Primary "cloudflare_pages" -AdditionalJson "[{`"type`":`"local_folder`",`"folder_path`":`"$($folderTarget.Replace('\','\\'))`"}]"
    $legOne = Run-Launcher -Script "deploy.bat" -LauncherArgs @($Course, "$Section", "--target", "cloudflare") -LogFile (Join-Path $work "pair2-cf.log")
    $legTwo = Run-Launcher -Script "deploy.bat" -LauncherArgs @($Course, "$Section", "--to-folder", $folderTarget) -LogFile (Join-Path $work "pair2-folder.log")
    if ($legOne.ExitCode -eq 0 -and $legTwo.ExitCode -eq 0) { Ok "both legs exited 0" }
    else { No "a leg failed (cloudflare $($legOne.ExitCode), folder $($legTwo.ExitCode))" }
    $cfPaired = Url-FromLog $legOne.Log
    if ($cfPaired) {
        Note-Site $cfPaired
        Check-Url "Cloudflare (paired with a folder)" $cfPaired -MustEndWith "pages.dev"
        Wait-CloudflareProduction "Cloudflare (paired with a folder)" $legOne.Log $cfPaired
        Check-PageLinks "Cloudflare (paired with a folder)" "$($cfPaired.TrimEnd('/'))/" cloudflare
    }
    else { No "no Cloudflare address in the paired output" }
    Check-Folder "folder (paired with Cloudflare)" (Join-Path $folderTarget "section$Section")
    Check-EngineFolder "the folder (paired with Cloudflare)" (Join-Path $folderTarget "section$Section")
    Check-NoMarkerFolder "the folder (paired with Cloudflare)" (Join-Path $folderTarget "section$Section")
    Check-ServedCase "the folder (paired with Cloudflare)" (Join-Path $folderTarget "section$Section")
} else { Skipped "Cloudflare + folder (no Cloudflare credentials)" }

Hdr "Pairing 3 of 3 - Netlify primary, Cloudflare also"
if ($haveNetlify -and $haveCloudflare) {
    Set-Destination -Primary "netlify" -AdditionalJson '[{"type":"cloudflare_pages"}]'
    $legOne = Measure-Deploy "Netlify, second publish" "deploy.bat" @($Course, "$Section") (Join-Path $work "pair3-netlify.log")
    Set-Destination -Primary "cloudflare_pages"
    $legTwo = Measure-Deploy "Cloudflare, second publish" "deploy.bat" @($Course, "$Section", "--target", "cloudflare") (Join-Path $work "pair3-cf.log")
    if ($legOne.ExitCode -eq 0 -and $legTwo.ExitCode -eq 0) { Ok "both legs exited 0" }
    else { No "a leg failed (netlify $($legOne.ExitCode), cloudflare $($legTwo.ExitCode))" }
    $u1 = Url-FromLog $legOne.Log
    if ($u1) {
        Note-Site $u1
        Check-Url "Netlify (paired with Cloudflare)" $u1 -MustEndWith "netlify.app"
        Check-Engine "Netlify (paired with Cloudflare)" "$($u1.TrimEnd('/'))/"
        Check-PageLinks "Netlify (paired with Cloudflare)" "$($u1.TrimEnd('/'))/" netlify
    } else { No "no Netlify address in the paired output" }
    $u2 = Url-FromLog $legTwo.Log
    if ($u2) {
        Note-Site $u2
        Check-Url "Cloudflare (paired with Netlify)" $u2 -MustEndWith "pages.dev"
        Wait-CloudflareProduction "Cloudflare (paired with Netlify)" $legTwo.Log $u2
        Check-Engine "Cloudflare (paired with Netlify)" "$($u2.TrimEnd('/'))/"
        Check-PageLinks "Cloudflare (paired with Netlify)" "$($u2.TrimEnd('/'))/" cloudflare
    } else { No "no Cloudflare address in the paired output" }
} else { Skipped "Netlify + Cloudflare (needs both sets of credentials)" }

# ------------------------------------------------------------------ finishing
$script:ReachedTheEnd = $true
# Put a first publish's surname and records back BEFORE the Result block, so
# the names of the sites it made can be listed in it. The finally below does
# it again, harmlessly, on every other exit path.
Restore-FirstPublishState
Hdr "Result"
Write-Host "  $($script:Pass) passed, $($script:Fail) failed, $($script:Skip) skipped"
if ($script:Measured.Count -gt 0) {
    Write-Host ""
    Write-Host "  Publishing a site that carries the Python engine (#455), measured:"
    foreach ($line in $script:Measured) { Write-Host "    $line" }
}
Write-Host "  recipe: this checkout at $($script:Commit)$(if ($script:Dirty -gt 0) { " with $($script:Dirty) uncommitted change(s)" } else { ', clean' }); $($script:MirrorChanged.Count) file(s) mirrored into the folder"
Write-Host "  runtime: $($script:Runtime)"
if ($script:SitesUsed.Count -gt 0) {
    Write-Host "  published to$(if ($FirstPublish) { ' (CREATED by this first-publish run; nothing deletes them)' }):"
    foreach ($site in $script:SitesUsed) { Write-Host "    $site" }
}
foreach ($site in $script:SitesWritten) { Write-Host "    record removed from the course: $site" }
Write-Host "  logs: $work"
if ($script:Fail -gt 0) {
    Write-Host "  Failures:" -ForegroundColor Red
    foreach ($f in $script:Failures) { Write-Host "    - $f" -ForegroundColor Red }
    exit 1
}
exit 0

}
finally {
    Restore-FirstPublishState
    Restore-Config
    Stop-AnyPreview
    Remove-RunnerPage

    # DID THIS RUN ACTUALLY FINISH? Measured the hard way: a PowerShell error
    # inside Run-Launcher ended the run after four checks, printed no Result
    # block at all, and the process still exited 0 - because a script that
    # stops without an explicit `exit` exits 0, whatever went wrong on the way.
    # Anything reading the exit code, a person or a release checklist, would
    # have been told the publishing path was verified when nine tenths of it
    # never ran.
    if (-not $script:ReachedTheEnd) {
        Write-Host ""
        Write-Host "THIS RUN DID NOT FINISH - it stopped before the Result block." -ForegroundColor Red
        Write-Host "Whatever it printed above, the publishing path is NOT verified." -ForegroundColor Red
        exit 1
    }
}
