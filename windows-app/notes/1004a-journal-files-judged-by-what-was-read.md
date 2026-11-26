# #1004-a: the journal's own files are judged only by what was read from them (Mac Undo, #899)

Branch `issue/1004a-journal-files-judged-by-what-was-read`, base `origin/dev` 0e12bc8ac. `origin/dev` had not moved at either merge point (before proving, before hand-back: "Already up to date"), so there is no merge commit.

## For PROGRESS

- Mac #1004-a (2026-11-26): a file of the list is judged only by the bytes read from it. (1) A `folder-id`/`computer-id` holding no identifier is known by the `fstat` of the descriptor that read it (device, file number, size, time; `UndoIdentifierFile.inspect`, `UndoFileReads.readWholeWithStatus`), never by a second look at the name; set aside only while `lstat` of the name is still that file, and the file moved is compared again after the rename and put back if it is another. (2) `UndoFoldCache.read` passes over a segment gone since the listing only when it is not the newest listed; the newest gone throws `couldNotRead`. (3) `UndoJournal.segmentNumbers` lists with `opendir`/`readdir` (`namesListed(in:)`): only `ENOENT`/`ENOTDIR` is no segments, anything else `couldNotRead`.
- Contract: `file-formats.json` → `undoJournal.identifierFiles.unreadable` (the file inspected defined), `undoJournal.files["journal-NNNNNN.jsonl"]` (two sentences appended); `shared-rules.json` → one `stackCases` row and the call `newestSegmentGoesWhileRead` in `stackCasesHow`. Held on Windows: 1 row, `Reason1004JournalReading`.

## For documentation 12

- **The replay call.** Windows must add `newestSegmentGoesWhileRead` to `UndoStackContractTests` (the call dispatch about line 342, beside `undoWhileAStepBegins`): an Undo during which, once `UndoJournal.Segments()` has listed the folder and before the newest segment is opened, the newest segment is moved away; it is moved back once the Undo has answered. Expect `listUnavailable` (Windows' word for an unreadable list), head 2, onTheList [1, 2]. The reader needs a seam between `Segments()` and `ReadSegments`'s opens (Read(), about line 452). The reader itself already behaves: `ReadSegments` (UndoJournal.cs about 533 to 538: "An older segment pruned since the listing is passed over; the newest never is") returns `CannotRead`, so the Undo is refused as the list unreadable. Then drop the row from `Reason1004JournalReading`.
- **The folder-id.** Windows already meets the new `identifierFiles.unreadable` sentence. Read: `FolderIdentityFile.cs` 95 to 121 (the identity is taken from the handle the bytes are read through, line 104, `IdentityOf(stream.SafeFileHandle)`), 226 to 252 (`SetAside`: the name opened once, its identity compared with the read's, read again, and renamed through that same handle with `SetFileInformationByHandle`/`FileRenameInfo`, so the file moved is provably the file read). One small difference, not owed: Windows takes the "written less than ten seconds ago" time by path (`File.GetLastWriteTimeUtc(FilePath)`, line 108) after the read, where the Mac now takes it from the read's descriptor; a file swapped in that instant could make an empty file look young or old, which only changes "not yet" against "set aside" for a file that is then compared by identity anyway, so no good identifier is lost. Named for W8 to decide, not a fault.
- **The unlistable folder.** Windows already does this (`Segments()`, UndoJournal.cs 395 to 411: only `DirectoryNotFoundException` is no segments).
- **Cached newest not listed at all, nothing higher listed** (the brief's question). The Mac and Windows do NOT differ, so no test was added. Mac: `stillValid` (UndoJournal.swift 500 to 535) treats a remembered segment that is not listed as gone from the oldest end only when it is below the lowest listed (line 513); a remembered newest missing with a lower one still listed fails `stillValid`, the list is read whole from what is listed, and the read loop (413 is the forgetting of passed-over ends) folds the rest. Windows: `ReadSegments` 513 to 524, "once one kept segment is there, every later kept one must be": the same case is `Invalid`, read whole from what is listed. Both read a shorter list in that case, and both pass over everything when no remembered segment is listed at all. This is the same hole as gap 2 one read later (the newest gone between two reads rather than between a listing and an open); it is not this piece's, see "For the director".
- **What macOS allows, and the window left.** macOS has no rename by descriptor (`renameat`, `renamex_np` all take paths), so the Mac compares `lstat` of the name with the read's `fstat` immediately before `FileManager.moveItem`, and `lstat` of the set-aside name immediately after; a mismatch is put back with `renamex_np(RENAME_EXCL)` as before. The window left is the instant between that last `lstat` and the rename: a file put at the name inside it is moved, then found to be another file and put back (unless a third file has taken the name by then, which is today's put-back failure, now possible only inside that instant). No smaller window exists on macOS without a rename through a descriptor.
- **Measured (macOS 26, this Mac):** `FileManager.contentsOfDirectory(atPath:)` on a folder whose parent has mode 000 throws `NSCocoaErrorDomain` 260 (`fileReadNoSuchFile`) with underlying `NSOSStatusErrorDomain` -43 (`fnfErr`), not `EACCES`; so the brief's "read the underlying POSIX error" route would have kept the bug (first green run, `run-green.log`, failed exactly so). Hence `opendir` and its `errno`.

## Must-fail lines

All in `windows-app/notes/1004a-mustfail.log`. 4 RED of 4.

- M1 (the file number taken by path again: `setAside(url, ifStillTheFileRead: identity(at: url) ?? inspection.file)`): `UndoJournalCoreTests.swift:98 testAFolderIDReplacedByAGoodOneIsNeverSetAside`: "alone: the good folder-id was moved aside (a put-back was needed)", and the third-file variant.
- M2 (`continue` for every gone segment): `UndoJournalCoreTests.swift:109 testTheNewestSegmentGoneAfterTheListingIsAnUnreadableList` ("read on: ... gave a fold of 0 steps, not an unreadable list") and `UndoJournalContractTests.swift:118 testStackCases` (the #1004 row).
- M3 (`contentsOfDirectory` then `fileExists`): `UndoJournalCoreTests.swift:115 testAListFolderThatCannotBeListedIsUnreadable`: "a list folder that cannot be listed answered [], not a throw".
- M4 (Python, the model's call answering `nothingToUndo`): `test_stack_cases` on the #1004 row: `'nothingToUndo' != 'listUnavailable'`.
- Red first on the base (product unchanged, seams and tests at 2925e32b6): the four new core tests and the stack row, five failures (log, first section). The older-segment half of the newest-segment test passes on the base, as the brief expects.

What each test pins:
- `testAFolderIDReplacedByAGoodOneIsNeverSetAside`: a damaged `folder-id` replaced by a good one (a new file, renamed onto the name) at the seam `afterAnIdentifierFileIsRead`; the answer is the good identifier, the name still holds it, no put-back was ever needed (the seam `beforeAnIdentifierFileIsPutBack` never runs, so the good file was never moved), and no `.unreadable-` file holds it; the second variant also writes a third identifier at the name at the put-back seam, which on the base stranded the good one.
- `testAFileThatIsNotTheOneReadIsPutBack`: a different damaged file put at the name at `beforeAnIdentifierFileIsSetAside` (after the last compare): it is put back, nothing is left aside. (Not in the brief's must-fail list; red on the base, where the other file was set aside and a new identifier made.)
- `testTheNewestSegmentGoneAfterTheListingIsAnUnreadableList`: at `afterTheSegmentsAreListed` the only (newest) segment is moved away: `couldNotRead`, both reading on and read whole; put back, the list reads 2 steps; then an empty older segment 1 below the steps in segment 2 is deleted at the seam: passed over, 2 steps.
- `testAListFolderThatCannotBeListedIsUnreadable`: the list folder's parent set to mode 000 (restored in the check's `defer` and again in `tearDown`): `couldNotRead`; a folder that is not there: no segments.

## Runs

All through `xlock.sh`, `.dd/` in the worktree.
- `run-red.log`: UndoJournalCoreTests + UndoJournalContractTests on the unchanged product: 35 tests, 5 failures (all the new ones).
- `run-green.log`: the 19 classes below with the first fix (Cocoa's error read): 224 tests, 1 failure (the unlistable folder; the measurement above).
- `run-green2.log`: UndoJournalCoreTests, UndoReadAheadTests, UndoJournalContractTests, UndoFilesContractTests, FileFormatsContractTests, SharedRulesContractTests, UndoWriterScanTests, and every class reading documentation 09 as text (AboutWindowLinksTests, AlertKeysTests, CloudSyncNoticeLayoutTests, CourseSettingsTeardownTests, DetailTabsLayoutTests, ListTableGoldenTests, ProgressViewSizeTests, TodaysClassOnTheFrontPageTests, TickTableTests, UnsavedSettingsNoticeLayoutTests, UpdateRemindersTests, WorkingFolderSelectionTests): 224 tests, 0 failures. `UndoCoreChecks` is not a test class (an enum the core tests call).
- `run-M1.log` to `run-M3.log`: as above.
- `python3 scripts/test_make_undo_traces.py`: 36 tests OK (it did not say the traces were stale, so `make_undo_traces.py` was not run).

## Left for the next piece

Listings of the list's own folders other than the segments, read and judged not to read the list (so unchanged): `UndoRecovery.swift` 1358 and 1363 (`deleteUnneededContent`, the content/ folder): an error lists nothing and so deletes nothing, the safe side; `UndoRecovery.swift` 1383 (`deleteUnneededSegments`, `try? segmentNumbers()`): an error prunes nothing; `JournaledWrite.swift` 1415 (`UndoShadowStaging.tidyLeftovers`, the list's own notes folder): an error tidies nothing. None decides what the list holds.

Listings of WORKING folders with `try? ... contentsOfDirectory` or an enumerator (not this piece's): `UndoRecovery.swift` 499 (`keptOriginalFiles`), 649 (`foldersKeptAside`), 803 (`carryingMoveState`, enumerator); `UndoCheck.swift` 1288 (`removeAFolderLeftOut`), 1589 (`stepsOwnFilesInside`, enumerator), 1814 (`tidyLeftovers`, a `do`/`catch`); `UndoOpKinds.swift` 919 (`walk`), 1218 (`spellingListed`); `UndoWebsite.swift` 253 (`readRecord`).

## For the director

- No parked questions.
- Not this piece's, noted: a remembered newest segment that is gone at the NEXT read (between two reads, not between a listing and an open) is read as a shorter list on both platforms (see "For documentation 12"). The same reasoning as gap 2 says it should be unreadable (pruning never deletes the newest), but the newest that a previous read knew may legitimately stop being the newest only by a newer segment appearing, which `stillValid` already handles. If wanted, it is one more line in `stillValid` and in Windows' `ReadSegments` and a row both can run; it was not in the brief, so it was not built.
- A race between a read and a rename has no fair contract row on both platforms (no replay can place the swap at the same instant on both), so the folder-id rule is held by the `identifierFiles.unreadable` sentence and the Mac's unit tests only; no row was invented.
- Python: modelled, not skipped (the model's call answers `listUnavailable` and changes nothing; the model has no segments, so it is the reader's answer, not its mechanism).

## Self-check

1. Broke each fix and watched its test fail: M1 to M4, 4 RED of 4, lines above; every new test was also red on the base.
2. No timed waits: the seams are event hooks; no sleep in product or test.
3. Failure paths: nothing a teacher reads changes (switch off); an unreadable list is `couldNotRead`, which a shadow step records past (`rule.shadow`) and a live Undo answers `listUnavailable`; the row shows the list is not cleared after.
4. `dev` merged before proving: `origin/dev` was 0e12bc8ac (the base) at both points, no merge commit needed.
5. No number tuned by trial.
6. Contract cases run from the JSON (the replay dispatches the call by name); nothing outside the brief's scope changed (Mac files, contracts, documentation 09, the Python test, the ledger, these notes).
7. House style: the grep over every added Swift line is empty; `FileIdentity` and `Inspection` carry MARK sections.
8. Riding lows: none named in the brief.
9. The rename record is untouched; `undoJournalIsLive` untouched (off).
10. The new row runs in the Mac replay and the Python model, and is held on Windows by exact name (checked by script: the name is in `stackCases` and once in the ledger); it still fails there because `UndoStackContractTests` hits `Assert.Fail("a call this replay does not know: newestSegmentGoesWhileRead")` (line 488).
