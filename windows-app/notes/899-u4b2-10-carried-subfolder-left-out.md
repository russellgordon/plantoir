# U4b2-10: carried-subfolder-left-out (#899)

Branch `issue/899-u4b2-10-carried-subfolder-left-out`, from `origin/issue/899-u4b2-9-case-only-rule-pinned` a10425ee3 (which holds `dev` 24fcbc718). `origin/dev` merged before proving and again before hand-back: both "Already up to date" (`dev` still 24fcbc718), so no merge commit.

## For PROGRESS

- Mac: a folder a carried edit made inside a moved folder (`renamed/sub` for `renamed/sub/x.md`) is left out of the move's judgement with the edit's file, and removed, when empty, once the folder has moved back and the swap's own files are tidied. `UndoMoveSide.readNamingFoldersLeftOut` (with `foldersHoldingOnly` and `isBelow`, inside by `UndoOp.partInside`) leaves out every folder that holds at least one file left out and nothing else but folders so left out; judged that way first and, failing that, as listed (the moved folder may have held an empty folder of its own). The swap's last look before a move's rename names those folders; after the tidy each is `rmdir`ed where it now is. Riding low: the part-two review of U4b, L3.
- Contract: `file-formats.json` → `undoJournal.opKinds.wholeOps` says the rule; `shared-rules.json` → three `undo.stackCases` rows, two calls and the key `madeFolder` in `stackCasesHow`.

## For documentation 12

- **W8's listing override leaves out made folders too.** When W8 judges a carrying move with its carried edits taken back (opKinds.wholeOps), a listed file whose override is "absent" is left out (as now planned), and so is every listed folder below the moved folder that holds at least one such file and nothing else: no kept file, no link, no folder that is not itself left out (work deepest first). Compare "below" with the one part-by-part, case-insensitive comparison (U4b2-9's paragraph). Judge with those folders left out first; if the listing's SHA-256 does not then match the move's `listingSha`, judge again with every folder listed, because the moved folder may have held an empty folder of its own in which the edit made its file. Either match is "holds the content".
- **The tidy.** The swap's own last look at the moved folder, just before its rename, is the judgement that names the left-out folders. Once every swap has gone in and the step's own staged files and kept originals are removed, remove each named folder at its place after the move (deepest first), only if empty (`RemoveDirectory`, which refuses a folder with anything in it; never a recursive delete). Not on a refusal: a reversed swap puts the folder back as it was.
- **Why not hand the swap a list from the check:** that would be a second judgement of which folders the step made; the swap's last look already makes it, on the disk as it is at the rename.
- **The new key and calls** (stackCasesHow says them in full): `moveAFolderWithAFileMadeInANewFolderInside` is `moveAFolderWithAPageEditedInside` plus a `writeFile` creating `courses/TST1O/renamed/sub/x.md` (`X\n`, its blob in the list); `addAFolderInsideTheMadeFolder` writes `courses/TST1O/renamed/sub/mine/y.md` (`Y\n`) by hand; `madeFolder` is what `sub` holds wherever the moved folder is (renamed if there, else media): names in byte order joined by ", ", `empty`, or `none`.
- **How each held row fails on Windows today:** `UndoStackContractTests.WalkTheCase` asserts every key of a case is in `KeysChecked` before any call; `madeFolder` is not there, so all three rows stop at "a key this replay does not check: madeFolder", which `HeldCaseStillStopsAtItsGap` accepts (read in `windows-app/Plantoir.Tests/UndoStackContractTests.cs`, lines 19 to 26 and 72 to 74). Behind that, the replay does not know the two calls. The key check is per row, not a block-wide enumeration, so no unheld row turns red.

## Must-fail lines

See `windows-app/notes/899-u4b2-10-mustfail.log`. Red first: the Undo row (changedSince, not undone; sub holds x.md, not none), the redo row (nothingToRedo) and the judgement test. S1 folders kept in the override: both rows and the judgement test RED. S2 the tidy skipped: the Undo row RED (`madeFolder` empty, not none) and the redo row (the empty `sub` went back with the folder, so the Redo is refused changed since). S3 other folders ignored and S5 kept files ignored: PASSED against the first form of the unit test and the contract rows, so the unit test was strengthened (a made folder beside the content's own `sub` holding b.md and `keep` holding an empty folder); then RED. S4 no fallback: the empty-folder-of-its-own test RED. 5 of 5 RED. Restored each time (`git checkout`, status clean of it).

What each new row proves: the Undo row fails without the judgement (S1) and without the tidy (S2); the redo row fails without either (the step is never undone, or the empty folder spoils the Redo); the third row ("a folder put inside the folder a carried edit made") is the guard and passes with the rule or without it: it proves the rule did not make the judgement too loose (a judgement that dropped every folder holding a left-out file, whatever else it held, would undo it). The S3/S5 clauses (a made folder must hold nothing else) cannot change any contract row's answer, since a folder holding something kept never matches the listing when dropped; they matter only when a made folder and a content folder holding a left-out file sit side by side, which the unit test pins.

## Runs

- `run-red1.log`: UndoOpKindsTests 32, UndoJournalContractTests 19: 4 failures (above).
- `run-green1.log`: the same 51 tests, 0 failures. `run-unit2.log` (strengthened test): UndoOpKindsTests 32, 0 failures.
- `run-own.log` (after the dev merge): UndoOpKindsTests, UndoJournalContractTests, UndoFilesContractTests, UndoRenameFolderStepTests, UndoKeptCopiesTests, UndoWriterScanTests (reads `UndoCheck.swift` as text): first run 1 failure (UndoWriterScanTests: `UndoCheck.swift` has 16 writing calls, the list allowed 15: the new `rmdir`); the entry now allows 16 with the reason. `run-own2.log`: 113 tests, 0 failures.
- `python3 scripts/test_make_undo_traces.py`: 33 tests OK; the traces are not stale (no regeneration, no generated file touched).
- Logs in `/Users/russellgordon/plantoir/wt-899-u4b2-10/.dd/`.

## Left for the next piece

- A link inside a made folder keeps it (the `listing.links` clause), unpinned by any sabotage: no carried edit makes a link today.
- A made folder holding only the Finder's `.DS_Store` is left out of the judgement (the listing ignores that name) but `rmdir` will not remove it, so `sub/.DS_Store` would be left behind after an Undo. Not reachable by any writer today; the fix would be to remove a lone `.DS_Store` first.
- The Python model holds folders only as their files (`folder_of_pages`), so it cannot hold an empty folder: no judgement to mirror, and its three rows pass by construction. Said here rather than adding folder state to the model.

## For U7

- Recovery's put-back runs the same `UndoSwap.swap`, so a recovered step tidies a made folder the same way; recovery's own judgement (`carryingMoveState`) goes through `UndoMoveSide.read`, so it leaves made folders out too. `UndoRecovery.swift` was not changed and not tested for this shape.

## For the director

- `contracts/` changed (`shared-rules.json`, `file-formats.json`): both gates. No Windows test enumerates `stackCases` keys block-wide (the key check is per row), so no unheld PC row goes red.
- Ledger: 3 new names under `Reason899W8U4b` (checked by script against the contract byte for byte); the reason's text now names the two calls and the key.
- Merge note: this branch touches `UndoOpKinds.swift` (`UndoMoveSide`) and `UndoCheck.swift` (the swap's move case and step 3), tests, contracts, documentation 09, the ledger. Not the rename sheet, `FolderRenameRun` or recovery.
- HIG: nothing a teacher sees or hears changed; no section needed.

## Self-check

1. Broke each fix and watched its test fail: S1 to S5, five RED, lines in the log; two sabotages first passed and the test was made real.
2. No timed waits: none added.
3. Every sentence on the failure paths is true: no new sentence; a refused Undo says changed since, naming the moved folder where the teacher finds it, as before, and nothing is moved (row three).
4. `dev` merged before proving: 24fcbc718, already up to date both times.
5. No number tuned by trial.
6. House style and contracts: rows run from the JSON on the Mac and in Python; nothing outside the brief.
7. `grep -n "DispatchQueue\|\.map {\|\.filter {\|\.reduce(\|\$0"` over the added Swift lines: empty; no new type authored (functions added to `UndoMoveSide`, which has its MARK).
8. Riding low L3 fixed with tests red first.
9. The rename record is still kept; `undoJournalIsLive` untouched (off).
10. Every new contract row is in the Mac's replay (`testStackCases`) and Python's, and held by exact name on Windows (3 names).
