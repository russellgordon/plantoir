# #899 W7b2-1: Make Room for Classes is ONE step (Windows #949)

**This branch is never merged without W7b2-2.** Duplicate Class still makes its room file by file through `InsertClassesFileByFileForDuplicate` and `RewriteLinksFileByFileForDuplicate`, kept unchanged for it; W7b2-2 converts Duplicate Class and deletes both.

Branch `issue/899-w7b2-1-make-room`, from `origin/dev` 0a0fbe267 (W7b1, W7b2-4, -5, -10 and -11 merged). Merges of `origin/dev`: f21a18782 (merging da7474047: Mac U4b2-1 to -3, Windows W7b2-6 and W7b2-9); `origin/dev` still da7474047 at hand-back, so no second merge was needed.

## For PROGRESS

- Make Room for Classes (`ApplyInsertClasses`, key `makeRoomForClasses`, the mac's `ClassInsertionPlanner.apply`) is ONE `UndoActionStep`, all or none: each rename planned as a `Write` of the new name and a `Remove` of the old (`UndoActionStep.Remove`, new), each link rewritten, each date moved and each new blank page in the same step, every page read through the step (`step.Exists`, `ReadText`; `PlannedWithContent`, new, lets the link pass read a renamed page under its new name). The class folder is made by the swap, never beforehand.
- A rename whose new name is taken and a new page whose name is taken are still carried past and named, at plan time. A page that cannot be planned or written changes nothing: "Nothing was changed: …". A part-way stop says `wording.publishStoppedPartWay` with "the classes you made room among" (the mac's `saidWhenTheStepStopped` words), naming the kept file.
- The fixture row `makeRoomForClasses` is converted (`Converted`, `Run`), out of `HeldButRunnable` and out of the `Reason899W7b2` ledger row; its traces run the real action.
- The plain write (shadow, a step that cannot be named) never follows a link the step REMOVED, or a page written where such a link stood: it acts on the link itself, as `File.Delete` and `Save` did. Without this, converting Make Room would have deleted, or written Day 2's content into, the file a linked later class leads to.

## For documentation 12

- Make Room's step: file order is the order first planned. For the mac's fixture (unit 1, at day 2) that is `Unit 1, Day 4.md` (the first rename's new name), `Unit 1, Day 3.md` (its old name, removed, then the second rename's new name), `Unit 1, Day 2.md` (removed, then the new blank page), `Unit 2, Day 1.md` (its link, then its date). This is the mac's order exactly; no difference to name. Four `writeFile`, no recompute.
- #550's carried-past failed write and #422's "with links not updated" count are gone for Make Room: a write that would fail now refuses the whole step. The trail line `MakingRoomDidNotFinishEveryPage` still says what was carried past at plan time; its "with links not updated" count is always 0 now.
- Shadow, a later class that is a symbolic link: Windows writes the step plainly (no step recorded), a plain copy at the new name and the link itself removed, the file it led to untouched. The mac's clause of `undo.rule.shadow` (U4b2-1) refuses that step before anything changes. Held by name in `UndoMakeRoomStepTests.ALinkedLaterClassIsWrittenPlainlyWithTheLinkRemovedAndItsFileUntouched_WhereTheMacRefusesBeforeAnythingChanges_UntilU4b2Pieces14And15` until pieces U4b2-14 and 15 settle moved links. Live, Windows refuses it too (the step cannot name a link).

## Changed tests and sentences

- `InsertClassesTests.MakeRoomWhoseNewPageCouldNotBeSaved_IsCarriedPastAndNotedAsAChange` → `MakeRoomWhoseNewPageCouldNotBeSaved_ChangesNothing` (a new page's place made a folder while planning: nothing renamed, "Nothing was changed", the menu's line "changed nothing"). Its plan is now unit 2 at day 2, two classes, so the folder lands on a path no rename touches.
- `DeclinedPagesAreNamedTests.MakingRoomCountsOnlyTheClassesItActuallyMoved`: the read-only page (whose failed write was carried past and named) is taken out; it counts the declined page only. The read-only case is `UndoMakeRoomStepTests.APageThatCannotBeWrittenChangesNothing`.
- `DeclinedPagesAreNamedTests.MakingRoomCountsOnlyTheLinksItSavedAndNamesThePageItCouldNot` → `MakingRoomWhoseLinkedPageCannotBeWrittenChangesNothing`.
- `ADuplicateWhoseNewPageCouldNotBeSaved_ThrowsAndIsNotStillTaken` and every `DuplicateClassTests` test unchanged (Duplicate keeps its path).
- `NamedGapLedger.Reason899W7b2` (W7b2-6's wording, from `dev`): "W7b2-1 converted Make Room for Classes", and Make Room taken out of the list still to convert. U4b2-1's row `Owed(…, Reason899W7b2MakeRoomLinkedPage, "makeRoomForClasses")` and its constant are removed (the fixture row is green, and nothing else used the constant); the difference it named is held by the linked-later-class test above, whose name carries its substance.
- `UndoWriterScanTests.Allowed["Plantoir.Core/Assist/AssistWorkspace.cs"]`: count 4 unchanged (`File.Delete` and `Directory.CreateDirectory` in the duplicate's path, `File.WriteAllText` in `Save`, `File.Move` of the rollover's marker); reason now names W7b2-2 for the duplicate's path and Make Room among the actions through the door.
- `ApplyInsertClasses`' remarks, `InsertClassesFileByFileForDuplicate`'s summary and `RewriteLinksFileByFileForDuplicate`'s remarks.

## Must-fail lines

File `vm-tools/guest/899-w7b2-1-mustfail.json` (ASCII anchors: PowerShell 5.1 reads the JSON as ANSI, so row 3's "…" anchor was NOT-FOUND in run `a`), run by `899-w7b2-1-go.ps1` with `899-w7b2-1-pc-run.ps1` (a copy of `899-w7b2-6-pc-run.ps1`). Run `w7b2-1-b` on f21a18782: **6 RED of 6**, each failing the one test named, and the restored tree 443 of 443 green.

1. Written file by file (a rename saved and deleted outside the step): `UndoMakeRoomStepTests.MakingRoomIsOneStepInTheMacsFileOrder`.
2. A before read at make time (`UndoActionStep.Make` re-reads every before): `AnEditMadeWhileItPlansIsNeverWrittenOver`.
3. A recompute named (the section front page kept true): `MakingRoomIsOneStepInTheMacsFileOrder`.
4. A file out of its planned order (each rename's remove before its write): `MakingRoomIsOneStepInTheMacsFileOrder`.
5. The old carried-past write failure put back (#550): `InsertClassesTests.MakeRoomWhoseNewPageCouldNotBeSaved_ChangesNothing`.
6. A change-nothing plan making a step and writing its backup: `APlanThatChangesNothingMakesNoStepAndNoWrite`.

## Runs

All on the PC (LENOVO 20QES70500, Intel Core i5-8365U, 16 GB, Windows 11 Pro 26200), under the turn lock, the brief's classes plus every class a grep for `make_room_for_classes`/`ApplyInsertClasses` finds (AssistScenarioTests, AssistSurfaceContractTests, ClubNounTests, ContractTests, DeclinedPagesAreNamedTests, SectionVerbsTests, UndoAcrossToolsTests; no UI class).

- `w7b2-1-a-red`, cf9548fb4 (tests only): both builds exit 0; **8 failed of 71**: five of `UndoMakeRoomStepTests` (one step in the mac's order, taken rename, cannot be written, part way, plan-time befores), the fixture row `TheWindowsActionLeavesTheRecordedStep(makeRoomForClasses)`, `InsertClassesTests.MakeRoomWhoseNewPageCouldNotBeSaved_ChangesNothing`, `DeclinedPagesAreNamedTests.MakingRoomWhoseLinkedPageCannotBeWrittenChangesNothing`. The three that passed before the product change (never Hidden, change-nothing, the linked later class) pin behaviour the old path already had and the conversion must keep; each is proven by must-fail row 6 or by its own assertions on the new path.
- `w7b2-1-a`, c58cf1acc (before the merge): 443 of 443; must-fail 5 RED, row 3 NOT-FOUND (anchor encoding, fixed); harness 6 failures of 12 in each place, the harness's own fault: its pages were alike but for the day, so a rename left two pages byte for byte as laid and the step held two files (beforeSwap@2 and @3 never reached). Pages now carry their own lesson.
- `w7b2-1-b`, f21a18782 (merged `dev` da7474047): both builds exit 0; **443 of 443**; must-fail **6 RED of 6**, restored 443 green; harness `w7-make-room-kill` (three renames planned with removes and one new page, real `ApplyInsertClasses`, killed at afterBegin, beforeSwap@0 to @3 and beforeApplied, shadow then live, recovered by a second process): reference 4 of 4 pages changed; **0 failures of 12 outside OneDrive and 0 of 12 inside OneDrive** (running); every page whole, no staged file, nothing Hidden but a kept copy; scratch folders removed.

## Left for the next piece

- Duplicate Class (W7b2-2): convert `ApplyDuplicateClass` to plan the room through `PlanTheRoom` into its own `duplicateClass` step (the stash's `DuplicateThroughTheStep` is the sketch; replace its `StoppedWhileWriting(…); throw;` with `RefusalForAStepThatStopped(error, "the classes and the copy", section)` per the mac's 4318/4495, and "the classes" for the room alone). `PlanTheRoom` returns `RoomPlanned` with counts only; piece 2 needs the created paths back (the stash's `out List<string> created`) for its #200 A "was this page made by this run" check — add it there. Then delete `InsertClassesFileByFileForDuplicate`, `RewriteLinksFileByFileForDuplicate`, the `File.Delete`/`Directory.CreateDirectory` they hold (the writer-scan count for `AssistWorkspace.cs` drops by two) and the scan reason's W7b2-2 clause; `ADuplicateWhoseNewPageCouldNotBeSaved_ThrowsAndIsNotStillTaken` then pins the old path and must be rewritten.
- `RoomPlanned.Reply` is shared wording; piece 2's `inserted.Message` comes from it.

## For the director

- First: never merge without W7b2-2.
- The merge took U4b2-1's ledger row for `makeRoomForClasses` and its constant `Reason899W7b2MakeRoomLinkedPage` out (the row is converted; `NoConvertedStepIsHeld` would fail on it). The difference it named (the mac refuses a step whose later class is a link; Windows in shadow writes a plain copy at the new name and removes the link itself, the linked file untouched) is held by name in the test `UndoMakeRoomStepTests.ALinkedLaterClassIsWrittenPlainlyWithTheLinkRemovedAndItsFileUntouched_WhereTheMacRefusesBeforeAnythingChanges_UntilU4b2Pieces14And15`, proven green in run `b`. Live, Windows refuses that step too (a link cannot be named in a step). Pieces U4b2-14 and 15 decide; when they do, that test changes.
- The plain write's link fix in `UndoActionStep` (`_removedOnce`: a link the step removed, or a page written where it stood, is acted on at the link itself) applies to every action, not only Make Room; only a rename plans a remove today.
- The stash "w7b1 half-written Make Room and Duplicate, 2026-11-21" is untouched.

## Self-check

1. Broke each fix and watched its test fail: the tests-first commit failed 8 named tests; six must-fail rows all RED on the merged tree, each naming its failing test (above).
2. No timed waits: none added; the harness child blocks in its kill seam until killed, as the existing runs do.
3. Failure-path sentences true: a page that cannot be planned or written says "Nothing was changed: …" and every page is as before (`APageThatCannotBeWrittenChangesNothing`, `MakeRoomWhoseNewPageCouldNotBeSaved_ChangesNothing`, `MakingRoomWhoseLinkedPageCannotBeWrittenChangesNothing`, `AnEditMadeWhileItPlansIsNeverWrittenOver`); part way says `publishStoppedPartWay` with "the classes you made room among" and the kept file's name (`APartWayStopSaysThePartWaySentence`). Sentences naming the moved code (Menu.cs's "Make Room records NO undo entry", the writer-scan reason, `Reason899W7b2`) checked and true for today's in-memory undo.
4. `dev` merged before proving: f21a18782 (da7474047); unchanged at hand-back.
5. No number tuned by trial: none.
6. House style and contracts: the fixture runs from `undo-action-steps.json`; no contract or mac file changed; Windows-only.
7. Fixture row `makeRoomForClasses` green, its traces run the real action, out of `HeldButRunnable` and the ledger; `Reason899W7b2` true.
8. Writer-scan count for `AssistWorkspace.cs` true at 4, reason names W7b2-2.
9. Riding lows: none named.
10. File order is the action's (the mac's exactly); every before read at plan time (must-fail row 2).
11. The stash is untouched (`git stash list` still shows it).
