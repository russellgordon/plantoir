<#
.SYNOPSIS
    Drive the real Plantoir through its interface and check what it renders.

.DESCRIPTION
    WHY THIS IS SEPARATE FROM `dotnet test`
    =======================================
    The ordinary suite is fast, headless and offline, and it must stay that
    way — it is the gate. These tests launch the real built application, put a
    window on screen, click through it and read what UI Automation reports.
    They need a desktop session, an x64 Debug build, and the foreground. So
    they are opt-in and wired into nothing, the same posture `verify-deploy.ps1`
    has for publishing.

    They are still COMPILED by every build: the project is in the solution and
    the tests carry [UiFact], which skips unless PLANTOIR_UI_TESTS=1. A suite
    nothing compiles is a suite that quietly stops matching the code.

    WHAT THEY COVER, AND WHAT THEY DO NOT
    =====================================
    They cover what a unit test cannot see: that a control can be reached, that
    clicking it opens something, that the RENDERED text is what the model said
    in the order the contract fixes, that a scrolling list is not cut off at the
    bottom, and that the sheet follows the course a teacher selected rather than
    going stale. They do NOT judge anything visual — colour, contrast, dark-mode
    legibility, how a long name wraps. That is a screenshot pass, not this.

    NOTHING OF YOURS IS TOUCHED
    ===========================
    The app is launched with `--state-dir`, which moves its ENTIRE Plantoir
    folder - settings, the breadcrumb trail, the startup log, scheduled-deploy
    sentinels, models, built sites - to a temporary folder deleted afterwards;
    the working folder is built from scratch. Your own working folder,
    remembered windows and window positions are not read or written.

    The exception worth knowing: the LAUNCHERS compute the builds root
    themselves, so do not write a test that previews or schedules from a
    redirected run without reading `AppDataRoot` first.

    A RUNNING PLANTOIR IS CLOSED
    ============================
    Two copies would fight over the foreground, and a click meant for the
    sidebar would land in whichever window happened to be in front. Russell's
    standing instruction is to close his copy rather than stop and ask each
    time - it is his development copy and holds no unsaved state of its own -
    so this closes it, and SAYS so rather than doing it quietly. It is not
    reopened afterwards; that part is his.

.EXAMPLE
    .\run-ui-tests.ps1
.EXAMPLE
    .\run-ui-tests.ps1 -Filter "FullyQualifiedName~TheSheetCloses"
#>
[CmdletBinding()]
param(
    [string]$Filter = ""
)

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot

$running = Get-Process -Name Plantoir -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "Closing your running Plantoir (pid $($running.Id -join ', ')) - two copies" -ForegroundColor Yellow
    Write-Host "would fight over the foreground. It is not reopened afterwards." -ForegroundColor Yellow
    $running | Stop-Process -Force
    Start-Sleep -Milliseconds 800
}

# The tests drive the x64 Debug build - the same binary the "PT - Dev"
# shortcut runs, so they exercise what you are about to test by hand.
Write-Host "Building the app (x64 Debug)..." -ForegroundColor Cyan
dotnet build "$repo\windows-app\Plantoir\Plantoir.csproj" -c Debug -p:Platform=x64 --nologo
if ($LASTEXITCODE -ne 0) { Write-Host "The app did not build." -ForegroundColor Red; exit 1 }

$env:PLANTOIR_UI_TESTS = "1"
$dotnetArgs = @("test", "$repo\windows-app\Plantoir.UiTests\Plantoir.UiTests.csproj", "-c", "Debug", "-p:Platform=x64", "--nologo")
if ($Filter) { $dotnetArgs += @("--filter", $Filter) }

Write-Host "Driving the interface..." -ForegroundColor Cyan
& dotnet @dotnetArgs
$code = $LASTEXITCODE

$env:PLANTOIR_UI_TESTS = $null
# A crashed run can leave the app behind; it was ours, so it goes.
Get-Process -Name Plantoir -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# ...and so can a LAUNCHER the app had started. Killing Plantoir.exe kills only
# Plantoir.exe: the whole-tree kill lives in ConPty.Kill(), which runs when the
# APP terminates a task, not when the app is terminated from outside. So a test
# that fails while setup.ps1 is mid-run leaves powershell.exe and python.exe
# alive, holding the temp working folder open - DrivenApp's own
# Directory.Delete then fails silently (it must never turn a passing test red)
# and the folder survives with nothing to say where it came from.
#
# Matched on the command line naming one of THIS suite's temp folders, whose
# names DrivenApp builds as "plantoir-ui-<8 hex>". Nothing of anyone else's can
# match that, which is what makes a force-kill here safe.
$orphans = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='python.exe'" -ErrorAction SilentlyContinue |
             Where-Object { $_.CommandLine -match 'plantoir-ui-[0-9a-f]{8}' })
if ($orphans.Count -gt 0) {
    Write-Host "Cleaning up $($orphans.Count) launcher process(es) left behind by a test run." -ForegroundColor Yellow
    foreach ($o in $orphans) { Stop-Process -Id $o.ProcessId -Force -ErrorAction SilentlyContinue }
}
exit $code
