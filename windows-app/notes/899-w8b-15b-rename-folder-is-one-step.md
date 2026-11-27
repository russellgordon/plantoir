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

(filled in from the runs)

## Runs

(filled in from the runs)

## Left for the next piece

- 16: the traces (action-151 to 162) still stop at the replay's `folderMoves` guard.
- 21: a linked place reaches `MoveFolder` and is refused `cannotTellNow` (the pinned test above). 21 plans `MoveLink` there instead, and a link to a non-folder is then skipped as a file at that place is.

## For the director

(filled in)
