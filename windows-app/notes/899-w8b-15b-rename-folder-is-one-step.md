# #899 W8b-15b: Rename folder is ONE step through the door (Windows #949)

Branch `issue/899-w8b-15b-rename-folder-is-one-step`, built on 15a's `origin/issue/899-w8b-15a-a-step-moves-a-folder` (4d416c799), which already holds `origin/dev` 4f228c923: no merge commit was needed (checked at the start and again before hand-back).

## What landed

- `SpecialFolderRenamer.Rename(old, new, scope, course, sections, settings, finishing[, undo, door])` plans ONE `UndoActionStep`, key `renameFolder`, made by `sheet`, held by the course, and makes it:
  - one `UndoActionStep.MoveFolder(from, to)` per place of the folder (15a; the step's listing is taken at plan time);
  - each relinked page (`PlanRelinkedPages`), read now where the walk finds it and named at its place after the move (`PlaceAfter`, by `UndoOp.PartInside`), planned in the one page order (`UndoActionStep.ComparePageOrder` on the slashed path). The step re-sorts by the same function when a folder moves; when none moves (the finishing run, and a rename whose folder is not on disk) the step keeps the planned order, so the renamer's sort is what orders those;
  - the settings, through the new `CourseConfiguration.PlanRecordOnDisk(change, path, step)`: one fresh read, the change applied to it, then W8-12's member planner (`MembersMoved`, keys sorted ordinal: `expandable`, `shared_folders`; or `expandable`, `hidden`, `per_section_folders`), or one whole `writeFile` when the member rule cannot move it. After the make, `FinishRecord` applies the change to this copy and takes the file as read back as its last-saved state. There is no second settings write.
  - A `changedSince` refusal at the make is planned again from the disk, up to three times (the mac's `renameFolder` loop). Any other refusal, and every plan-time refusal, is a `RenameException` carrying the door's own sentence, with nothing changed.
- `Directory.Move` and `RelinkPages` are gone. The places are found without following a link (`IsAPlaceToMove`: `UndoLinks.Look` is Folder, Link or CannotLook; never `Directory.Exists`). A place that is a link reaches `MoveFolder`, which refuses `cannotTellNow` before anything changes: pinned by `APlaceOfTheFolderThatIsALinkStopsThePlanCannotTellNowAndChangesNothing_UntilW8bPiece21`, for 21 to turn round.
- The page walk: `PagePaths.MarkdownPages(course, descendsIntoLinks: false)` does not descend into a folder entry `UndoLinks.Look` calls a link (a name-surrogate reparse point). Any other reparse point, a OneDrive placeholder's, is walked as the folder it is. Every other caller of `MarkdownPages` is unchanged (the parameter defaults to true).
- The finishing run (`CourseSettingsView` passes `finishing`) is the same function: no move, its relinked pages and members as one step.
- `CourseSettingsView.RenameFolderAsync`: `SpecialFolderRenamer.RenamingTheSettings` (the curriculum folders read before the move, #345, moved here from the view so the fixture drives the same code) and `Rename` in the one `Task.Run` as before; the `Config.RecordOnDisk` after it and its catch are gone. The record is cleared, the trail line and the notice are as before.
- Unchanged, as the brief says: the rename record (written before the make when a folder moves, cleared by the sheet after), every sentence (`DoneMessage`, `RenameNothingWasThere`, the refusals). `HalfFailureMessage` is no longer called by the rename (all or none now); it stays for 18b.

## For PROGRESS

- W8b-15b: Rename folder (Course Settings) is ONE step through the door: one `move` per place, the relinked pages at their new places in the one page order, one `editJSON` per changed settings member. `renameFolder` and `renameFolderPerSection` match the mac's recorded steps. The walk never goes through a link. A linked place stops the rename until W8b-21.

## For documentation 12

- "What W8 owes from U4b2-11": built in W8b-15b (`SpecialFolderRenamer.Rename`, `PlanRelinkedPages`, `CourseConfiguration.PlanRecordOnDisk`).
- "What W8 owes from U4b2-15", "Windows today": `Directory.Move` and `Directory.Exists` are gone from `SpecialFolderRenamer`; the walk skips a link by `UndoLinks.Look`, not by `FileAttributes.ReparsePoint` as the "Pages" bullet says ("must skip an entry with `FileAttributes.ReparsePoint`" would skip a OneDrive placeholder; correct it to "an entry `UndoLinks.Look` calls a link").

## Must-fail lines

`vm-tools/guest/899-w8b-15b-mustfail.json`, run in `w8b-15b-mf` on 8e7843064, restored at 501 of 501:

1. The members written by a second save after the step (`RecordOnDisk` after `FinishRecord`): RED in `UndoRenameFolderStepTests.APerSectionRenameIsOneStepOfItsMovesThenItsPagesThenItsMembersAndNoSecondWrite`. The whole re-spelled write loses `"num_sections" :   2,`.
2. The walk descending into a link (the `UndoLinks.Look` skip removed): RED in `ALinkInsideTheCourseIsNotWalked`. The page behind the link is planned, so the step cannot be named and is written plainly, and the outside page is changed.
3. The walk skipping by `FileAttributes.ReparsePoint`: RED in `AOneDriveStylePlaceholderFolderIsWalkedAsTheFolderItIs`. The placeholder folder is skipped and its page is not relinked. This test RAN on the PC: a Cloud Files API placeholder (tag `IO_REPARSE_TAG_CLOUD`, not a name surrogate) under a sync root of the test's own can be made and listed. That is what 15a could not do with a bare `0x80000013` tag.
4. The pages in directory order (the renamer's `ComparePageOrder` sort removed): RED in `TheFinishingRunIsOneStepOfItsPagesInTheOnePageOrderThenItsMembersAndNoMove`. With no folder move, the step keeps planned order, and `MarkdownPages`' case-blind sort puts `index.md` before `_Intro.md`.
5. `Directory.Move` put back before the make: NOT RED in `w8b-15b-mf`, where the row named `APerSectionRename…`. The step judges each move by content. With `from` gone and `to` holding the planned listing, the move reads as already made, so the step goes ahead and the test passes. The row's filter named the wrong class. The test that catches a writing call coming back is `UndoWriterScanTests` (`SpecialFolderRenamer.cs` allowed 3; the sabotage makes 4). The row now names that class, and `w8b-15b-mf5` ran it alone (result under "Runs").
   - In `w8b-15b-mf5` (8e7843064): **RED**, `SABOTAGE 1 build=0 test=1 RED (5) Directory.Move put back :: Failed! - Failed: 1, Passed: 4, Skipped: 0, Total: 5` (`UndoWriterScanTests`). Must-fail is therefore 5 RED of 5. (Line added by W8b-16's writer from `C:\vm-setup\w8b-15b-mf5\run.log`.)

## Runs

- `w8b-15b-a` (0251619e5): both builds 0 errors. 499 of 501 passed, 0 skipped. `renameFolder` and `renameFolderPerSection` failed because the fixture wrote the marker before making the working folder. Fixed in 164e5726a.
- `w8b-15b-b` (8e7843064): both builds 0 errors. **501 passed of 501**, 0 skipped. The run covered `UndoRenameFolderStepTests` (6, the symbolic-link and placeholder tests run), `SpecialFolderRenamerTests`, `FolderRenameApplyTests`, `UndoActionStepsOnWindowsTests`, `UndoActionStepFolderMoveTests`, `NamedGapLedgerTests`, `UndoActionTraceContractTests` and the three scan classes `UndoWriterScanTests`, `UndoOpKindsContractTests` and `UndoStackContractTests`.
- `w8b-15b-mf` (8e7843064): must-fail 4 RED of 5, row 5 NOT RED (above). Restored at 501 of 501.
- `w8b-15b-mf5` (8e7843064, 2026-11-27 01:21 to 01:22): row 5 alone against `UndoWriterScanTests`: RED, 1 failed of 5. Restored: **501 passed of 501**, 0 skipped. HEAD-AFTER the same, status clean, the lock taken and released by the run itself. (Added by W8b-16's writer from `C:\vm-setup\w8b-15b-mf5\run.log`.)
- Locks: every run's own script took and released the lock. Runs b and mf waited behind the director's `day27-4-two` runs. I removed no lock that was not mine.

## Left for the next piece

- 16: the traces (action-151 to 162) still stop at the replay's `folderMoves` guard.
- 21: a linked place reaches `MoveFolder` and is refused `cannotTellNow` (the pinned test above). 21 plans `MoveLink` there instead, and a link to a non-folder is then skipped as a file at that place is.

## For the director

- Tests first: 22d976478 (the tests, including the fixture rows and the ledger) comes before 0251619e5 (the product). The tests do not compile on the product without `RenamingTheSettings` and the new `Rename` overload, so their red is the must-fail rows, as in W8-12 and 15a.
- Parked: nothing for Russell. A refusal now shows the door's own sentence through `RenameException`. The contract's `renameFolderNothingWasChanged` and the part-way sentences are 18b's. `HalfFailureMessage` is no longer reached (all or none); 18b decides it.
- Found by row 5, for 16 and 21 to know: a folder moved by hand to the new name between the plan and the make reads to the step as the move already made (judged by content). The step goes ahead, and the move op is recorded. That is the `opKinds.move` rule as built in W8-2 and W8-5, not a fault of this piece. I did not test whether the mac does the same.
- `FinishRecord` runs on the `Task.Run` thread, where today's `RecordOnDisk` ran on the UI thread after it. The sheet is awaiting, so nothing reads `Config` meanwhile. 20a moves the planning anyway.
- Self-check:
  - 11: both rows are out of the ledger, `Reason899W8U4b` names only the twelve traces, and `Reason899W8U4b2LinkedFolder` is rewritten (it described `Directory.Move` and the old walk).
  - 12: no `KeysChecked` key was added. `MakeAndMatch` now compares `move` ops with `folderMoves`.
  - 13: link is `UndoLinks.Look`, at-or-inside is `UndoOp.PartInside`, page order is `ComparePageOrder`, members go through `MembersMoved`.
  - 14: no run is going, no lock is held, and I removed none that was not mine.
