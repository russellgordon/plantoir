# U4b2-4: kept-line-by-path (#899)

Branch `issue/899-u4b2-4-kept-line-by-path`, from `origin/dev` bf14823ac. The part-two review of U4b, LOW 4.

## For PROGRESS

- Mac: the trail line `undo kept what it replaced` decides "from what was kept beside it" of each page by its place in the working folder, never by its file name alone. Kept files are passed to the hook by path (page folder plus hidden name); `putBackFromAKeptOriginal` holds pages by path; the hook also takes every page the step changes (`pagesOfTheStep`). A named page whose file name any page of the step shares is named by its path inside the course, or by its path in the working folder when it is not under `courses/<course>/` or the step has no course. Eight tests in `UndoKeptCopiesTests`' U4b2-4 section (Undo, Redo, top of the working folder, no course, capitals).
- **`contracts/` changed (review 1, the director's decision): both gates.** `shared-rules.json`: one clause at the end of the `undo kept what it replaced` row's `carries` (its `line` example unchanged byte for byte); one new `undo.stackCases` row, "U4b2-4: two pages named index.md in two sections, …", with four new calls and the new key `keptWhatItReplacedSays`, described in `stackCasesHow`; `scripts/test_make_undo_traces.py` replays the calls in its model (the key is the Swift replay's alone: the model writes no words). Traces not stale. One row held for Windows in `NamedGapLedger.cs` under the new reason `Reason899W4cKeptLineByPath`.

## For documentation 12

What Windows does today (read in `windows-app/Plantoir.Core/Undo/UndoDoor.cs` `SayWhatItKept`, and `UndoRecovery.cs` `UndoTrail.KeptWhatItReplacedWords`): the line is not yet decided page by page at all. It says "put back … from what was kept beside it" of every named page, takes no list of pages put back from a kept original, and keeps each kept file by its bare file name (`Path.GetFileName(kept)`), skipping a second kept file with the same name in another folder. W4c owes, when it brings the line up to the Mac:

1. `SayWhatItKept` records each kept file as `<page's folder>/<hidden name>` (the folder of the op's relative path, `/`-separated; a page at the root gives the bare hidden name), and skips a kept file only when that whole path is already listed.
2. The pages put back from a kept original are listed by the op's relative path (the use's path, whole), never its last part.
3. The line works out each kept file's page as its folder plus the name between the hidden name's leading dot and its last `.plantoir-undo-`. A page is said to come "from what was kept beside it" only when that page path is in the list of 2.
4. A page is named on the line, quoted, by its file name; when any other page the step changes (every op's path, named on the line or not) has the same file name, by its path with the leading `courses/<course>/` taken off (“Section 1/index.md”), and when the page is not under `courses/<course>/` (the top of the working folder, another course's folder) or the step has no course, by its whole path in the working folder (“index.md”, “courses/ICS3U/Section 1/index.md”). The prefix is compared exactly (ordinal), and names that differ only in capitals (`Index.md`, `index.md`) are different names, each named by its file name. The same naming is used in the opening clause and in each "What … held a moment before / holds now is kept beside it as the hidden file “…”" sentence; the hidden file itself is always its bare name.
5. `KeptWhatItReplacedWords` must still accept a bare hidden name (a page at the top of the working folder), so `UndoTrailWordsContractTests.KeptWhatItReplacedSaysWhatTheContractSays`, which passes `.A.md.plantoir-undo-4-undo-orig` and no page list, keeps passing unchanged.
6. The trail line's list of files (`UndoTrailLine`'s last argument in `SayWhatItKept`, today `[.. keptOfWhatItHeld, .. keptOfWhatItHoldsNow]`) stays what it is for a reader of the trail: the kept files' bare names, as now. Build the path lists for the words separately, or take the bare name of each path when building it; do not let the payload turn into paths as a side effect of item 1.
7. The new stack case "U4b2-4: two pages named index.md in two sections, …" is held under `Reason899W4cKeptLineByPath`. It fails on Windows today, because `UndoStackContractTests`' key set has no `keptWhatItReplacedSays` and its replay knows none of the calls `wholeFileStepOnTwoPagesNamedIndex`, `firstIndexAfterContentGoneAndCannotBeStored`, `secondIndexBeforeContentGoneAndCannotBeStored` or `keepTheOriginalOfTheSecondIndex` (`stackCasesHow` says what each does). Even with those added, the line Windows writes would say "from what was kept beside it" of both pages and name each “index.md”. W4c lifts the hold once all of it is built.

Example (Mac test `testTheKeptLineKeysPagesByTheirPlaceInTheWorkingFolder`): kept `courses/ICS3U/Section 1/.index.md.plantoir-undo-4-undo-orig` (held), `courses/ICS3U/Section 2/.index.md.plantoir-undo-3-apply-orig` (holds now), put back from a kept original `courses/ICS3U/Section 2/index.md` gives `ICS3U/1 · Undo put back “Section 1/index.md”, and put back “Section 2/index.md” from what was kept beside it, but the list could not keep a copy of all it needs for this change, so what it could not keep stays beside the page, and the next Undo or Redo of this change uses it. What “Section 1/index.md” held a moment before is kept beside it as the hidden file “.index.md.plantoir-undo-4-undo-orig”. What “Section 2/index.md” holds now is kept beside it as the hidden file “.index.md.plantoir-undo-3-apply-orig”.`

One held row (item 7).

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
