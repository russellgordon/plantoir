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

- The Python model holds folders only as their files (`folder_of_pages`), so it cannot hold an empty folder: no judgement to mirror, and its three rows pass by construction. Said here rather than adding folder state to the model.

## For U7

- Recovery judges a carrying move through the same `UndoMoveSide.read` and runs the same `UndoSwap.swap`, so a recovered step leaves made folders out and removes them as an Undo does, with one gap (review 1, LOW 1): a process killed after the swap's tidy and before `removeAFolderLeftOut` leaves an empty made folder at `media`. Recovery then finds the edit back and the move `neither` (the empty folder is listed and no file left out is in it), settles the step as interrupted / changed by hand and clears the list; the empty folder stays. Nothing is lost. Not run here; read from the code by the reviewer, and `UndoRecovery.swift` was not changed. A cure, if U7 wants one: recovery leaves out an empty folder at a carried edit's absent place.

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

## Review 1 (2 MEDIUM, 4 LOW), all fixed in this branch

- **MEDIUM 1, mixed folders.** The two tries (all candidates left out, then none) are replaced by `UndoMoveSide.foldersTheContentLacks`: every set of candidates closed below (a folder left out only with every candidate below it), from all down to none, in one order (a bitmask counted down); the one whose listing matches `listingSha` is what the content lacked, and at most one can match. The list keeps only the hash, so the sets are tried, not read. Bound: `mostFoldersDecidedOneByOne` = 8 (at most 256 hashes); beyond it only all or none, so a step with more than eight, some of them the content's own, is refused as changed since (takes nothing back, loses nothing). Said in `wholeOps` and pinned. No journal format change (director's choice). New rows, each failing on the old code: "U4b, an empty folder of the moved folder's own, with a folder a carried edit made inside it: Undo takes the step back and keeps the folder of its own" (a), its "…: undone and redone", and "U4b, an empty folder of the moved folder's own, a file a carried edit made in it and a folder made beside it: …" (b); new key `foldersInside` (read by `UndoContractKinds.foldersInside`; Python lists it as one it does not check, since the model holds no empty folder).
- **MEDIUM 2, the Finder's record.** `UndoSwap.removeAFolderLeftOut` removes a `.DS_Store` before the `rmdir` only when it is the folder's one entry and a regular file (lstat); a link of that name, or anything else inside, leaves the folder whole. There is no separate `.DS_Store` code in `createTree`'s take-out to share (it removes the whole folder after its rename to -gone); what is shared is the name, `UndoTreeListing.ignoredName`, the one the listing ignores. Row: "U4b, the Finder's record of a window written inside the folder a carried edit made: Undo takes it out with the folder, and the Redo goes in" (call `finderRecordsAWindowInTheMadeFolder`). The writer scan's count for `UndoCheck.swift` is 17 (the `removeItem` of the record).
- **LOW 1**: "For U7" corrected (above).
- **LOW 2**: the third row's `why` now says it is a regression guard, not a proof of the rule.
- **LOW 3**: `testAFolderHoldingAnythingKeptIsNeverACandidate` calls `foldersHoldingOnly` directly with a kept file, a link and a kept folder beside a lone candidate. It passed before the review's fixes (the clauses were there); its must-fail is S3 below.
- **LOW 4**: the `rmdir`'s result is discarded with a comment saying why nothing is owed (every swap has gone in; a folder that will not go holds something), as `removeTheFoldersMade` treats the same failure.
- **For documentation 12 (W8)**: decide each candidate on its own as above (sets closed below, all to none, up to eight; beyond, all or none); before removing a left-out folder, delete a lone `.DS_Store` that is a regular file (not a reparse point), then `RemoveDirectory`.
- **Windows**: 4 more names under `Reason899W8U4b` (7 in all for this piece), checked by script byte for byte; each stops at `KeysChecked` on `foldersInside` or `madeFolder`.
- **Runs**: `run-r1-red.log` (8 failures: the four rows and four unit cases; the clause and beyond-eight cases passed, as they must on the old code), `run-r1-green.log` (UndoOpKindsTests, UndoJournalContractTests, UndoWriterScanTests: 63, 0 failures), must-fail in the log (R1 to R5, 5 RED; the bound-of-nine sabotage first passed because the test's two calls shared a folder, fixed); `run-r1-own.log`: the six own classes, 119 tests, 0 failures; Python 33 OK, traces not stale.

- **Merge**: `origin/dev` 811c956ce merged after review 1's fixes (merge commit 5d800c875); after it the six own classes again: 119 tests, 0 failures (`run-r1-own-merged.log`); Python 33 OK.
