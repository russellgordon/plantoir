# U4b2-12: rename-traces-made (#899)

Branch `issue/899-u4b2-12-rename-traces-made`, from `origin/issue/899-u4b2-11-rename-step-recorded` e21cacb62 (holds `dev` 811c956ce and pieces 9, 10, 11). `origin/dev` was merged before proving and again before hand-back. Both times it was "Already up to date" (`dev` still 811c956ce), so there is no merge commit.

## For PROGRESS

- Mac: Rename folder's two recorded steps (`renameFolder`, `renameFolderPerSection`) have action traces now. There are twelve, `action-151` to `action-162`, made by `scripts/make_undo_traces.py` and replayed by `UndoActionStepsTests.testEveryActionTraceReplaysAsTheContractSays` through `JournaledWrite.perform(ops:)`. `STEPS_WITHOUT_TRACES_YET` and `steps_with_traces` are gone.
- The model (Python):
  - `action_fixture` lays each folder's listing at its `from` (`lay_folder_moves`). A carried page is not laid at its new place.
  - `make_recorded_step` sends a `folderMoves` step to `Model.folder_moves_step`: one `move` (with `listingSha`) per folder first, then `change_ops` (the old inline loop of `files_step`, now one function both use), then `recompute_ops`. The step is planned forward and made by `ops_step`, the same path as any `perform(ops:)` step.
  - `path_hashes` hashes a folder held as its files by its listing (`folder_hash`).
- The model was wrong about one thing, and the Mac's rule was already settled (U4b, `UndoOp.placeAsFound`). A refused Undo of a move names its `to`, and a refused Redo names its `from`. The model named `from` both ways. It now uses `place_as_found`. Only `action-154` call 4 depended on this (`Concepts` became `Ideas`), and no earlier trace or case changed.
- Riding lows from review 2 of U4b2-11, fixed:
  - (A) `ClassPages.isInPathOrder` breaks a tie by the paths' UTF-8 bytes as spelled.
  - (B) `SpecialFolderRenamer.inPathOrder(_:under:)` keys each page by `UndoFolderPlaces.placeResolvingOnlyAbove`, so a link is ordered by its own place.
  - (C) the order test no longer depends on the volume's listing order.
  - The steps file's note states the tie-break and the own-place rule. Re-recorded: only the note line changed, and no recorded step changed.

## For documentation 12

- **The twelve new traces are held** in `NamedGapLedger.cs`, area `UndoActionTraces`, under `Reason899W8U4b`. I checked by script that the names match the contract byte for byte (12 of 12). The reason's text now names them.
- **Why each still fails on Windows and does not go red.** `UndoActionTraceContractTests.ReplayTheActionTrace` checks `moves`, `members`, `trees` before any door is asked. Both rename steps hold `members`, so each trace fails there with "a step this replay does not make yet (members)". `EveryCallOfEveryActionTrace` gives the held case to `HeldCaseStillStopsAtItsGap`, which wants "a step this replay does not make", and the message contains it. So all twelve fail at the guard, are held, and pass the held check. None passes, and none goes red unheld. The guard does not name `folderMoves` itself, because `members` comes first. Removing `members` from the guard alone would NOT let these traces through correctly. Without folderMoves support the replay would write each carried page's before at its NEW place and make no folder move.
- `EveryHeldActionTraceIsStillInTheContract` passes because all twelve names exist. No other Windows test enumerates action traces or step names: `UndoTraceContractTests` reads only `traces`, and the step rows are piece 11's, still held.
- **What W8 must do to run them:**
  1. Lay each `folderMoves` entry's `files` (text by path inside) and `folders` at its `from`.
  2. Write every `files` entry's `before` EXCEPT a page inside a folder move's `to` (part by part, without regard to case). That page is carried: its before is already in the listing at the old place.
  3. Make the step as one ops step: per folder a `move` {from, to, listingSha} (no blob), then each file's ops (a carried page named at the NEW place, its before the old text, its after the recorded after), then the `editJSON` members in the recorded order.
  4. Hash at both places each folder (its listing's SHA-256, null when absent) and each page of its listing, as the trace's `afterUndoingAll` and `final` keys name them.
  5. Name a refused Undo of a move by its `to` and a refused Redo by its `from` (`action-154`: `courses/ICS3U/Ideas`; `action-152`: `courses/ICS3U/Concepts`, others 1).
- **Page order for W8's own recording** (steps file's note): lowercased path, then on a tie the UTF-8 bytes as spelled, no locale. Each page is ordered by its own place inside the course (the course folder canonical, the parts below as written), never a link's target. On the Mac a file URL spells every path in one Unicode form (measured: `caf\u{E9}` and `cafe\u{301}` give the same bytes), so only a case-only pair can tie. NTFS keeps the form as written, so W8 should apply the byte tie-break as stated.

## Must-fail lines

The log is `windows-app/notes/899-u4b2-12-mustfail.log`. Every sabotage was restored with `git checkout`, and `git status` was clean after each one.

| | Sabotage | Result |
|---|---|---|
| M1 | Python: the model's backward order with the move first (`plan` keeps `ordered = list(ops)` going back) | RED, 17 failures, among them both rename tests (`changedSince` != `undone`), the ops both ways, and the U4b stack cases |
| M2 | Mac: the replay names each carried edit at the folder's OLD place | RED, `UndoActionStepsTests.swift:1671`: the replay throws at `action-154`'s hand edit, because the step did not move the folder |
| M3 | Python: a refused move always named by its `from` | RED: `test_a_refused_undo_of_a_rename_names_the_renamed_folder` and the stale-traces test |
| M4 | Mac: a rename's page keyed by `canonicalPath` (follows the link) | RED, `UndoRenameFolderStepTests.swift:312` (zzz.md first) |
| M5 | Mac: the tie-break removed | RED, `UndoRenameFolderStepTests.swift:325` |

5 of 5 RED. M2, M4 and M5 were in one build: each test has its own sabotage.

What each test proves:

- `test_a_rename_step_undone_ends_at_its_fixture_and_redone_at_the_recorded_after`: undo is the identity on places and bytes, and redo gives the recorded afters. It fails if the move goes back before its edits.
- `test_a_rename_trace_hashes_each_folder_by_its_listing_at_both_ends`: each folder at its old place carries the recorded `listingSha`. It fails if `folder_hash` or the laying is removed.
- `test_a_refused_undo_of_a_rename_names_the_renamed_folder`: the place a refusal names, in both directions.
- The Mac replay: model and Mac agree call by call. It went red before it learned folder moves (`run-red2.log`, the old replay throws at `action-154`).

## Runs

Logs are in `/Users/russellgordon/plantoir/wt-899-u4b2-12/.dd/`.

- Python red first: 2 errors and 2 failures (the new functions absent, the trace count 150 != 162). Then 36 OK. `make_undo_traces.py --check`: current.
- `run-red1.log`: this build picked up my new replay while it compiled, so it is not the red run. It found the one disagreement (`action-154` call 4, Mac `Ideas`, model `Concepts`), which led to the model fix above.
- `run-red2.log`: the old replay against the new traces: RED (it throws at `action-154`).
- `run-red3.log`: the new replay GREEN. The lows' new tests ran against stubs that keep the old behaviour: RED for the linked page (:312) and the case tie (:325), and :329 showed that a file URL folds the Unicode form (the assertion was then corrected to say so).
- `run-write.log`: re-recorded with `TEST_RUNNER_PLANTOIR_WRITE_UNDO_ACTION_STEPS=1`. `contracts/undo-action-steps.json` changed in its note line only.
- `run-green1.log`: UndoActionStepsTests, UndoJournalContractTests, UndoFilesContractTests, UndoRenameFolderStepTests, SpecialFolderRenamerTests, UndoWriterScanTests (which reads changed product files as source): 139 tests, 0 failures.
- `run-mf.log`: M2, M4, M5.

`git diff` of `undo-traces.json` against piece 11: the 150 earlier action traces, the 20 seeded traces, the note and the fixture are unchanged (checked by script). Only `actionNote` and the twelve appended traces changed.

## Left for the next piece

- Piece 13: the model's recovery with a hand edit (not touched).
- The model cannot hold an empty folder. A rename trace therefore never deletes the last page of a moved folder, and a listing with an empty folder inside raises in `lay_folder_moves`. Neither recorded step has one. If a later recording does, the model needs a representation for an empty folder.
- Piece 14 merge: my `make_undo_traces.py` edits are in new functions and in `plan`'s whole-op refusal line, `files_step`, `action_trace` and `path_hashes`. Piece 14's hunks are in `tree_reading`, `move_state` and the `page_item` area, so the two should merge without a conflict. The new `place_as_found` sits beside the `EDIT_KINDS` line.

## For the director

- `contracts/` changed: `undo-traces.json` (the note and 12 traces) and `undo-action-steps.json` (the note line). Both gates are needed, taken with piece 11.
- Windows: the twelve trace names needed ledger entries, and they were added. No other Windows test enumerates them.
- HIG: nothing a teacher sees or hears changed (the page order of a rename's relink is internal), so no section was read.
- Nothing is parked. The one disagreement was the model's, and the Mac rule it now copies was settled in U4b.

## Self-check

1. Broke each fix and watched its test fail: M1 to M5, 5 RED.
2. No timed waits were added.
3. Every sentence on the failure paths is true. No product sentence changed. The ledger reason and the notes on Windows were read against `UndoActionTraceContractTests.cs`.
4. `dev` merged before proving and before hand-back: up to date both times.
5. No number was tuned by trial (12 = 2 steps x 6 traces per step).
6. Contracts: `undo-traces.json` was written by the generator, and the steps file by the recorder. Nothing outside the brief was touched.
7. `grep -n "DispatchQueue\|\.map {\|\.filter {\|\.reduce(\|\$0"` over the changed Swift lines: empty. No new type was authored (the static funcs sit inside existing MARK sections).
8. Lows A, B and C were fixed. A and B have tests that were red first against stubs. C is the restructured test, made independent of the volume's order.
9. The rename record is still kept, and `undoJournalIsLive` is untouched (off).
10. All twelve new traces are in the Mac's replay and held on Windows by exact name.
