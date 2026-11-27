# U4b3 relink-3 (#899): a step with a relinking move, killed at any moment of its swaps, is settled whole

Brief `vm-tools/briefs/2026-11-26-899-u4b3-relink-3-a-killed-relink-settles-whole.md`, from relink-2's pushed head 48693cee0 on `issue/899-u4b3-linked-class-page-moves-its-link` (clean). `origin/dev` still 06e067fbe (already merged in) before proving and before handing back: no merge needed. **`contracts/` touched: both gates.**

## For PROGRESS

- `UndoKillPoint` gains `relinkStaged(Int)` and `relinkRenamedIn(Int)`. `UndoSwap.relinkLink` now answers `UndoRelinkOutcome` (`made`, `failed`, `stoppedByATest`) and takes `stoppingAt:` (the target's index; the swap going in passes it, a reversal passes none), checked after the staged link is made and after it is renamed in; the swap returns `.stoppedByATest` from there.
- `UndoRecovery.removeTheLinksJustMade(of:root:goingForward:)`, called in `settle` after the live tidy and before `fileStates`, live mode only (shadow recovery never writes into a working folder, so there both links standing is neither and the step closes interrupted, as the recovery rule says for shadow). For each relinking move with `from` holding the `linkShaBefore` text and `to` the `linkShaAfter` text (`lstat`, `readlink`, `UndoMoveSide.readLink`), the link at the interrupted swap's destination (`to` for `begin` and `redoing`, `from` for `undoing`) is re-read and `unlink`ed (`UndoSwap.removeALink`). Either side unreadable, or the unlink failing: `cannotTellNow`, the step left for the next recovery. A side whose folders lead out of the working folder (`UndoPlaces.staysInside(_:_:namedBy:)`) is skipped (judged as always).
- A staged new link (`relinkStaged`) is removed by `tidyLeftovers` as the swap's own staged item: proven by the `relinkStaged` row and the every-moment test (nothing containing `.plantoir-undo-` left; the link's target, a file outside or nothing, untouched, so `removeItem` removed the link itself and `isAFolderSetAside`'s `lstat` never took it for a folder).
- Contract: `undo.recoveryCasesHow` one sentence (`withARelink`, its two shapes, the two stop points, `files` over Day 3 to Day 5); `undo.rule.recovery` one clause (after "half applied"); seven `recoveryCases` rows "U4b3 relink-3: …" (70 to 77).
- Mac replay: key `withARelink` (`alone` → `relinkALink`, `leavingAHandedOverPlace` → `relinkALinkLeavingAHandedOverPlace`, new calls in `UndoContractKinds`), the twin read over `relinkedDays` (3, 4, 5) by `handedOver(in:days:)`, the stop points parsed, and the "nothing staged left" check now also for the handed-over and relink shapes. `UndoJournalContractTests` count 77.
- Python: `whole_moved` makes a relink's destination with that side's text (the model's `linkTexts` stands for the list's two blobs); `stopped_part_way(..., inside=)` for the two inner moments; `remove_the_links_just_made` called first in `recover`; `test_recovery_cases_with_a_relink`. Traces not stale.

## Rows (seven)

`alone`: forward `relinkStaged:0` (failed), forward `relinkRenamedIn:0` (failed), undo `relinkRenamedIn:0` (done). `leavingAHandedOverPlace`: forward `relinkRenamedIn:0` (failed), `beforeSwap:1` (rolledBack), `beforeSwap:2` (rolledBack), undo `beforeSwap:1` (done). None dropped: the staged and renamed-in rows differ (a staged item tidied against a link removed), the shape-B renamed-in row proves the removal comes before the pairing (Day 4 then holds only the old link), `beforeSwap:1` puts back the relink alone and `beforeSwap:2` the relink and the page across the handed-over place. No `handedOver` key: door-4's reads Day 2 to Day 4, not these days; `files` compares Day 3 to Day 5 with the twin instead.

## For documentation 12

Windows' `UndoSwap` relink gains the same two stop points inside it (after the staged link is made; after it is renamed in), reached only going in, never in a reversal. `UndoRecovery` (live only), before judging a step, removes for each relinking move whose two links both stand holding their own texts the one at the interrupted swap's destination (`to` for begin and redoing, `from` for undoing), re-read first; an unreadable side or a failed removal is cannotTellNow. A plan never does this. The recovery harness and `UndoRecoveryContractTests` learn `withARelink` (`alone`, `leavingAHandedOverPlace`, shapes as in `recoveryCasesHow`), `relinkStaged:N` and `relinkRenamedIn:N`, `files` over Day 3 to Day 5, and nothing staged left; the harness (`windows-app/Plantoir.UndoHarness/`) kills a relink at every moment. Held: the seven rows by exact name under `Reason899W8RelinkedLink` in `UndoRecoveryCases` (script check: each name once in each file, 7 of 7); each fails on Windows today because `withARelink` is not in `UndoRecoveryContractTests.KeysChecked` ("a key this replay does not check").

## Must-fail lines

RED 4 of 4 (`899-u4b3-relink-3-mustfail.log`): M1 run-r3-red2, M2 run-r3-mf2, M3 run-r3-mf3, M4 Python.

Red first: run-r3-red2, the removal disabled (the code as it was, with the stop points it needs to be reached): the three `relinkRenamedIn` rows and every `relinkRenamedIn` moment of the kill test red (38), the four other rows green, as they must be. (run-r3-red, the first try, also showed two faults in the new test, fixed: outside files laid after the "before" look, and the out-leading loop run on shape B; see "For the director" 1.)

## Runs (`.dd/`)

run-r3-red, run-r3-red2, run-r3-green1 (UndoRelinkTests and UndoJournalContractTests, 33 of 33), run-r3-mf2, run-r3-mf3, run-r3-green (UndoRelinkTests, UndoHandedOverPlaceTests, UndoRenameFolderStepTests, RestoreRecoveryTests, UndoJournalContractTests, UndoFilesContractTests, UndoWriterScanTests, SharedRulesContractTests: 225, 0 failures). `python3 scripts/test_make_undo_traces.py` OK (40). No test reads documentation 09 as text (grep); the writer scan's counts unchanged (recovery's unlink goes through `UndoSwap.removeALink`).

## Left for the next piece

- relink-4: `JournaledStep.relinkLink`.
- No barrier case met that Windows can neither pass nor hold.

## For the director

1. **A step that moves a page into a place a link leading OUT of the working folder leaves is refused `notReadable` by the door's vet** (`JournaledWrite.vet`: every path must stay inside through its links, and the page's `to` is, at that moment, the link leading out). Met while writing the kill test (shape B with absolute outside texts); not built here (the door, out of scope). The every-moment test runs the out-leading texts on the relink alone and shape B with inside texts only, and says so. By the same vet it is very likely the same for a plain link's move (not run); relink-5 (Insert Class re-pointing a later class) meets it when a later class leads outside the working folder. Options: (a, recommended) relink-5's brief checks it against Insert Class's own rows and, if a later class can lead outside, the vet judges a handed-over place by the folders above it only, as the swap already does (`placeLeadingOut(atStaging:)` with `handedOver`); (b) leave it: such a step is refused before anything changes.

## Self-check

1 to 6 (NIGHT3): own classes only through `xlock.sh`, no gate, no Windows, no UI test, no window; red first and must-fail recorded; notes written. 7: house-style grep over added Swift lines empty; the new enums need no MARK (no properties or functions), the test class's sections kept with a `Killed and recovered (relink-3)` section. 8: no riding lows. 9: switch off, rename record untouched. 10: every new row in the Mac replay and Python; all seven held by exact name.
