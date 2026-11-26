# W8-8: recovery puts back what a hand edit is not in the way of, a carried page included (#899, Windows #949)

Branch `issue/899-w8-8-recovery-hand-edit-carried`, from piece 7's `origin/issue/899-w8-7-recovery-of-a-carrying-move` at f32ade9f9 (on `origin/dev` 06e067fbe). `origin/dev` did not move during the piece (06e067fbe at the start and at hand-back), so there is no merge commit. Closes merge window 6 (pieces 7 and 8 merge together).

## First, check (night25-7 sweep, "For W8")

Windows' settle already puts back every place not in the way, and needed no product change for this piece:

- `Plantoir.Core/Undo/UndoRecovery.cs` `Settle`, about lines 950 to 956: each place is sorted into `inTheWay` (Neither), the start state, or `endPaths`. In the `else` branch (about 983) the put-back plan is made from `endPaths` alone (`opsToPutBack`, about 985) whether or not `inTheWay` is empty. Then the step is closed interrupted, `changedByHand`, naming `PathsOnly(inTheWay)` in the ops' order (about 1094). This is the mac's `settle` (`opsToPutBack`, `pathsOnly(inTheWay)`).
- A carried page changed by hand already puts its move in the way. `CarryingMoveState` (about 845) takes a carried edit back only when the page is as the step left it (`StateOf(edit, current) == After`). A page that is neither is left as it is, so the folder's listing matches neither side of the move, and `WholeStateOf` answers Neither. The move is named by its `PlaceName` (its `from`) before the page, because it comes first in the ops.
- The proof: both new tests in `UndoRecoveryTests` passed on the product as piece 7 left it (run `899-w8-8-red`), and must-fail 1 to 3 show that each of the three rules is what makes them pass.

## For PROGRESS

- Recovery of a step that moves a folder and edits a page inside it, when the teacher has changed a page by hand since it stopped: every place not in the way is put back. When the carried page was changed, the move is in the way too, and the folder stays where it was moved with the page as the teacher left it. The step is interrupted naming the move by its `from`, then the page. Windows already did this once piece 7 had landed; piece 8 taught the replay `handEdit: carried` and proved it.

## For documentation 12

(Not edited by this piece, as the COMMON says.) In "What W8 owes from U4b2-13":
- "Held:" is no longer true. Neither row is held: `handEdit: second` left at W8-7, `handEdit: carried` at W8-8, and `Reason899W8U4b2HandEditCarried` is gone.
- "What W3/W8 owe (check)": done. Windows' settle puts back every place not in the way (`UndoRecovery.Settle`, the `opsToPutBack` from `endPaths`). The carried row needed no product change, because `CarryingMoveState` leaves a carried page that is neither as it is.
- In "What W8 owes from U4b2-9", the paragraph "Which held rows fail on Windows today, and why" still names the `handEdit: carried` row as held (W8-8). Drop that clause.

## Tests, red first

- `UndoRecoveryContractTests.Walk` knows `handEdit: carried` (with `withAMovedFolder`). It calls `UndoKindsForTheCases.EditTheCarriedPageByHand`, the mac's `editTheCarriedPageByHand`: a.md under `renamed` if that folder exists, else under `media`, with every line starting `Line one: ` set to `Line one: by hand.`. Any other unknown value still fails by name ("a key this replay does not check: handEdit …").
- `UndoKindsForTheCases.Holds` (what `movedFolder` says of a.md) now reads as the mac's `movedFolder` does: `Line one: new.` gives new, `Line one: old.` gives old, anything else gives byHand. Before, only the exact text `Hand.\n` was byHand, so `Line one: by hand.` read "something else". The stack replay's `editThePageInsideByHand` (`Hand.`) still reads byHand.
- New, in `UndoRecoveryTests` (the brief's "piece 7's recovery test class": piece 7 added no class of its own, so these sit with the recovery tests beyond the contract):
  - `ACarriedPageChangedByHandPutsItsMoveInTheWayAndEverythingElseIsPutBack`: stopped before swap 3, a.md changed by hand. Both pages are put back, `renamed, byHand`, a.md byte for byte as edited, interrupted naming `[courses/TST1O/media, courses/TST1O/renamed/a.md]`, nothing staged.
  - `APageOutsideTheFolderChangedByHandLeavesTheMoveToBePutBack`: stopped before swap 2, second changed by hand. The folder and first are put back (`media, old`), second is as edited, interrupted naming only second.
- Red, run `899-w8-8-red` at 9dc350bf7 (the replay taught, the row still in the ledger): **1 failed of 311**. The failure was the held `handEdit: carried` row, which now passes and so failed `HeldCaseStillStopsAtItsGap` ("is ledgered as not built here yet … it now EXISTS"). The two new tests passed (see "First, check").

## Ledger

- The `UndoRecoveryCases` row "U4b2-13: … the page inside the moved folder is then changed by hand …" is gone, and so is `Reason899W8U4b2HandEditCarried`, which nothing else used. No other reason sentence named `handEdit carried`. `Reason899W8U4b`'s sentence names only Rename folder's recorded steps and traces as still owed, which is still true.
- Lesson 4: no key was added to `KeysChecked` (`handEdit` was there already). No row is held under any reason carrying `handEdit: carried` now.

## Must-fail lines

`vm-tools/guest/899-w8-8-mustfail.json`, run `899-w8-8-all` from the clean committed 4df66634d. Each sabotage was restored by `git checkout`. The result was **3 RED of 3** (STATUS clean, HEAD-AFTER SAME), and once restored **311 passed**:

1. Nothing put back when one place is in the way (`endPaths` put back only when `inTheWay` is empty): 14 failed, the plain-page hand-edit rows and both U4b2-13 rows and tests among them.
2. The carried move not put in the way (`CarryingMoveState`'s Neither answered After): 2 failed, the `handEdit: carried` contract row and `ACarriedPageChangedByHandPutsItsMoveInTheWayAndEverythingElseIsPutBack`.
3. The line naming the page before the move (the `changedByHand` paths ordered backwards): 2 failed, the same two.

## Runs

The PC (LENOVO 20QES70500, i5-8365U, 16 GB, Windows 11 Pro 26200). Each run took and released the turn lock (`LOCK-RELEASED`). Each run did both builds, then the classes `UndoRecoveryContractTests`, `UndoRecoveryTests`, `UndoRecoveryReviewFixesTests`, `NamedGapLedgerTests`, `UndoWriterScanTests`, `UndoOpKindsContractTests` and `UndoStackContractTests` (the last because `Holds` is shared with it). There was no harness run.

- `899-w8-8-red`: 9dc350bf7, 1 failed of 311 (above).
- `899-w8-8-all`: 4df66634d, **311 passed, 0 failed, 0 skipped**, then must-fail 3 RED of 3, and 311 passed once restored.

## Left for the next piece

- Piece 7's note: recovery's put-back plans only the ops whose place is at the end (`endPaths`), and reads each at the path it names. A carried edit put back on its own while its folder is at `from` would be read at `to`. Judged here: **not changed.** The mac's `settle` does exactly the same (`opsToPutBack` read at `op.placeName`, `UndoRecovery.swift` about 1009 to 1023), and no contract row reaches it. Only a teacher moving the folder back by hand, with the carried edit then judged at its end, reaches it. Changing it on Windows alone would be a difference nobody chose. If it is wanted, it is a mac row first (a `recoveryCases` row whose hand change is the folder moved back), then Windows copies it.
- Recovery of a case-only move, or of a link's move, killed part way: there is still no contract row on the mac (pieces 5 and 6's "Left"). No row was invented.

## For the director

- No product change was needed: piece 7's recovery already settled both U4b2-13 rows. This piece is the replay, the reading of `movedFolder`, two tests, the ledger, and the must-fail that shows the three rules are what pass the rows.
- Documentation 12 needs the three corrections under "For documentation 12" (two in U4b2-13's section, one clause in U4b2-9's).

## Self-check

1 to 6 (NIGHT3's): tests first (red above); one invariant; no teacher-facing change; no timed waits; pushed after each step; no `contracts/` change. 7: the replay rows are green, the ledger row is gone, and the reason constant is gone. 8: the writer scan is unchanged (no writing call moved), and `UndoWriterScanTests` is in the run. 9: there were no riding lows. 10: n/a (no action converted). 11: done, and the constant is gone. 12: no key was added (Ledger, above). 13: no new comparison; the test helper uses `Directory.Exists` as `MovedFolder` beside it does, and the product calls `UndoOp.PartInside` and `UndoLinks.Look` as before. 14: no run is going, each lock was released by its own run, and no other lock was touched.
