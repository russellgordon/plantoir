# U4b2-11: rename-step-recorded (#899)

Branch `issue/899-u4b2-11-rename-step-recorded`, from `origin/issue/899-u4b2-10-carried-subfolder-left-out` 78671eafc (holds `dev` 811c956ce and pieces 9 and 10). `origin/dev` merged before proving and again before hand-back: both "Already up to date" (`dev` still 811c956ce), so no merge commit. (Merged on 2026-11-26 in `night25/integration-7`, 69b247fd5, with U4b2-11 to U4b2-15. "For PROGRESS" and "For documentation 12" are folded into `windows-app/PROGRESS.md` and documentation 12.)

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

## Review 1 (1 MEDIUM, 2 LOW), all fixed in this branch

- **MEDIUM 1 (director: sort in the product).** `SpecialFolderRenamer.plan` returns its pages through `inPathOrder`, sorted by `ClassPages.isInPathOrder` (new named function: the lowercased-path comparison `ClassPages.pagesOfSection`, `ClassPages.markdownPages` and `JournaledStep.markdownFiles` each wrote inline, now all call it), each page's place read canonical once (`UndoFolderPlaces.canonicalPath`): the first form compared the raw URLs and still put `section1/index.md` first, because a carried page's place is spelled `/var/...` and the walk's `/private/var/...`. The steps file's note states the order. Re-recorded: `renameFolder`'s two pages swap (Ideas/Arrays.md first); `renameFolderPerSection` unchanged; the note line. Red first: `run-r1-red.log` (the exact-order assertion, `UndoActionStepsCourseSettings.swift:143`, and the new `UndoRenameFolderStepTests.testARenamePlansItsPagesInPathOrderNotTheDisksOrder`, which first checks the walk finds `index.md` before `Arrays.md` on this course). Must-fail: the plan's pages left in walk order: RED at :143, :544 and `UndoRenameFolderStepTests.swift:279` (`run-r1-mf.log`). Pieces 9 and 10's move check: each page edit is judged and changed on its own, against its own file; `UndoOpKindsTests` 38, `UndoJournalContractTests` 19 and `UndoRenameFolderStepTests` 39 green after the sort.
- **LOW 1.** The Python test pins `STEPS_WITHOUT_TRACES_YET` to exactly the two names and requires `folderMoves` if and only if a step is left out. Must-fail: `addFolder` added to the tuple: RED (`run-r1-mf-python.log`).
- **LOW 2.** `assertTheRenameSteps` asserts the pages' exact order again (path order).
- Runs: `run-r1-write.log` (re-record), `run-r1-green.log`: UndoActionStepsTests, UndoRenameFolderStepTests, UndoFilesContractTests, UndoWriterScanTests (reads the three changed product files), SpecialFolderRenamerTests, UndoJournalContractTests, UndoOpKindsTests: 175 tests, 0 failures. Python 34 OK; traces current (`undo-traces.json` unchanged by this round).
