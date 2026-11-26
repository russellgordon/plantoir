# U4b2-13: model-recover-hand-edits (#899)

Branch `issue/899-u4b2-13-model-recover-hand-edits`, from `origin/issue/899-u4b2-12-rename-traces-made` 8939d5327 (holds `dev` 811c956ce and pieces 9 to 12). `origin/dev` was merged before proving and again before hand-back: "Already up to date" both times (`dev` an ancestor), so there is no merge commit. (Merged on 2026-11-26 in `night25/integration-7`, 69b247fd5, with U4b2-11 to U4b2-15. "For PROGRESS" and "For documentation 12" are folded into `windows-app/PROGRESS.md` and documentation 12.)

## Must-fail lines

Log: `windows-app/notes/899-u4b2-13-mustfail.log`. Each restored with `git checkout`, `git status` clean after.

| | Sabotage | Result |
|---|---|---|
| M1 | Python: `recover`'s old early return (any place in the way: interrupted, nothing put back) | RED: `test_recovery_cases_with_a_moved_folder`, both new rows (the first page still `publish: true`), 2 failures |
| M2 | Mac replay: `editTheCarriedPageByHand` writes nothing | RED: `UndoJournalContractTests.swift:142`, the carried row: "the step is rolledBack", "the moved folder is media, old" |

| M3 | Mac product (review 1, LOW 2): settle leaves a move out of `opsToPutBack` whenever a place is in the way | RED: `UndoJournalContractTests.swift:142`, row 1 only: "the moved folder is renamed, old" |

3 of 3 RED. Python red first: before the fix (with only `recover`'s answer widened to three values), exactly the two new rows failed (`.dd/py-red.log`, `failures=2`); that run is the same sabotage as M1.

## Runs

Logs in `/Users/russellgordon/plantoir/wt-899-u4b2-13/.dd/`.

- `py-red.log`: 36 tests, 2 failures (the two new rows). `py-green.log`: 36 OK. `make_undo_traces.py --check`: current.
- `run-green1.log`: `UndoJournalContractTests`, 19 tests, 0 failures (`testRecoveryCases` 62 rows). No other Mac class reads a changed file as source text (grep of `mac-app/Tests` for the three changed test files and the script: only `UndoActionStepsTests`, which names the script in a comment and a message, never reads it). Other classes read `shared-rules.json` as data, none of them `undo.recoveryCases`.
- `run-mf2.log`: M2.
- `py-mf1.log`: M1.

## Left for the next piece

- Review 1 of piece 12, LOW 1 (no trace kills a rename part way: the action-trace format has no kill call): not needed by this brief. Recovery is proven by `recoveryCases`, which have kill points, so I did not add a kill call to the trace format. A kill call (contract note, Mac replay, Python, held names) is its own piece if the director wants the recorded steps' own bytes killed part way; the per-section step's two folder moves (a kill between them) would be its first trace.
- LOW 2 (no per-section refusal names a moved folder): not a one-trace addition. The action traces are all seeded random; a hand-picked trace needs a new path in `generate` and the Mac replay, and it changes `undo-traces.json`, which this brief says should not change. Scenario for the piece that takes it: per-section rename, a `body` hand edit of the page inside `section2/Assessments` (at its new place), then Undo: which folder is named first going back.
- LOW 3 (a link inside the course that leads back to the course cuts `UndoFolderPlaces.placeResolvingOnlyAbove` short): product Swift, out of this brief's scope; for U7 (below).
- LOW 4 (the must-fail log of piece 12): nothing to do, as the director said.

## For U7

- `placeResolvingOnlyAbove` (`JournaledStep.swift`, about line 1114): the walk stops at the first ancestor whose canonical path is the course's, so `section1/self -> <course>` makes `section1/self/Concepts/Arrays.md` keyed as `<course>/Concepts/Arrays.md`. It changes only the order of relinked pages, never what is written. A test: a course with that link and two pages, `inPathOrder` must order by `section1/self/...` as written.
- The known gap is still U7's: a step killed after its edit inside the folder went in, then a page edited by hand elsewhere: the put-back plan does not leave the step's own kept copy inside the folder out, so the folder is refused too and the step closes interrupted with nothing put back. Neither new row is that case (row 1 stops before the edit inside is swapped, row 2 too), and the Python model, which holds no staged files, would put the pages back there: the model and the Mac would differ in that one case, which is why no row reaches it.

## Review 1 (fixes)

- LOW 1: `recover`'s docstring names its two known differences from settle (external targets named; no staged files, the U7 gap) and why no row run through the model reaches them.
- LOW 2: M3 above, a product sabotage that turns row 1 red on the Mac.
- LOW 3: a `handEdit` that is not a string fails the row on the Mac (`UndoContractReplay.runRecoveryCases`), never skipped.
- LOW 4: the reason of their own, above.
- Runs: Python 36 OK, `--check` current, `run-green2.log` 19 tests 0 failures, `run-mf3.log` M3.

## For the director

- **For W8 (review 1, LOW 5, Windows test code, not changed here):** `windows-app/Plantoir.Tests/UndoRecoveryContractTests.cs` lines 74 to 79 (`PathOf` passes an unknown name through as a path) and 201 to 205 (the hand edit reads that path): an unknown `handEdit` value fails with a bare null reference. When W8 adds `withAMovedFolder` to `KeysChecked`, refuse an unknown `handEdit` by name ("a handEdit value this replay does not know"), as the Mac does, and teach it `carried`.

- `contracts/` changed: `shared-rules.json` only (two `recoveryCases` rows, one sentence in `recoveryCasesHow`). Both gates.
- Ledger: 2 rows added, nothing else under `windows-app/Plantoir.*`.
- Merge with piece 14: my hunks are in `recover` and a new function after it (`make_undo_traces.py`), `test_recovery_cases_with_a_moved_folder` and a new helper after it, the end of `recoveryCases` and of `recoveryCasesHow`, `runRecoveryCases`' hand-edit lines, and the end of the U4b `UndoRecoveryCases` ledger list; piece 14's hunks are elsewhere in each file (checked by hunk ranges). Documentation 09: both pieces add a paragraph at the end of the same section; keep both.
- HIG: nothing a teacher sees changed; no section read.
- Nothing parked: the Mac agreed with Swift's reading on both rows.

## Self-check

1. Broke each fix and watched it fail: M1 (Python model), M2 (Mac replay's hand edit), 2 RED.
2. No timed waits added.
3. Every sentence on the failure paths is true: the replay's new failure lines say what is missing; the ledger reason read against `UndoRecoveryContractTests.Walk`.
4. `dev` merged before proving and before hand-back: up to date both times.
5. No number tuned by trial (62 = 60 + 2 rows).
6. Contracts: `shared-rules.json` by hand (authored), formatted as its neighbours; `undo-traces.json` unchanged.
7. `grep -n "DispatchQueue\|\.map {\|\.filter {\|\.reduce(\|\$0"` over the added Swift lines: empty. The new static func sits in `UndoContractKinds`' existing section; no new type.
8. Riding lows: L5 of the part-two review is this piece (fixed, red first). Piece 12's review lows: 1, 2, 3 written above with reasons; 4 nothing to do.
9. The rename record is still kept; `undoJournalIsLive` untouched (off).
10. Both new rows are in the Mac's replay (`testRecoveryCases`, green) and held on Windows by exact name.
