# U4b2-4: kept-line-by-path (#899)

Branch `issue/899-u4b2-4-kept-line-by-path`, from `origin/dev` bf14823ac. The part-two review of U4b, LOW 4.

## Must-fail lines

Review 1 round: S2 (LOW 1 off), S3 (line keyed by name), S4 (`UndoCheck` put-back pages by last part), S5 (`UndoCheck` kept files by bare name), each failing lines named in the log; RED 4 of 4. First round:
See `windows-app/notes/899-u4b2-4-mustfail.log`. Before the fix all three new tests failed (run-red). Sabotage: match pages by last path part on both sides in `UndoTrail.keptWhatItReplacedLine`: the three new tests fail (`UndoKeptCopiesTests.swift:376`, `:377`, `:401`, `:419`); restored, `git diff` clean. RED 1 of 1.

## Runs

Review 1 round (5637f2933, `origin/dev` still bf14823ac, already up to date; no merge commit): `UndoKeptCopiesTests`, `UndoJournalContractTests`, `UndoSweepFindingsTests`, `ActivityTrailWiringTests`, `UndoWriterScanTests`, `UndoShadowPublishTests`: 65 tests, 0 failures (run-green4). `python3 scripts/test_make_undo_traces.py`: 31 tests OK, traces not stale. Sabotages S2 to S5 in the must-fail log, RED 4 of 4. Red first for LOW 1: S2 is the code before the LOW 1 fix; the two LOW 1 tests fail there. The LOW 2 and LOW 3 tests pin behaviour that was already true after the first round, so they show red only under S3 to S5.

First round:

- run-red (bf14823ac plus the new tests): `UndoKeptCopiesTests` 11 tests, 8 failures, all in the three new tests.
- run-green (8f157262e): `UndoKeptCopiesTests`, `UndoJournalContractTests`, `UndoSweepFindingsTests`, `ActivityTrailWiringTests`, `UndoWriterScanTests` (reads `UndoCheck.swift`, `JournaledWrite.swift`, `UndoAppSeams.swift` as source text), `UndoShadowPublishTests` (calls the line with bare names): 61 tests, 0 failures.
- run-mustfail: as above.
- `origin/dev` merged before proving and before hand-back: still bf14823ac both times, so no merge commit (already up to date).

## Left for the next piece

Nothing.

## For the director

- Review 1's clause scope said the clause must not claim that pages sharing a name with any page of the step are path-named; the director also asked for LOW 1's fix, which makes that true. So the clause says "another page of the same step", which is what the code now does. Everything else is as the review scoped it.

- No interface change: a trail line only, so no HIG section applies (none read).

## Self-check

1. Broke the fix and watched the tests fail: yes, the run before the fix and the sabotage above, failing lines named.
2. No timed waits: none added.
3. Failure-path sentences: the line is written only once the swap has gone in; it names what is on the disk (the kept files listed from `keptOriginalFiles` after the tidy), now by path, so two kept files with the same hidden name in two folders are both named (before, the second was dropped).
4. `dev` merged in before proving: bf14823ac, already up to date.
5. No number tuned by trial: none.
6. House style and contracts: no contract cases retyped; nothing outside the brief changed.
7. House style grep over the added Swift lines: empty; the new functions sit inside `UndoTrail`'s existing sections, the new tests under a `// MARK: -` heading.
8. Riding low L4 (part-two review): fixed, with tests that failed first. Review 1's LOW 1 to 3: fixed and tested (red runs above); LOW 4: documentation 12 items 5 and 6.
9. The rename record is untouched; `undoJournalIsLive` untouched (off).
10. The `carries` clause and the new stack case are in the Mac's replay (`UndoJournalContractTests.testStackCases`, which S3 to S5 turn red) and in the Python model; the stack case is held on Windows by its exact name, checked by script byte for byte against the JSON.
