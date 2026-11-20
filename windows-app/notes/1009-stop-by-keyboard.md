# #1009 Windows: stop a preview or deploy from the keyboard, round 6 notes

The branch's own PROGRESS entry and documentation 12 section were written in rounds 1 to 5. Round 6 (the fifth review's MEDIUM and LOW) is held here under the NIGHT3 rule, for the director to fold in.

## For PROGRESS

Add one bullet to the 2026-11-20 entry "Escape stops a running preview or deploy, with the mac's stop question (#1009, the mac's #988)":

- Fifth review's fixes: a stopped task is recorded as stopped whatever the launcher exited with. Escape or Cancel on a preview sends Control-C and `preview.ps1` ends its serve with exit 0, and the trail line read "finished preview.ps1 — succeeded". `ScriptRunner.FinishedOutcome` now takes the mac's order (`ScriptRunner.outcomeDescription`): stopped by the teacher, closed for a deploy, backed out at a question, then the exit code ("succeeded", or "failed (exit code N)"). Test: `StopQuestionsContractTests.AStopIsRecordedAsAStop_WhateverTheLauncherExitedWith` (the function over exit codes 0, 1 and -1, and a staged runner cancelled by the teacher that ends with exit 0, whose trail line must read "— stopped by the teacher"); red with the exit code checked first again. A stale comment on `IsBetweenPhases` no longer names the 100 ms poll #1016 removed. RESULT-LINE

## For documentation 12

In the section "Escape stops a running preview or deploy, and the stop questions (#1009, the mac's #988)", under what the trail records:

- **A stop is recorded as a stop.** The "task finished" line's outcome is decided in the mac's order: "stopped by the teacher" when the teacher stopped the task (Escape, Cancel, the console's Stop, or Stop Deploy at the question), then "closed for a deploy", then "backed out at a question", and only then the exit code. The order matters on Windows because a preview stopped with Control-C exits 0: read by exit code first, a stop was written as "succeeded", and a problem report could not tell a teacher's stop from a preview that ended on its own. `ScriptRunner.FinishedOutcome` is the one place the order lives; the run's saved transcript carries the same words. The order is not data in `shared-rules.json` (`activityTrail` gives only why the outcome must tell a stop from a failure), so the cases are in the test.
- **Correct a sentence the fix made wrong**, in the paragraph "*The text-box test.*" (about line 14623): "and stopping a serving preview ends without the "stopped by the teacher" line the test waited for, since the build's `preview.ps1` had already ended "succeeded"" becomes "and stopping a serving preview then ended without the "stopped by the teacher" line the test waited for: `preview.ps1` exits 0 on Control-C and the outcome was read from the exit code first, so the line said "succeeded" (fixed in the fifth review's round: a stop is recorded as a stop)".
