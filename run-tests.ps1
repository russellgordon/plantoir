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

    `--blame` names it properly: it writes TestResults\<guid>\<guid>_Sequence.xml
    saying which test was running when the host died (the name is that way
    round - checked against `dotnet test --help`, not remembered). That is the
    cheap flag. `--blame-crash` additionally writes a full process dump,
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

. "$repo\windows-app\TestRunOutcome.ps1"

# The capture is the subtle half - stderr, the preference juggling,
# flattening the ErrorRecord - so it is SHARED rather than copied into each
# runner. Invoke-TestRun's own comment carries the three details and what
# each one cost; the untracked batch driver had the first of them wrong, so it
# could not have seen the banner even had it been looking - which is the
# argument against keeping three copies of this.
$run = $null
Invoke-TestRun -DotnetArguments $dotnetArgs -Result ([ref]$run)
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
}

# Zero only for a genuine pass, and the numbers follow Microsoft.Testing.
# Platform's published meanings where they fit. Get-TestRunExitCode explains
# the whole scheme, including why 2 is avoided even though it looks free.
exit (Get-TestRunExitCode -Verdict $outcome.Verdict -ExitCode $run.ExitCode)
