# #1055 M5: no step hands a place over; the kept-page guard re-laid on a plain step

Branch `issue/1055-M5-no-step-hands-a-place-over`, stacked on M4's pushed head 93406dce2 (no merge needed: `origin/dev` and M4's head had not moved at 14:22, both already in). Touches `contracts/` (`shared-rules.json`, two rows and one `recoveryCasesHow` sentence added): both gates (the director's).

## State at hand-back (2026-11-27, about 14:25): NOT FINISHED

Done and pushed (every pushed commit builds, its classes green):

1. The four guard tests, re-laid on a plain step with no link, in the new `mac-app/Tests/QuartzTeachersTests/UndoKeptPageUnderAVisibleNameTests.swift` under `// MARK: - The kept-page guard on a plain step (#1055 M5)`: green on M4's head (commit 3b4f345d4), all four RED on the throwaway mutant (below), the mutant reverted, never committed.
2. The two re-laid recovery rows in `undo.recoveryCases`, after the two old kept rows (which stay until the removal): "U4b3 kept-original-named, re-laid (#1055 M5): a step that removes Day 3's page ..." and "... re-laid (#1055 M5): the same, with Unit 1, Day 3 (kept by Undo).md already taken: ...". Same `work`, `stopAt` (beforeSwap:2), `files` (unchecked), `phase` (interrupted), `head` (null), `cleared` (interrupted), `keptVisibleAs`, `keptPageLines` (1), `visibleNameTaken` as the old rows; no `handEdit`, no `handedOver`, no `pathsNamed` (both keys go with the handover). ONE new key, `withAPlainPageMove` (true), defined in one sentence at the end of `recoveryCasesHow`: the plain step (Day 3 `Three.` to Day 4, Day 3 removed, `Five.` at Day 5) and `Someone else's.` written at Day 3 before recovery. Laid by the Mac replay (`UndoContractReplay.swift`: the key, a `plainPageMove` shape through the handed-over path's twin and call; `UndoContractReplayKinds.swift`: the call `movePlainPageAwayFromDay3`) and by the Python model (`test_recovery_cases_with_a_plain_page_move`). `UndoJournalContractTests` recovery count 72 -> 74. Both rows green on the Mac replay, and both RED (three failures each, as the old rows) with `keepPagesWhosePlaceIsTaken` returning at once (mutant reverted). When the removal takes out the handed-over path, the plain step's laying in the replay must be kept (re-homed off `handedOverCall`).
3. Windows: both re-laid rows held by exact name (`Reason1055KeptPageReLaid`, one `Owed(UndoRecoveryCases, 1055, V200, ...)` above the U4b3 relink comment in `NamedGapLedger.cs`): `withAPlainPageMove` is not in `UndoRecoveryContractTests.KeysChecked`, so each held row stops at "a key this replay does not check". Edited by reading only: `windows-app/Plantoir.Tests/NamedGapLedger.cs` (one constant, one entry; quotes, commas, parentheses read back).

Left (nothing of it started; no half-removed state anywhere):

- The whole Remove list of the brief (product, tests, `shared-rules.json` door rows and the two OLD kept rows, `file-formats.json`, Python, notes top lines), the row-count script, and the done-means greps.

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
- `run-rows`: `UndoJournalContractTests` 19 of 19 green with the two rows (74 recovery cases).
- `run-rows-mutant`: `testRecoveryCases` red on both re-laid rows (and the old two) with `keepPagesWhosePlaceIsTaken` returning at once; reverted.
- `run-rows2`: `UndoJournalContractTests`, `SharedRulesContractTests`, `UndoKeptPageUnderAVisibleNameTests`: 90 green.
- `run-readers`: `UndoOpKindsTests`, `RestoreWholeCourseContractTests`, `JournaledStepTests`, `FileFormatsContractTests`: 85 green.
- Plain Debug build: succeeded.
- `python3 scripts/test_make_undo_traces.py`: 40 OK (traces not stale).

## Windows

Edited: `windows-app/Plantoir.Tests/NamedGapLedger.cs` only (the hold above). The Windows suite should stay at its six known failures.

## COMMON's self-check

- Swift rules: no map/filter/reduce, no `$0`, explicit loops, `// MARK: -` sections in the class and both structs, no GCD, no timed waits: yes.
- No teacher-visible wording changed; no new handling or edge case.
- No UI class, no app launch, no gate, no whole suite.

## Parked

- The replay also accepts `withAHandedOverPlace: plainPageMove` as an alias of the new key (a side effect of reusing the handed-over path); it goes with the removal.
