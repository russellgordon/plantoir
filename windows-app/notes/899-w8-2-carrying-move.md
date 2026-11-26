# #899 W8-2: a move carries the edits at or inside its `to` (PARTIAL, 2026-11-26)

Base: `origin/issue/899-w8-1-leaving-place-named` at 66659cf87, which already holds `origin/dev` 0e12bc8ac, so no merge commit was needed before the proof (`git merge-base --is-ancestor origin/dev HEAD`); none needed before hand-back either (checked again at the end).

**This piece stopped at a committed point that keeps carrying moves UNREADABLE** (brief: "If it grows past that, stop at a committed point that keeps carrying moves UNREADABLE"). `UndoStep.WholeOpsStandAlone` is unchanged: an op at or inside a move's `to` is still a barrier, so nothing the check or the swap cannot yet handle is readable.

## For PROGRESS

- `UndoOp.PartInside(place, path)` (`Plantoir.Core/Undo/UndoFormat.cs`): the ONE comparison for "at or inside", the mac's `UndoOp.partInside` (U4b2-9): split on `/`, each part compared by `ToLowerInvariant` ordinal, the rest returned as the path spells it ("" for the place itself, null for neither). `UndoOp.PlacesOverlap` now calls it both ways; it was a second spelling comparison (`StartsWith(other + "/")` on the lowered strings), same answers.
- A folder move's `listingSha` is no longer one of the op's `Blobs` (`opKinds.move`: "The moved content is never a blob: the item itself is what moves"). Before, `UndoFormat.ReadOp` added it for every op, so the door's vetting (`UndoDoor.cs` about 330) refused every folder move made through `Perform` as `notReadable`, as the mac's `JournaledWrite.vet` did until U4b. A `createTree`/`removeTree` still names its listing as a blob (pruning keeps it: `ATreesListingIsStillOneOfItsBlobs`, and `UndoPruningTests` green).

## For documentation 12

- Under "What W8 owes from U4b2-9": Windows' one comparison is `UndoOp.PartInside` (since W8-2); `PlacesOverlap` is built on it. Every later W8 piece calls it, never a new comparison.
- The U4b notes' worry "A folder move's listingSha is not a blob … Check that Windows' vetting does not do the same": it did; fixed in W8-2 (`UndoCarryingMoveTests.AFolderMoveIsMadeThroughTheDoorWithNoListingBlobAndUndone`).

## Tests (new class `Plantoir.Tests/UndoCarryingMoveTests.cs`)

- `PartInsideComparesEachPartWithoutRegardToCaseAndKeepsTheRestAsSpelled` (4 rows), `PartInsideIsNullForAPartThatOnlyBeginsAlikeOrAPathOutside` (4 rows, `Media` against `Mediahouse/a.md` included), `PlacesOverlapIsPartInsideEitherWay`.
- `AFolderMovesListingIsNotOneOfItsBlobs`, `ATreesListingIsStillOneOfItsBlobs`.
- `AFolderMoveIsMadeThroughTheDoorWithNoListingBlobAndUndone` (real door, made then undone).

Red first (run `899-w8-2-red`, ref e5c1037a4, `PartInside` a throwing stub): 10 failed of 12. The PartInside rows failed at lines 24 and 34; `AFolderMovesListingIsNotOneOfItsBlobs` at line 56 (`Assert.Empty(read.Blobs)`); the door test at line 87 (`Perform` refused, not `Applied`). The two that passed are the ones the old code already satisfied (`PlacesOverlapIsPartInsideEitherWay`, `ATreesListingIsStillOneOfItsBlobs`).

## Must-fail lines

`vm-tools/guest/899-w8-2-mustfail.json`, three rows of the brief's eight (the three this piece's code carries): 3 RED of 3 (see "Runs").

1. `PartInside` comparing case.
2. `PartInside` matching a prefix that is not a whole part.
3. The listing named as a blob again.

The other five (an edit inside `from` made readable; the edit staged before the move; the edit taken back after the move; the move judged without the override; a refusal naming `from` before an Undo) need code this piece did not write.

## Runs

- `899-w8-2-red` (PC, ref e5c1037a4): both builds 0; `UndoCarryingMoveTests` 10 failed, 2 passed, as above. Lock taken and released by this run.
- `899-w8-2-green2` (PC, ref d7d542962; waited 23 minutes for the lock held by `int-d26-1`, left alone): both builds 0; the brief's classes plus `UndoOpKindsContractTests`, 894 passed, 0 failed, 0 skipped. Must-fail 3 RED of 3 (row 1: 3 failed of 12; row 2: 3 of 12; row 3: 2 of 12), each restored by `git checkout`; restored run 894 passed; HEAD-AFTER SAME, status clean. Lock taken and released by this run only.

## Left for the next piece

Everything of the brief past the comparison and the listing blob, for a W8-2 continuation (it must land with piece 3, order file window 1):

- **Readability**: `WholeOpsStandAlone` letting an op at or inside a move's `to`, after it, stand (a `MoveCarries(move, edit)` as the mac's `UndoOp.moveCarries`, `UndoFormat.swift:1046`: edit kinds writeFile/editLine/replaceText/editJSON only, `PartInside(to, path) != null`, `!PlacesOverlap(from, path)`; the case-only branch is piece 5's, the link branch piece 6's).
- **The check** (`UndoCheck.Plan`): a `Carriers(ops)` map; forward, the carried edit read at `placeBeforeTheMove` and the move's target put FIRST (the mac's `leadingTargets`); backward, the move judged with the listing override (each carried file as `working[path]`, matched to the listing by `PartInside`, never as spelled); a moved item's refusal at `placeAsFound` (`to` before an Undo, `from` before a Redo) unless W8-1's leading-out place applies.
- **The swap**: a carried edit staged only at its turn (after the move has gone in), going forward. The Ready result's `Whole` list is today always swapped after the files; forward needs the carrying move first.
- **A trap found here, for whoever continues**: going backward, the swap keeps the carried page's original as a `-orig` hard link BESIDE it, i.e. inside the moved folder, and that file is still there at the move's last look (`SwapAWholeOp`, `MoveHere`: `UndoMoveSides.Read` of the whole folder), so an Undo of a carried edit through the real door is refused as changed since until piece 3's own-files rule covers the swap's last look AND the swap follows those files when the folder moves (else the tidy misses them). So the stack row "Undo takes the edit back, then the move" cannot pass in piece 2 alone; the brief's "Undo, Redo and Undo Undo of a carried edit through the real door" needs piece 3's swap part, or that part moved into piece 2.
- **The replay**: key `movedFolder`, calls `moveAFolderWithAPageEditedInside`, `addAFileInsideTheMovedFolder`, `editThePageInsideByHand`, `stepEditingInsideAMovesFrom`; the five `Reason899W8U4b` rows; lesson 4's check of every held row carrying `movedFolder`.
- Must-fail rows 4 to 8 of the brief.

## For the director

- The brief's budget (130k) could not hold the whole invariant; this piece stopped with carrying moves unreadable (safe). The continuation should be briefed with the trap above: piece 2's door tests and its first stack row need the swap's last look to leave out THIS swap's own kept `-orig` inside the folder, and to follow it through the rename (piece 3's brief has this as "each swap's last look"). Recommendation: move the swap's own-files part of piece 3 into the continuation of piece 2, and leave piece 3 the plan-time and recovery parts, the replay call `leaveAKeptCopyInsideTheMovedFolder` and its two M1 rows.
- No `contracts/` change. No question for Russell.

## Self-check

1-6 (NIGHT3): one piece's scope only, tests red first, no timed waits, no interface change, no confirmations, notes written. 7. No fixture row changed (none in scope). 8. No writer-scan change. 9. No riding lows. 10. Not reached (no step converted). 11. No held row cleared; `Reason899W8U4b` rewritten so it no longer names the listing blob as owed. 12. No key added. 13. One function: `UndoOp.PartInside`; `PlacesOverlap` calls it. 14. No run left going; this piece's two runs each released only their own lock; one waiting start (`899-w8-2-green`, ref 04708bbe1) was stopped before it took the lock, to restart on d7d542962; the lock `int-d26-1` held then was not touched.
