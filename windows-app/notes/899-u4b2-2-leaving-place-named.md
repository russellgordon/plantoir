# #899 U4b2-2: a leaves-the-folder refusal names the place that leads out

Branch `issue/899-u4b2-2-leaving-place-named`, from `origin/dev` a03fecefd. Writer: Claude Opus 5.5.

## Review 1 round (2026-11-25)

- MEDIUM 1, fixed in code (director's decision): the check just before each change (staging and swap, `UndoSwap.swap`) named `target.relativePath`, so a link made between the plan and the change that takes only `to` out (Undo) or only `from` out (Redo) named the other side. Both now call `UndoSwap.placeLeadingOut`, which for a move calls `UndoCheck.placeLeavingTheFolder(op.pathsNamed, root:)`, the same function the plan now uses; for any other change it names the place changed, as before. Four tests (Undo and Redo, at `afterTheCheck` and at `beforeSwap(0)`), each failed first.
- LOW 1: three Redo stack rows (only the new place, only the old place, both).
- LOW 2: the "only the old place" Undo row is gone; its `refusalNamed` is on the U2 row, which is now held on Windows (fails at the key there).
- Held rows: 6 (two Undo, three Redo, the U2 row). Superseded by review 2, below.

## Review 2 round (2026-11-25)

- MEDIUM 1 (the director's instruction to merge was withdrawn): the U2 link row is back exactly as at a03fecefd (no `refusalNamed`, not held, checked by script against `git show a03fecefd`), so the PC still proves that nothing is moved out through a link. The separate Undo row "U4b2-2: only the move's old place leads out ..." is back, carrying `refusalNamed`, held.
- Held rows: 6, all `U4b2-2`: three Undo (only the new place, only the old place, both) and three Redo (the same three).
- LOW 1 and LOW 2: "For documentation 12" corrected (folded since into documentation 12, "What W8 owes from U4b2-2").

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
- Review 2 round: `run-r2-green` (the 5 classes, 137 tests, 0 failures), `run-r2-mustfail-oldrow` (the last place named: the restored old-place Undo row red, with the other "old place" rows and tests), `test_make_undo_traces.py` 31 OK.
- Review 1 round: `run-r1-first` (4 new tests red on ddb585569), `run-r1-green` (the 5 classes, 137 tests, 0 failures), `run-r1-mustfail-a` to `-d`, the Python must-fail; `test_make_undo_traces.py` 31 OK; `origin/dev` still a03fecefd.

## Left for the next piece

- Nothing. (The Redo rows asked for in review 1 are in.) The window between plan and change has no contract row: a stack call cannot act between the check and the swap except through `undoWhileAStepBegins`-style hooks, which W8 would have to learn; the Swift tests pin it.

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
