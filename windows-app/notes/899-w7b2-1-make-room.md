# #899 W7b2-1: Make Room for Classes is ONE step (Windows #949)

**This branch is never merged without W7b2-2.** Duplicate Class still makes its room file by file through `InsertClassesFileByFileForDuplicate` and `RewriteLinksFileByFileForDuplicate`, kept unchanged for it; W7b2-2 converts Duplicate Class and deletes both. (Merged together with W7b2-2 on 2026-11-26, c50bc8112: both are deleted and Duplicate Class is one step.)

Branch `issue/899-w7b2-1-make-room`, from `origin/dev` 0a0fbe267 (W7b1, W7b2-4, -5, -10 and -11 merged). Merges of `origin/dev`: f21a18782 (merging da7474047: Mac U4b2-1 to -3, Windows W7b2-6 and W7b2-9); `origin/dev` still da7474047 at hand-back, so no second merge was needed. (Merged on 2026-11-26 in `night25/integration-5`, c50bc8112, with W7b2-2, -7 and -8. "For PROGRESS" and "For documentation 12" are folded into `windows-app/PROGRESS.md` and documentation 12. What follows says the ledger and the writer scan as this branch saw them: on the merged tree the `Reason899W7b2` row and reason, and `Reason899W7b2MakeRoomLinkedPage`, are gone, and only `Reason899NoDuplicateAsNextClass` is left of W7b2, for W7b2-3. W7b2-3 merged later the same day, in `night25/integration-6`: that reason and its row are gone too, and no W7b2 action is held.)

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
7. Review 1 L5, `_removedOnce` reverted (the plain write follows a link the step removed): both cases of `ALinkedLaterClassIsWrittenPlainlyWithTheLinkRemovedAndItsFileUntouched_WhereTheMacRefusesBeforeAnythingChanges_UntilU4b2Pieces14And15` (outside and inside the working folder).
8. Review 1 L5, a change-nothing plan making a step that writes a file (`course_config.json`): `APlanThatChangesNothingMakesNoStepAndNoWrite`, on its step count.
9. Review 1 L5, a made page left Hidden: `NoNewOrRenamedPageIsEverHidden`.

Run `w7b2-1-d` on 24574d77f (after review 1): **9 RED of 9**, the restored tree 445 of 445 green.

## Runs

All on the PC (LENOVO 20QES70500, Intel Core i5-8365U, 16 GB, Windows 11 Pro 26200), under the turn lock, the brief's classes plus every class a grep for `make_room_for_classes`/`ApplyInsertClasses` finds (AssistScenarioTests, AssistSurfaceContractTests, ClubNounTests, ContractTests, DeclinedPagesAreNamedTests, SectionVerbsTests, UndoAcrossToolsTests; no UI class).

- `w7b2-1-a-red`, cf9548fb4 (tests only): both builds exit 0; **8 failed of 71**: five of `UndoMakeRoomStepTests` (one step in the mac's order, taken rename, cannot be written, part way, plan-time befores), the fixture row `TheWindowsActionLeavesTheRecordedStep(makeRoomForClasses)`, `InsertClassesTests.MakeRoomWhoseNewPageCouldNotBeSaved_ChangesNothing`, `DeclinedPagesAreNamedTests.MakingRoomWhoseLinkedPageCannotBeWrittenChangesNothing`. The three that passed before the product change (never Hidden, change-nothing, the linked later class) pin behaviour the old path already had and the conversion must keep; each is proven by must-fail row 6 or by its own assertions on the new path.
- `w7b2-1-a`, c58cf1acc (before the merge): 443 of 443; must-fail 5 RED, row 3 NOT-FOUND (anchor encoding, fixed); harness 6 failures of 12 in each place, the harness's own fault: its pages were alike but for the day, so a rename left two pages byte for byte as laid and the step held two files (beforeSwap@2 and @3 never reached). Pages now carry their own lesson.
- `w7b2-1-b`, f21a18782 (merged `dev` da7474047): both builds exit 0; **443 of 443**; must-fail **6 RED of 6**, restored 443 green; harness `w7-make-room-kill` (three renames planned with removes and one new page, real `ApplyInsertClasses`, killed at afterBegin, beforeSwap@0 to @3 and beforeApplied, shadow then live, recovered by a second process): reference 4 of 4 pages changed; **0 failures of 12 outside OneDrive and 0 of 12 inside OneDrive** (running); every page whole, no staged file, nothing Hidden but a kept copy; scratch folders removed.

- `w7b2-1-c` was launched with its mode quoted wrongly (PowerShell `-File` split it), so it would have run the wrong ref; it was stopped while building, its own lock removed (owner line `w7b2-1-c-red`), no other run waiting, the PC checkout clean.
- `w7b2-1-d`, 24574d77f (review 1's fixes: the clause read by the linked-later-class test, now a theory with a link inside the working folder too; `AmongBlankPagesAPageThatComesOutUnchangedIsNotInTheStep`; the change-nothing test's step count first): both builds exit 0; **445 of 445**; must-fail **9 RED of 9**, restored 445 green. The harness was not changed and not re-run (review 1's L3 is pinned in the unit test instead).

## Left for the next piece

- Duplicate Class (W7b2-2): convert `ApplyDuplicateClass` to plan the room through `PlanTheRoom` into its own `duplicateClass` step (the stash's `DuplicateThroughTheStep` is the sketch; replace its `StoppedWhileWriting(…); throw;` with `RefusalForAStepThatStopped(error, "the classes and the copy", section)` per the mac's 4318/4495, and "the classes" for the room alone). `PlanTheRoom` returns `RoomPlanned` with counts only; piece 2 needs the created paths back (the stash's `out List<string> created`) for its #200 A "was this page made by this run" check — add it there. Then delete `InsertClassesFileByFileForDuplicate`, `RewriteLinksFileByFileForDuplicate`, the `File.Delete`/`Directory.CreateDirectory` they hold (the writer-scan count for `AssistWorkspace.cs` drops by two) and the scan reason's W7b2-2 clause; `ADuplicateWhoseNewPageCouldNotBeSaved_ThrowsAndIsNotStillTaken` then pins the old path and must be rewritten.
- `RoomPlanned.Reply` is shared wording; piece 2's `inserted.Message` comes from it.

## For the director

- First: never merge without W7b2-2.
- **`contracts/` changed** (review 1, M1, accepted by the director): `shared-rules.json` → `undo.rule.shadow`, only its pointer "(held by name in NamedGapLedger.cs, UndoActionStepsOnWindows, makeRoomForClasses)" now names `UndoMakeRoomStepTests.ALinkedLaterClassIsWrittenPlainlyWithTheLinkRemovedAndItsFileUntouched_WhereTheMacRefusesBeforeAnythingChanges_UntilU4b2Pieces14And15`, which reads the clause and fails once either platform's half of it, or that pointer, is gone. Nothing else in the clause changed (its "on Windows Insert Class still goes ahead outside the door" stays: the step is written plainly, without the list). Mac tests that load `undo.rule`: none compares the shadow clause's text (`UndoSweepFindingsTests.testAShadowStepThatRemovesALinkedPageIsRefusedBeforeAnythingChanges` names it in a comment only; `UndoContractReplay` and `UndoSweepFindingsTests.testTheUndoLinesSentencesAreTheContracts` read other keys); for the gate: `SharedRulesContractTests`, `UndoSweepFindingsTests`, `UndoContractReplay`'s classes.
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
