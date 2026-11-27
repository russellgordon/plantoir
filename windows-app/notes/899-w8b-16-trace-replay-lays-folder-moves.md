# #899 W8b-16: the action-trace replay lays folderMoves and makes the moves first (Windows #949)

Branch `issue/899-w8b-16-trace-replay-lays-folder-moves`, built on 15b's `origin/issue/899-w8b-15b-rename-folder-is-one-step` (974c0eb53). `origin/dev` 8046ca2e8 merged first, in fb5eb10ac (clean). Before hand-back `origin/dev` was still 8046ca2e8, already in the branch, so no second merge commit was needed.

Test code only: no product change was needed.

## What landed

- `UndoActionTraceContractTests.WhatThisReplayDoesNotMake(recorded, byTheWindowsAction)` is the guard, as one function: `moves` stops every step (the rollover, W7c); `folderMoves`, `members` and `trees` stop only a step no Windows action makes (not in `WindowsActionsOnTheMacFixture.Converted`), `folderMoves` named first. Rename folder's two steps are converted (15b), so their traces now run.
- Before the action, each `folderMoves` entry is laid at its `from` as its listing (its `folders`, and each `files` text by its path inside). A recorded file inside a move's `to` (`UndoOp.PartInside`, the one comparison) is carried: its before is NOT written at its new place. The Windows action (`SpecialFolderRenamer.Rename` through `Run`) makes the step.
- Hashed in `afterUndoingAll` and `final`: each folder at its `from` and `to` (by its listing's SHA-256, null when absent, the existing `Hashes`), and every page of its listing at both places.
- At the action: besides the op kinds (`move` first), the step's `move` ops are checked by from, to and `listingSha` in the recorded order (`LastBeginsFolderMoves`); `LastBeginsFilePaths` leaves `move` ops out (they name no file).
- A refused Undo is named by the move's `to`, a refused Redo by its `from`: the trace's own `path` check, met by the door's `UndoOp.PlaceAsFound` (action-154 `courses/ICS3U/Ideas`, action-152 `courses/ICS3U/Concepts`).
- New fact `AStepWithFolderMovesStopsByNameUnlessItsWindowsActionMakesIt`: every recorded step with `folderMoves` stops at "folderMoves" when not converted and goes through when converted; a step with `moves` stops at "moves" either way.
- Ledger: action-151 to 162 out of `UndoActionTraces`; `Reason899W8U4b` held nothing more and is removed. The ledger comment above the rollover rows and the `UndoActionTraces` summary are rewritten (only the rollover's `moves` is held there now).

## For PROGRESS

- W8b-16: `UndoActionTraceContractTests` replays Rename folder's twelve traces (action-151 to 162) through the real Windows Rename: each folder laid at its from as its listing, no carried page written at its new place, the moves checked by from, to and listingSha, each folder and its pages hashed at both places. `Reason899W8U4b` is gone.
- Correction for `windows-app/PROGRESS.md` about line 916 (round three, E): the held traces are named there as of that day; from W8-11 the replay's guard is `moves` and `folderMoves`, and from W8b-16 Rename folder's traces (action-151 to 162) pass; only the rollover's (action-121 to 132, `moves`) are held.

## For documentation 12

- "What W8 owes from U4b2-11", first bullet (about line 18302): for "(`UndoActionTraceContractTests` checks `moves`, `members`, `trees` per trace; ...)" read: "(`UndoActionTraceContractTests` stops a trace by name, per trace, at `moves`, and, for a step no Windows action makes, at `folderMoves`, `members` or `trees`; since W8b-16 the two steps' traces pass, below)".
- "What W8 owes from U4b2-12", second bullet (about line 18307), replace with: "**Since W8-11** the guard is `moves` and `folderMoves`, so the twelve traces stopped with "a step this replay does not make yet (folderMoves)"; a `members` or `trees` step not converted stops at its own name after it. **Since W8b-16** the guard (`WhatThisReplayDoesNotMake`) stops a `folderMoves` step only when no Windows action makes it, and all twelve traces pass: built as the five steps below say (step 3 by the Windows Rename itself, checked by the op kinds and by each move's from, to and listingSha)." The sentences "The guard does not name `folderMoves` itself, because `members` comes first" and "Removing `members` from the guard alone would NOT let these traces through" are no longer true and go.
- "What W8 owes from U4b2-12", first bullet: the twelve traces are out of the ledger and `Reason899W8U4b` is removed (W8b-16).

## Must-fail lines

`vm-tools/guest/899-w8b-16-mustfail.json`, run in `w8b-16-a` on 61fae66f9, **5 RED of 5**, restored at 435 of 435:

1. A carried page's before written at its NEW place (the `carried` skip removed): RED, 12 failed in `UndoActionTraceContractTests` (every Rename folder trace): `RenameException: There is already something called "Ideas" beside it. Move or rename that first.`
2. The folder moves made after the file ops (`UndoActionStep.MakeAsOps`, the moves' loop moved after the files): RED, 12 failed: `RenameException: a page could not be saved.` (the door refuses a carried edit before its move).
3. The refusal named by the other side (`UndoCheck`, `op.PlaceAsFound(!backward)`): RED, 2 failed: `action-154, call 4 (undo): named courses/ICS3U/Concepts` and `action-152, call 6 (redo): named courses/ICS3U/Ideas`.
4. `folderMoves` removed from the guard for every step: RED in `AStepWithFolderMovesStopsByNameUnlessItsWindowsActionMakesIt`: `renameFolder: not stopped by folderMoves`.
5. W8-9 to 14 review 1, LOW 2 (`saveCourseSettings` out of `Converted`): RED, 6 failed (action-133 to 138), each `action-133: a step this replay does not make yet (members)`: the clause stops it by name, never at the final hashes.

## Runs

- `w8b-16-a` (PC, `899-w8b-16-pc-run.ps1`, mode `classes,mustfail`, 2026-11-27 01:27 to 01:35), one lock taken and released by the run itself:
  - **Tests first** at cf4d53c45 (the tests' commit, before the replay changed): RED, 13 failed of 165 in `UndoActionTraceContractTests`: action-151 to 162, each at the guard, `action-151: a step this replay does not make yet (folderMoves)` (`ReplayTheActionTrace`, the `Assert.Fail` after `WhatThisReplayDoesNotMake`), and `AStepWithFolderMovesStopsByNameUnlessItsWindowsActionMakesIt` (`stopped although its Windows action makes it`).
  - At 61fae66f9: both builds 0 errors. **435 passed of 435**, 0 skipped: `UndoActionTraceContractTests`, `UndoActionStepsOnWindowsTests`, `NamedGapLedgerTests`, `UndoWriterScanTests`, `UndoOpKindsContractTests`, `UndoStackContractTests`. The rollover's held rows (action-121 to 132) still stop at "(moves)" (`HeldCaseStillStopsAtItsGap` passes for them).
  - Must-fail as above; restored 435 of 435; HEAD-AFTER the same, status clean.
- No lock was held by anyone when I started; I removed none that was not mine.

## Left for the next piece

- 21: a linked place of the folder (15b's pinned `cannotTellNow` test); no trace of a linked rename is recorded yet, so nothing in this replay waits on it.

## For the director

- Parked: nothing.
- Self-check (W7b2's list, then W8's):
  - 7/11: the twelve trace rows pass and are out of the ledger; `Reason899W8U4b` is gone; the two comments that named Rename folder's traces as held are rewritten; no other reason named the trace guard.
  - 8: no writing call moved; `UndoWriterScanTests` run.
  - 9: LOW 2 of W8-9 to 14 review 1 is must-fail row 5; the day26-6 documentation 12 low is above under "For documentation 12", PROGRESS 916 under "For PROGRESS".
  - 10: the step's order is checked: moves first (op kinds and `LastBeginsFolderMoves`), then the files in the recorded order.
  - 12: no `KeysChecked` key added. Every row still held in `UndoActionTraces` (action-121 to 132) was run and still stops at "(moves)".
  - 13: at or inside is `UndoOp.PartInside`; the refusal's place is `UndoOp.PlaceAsFound`.
  - 14: no run going, no lock held, none removed that was not mine.
