# U4b2-11: rename-step-recorded (#899)

Branch `issue/899-u4b2-11-rename-step-recorded`, from `origin/issue/899-u4b2-10-carried-subfolder-left-out` 78671eafc (holds `dev` 811c956ce and pieces 9 and 10). `origin/dev` merged before proving and again before hand-back: both "Already up to date" (`dev` still 811c956ce), so no merge commit.

## For PROGRESS

- Mac: Rename folder's step is recorded from its real code (`CourseSettingsView.renameFolder`, present on this base and on piece 8's branch alike, so no rebase is needed) into `contracts/undo-action-steps.json`: `renameFolder` (per-course `Concepts` to `Ideas`) and `renameFolderPerSection` (`Tasks` to `Assessments`, one move per section). New recorded key `folderMoves`: `from`, `to`, `listingSha`, and the listing before the step (`folders`, byte order; `files`, text by path inside). A carried page is in `files` at the NEW place, its `before` the text at the old one.
- `make_undo_traces.py`: `STEPS_WITHOUT_TRACES_YET` leaves the two steps out of `actionTraces` by name (piece 12 removes it); `actionNote` says what `folderMoves` means. `undo-traces.json` changed only in that note.
- Riding low (review 1 of U4b2-6, L4): a regeneration keeps each committed `recorded`/`answeredAt` moment on a line otherwise the same (`UndoActionStepsTests.keepingTheCommittedMoments`), so this regeneration changed only the note and the two new steps (the class-dates step still reads 2026-11-20).

## For documentation 12

- **The two new steps are held** in `NamedGapLedger.cs` under `Reason899W8U4b` (area `UndoActionStepsOnWindows`), names checked by script byte for byte. Each still fails on Windows: neither is in `WindowsActionsOnTheMacFixture.Converted` or `HeldButRunnable`, so `TheWindowsActionLeavesTheRecordedStep` reaches `MakeAndMatch`, which throws "no Windows action is converted for it yet", the text `HeldCaseStillStopsAtItsGap` is given (read in `windows-app/Plantoir.Tests/UndoActionStepsOnWindowsTests.cs` about lines 535 to 590). No Windows test enumerates a step's keys block-wide (`UndoActionTraceContractTests` checks `moves`, `members`, `trees` per trace, and no trace names the two steps), so the new key turns no unheld row red.
- **What W8 must do to convert them:** Windows' Rename folder (Course Settings) run on the recorded course (two sections, per-section `Tasks`, shared `Concepts`; pages as in each step's `files` befores and `folderMoves` listings; `course_config.json` as recorded) must leave ONE step under the key `renameFolder`, made by the sheet, whose ops are: one `move` per folder (each with the `listingSha` recorded, which is the SHA-256 of the listing text `folder <path>\n` / `file <sha> <path>\n` sorted by path bytes), then one edit per relinked page (each carried page named at the folder's NEW place), then one `editJSON` per changed member in the recorded order (`expandable`, `shared_folders`; or `expandable`, `hidden`, `per_section_folders`). The order among the pages is the Mac plan's walk order (the contract asks none); a Windows walk that finds them in another order makes the same pages and ops otherwise, so W8's match should compare the pages as a set inside the run of page edits, or the director rules the order.

## Must-fail lines

See `windows-app/notes/899-u4b2-11-mustfail.log`. Red first: three `UndoActionStepsTests` failures (contract not current, no folder move, the new date kept). M1 carried edits at the OLD place: RED (`UndoActionStepsCourseSettings.swift:141`, and :544 the committed file). M2 the contract's carried page at the old place: RED (:202, :213). M3 the old stamping: RED (:225). M4 Python's leave-out emptied: 4 RED. M5 a listing's text changed: RED (:191). 5 of 5.

## Runs

- `run-red1.log`, `run-red2.log`: red first (above). `run-red1.log` also showed the first form of my order assertion ("carried pages, then pages outside") red on the door's real order: in the per-course step the plan's walk finds `section1/index.md` before `Ideas/Arrays.md`. `opKinds.wholeOps` asks no order among a step's edits (only moves first, each carried edit after its move, named at `to`), so the assertion now pins the moves first, the pages as a set, then the `editJSON`s; the committed file pins the exact order. Not a product fault.
- `run-write.log`: the regeneration (`TEST_RUNNER_PLANTOIR_WRITE_UNDO_ACTION_STEPS=1`). `git diff contracts/undo-action-steps.json`: the note line and the two new steps only.
- `run-green1.log`: UndoActionStepsTests 19, UndoFilesContractTests 3, UndoRenameFolderStepTests 38: 60 tests, 0 failures. No other Mac test reads a changed file as source text.
- `python3 scripts/test_make_undo_traces.py`: 34 tests OK (one new); `make_undo_traces.py` run: 150 action traces, `undo-traces.json` changed in `actionNote` only.
- Logs in `/Users/russellgordon/plantoir/wt-899-u4b2-11/.dd/`.

## Left for the next piece

- Piece 12: the two steps' traces and their replay (remove `STEPS_WITHOUT_TRACES_YET`; the model must make a `move` carrying `listingSha` and the carried edits; `folderMoves`' listing is the content to lay at `from`). Mac's `replayActionTraces` must then read `folderMoves`. The page order inside a step is the walk's (above).
- Recording ran in shadow (as every other recorded step); the shadow step is closed `done` with the same ops as the live one in `UndoRenameFolderStepTests`.

## For the director

- `contracts/` changed (`undo-action-steps.json`: note and two steps; `undo-traces.json`: `actionNote` only): both gates, taken with piece 12. No Windows test enumerates step keys block-wide.
- No rebase needed on pieces 7 and 8: the recording calls `CourseSettingsView.renameFolder(_:to:scope:)`, which exists unchanged in signature on `origin/issue/899-u4b2-8-plan-read-off-the-pool` (there called by `renameFromTheSheet`).
- Ledger: 2 names under `Reason899W8U4b`; the reason's text now names the two steps and the key.
- HIG: nothing a teacher sees or hears changed; no section needed.

## Self-check

1. Broke each fix and watched its test fail: M1 to M5, 5 RED, lines in the log.
2. No timed waits: none added.
3. Every sentence on the failure paths is true: no product sentence changed; the note sentences and the ledger reason say what the recorder and the generator do, checked against the code; the Windows claims read in `UndoActionStepsOnWindowsTests.cs` and `UndoActionTraceContractTests.cs`.
4. `dev` merged before proving: 811c956ce, already up to date both times.
5. No number tuned by trial (the counts 27 and 3 are the steps and folder moves recorded).
6. House style and contracts: the recording written by the test, never by hand; read back by `testEveryRecordedFolderMoveHoldsTheListingItNames` and by Python; nothing outside the brief.
7. `grep -n "DispatchQueue\|\.map {\|\.filter {\|\.reduce(\|\$0"` over the added Swift lines: empty; no new type authored (a stored property added to `Recorded`, inside its MARK).
8. Riding low L4 fixed with a test red first; "the recorded renameFolder trace, first half" is this piece.
9. The rename record is still kept; `undoJournalIsLive` untouched (off); no product code changed.
10. Both new steps are in the Mac's check (`testEveryDailyActionIsOneStepThroughTheDoor` and the reader test) and held by exact name on Windows.
