Removed by #1055 (2026-11-27): Plantoir has no link code beyond reading and writing through a link.

# U4b2-14: a-moved-link-is-judged-by-its-bytes (#899)

Branch `issue/899-u4b2-14-a-moved-link-is-judged-by-its-bytes`, from `origin/issue/899-u4b2-10-carried-subfolder-left-out` 78671eafc (which holds `dev` 811c956ce and pieces 9 and 10). `origin/dev` merged before proving and again before hand-back: both "Already up to date" (`dev` still 811c956ce), so no merge commit. (Merged on 2026-11-26 in `night25/integration-7`, 69b247fd5, with U4b2-11 to U4b2-15. "For PROGRESS" and "For documentation 12" are folded into `windows-app/PROGRESS.md` and documentation 12. Piece 15, merged beside this one, made Rename folder move a folder that is a link and reworded `undo.rule.shadow`; the lines below that say the writers and that clause are unchanged are this piece's record as it stood.)

## Must-fail lines

See `windows-app/notes/899-u4b2-14-mustfail.log`. Red first: 9 failures (two check rows, two stack rows, the never-follows test). S1 the reading follows the link: both content rows, both stack rows and the unit test RED; the "another target" row passes under S1 (following never finds a link, and a non-link is something else either way) and is pinned by S3. S2 a folder taken for the link: the "plain folder now" row RED. S3 a link's target ignored: the "another target" row RED. S4 the leaf of a link move resolved for the stays-inside check: the unit test RED (refused notReadable). S5 (Python) `move_state` ignores `linkSha`: two check rows and both stack rows RED. 5 of 5 RED; restored each time (`git status` clean).

What each new row proves: "judged by the target it names" fails without the link reading (S1, S5); "another target" guards against judging a link by its presence alone (S3); "a plain folder now where the link was" guards against a reading that follows the link to its folder (S2); "a link leading out of the working folder" (from holds the link, to free: alreadyBack / canRedo) proves the out-of-folder clause of the sentence at the reading; the door half of that clause (the leaf not resolved) is the unit test under S4. The two stack rows prove Undo and Redo through the door: the link goes back as a link with the same target and comes again, and `courses/TST1O/library` (what it leads to) is byte for byte unchanged after each.

## Runs

- `run-red1.log`: UndoOpKindsTests 39, UndoJournalContractTests 19: 9 failures (above).
- `run-green1.log`: the same 58, 0 failures.
- `run-own.log`: UndoOpKindsTests, UndoJournalContractTests, UndoFilesContractTests, UndoDoorGuardTests, UndoRenameFolderStepTests, UndoWriterScanTests (reads `UndoCheck.swift` as text; no new writing call), FileFormatsContractTests (reads `file-formats.json`): 134 tests, 0 failures.
- `run-mf-s1.log` to `run-mf-s4.log`: the sabotages.
- `python3 scripts/test_make_undo_traces.py`: 33 tests OK; the traces are not stale (no regeneration; `undo-traces.json` and `undo-action-steps.json` untouched).
- Logs in `/Users/russellgordon/plantoir/wt-899-u4b2-14/.dd/`.

## Left for the next piece

- Piece 15 (Rename folder for a per-section folder that is a link): the writer records `UndoOp.moveLink(from:to:linkSha:)` with `UndoHash.sha256(of: UndoTreeReading.linkTarget(at:))` where `JournaledStep.moveFolder` now asks `UndoTreeReading.read` (which answers `.notATree` at a link). `JournaledStep.moveFolder` is unchanged here on purpose: changing it would change what Rename folder does now, which is piece 15's.
- Riding low (a), `2026-11-25-899-u4b2-6-review-1.md` L3 (an earlier run's moved link neither named on the part-way line nor told): it is in `SpecialFolderRenamer.swift` (`foldersAtTheirNewName`, `placesAnEarlierRunMayHaveMoved`), not in the door; left for piece 15.
- A link move that carries an edit (an edit named inside the link's `to`) is readable and not exercised: the edit writes through the link, its kept original sits in the folder the link leads to, and `followTheMove` renames its path with the link, which still resolves to the same file. No writer makes such a step; piece 15 should either pin it with a row or make the step unreadable.

## For the director

- `contracts/` changed (`shared-rules.json`, `file-formats.json`): both gates, taken once with piece 15 (brief). `undo.rule.shadow` is NOT changed, so the Windows test `UndoMakeRoomStepTests.ALinkedLaterClassIsWrittenPlainlyWithTheLinkRemovedAndItsFileUntouched_WhereTheMacRefusesBeforeAnythingChanges_UntilU4b2Pieces14And15` needs no change.
- Ledger: 6 new names under `Reason899W8U4b` (4 in `UndoCheckCases`, 2 in `UndoStackCases`), checked by script against the contract byte for byte; the reason's text now names `linkSha`, `linkTarget`, `moveALinkToAFolder` and `linkedFolder`.
- Piece 11 overlap: `scripts/make_undo_traces.py` changed in three small functions (`tree_reading`, `move_state`, `page_item`, 13 lines); `undo-action-steps.json` untouched.
- Merge note: touches `UndoFormat.swift` (UndoOp), `UndoOpKinds.swift` (`UndoMoveSide`, `UndoPlaces`), `UndoCheck.swift` (`placeLeavingTheFolder`'s signature, the swap's move case), `JournaledWrite.swift` (one call), tests, contracts, documentation 09, the ledger.
- HIG: nothing a teacher sees or hears changed; no section needed.

## Self-check

1. Broke each fix and watched its test fail: S1 to S5, five RED, lines in the log; the two guard rows passed on the old code and each is pinned by its own sabotage.
2. No timed waits: none added.
3. Every sentence on the failure paths is true: no new sentence; a link changed since is refused changed since, naming the place as before.
4. `dev` merged before proving and before hand-back: 811c956ce, already up to date both times.
5. No number tuned by trial.
6. Contracts: rows run from the JSON on the Mac and in Python; nothing outside the brief.
7. `grep -n "DispatchQueue\|\.map {\|\.filter {\|\.reduce(\|\$0"` over the added Swift lines: empty; no new type authored (functions added to `UndoMoveSide`, `UndoPlaces`, `UndoOp`, `UndoContractKinds`, each with its MARK).
8. Riding lows: (b) fixed (a contract sentence; no test can fail on wording, said here); (a) left for piece 15 with the reason.
9. The rename record is still kept; `undoJournalIsLive` untouched (off).
10. Every new contract row is in the Mac's replay (`testCheckCases`, `testStackCases`) and Python's, and held by exact name on Windows (6 names).

## Review 1 (1 MEDIUM, 3 LOW), all fixed in this branch

- **MEDIUM 1.** `UndoOp.moveCarries` (and Python `move_carries`) answers false for a link's move, so an edit under its `to` breaks `wholeOps` and the step is `unknown.unreadableStep`, decided from the shape before any reading. `UndoSwap.stepsOwnFilesInside` returns nothing for a place that is a link (`UndoTreeReading.linkTarget` succeeds only on a link), its own guard. `opKinds.move` says in one clause that a link's move carries no edit. New stackCases row "U4b2-14, review 1: a link's move with an edit inside its new place: a step this version cannot read, a barrier" (call `stepEditingInsideALinksMove`, the shape of `stepEditingInsideAMovesFrom`); red on the old code, held for Windows by exact name (Windows stops at the unknown call; it would also refuse the op itself, having no linkSha). The guard has no contract row: no verdict can see it, since a link side is never a content side for a folder's move (a listingSha move at a link reads `.notATree` whatever is listed), so its reader is `testTheStepsOwnFilesAreNeverListedThroughALink` (red before the guard).
- **LOW 1.** `opKinds.move`: a relative target is kept as written, so a link moved to another depth leads elsewhere; nothing it led to is touched, nothing is told, and Undo puts it back.
- **LOW 2.** The check replay (Mac) now asks `UndoCheck.placeLeavingTheFolder` of a move's places before judging the pair (changed since when one leads out), and `checkCasesHow` says so; Python needs nothing (no row's verdict differs there: a sha or listing move at a link outside is something else already, and a link's move resolves only the folders above). The row is now "move of a link: a link leading out of the working folder, to a folder that is there: holds the content, never followed", target `../../../..` (the folder holding the scratch working folder, always there); S4 now turns it red. Its old name in the ledger was replaced, not added. For W8: Windows' check replay judges the pair only; when it learns linkSha it should ask the same stays-inside check of a move's places, resolving only the folders above a link's move.
- **LOW 3.** Said in the must-fail log in one line: S3 is the sabotage the "another target" row can catch; S1 cannot.
- **Runs.** `run-r1-red.log` (2 failures, above); `run-r1-own.log`: the seven own classes, 135 tests, 0 failures; must-fail R1, R2, S4 again, R3 (Python): 4 of 4 RED. Python 33 OK; traces not stale. `origin/dev` 811c956ce: already up to date.
- **Ledger.** 7 names for this piece under `Reason899W8U4b` (4 check, 3 stack), checked against the contract by script; the reason names the call `stepEditingInsideALinksMove`.
