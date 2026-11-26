# #899 U4b2-5: part-way-line-true

Branch `issue/899-u4b2-5-part-way-line-true`, from `origin/dev` bf14823ac. `origin/dev` merged before proving and before hand-back: both times already up to date at bf14823ac (no merge commit made).

## Review 1 round (M1, L1 to L4), 2026-11-26

- M1: a part-way line names a folder only if it belongs to this rename (a destination of this run's planned moves, or a place the record of the rename it finishes names) AND the disk shows it at the new name. One function, `SpecialFolderRenamer.foldersAtTheirNewName(…, planned:, earlierRecord:)`, returning `LeftAtTheNewName` (places, unreadable). The record gains `moved` (one string, a place per line, inside the course, new spelling), written by `RenameRecordClaim.renameIsStarting(moving:)` with this run's moves plus the earlier record's places when it is the same rename. A record without `moved` (Windows', older) falls back to: a new-name place whose old name is absent beside it.
- L1: tests added for the review's scenario (per-section start run, hand-made `section2/Assessments`, every folder back: says `stoppedPartWay`, never names it), a per-section finish run (both sections, in order), a start run after a killed one (both runs' sections, and the record keeps both), a capitalisation-only finish (function test).
- L2: only ENOENT/ENOTDIR read as absent; any other `lstat` refusal or a failed listing is `unreadable`, added to the trail line as "; could not tell whether these are at the new name: <place> (<what the system said>)"; the sheet's sentence is chosen by what could be read (no new sentence). Pinned by a function test (a section folder with no permissions).
- L3: a link at the new name counts only where this run moved a link there (`FolderRenamePlan.Move.isALink`, read by `lstat` at planning). An earlier run's recorded place counts only as a real folder.
- L4: confirmed in `windows-app/Plantoir.Core/Models/SpecialFolderRenamer.cs:270-277` and `Plantoir/Views/CourseSettingsView.xaml.cs:479-481` that Windows' "Plantoir renamed m of n copies" stop returns its message with no trail line; `carries` and README now say so. Prose only, no held row.
- `SpecialFolderRenamer.somethingIsThere` removed (its one caller is gone; `presence(at:spelledExactly:)` is the one reading).
- Merges: origin/dev da7474047 merged as 89cdebe53 (Windows notes and tests, `contracts/class-planning.json`, documentation 12; nothing under `mac-app/`), then the 11 classes re-run green: 239 tests, 0 failures (run-r1-merged).

## For PROGRESS

- Mac: a Rename folder that stops part way (a refused step that could not all be put back) now names the folders at the new name as read from the disk, whether this run moved them or an earlier, interrupted run did. A run finishing an interrupted rename used to say "did not rename the folder Concepts to Ideas" while every folder was at "Ideas". `foldersLeftAtTheirNewName(planned.moves, …)` is replaced by one function, `SpecialFolderRenamer.foldersAtTheirNewName(renaming:to:scope:courseDirectory:sectionNumbers:planned:earlierRecord:)` (U4b2-6 then chose the sentence and line through `partWayEnding`). No sentence's wording changed.
- `contracts/shared-rules.json` → `activityTrail.mustRecord` → `folder renamed` → `carries` reworded (no new key, no new event, count unchanged); `contracts/README.md` two passages.

## For documentation 12

- (Review 1; superseded by U4b2-6, see `899-u4b2-6-rename-sentences-in-contract.md`) The rename record carries `moved`, now an ARRAY of strings, and `mayHaveMoved`, with its whole format in `contracts/file-formats.json` → `folderRenameRecord`. A part-way line names a place only when it is in `moved` or a move of this run AND the disk shows a folder there by a no-follow check (a link only when this run moved a link). A record without `moved` names no place; its possible places are told as ones it cannot tell are this rename's. A no-follow check that fails for any reason but "no such file", or a listing that fails, is told on the trail as "could not tell whether these are at the new name: <place> (<reason>)", never read as absent.

- (Superseded by review 1 and U4b2-6; kept short so W8 does not build the earlier reading.) Windows' part-way ending, once W8 brings the one-step rename, follows the U4b2-6 notes: belongs (a move of this run, or in the earlier record's `moved`) AND shows (a folder by a no-follow check; a link only where this run moved a link; for a capitalisation-only rename only when the parent LISTS the new spelling). It never counts a place by the disk alone.
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
- (Was an accepted edge in the first round; fixed as review 1's M1.)
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
