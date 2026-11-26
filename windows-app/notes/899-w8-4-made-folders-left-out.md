# #899 W8-4: a folder a carried edit made is left out and removed (2026-11-26)

Branch `issue/899-w8-4-made-folders-left-out`, base piece 3's head ab8702374 (which holds `origin/dev` 253f8915f). `origin/dev` was 253f8915f at the start and already in the base, so the first merge was not needed. Before hand-back it had moved to 461ee3943, and it was merged in at 68f2d131a with no conflicts.

## For PROGRESS

- U4b2-10 on Windows: a folder inside a moved folder that holds only files left out of the move's judgement (and folders so left out) is left out with them. Each candidate is decided on its own: every set that leaves a folder out only with every candidate below it, from all down to none, up to eight candidates; beyond eight only all or none. The one set whose listing's SHA-256 matches `listingSha` is what the content lacked (`UndoMoveSides.ReadNamingFoldersLeftOut`, `FoldersTheContentLacks`, `FoldersHoldingOnly`, `MostFoldersDecidedOneByOne` = 8; "below" is `UndoOp.PartInside`). `UndoMoveSides.Read` is now the same reading's side, so the plan (`UndoCheck.WholeStateOf`) and the swap's last look judge alike.
- The swap's last look before a move's rename names the left-out folders at their place after the move. Once every swap is in and the step's own staged and kept files are tidied, each is removed deepest first (`UndoSwap.RemoveAFolderLeftOut`). A lone `.DS_Store` goes first only when `UndoLinks.Look` says it is a regular file. The folder itself goes only by `Directory.Delete(recursive: false)`, and only when it is a folder (never a link put at its place). Never on a refusal, and never told when it fails.
- Riding lows of the window 1 review:
  - LOW 3: `FollowTheMove` now also follows the folders the swap made (`foldersMade`), forward and in a reversal, so a refused swap's tidy finds them where the folder went back to.
  - LOW 1: a refused folder rename, and the could-not-write for the folder that will hold it, name the place the folder leaves (`move.FromRelative`), as the mac's `moveHere` names `namedAs`.
  - LOW 2: tests only (no product change).

## For documentation 12

- "What W8 owes from U4b2-10": done on Windows by W8-4 as the section describes. One Windows difference: a Windows listing holds no link (a folder holding one is `NotATree`), so "no link" in the candidate rule is decided by the reading itself, and a made folder holding a link refuses the move as something else.
- The test seam `UndoSeams.RemovingAFolderLeftOut` (called with each folder just before the tidy removes it) exists only so a test can see that a refused swap tidies none. A folder left out always still holds the swap's own kept or staged file on a refusal, so the emptiness check alone would hide a tidy run there.

## Must-fail lines

`vm-tools/guest/899-w8-4-mustfail.json`, eight rows: the brief's five, then one for each riding low. Filter: `UndoMadeFoldersTests`, `UndoStackContractTests` and `UndoCarryingMoveTests` (166 tests at mf3). Every row was restored by `git checkout`.

1. Made folders counted (`candidates = []`): RED, 9 failed.
2. All or none only, at any number: RED, 4 failed.
3. A recursive delete: RED, 1 failed (`AFolderLeftOutHoldingAnythingElseIsKeptWithAllItHolds`).
4. The `.DS_Store` deleted when it is a link: RED, 1 failed (`ADsStoreThatIsALinkIsNotDeleted`).
5. The tidy run on a refusal: RED, 1 failed (`TheTidyOfFoldersLeftOutNeverRunsOnARefusal`).
6. LOW 3, the folders made not followed by a reversal: RED, 1 failed (`AFolderMadeForACarriedFileIsFollowedWhenTheSwapIsReversed`).
7. LOW 2, `Reverse` without its `LetGoOwnFilesInside`: NOT RED at mf2. The staging-failure test the review suggested holds no handle inside the folder at the reversal. RED at mf3, 1 failed, once `ARedoRefusedAtItsCarriedPageLetsGoOfItsStagedFileAndMovesTheFolderBack` was added: a Redo refused at the carried page's own swap, with its staged `-new` held inside the moved folder.
8. LOW 1, a failed folder rename names the destination: RED, 1 failed (`AFolderRenameThatFailsNamesThePlaceItLeaves`).

## Runs

All runs were on the PC, under `C:\vm-setup\wt-compare.lock`, with the brief's seven classes, both builds 0.

- `899-w8-4-red` (ref 1357b6f7e, tests first with a stub tidy): **11 failed of 213**. The failures:
  - the six unheld stack rows that need the tidy or the override;
  - `AFolderMadeForACarriedFileIsFollowedWhenTheSwapIsReversed` (LOW 3);
  - `AnEmptyFolderLeftOutIsRemoved`, `AFolderLeftOutHoldingOnlyARegularDsStoreIsRemovedWithIt`, `EightCandidatesAreDecidedOneByOne` and `TheTidyOfFoldersLeftOutNeverRunsOnARefusal` (that test's second half, since removed).

  Passing on the product as it was, as they must, since they are guards:
  - the nine-candidates refusal, the link-in-a-made-folder refusal, and the recursive and link tidy tests (the stub deletes nothing);
  - the "folder put inside the made folder" stack row (its own `why` says it passes either way);
  - LOW 2's first test.

  LOW 1's first version passed too, because the held file was unreadable, so the last look refused first. It was fixed to hold the file readable, and must-fail row 8 proves it.
- `899-w8-4-green` (ref 53ecc938b): 212 of 213. The second half of the refusal test undid a list that the refusal had cleared, so the test was wrong. It was split.
- `899-w8-4-mf` (ref 093f0c115): void. The refusal test's page-based refusal comes before the move, because file targets go before whole ops when a step is taken back. It was remade with a second folder's move, which is taken back after the carrying move.
- `899-w8-4-mf2` (ref 024b7065f): **214 passed, 0 failed**. Must-fail 7 RED of 8 (row 7 NOT RED). Restored: 214 passed. HEAD-AFTER SAME, status clean.
- `899-w8-4-merge` (ref 68f2d131a, dev merged in): both builds 0, the brief's classes **218 passed, 0 failed**, `LOCK-RELEASED`.
- `899-w8-4-mf3` (ref 285e8850f): **215 passed, 0 failed**. Must-fail **8 RED of 8** (166 tests in the filter). Restored: 215 passed. HEAD-AFTER SAME, status clean, `LOCK-RELEASED`. This is the head proven; the notes commit after it changes no code.

## Left for the next piece

- Recovery's killed tidy of the made folders (U7, per the U4b2-10 notes): not in scope.
- Pieces 7 and 8, from piece 3's notes: `ownSeq` at recovery's put-back, `StepsOwnFilesInside` for recovery's carrying state, `PathsToTidy` in recovery's `TidyLeftovers` (`TidyClosedSteps` included).
- The folders a move's last look left out are not followed by a LATER move of the same step. No step makes two moves that nest today.

## For the director

- No parked questions. No `contracts/` change. No `mac-app/` change.
- `AMadeFolderHoldingALinkIsNeverLeftOut` holds on Windows by the listing's own rule (a link anywhere makes the folder not a tree), not by the candidate rule; no sabotage of `FoldersHoldingOnly` can make it red.

## Self-check

1 to 6 (NIGHT3-COMMON):
- Tests came first (red run above).
- Only `windows-app/` changed, plus `vm-tools/guest` scripts.
- No timed waits, no interim states, nothing a teacher sees.
- Commits are small and carry `#899`.
- Pushed.

Then the W7b2 and W8 items:
- 7: no fixture row; the ledger rows are gone and the reason sentence is true.
- 8: no writer-scan change (no writing call moved).
- 9: LOW 1 and LOW 3 are fixed with tests. LOW 2 has two tests, and must-fail row 7 is RED.
- 10: the order of file targets is untouched.
- 11: the seven rows are out of `Reason899W8U4b`'s `Owed` list. The reason's U4b2-10 clause is removed and its W8-4 sentence added. No other reason named `madeFolder` or `foldersInside` (grep), and no constant went unused.
- 12: the keys `madeFolder` and `foldersInside` are carried only by the seven rows, all now unheld and green.
- 13: every "below" and "inside" is `UndoOp.PartInside` (`FoldersHoldingOnly`, `LeavesOutEveryCandidateBelow`, `FollowTheMove`'s folders made); "is a link" is `UndoLinks.Look`.
- 14: each run was waited on in the foreground until `RUN_DONE`. Each released only its own lock (`LOCK-RELEASED`). The other tree's lock (`int-d26-2`) was waited for and never touched.
