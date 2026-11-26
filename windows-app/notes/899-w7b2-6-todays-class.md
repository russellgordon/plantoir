# #899 W7b2-6: Show on Front Page is ONE step (Windows #949)

**This branch never merges without W7b2-9** (the one alert that names the kept file). Merged alone, a part-way front page would say nothing at all: the view maps `ShownWithWhatItHeldKept` exactly as `Written` for now. (Merged together with W7b2-9 on 2026-11-25, 88b3d01d9: the alert is built.)

Branch `issue/899-w7b2-6-todays-class`, from `origin/night25/integration-1` 53bb1959f (= `dev` a03fecefd + W7b2-5 + W7b2-11, the director's base). `origin/dev` (a03fecefd) is already contained in the base, so both "merge `origin/dev`" steps were no-ops ("Already up to date"; no merge commit). No `contracts/` change, no `mac-app/` change.

## Must-fail lines

`vm-tools/guest/899-w7b2-6-mustfail.json`, run by `899-w7b2-6-go.ps1` (calling `899-w7b2-6-pc-run.ps1`, a copy of `899-w7b-pc-run.ps1`). Each row is reverted alone, its test run, then restored with `git checkout`.

1. written outside the step (the front page by `File.WriteAllText`, as before): `UndoTodaysClassStepTests.ShowIsOneStepWithTheFrontPageAsItsContent`.
2. the front page named as a recompute instead of the step's content: `ShowIsOneStepWithTheFrontPageAsItsContent`.
3. a part-way stop answered as `CouldNotSave` (the part-way catch filtered out): `APartWayStopIsShownWithWhatItHeldKeptNeverCouldNotSave`.
4. an `AlreadyShows` answer making a step: `AnAlreadyShowsAnswerMakesNoStep`.
5. riding low, W7b2-5 review 1 L3 (a plan whose every page is declined answered with the done sentence): `UndoStartOfYearStepTests.APlanThatChangesNothingMakesNoStep`.
6. riding low, W7b2-11 review 2 L2 (the straight apostrophe back in the held-timetable sentence): `ReDateTests.AReDateWhoseTimetableIsHeldSaysTheClassDatesAndNoHiddenPath`.

Run d: 6 RED of 6, each a single failing test; RESTORED 510 of 510.

## Runs

All on the PC under `C:\vm-setup\wt-compare.lock` (the run script takes it, writes `owner.txt`, and removes it last; the lock was free after run d).

- Run a (`899-w7b2-6-a`, 5bed94d09): both builds 0 errors. 479 of 480 passed. The one failure was the riding-low test L3: the declined sentence names pages in the PLAN's order (classes first: "“Unit 1, Day 2” and “Loops”"), not the recorded files' order. This was the test that failed first. Fixed in 51292ae33 (the test takes the names from the plan's drafts). Every other new test, the fixture row and the six traces passed on first run. Must-fail rows 1 to 4 RED.
- Run b (`899-w7b2-6-b`, 51292ae33): 480 of 480. Must-fail 5 of 6 RED; row 6 NOT-FOUND (Windows PowerShell read the raw curly apostrophe in the JSON as ANSI). The file is now written with `\u2019` escapes.
- Run c (`899-w7b2-6-c`, must-fail only): row 6 NOT-RED with no totals, because its test is in `ReDateTests`, not `TimetableTests`, so its filter matched nothing. That also meant runs a and b had not run `ReDateTests`, the class the apostrophe test is in.
- Run d (`899-w7b2-6-d`, 51292ae33): both builds 0 errors (app x64 Debug: 37 warnings, none new). The classes: UndoTodaysClassStepTests, TodaysClassContractTests, UndoActionStepsOnWindowsTests, UndoActionTraceContractTests, NamedGapLedgerTests, UndoWriterScanTests, UndoStartOfYearStepTests, TimetableTests, ReDateTests, and the twenty source-scan classes that read `SectionDetailView.xaml.cs` (ClassesDatedLaterAtDeployTests, CourseBeingCopiedTests, DialogTitleScanTests, ObsidianOpenRouteTests, ObsidianRouteSourceTests, PreviewBrowserPrivacySourceTests, PreviewLeaseFolderKeyTests, PreviewNavigationSourceTests, PreviewStartRecordTests, PreviewWaitWakesOnTheRunTests, PublishingDestinationsContractTests, ReferenceInterfaceTests, ReferenceRefusalTests, ScheduledRunAnnouncementTests, SectionDeployRunSourceTests, SectionDetailTeardownSourceTests, SectionProblemsSourceTests, StopQuestionsContractTests, plus TodaysClassContractTests and UndoWriterScanTests above): 510 of 510. Must-fail 6 RED of 6. HEAD-AFTER the same, tree clean.
- No UI class, no harness, no whole suite.

On "tests first": the new tests use the new `Outcome` record types, so they cannot compile against the old enum. The old behaviour was proven red by sabotage instead. Row 1 puts back exactly the old write, and row 3 is the old `catch` answering `CouldNotSave`.

## Left for the next piece

- Not Today's record (`RecordNotToday`, W7b2-7): the writer-scan entry for `TodaysClassOnTheFrontPage.cs` is now 2 (its `Directory.CreateDirectory` and `File.WriteAllText`) and says so.
- The alert (W7b2-9), see below.

## For the director

- **For W7b2-9.** `AssistWorkspace.ShowTodaysClass` returns `TodaysClassOnTheFrontPage.Outcome.ShownWithWhatItHeldKept` with `KeptOriginals` (each kept file's FULL path, the one to select in File Explorer) and `KeptNames` (file names, for `kept`). The only caller is `SectionDetailView.OfferTodaysClass` (about line 1303): the switch has an arm `Outcome.ShownWithWhatItHeldKept => null` with a comment naming W7b2-9, and the method returns true for it as for `Written` (the page does show the class). That arm is where the alert goes (`keptTitle`, `kept`, `showKept`, `keptGone`; the ledger's `Reason899W4cKeptAlert` and its `TodaysClassWording` row at `NamedGapLedger.cs` about 645, left for piece 9). Piece 9 should also rewrite `Reason899W4cKeptAlert`'s last sentence ("until it lands Windows has no part-way front page to report"), which W7b2-6 made untrue; I left it, as the brief said. The part-way test to copy is `UndoTodaysClassStepTests.APartWayStopIsShownWithWhatItHeldKeptNeverCouldNotSave` (the seams that produce a kept file).
- `ShowOnTheFrontPage` is `internal` now (it takes an `UndoActionStep` maker, an internal type); its only callers were the workspace and the tests through it.
- W7b2-11's could-not-be-read sentences ("this section's class dates could not be read.") keep their straight apostrophe: the director's instruction named only the held-timetable sentence. If the house typography should hold there too, it is two constants in `TimetableMemory.cs` (about 331) and one test string (`TimetableTests.cs` about 788).
- **For the mac (W7b2-5 review 1 L1):** written under "For the director" in `windows-app/notes/899-w7b2-5-start-of-year.md` (the mac's part-way start of the year names no kept file).

## Self-check

1. Broke each fix and watched its test fail: must-fail rows 1 to 6 RED (run d), each test named above.
2. No timed waits: none in product or test. The PC waits were until-loops on the run's log.
3. Every failure sentence is true. A refusal is `CouldNotSave` ("The front page could not be saved, so it still shows {shown}."), and the page is byte for byte as it was (tested). A part-way stop is `ShownWithWhatItHeldKept` with the kept name, and the page shows the new class (tested). Its trail line says what was kept. The view says nothing for it yet, which W7b2-9 owns, so the branch does not merge without piece 9. `AlreadyShows` and `NoLongerOffered` make no step and change nothing (tested). Grep for `Outcome.Written` and the other outcome names: every use has been moved to the record types.
4. `dev` merged in before proving: `origin/dev` a03fecefd was already in the base 53bb1959f. It was fetched again before run b and before hand-back, both times "Already up to date", so there is no merge commit.
5. No number tuned by trial.
6. House style and contracts: the step is read from `undo-action-steps.json` by name, and the morning's pages are the mac's `morning()`, copied as written. Changes are in `windows-app/` only, plus `vm-tools/guest/`.
7. The fixture row is green (UndoActionStepsOnWindowsTests and UndoActionTraceContractTests, run d). `showTodaysClassOnTheFrontPage` is out of the ledger row. `Reason899W7b2` now names W7b2-6 as converted and no longer lists Today's Class among the pending actions.
8. The writer-scan count is true: `TodaysClassOnTheFrontPage.cs` is 2 (Not Today's folder and record), and the reason names W7b2-7.
9. Riding lows: W7b2-5 L1 (notes corrected, plus the mac follow-up under "For the director"), L2 (`PlaceInTheFolder` removed, `Relative` kept), L3 (the answer checked, must-fail 5). W7b2-11 L1 (#1043 named four times) and L2 (curly apostrophe in the constant and its test, must-fail 6).
10. The step keeps the action's file order (one file). Its before is read at plan time by `step.Write`, before `Make`.
