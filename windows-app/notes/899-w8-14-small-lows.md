# #899 W8-14: the open Windows lows from W7b2 and the sweeps (Windows #949)

Branch `issue/899-w8-14-small-lows`, built on `origin/issue/899-w8-10b-thinning-kept-copies` (68fc3c86d; pieces 9, 10 and 10b, unmerged, on `dev` 4f228c923). `origin/dev` was already in the base (no merge commit needed; checked again before hand-back).

## The brief's lows, one line each

1. **W7b2-3 review 1, L1 (menu copy, one read).** `UndoActionStep.WasThereWhenPlanned` answers from the step's own before; `ApplyMenuDuplicate` asks it after `step.Write`, and `step.Exists` before it is gone. Tests: `WhetherThePageWasThereIsWhatTheStepPlannedAsItsBefore` (a page dropped after the step's read, and one removed after it) and `TheCopyAsksTheStepWhetherThePageWasThere` (the call's place in the action). Found while doing it: in the action the window was already closed a second way, because the plan made again (`PlanAddClasses`, `File.Exists(path)`) counts any file at the new name and refuses as changed while saving, so no action-level test can tell the two orders apart; the RED is shown on the function and on the call.
2. **W7b2-3 review 1, L2 (the press's plan-time route).** `APageThePlanCannotReadIsSaidThroughThePressAsTheMacSaysIt`: the Worksheet page held with `FileShare.None` while `PublishAndRemember` plans; the conversation's copy is made first (`BackUpBeforeARolloverFromTheMenu`) so the held page meets the plan, not the zip. Says the unreadable-page sentence; nothing written. Green on the product as it was (the route was right, only unpinned); must-fail row 3 is its red.
3. **W7b2-3 review 1, L3 (row 9's anchor).** `vm-tools/guest/899-w7b2-1-mustfail.json` row 9 now anchors on Make Room's comment line plus its `MakeTheUndoStep` line, found once; the same row is row 5 of `899-w8-14-mustfail.json`, run against `UndoMakeRoomStepTests` alone.
4. **Night25-6 sweep LOW 2.** `AssistWorkspace.MenuDuplicate.cs` class remarks: the copy is one step through the door, staged and renamed whole; no `FileMode.CreateNew`, no "Windows' W7 copies".
5. **Night25-6 sweep LOW 3.** `PublishAndRemember`'s `<exception>` names every sentence `RefusalForAPressThatStopped` returns.
6. **Night25-4 sweep, piece 6.** `WindowsOwnJson["keepClassesDatedLater"]`'s `Why` no longer says the mac's recorded step names the page with its `.md`.

## The director's added lows

(a) `2026-11-26-899-w8-11-13-review-1.md`:

- **LOW 1 (whole-file fallback).** Fixed. `CourseConfiguration.PlanWhole` plans the whole bytes with the plan's own read as the before (`step.EditJson(place, read.Data!, [], whole)`, the mac's `editJSON(at:read:members:[] leaving: whole)`); a file the plan found not there is planned new (`WriteBytes`), as the mac's `step.write(whole, to:)`. Both `PlanMemberWrite` and `PlanWrite` call it. Tests: `AFilePlannedWholeTakesThePlansOwnReadAsItsBefore` (the disk holds other bytes than the plan's read: the before is the read, the make is refused, their bytes kept) and `AFileNotThereWhenPlannedIsPlannedWholeWithNoBefore`. Not copied: the mac's read-again loop inside `planWrite` (Windows' `ChangedSince` retry covers the same race at the make).
- **LOW 2 (Set School Year writes only its member).** PARKED, see "For the director". The doc comment of `ReferenceCourseUpkeep.WriteSchoolYear` now says the difference and that it is parked.
- **LOW 3 (Save through the door with a held file).** `CourseSettingsHeldFileTests.HeldByAReaderTheWindowsSaveIsRefusedAsInUseAndChangesNothing`: a reader that allows reading but not the replace; `SaveCourseSettings` is refused `FileIsInUse`, the file unchanged, nothing staged left, no step, the edit still unsaved.
- **LOW 4 (unreachable `MembersDraft`).** The trace replay now fails any step with `members` or `trees` that is not in `Converted`, by name ("a step this replay does not make yet (members)"); `MembersDraft` is removed. `moves` and `folderMoves` are still checked first, so Rename folder's twelve traces still stop at "(folderMoves)". No must-fail row: no recorded step reaches the new guard today.
- **LOW 5 (a folder appears between plan and make).** `UndoAddFolderStepTests.AFolderMadeByAnotherProgramBetweenThePlanAndTheMakeIsLeftAsItIs` (the door's `BeforeTheBegin` seam makes the folder with a page): nothing written into it, empty outcome, no step.
- **LOW 6.** `HowITeachSettingsRow.WorkingFolderOf`'s old `<summary>` removed. `windows-app/PROGRESS.md:916` (action-133 to 150 held under `Reason899W8U4a`) is not edited here (W7b2 COMMON): see "For PROGRESS".
- **LOW 7.** Run: `UndoSetSchoolYearStepTests`, `UndoSaveCourseSettingsStepTests`, `CourseSettingsSaveTests`, `CourseSettingsHeldFileTests`, `TwoWindowSettingsTests`, `ActsUseTheSavedSettingsTests`, `UndoAddFolderStepTests` are all in this piece's run (see "Runs").

(b) `2026-11-26-day26-6-sweep.md`:

- **LOW 1** (documentation 12 at about 18298 and 18305): W8b's, not touched.
- **LOW 2.** `TwoWindowSettingsTests` (all three Saves) and `CourseSettingsSaveTests.EveryPerSectionChangeEnablesSaveAndWritesOnlyItsOwnKey` now Save through `SaveCourseSettings` on the test's own list. New `AStaleWindowsSaveOfTheSameMemberWinsAndSaysItReplacedIt` pins #272 as named (same member, `ReplacedChangesFromElsewhere`). `CourseConfiguration.Write`'s summary: names which writers still use it and which plan the same merge into a step, "refuses the write", the right test name, one `</summary>`.
- **LOW 3** (trace range): see "For documentation 12".

(c) `2026-11-26-899-w8-7-8-review-1.md`:

- **L2 (kept-copy trail functions look at the old place too).** Not changed. Windows' reading follows the W8-7 brief ("the judgement of the kept copies look … at the folder's old place too") and the reviewer judged it the more truthful; making Windows copy the mac would drop a true trail line. Recorded for the director as a Mac LOW (below), so the two trails agree.
- **L3.** `UndoRecoveryContractTests` comment: "the move, then the two pages, then the edit inside".
- **L4.** `StagedLeftovers` fails by name on an entry `UndoLinks.Look` answers `CannotLook`. No fixture reaches it.

(d) `2026-11-26-day26-5-sweep.md`:

- **Item 2.** `UndoRecovery.cs` (the shadow tidy comment in `Recover`) and `UndoShadowClosedStepTidyTests`' class summary now say files and moves (`ChangesOnlyFilesAndMoves`), a folder set aside or a tree left for live.
- **Items 3 and 4**: see "For documentation 12". **Item 1** (the contract sentence `undo.rule.recovery`): a Mac piece's, see "For the director".

Already gone on the base: none of the listed lows was already fixed.

## For PROGRESS

- W8-14: the small Windows lows of W7b2-3, the night-25 sweeps, W8-7/8 review 1, W8-11 to 13 review 1 and the day-26 sweeps 5 and 6, as listed above.
- `PROGRESS.md:916` still says action-133 to 150 are held under `Reason899W8U4a`; that reason and its rows are gone since W8-11 to 13. And `PROGRESS.md:2436` says "action-133 to 144": the rows were action-133 to 150 (133 to 138 `saveCourseSettings`, 139 to 144 `addFolder`, 145 to 150 `setSchoolYear`).

## For documentation 12

- About line 18367: "action-133 to 144" should be "action-133 to 150" (the three U4a steps, six traces each; day26-6 sweep LOW 3).
- About line 18318 ("Why each still fails on Windows and is not red"): `withAMovedFolder` IS in `KeysChecked` now; mark it "no longer true" as its neighbours are (day26-5 sweep item 3).
- About line 18364: the shadow only-copy kept inside the moved folder is the mac's rule too (its `tidyClosedSteps(keepingOnlyCopies: true)`), not "a Windows-only fact for the Mac to know" (day26-5 sweep item 4).
- The replay's guard: a `members` or `trees` step not converted now stops by name in `UndoActionTraceContractTests`; `MembersDraft` is gone.

## Must-fail lines

`vm-tools/guest/899-w8-14-mustfail.json`, five rows, **5 RED of 5**, each from a clean committed tree at f53979171, restored after (`git status` empty, HEAD the same):

1. the step's `WasThereWhenPlanned` reads `File.Exists`: `UndoMenuDuplicateStepTests.WhetherThePageWasThereIsWhatTheStepPlannedAsItsBefore`, line 186 (run alone as `w8-14-mf1`: its first anchor held curly quotes that the PC's PowerShell 5.1 misreads, so it was re-anchored in ASCII).
2. `alreadyThere` read by `File.Exists` in the copy: `UndoMenuDuplicateStepTests.TheCopyAsksTheStepWhetherThePageWasThere`, line 209.
3. the press's `planning: true` made `false`: `UndoLinksChecklistStepTests.APageThePlanCannotReadIsSaidThroughThePressAsTheMacSaysIt`, line 368.
4. (riding) a settings file planned whole read again: `UndoSetSchoolYearStepTests.AFilePlannedWholeTakesThePlansOwnReadAsItsBefore`, line 204.
5. w7b2-1 row 9 at its new anchor, run against `UndoMakeRoomStepTests` alone: `NoNewOrRenamedPageIsEverHidden`, line 126 (1 failed of 10).

## Runs

- `w8-14-a` (PC, f53979171): both builds 0 errors; 20 classes (the brief's four, the settings and Add folder classes of the riding lows, `UndoActionTraceContractTests`, `UndoRecoveryContractTests`, `UndoRecoveryTests`, `UndoShadowClosedStepTidyTests`, `NamedGapLedgerTests`, and the scan classes `UndoWriterScanTests`, `UndoOpKindsContractTests`, `UndoStackContractTests`): **617 passed of 617**.
- `w8-14-mf` and `w8-14-mf1`: must-fail, above; restored 617 of 617 and 6 of 6.
- Tests first: the new tests were committed before the product changes (498bb2c08 before 61b2d7f21; 293e9cdca before 561273d3d); the new ones for lows 1 and LOW 1 did not compile on the product as it was (no `WasThereWhenPlanned`, no `PlanWhole`), and the must-fail rows are their red.
- Lock: taken and released by each run's own script; none removed that was not ours.

## Left for the next piece

- The trace guard's new clause and `StagedLeftovers`' `CannotLook` have no must-fail row: nothing in today's fixtures reaches either.

## For the director

1. **Set School Year and unsaved Course Settings edits (parked, review LOW 2).** Example: a teacher opens Course Settings for ICS3U, changes the course name, does not press Save, and then sets the school year from the Set School Year sheet. On the Mac, `SetSchoolYearSheet.write` calls `writeAsOneStep`, which plans every member its copy changed, so the step saves the new course name too (and Undo of "set school year" takes the name back). On Windows (`WriteMemberAsOneStep`), only `reference_school_year` is written and the name stays an unsaved edit. The mac's own comment there says "its one `editJSON` the school year", and the contract's recorded step (`undo-action-steps.json` → `setSchoolYear`) has one member, but its fixture holds no unsaved edit, so the contract does not decide. Options: (a) RECOMMENDED: the year alone, as Windows does; a Mac LOW makes the Mac's sheet write only its member, and a contract case with an unsaved edit pins both; (b) both write every unsaved change, and Windows' sheet changes to the merge; (c) leave the difference and document it. Nothing in the v2.0.0 milestone settles it (searched).
2. **Mac LOW (W8-7/8 review 1, L2).** Windows' kept-copy trail functions (`PathsToTidy`, `KeptOriginalsOfWhatWasRecorded`) also look at a carried page's old place; the Mac's `keptOriginalsLeft` and `keptOriginalsOfWhatWasRecorded` do not. Windows left as it is (the W8-7 brief's rule, the truer trail); the Mac to follow so the trails agree.
3. **Contract wording (day26-5 sweep item 1).** `shared-rules.json` → `undo.rule.recovery` still says shadow tidies only steps of files changed in place; both apps tidy steps of files and moves. A Mac piece owns the sentence.
