# W8b-19a1: a Rename folder holds its course (#899, Windows #949)

Base: `origin/issue/899-w8c-3b2-the-assistants-section-restore-and-the-restore-lows` (8e2ed1de8), which holds `origin/dev` f5b2d69c8; `origin/dev` is in the branch.

## Built

- `CourseActivity` (Core): `FolderRenameClaim` (`IDisposable`; the Mac's `FolderRenameRecord`), `BeginFolderRename` (null when the course is claimed), `FolderRenameSwapBegins` (false for an ended claim), `RenameSwapBegins` (the Mac's `FolderRenameRun.swapBegins` without its quit half: false while `CourseIsBeingRestored`), `EndFolderRename`, `CourseIsRenamingAFolder`, `FolderRenameIsSwapping`, `FolderRenameIsUnderWay(course)`; the restore claim `BeginRestore` (an `IDisposable` token) and `CourseIsBeingRestored`. Every folder comparison goes through `WorkingFolder.IsTheSame`. `Reset` clears both lists.
- `SpecialNames.RenameFolderUnderWay`: `undo.wording.renameFolderUnderWay`, pinned by key.
- `SpecialFolderRenamer.RenameHoldingTheCourse(workingFolder, courseCode, rename)`: the click. It takes the claim before its first await (on the UI thread, at the click), refuses a claimed course with `RenameException(renameFolderUnderWay)` and runs nothing, and gives the claim back by `using` on every ending. `Rename` gains `Func<bool>? swapBegins`, asked once after the plan and before the record and `step.Make()`. If it is refused, `RenameException(NothingWasChanged(old, OperationCanceledException's message))` is thrown and nothing is written. That is the Mac's "said as its cancellation".
- `CourseRestorer.RestoreWholeCourse` holds `BeginRestore(working folder, code)` for its whole run, by `using`. The test seam `WhileRestoringTheWholeCourse` is internal. The Mac's only caller is `WorkspaceModel.restoreBackup`, so this is the one place.
- `CourseSettingsView.RenameFolderAsync` calls `RenameHoldingTheCourse` around its `Task.Run` and passes `() => CourseActivity.RenameSwapBegins(claim)`.
- Riding low (#1055 W4 review L2): `APlaceOfTheFolderThatIsALinkStopsThePlanCannotTellNowAndChangesNothing` now pins the whole sentence.

## Red line

The tests-first commits are 325aa8945 and bf9a77f5a. `FolderRenameClaimTests` does not compile on the product as it was: `CourseActivity.BeginFolderRename`, `RenameSwapBegins`, `BeginRestore`, `SpecialNames.RenameFolderUnderWay`, `RenameHoldingTheCourse` and `WhileRestoringTheWholeCourse` are all missing. That is red for the whole class. The L2 pin may already pass on the old product, because it pins a sentence that was already right.

## Totals

See the writer's run line in the hand-back (`vm-tools/runs/899-w8b-19a1-writer.*`).

## For 19a2

The question is `CourseActivity.CourseIsRenamingAFolder(string folderPath, string courseCode) : bool` (folderPath is the working folder), and the sentence is `CourseActivity.FolderRenameIsUnderWay(string course)`. The Mac asks it in these places (`git grep -n courseIsRenamingAFolder origin/dev -- mac-app/QuartzTeachers`). Each Windows place below is a guess for 19a2 to confirm:

| Mac | Windows place |
|---|---|
| `Course.isRenamingAFolder`, `WorkspaceModel.isRenamingAFolder` (menus' greying) | `MainWindow.Menus.cs` state (19b's greying; 19a2's refusals) |
| `WorkspaceModel.structuralRefusal` (rename course, add section, removal) | `SidebarPane` Rename Course / Add Section / remove |
| `WorkspaceModel.wholeCourseRestoreRefusal` | `SidebarPane.AskWhichRestore` before `RestoreWholeCourse` |
| `CourseActivity.structuralHoldReason` | `CourseActivity.AssistHoldRefusal` / `BusyReason` |
| `ReferenceReplacer.refusal`, `.replace` | Windows' Replace reference course |
| `SectionDetailVerbs.deployWillBeRefused`, `SectionDetailView.deployAndWait` | the section view's Deploy |
| `ScheduledDeployCleanup.folderRenameRefusal` | Windows' scheduled-deploy run (none in-process; 19a3) |
| `AssistSiteWork.rebuildPreview`, `.deploy`, `AssistToolRunner.bringThePreviewUpToDate`, `AssistSectionRestore.waitsForARename` | the assistant window's and `Plantoir.Mcp`'s (19a3) |
| Save in Course Settings (the Mac's sheet) | `CourseSettingsView` Save |

## For 20a

The swap question sits in `SpecialFolderRenamer.Rename`, the internal overload. It is the `if (!swapAsked && swapBegins is not null)` block just before `record.RenameIsStarting` and `step.Make()`, inside the retry loop, and it is asked once. It runs on the `Task.Run` thread today. 20a moves that one moment to the UI thread. The claim is the caller's (`RenameHoldingTheCourse`); no static flag is used.

## For documentation 12

No corrections.

## Self-check

- One claim, keyed by working folder and code, seen by every window (a static in Core): yes. It is given back by `using` on every ending, and the tests cover whole, refused, part way, cancelled and an unexpected exception.
- A second rename is refused at the click with the contract's sentence (read by key in the test), no claim is taken and nothing runs: yes.
- The swap is refused while a restore holds the course. The rename writes nothing (tree and record unchanged) and the claim is given back: yes.
- No ledger row, no `contracts/` change, no interface change, and `undoJournalIsLive` was not touched. "being renamed right now" is in one product file (`SpecialNames.cs`).
- One function per rule: folder comparisons call `WorkingFolder.IsTheSame`.
- No run is left going and no lock was touched by hand.
