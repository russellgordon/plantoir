# #1055 M2: Rename folder refuses a per-section or shared folder that is a link, before anything changes (Mac)

Brief: `vm-tools/briefs/2026-11-27-1055-M2-rename-folder-refuses-a-linked-folder.md`. Branch `issue/1055-M2-rename-folder-refuses-a-linked-folder`, from M1's pushed head 839bbbce3 (stacked on M1). Touches `contracts/`: both gates. `origin/dev` (99499d6b7) and M1's head (839bbbce3) merged before proving and again before hand-back: both already up to date, so no merge commit.

## For PROGRESS

Rename folder no longer moves a per-section or shared folder that is itself a symbolic link (U4b2-15 removed). The plan refuses it before anything is written, as U4b did: `JournaledStepError.refused(.cannotTellNow(path:), fileName: <the folder's name>)`, read by the teacher as the door's existing sentence ("“Tasks” was not renamed, and nothing was changed: The file “Tasks” couldn’t be saved."). No new wording.

## What was removed

- `SpecialFolderRenamer.swift`: U4b2-15's product hunks (`75122d0d9`), reversed with `git apply -R` of that commit's own diff (it applied cleanly at an offset): `Move.sha` back to `listingSha` with its comment, `isALink`'s comment, the plan's link branch back to `guard let listingSha = UndoTreeReading.read(at: location).listingSha else { … }`, `apply` back to `step.moveFolder` alone, the record's places back to `case .folder, .unreadable`, `foldersAtTheirNewName` back to `case .folder:` and the `.link` branch with no `else`, and the doc-comment additions.
- Tests, `UndoRenameFolderStepTests`: `testAPerSectionFolderThatIsALinkIsRenamedByMovingTheLink`, `testWithTheSwitchOffAPerSectionFolderThatIsALinkIsRenamedAsBeforeU4b`, `testALinkedSectionsRenameKilledBeforeAnyOfItsSwapsIsWholeAfterRecovery`, `testALinkToAnotherSectionsFolderOfTheSameRenameIsMovedAsALink`, `testASharedFolderThatIsALinkOutOfTheWorkingFolderIsRenamedAndWhatItLeadsToIsUntouched`, and `killARename`'s `linked:` parameter and branches. `linkSectionTwosTasks` and `linkTarget` stay (the new tests use them).
- Tests, `SpecialFolderRenamerTests`: 75122d0d9's hunks reversed (`git apply -R`): `testARecordWithoutItsPlacesTellsALinkAtTheNewNameAsMayHaveMoved` removed, the two `sha:` arguments back to `listingSha:`, `testALinkAtTheNewNameIsNotTheRenamedFolderUnlessALinkWasMoved` back to its `75122d0d9^` form.
- `testADanglingLinkAtASectionsPlaceIsSkippedAsBeforeU4b` KEPT: it passes unchanged after the revert.
- `undo.stackCases`: the 2 rows "U4b2-15, Rename folder of a per-section folder that is itself a link…" (checked by script: 135 to 133, 2 removed, every other row identical by JSON).
- `undo.stackCasesHow`: the U4b2-15 sentence (db41d6729's insertion, removed exactly). Key `linkedFolder` stays.
- `activityTrail` → `folderRenamed.carries`: "a link only where this run moved a link there" back to "a link only where a link was moved", and the clause ", and so too any link at a place at the new name … (U4b2-15), and the record does not say which places were links" removed (7193a22e7's and db41d6729's words only; later edits kept).
- `file-formats.json`: `mayHaveMoved`'s `why` back byte for byte to its 7193a22e7^ form; `opKinds.move`'s parenthetical back to "(U4b2-14):".
- Mac replay: the `renameAPerSectionFolderThatIsALink` case and its name in `UndoContractReplayKinds.swift`. `JournaledStep.recordableFolderMoves` stays (product code calls it).
- Python model: the call dropped from the `if call in (…)` (back to `if call == "moveALinkToAFolder":` with U4b2-14's comment) and from the known-calls list. 46 OK; `make_undo_traces.py` rewrote `undo-traces.json` with no change.
- Kept for M3 to M6 (U4b2-15 added them, U4b2-14's door rows still reach them; M6 removes them): `JournaledStep.moveLink`, `folderMoveOp`, `UndoTreeReading.linkSha`.
- Notes file `899-u4b2-15-a-linked-section-folder-is-renamed.md` kept with the top line "Removed by #1055 (2026-11-27): …".

## What was put back

U4b's refusal from `75122d0d9^`: a folder whose listing cannot be read (a link has none) is refused `cannotTellNow` before the rename record and before any step. `git diff 75122d0d9^ HEAD -- …/SpecialFolderRenamer.swift` now holds only hunks of other commits: U4b2-11/12's (`86adac4bd` the planning thread, `e04fdff09` path order, `853c5e7be`), #909's (`e64df19c0`), the settings sweep (`39c32d392`), fix round one (`9fbda957d`) and mac-1 (`1d442f6d8`); none of its +/- lines name U4b2-15, `moveLink`, `linkSha` or `cannotTellWhose.append`.

## Tests (red first)

Commits 9e5b96f12 and the next one (the plain rename's ops recorded from the base), before any product change.

1. `testAPerSectionFolderThatIsALinkIsRefusedBeforeAnythingChanges` (live and shadow): RED on the base (`run-red1.log`: plan not refused, sentence nil, link moved to `section2/Activities`, settings changed, 1 step), green after.
2. `testASharedFolderThatIsALinkOutOfTheWorkingFolderIsRefusedAndWhatItLeadsToIsUntouched`: RED on the base (same faults), green after.
3. `testAPlainPerSectionRenameStillPlansTheSameMoves`: the exact plan lines and op lines (both listing SHA-256s included) recorded from a run on the base (`run-red2.log`); green on the base (`run-base3.log`) and after.

## Runs

Logs in `/Users/russellgordon/plantoir/wt-1055-M2/.dd/`.

- `run-red1.log`, `run-red2.log`, `run-base3.log`: as above.
- `run-own.log`: UndoRenameFolderStepTests, SpecialFolderRenamerTests, RestoreDuringAFolderRenameTests, UndoStoppedStepTests, UndoActionStepsTests, FolderPathRewriterTests, UndoOpKindsTests, UndoSweepFindingsTests, UndoJournalContractTests, UndoFilesContractTests, SharedRulesContractTests, FileFormatsContractTests, UndoWriterScanTests: 339 tests, 0 failures.
- `run-build.log`: plain Debug build, BUILD SUCCEEDED.
- `python3 scripts/test_make_undo_traces.py`: 46 OK; traces current.
- Greps: `moveLink\|linkSha\|\.sha\b` in SpecialFolderRenamer.swift empty; `renameAPerSectionFolderThatIsALink` in contracts, mac-app, scripts empty; `U4b2-15` in contracts empty; `move of a link\|linkedFolder` in shared-rules.json 7 lines (stay).

## Windows (edited by reading; not compiled)

No Windows file edited. Windows RUNS the two removed rows (`UndoStackContractTests.LinkCases`, `case "renameAPerSectionFolderThatIsALink"` at about 663); with the rows gone the case is never reached, `TheContractHoldsTheStackCases` holds (133 rows, floor 46; `Cases() + LinkCases()` still the whole array), and `NamedGapLedger.cs` names neither row nor `Reason899W8U4b2LinkedFolder` (grep: none). The suite stays at its six known failures. No Windows product code must change in this merge window.

## For documentation 12

- Windows' renamer still moves a linked folder as the link (`step.MoveLink`, `Plantoir.Core/Models/SpecialFolderRenamer.cs` about 444) until #1055 W4, which makes it refuse as the Mac now does.
- The replay case `renameAPerSectionFolderThatIsALink` in `UndoStackContractTests.cs` (about 663) and its name in `LaysASymbolicLink` (about 61) are dead once these rows go; they go with W4.

## Self-check (COMMON)

1. Broke each fix and watched its test fail: tests 1 and 2 RED on the base (the behaviour being removed), green after; test 3 green both times.
2. No timed waits added.
3. Every sentence on the failure path is true: the refusal is the door's existing sentence; nothing changed (byte-for-byte snapshot of the working folder, links by their text).
4. `origin/dev` and M1 merged before proving and before hand-back: already up to date both times.
5. No number tuned by trial: test 3's SHA-256s are recorded from the base, not chosen.
6. Contracts: only U4b2-15's words removed, by reading 7193a22e7 and db41d6729; rows removed by script, every other row identical.
7. `grep -n "DispatchQueue\|\.map {\|\.filter {\|\.reduce(\|\$0"` over the added Swift lines: empty. New tests and helpers sit in the existing MARK section, renamed "A per-section or shared folder that is itself a link (#1055: refused)".
8. No riding lows in this brief.
9. The rename record is still written before a step and cleared after (the refusal comes before it, as in U4b); `undoJournalIsLive` untouched (off).
10. No new or changed contract row; 2 removed, both gone from the Mac replay and the Python model; nothing held.

## For the director

Nothing parked.
