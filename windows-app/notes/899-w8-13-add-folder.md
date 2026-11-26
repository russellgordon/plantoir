# W8-13: Add folder as ONE step (#899, Windows #949)

Branch `issue/899-w8-13-add-folder`, from piece 12's `issue/899-w8-12-save-course-settings` a3ec04d24 (which holds piece 11 and `origin/dev` 96a3d2b73), not from piece 11 as the brief said, so that the two do not conflict (`Converted`, the `Run` switch, `Reason899W8U4a`). `origin/dev` had not moved at the start or at hand-back (checked with `git fetch`), so no merge commit was needed.

## For PROGRESS

- Add folder (Course Settings, adding a name to a folder list) is ONE step through the door: `SpecialFolderRenamer.CreateFoldersOnDisk`, made by `sheet`, action `addFolder`, held by the course (no section). It finds the folders to make (one per section for a per-section folder; a folder already there is skipped, as before), reads the course's primary curriculum folder ONCE, before the step is planned (the mac's order since U4a; it was read after the folders were made), and plans every folder with its two scaffold pages through `FolderScaffold.PlanPages` (the mac's `planPages`): one `createTree` per tree, the tree's root the highest folder of the new one's path that is not there yet, holding the folders below it and the new folder's `index.md` and `_DUPLICATE ME.md`. The door is given the listing and every listed file's bytes as blobs.
- All or none: a tree that cannot be made makes nothing, and the outcome is "no folder made", so the sheet shows no notice and no `folder created` trail line (the mac's `createFoldersOnDisk` returns an empty outcome on any error). The `folder created` line is unchanged for a made folder.
- `UndoActionStep.MakeTree` (the mac's `JournaledStep.makeTree`) plans a tree; a step holding trees is made through the door that takes every kind (`MakeAsOps`), the trees after the files, each counted in `pageCount` as the mac counts it. In shadow, a step that cannot be named is made plainly by `UndoSwap` with a `MakeTree` target per tree, all or none.
- `FolderScaffold.WritePages` is gone (its one caller was the add); `FolderScaffold.CurriculumPageNames(configuration, courseDirectory)` is the one place the sheet and the fixture read the primary curriculum folder's names.
- Fixture: `addFolder` is in `Converted`, run with the mac's arguments (`Labs`, shared, `2026-09-08T07:00:00.000-0400`, the bundled template); each recorded tree is compared folder by folder and byte by byte. The trace replay makes a step with `trees` (`trees` left its guard; `moves` and `folderMoves` stay), hashes a folder by its listing, and removes a folder by hand for a `deletePage` hand edit of a folder path. No `WindowsOwnJson` entry.

## For documentation 12

Under "What W8 copies from U4a": Add folder is built (W8-13) as above. U4a is complete on Windows.

## Must-fail lines

`vm-tools/guest/899-w8-13-mustfail.json`, three rows (see Runs for results).

## Runs

(filled below)

## Left for the next piece

(filled below)

## For the director

- Tests first: the new class `UndoAddFolderStepTests` was written before the product was run; on the base it does not compile (no `CreateFoldersOnDisk` taking a list and door), so each behaviour is proven red by its must-fail row, as pieces 11 and 12 did. This Mac has no `dotnet`, so the first compile was the PC run.
- `FolderScaffoldContractTests.TheCurriculumIsReadAfterTheFolderIsMade` became `TheCurriculumIsReadBeforeTheFolderIsMade`: the mac's U4a reads the curriculum names before the step (`CourseSettingsView.swift` `createFoldersOnDisk`), and a step cannot read what it has not made. `APageAlreadyThereIsNeverWrittenOver` (a test of `WritePages` alone) went with `WritePages`: a folder already there is never planned (`ReAddingAFolderThatIsAlreadyThereWritesNothingInIt`, and `ReAddingAFolderThatIsThereMakesNoStep` here), and the door's `createTree` refuses a place that is not empty.
- The writer scan: `FolderScaffold.cs`'s entry went (its one writing call was `WritePages`; its reason, "a new working folder's scaffold, made with New Course", named no call it held). `SpecialFolderRenamer.cs` is 5 (was 6), waiting for Rename folder, W8b.

## Self-check

(filled below)
