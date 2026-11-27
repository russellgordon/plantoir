# #1055 M5: no step hands a place over; the kept-page guard re-laid on a plain step

Branch `issue/1055-M5-no-step-hands-a-place-over`, stacked on M4's pushed head 93406dce2 (no merge needed: `origin/dev` and M4's head had not moved at 14:22, both already in). Touches `contracts/`: NOT YET (nothing under `contracts/` changed in what is pushed).

## State at hand-back (2026-11-27, about 14:25): NOT FINISHED

Done and pushed (every pushed commit builds, its class green):

1. The four guard tests, re-laid on a plain step with no link, in the new `mac-app/Tests/QuartzTeachersTests/UndoKeptPageUnderAVisibleNameTests.swift` under `// MARK: - The kept-page guard on a plain step (#1055 M5)`: green on M4's head (commit 3b4f345d4), all four RED on the throwaway mutant (below), the mutant reverted, never committed.

Left (nothing of it started; no half-removed state anywhere):

- The two re-laid recovery rows in `undo.recoveryCases` ("... re-laid (#1055 M5): ..."). They need one new key for the plain step (the old rows' step is `withAHandedOverPlace: beforeALinksMove`, which is to go), defined in `recoveryCasesHow`, laid by the Mac replay (`UndoContractReplay.swift` about 1720 to 2230: a new call in `UndoContractKinds`, the twin, `files`, `handEdit`, `keptVisibleAs`, `visibleNameTaken`, `keptPageLines`) and by the Python model (`scripts/test_make_undo_traces.py` `test_recovery_cases_with_a_handed_over_place`, `traces.recover`, `traces.keep_pages_whose_place_is_taken`). Then the Windows hold (`NamedGapLedger.cs`, `Reason1055KeptPageReLaid`), since the key would be new to Windows.
- The whole Remove list of the brief (product, tests, `shared-rules.json`, `file-formats.json`, Python, notes top lines), and the done-means greps.

## The plain step chosen, and why it reaches the state

No ordinary Insert Class through `JournaledStep` was used: the tests lay the ops directly, as the old tests laid shape B, so the swap and recovery are what is under test. The step is Insert Class's plain move of Day 3's page with no link: `writeFile` Day 4 (new, holding `Three.`), `writeFile` Day 3 (`Three.` -> removed), `writeFile` Day 5 (new, `Five.`). At the last swap (Day 5) a plain file `Someone else's.` is written at Day 3 and the swap is refused (`fileInUseAtSwap` true). The swap's reversal then cannot put Day 3's page back, because `putBackAKeptOriginal` puts a removal back exclusively (fdc4d3b55): `notPutBack`, the page kept beside its place. Recovery by another process then finds Day 3 taken and `keepPagesWhosePlaceIsTaken` names the page `Unit 1, Day 3 (kept by Undo).md`. For test 2 (an Undo taking a new page away), the step writes new pages at Day 5 then Day 3; its Undo (reversed) takes Day 3's away first, and the same happens at the Undo's last swap.

So the STOP condition does not apply: an ordinary step with no link reaches the guard (both the never-write-over check of fdc4d3b55 and `keepPagesWhosePlaceIsTaken`).

Differences from the old tests, said plainly: the swap's refusal is `fileIsInUse` naming Day 5 (the old tests' `changedSince` naming Day 3 came from the handed-over filler's own check, `placeIsLeftEarlier`, a handover-only hunk of fdc4d3b55), so tests 1 and 2 assert `notPutBack` with one kept original, not the refusal's path. The plain case keeps fdc4d3b55's effect through `putBackAKeptOriginal`/`renameExclusively`, which is not handover-only; `placeIsLeftEarlier` is handover-only and may go with the removal.

## The mutant (throwaway, reverted, never committed)

`UndoSwap.putBackAKeptOriginal` always `rename` (replacing), and `UndoRecovery.keepPagesWhosePlaceIsTaken` returning true at once. All four tests red: lines in `windows-app/notes/1055-M5-mustfail.log` (9 failures in 4 tests). Note: `placeFilled(by:)` is not on the swap's path at all (only recovery's `keepPagesWhosePlaceIsTaken` and the handover code read it), so for tests 1 and 2 the mutant that pins the guard is the exclusive put-back, not `placeFilled`.

## Runs (all through `xlock.sh`, one class, 15-minute kill)

- `run-guard1`: 3 of 4 green; test 2's step ordered so Day 3 was swapped last (fixed by ordering the ops).
- `run-guard2`: 4 of 4 green on M4's head.
- `run-mutant`: 4 of 4 red, 9 failures; mutant reverted (`git status` clean after).

## Windows

No Windows file edited.

## COMMON's self-check

- Swift rules: no map/filter/reduce, no `$0`, explicit loops, `// MARK: -` sections in the class and both structs, no GCD, no timed waits: yes.
- No teacher-visible wording changed; no new handling or edge case.
- No UI class, no app launch, no gate, no whole suite.

## Parked

- None.
