# U4b3 kept-original-named (#899), 2026-11-26

Brief `vm-tools/briefs/2026-11-26-899-u4b3-kept-original-named.md`, from bb92aabc2 (origin/dev 96a3d2b73 already merged in; still current at hand-back, no merge needed). Russell's answer to "Held for Russell" 1 (2026-11-26, recorded on #899): the words go BEFORE the extension, `Unit 1, Day 3 (kept by Undo).md`; nothing added to hide it from the website.

## For PROGRESS

- DONE: recovery keeps a page a step removed or moved away, found only in its hidden kept original while something else (a file, a folder or a link) holds its place, under the first free visible name beside its place, `Unit 1, Day 3 (kept by Undo).md`, then `(kept by Undo 2)` and on (`UndoRecovery.keepPagesWhosePlaceIsTaken`). One naming loop for a folder and a page: `UndoSwap.renameToAVisibleName`, which `keepUnderAVisibleName` (the folder's) now calls; `UndoSwap.visibleName(for:number:isAPage:)` puts a page's words before its extension. A taken name is skipped, never replaced (RENAME_EXCL, as for a folder). The trail line 'undo kept a page under a visible name' (new event; `UndoTrailHook.keptAPageLine`, `UndoTrail.keptAPageLine`, `ActivityTrail.Event.undoKeptAPageUnderAVisibleName`) is told just BEFORE the rename. A place that cannot be read now leaves it hidden and says nothing (tried again: `tidyClosedSteps` does not mark the step tidied).
- Which kept originals: a `-orig` FILE of the step beside a place an op leaves or fills whole (`UndoCheck.placeLeft`, `placeFilled`: so an undo's page taken away counts as well as a step's page removed), not a copy of what the place holds, while the place holds something. Free place, or a kept original beside its own page (a page changed in place: U3a, U3c rows): untouched (M3 proves it).
- Closing paths: `couldNotPutBack` calls it before its line, so that line names only what is still hidden; the `changedByHand` interrupted branch is reached through `tidyClosedSteps`, which runs in the same recovery right after the closing (and again at any later recovery, so a death between the closing and the rename is covered). `rolledBack` and `completed` cannot leave such a page: rolled back, every page is back in its place; completed, the place holds the step's own end and its kept original is tidied or named by 'undo kept what a page held' as before. Live only: shadow never writes into a working folder, as for a folder set aside (which shadow never makes).
- If the visible name is taken: the folder rule's own answer, the next number (`(kept by Undo 2).md`), the taken file untouched (row 2).
- Riding low (day26-5 sweep, `undo.rule.recovery`): Mac's `changesOnlyFilesAndMoves` confirmed (shadow tidies steps of in-place edits, recompute and moves since U4b part four). The contract sentence now says so, and that a step holding any other op (createTree, removeTree, external, moveApart, setAside) has its staged items left for a live recovery; documentation 12's two copies (the U3 bullet and the W7 row) say the same. No test pins the old words (git grep of mac-app, windows-app, scripts).
- Tests: two new in `UndoHandedOverPlaceTests` ("A kept page named"); `testAFileWrittenWhereAPageWasRemovedSurvivesRecovery` now pins the visible file too; `testRecoveryCases` count 77 to 79.

## Rows

Added to `undo.recoveryCases` after the door-5 rows, each in the Mac's replay and the Python model, both held under `Reason899W8HandedOverPlace` (names checked by script: once in shared-rules.json, once in the ledger, byte for byte):
1. "U4b3 kept-original-named: a step that hands places over before and after a link's move dies with Day 3's page removed and the link not yet moved, and someone's page is then written at Day 3: nothing written over it, the removed page kept as Unit 1, Day 3 (kept by Undo).md and named on the trail, the step interrupted, the list cleared" (`keptVisibleAs`, `keptPageLines: 1`). `keptOriginalsBeside` is NOT used: its check wants exactly one 'could not put back' line, and with nothing hidden there is none; the row instead fails on "staged items left" (handed-over rows' own check) when anything stays hidden.
2. "U4b3 kept-original-named: the same, with Unit 1, Day 3 (kept by Undo).md already taken: ..." (`visibleNameTaken`, which for a handed-over row writes `earlier` at that name and checks it after).
`recoveryCasesHow`: one sentence for `keptVisibleAs` on a page, `visibleNameTaken` on a page, and the new key `keptPageLines`. The rule clause sits beside the folder's in `undo.rule.recovery`; the trail-lines entry beside 'undo found a folder set aside'.

Why each fails on Windows: `UndoRecoveryContractTests.KeysChecked` has neither `withAHandedOverPlace` nor `keptPageLines` (line 23; line 88 asserts every key is checked).

## For documentation 12

W8b piece 21c, beside 21a: Windows' recovery does the same, one naming function for a folder and a page (`<name> (kept by Undo)` for a folder; for a page the words before the extension, `Unit 1, Day 3 (kept by Undo).md`, then ` 2`, ` 3`): for a step closed interrupted (changedByHand or couldNotPutBack, or found closed by a later tidy), every kept-original FILE of the step beside a place an op leaves or fills whole, not a copy of what that place holds while something holds it, is renamed with MoveFileEx without MOVEFILE_REPLACE_EXISTING to the first name nothing holds; the trail line 'undo kept a page under a visible name' (place and visible name, inside the working folder) is written just before; a place that cannot be read leaves it hidden, nothing said, tried again. The couldNotPutBack line is said after it. Live only.

## Must-fail lines

RED 4 of 4: see `899-u4b3-kept-original-named-mustfail.log` (M1 to M4 as the brief names them; M1 was also the first red run).

## Runs (`.dd/`)

run-kon-red-m1 (red: 9 failures as expected, with the new rows' `handedOver` read from it, matching the Python model), run-kon-green (157/157: UndoHandedOverPlaceTests, RestoreRecoveryTests, UndoJournalContractTests, UndoFilesContractTests, UndoWriterScanTests, SharedRulesContractTests), run-kon-m2, run-kon-m3. `python3 scripts/test_make_undo_traces.py`: 40 OK; `make_undo_traces.py --check`: traces current.

## Left for the next piece

Nothing of this piece.

## For the director

Nothing parked. Note: the visible page is a `.md` in the section folder, so Plantoir lists it and the website publishes it (Russell chose this knowing it).

## Self-check

House style grep over added Swift lines: empty; `KeptPageProbe` has its MARK section. Switch off, rename record untouched. Every new row in the Mac's replay and the Python model and held by exact name. Merge: origin/dev 96a3d2b73 already in at the start and at hand-back.
