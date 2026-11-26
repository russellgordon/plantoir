# #899 W8-3: the step's own files inside a moved folder (2026-11-26)

Base: `origin/issue/899-w8-2-carrying-move` at c5e1c999b (it holds `origin/dev` 253f8915f, merged at 1e4c270d3). `origin/dev` had not moved at hand-back (253f8915f), so there was no second merge: 1e4c270d3 is the merge for both "before you prove" and "before you hand back". This piece closes merge window 1 (pieces 1, 2, 3).

What piece 2 had already built (not redone): within ONE swap, its own staged and kept files inside the moved folder let go, left out of the last look and followed (`LetGoOwnFilesInside`, `FollowTheMove`, `UndoStagedFile.MovedTo`).

## For PROGRESS

- **The plan** (`UndoCheck.Plan(..., ownSeq)`, the mac's `plan(ownSeq:)`): for a move that carries edits, the step's own staged and kept files inside its folder, from ANY of its swaps (apply, undo, redo, recovery), are left out of the move's judgement on BOTH sides (`overridingTo` and the new `overridingFrom` of `WholeStateOf`), in both directions. A carried file's listing override wins over its own entry. The door passes `record.Step.Seq` for an Undo or a Redo; making a step passes none. Recovery does not pass it yet (pieces 7 and 8).
- **`UndoSwap.StepsOwnFilesInside(folderFull, seq)`** (the mac's `stepsOwnFilesInside`): walks the folder, never through a link (`UndoLinks.Look`), and names each entry `IsStaged(name, "<seq>")` matches (the one marker test, `.<name>.plantoir-undo-<seq>-…`; step 11's never match step 1's), relative to the folder with `/`, as absent. Anything else inside still counts. The paths are built by the walk itself, so no comparison of spellings is made. "Inside the moved place" for the swap's own files is still `UndoOp.PartInside` (piece 2).
- **The swap's last look** before a forward `MoveHere` also leaves out what the step's EARLIER swaps left inside the folder (`SeqOfLabel(label)` then `StepsOwnFilesInside`). Those files move with the folder because they are inside it; a reversal's rename back carries them the same way.
- **The tidy follows the folder:** `UndoStep.PathsToTidy` is `Paths` plus each carried edit's `PlaceBeforeTheMove`, so a tidy finds the step's own files beside a carried page wherever the folder is now. It is used by the door's tidy after a put-back from kept originals and by pruning's tidy (`UndoJournal`). Recovery's tidies still pass `Paths` (pieces 7 and 8). `Paths` itself is unchanged, because the `interrupted` line uses it.
- **A kept original of a carried page is looked for where the page is now:** the plan remembers where each file was read (`readAt`: a carried file whose move goes in now is read at its place before the move) and asks `keptOriginal` there.
- **Riding low, fixed:** the swap's own late `MoveHere` refusal (changed since, cannot tell) now names `move.FromRelative`, the place where the folder is when the swap runs. That is the place `PlaceAsFound` names at the plan (`to` before an Undo, `from` before a Redo). Before, it named the destination. `CouldNotWrite` and a failed rename still name the destination, as before.

## For documentation 12

- Under "What W8 owes from U4b": Windows now leaves out the step's own files from any swap at the plan and at the swap's last look (`StepsOwnFilesInside`, `ownSeq`), as the mac does. Its tidy looks where a moved folder is now (`PathsToTidy`). Recovery's state and recovery's tidy are still owed (pieces 7 and 8). They should call `StepsOwnFilesInside` and `PathsToTidy` and add no second version of either.

## Tests (in `UndoCarryingMoveTests`)

- `AKeptCopyInsideTheFolderAtItsOldPlaceIsLeftOutOfTheRedo`: undone, a kept copy of step 1 inside the folder at `from`, redone. The copy moves with the folder and stays.
- `AKeptCopyInsideTheFolderAtItsNewPlaceIsLeftOutOfTheUndo`: redone, a kept copy inside at `to`, undone.
- `AnotherStepsStagedFileInsideTheFolderIsNotLeftOut`: step 2's kept copy inside the folder makes the Undo refused, changed since, naming `to`.
- `ATeachersFileNamedLikeAStagedFileOfAnotherSeqIsNotLeftOut`: a file named as step 11's, for step 1: refused.
- `TheKeptOriginalOfACarriedPageIsLookedForWhereThePageIsNow` (on `Plan`): a carried `writeFile` whose blob is gone, going forward. The kept original is asked for at `from/a.md` only, and the plan is `Ready`.
- `ALateRefusalOfTheMoveNamesTheFolderWhereItIsNow` (riding low): a file added inside `to` after the check, so the swap refuses and names `to`.
- `TheTidyFindsTheStepsOwnFilesWhereTheMovedFolderIsNow`: undone, a removable kept copy at `from` is tidied through `PathsToTidy`.
- The replay: the call `leaveAKeptCopyInsideTheMovedFolder`, which puts `Kept.` beside a.md, named as the newest step's `-undo-orig`, wherever the folder is now.
- **Red first** (run `899-w8-3-a-red`, ref 2be55f9b5, the tests on the product as it was): **6 failed of 160.** They were the two old-and-new-place tests (lines 246 and 262: refused, not redone or undone), the kept-original test (line 313), the late refusal (line 329: it named `from`), and the two M1 `EveryStackCase` rows (`WalkTheCase` lines 89 and 90). Two tests passed there as expected, because the old code counted every file: the other step's and the look-alike. Must-fail row 3 proves them. The tidy test was written after the product (it needed `PathsToTidy` to compile), and must-fail row 4 proves it.

## Ledger

- The two `UndoStackCases` rows "U4b, M1: …" pass and are out of the `Reason899W8U4b` row.
- `Reason899W8U4b` rewritten. It no longer names `leaveAKeptCopyInsideTheMovedFolder` or the M1 rows as owed, and it says what W8-3 does. Its recovery, case-only, made-folder, link and Rename folder clauses are unchanged. No other reason named the call. The constant is still used.
- Lesson 4: no key was added to any `KeysChecked`, so no held row could move.

## Must-fail lines

`vm-tools/guest/899-w8-3-mustfail.json`, six rows (the brief's four, one for the swap's last look, and the riding low). Run `899-w8-3-mf2` (ref 9008699e7): **6 RED of 6**. Of 153 tests (`UndoCarryingMoveTests` and `UndoStackContractTests`), rows 1 to 6 failed 4, 4, 2, 1, 1 and 1. Each row was restored by `git checkout`, and the restored run was 270 passed.

1. The own files counted at the plan (`ownSeq: null` at the door).
2. The own files of earlier swaps counted at the swap's last look.
3. Any step's files left out, not only this step's (`IsStaged(name, own)` widened to any marker).
4. The files not followed when the folder moves (`PathsToTidy` without the place before the move).
5. The kept original of a carried page looked for at the old place (`readAt[path]` back to `path`).
6. The swap's late refusal names the destination.

## Runs (the PC, each under `C:\vm-setup\wt-compare.lock`, whose owner file names `899-w8-3 <label>`, released by the run itself)

- `899-w8-3-base` (ref c5e1c999b, piece 2's head on the merge of dev, before anything was changed): both builds 0; the brief's eight classes **263 passed, 0 failed**.
- `899-w8-3-a-red` (ref 2be55f9b5): both builds 0; 6 failed of 160, as above.
- `899-w8-3-a-green` (ref eeeab0e71): both builds 0; the brief's classes **269 passed, 0 failed**.
- `899-w8-3-mf` (ref 9008699e7): void. Its `-Mode` argument was mangled by quoting, so only a build ran and no tests. It was run again as `-mf2`.
- `899-w8-3-mf2` (ref 9008699e7): both builds 0; the brief's classes **270 passed, 0 failed, 0 skipped**; must-fail 6 RED of 6; restored 270 passed; HEAD-AFTER SAME, status clean.
- The last commit (the notes, and one code comment in `UndoSwap.cs` corrected) changes no code, so it had no run of its own.

## Left for the next piece

- Recovery (pieces 7 and 8): pass `ownSeq` to `UndoCheck.Plan` at the recovery put-back (`UndoRecovery.cs` about line 894), use `StepsOwnFilesInside` for recovery's carrying state, and use `PathsToTidy` in recovery's `TidyLeftovers` calls.

## For the director

- No `contracts/` change. No question for Russell.

## Self-check

1-6 (NIGHT3): one invariant only. Tests were red first (`899-w8-3-a-red`). No timed waits. No interface change. No confirmations. Notes written. 7. No fixture row (none in scope). 8. No writer-scan change (no writing call moved). 9. The riding low is fixed with a test and must-fail row 6. 10. The order of the step's ops is unchanged, and every before is still read at plan time (the kept original at the place the page is read). 11. The two M1 rows pass and are out of the ledger, `Reason899W8U4b` is rewritten, and no constant is left unused. 12. No key added. 13. One function per rule: own names by `IsStaged` (the marker), "inside the moved place" by `UndoOp.PartInside` (piece 2's `LetGoOwnFilesInside` and `FollowTheMove`), the carried page's earlier place by `UndoOp.PlaceBeforeTheMove`, and a link by `UndoLinks.Look`. 14. No run left going, no lock left held, none removed that this piece did not take.
