# #899 U4b2-5: part-way-line-true

Branch `issue/899-u4b2-5-part-way-line-true`, from `origin/dev` bf14823ac. `origin/dev` merged before proving and before hand-back: both times already up to date at bf14823ac (no merge commit made).

## For PROGRESS

- Mac: a Rename folder that stops part way (a refused step that could not all be put back) now names the folders at the new name as read from the disk, whether this run moved them or an earlier, interrupted run did. A run finishing an interrupted rename used to say "did not rename the folder Concepts to Ideas" while every folder was at "Ideas". `foldersLeftAtTheirNewName(planned.moves, …)` is replaced by one function, `SpecialFolderRenamer.foldersAtTheirNewName(renaming:to:scope:courseDirectory:sectionNumbers:)`. No sentence's wording changed.
- `contracts/shared-rules.json` → `activityTrail.mustRecord` → `folder renamed` → `carries` reworded (no new key, no new event, count unchanged); `contracts/README.md` two passages.

## For documentation 12

- Windows' part-way line, once W8 brings the one-step rename: in a run FINISHING an interrupted rename (the earlier run moved the folders, so this run's plan has no moves), the folders named as "still called <new>" are found from the disk: every place the folder lives at its NEW name (shared: `<course>/<new>`; per section: `<course>/section<N>/<new>` for each section number) that exists by a no-follow presence check (a link counts, nothing read). For a rename that only changes capitalisation, a place counts only when its parent directory LISTS the new spelling exactly (the old spelling "exists" there on a case-insensitive volume). Nonempty: say `undo.wording.renameFolderRenamedOnlyInPart` and write the "renamed … only in part" trail line naming those paths inside the course; empty: `renameFolderStoppedPartWay` and the "did not rename" line. The same reading is used in a start run; never choose by which run moved what.
- Until W8, Windows' one part-way `folder renamed` line is "renamed the folder … but could not write it to this course's settings" (`CourseSettingsView.xaml.cs` about line 497), and `carries` now says so.
- No ledger row: no case was added, and no Windows test reads this `carries` (grep of `windows-app/Plantoir.Tests` for "folder renamed": only `SpecialFolderRenamerTests.cs:355`, which checks the event key, not `carries`).

## Must-fail lines

- Sabotage 1 (folders taken from `planned.moves` again in a finish run): `UndoRenameFolderStepTests.testAFinishStoppedPartWaySaysTheFolderIsAtItsNewName` fails at :1083 (sentence), :1088 (trail line), :1089 (no "did not rename" line). RED 1 of 1. Log: `windows-app/notes/899-u4b2-5-mustfail.log`.
- The new test also failed first, before the fix, at the same three asserts (run-red).

## Runs

- run-red: the new test alone, before the fix: failed as above.
- run-green: `UndoRenameFolderStepTests`, `SpecialFolderRenamerTests`, `ActivityTrailWiringTests`, `UndoSweepFindingsTests`, `SharedRulesContractTests`, plus the classes that read the two changed Swift files as source text (`UndoWriterScanTests`, `SaveEnablesTests`, `TwoWindowSettingsTests`, `GradedFolderChoicesTests`, `AccessibilityNamesTests`, `SettingsSaveNoticeTests`): 233 tests, 0 failures, TEST SUCCEEDED.
- run-mustfail: as above.
- `python3 scripts/test_make_undo_traces.py`: 31 tests OK (no undo row touched; traces not stale).

## Left for the next piece

- Piece 4 review 2 low: the replay does not check that the two removed blobs sit in different prefix folders. It is in `UndoContractReplay*.swift`, which this piece does not touch.
- Piece 4 review 2 low: the documentation 12 note does not say the Mac treats the two Unicode forms of a name as the same. Documentation 12 is not in this piece's files (writers do not edit it; the director folds notes).
- Edge, not changed: in a START run, a section with no folder at the old name but one already at the new name (on disk, not in the settings) would now count as "still called" after a part-way stop. The plan refuses a taken destination only where the old folder exists, and the sheet refuses a new name the settings list, so this needs a folder on disk the settings never listed. The sentence is then still true of the disk.
- Not done: the wording for "no folder of the course at either name" in a finish run. A finish run is offered only when the new name is on disk (`looksLikeAnInterruptedRename`), so that branch takes the existing `stoppedPartWay` sentence.

## For the director

- `contracts/` touched (`carries` prose and README): both gates. No contract key added, no ledger row.
- HIG "Writing" not re-read: no new wording; the existing `renameFolderRenamedOnlyInPart` sentence is used unchanged, as the brief prefers.
- Piece 4's lines (`undo kept what it replaced` carries, `undo.stackCases`, the ledger) untouched; my `carries` edit is the `folder renamed` entry at line 372 only.

## Self-check

1. Broke the fix and watched the test fail: yes, sabotage 1, three asserts named; also red before the fix.
2. No timed waits: none added; the test waits on nothing but the awaited rename.
3. Sentences on the failure paths true: the finish run's part-way sentence and line now name "Ideas", which is on disk (asserted); start-run part-way tests unchanged and green.
4. `dev` merged before proving: up to date at bf14823ac, both times.
5. No number tuned by trial: kill-point indices follow the finish step's op order (page relink 0, settings 1).
6. House style and contracts: no retyped contract text; scope held to `mac-app/`, `contracts/`, documentation 09, notes.
7. grep for `DispatchQueue`, `.map {`, `.filter {`, `.reduce(`, `$0` over added lines: empty; the new test sits under its own `// MARK: -`.
8. Riding lows L1, L2, L3 of part nine fixed (L1 with a test that failed first; L2 and L3 are contract prose, read by no test). Piece 4's two lows written above with the reason.
9. Rename record kept (untouched); `undoJournalIsLive` still `false`.
10. No new or changed contract row with a key; the `carries` prose has no reader on either platform beyond the event-name pin.
