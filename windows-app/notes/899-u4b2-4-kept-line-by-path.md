# U4b2-4: kept-line-by-path (#899)

Branch `issue/899-u4b2-4-kept-line-by-path`, from `origin/dev` bf14823ac. The part-two review of U4b, LOW 4.

## For PROGRESS

- Mac: the trail line `undo kept what it replaced` decides "from what was kept beside it" of each page by its place in the working folder, never by its file name alone. Kept files are passed to the hook by path (page folder plus hidden name); `putBackFromAKeptOriginal` holds pages by path. Two named pages that share a file name are each named by their path inside the course. Three new tests in `UndoKeptCopiesTests`. No `contracts/` change (the `carries` text says "decided page by page", never "by name"). Mac gate only.

## For documentation 12

What Windows does today (read in `windows-app/Plantoir.Core/Undo/UndoDoor.cs` `SayWhatItKept`, and `UndoRecovery.cs` `UndoTrail.KeptWhatItReplacedWords`): the line is not yet decided page by page at all. It says "put back … from what was kept beside it" of every named page, takes no list of pages put back from a kept original, and keeps each kept file by its bare file name (`Path.GetFileName(kept)`), skipping a second kept file with the same name in another folder. W4c owes, when it brings the line up to the Mac:

1. `SayWhatItKept` records each kept file as `<page's folder>/<hidden name>` (the folder of the op's relative path, `/`-separated; a page at the root gives the bare hidden name), and skips a kept file only when that whole path is already listed.
2. The pages put back from a kept original are listed by the op's relative path (the use's path, whole), never its last part.
3. The line works out each kept file's page as its folder plus the name between the hidden name's leading dot and its last `.plantoir-undo-`. A page is said to come "from what was kept beside it" only when that page path is in the list of 2.
4. A page is named on the line, quoted, by its file name; when another page named on the same line has the same file name, by its path with the leading `courses/<course>/` taken off (“Section 1/index.md”). The same naming is used in the opening clause and in each "What … held a moment before / holds now is kept beside it as the hidden file “…”" sentence; the hidden file itself is always its bare name.

Example (Mac test `testTheKeptLineKeysPagesByTheirPlaceInTheWorkingFolder`): kept `courses/ICS3U/Section 1/.index.md.plantoir-undo-4-undo-orig` (held), `courses/ICS3U/Section 2/.index.md.plantoir-undo-3-apply-orig` (holds now), put back from a kept original `courses/ICS3U/Section 2/index.md` gives `ICS3U/1 · Undo put back “Section 1/index.md”, and put back “Section 2/index.md” from what was kept beside it, but the list could not keep a copy of all it needs for this change, so what it could not keep stays beside the page, and the next Undo or Redo of this change uses it. What “Section 1/index.md” held a moment before is kept beside it as the hidden file “.index.md.plantoir-undo-4-undo-orig”. What “Section 2/index.md” holds now is kept beside it as the hidden file “.index.md.plantoir-undo-3-apply-orig”.`

No ledger row: no contract row changed or added.

## Must-fail lines

See `windows-app/notes/899-u4b2-4-mustfail.log`. Before the fix all three new tests failed (run-red). Sabotage: match pages by last path part on both sides in `UndoTrail.keptWhatItReplacedLine`: the three new tests fail (`UndoKeptCopiesTests.swift:376`, `:377`, `:401`, `:419`); restored, `git diff` clean. RED 1 of 1.

## Runs

- run-red (bf14823ac plus the new tests): `UndoKeptCopiesTests` 11 tests, 8 failures, all in the three new tests.
- run-green (8f157262e): `UndoKeptCopiesTests`, `UndoJournalContractTests`, `UndoSweepFindingsTests`, `ActivityTrailWiringTests`, `UndoWriterScanTests` (reads `UndoCheck.swift`, `JournaledWrite.swift`, `UndoAppSeams.swift` as source text), `UndoShadowPublishTests` (calls the line with bare names): 61 tests, 0 failures.
- run-mustfail: as above.
- `origin/dev` merged before proving and before hand-back: still bf14823ac both times, so no merge commit (already up to date).

## Left for the next piece

Nothing.

## For the director

- The path naming when two named pages share a file name is a variant of a sentence a teacher reads that lives only in Swift and here; the brief allowed it without a `contracts/` clause ("say so in the notes"). If you want it in `carries`, it is one clause ("a page whose file name another named page shares is named by its path inside the course") and brings both gates.
- No interface change: a trail line only, so no HIG section applies (none read).

## Self-check

1. Broke the fix and watched the tests fail: yes, the run before the fix and the sabotage above, failing lines named.
2. No timed waits: none added.
3. Failure-path sentences: the line is written only once the swap has gone in; it names what is on the disk (the kept files listed from `keptOriginalFiles` after the tidy), now by path, so two kept files with the same hidden name in two folders are both named (before, the second was dropped).
4. `dev` merged in before proving: bf14823ac, already up to date.
5. No number tuned by trial: none.
6. House style and contracts: no contract cases retyped; nothing outside the brief changed.
7. House style grep over the added Swift lines: empty; the new functions sit inside `UndoTrail`'s existing sections, the new tests under a `// MARK: -` heading.
8. Riding low L4 (part-two review): fixed, with tests that failed first.
9. The rename record is untouched; `undoJournalIsLive` untouched (off).
10. No contract row new or changed.
