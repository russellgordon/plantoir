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

    THE FIVE VERDICTS
    =================
      Passed      totals present, nothing failed, at least one test ran.
      Failed      totals present, at least one test failed. Ordinary red.
      HostCrash   the run was aborted underneath the tests. The test NAMED in
                  the output is a bystander, and re-running it proves nothing.
      RanNothing  the run finished and nothing actually EXECUTED - either
                  Total is 0, or every test was skipped. Green having run
                  nothing is the failure mode `PythonToolchainTests` was
                  written to close, and it has a second dress here: run
                  `dotnet test Plantoir.UiTests.csproj` directly and all eleven
                  [UiFact] tests skip, which prints "Passed!" and a Total of 11.
                  Counting Total alone would call that a pass. (Not reachable
                  through `run-ui-tests.ps1`, which sets PLANTOIR_UI_TESTS
                  itself - an earlier version of this note said otherwise.)
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

    # A filter that matched nothing. It needs its own marker because vstest
    # prints NO totals line for it and exits ZERO - so without this it lands on
    # NoResult and, worse, on a successful exit code. Measured 2026-09-08:
    # `dotnet test --filter FullyQualifiedName~NoSuchTest` prints
    # "No test matches the given testcase filter ..." at column 0 and exits 0.
    # That is the "green having run nothing" failure this file exists to close,
    # arriving through the one door that was left open.
    $matchedNothing = $Output -match '(?m)^No test matches the given testcase filter'

    # Every totals line, summed. One per test assembly, so a solution-wide run
    # prints several and reading only the first would answer for one project
    # and imply it answered for all of them. Measured on a solution-wide run:
    # one line per assembly and NO grand total, so summing is the right reading.
    #
    # Anchored to the banner at the start of a line - `Passed!  - `, `Failed!  - `
    # or `Skipped! - `, all of which vstest prints unindented - for the same
    # reason the crash markers are, and here the unsafe direction is sharper.
    # A test's assertion MESSAGE is echoed into the run output, indented three
    # spaces (measured; its Console output is not echoed at all). So an
    # unanchored pattern would sum a totals line that a test merely quoted, and
    # the one case that is not conservative is the dangerous one: an
    # all-skipped run plus any echoed text shaped like `Failed: 0, Passed: 3,
    # Skipped: 0, Total: 3` would turn RanNothing into Passed.
    $totals = [regex]::Matches(
        $Output,
        '(?m)^\w+!\s+-\s+Failed:\s*(\d+),\s*Passed:\s*(\d+),\s*Skipped:\s*(\d+),\s*Total:\s*(\d+)')

    $failed = 0; $passed = 0; $skipped = 0; $total = 0
    foreach ($m in $totals) {
        $failed  += [int]$m.Groups[1].Value
        $passed  += [int]$m.Groups[2].Value
        $skipped += [int]$m.Groups[3].Value
        $total   += [int]$m.Groups[4].Value
    }

    if ($crashed) {
        $verdict = 'HostCrash'
        $summary = 'HOST CRASH - the test host died underneath the run. This is ' +
                   'not a failing test, and ANY test named above is a bystander: ' +
                   're-running it proves nothing.'
        if ($totals.Count -gt 0) {
            $summary += " Totals did print for part of the run ($passed passed, $failed failed) " +
                        'and are NOT the answer: the run did not finish.'
        }
    }
    elseif ($matchedNothing) {
        $verdict = 'RanNothing'
        $summary = 'RAN NOTHING - the filter matched no tests, so nothing was run. ' +
                   'Note that dotnet test exits 0 for this, which is why the exit code ' +
                   'cannot be trusted here either.'
    }
    elseif ($totals.Count -eq 0) {
        $verdict = 'NoResult'
        # The wording follows the exit code rather than assuming a build error:
        # "look further up for a build error (exit code 0)" sends the reader
        # hunting for something that is not there.
        $summary = 'NO RESULT - no totals line and no crash banner, so the run never ' +
                   'reached the tests. '
        if ($ExitCode -ne 0) {
            $summary += "Look further up for a build error (exit code $ExitCode)."
        } else {
            $summary += 'It exited 0 having reported nothing, which is not a pass.'
        }
    }
    elseif ($total -eq 0 -or ($passed -eq 0 -and $failed -eq 0)) {
        # Skipped is deliberately NOT counted as having run. See the note above:
        # an opt-in suite whose switch did not take reports every test skipped
        # and a healthy-looking Total, and that is the exact shape of a green
        # that proves nothing.
        $verdict = 'RanNothing'
        $summary = 'RAN NOTHING - the run finished and executed no tests at all ' +
                   "($skipped skipped of $total). An opt-in suite whose switch did not " +
                   'take looks exactly like this, and so does a suite that has stopped ' +
                   'being discovered. (A filter that matched nothing is reported ' +
                   'separately, because vstest words that case differently.)'
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

function Invoke-TestRun {
<#
.SYNOPSIS
    Run `dotnet test` so the output is shown live, captured whole, and readable
    by Get-TestRunOutcome.

.DESCRIPTION
    This exists because the CAPTURE is the subtle half, not the parsing, and it
    was copied into three scripts - one of them the UNTRACKED batch driver,
    which had `2>&1` missing and so could not have seen the banner even had it
    been looking (it judged by the exit code alone). A correction that has to
    land in three places, one of them in no diff anyone reviews, is a
    correction that will land in two.

    Three details, each of which has already cost something:

      * `2>&1` is REQUIRED. The "Test host process crashed" banner goes to
        STDERR. Capturing stdout alone keeps the live output looking perfect
        and silently loses the one marker worth having.

      * `2>&1` on a native command is a TERMINATING error while
        $ErrorActionPreference is 'Stop', which every caller here sets. So it
        is lowered around the call and put straight back.

      * `"$_"` flattens the ErrorRecord that `2>&1` produces back into the line
        the tool actually wrote. Without it, PowerShell 5.1 renders each stderr
        line as a multi-line NativeCommandError blob with CategoryInfo and
        FullyQualifiedErrorId - burying the banner this is here to surface.

    The lines are left on the SUCCESS stream (they flow out of this function to
    the caller's own output) so a run still shows live AND a caller redirecting
    the script to a file gets the transcript. Write-Host would be simpler and
    captures to nothing. The captured text and exit code come back through
    -Result instead, precisely because the success stream is spoken for.

    ONE COUPLING WORTH KNOWING, because removing the flattening would break
    something that looks unrelated. Get-TestRunOutcome anchors its patterns to
    the start of a line, so a wrapped line would stop matching and a green run
    would read as NoResult. `Out-String` wraps FORMATTED OBJECTS to the console
    width - but not plain strings, which it simply joins. Measured 2026-09-08
    at widths 60, 80, 100, 120 and the default against the real 115-character
    totals line: every one gives Passed and 1210, because `"$_"` has already
    made them plain strings. Drop the flattening and ErrorRecords arrive as
    objects, which DO wrap. So do not add `-Width` here to be safe, and do not
    remove the `ForEach-Object` as redundant: it is what makes the width
    irrelevant.

.EXAMPLE
    $run = $null
    Invoke-TestRun -DotnetArguments $args -Result ([ref]$run)
    $outcome = Get-TestRunOutcome -Output $run.Output -ExitCode $run.ExitCode
#>
    [CmdletBinding()]
    param(
        # Everything after `dotnet`, e.g. @("test", $project, "--nologo").
        [Parameter(Mandatory)][string[]]$DotnetArguments,

        # Receives an object with .Output (the whole transcript) and .ExitCode.
        [Parameter(Mandatory)][ref]$Result
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & dotnet @DotnetArguments 2>&1 | ForEach-Object { "$_" } | Tee-Object -Variable teed
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }

    $Result.Value = [pscustomobject]@{
        Output   = ($teed | Out-String)
        ExitCode = $code
    }
}

function Get-TestRunExitCode {
<#
.SYNOPSIS
    The process exit code to report for a verdict.

.DESCRIPTION
    ZERO ONLY FOR A GENUINE PASS. That rule matters more than the individual
    numbers: `dotnet test` exits 0 for a filter that matched no tests, so
    deferring to its exit code let a run that executed nothing report success -
    the exact "green having run nothing" this file exists to close, arriving
    through the one door left open. Measured 2026-09-08.

    The numbers follow Microsoft.Testing.Platform's published meanings where
    they fit, so this stays honest through an xunit v3 / MTP migration:

      0  passed
      1  a test failed (what VSTest gives today)
      3  the session was aborted - here, the test host died
      8  zero tests ran
      4  ours: a run that produced no totals and no banner at all

    **2 is deliberately avoided.** MTP defines it as "at least one test
    failed", so using it for a host crash would invert the single distinction
    this whole file exists to draw, for the one reader most likely to be
    automated.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Verdict,
        [Parameter(Mandatory)][int]$ExitCode
    )

    switch ($Verdict) {
        'Passed'     { 0 }
        'HostCrash'  { 3 }
        'RanNothing' { 8 }
        'NoResult'   { if ($ExitCode -eq 0) { 4 } else { $ExitCode } }
        default      { if ($ExitCode -eq 0) { 1 } else { $ExitCode } }
    }
}
