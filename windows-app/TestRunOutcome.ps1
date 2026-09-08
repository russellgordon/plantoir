<#
.SYNOPSIS
    Read what a `dotnet test` run actually did, rather than what its exit code
    implies.

.DESCRIPTION
    WHY THIS EXISTS
    ===============
    `dotnet test` exits 1 when a test fails. It also exits 1 when the TEST HOST
    dies underneath the run, when the build never got as far as testing, and
    when nothing was found to run. Those are four different events with four
    different responses, and the exit code cannot tell them apart.

    That is not a hypothetical. On the mac the same blindness — `xcodebuild`
    exit 65, a `Failing tests:` line naming whichever test happened to be
    running, and `0 failures` in the totals two lines above — rejected 3 of 7
    pieces of correct work in one overnight batch, and was raised in `TODO.md`
    twice, a fortnight apart, before anybody noticed the two entries were one
    defect (`GUI-IMPROVEMENTS.md` row 444). The lesson that side sent over is
    the one this file implements: **the honest signal is the test TOTALS, never
    the exit code.**

    WHAT A CRASHED HOST LOOKS LIKE HERE, MEASURED
    =============================================
    Measured 2026-09-08 on this machine (Lenovo 20QES70500, Intel Core i5-8365U
    @ 1.60 GHz, 16 GB; Windows 11 Pro 26200, .NET 9 SDK, xunit 2.9.2,
    Microsoft.NET.Test.Sdk 17.12.0) by putting each failure in deliberately and
    reading what came back. Same project, same command, one variable:

      A test host that dies    -> "The active test run was aborted. Reason:
                                   Test host process crashed : ..." and
                                  "Test Run Aborted."
                                  NO totals line at all.        Exit code 1.
      An ordinary assertion    -> "Failed!  - Failed: 1, Passed: 0, Skipped: 0,
                                   Total: 1, Duration: 17 ms"   Exit code 1.

    So the two are identical at the exit code and differ completely in the
    output: a crashed run has no totals line, and says so in two places. That
    asymmetry is the whole basis of this file.

    THE FOUR VERDICTS
    =================
      Passed      totals present, nothing failed, at least one test ran.
      Failed      totals present, at least one test failed. Ordinary red.
      HostCrash   the run was aborted underneath the tests. The test NAMED in
                  the output is a bystander, and re-running it proves nothing.
      RanNothing  the run finished and nothing actually EXECUTED - either
                  Total is 0, or every test was skipped. Green having run
                  nothing is the failure mode `PythonToolchainTests` was
                  written to close, and it has a second dress here: run
                  `run-ui-tests.ps1` with PLANTOIR_UI_TESTS unset and all
                  eleven [UiFact] tests skip, which prints "Passed!" and a
                  Total of 11. Counting Total alone would call that a pass.
      NoResult    neither marker. The build failed, the project was not found,
                  or the run never started.

    HostCrash WINS over any totals that did print. A run with several test
    projects can crash in one and summarise another, and a partial answer to
    "did the suite pass" is not an answer.

    RETRYING IS DELIBERATELY NOT DONE HERE
    ======================================
    The mac's `overnight/run.sh` reports HOST-CRASH and stops, on purpose. A
    crash that is retried until it passes is a crash nobody measures, and the
    mac's was fixed only once somebody counted it (10 in 30 runs before, 0 in
    30 after). This file names what happened and leaves the response to the
    caller.

.EXAMPLE
    . "$PSScriptRoot\windows-app\TestRunOutcome.ps1"
    $out = & dotnet test ... 2>&1 | Out-String
    $verdict = Get-TestRunOutcome -Output $out -ExitCode $LASTEXITCODE
    if ($verdict.Verdict -eq 'HostCrash') { ... }
#>

function Get-TestRunOutcome {
    [CmdletBinding()]
    param(
        # Everything `dotnet test` wrote, stdout and stderr together. Pass it
        # through Out-String first: the markers are whole lines, and an array
        # of objects will not match a line-based regex reliably.
        [Parameter(Mandatory)][AllowEmptyString()][string]$Output,

        # Kept for the record and for NoResult, never used to decide between
        # Failed and HostCrash — that is the whole point.
        [Parameter(Mandatory)][int]$ExitCode
    )

    # Both markers are checked, not just one. "The active test run was aborted"
    # carries the specific reason and is what appears today; "Test Run Aborted."
    # is the general banner and also covers a host killed from OUTSIDE, which
    # gives a different reason and the same banner.
    #
    # ANCHORED TO THE START OF A LINE, and the direction of the risk is why.
    # vstest prints both unindented. A test's own output, a stack frame or an
    # assertion diff quoting one of these sentences is indented or embedded, so
    # anchoring costs nothing and closes a false POSITIVE - which is the
    # dangerous direction: calling a genuinely failing suite a HostCrash hides
    # a real failure behind "not a failing test, do not re-run". A false
    # NEGATIVE is safe by construction: a crashed run prints no totals line, so
    # missing the banner lands on NoResult, which is still neither a pass nor a
    # test failure. Wrong in the harmless direction rather than the harmful one.
    $crashed = $Output -match '(?m)^The active test run was aborted' -or
               $Output -match '(?m)^Test Run Aborted\.'

    # Every totals line, summed. One per test assembly, so a solution-wide run
    # prints several and reading only the first would answer for one project
    # and imply it answered for all of them.
    $totals = [regex]::Matches(
        $Output,
        'Failed:\s*(\d+),\s*Passed:\s*(\d+),\s*Skipped:\s*(\d+),\s*Total:\s*(\d+)')

    $failed = 0; $passed = 0; $skipped = 0; $total = 0
    foreach ($m in $totals) {
        $failed  += [int]$m.Groups[1].Value
        $passed  += [int]$m.Groups[2].Value
        $skipped += [int]$m.Groups[3].Value
        $total   += [int]$m.Groups[4].Value
    }

    if ($crashed) {
        $verdict = 'HostCrash'
        $summary = 'HOST CRASH - the test host died underneath the run, so the ' +
                   'test named above is a bystander and re-running it proves nothing. ' +
                   'This is not a failing test.'
        if ($totals.Count -gt 0) {
            $summary += " Totals did print for part of the run ($passed passed, $failed failed) " +
                        'and are NOT the answer: the run did not finish.'
        }
    }
    elseif ($totals.Count -eq 0) {
        $verdict = 'NoResult'
        $summary = 'NO RESULT - no totals line and no crash banner, so the run never ' +
                   "reached the tests. Look further up for a build error (exit code $ExitCode)."
    }
    elseif ($total -eq 0 -or ($passed -eq 0 -and $failed -eq 0)) {
        # Skipped is deliberately NOT counted as having run. See the note above:
        # an opt-in suite whose switch did not take reports every test skipped
        # and a healthy-looking Total, and that is the exact shape of a green
        # that proves nothing.
        $verdict = 'RanNothing'
        $summary = 'RAN NOTHING - the run finished and executed no tests at all ' +
                   "($skipped skipped of $total). A filter that matches nothing looks " +
                   'exactly like this, so does an opt-in suite whose switch did not take, ' +
                   'and so does a suite that has stopped being discovered.'
    }
    elseif ($failed -gt 0) {
        $verdict = 'Failed'
        $summary = "FAILED - $failed of $total failed ($passed passed, $skipped skipped)."
    }
    else {
        $verdict = 'Passed'
        $summary = "PASSED - $passed passed, $skipped skipped, $total total."
    }

    [pscustomobject]@{
        Verdict  = $verdict
        Failed   = $failed
        Passed   = $passed
        Skipped  = $skipped
        Total    = $total
        ExitCode = $ExitCode
        Summary  = $summary
    }
}
