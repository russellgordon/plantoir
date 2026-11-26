# #899 U4b3 door-4: a step that hands a place over is readable

Brief: `vm-tools/briefs/2026-11-26-899-u4b3-door-4-a-handed-over-place-is-readable.md` (chain: `2026-11-26-899-u4b3-ORDER.md`). Branch `issue/899-u4b3-linked-class-page-moves-its-link`, worktree `wt-899-u4b3`, from door-3's head b0fed2c19. **`contracts/` touched: both gates.**

## For PROGRESS

- `contracts/file-formats.json` → `undoJournal.opKinds.wholeOps` now names TWO exceptions. The second (U4b3) is a place handed over within the step. It is written as doors 1 to 3 built it: the pair and what leaves and fills, the one comparison, which moves never hand over, and "each leaver hands its place to the first filler after it". Then the order in each direction (the second of the pair judged with the place free when the first is a change of the same check), the leaves-the-folder look on the folders above, the place judged whole just before the change, and recovery's judgement. Last, what stays unreadable: a filler before its leaver, a third op, a place handed over twice, and a handover in a step that carries an edit. `opKinds.move`'s link sentence now says a link's old or new place may be handed over, its new place never written inside. `grep "no other op"` finds only `wholeOps` itself, now corrected.
- `UndoStep.wholeOpsStandAlone` (`UndoFormat.swift`) finds the step's handovers with door-1's `UndoCheck.handovers(in:)`, the one rule. A step with any handover must carry no edit (`UndoCheck.carriers` empty) and hand each place over once. In the pairwise overlap test, the exact handed-over place shared by exactly that leaver and filler (`UndoStep.isHandedOver`) is the only sharing passed over. Everything else is refused as before. A filler before its leaver is never a handover (`handovers` looks only after the leaver), so its overlap still refuses. A third op at, inside or above the place overlaps the pair's move, which is whole, so it refuses too. `JournaledWrite.vet`'s read-back therefore lets such a step be made, and Undo and Redo take it.
- `stackCases`: 7 rows "U4b3 door, …", 5 calls and the key `handedOver`, each in one sentence of `stackCasesHow`. `handedOver` reads `Day 2: …; Day 3: …; Day 4: …; library: untouched|changed`. The brief asked for "the handed-over place(s), then the move's other place". I wrote it as all three days in day order, plus the library, because in shape B both of the move's places are handed over and that order has no single answer. For shape A it gives the brief's order. Mac replay: `UndoContractReplayKinds` (the calls, `handedOver(in:)`, the helpers `layALink` and `appendAStepChangingNothing`) and `UndoContractReplay.stackKeys` with its check.
- The `why` of the row "U4b2-14, review 1: a link's move with an edit inside its new place" said "The only exception to opKinds.wholeOps". It now names the edit exception as the first and says the second never covers an edit inside a move's new place.
- Python: `make_undo_traces.handovers` (with `hands_over_as_a_move`, `place_left` and `place_filled`, Swift's rule word for word). `plan` judges the second of a pair with the place free when the first is a change of the plan: a move's `to` going forward or its `from` going back is popped, and a file op starts from absent. In a step with a handover, `plan` gives the changes in its own order, so the last op at a place sets what it holds. `swap_groups` gives such a step in the step's order, reversed going back, with a file at the first op naming it. `test_make_undo_traces.readable_step` carries the shape rule as Swift's. The model's calls go through `vetted_ops_step`, which refuses a step `readable_step` refuses, as `vet` does. New test `HandedOverOrderTests` pins `swap_groups` for shape B in both directions.
- Unit tests: `UndoHandedOverPlaceTests`, section `// MARK: - Readable by shape (door-4)`, 9 tests. Readable: shapes A, B and C, and A read back through the journal's coding. Unreadable: the filler first, a third op at P, P inside a moved folder's `from` (and the folder's own place written), a case-only move, a `moveApart`, a handover in a step that carries an edit (the same edit without the handover is readable), and P handed over twice.

## For documentation 12

- Windows' `UndoFormat.ShapeIsKnown` (the step's wholeOps check) must accept exactly the pairs of `opKinds.wholeOps`' second exception. Find the pairs with the same rule the plan uses: for each leaver (a file's or link's `move` at its `from`, or a `writeFile` with a before-hash and no after-hash), the first later filler at the exact same place (a file's or link's `move` at its `to`, or a `writeFile` with no before-hash and an after-hash), compared part by part ignoring case, at least one of the two a move (never `listingSha`, a capitalisation-only move, `moveApart` or `setAside`). Then:
  1. if there is any pair: refuse when the step carries an edit (an edit named inside a move's new place after it, U4b) and when two pairs name the same place;
  2. in the overlap test between a whole op and another op, pass over ONLY the overlap of the pair's own place, between exactly the pair's two ops; every other overlap refuses as today. A filler before its leaver and a third op at, inside or above the place are therefore refused with no rule of their own.
- What the plan, the swap and recovery must do is in doors 1 to 3's notes (`899-u4b3-door-1-*.md`, `-door-2-*.md`, `-door-3-*.md`, each under "For documentation 12"). The Python model (`scripts/make_undo_traces.py`: `handovers`, `plan`, `swap_groups`) is the executable statement of the same rule.
- Held rows: 7 `stackCases` rows, every name beginning "U4b3 door,", under `Reason899W8HandedOverPlace` in `NamedGapLedger.cs`. Each name occurs once in `shared-rules.json` and once in the ledger, checked by script. Why each fails on Windows today, read in `UndoStackContractTests.cs`: rows 1 to 5 carry the key `handedOver`, which is not in `KeysChecked` (line 19), so `WalkTheCase` fails at line 74, "a key this replay does not check: handedOver", before any call (row 5 also carries `refusalNamed`, likewise unchecked). Rows 6 and 7 carry no new key. Their second call (`stepFillingAPlaceBeforeItIsLeft`, `stepHandingOverAFoldersPlace`) reaches the end of `StackReplay.Call` and fails at line 488, "a call this replay does not know". Both messages are among the two `HeldCaseStillStopsAtItsGap` accepts (line 63).
- The Windows door piece that builds all of this (ShapeIsKnown, Plan, Swap, Recovery, the harness kills, UndoDoor) is the director's to add to the W8 ORDER, before W8b piece 22.

## Must-fail lines

`windows-app/notes/899-u4b3-door-4-mustfail.log`. Each sabotage was built and run, then restored from a saved copy. `git diff` showed only this piece's change after each.

- M1 (`wholeOpsStandAlone` back to door-3's rule, the red run itself): rows 1 to 5 fail on the Mac, and the readable-shape unit tests fail.
- M2 (a link's move may share its exact place with any op, in any order): row 6 ("a place filled before it is left") fails, along with `testAFillerBeforeItsLeaverIsUnreadable` (and `testAThirdOpAtTheHandedOverPlaceIsUnreadable`).
- M3 (a folder's move may share its exact place): row 7 ("a folder's move whose place is then written") and `testAPlaceInsideAMovedFoldersFromIsUnreadable` fail.
- M4 (Python `readable_step` without the handover rule): rows 1 to 5 fail in `test_make_undo_traces.py`.
- M5 (Python): `swap_groups` back to today's order fails `HandedOverOrderTests` only. The stack rows never reach `swap_groups`: it is used only by `stopped_part_way`, recovery's model, which is door-5's. Rows 3 and 4 depend on `plan`'s own order of changes. With that order reverted to today's (whole changes, then files), rows 3 and 4 fail (Day 3 ends empty, not the link). Both sabotages are recorded.

RED 5 of 5.

## Runs

- Red first (product change set aside, the new tests and rows in place): `UndoHandedOverPlaceTests` and `UndoJournalContractTests`, 54 tests, 5 failing. They were `testStackCases` (rows 1 to 5: the step refused at the read-back, so nothing was offered, "nothingToUndo"), `testShapesAAndBAndCAreReadable` and `testAHandedOverStepIsReadBackReadable`. Rows 6 and 7 and the refusal unit tests passed on the base, as guards should. M2 and M3 are their must-fails.
- Green: the same two classes, 54 of 54.
- Proof: `UndoHandedOverPlaceTests`, `UndoJournalContractTests`, `UndoFilesContractTests`, `UndoRenameFolderStepTests`, `UndoDoorGuardTests`, `UndoWriterScanTests`, `JournaledStepTests`, `SharedRulesContractTests`, every class that reads `file-formats.json` about the journal (`FileFormatsContractTests`, `UndoActionStepsTests`, `SpecialFolderRenamerTests`, `RestoreRecoveryTests`, `DoorCourseHoldTests`), and the 14 classes that read documentation 09 as text: 440 tests, 0 failures.
- Python: `test_make_undo_traces.py` 37 tests OK, and the traces are not stale (`test_the_committed_traces_are_what_the_generator_writes` passes; `make_undo_traces.py` not re-run).
- `origin/dev` 461ee3943 was merged in at the start (97d312ec9; one conflict in documentation 09, both sections kept). Before hand-back `origin/dev` was still 461ee3943, already in the branch, so no second merge commit.

## Left for the next piece

- door-5: `recoveryCases` rows and the Python recovery model for a handed-over step. `swap_groups`'s new order is pinned so far only by `HandedOverOrderTests`. Door-3's parked naming (`from → to` in `interrupted` paths and `cannotTellNow`) is still door-5's.
- door-5 or part 2: the stack rows lay links whose targets stay inside the working folder only. Door-1's tests cover links that lead out.

## For the director

Nothing parked.

## Self-check

1. Broke each fix and watched it fail: M1 to M5 (log).
2. No timed waits.
3. Failure paths: no new sentence a teacher reads. The refusal is `unknown.unreadableStep`, as before.
4. `dev` merged at the start (97d312ec9). Unchanged at hand-back.
5. No number tuned by trial.
6. Scope: `UndoFormat.swift`, the test class, the replay, two contract files, the two Python scripts, the ledger, documentation 09, these notes and the log.
7. The grep for `DispatchQueue|.map {|.filter {|.reduce(|$0` over the changed Swift lines is empty. MARK sections are in place.
8. No riding lows.
9. The rename record is still kept and the switch is still off (not touched).
10. Seven new rows, all in the Mac replay and the Python model, all held by exact name for Windows.
