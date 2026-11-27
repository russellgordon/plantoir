Removed by #1055 (2026-11-27): symbolic links in course content are not supported.

# #899 U4b3 door-5: a step that hands a place over, killed before any of its swaps, settles whole

Brief: `vm-tools/briefs/2026-11-26-899-u4b3-door-5-a-killed-handover-settles-whole.md` (chain: `2026-11-26-899-u4b3-ORDER.md`, fifth link). Branch `issue/899-u4b3-linked-class-page-moves-its-link`, worktree `wt-899-u4b3`, from door-4's head 84bee6dc4. **`contracts/` touched: both gates.**

## For PROGRESS

- `undo.recoveryCases`: 8 rows "U4b3 door-5: …", key `withAHandedOverPlace` (`afterALinksMove`, `beforeALinksMove`), defined in one sentence at the end of `recoveryCasesHow` with its swap order (the step's order; an undo reversed), what `files` means for it (the class pages and the library before or after, not `first` and `second`), `handedOver` (stackCases' key), and `handEdit` `handedOverPlace`. Rows: shape A forward at `beforeSwap:1` (rolledBack, before); A's undo at `beforeSwap:1` (done, after); A forward at `beforeSwap:1` with someone's page then written at Day 3 (interrupted, both of the pair in the way, nothing written over it, the list cleared, naming Day 3 as a plain path); shape B forward at 1, 2 and 3 (rolledBack, before); B's undo at 1 and 2 (done, after). B's three forward rows all roll back, but each with a different set of ops in (the copy, the copy and the removal, those and the link's move), so none says the same thing for the same reason; all kept.
- Door-3's parked naming, settled: recovery still judges a handed-over move under its key `from → to` (it must be told apart from the page at the same place), but a teacher and the trail are shown a plain path: the move's own place (`placeName`, its `from`), as every other move is named, each path once. `UndoRecovery.placesShown(of:)`; in `settle`, `pathsOnly` maps and de-duplicates, `cannotTellNow(path:)` names the plain path, and the counts on the trail (`interrupted(filesInTheWay:)`, `interruptedLine`, `couldNotPutBackLine`) count shown paths. For a step with no handover nothing changes (the map is empty). Rejected: naming the move's `to` (in shape B both places are handed over, so `to` is the removal's own path too, and the two names would disagree with how every other move is named) and naming both places (a teacher looking at Day 3 is told about Day 4, which nothing put in the way).
- A gap door-1 did not reach, fixed in one place: `JournaledWrite.vet`'s "every path stays inside" check followed the link at a handed-over place for the file op that shares it, so a step whose link leads OUT of the working folder was refused at the door (`refused(notReadable)`) though the plan (door-1) judges the same op on the folders above only. `vet` now judges the file op of a pair in which a link moves with `UndoPlaces.staysInsideAbove`, as the plan does. About fifteen lines; proven by the leading-out kill test (M4).
- Mac replay: `UndoContractReplay.runRecoveryCases` knows `withAHandedOverPlace` (made through door-4's calls, killed by `beforeSwap:N`), reads `before` and `after` from a twin folder (the call made whole, then undone), `handedOver`, and `handEdit` `handedOverPlace`. `UndoJournalContractTests.testRecoveryCases` counts 70.
- Unit tests: `UndoHandedOverPlaceTests`, `// MARK: - Killed and recovered (door-5)`: each shape through `JournaledWrite.perform(ops:)` by a gone process, killed before every swap in turn going forward and, for its Undo, going back (2 kills for A, 4 for B, each way), recovered by another process with `UndoRecovery.run`: the folder whole before or whole after (by link target and bytes, the library included), nothing staged, the step settled; once with the links inside the working folder and once leading out (nothing outside changed).
- Python: `recovery_states` judges the pair together as door-3's Swift does (`moves_handing_over`, `place_judged`), and a link or folder where a page is named is `neither` (it used to raise). `recover` names places as `places_shown` (the plain path, each once). `put_back_what_took_effect` picks ops by the judged name. New test `test_recovery_cases_with_a_handed_over_place` replays the 8 rows through `stopped_part_way` (which now reaches door-4's `swap_groups` order for such a step: proven by these rows, not only `HandedOverOrderTests`) and `recover`.
- Documentation 09: one passage added to door-4's paragraph "U4b3 door: a place handed over within a step".

## For documentation 12

- Windows' `UndoRecovery` settles such a step whole by door-3's two tables (its notes, "For documentation 12"). Then, in its settle, show a handed-over move under its own place (its `from`), as every other move is named: the `interrupted` line's `paths`, the cannot-tell-now refusal and every count on the trail name each plain path once, never `from → to`. The row "… naming Day 3 as a plain path …" pins it.
- Windows' door (`JournaledWrite`'s vet, the "stays inside" look): a file op that leaves or fills a place a link's move hands over is judged on the folders above the place only, as the plan judges it; otherwise a link leading out of the working folder refuses the step.
- New rows: 8 `recoveryCases` rows, every name beginning "U4b3 door-5:", held under `Reason899W8HandedOverPlace` in `NamedGapLedger.cs` (reworded to add the recovery half). Each name occurs once in `shared-rules.json` and once in the ledger, checked by script. Why each fails on Windows today: every row carries `withAHandedOverPlace`, which is not in `UndoRecoveryContractTests.KeysChecked` (line 23), so the walk fails at line 86, "a key this replay does not check: withAHandedOverPlace", before anything is made.
- The W8 harness (`windows-app/Plantoir.UndoHarness/`) should kill such a step at every swap too, each way, with a link leading out once: the Mac's kill test is the model.

## Must-fail lines

`windows-app/notes/899-u4b3-door-5-mustfail.log`. Red first: the naming row failed on door-4's base (the interrupted line named `… Day 3.md → … Day 4.md` and `… Day 3.md`); the other seven rows passed there, as door-3 built recovery's judgement. M1 (leaver judgement out): two rows and both kill tests fail (shape B, forward, before swap 3: not whole). M2 (filler judgement out): three rows and both kill tests fail. M3 (Python pair rounds out): the five shape-B rows fail. M4 (vet without the above-only look): the leading-out kill test fails, `refused(notReadable)`. M5 (Python `places_shown` the identity): the naming row fails. RED 5 of 5.

## Runs

- Red first: run-door5-red.log (UndoHandedOverPlaceTests, UndoJournalContractTests).
- Green: run-door5-green2.log, 56 of 56.
- Proof (run-door5-proof.log): UndoHandedOverPlaceTests, UndoJournalContractTests, UndoFilesContractTests, UndoRenameFolderStepTests, RestoreRecoveryTests, UndoWriterScanTests, SharedRulesContractTests, JournaledStepTests, UndoDoorGuardTests and the 13 other classes that read documentation 09 as text: 337 tests, 0 failures.
- Python: `test_make_undo_traces.py` 38 tests OK; the traces are not stale.
- `origin/dev` 461ee3943 was already in the branch at the start and at hand-back (door-4 merged it, 97d312ec9): no merge commit.

## Left for the next piece

- door-6 (`JournaledStep`): the vet's above-only look is now in `JournaledWrite.vet`; `JournaledStep`'s own planning of a link move's old place as free is still door-6's.
- Nothing of this piece is half done.

## For the director

Nothing parked. One decision taken inside the brief's room and recorded above: a handed-over move is shown under its `from` (its `placeName`). Change it before part 2 if a teacher should see the other place.

## Self-check

1. Broke each fix and watched it fail: M1 to M5 (log).
2. No timed waits.
3. Failure paths: the only sentence a teacher can meet is the existing interrupted and cannot-tell-now lines; they now name a plain path.
4. `dev` already merged (unchanged 461ee3943).
5. No number tuned by trial.
6. Scope: `UndoRecovery.swift`, `JournaledWrite.swift`, the two test classes and the replay, `shared-rules.json`, the two Python scripts, the ledger, documentation 09, these notes and the log.
7. The grep for `DispatchQueue|.map {|.filter {|.reduce(|$0` over the changed Swift lines is empty; MARK sections in place.
8. No riding lows.
9. The rename record is still kept and the switch is still off (not touched).
10. Eight new rows, all in the Mac replay and the Python model, all held by exact name for Windows.
