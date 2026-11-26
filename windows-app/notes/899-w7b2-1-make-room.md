# #899 W7b2-1: Make Room for Classes is ONE step (Windows #949)

**This branch is never merged without W7b2-2.** Duplicate Class still makes its room file by file through `InsertClassesFileByFileForDuplicate` and `RewriteLinksFileByFileForDuplicate`, kept unchanged for it; W7b2-2 converts Duplicate Class and deletes both.

Branch `issue/899-w7b2-1-make-room`, from `origin/dev` 0a0fbe267 (W7b1, W7b2-4, -5, -10 and -11 merged). Merges of `origin/dev`: none needed, base was `origin/dev` itself (see "Runs" for the check before hand-back).

## For PROGRESS

- Make Room for Classes (`ApplyInsertClasses`, key `makeRoomForClasses`, the mac's `ClassInsertionPlanner.apply`) is ONE `UndoActionStep`, all or none: each rename planned as a `Write` of the new name and a `Remove` of the old (`UndoActionStep.Remove`, new), each link rewritten, each date moved and each new blank page in the same step, every page read through the step (`step.Exists`, `ReadText`; `PlannedWithContent`, new, lets the link pass read a renamed page under its new name). The class folder is made by the swap, never beforehand.
- A rename whose new name is taken and a new page whose name is taken are still carried past and named, at plan time. A page that cannot be planned or written changes nothing: "Nothing was changed: …". A part-way stop says `wording.publishStoppedPartWay` with "the classes you made room among" (the mac's `saidWhenTheStepStopped` words), naming the kept file.
- The fixture row `makeRoomForClasses` is converted (`Converted`, `Run`), out of `HeldButRunnable` and out of the `Reason899W7b2` ledger row; its traces run the real action.
- The plain write (shadow, a step that cannot be named) never follows a link the step REMOVED, or a page written where such a link stood: it acts on the link itself, as `File.Delete` and `Save` did. Without this, converting Make Room would have deleted, or written Day 2's content into, the file a linked later class leads to.

## For documentation 12

- Make Room's step: file order is the order first planned. For the mac's fixture (unit 1, at day 2) that is `Unit 1, Day 4.md` (the first rename's new name), `Unit 1, Day 3.md` (its old name, removed, then the second rename's new name), `Unit 1, Day 2.md` (removed, then the new blank page), `Unit 2, Day 1.md` (its link, then its date). This is the mac's order exactly; no difference to name. Four `writeFile`, no recompute.
- #550's carried-past failed write and #422's "with links not updated" count are gone for Make Room: a write that would fail now refuses the whole step. The trail line `MakingRoomDidNotFinishEveryPage` still says what was carried past at plan time; its "with links not updated" count is always 0 now.
- Shadow, a later class that is a symbolic link: Windows writes the step plainly (no step recorded), a plain copy at the new name and the link itself removed, the file it led to untouched. The mac's clause of `undo.rule.shadow` (U4b2-1) refuses that step before anything changes. Held by name in `UndoMakeRoomStepTests.ALinkedLaterClassIsCopiedAtItsNewNameWhereTheMacRefuses` until pieces U4b2-14 and 15 settle moved links. Live, Windows refuses it too (the step cannot name a link).

## Changed tests and sentences

- `InsertClassesTests.MakeRoomWhoseNewPageCouldNotBeSaved_IsCarriedPastAndNotedAsAChange` → `MakeRoomWhoseNewPageCouldNotBeSaved_ChangesNothing` (a new page's place made a folder while planning: nothing renamed, "Nothing was changed", the menu's line "changed nothing"). Its plan is now unit 2 at day 2, two classes, so the folder lands on a path no rename touches.
- `DeclinedPagesAreNamedTests.MakingRoomCountsOnlyTheClassesItActuallyMoved`: the read-only page (whose failed write was carried past and named) is taken out; it counts the declined page only. The read-only case is `UndoMakeRoomStepTests.APageThatCannotBeWrittenChangesNothing`.
- `DeclinedPagesAreNamedTests.MakingRoomCountsOnlyTheLinksItSavedAndNamesThePageItCouldNot` → `MakingRoomWhoseLinkedPageCannotBeWrittenChangesNothing`.
- `ADuplicateWhoseNewPageCouldNotBeSaved_ThrowsAndIsNotStillTaken` and every `DuplicateClassTests` test unchanged (Duplicate keeps its path).
- `NamedGapLedger.Reason899W7b2`: "W7b2-1 converted Make Room for Classes", and Make Room taken out of the list still to convert.
- `UndoWriterScanTests.Allowed["Plantoir.Core/Assist/AssistWorkspace.cs"]`: count 4 unchanged (`File.Delete` and `Directory.CreateDirectory` in the duplicate's path, `File.WriteAllText` in `Save`, `File.Move` of the rollover's marker); reason now names W7b2-2 for the duplicate's path and Make Room among the actions through the door.
- `ApplyInsertClasses`' remarks, `InsertClassesFileByFileForDuplicate`'s summary and `RewriteLinksFileByFileForDuplicate`'s remarks.

## Must-fail lines

File `vm-tools/guest/899-w7b2-1-mustfail.json`, run by `899-w7b2-1-go.ps1` (a copy of `899-w7b2-6-pc-run.ps1` as `899-w7b2-1-pc-run.ps1`). RESULTS: see "Runs".

## Runs

(filled in below)

## Left for the next piece

- Duplicate Class (W7b2-2): convert `ApplyDuplicateClass` to plan the room through `PlanTheRoom` into its own `duplicateClass` step (the stash's `DuplicateThroughTheStep` is the sketch; replace its `StoppedWhileWriting(…); throw;` with `RefusalForAStepThatStopped(error, "the classes and the copy", section)` per the mac's 4318/4495, and "the classes" for the room alone). `PlanTheRoom` returns `RoomPlanned` with counts only; piece 2 needs the created paths back (the stash's `out List<string> created`) for its #200 A "was this page made by this run" check — add it there. Then delete `InsertClassesFileByFileForDuplicate`, `RewriteLinksFileByFileForDuplicate`, the `File.Delete`/`Directory.CreateDirectory` they hold (the writer-scan count for `AssistWorkspace.cs` drops by two) and the scan reason's W7b2-2 clause; `ADuplicateWhoseNewPageCouldNotBeSaved_ThrowsAndIsNotStillTaken` then pins the old path and must be rewritten.
- `RoomPlanned.Reply` is shared wording; piece 2's `inserted.Message` comes from it.

## For the director

- First: never merge without W7b2-2.
- U4b2-1 (`origin/issue/899-u4b2-1-linked-page-written-through`) gives `makeRoomForClasses` its own ledger row with `Reason899W7b2MakeRoomLinkedPage`. This branch removes `makeRoomForClasses` from the `Reason899W7b2` row only; when both merge, that U4b2-1 row must go too (the fixture row is green, and `NoConvertedStepIsHeld` fails while it is held), and `Reason899W7b2MakeRoomLinkedPage` is then unused. The link difference stays held by name in `UndoMakeRoomStepTests.ALinkedLaterClassIsCopiedAtItsNewNameWhereTheMacRefuses`, which a PC run proves. Its sentence ("Windows' ApplyInsertClasses still writes outside the door") is no longer true after this branch.
- The stash "w7b1 half-written Make Room and Duplicate, 2026-11-21" is untouched (read with `git stash show -p`).

## Self-check

(filled in below)
