# U4b2-14: a-moved-link-is-judged-by-its-bytes (#899)

Branch `issue/899-u4b2-14-a-moved-link-is-judged-by-its-bytes`, from `origin/issue/899-u4b2-10-carried-subfolder-left-out` 78671eafc (which holds `dev` 811c956ce and pieces 9 and 10). `origin/dev` merged before proving and again before hand-back: both "Already up to date" (`dev` still 811c956ce), so no merge commit.

## For PROGRESS

- Mac: a `move` whose item is a symbolic link moves the link itself and is judged by `linkSha`, the SHA-256 of the target it holds (`readlink`), never followed. `UndoOp.linkSha`, `UndoOp.moveLink`; a move is readable with exactly one of `sha`, `listingSha`, `linkSha`. `UndoMoveSide.readLink` (lstat + readlink) is called first from `readNamingFoldersLeftOut`, the one reading the check, the swap's last look and recovery (through `wholeState`) share. `UndoPlaces.staysInside(_:_:namedBy:)` resolves only the folders above a link move's `from` and `to`; the plan's `placeLeavingTheFolder` (now takes the op), the swap's `staysInside(target)`, `aWebsiteRecordIsChangedSince` and the door's own check in `JournaledWrite` call it. The swap no longer walks a link move's `from` for the step's own files (`stepsOwnFilesInside` would read through the link). The rename is the existing `renamex_np` (RENAME_EXCL), which renames the link.
- Why `linkSha` and not a one-line listing `link <sha> .` under `listingSha`: an older reader (this version before the piece, Windows today) compares `listingSha` against the folder it reads; at a link it finds no folder and judges "changed since", which clears the list: a misreading. A new key leaves an older reader with neither `sha` nor `listingSha`, so `shapeIsKnown` (Mac) and `UndoFormat.ShapeIsKnown` (Windows, line 675) refuse the op as not readable: the barrier an unknown step is meant to be. It is also the smaller change: no listing line with a path of `.`, which `isSafeRelativePath` would have to learn.
- Contract: `file-formats.json` → `opKinds.move` (shape, the link sentence, out-of-folder clause), `opKinds.wholeOps` (riding low b, below). `shared-rules.json` → 4 `checkCases`, 2 `stackCases`, `checkCasesHow` (op key `linkTarget`), `stackCasesHow` (call `moveALinkToAFolder`, key `linkedFolder`).
- Riding low (b), `2026-11-25-899-u4b2-10-review-2.md` LOW 1: `wholeOps` now says Undo of an untouched rename "always works but in that one case, more than eight such folders some of which are the content's own", and the refusal sentence says "nothing is taken back and no file is lost, and, as with every change since, the list is cleared, so that step and every older one can no longer be undone". Documentation 09's U4b2-10 paragraph says the same. Piece 10's notes file is not edited (it is that piece's record); this paragraph corrects its "loses nothing": true of files, not of the list.
- Python model: `tree_reading` reads a link as `("link", sha(target))`, `move_state` judges `linkSha`, `page_item` knows a link page; the harness turns `linkTarget` into `linkSha` and models the stack call and key. All six rows are modelled, none skipped.
- The writers are unchanged: Rename folder still refuses a per-section folder that is a link (piece 15), Insert Class still refuses renaming a later class that is a link. `undo.rule.shadow` is unchanged and stays true (it is about writers; its "until pieces 14 and 15" still holds, piece 15 settles it).

## For documentation 12

- **W8 moves a reparse point as itself.** For a `move` with `linkSha` (opKinds.move): read each side without following: `File.GetAttributes`/`FileSystemInfo` with `FileAttributes.ReparsePoint` set and `LinkTarget` (the target string as stored, never `ResolveLinkTarget`); the side holds the content when it is a link whose target string, as UTF-8 bytes, hashes (SHA-256) to `linkSha`; absent is free; a folder, a file or a link with another target is something else; a link whose target cannot be read is "cannot tell now". Move it with `MoveFileEx` on the link path without `MOVEFILE_REPLACE_EXISTING` (it moves the reparse point, not the target). For the leaves-the-working-folder check, resolve only the folder above a link move's `from` and `to`, never the link: a link leading out of the working folder, or nowhere, is moved like any other, and its target is never opened, listed or touched. Do not walk inside a link move's `from` looking for the step's own staged files. Read the op as readable with exactly one of `sha`, `listingSha`, `linkSha` (`UndoFormat.ShapeIsKnown`, the line `return (op.Sha is not null) != (op.ListingSha is not null)`).
- **Target bytes.** The Mac hashes `readlink`'s bytes. A Windows symbolic link's stored target is UTF-16 and may be stored with backslashes; a step recorded on one platform and judged on the other would compare different bytes. Hash the target as UTF-8 of the string `LinkTarget` gives, unchanged. A link made on one platform and judged on the other is changed since, which is safe (refused, nothing moved). Say so if W8 decides to normalise separators; the contract does not ask for it.
- **The replay.** `checkCases` op key `linkTarget` → `linkSha` = SHA-256 of its UTF-8 bytes (as `contentText` → `sha`). `current`'s `link` already makes a link (`UndoKindsForTheCases.MakeALink`); for these rows it must make it with the target the case gives (today it ignores the target), or the first and fourth rows cannot pass. Stack call `moveALinkToAFolder` and key `linkedFolder` as `stackCasesHow` says.
- **How each held row fails on Windows today.** The four `checkCases` rows: the op has no `sha` and no `listingSha` (Windows ignores `linkTarget`), so `ShapeIsKnown` refuses it and each is answered notReadable both ways, which is what `UndoCheckContractTests.JudgeAsTheLedgerSays` requires of a row held under `UndoCheckCases` (`Assert.False(op.Readable)`); `UndoOpKinds.cs` about 682 (the reparse-point reading) is never reached. The two `stackCases` rows stop at "a key this replay does not check: linkedFolder" (`UndoStackContractTests.KeysChecked`), which `HeldCaseStillStopsAtItsGap` accepts; behind that the call is unknown. No Windows test enumerates `checkCases` op keys or `stackCases` keys block-wide, so no unheld row turns red.

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
