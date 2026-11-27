# #899 W8b window B lows (pieces 17, 18a, 18b): the six lows of review 1

Branch `issue/899-w8b-window-b-lows` from `origin/dev` 6dc36fcea. Tests first at b3d51d8db. Merge of `origin/dev` before proving: none needed (`origin/dev` still 6dc36fcea); before hand-back: see "Runs".

## For PROGRESS

- W8b window B lows done: a test's stop is its own exception type (`UndoStepStoppedByATestException`, `Plantoir.Core.Undo`), and Rename folder keeps its record only for that and for a part-way stop, putting it back for every other exception from the make, as the Mac's `stepWasNotMade` and catch-all do. The unreadable clause gives the system's short reason with no path (`UndoLinks.ShortReason`).

## The six lows

1. **(17) The record after a non-I/O exception.** `UndoActionStep.Answer` throws `UndoStepStoppedByATestException` (a subclass of `InvalidOperationException`, so nothing that caught the old type changes) for `UndoOutcomeKind.StoppedByATest`. `SpecialFolderRenamer.Rename` now has: changed-since retry, part way (kept), stopped by a test (kept, rethrown), I/O and access (put back, `renameFolderNothingWasChanged`), and a catch-all (put back, rethrown as it came, the Mac's `catch { record.nothingWasChanged(); throw error }`). The brief's "I/O and access errors the Mac keeps it for": the Mac keeps the record only for `leftPartWay` and `stoppedByATest`; an I/O error puts it back on both, as it already did on Windows. Tests: `ABugsNullReferenceFromTheMakeLeavesNoRecord` (no record, `OneSectionRestore.RenameIsUnfinished` false), `ABugsArgumentExceptionFromTheMakePutsTheEarlierRecordBack` (byte for byte), and the guard `ATestsStopKeepsThisRunsRecord`. The bug is thrown from the door's `BeforeTheBegin` seam with the list live (in shadow the make writes plainly instead, so no exception leaves it).
2. **(18b) The unreadable reason.** `UndoLinks.ShortReason(error, fullPath)`: an error with the system's code (facility Win32) is said as `new Win32Exception(code).Message` ("Access is denied."), the Mac's `strerror`; any other keeps .NET's message with the full path said as its last name. Used by `UndoLinks.Look`'s catch and by `WhatIsAt`'s listing catch. The place is already the course's own (`section1/Assessments`). Test: `AnUnreadablePlaceIsToldWithAShortReasonAndNoPath`, under the test's temp root (under the account folder on the PC): `LookingAtAPlaceFails` hands over what the REAL `Look` said at the refused name of low 3, and the clause, sentence and trail line hold no `:\`, no backslash, no user name, no root.
3. **(18b) The real capture.** `ALookTheSystemRefusesKeepsItsReason`: `UndoLinks.Look(path, out said)` on a place the system truly refuses (`section1/not|a name`, a name Windows will not take: an `IOException`), CannotLook with a reason. A deny entry was tried first (ReadAttributes and ReadData on the folder, ReadData on its parent): on the PC the look still saw a Folder (run `w8b-wbl-a`), the same account reading past a deny that 18b's seam was made for, so the brief's ACL folder is not a look that fails there.
4. **The writer-scan label.** `UndoWriterScanTests.cs` `SpecialFolderRenamer.cs`: "written with all five keys (from, to, scope, moved, mayHaveMoved) since W8b-18a".
5. **Untrue sentences.** None left in `windows-app/` (searched for each). Documentation 12 about 18238 already says the old part-way line is no longer true (folded at integration-8). The `contracts/` ones are under "For the director".
6. **A record unreadable at the start.** No code change. `ARecordUnreadableAtTheStartIsRemovedByARefusal` pins today's behaviour: the claim reads a locked record as none, so a refusal removes it (the Mac's `try? Data(contentsOf:)` does the same).

## For documentation 12

- W8b window B lows: "Rename folder keeps its record only when the step was stopped by a test or stopped part way; any other exception from the make puts the earlier record back (the Mac's `stepWasNotMade`)." and "The part-way clause 'could not tell whether these are at the new name' gives the place as the course names it and the system's short reason, never a path."
- A record that cannot be read when a rename starts is read as none, so a refusal removes it, on both platforms (review 1, LOW 6; for the Mac line's owner).

## Must-fail lines

`vm-tools/guest/899-w8b-wbl-mustfail.json`, three rows, each RED in run `w8b-wbl-b` (see "Runs"). Script: `899-w8b-wbl-pc-run.ps1` with launchers `-a` and `-b`.

## Runs

- `w8b-wbl-a` (PC, 9c666947c, red half at b3d51d8db): RED 4 of 65 in `SpecialFolderRenamerTests` at the tests' commit (`ABugsNullReferenceFromTheMakeLeavesNoRecord`, `ABugsArgumentExceptionFromTheMakePutsTheEarlierRecordBack`, and the two deny-entry tests); at 9c666947c the two deny-entry tests still failed (the look saw a Folder: the PC's account reads past a deny), so they were rewritten on a refused name (1e8204f9f).
- `w8b-wbl-b` (PC, 1e8204f9f): both builds 0 errors; 348 of 348 passed in `SpecialFolderRenamerTests`, `RenameRecordShapeTests`, `FolderRenameApplyTests`, `UndoRenameFolderStepTests`, `NamedGapLedgerTests`, `UndoWriterScanTests`, `UndoOpKindsContractTests`, `UndoStackContractTests`; must-fail 3 of 3 RED (row 1: both `ABugs…`; row 2: `AnUnreadablePlaceIsToldWithAShortReasonAndNoPath`; row 3: `ALookTheSystemRefusesKeepsItsReason`); restored 348 of 348; HEAD unchanged, status clean, lock released (ours).
- Merges of `origin/dev`: none needed before proving or before hand-back (`origin/dev` stayed 6dc36fcea).

## Left for the next piece

- `UndoActionStep`'s one-file path still answers `UndoSwapResult.StoppedByATest` as `UndoStepRefusedException("stopped by a test")` (about line 805). Rename folder never takes that path (its folder moves go through `MakeAsOps`), so no record is touched by it; left as it is.

## For the director

- `contracts/` not changed. Review 1's LOW 5 sentences, each still untrue of Windows, for a contract pass:
  - `contracts/README.md` about 2299 to 2302: "Windows' one part-way line until W8 is … its stop after moving some of the copies writes no line." True: Windows writes the Mac's three part-way lines. About 2285: "Windows still says both until its own piece (W8)": true now that neither is said on Windows since 15b and 18b.
  - `file-formats.json` → `folderRenameRecord`: example 1's name "what Windows writes today" should be "what a released Windows build writes" (bytes unchanged); `moved`'s why "Absent means the record does not say (Windows, or an older Mac build)" should be "(a released Windows build, or an older Mac build)"; in the note, only the reader and writer sentences change (keep the bytes clause).
  - `shared-rules.json` `folder renamed` → `carries`: "(one Windows or an older build wrote, …)" should be "(one a released Windows build or an older Mac build wrote, …)", in addition to 18b's "On Windows until W8" sentence.
- Nothing parked.

## Self-check

Tests first (b3d51d8db); one function per rule (the short reason is `UndoLinks.ShortReason`, called by both catches; "is it a link" stays `UndoLinks.Look`); no ledger row; no timed waits; no lock removed that this run did not take.
