# #899 W8-2: a move carries the edits at or inside its `to` (2026-11-26; first writer, then W8-2b)

Base: `origin/issue/899-w8-1-leaving-place-named` at 66659cf87, which held `origin/dev` 0e12bc8ac. The first writer stopped with carrying moves unreadable (`PartInside`, the listing blob: commits e5c1037a4 to 27806c85f). **W8-2b** (brief `2026-11-26-899-w8-2b-carrying-move-continued.md`) continued on the same branch and did steps 1 to 5: carrying moves are now readable, judged and swapped. Merge of `origin/dev` (253f8915f) before the last proof and hand-back: 1e4c270d3, clean.

## For PROGRESS

- `UndoOp.PartInside(place, path)` (`Plantoir.Core/Undo/UndoFormat.cs`): the ONE comparison for "at or inside", the mac's `UndoOp.partInside` (U4b2-9): split on `/`, each part compared by `ToLowerInvariant` ordinal, the rest returned as the path spells it ("" for the place itself, null for neither). `UndoOp.PlacesOverlap` calls it both ways.
- A folder move's `listingSha` is no longer one of the op's `Blobs` (`opKinds.move`). Before, the door's vetting refused every folder move made through `Perform` as `notReadable`, as the mac's `JournaledWrite.vet` did until U4b. A `createTree`/`removeTree` still names its listing as a blob.
- **W8-2b: a move carries the edits at or inside its `to`** (`opKinds.wholeOps`' one exception, the mac's U4b):
  - Readability: `UndoOp.MoveCarries(move, edit)` (the mac's `moveCarries`: writeFile, editLine, replaceText or editJSON; no from, to or target; `PartInside(to, path) != null`; `!PlacesOverlap(from, path)`). `UndoStep.WholeOpsStandAlone` lets such an edit stand when it comes AFTER the move. Before the move, or inside `from`, it is still a barrier. A case-only move carries nothing yet (its two places overlap: piece 5); a link's move is not readable on Windows (piece 6).
  - The check (`UndoCheck.Plan`): `UndoCheck.Carriers(ops)`. Going forward, a carrying move that goes in now is put in `Ready.Leading`, and each carried file is read at `UndoOp.PlaceBeforeTheMove` and marked in `Ready.StagedAtItsTurn`. Going back, the move is judged with each carried file, as taken back, in place of its listing entry (`WholeStateOf(..., overridingTo)` to `UndoMoveSides.Read(..., overriding)`, matched by `PartInside`, the disk's spelling kept). Every move's refusal (changed since, cannot tell) names `UndoOp.PlaceAsFound(backward)`: `to` before an Undo, `from` before a Redo. W8-1's leading-out place still comes first.
  - The swap: `UndoDoor.TargetsOf` orders Leading, then the files, then the other whole ops. Recovery's put-back now uses it too, so a leading move is never dropped there. A target with `StagesAtItsTurn` is staged just before its own swap, once the move has made its folder. Going back, the edit is swapped first, then the move.
  - The swap's own files inside the moved folder (the part of piece 3 taken here; see "For the director"): before a `MoveHere`, and before a reversal's rename back, the swap lets go the handles of ITS OWN staged and kept files inside the folder (Windows will not rename a folder with a file open below it) and leaves them out of the move's last look (`ownLeftOut`, as `Absent` overrides). After the rename it follows them (`UndoStagedFile.MovedTo`: the file identity kept, removed by name and identity from then on), so its tidy and a reversal find them where they are.

## For documentation 12

- Under "What W8 owes from U4b2-9": Windows' one comparison is `UndoOp.PartInside` (since W8-2); `PlacesOverlap` is built on it. Every later W8 piece calls it.
- The U4b notes' worry "A folder move's listingSha is not a blob … Check that Windows' vetting does not do the same": it did; fixed in W8-2 (`UndoCarryingMoveTests.AFolderMoveIsMadeThroughTheDoorWithNoListingBlobAndUndone`).
- Windows carries edits since W8-2 (`MoveCarries`, `Carriers`, `PlaceBeforeTheMove`, `PlaceAsFound`, the listing override in `UndoMoveSides.Read`, `Ready.Leading`, `StagesAtItsTurn`). A Windows-only fact for the mac to KNOW: a swap must let go of every handle it holds on its own staged and kept files inside a folder before it renames that folder (the access-denied measurement in `UndoStagedFile`'s summary). From then until the swap ends, those files are removed by name and file identity, not by handle; the folders of the swap's other pages keep their handles.

## Tests (new class `Plantoir.Tests/UndoCarryingMoveTests.cs`)

- First writer: `PartInsideComparesEachPartWithoutRegardToCaseAndKeepsTheRestAsSpelled` (4 rows), `PartInsideIsNullForAPartThatOnlyBeginsAlikeOrAPathOutside` (4 rows), `PlacesOverlapIsPartInsideEitherWay`, `AFolderMovesListingIsNotOneOfItsBlobs`, `ATreesListingIsStillOneOfItsBlobs`, `AFolderMoveIsMadeThroughTheDoorWithNoListingBlobAndUndone`. Red first (run `899-w8-2-red`, ref e5c1037a4): 10 failed of 12.
- W8-2b: `AnEditInsideAMovesToAfterTheMoveIsCarriedAndStands`, `AnEditInsideAMovesToBeforeTheMoveIsABarrier`, `AnEditInsideAMovesFromIsABarrier`, `AWholeOpInsideAMovesToIsStillABarrier`, `ACarriedEditIsMadeUndoneRedoneAndUndoneAgainThroughTheDoor` (no staged file left), `ACarriedNewPageIsTakenOutAndThenTheFolderMovedBack` (a removed page's kept original holds its folder's handle until let go before the move), `ARefusedUndoNamesTheMovedFolderWhereItIsNow`. Red first (run `899-w8-2b-red`, ref 390dc8132, `MoveCarries` a stub returning false): 4 failed of 19, at lines 120 (`Assert.True(UndoOp.MoveCarries(...))`), 174, 200 and 219 (`Perform` not `Applied`: the step unreadable). The three barrier tests passed there, as the old code already satisfied them; must-fail row 4 proves them.
- The replay (`UndoStackContractTests`): the calls `moveAFolderWithAPageEditedInside`, `addAFileInsideTheMovedFolder`, `editThePageInsideByHand`, `stepEditingInsideAMovesFrom`, and the key `movedFolder`.

## Ledger

- Five `UndoStackCases` rows under `Reason899W8U4b` pass and are gone: "an edit inside a moved folder: Undo takes the edit back, then the move"; "…: undone and redone, the move goes in before the edit"; "a file added inside the moved folder since: …"; "the page inside the moved folder edited by hand since: …"; "an op naming a path inside the place a move leaves: …".
- `Reason899W8U4b` rewritten: it no longer names those four calls or the stack key `movedFolder` as owed, says what Windows now does, and names what is still owed in the stack cases (the two M1 rows and `leaveAKeptCopyInsideTheMovedFolder`, W8-3). Its recovery clause (`withAMovedFolder`, `movedFolder`, `keptCopyLeftInsideTheFolder`) is unchanged: the recovery replay was not taught `movedFolder`. No other reason names a call or key taught here.
- Lesson 4, `movedFolder` added to the stack replay's `KeysChecked`: every row still held that carries it (the two M1 rows, the made-folder rows, the case-only rows, and the link rows) stops first at a call this replay does not know (`leaveAKeptCopyInsideTheMovedFolder`, `moveAFolderWithAFileMadeInANewFolderInside`, `moveAFolderHoldingAnEmptyFolder…`, `renameAFolderInCaseOnly`, `moveALinkToAFolder`). The run's `EveryStackCase` is green, so each still stops at its accepted gap.

## Must-fail lines

`vm-tools/guest/899-w8-2-mustfail.json`, ten rows: the brief's eight plus two for piece 3's swap part. Run `899-w8-2b-mf` (ref c73a04f56): **10 RED of 10**, each restored by `git checkout`.

1. `PartInside` comparing case.
2. `PartInside` matching a prefix that is not a whole part.
3. The listing named as a blob again.
4. An edit inside `from` made readable (`MoveCarries`).
5. The carried edit staged before the move (`StagesAtItsTurn` ignored at staging).
6. The carried edit taken back after the move (the carrying move leading going back too).
7. The move judged without the listing override.
8. A refusal naming `from` before an Undo (`PlaceName` for `PlaceAsFound`).
9. Piece 3's swap part: the swap's own files inside the folder counted at its last look.
10. Piece 3's swap part: the swap's own files not followed when the folder moves.

## Runs

- `899-w8-2-red`, `899-w8-2-green2`: the first writer's (894 passed then).
- `899-w8-2b-red` (PC, ref 390dc8132): both builds 0; `UndoCarryingMoveTests` 4 failed, 15 passed, as above.
- `899-w8-2b-green1` (PC, ref c73a04f56): both builds 0; the brief's classes plus `UndoOpKindsContractTests`: 901 passed, 0 failed, 0 skipped.
- `899-w8-2b-mf` (PC, ref c73a04f56): 10 RED of 10 (row 1: 3 failed of 19; 2: 3; 3: 5; rows 4 to 10 with the stack replay too, of 146: 2, 7, 4, 4, 1, 4, 4); restored run 901 passed; HEAD-AFTER SAME, status clean.
- NOT run: a green run on the merge of `origin/dev` (1e4c270d3). The coordinator stopped the piece at its budget before it; the merge was clean, and it touched none of the Undo product files (only `TodaysClassOnTheFrontPage.cs`, `NamedGapLedger.cs` +8 lines, three test files and the contracts). The next run of this branch must be on 1e4c270d3 or later.
- Every run took the lock `C:\vm-setup\wt-compare.lock` itself and released only its own (the owner file names `899-w8-2 <label>`).

## Left for the next piece

- **Before anything else:** a green PC run of the brief's classes on the merge commit 1e4c270d3 (or later), not yet run (budget). Then the review.

- **W8-3** (base this branch): the plan-time and recovery parts of "the step's own files inside a moved folder": a kept copy an EARLIER undo or redo of the step left inside the folder (`.<page>.plantoir-undo-<seq>-…`, any of the step's swaps), left out of the plan's judgement of the move on either side (the mac's `stepsOwnFilesInside(_, seq:)` and `UndoCheck.plan(ownSeq:)`), the tidy finding them where the folder is now, the kept original of a carried page looked for where the page is now, the replay call `leaveAKeptCopyInsideTheMovedFolder`, its two "U4b, M1:" rows, and must-fail rows "the own files counted" (at the plan), "any step's files left out, not only this step's", and "the kept original of a carried page looked for at the old place". Piece 3's "the files not followed when the folder moves" and the swap's last look are DONE here (rows 9 and 10): within one swap, its own files are left out and followed. Recovery's state (piece 7) is not touched.
- The swap's `MoveHere` refusal still names `target.RelativePath` (the destination) when the pair changes in the instant between the plan and the rename; the plan's refusal, which is what a teacher meets in every replayed case, names `PlaceAsFound`. Whether the swap's late refusal should name the place as found too is for the reviewer (the mac names its target there as well, as far as read; not changed here).

## For the director

- What of piece 3 was taken (the director's decision of 2026-11-26): ONLY the swap's own files, within one swap: `UndoSwap.SwapStaged`'s `LetGoOwnFilesInside` (its own staged `-new` and kept `-orig` files inside the place a `MoveHere` moves, found by `PartInside`, handles let go, left out of `UndoMoveSides.Read` at the last look) and `FollowTheMove` (renamed with the folder, both on the move and on a reversal's rename back), plus `UndoStagedFile.MovedTo`. Not taken: the plan's leaving out of files left by an EARLIER swap of the step, the tidy (`TidyLeftovers`) following a moved folder, `leaveAKeptCopyInsideTheMovedFolder` and its two M1 rows, and recovery. A Windows-only finding inside it: a staged file's handle (and a removed page's kept original's handle) below a folder makes the folder's rename fail, so it has to be let go first.
- No `contracts/` change. No question for Russell.

## Self-check

1-6 (NIGHT3): one piece's scope only (steps 1 to 5 of the W8-2b brief, plus the named part of piece 3); tests red first (`899-w8-2b-red`); no timed waits; no interface change; no confirmations; notes written. 7. No fixture row changed (none in scope). 8. No writer-scan change (no writing call moved). 9. No riding lows. 10. The order of the step's ops is kept: the carrying move first going forward, the carried edit first going back; every before is read at plan time (a carried file at its place before the move). 11. The five rows pass and are out of the ledger; `Reason899W8U4b` rewritten; no constant left unused. 12. `movedFolder` checked against every held row that carries it (see "Ledger"). 13. One function per rule: every new "at or inside" calls `UndoOp.PartInside` (`MoveCarries`, `PlaceBeforeTheMove`, the listing override, `LetGoOwnFilesInside`, `FollowTheMove`). 14. No run left going, no lock left held, none removed that this run did not take.
