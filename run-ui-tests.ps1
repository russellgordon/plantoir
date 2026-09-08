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
    bottom, that the sheet follows the course a teacher selected rather than
    going stale, and that a sentence the contract pins is actually RENDERED
    where a teacher can see it rather than merely held in a constant.

    They do NOT judge anything visual — colour, contrast, dark-mode
    legibility, how a long name wraps. That is a screenshot pass, not this.

    NOTHING OF YOURS IS TOUCHED
    ===========================
    The app is launched with `--state-dir`, which moves its ENTIRE Plantoir
    folder - settings, the breadcrumb trail, the startup log, scheduled-deploy
    sentinels, models, built sites - to a temporary folder deleted afterwards;
    the working folder is built from scratch. Your own working folder,
    remembered windows and window positions are not read or written.

    The exception worth knowing: the LAUNCHERS compute the builds root
    themselves. ONE test runs one — NewCourseWizardUiTests presses the wizard's
    Create button, which runs setup.ps1 — and it is safe only because
    setup_course.py never resolves merged_output_root, so PLANTOIR_BUILD_ROOT
    is set and the folder it names is never made. Nothing enforces that. Do not
    write a test that previews or schedules without reading "The flags the app
    answers" in documentation/12-windows-app.md first.

    WHEN ONE FAILS
    ==============
    Set PLANTOIR_UI_KEEP=1 and run it again. A test that fails INSIDE the app
    has almost nothing to say from outside it, and the evidence that matters -
    that run's own startup.log, its breadcrumb trail, its per-run launcher log
    under Logs\runs, and its working folder - is all in the temporary folder
    normally deleted on the way out. With the switch set, the folder is kept
    and this script prints where it is.

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
.EXAMPLE
    $env:PLANTOIR_UI_KEEP = 1; .\run-ui-tests.ps1 -Filter "FullyQualifiedName~TheCreateButton"
    # Keeps the run's state folder and working folder so a failure can be read.
#>
[CmdletBinding()]
param(
    [string]$Filter = "",
    [switch]$Blame
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
# A token for THIS run, folded into every temporary folder DrivenApp makes, so
# the sweep at the end can match this run's own children and nothing else.
$env:PLANTOIR_UI_RUN = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$dotnetArgs = @("test", "$repo\windows-app\Plantoir.UiTests\Plantoir.UiTests.csproj", "-c", "Debug", "-p:Platform=x64", "--nologo")
if ($Filter) { $dotnetArgs += @("--filter", $Filter) }
# --blame writes TestResults\<guid>\<guid>_Sequence.xml naming the test that
# was running when a host died - that way round, checked against `dotnet test
# --help`. Cheap; --blame-crash would add a full dump and is not wired here.
if ($Blame) { $dotnetArgs += "--blame" }

Write-Host "Driving the interface..." -ForegroundColor Cyan

. "$repo\windows-app\TestRunOutcome.ps1"

# The capture is the subtle half - stderr, the preference juggling, flattening
# the ErrorRecord - so it is SHARED rather than copied into each runner.
# Invoke-TestRun's own comment carries the three details and what each one
# cost; the untracked batch driver had the first of them wrong, so it could not
# have seen the banner even had it been looking - which is the argument against
# keeping three copies of this.
#
# The tidying up is in a FINALLY, and not for tidiness. `& dotnet` throws
# CommandNotFoundException if dotnet is not on PATH - terminating even at
# 'Continue' - and before this that escaped past everything below, leaving
# PLANTOIR_UI_TESTS set in the caller's own session and the orphan sweep
# unrun.
$run = $null
try {
    Invoke-TestRun -DotnetArguments $dotnetArgs -Result ([ref]$run)
} finally {
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
    # Matched on THIS RUN's token, not on the suite's folder prefix. Matching the
    # prefix was the first version and it is too wide: two runs at once would kill
    # each other's live launchers, and a developer reading a kept folder (`Get-
    # Content ...\plantoir-ui-*\state\Logs\startup.log -Wait`) has that pattern in
    # their own command line and would be force-killed by a run finishing beside
    # them. The pid and folder are printed rather than a count, because a
    # force-kill that says only "1 process" is the kind of thing that gets
    # distrusted later.
    #
    # Guarded rather than assumed: with an empty token the pattern collapses back
    # to the folder PREFIX and sweeps every run on the machine, which is the exact
    # thing this rework exists to stop. An unset token means the sweep cannot know
    # what is its own, so it does nothing.
    $orphans = @()
    if ([string]::IsNullOrWhiteSpace($env:PLANTOIR_UI_RUN)) {
        Write-Host "No run token, so no orphan sweep - kill any leftover launcher by hand." -ForegroundColor Yellow
    } else {
        $orphans = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='python.exe'" -ErrorAction SilentlyContinue |
                     Where-Object { $_.CommandLine -match ("plantoir-ui-" + $env:PLANTOIR_UI_RUN) })
    }
    foreach ($o in $orphans) {
        Write-Host "Cleaning up a launcher this run left behind: $($o.Name) pid $($o.ProcessId)." -ForegroundColor Yellow
        Stop-Process -Id $o.ProcessId -Force -ErrorAction SilentlyContinue
    }

    # Where the evidence is, when there is any. DrivenApp says this too, but plain
    # Console output from Dispose is not attached to a test result and often does
    # not surface in `dotnet test`, so the reliable notice is here.
    $kept = @(Get-ChildItem $env:TEMP -Directory -Filter "plantoir-ui-$($env:PLANTOIR_UI_RUN)-*" -ErrorAction SilentlyContinue)
    foreach ($k in $kept) { Write-Host "Kept this run's files at $($k.FullName)" -ForegroundColor Cyan }
    if ($run -and $run.ExitCode -ne 0 -and $kept.Count -eq 0) {
        Write-Host 'Re-run with $env:PLANTOIR_UI_KEEP = 1 to keep the failed run''s logs and working folder.' -ForegroundColor Yellow
    }
}

# What actually happened, rather than what exit 1 implies. A HOST CRASH is not
# a failing test: the test named in the output is a bystander, and re-running
# it proves nothing - which is the mistake that rejected three of seven pieces
# of correct work on the mac in one night (GUI-IMPROVEMENTS.md row 444).
$outcome = Get-TestRunOutcome -Output $run.Output -ExitCode $run.ExitCode

$colour = switch ($outcome.Verdict) {
    'Passed'    { 'Green' }
    'HostCrash' { 'Magenta' }   # deliberately NOT the red a failing test gets
    default     { 'Red' }
}
Write-Host ""
Write-Host $outcome.Summary -ForegroundColor $colour

if ($outcome.Verdict -eq 'HostCrash') {
    Write-Host "Do not re-run it hoping for green. Count it: how often, and in which class." -ForegroundColor Magenta
    if (-not $Blame) {
        Write-Host "Re-run with -Blame to find out WHICH test was running when the host died." -ForegroundColor Magenta
    }
}
if ($outcome.Verdict -eq 'RanNothing') {
    Write-Host "A suite that ran nothing is not a suite that passed - check the filter." -ForegroundColor Red
    Write-Host "Note that dotnet test exits 0 for a filter that matched nothing." -ForegroundColor Red
}

$env:PLANTOIR_UI_RUN = $null

# Zero only for a genuine pass, and the numbers follow Microsoft.Testing.
# Platform's published meanings where they fit. Get-TestRunExitCode explains
# the whole scheme, including why 2 is avoided even though it looks free.
exit (Get-TestRunExitCode -Verdict $outcome.Verdict -ExitCode $run.ExitCode)
