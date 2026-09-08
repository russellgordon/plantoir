<#
.SYNOPSIS
    Run the Windows gate and say what actually happened.

.DESCRIPTION
    WHAT THIS IS, AND WHAT IT IS NOT
    ================================
    `dotnet test Plantoir.Tests/Plantoir.Tests.csproj` is still the gate and
    still correct to type. This runs exactly that and adds one thing on the
    end: an honest reading of what came back.

    So this is a CONVENIENCE, not a new gate, and nothing depends on it. If you
    type the raw command instead you lose nothing except the summary — but then
    read "WHAT TO LOOK FOR" below, because the distinction it draws is real
    whether or not a script draws it for you.

    WHY IT EXISTS
    =============
    `dotnet test` exits 1 when a test fails. It also exits 1 when the test HOST
    dies underneath the run, and when the project failed to compile. Three
    different events, three different responses, one exit code.

    The middle one is the expensive one. On the mac the same blindness rejected
    3 of 7 pieces of correct work in a single overnight batch, and was raised in
    `TODO.md` twice, a fortnight apart, before anybody noticed the two entries
    were one defect (`GUI-IMPROVEMENTS.md` row 444). What makes it expensive is
    that it does not look like an infrastructure problem: a test is NAMED, so
    the name gets investigated, and re-running it passes, so it gets filed as
    flaky.

    WHAT TO LOOK FOR, IF YOU TYPE THE RAW COMMAND
    =============================================
    Measured 2026-09-08 on this machine by putting each failure in deliberately
    (Lenovo 20QES70500, Intel Core i5-8365U @ 1.60 GHz, 16 GB; Windows 11 Pro
    26200, .NET 9 SDK, xunit 2.9.2, Microsoft.NET.Test.Sdk 17.12.0):

      A failing test ends with a totals line -
        "Failed!  - Failed: 1, Passed: 0, Skipped: 0, Total: 1, Duration: 17 ms"

      A DEAD HOST has no totals line at all, and says so twice -
        "The active test run was aborted. Reason: Test host process crashed"
        "Test Run Aborted."

    Both are exit code 1. **The totals line is the honest signal; the exit code
    is not.** If it is absent, the test named above it is a bystander.

    `--blame` names the bystander properly: it writes a Sequence_<guid>.xml
    under TestResults\ saying which test was running when the host died. That
    is the cheap flag. `--blame-crash` additionally writes a full process dump,
    which is tens to hundreds of megabytes — worth it once you are actually
    hunting one, not by default. Both paths are gitignored.

    WHAT IS AND IS NOT KNOWN TO CRASH HERE
    ======================================
    Nothing on this side has ever been seen to. `Plantoir.Tests` hosts no
    window — the mac's crash needed a real NSAlert torn down inside a layout
    pass, and there is no WinUI equivalent — and `Plantoir.UiTests` drives the
    app OUT of process, so the app dying is an assertion failure rather than a
    host death (measured; see `documentation/12-windows-app.md`). This exists so
    that if one ever does happen it is read correctly the first time, rather
    than costing what it cost the mac.

.EXAMPLE
    .\run-tests.ps1
.EXAMPLE
    .\run-tests.ps1 -Filter "FullyQualifiedName~SiteHealth"
.EXAMPLE
    .\run-tests.ps1 -Blame
    # Adds --blame, so a dead host names the test that was running.
#>
[CmdletBinding()]
param(
    [string]$Filter = "",
    [switch]$Blame
)

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot

$project = "$repo\windows-app\Plantoir.Tests\Plantoir.Tests.csproj"
$dotnetArgs = @("test", $project, "--nologo")
if ($Filter) { $dotnetArgs += @("--filter", $Filter) }
if ($Blame)  { $dotnetArgs += "--blame" }

# Captured as well as shown. `2>&1` is required — the crash banner goes to
# stderr, so capturing stdout alone keeps the live output and silently loses
# the one marker this exists to find. And `2>&1` on a native command is a
# TERMINATING error while $ErrorActionPreference is 'Stop', so the preference
# is lowered around the call and put straight back.
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    # Flattened to plain strings, then Tee'd. Both halves earn their place:
    # `"$_"` turns the ErrorRecord that `2>&1` produces back into the line the
    # tool actually wrote (PowerShell 5.1 otherwise renders each stderr line as
    # a multi-line NativeCommandError blob with CategoryInfo and
    # FullyQualifiedErrorId, which buries the banner it is here to surface);
    # and Tee-Object leaves them on the SUCCESS stream, so the run still shows
    # live AND a caller redirecting this script to a file gets the transcript.
    # Write-Host would have been simpler and captures to nothing.
    & dotnet @dotnetArgs 2>&1 | ForEach-Object { "$_" } | Tee-Object -Variable teed
    $code = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $previousPreference
}
$captured = ($teed | Out-String)

. "$repo\windows-app\TestRunOutcome.ps1"
$outcome = Get-TestRunOutcome -Output $captured -ExitCode $code

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
    Write-Host "A suite that ran nothing is not a suite that passed. Check the filter, and" -ForegroundColor Red
    Write-Host "check that python is on PATH - PythonToolchainTests FAILS rather than skips" -ForegroundColor Red
    Write-Host "without one, deliberately, so this should be reachable only by a bad filter." -ForegroundColor Red
}

# 2 and 3, not 1, so a caller can tell a dead host and an empty run from a red
# suite without parsing anything. Everything else keeps dotnet's own code.
if ($outcome.Verdict -eq 'HostCrash')  { exit 2 }
if ($outcome.Verdict -eq 'RanNothing') { exit 3 }
exit $code
