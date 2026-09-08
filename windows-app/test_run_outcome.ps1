<#
    Checks Get-TestRunOutcome against output `dotnet test` really produced.

    WHY THIS IS A SCRIPT RUN BY THE UNIT SUITE, not a script somebody
    remembers: `TestRunOutcome.ps1` is what decides whether a red run gets
    investigated as a broken test or as a dead host, and a mistake in it is
    silent — it would simply keep saying "FAILED" and everyone would keep
    re-running the bystander. `Plantoir.Tests` runs this file inside
    `dotnet test` (see `TheTestRunReaderTellsACrashFromAFailure`), the same
    arrangement `test_stop_preview.ps1` already has.

    THE FIXTURES ARE REAL. Every string below was captured on 2026-09-08 by
    putting the failure in deliberately and reading what came back — a
    throwaway probe that called Environment.FailFast for the crash, and one
    that failed an assertion for the ordinary case. They are pasted, not
    written from memory, because a fixture invented to match the parser proves
    only that the parser matches itself.

    Run by hand:  powershell -NoProfile -File windows-app\test_run_outcome.ps1
#>

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\TestRunOutcome.ps1"

$failures = 0
$checks = 0

function Check {
    param([string]$What, $Expected, $Actual)
    $script:checks++
    if ($Expected -eq $Actual) {
        Write-Host "  ok   $What"
    } else {
        Write-Host "  FAIL $What - expected '$Expected', got '$Actual'" -ForegroundColor Red
        $script:failures++
    }
}

# --- Captured: a test host that died (Environment.FailFast in a test) --------
# Trimmed of the several hundred stack frames in the middle; the two markers
# and the ABSENCE of a totals line are what matter, and both are verbatim.
$hostCrash = @'
Test run for C:\...\Plantoir.UiTests.dll (.NETCoreApp,Version=v9.0)
A total of 1 test files matched the specified pattern.
The active test run was aborted. Reason: Test host process crashed : Process terminated. PROBE A: deliberate test-host death.
   at System.Environment.FailFast(System.String)
   at Plantoir.UiTests.ZzProbes.ProbeA_KillsTheTestHost()

Test Run Aborted.
'@

# --- Captured: an ordinary failing assertion --------------------------------
$ordinaryFailure = @'
Test run for C:\...\Plantoir.UiTests.dll (.NETCoreApp,Version=v9.0)
  Failed Plantoir.UiTests.ZzProbes.ProbeC_AnOrdinaryFailingAssertion [17 ms]
  Error Message:
   PROBE C: an ordinary failing assertion.

Failed!  - Failed:     1, Passed:     0, Skipped:     0, Total:     1, Duration: 17 ms - Plantoir.UiTests.dll (net9.0)
'@

# --- Captured: a clean run --------------------------------------------------
$clean = @'
Test run for C:\...\Plantoir.Tests.dll (.NETCoreApp,Version=v9.0)

Passed!  - Failed:     0, Passed:   671, Skipped:     3, Total:   674, Duration: 25 s - Plantoir.Tests.dll (net9.0)
'@

Write-Host "A host crash is not a failing test"
$v = Get-TestRunOutcome -Output $hostCrash -ExitCode 1
Check "verdict"                 'HostCrash' $v.Verdict
Check "no totals were believed" 0           $v.Total
Check "says HOST CRASH"         $true       ($v.Summary -like '*HOST CRASH*')
Check "says the name is a bystander" $true  ($v.Summary -like '*bystander*')

Write-Host "An ordinary failure is read as one"
$v = Get-TestRunOutcome -Output $ordinaryFailure -ExitCode 1
Check "verdict"        'Failed' $v.Verdict
Check "failed count"   1        $v.Failed
Check "total"          1        $v.Total

Write-Host "The two differ on OUTPUT, not on exit code"
# The point of the whole file: same exit code, opposite verdicts.
$crashVerdict = (Get-TestRunOutcome -Output $hostCrash       -ExitCode 1).Verdict
$failVerdict  = (Get-TestRunOutcome -Output $ordinaryFailure -ExitCode 1).Verdict
Check "same exit code, different verdicts" $true ($crashVerdict -ne $failVerdict)

Write-Host "A clean run passes"
$v = Get-TestRunOutcome -Output $clean -ExitCode 0
Check "verdict" 'Passed' $v.Verdict
Check "passed"  671      $v.Passed
Check "skipped" 3        $v.Skipped

Write-Host "Green having run nothing is not green"
$v = Get-TestRunOutcome -Output @'
Passed!  - Failed:     0, Passed:     0, Skipped:     0, Total:     0, Duration: 1 ms - Plantoir.Tests.dll (net9.0)
'@ -ExitCode 0
Check "verdict" 'RanNothing' $v.Verdict

Write-Host "A suite that skipped everything has not passed"
# The shape run-ui-tests.ps1 produces when PLANTOIR_UI_TESTS did not take:
# "Passed!", a healthy Total, and not one test actually executed.
$v = Get-TestRunOutcome -Output @'
Passed!  - Failed:     0, Passed:     0, Skipped:    11, Total:    11, Duration: 2 s - Plantoir.UiTests.dll (net9.0)
'@ -ExitCode 0
Check "verdict"  'RanNothing' $v.Verdict
Check "says how many were skipped" $true ($v.Summary -like '*11 skipped of 11*')

Write-Host "A build that never reached the tests is not a passing suite"
$v = Get-TestRunOutcome -Output @'
Views\SectionDetailView.xaml.cs(41,9): error CS1002: ; expected
Build FAILED.
'@ -ExitCode 1
Check "verdict" 'NoResult' $v.Verdict

Write-Host "A test that merely QUOTES the banner is not a crash"
# The markers are anchored to the start of a line for this: a failing test whose
# own output or assertion diff contains the sentence would otherwise be reported
# as a dead host, which hides a real failure behind "do not re-run this".
# This very file contains both sentences, so the risk is not hypothetical.
$v = Get-TestRunOutcome -Output @'
  Failed SomeTests.TheRunnerExplainsACrash [12 ms]
  Error Message:
   Assert.Contains() Failure: expected "Test Run Aborted." in the output
   The active test run was aborted. Reason: Test host process crashed : quoted, not real

Failed!  - Failed:     1, Passed:    41, Skipped:     0, Total:    42, Duration: 3 s - Plantoir.Tests.dll (net9.0)
'@ -ExitCode 1
Check "verdict"      'Failed' $v.Verdict
Check "failed count" 1        $v.Failed

Write-Host "A missed banner degrades to NoResult, never to a pass"
# The safe direction, asserted rather than assumed: if the wording ever changes
# and neither marker matches, a crashed run still has no totals line, so it
# lands on NoResult - not Passed, and not Failed.
$v = Get-TestRunOutcome -Output @'
Test run for C:\...\Plantoir.Tests.dll (.NETCoreApp,Version=v9.0)
The run stopped for some reason vstest words differently next year.
'@ -ExitCode 1
Check "verdict" 'NoResult' $v.Verdict

Write-Host "A crash wins over totals that printed for another assembly"
# A solution-wide run can summarise one project and crash in the next. A
# partial answer to "did the suite pass" is not an answer.
$v = Get-TestRunOutcome -Output ($clean + "`n" + $hostCrash) -ExitCode 1
Check "verdict"            'HostCrash' $v.Verdict
Check "says totals printed" $true      ($v.Summary -like '*did not finish*')

Write-Host "Totals from several assemblies are summed, not read once"
$v = Get-TestRunOutcome -Output @'
Passed!  - Failed:     0, Passed:   671, Skipped:     3, Total:   674, Duration: 25 s - Plantoir.Tests.dll (net9.0)
Failed!  - Failed:     2, Passed:     9, Skipped:     0, Total:    11, Duration: 3 m - Plantoir.UiTests.dll (net9.0)
'@ -ExitCode 1
Check "verdict" 'Failed' $v.Verdict
Check "total"   685      $v.Total
Check "failed"  2        $v.Failed

Write-Host ""
if ($failures -eq 0) {
    Write-Host "$checks checks, 0 failed" -ForegroundColor Green
    exit 0
} else {
    Write-Host "$checks checks, $failures failed" -ForegroundColor Red
    exit 1
}
