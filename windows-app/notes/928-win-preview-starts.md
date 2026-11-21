# #928, #1026, #1022 item 1: Windows preview starts and stops

Branch `issue/928-win-preview-starts`. #1022 item 1 is done here; #1022 item 2
(the 13 timed waits) is not touched, so #1022 stays open for it.

## For PROGRESS

### #928 (the mac's #812 and #813)

- The decisions are in `Plantoir.Core/Models/PreviewStarts.cs`
  (`HowTheRunStands`, `AStartIsUnderWay`, `TheStartStillBelongs`, `Begin`,
  `CouldNotStartLine`) and `PreviewAgainPresses` in the same file; the view
  only asks them.
- A start asked for while the window's own start waits in
  `WaitForStopsToFinish` or builds does nothing and writes
  `preview already starting`, in `PressPreviewAsync` (after the Stop branch)
  and FIRST in `StartAutomatedPreview`. The second press used to reach
  `PreviewLeases.Take` and show the other-window sentence;
  `StartAutomatedPreview` used to release that start's lease and overwrite its
  `_previewBuildRecord` (quit then asked for ever).
- Both starts take through `PreviewStarts.Begin` (lease, then this start's
  own record) and `TookTheStart`; the view no longer calls
  `CourseActivity.BeginPreviewBuild` itself. `StartAutomatedPreview`'s
  folder-keyed `PreviewLeases.Release(workspacePath, …)` is now the view's own
  `ReleaseLease()` (it also let go a `WorkLease` the old code leaked when it
  re-took `_previewWork`).
- A parked start runs its launcher only if it still holds its own lease (by
  reference), is the window's latest start (`_latestPreviewStart`), the page
  is not torn down and the quit has not gone ahead
  (`Plantoir.Core.Models.QuitGoingAhead`). Since review 1 (M1) the closing
  handler runs one `QuitGoingAhead.Pass` per run: the quit goes ahead in one
  place (`pass.GoAhead()`, which also abandons every repair press) and is
  taken back in one place, the pass's end, unless the pass said the close
  went through, was handed to the next pass, or was no quit. Keep Working
  when asked again after the wait for a tools copy used to leave it set, and
  Preview then started nothing until relaunch.
- A press while the window's own stop finishes (`StopPreviewAsync`, counted
  by `_stopsUnderWay`) does nothing and writes a true line to the diagnostic
  log ("…while this window's preview was still stopping: nothing was
  started"), not `preview already starting` (review 1, L1). No trail event
  names it and adding one needs a contract key, so it is the diagnostic log.
- An exception escaping either start after it took its lease hands back what
  that start still holds (`HandBackAfterAFailure`: stopped the way Stop
  stops it, only if `PreviewStarts.TheStartStillHoldsItsOwn`) (L2). The
  repair's refusal after the stop is shown through its own catch (L5).
- `AssistWorkspace`'s refusal for a folder that is not set up, which Section ▸
  Rebuild Preview shows a teacher, no longer names `preview.ps1` or the full
  path (`AssistWorkspace.NotAWorkingFolderYet`, the folder by its name) (L6).
- A run that never started (`HowTheRunStands` → `CouldNotStart`: not running,
  `LaunchProblem` set, asked before the exit code) ends the wait at once
  (`AbandonWait`: wait, record, lease), writes `preview could not start` with
  the sentence and `LaunchProblemDetail`, and shows the sentence under
  "Cannot Preview Yet". The console stays up with the sentence
  (`RefreshChrome`'s `showConsole` counts `LaunchProblem`).
- The repair's Preview Again records its press at once
  (`PreviewAgainPresses.Shared.Press`), is abandoned in `OnUnloaded` and on
  quit, starts only through `CarryOutAsync` if the press survived the stop,
  and writes `preview again abandoned` with "replaced" kept apart.
- `CourseActivity.UnderWay` counts each section once however many claims
  (`whatCountsAsUnderWay`).
- Sentences (items 8, 9): `ScriptRunner.CouldNotGetStarted` ("Could not get
  started. Try again, or restart this computer if it happens again.") and
  `ScriptRunner.FolderIsMissingAPiece` (no file name); the system's text and
  the file name go to `ScriptRunner.LaunchProblemDetail`, trail only.
  `TaskScheduling.NothingToSchedule` replaces the refusal that named
  `deploy.ps1` and the full folder path.
- Trail lines, in the mac's words: `preview already starting` writes "asked
  to preview while this window's preview was still starting: the start
  already under way goes on, and nothing else was started"; `preview could
  not start` writes "the preview could not start, and the teacher was told
  why: <sentence> (<detail>)" (`PreviewStarts.CouldNotStartLine`).
- Ledger: the `Owed(ActivityTrailEvents, 928, …)` entry and `Reason928` are
  removed; the three events are in `ActivityTrail.Event`.
- Tests: `PreviewStartRecordTests` (every `pressCases` and `previewAgainCases`
  case from the JSON, with windows A and B as two lease owners, the
  per-section count, `HowTheRunStands`, `TheStartStillBelongs`, a replaced
  press, two owners on one section, release by reference, a press during a
  stop, and source readings that both starts ask the model in order, release
  only their window's rows and hand back on a failure),
  `QuitGoingAheadTests` (every way out of the quit question, and a reading
  that the handler uses one pass), `LaunchProblemWordingTests` (refuses
  ".sh", ".ps1", ".py", "launcher", "script" in every launch problem and in
  the folder-not-set-up refusal; a missing launcher met for real). Review 1's
  L3: the two vacuous tests (`TwoStartsThenTheEnd…`, `TheViewRecordsABuild…`)
  are removed; the pressCase "a second press while the first waits for its
  stop" and the source-order theory cover item 4.
- Not met for real: the ConPTY launch failure (`CouldNotGetStarted`); the
  runner always launches `powershell.exe`, so the test reads the constant.
  The mac's test points its shell at a missing program.

- Must-fail (review 1), all reverts at once in scratch commit bd4b1bb5c (local only), each test failing on its own revert: VM B, 2026-11-21 00:31, 11 of 28 failed, the other 17 passed:
  - `QuitGoingAheadTests.KeepWorkingWhenAskedAgainAfterTheWait` line 56 and `AWindowOpenedDuringTheWait` line 71: the pass's default ending reverted from TakenBack (M1).
  - `QuitGoingAheadTests.TheClosingHandlerUsesOnePass` line 148: `LetHeldCopiesGo()` put back on the handler's Keep Working path.
  - `PreviewStartRecordTests.AnotherWindowsStartNeverEndsThisWindowsLease` line 258: `ReleaseLeftBehind` made to ignore the owner (M2).
  - `PreviewStartRecordTests.TheViewReleasesOnlyItsOwnWindowsLeases` line 381: `ReleaseLease`'s sweep put back to `PreviewLeases.Release(wp, …)` (M2).
  - `PreviewStartRecordTests.AReleaseRemovesOnlyTheLeaseItsStartTook` line 281: `Release(lease)` put back to `_active.Remove(lease)` (value equality).
  - `PreviewStartRecordTests.AStartHoldsItsOwnLeaseByReference` line 292: `TheStartStillHoldsItsOwn` made to compare with `Equals`.
  - `PreviewStartRecordTests.APressDuringAStopIsNotAStartUnderWay` line 301: the stop branch of `WhatAPressMeets` removed (L1).
  - `PreviewStartRecordTests.ThePressAsksWhetherTheWindowsStopIsUnderWay` line 392: `_stopsUnderWay++` removed from `StopPreviewAsync` (L1).
  - `PreviewStartRecordTests.AFailedStartHandsBackWhatItHolds` line 404: `HandBackAfterAFailure` removed from `StartAutomatedPreview`'s catch (L2).
  - `LaunchProblemWordingTests.TheFolderNotSetUpRefusalNamesNoFileOrPath` line 84 (via line 21): the old sentence naming `preview.ps1` put back (L6).
- Proven on VM B, head 90598c6b9 (dev 10d04bfbd merged): the piece's classes and every class that reads a changed file as source text, 44 classes in batches, all green except `PublishAndLauncherContractTests.EveryQuestionTheMacDeployLauncherAsksIsGuardedAtTheTopLevel` (deploy.sh line 1472 inside `run_token_mode()`; `deploy.sh` is untouched by this branch, so it is dev's, unrelated). `DialogTitleScanTests` needed the census at 17 for the "Cannot Preview Yet" alert. `PreviewThatCannotStartUiTests` passed twice.

### #1022 item 1

Done. Both shapes go one way: a `preview.ps1` missing before the press used to
throw inside today's-class question (`new AssistWorkspace` outside its try)
and the press did nothing, logged only. The construction is now inside the
try, the press goes on, the run cannot start, and the wait shows "Cannot
Preview Yet" with `FolderIsMissingAPiece` (see #928 above); a launcher gone
after the press's checks meets the same wait. Proven in the window by
`PreviewThatCannotStartUiTests` in the second VM (launcher moved aside before
the press; the alert's sentence read through UI Automation, the console
keeps it, the trail has `preview could not start`, and a second Preview after
the launcher is back starts).

### #1026

`ScriptRunner.CancelByUser`'s fallback remembers its run's number and process
and terminates only while that run is still current and running; it returns
the fallback's completion. Control-C's two seconds stay (behaviour,
`ControlCGrace`). `StopFallbackOwnsItsRunTests`: a second run started inside
the grace is still running after the first's fallback has completed; a run
that ignores Control-C is still terminated by its own fallback. (Review 1, L4: the first test's `IsRunning` assertion was dropped, since staged runs have no process and it held under the old code too; `FallbackTerminations` is what fails on revert.)

The mac's `ScriptRunner.swift` has the same shape (`DispatchQueue.main.asyncAfter`
near line 583, no run check); not touched here (Windows only tonight). #1015
probably holds it.

## For documentation 12

- "What the preview's wait waits on (#1016, the mac's #998)", the first row
  (line 137): replace the sentence from "A run that sets only `LaunchProblem`"
  to "which is a separate gap" with: "A run that sets `LaunchProblem` (the
  folder has no `preview.ps1`, before the press or after its checks, or a
  pseudo console that would not open) is a run that never started
  (`PreviewStarts.HowTheRunStands`, asked before the exit code): the wait ends
  at once, the record and the lease go back, the trail gets `preview could not
  start` with the sentence and `LaunchProblemDetail`, and the sentence is shown
  under "Cannot Preview Yet" while the console keeps it (#928, #1022 item 1).
  The rule withdrawn in #1016 took the console down with the sentence in it;
  the console now stays up while `LaunchProblem` is set."
- "Measured in the VM" (near line 14477): replace "so each UI test runs one
  preview; not looked into (it is not this piece's)." with "Explained by #1026:
  the earlier stop's two-second kill fallback (`ScriptRunner.CancelByUser`)
  asked only whether the runner was running and terminated the new run, whose
  stop flags were already reset, so it read as a failure. Since #1026 the
  fallback terminates only the run it was set for. The UI tests still run one
  preview each; that can now be relaxed."
- A new paragraph beside the preview start's description: "One start at a
  time per window (#928, the mac's #812): a start while the window's own start
  waits for a stop or builds does nothing (`preview already starting`); every
  start takes through `PreviewStarts.Begin`, the lease then its own record; a
  parked start runs only while it still belongs (its own lease, the latest
  start, the page there, the quit not gone ahead, `App.QuitHasGoneAhead`). The
  repair's Preview Again carries its press (`PreviewAgainPresses`, #813)."
- Sentences: launch problems name no file and carry no system text
  (`ScriptRunner.LaunchProblemDetail` holds both, trail only);
  `LaunchProblemWordingTests` holds Windows to it.
