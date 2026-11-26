# #899 U4b2-2: a leaves-the-folder refusal names the place that leads out

Branch `issue/899-u4b2-2-leaving-place-named`, from `origin/dev` a03fecefd. Writer: Claude Opus 5.5.

## For PROGRESS

- Mac: no product change (U4b part I already names the first of `path`, `from`, `to` that leads out). Pinned by three `undo.stackCases` rows read through a new key `refusalNamed`, a sentence in `undo.rule.stagedThenSwapped`, and five `UndoDoorGuardTests` (Undo and Redo; only the new place, only the old place for Redo, both). The Python model (`scripts/make_undo_traces.py` `plan`) names the same place now; it named `path or from` before. `undo-traces.json` unchanged (`make_undo_traces.py` says current).
- Windows: three stack rows held under `Reason899W8U4b` (sentence extended to name the calls and key).

## For documentation 12

W8 (Rename folder through the door) owes:

- `UndoCheck.Plan`, the leaves-the-folder block (about line 375): put in `inTheWay` the FIRST of `op.PathsNamed` (`Path`, then `From`, then `To`) for which `UndoPlaces.StaysInside(whole.Root, place)` is false, not `op.PlaceName`. Today a move whose `To` alone leads out is named by its `From`, the side that is as the step left it.
- `UndoStackContractTests`: the key `refusalNamed` (the `ChangedSince` refusal's first path after the last `undo` or `redo`; compare as a string) and three calls: `moveThePageIntoAFolder` (courses/TST1O/b.md, made holding `page\n` when neither place holds it, moved to courses/TST1O/new/b.md, one `move`), `moveThePageBetweenFolders` (courses/TST1O/old/c.md to courses/TST1O/new/c.md, the same way), `linkItsNewFolderOutside` (courses/TST1O/new removed and replaced by a junction to the same `Outside` folder `linkItsOldFolderOutside` uses). Then take the three `U4b2-2:` rows out of the ledger.

Why the held rows fail on Windows today: all three carry `refusalNamed`, which `KeysChecked` does not hold, so each fails at "a key this replay does not check: refusalNamed" before any call. Two of them ("only the move's old place", "both") would pass on Windows as soon as the replay reads the key, because `op.PlaceName` is `From` and `From` leads out in both; only "only the move's new place" needs the UndoCheck change. They are held, not left, because the key itself is unknown there (the brief's "not held if they would pass" does not apply: they would not pass).

## Must-fail lines

See `windows-app/notes/899-u4b2-2-mustfail.log`. RED 3 of 3:

1. Windows' rule (`op.path ?? op.from`) in the Mac loop: `testUndoRefusedBecauseOnlyTheNewPlaceLeadsOutNamesTheNewPlace` (line 188), `testRedoRefusedBecauseOnlyTheNewPlaceLeadsOutNamesTheNewPlace` (237), `testStackCases` the "only the new place" row only.
2. The last place instead of the first: `testUndoRefusedBecauseBothPlacesLeadOutNamesTheOldPlace` (203), `testRedoRefusedBecauseBothPlacesLeadOutNamesTheOldPlace` (254), `testStackCases` the "both" row only.
3. Python model naming `path or from`: `test_stack_cases`, the "only the new place" row.

Tests "failed first": none could fail on base, because the product already behaved; the must-fails above are the proof each test and row is real.

## Runs

- Merge of `origin/dev`: the branch starts at `origin/dev` a03fecefd, and `origin/dev` was still a03fecefd at hand-back (checked with `git merge-base --is-ancestor`), so no merge commit was needed either time.
- `run-green1`: UndoDoorGuardTests (14), UndoJournalContractTests (19), UndoFilesContractTests (30), UndoRenameFolderStepTests (3), SharedRulesContractTests (67): 133 tests, 0 failures. TEST SUCCEEDED.
- `python3 scripts/test_make_undo_traces.py`: 31 tests OK. `python3 scripts/make_undo_traces.py`: undo-traces.json is current.
- `run-mustfail1`, `run-mustfail2`: as above.

## Left for the next piece

- Stack rows are Undo only; the Redo directions are pinned by the Swift tests alone. A Redo row each would need no new call (undo, link, redo) if W8 or a later piece wants them in the contract.

## For the director

- `contracts/` touched: both gates.
- `documentation/09-mac-app.md`: my "U4b2: leaving-place-named" paragraph is at the end of the Undo section, the same place piece 1 appends "U4b2: linked-page-written-through". Expect a trivial conflict there: keep both, piece 1's first. `shared-rules.json` (stagedThenSwapped at line 48168, How at stackCasesHow, rows after the U2 link row) and `NamedGapLedger.cs` (the `Reason899W8U4b` sentence at line 469 and its stack hold at about 626) are away from piece 1's lines.
- A `checkCases` row could not carry this: `checkCasesHow` lets a place itself be a link (never followed), not a folder on its path replaced after the step, so the rows are `stackCases`, using the existing `moveThePageAside` and `linkItsOldFolderOutside` and three new calls.

## Self-check

1. Broke each fix and watched its test fail: three sabotages (Mac loop twice, Python model once), each red at the lines above, restored, `git status` clean.
2. No timed waits: none added; the tests wait on no event.
3. Sentences on the failure paths: the refusal names the place now reached through the link; no wording changed (out of scope). The rule sentence and the How text say the same as the code.
4. `dev` merged before proving: the branch is on `origin/dev` a03fecefd, unchanged at hand-back.
5. No number tuned by trial: none.
6. House style and contracts: rows run from the JSON; nothing outside the brief's scope (the How, the rule sentence, the rows, the replays, the Python model, the ledger, doc 09, these notes).
7. `grep` for DispatchQueue, `.map {`, `.filter {`, `.reduce(`, `$0` over added Swift lines: empty. New helpers sit under the existing `// MARK: - Functions` sections.
8. Riding lows: L1 (parity pinned: rows plus the ledger hold) and L2 (only-`to` and both, both directions: five tests) fixed; tests could not fail first on base (behaviour already right), proven by must-fail instead.
9. The rename record is untouched and `undoJournalIsLive` is still off (no product code changed).
10. Every new contract row runs in the Mac's replay (`testStackCases`) and in the Python model, and is held for Windows by exact name (checked by script against the JSON).
