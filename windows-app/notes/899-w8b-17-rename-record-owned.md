# #899 W8b-17: the rename record lives only while its own rename is unfinished (2026-11-27)

Base: `origin/issue/899-w8b-window-a-fixes` 71c49162d. Merges of `origin/dev` (8046ca2e8, before proving and before hand-back): already up to date both times, so no merge commits.

## For PROGRESS

- Rename folder's interrupted-rename record (`courses/.internal/renames/<CODE>.json`) has one owner, `RenameRecordClaim` (end of `Plantoir.Core/Models/SpecialFolderRenamer.cs`, the mac's `RenameRecordClaim`). It reads the earlier record's bytes before anything is written. `SpecialFolderRenamer.Rename` calls only its endings: `RenameIsStarting` (before a step that moves folders), `NothingWasChanged` (a refusal, and before each changed-since retry), `RenameIsWhole` (after the make and `FinishRecord`). A part-way stop (`UndoStepLeftPartWayException`) and a test's kill point keep this run's record.
- `CourseSettingsView.xaml.cs`'s unconditional `ClearRenameRecord` is gone. `RecordRenameStarting` and `ClearRenameRecord` are now `internal` (tests only, outside the owner). The writer scan count for the file stays 3: `WriteRenameRecord` is the one write, used for this run's record and for the put-back.
- The record's keys are unchanged (`from`, `to`, `scope`). 18a owns them.

## For documentation 12

- "What W8 owes from U4b2-3" is built on Windows. It can be marked done: `RenameRecordClaim`, with the tests named below. `changesTheSettings` is `settings is not null`, so the sheet clears a record of this folder renamed to another name even when nothing moved. A `Rename` with no settings change (the stack replay) leaves that record, as the mac's `rename` does.
- A failed put-back or clear writes `RenameNoteNotTidiedLine` on the trail under `folder renamed`, copied from the mac's `renameNoteNotTidiedLine`.
- One difference from the mac, deliberate: the mac's `rename` calls `nothingWasChanged` for an error that is not a `JournaledStepError`. Windows keeps the record for any exception that is not an `IOException` or `UnauthorizedAccessException`. The reason is that the door's "stopped by a test" is a bare `InvalidOperationException`, which must keep the record as a killed process would, and that type cannot be told apart from an unexpected fault. Keeping the record is the safe side, because the reader judges it against the disk.

## Tests that failed first

At d6f122fe9 (tests only), on the product as it was: 9 of 63 failed in `SpecialFolderRenamerTests` and `FolderRenameApplyTests`:
- `FolderRenameApplyTests.ARenameMovesEverySectionsFolderAndRewritesTheLinksThatNameIt`: `Assert.False` (the record was left after a whole rename).
- `SpecialFolderRenamerTests`:
  - `AnotherFoldersUnfinishedRecordSurvivesAWholeRenameOfThisOneByteForByte` (the bytes differ)
  - `ARefusalThatChangedNothingPutsTheEarlierRecordBackByteForByte` (the bytes differ)
  - `ARefusalThatChangedNothingLeavesNoRecordWhenThereWasNoneSoTheOneSectionRestoreIsNotGreyed`
  - `AWholeRenameWithNoEarlierRecordLeavesNone`
  - `TheSameRenamesRecordIsClearedWhenTheRenameIsFinished`
  - `ThisFoldersEarlierRenameToAnotherNameIsClearedOnceTheSettingsNoLongerNameIt`
  - `APutBackThatFailsAfterARefusalSaysDidNotRenameOnTheTrail` (`Assert.Contains`)
  - `APutBackThatFailsOnceTheRenameIsWholeSaysRenamedOnTheTrail` (`Assert.Contains`)
- These two passed red as well as green, as expected: `ARenameThatStoppedPartWayKeepsThisRunsRecord` (the old code kept every record) and `ARenameThatMovesNoFolderLeavesAnotherFoldersRecordUntouched` (the old code did not write when nothing moved). They are guards, and must-fail rows 1 and 4 turn the second one red.

## Must-fail lines

`vm-tools/guest/899-w8b-17-mustfail.json`, 4 RED of 4. Each test run was `SpecialFolderRenamerTests`.
1. The unconditional clear put back (`record.RenameIsWhole()` → `ClearRenameRecord`): `AnotherFoldersUnfinished…` failed with "another folder's unfinished rename is not this rename's to clear", plus 2 others.
2. The earlier record not read (`_earlierRecord = null`): `ARefusalThatChangedNothingPutsTheEarlierRecordBack…` failed (FileNotFound), and `TheSameRenamesRecordIsCleared…` and `AnotherFolders…` failed too.
3. "renamed" said on a refusal's failed put-back: `APutBackThatFailsAfterARefusalSaysDidNotRenameOnTheTrail` failed (`Assert.Contains`; the trail read "renamed the folder…").
4. Another folder's record cleared by a whole rename (`recordsThisFolder &&` dropped): `AnotherFolders…` and `ARenameThatMovesNoFolder…` failed.

## Runs

- `w8b-17-a` on the PC, using `899-w8b-17-pc-run.ps1` through `899-w8b-17-launch-a.ps1`, modes `classes,mustfail`, red ref d6f122fe9. Run 02:35 to 02:39 on 2026-11-27. The run took its own lock and released it.
- At ead15067b: both builds had 0 errors. 327 of 327 tests passed, 0 skipped, across `SpecialFolderRenamerTests`, `FolderRenameApplyTests`, `UndoRenameFolderStepTests`, `OneSectionRestoreContractTests` (no `OneSectionRestoreTests` exists), `NamedGapLedgerTests`, `UndoWriterScanTests`, `UndoOpKindsContractTests` and `UndoStackContractTests`.
- After the must-fail rows, the restored run passed 327 of 327. HEAD-AFTER was the same commit and the status was clean.

## Left for the next piece

- 18a: the record's keys (`moved`, `mayHaveMoved`). `RenameRecordClaim.RenameIsStarting` is where they are written; the mac's `renameIsStarting` reads `placesMoved(byTheRecord: earlierRecord…)` from the claim's earlier bytes, which Windows now holds as `_earlierRecord`.

## For the director

- No ledger row was cleared (the brief named none), and nothing was parked. No `contracts/` change was made.
- Self-check: 11 and 12 do not apply (no held row, no key). 13: the record comparisons call `SpecialFolderRenamer.RecordNames` and `RecordNamesTheFolder`, and there is no path comparison. 14: no run is left going, the lock was taken and released by the run itself, and no other lock was touched.
