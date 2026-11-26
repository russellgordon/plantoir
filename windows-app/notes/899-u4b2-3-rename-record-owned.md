# U4b2-3: a rename record exists only while the rename that wrote it is unfinished (#899)

Branch `issue/899-u4b2-3-rename-record-owned`, from `origin/dev` a03fecefd. Mac only; no `contracts/` change; no ledger row.

## For PROGRESS

- Mac, U4b2-3: `SpecialFolderRenamer.rename` (the one-call rename for a caller with no settings to change; no caller in the app, tests only) now clears the interrupted-rename record it wrote once its step is made or refused with nothing changed, and puts back byte for byte any record an earlier run left there (which its own had replaced on disk). Only a step left part way (`leftPartWay`) or killed (`stoppedByATest`) keeps its record. A success that finishes the recorded rename (the record names this same rename) clears it. Fixes the U4b final sweep's L5. Eight new tests in `SpecialFolderRenamerTests`.

## For documentation 12

- Windows as it is today (checked in `windows-app/`): `SpecialFolderRenamer.Rename` (Plantoir.Core/Models/SpecialFolderRenamer.cs:269) writes the record, overwriting any record on disk, only when there are folders to move. Its caller, `CourseSettingsView.xaml.cs:501`, clears the record unconditionally after the settings are written, including when nothing moved, so another folder's unfinished rename is lost the same way the Mac lost it before this piece. A first `Directory.Move` that fails (SpecialFolderRenamer.cs:271-277, nothing moved) throws `RenameException` with nothing changed and leaves this run's record, which then greys the one-section restore (`OneSectionRestore.cs:217-218`). A later move that fails (part way) or a failed settings write leaves the record, which is right.
- What Windows must do (one instruction for W8): read the record already on disk before writing its own. After a refusal that changed nothing (a first move that fails with nothing moved included), put that earlier record back byte for byte, or leave no record when there was none. After a rename that stopped part way, keep this run's record. Once the rename is whole (folders moved and settings written): clear a record of this same rename; clear a record of this folder renamed to another name too, since the settings no longer name the old folder; put back any other earlier record; and touch nothing when no folder moved and the record is another folder's. If the put-back or clear fails, write a `folder renamed` trail line saying "did not rename" after a refusal and "renamed" only once the rename is whole.

## Must-fail lines

See `windows-app/notes/899-u4b2-3-mustfail.log`. 4 RED of 4, plus tests first (R0: 5 tests red on dev's `rename`).

- M1 success clear removed: `testASuccessfulRenameLeavesNoRecord` "the record was left" (and two more).
- M2 clear on every refusal: `testAnEarlierRunsRecordSurvivesARefusedRenameOfAnotherFolder` "the earlier run's record was not left as it was".
- M3 part way treated as refusal: `testARenameStoppedPartWayKeepsItsRecord`, `testARenameKilledPartWayKeepsItsRecord`.
- M4 cleared before the plan: `testAnEarlierRunsRecordSurvivesARenameRefusedAtItsPlan` (and three more).

## Runs

All through `xlock.sh`, 15-minute kill, logs in `/Users/russellgordon/plantoir/wt-899-u4b2-3/.dd/`.

- `run-good.log`: SpecialFolderRenamerTests 39/0, AssistCurriculumMentionsTests 14/0, UndoRenameFolderStepTests 30/0 (83 tests, 0 failures).
- `run-scan.log`: UndoWriterScanTests (reads SpecialFolderRenamer.swift as source text) red at "has 5 writing calls; the list allows 3"; allowance raised to 5 with the put-back named in its reason; `run-scan2.log` 6/0.
- `run-r0.log`, `run-m1.log` to `run-m4.log`: must-fail above.
- Merges of `origin/dev`: before proving and before hand-back, both "Already up to date" (dev stayed at a03fecefd); no merge commit was needed.

## Review 1 (M1, L1 to L5), fixed in this branch

- M1: `CourseSettingsView.renameFolder` now owns its record through `RenameRecordClaim` (in `SpecialFolderRenamer.swift`, the model), the same type `rename` uses: read once before the loop; `renameIsStarting` before each make that moves folders; `nothingWasChanged` on the changed-since retry and every refusal; `stepWasNotMade` keeps it part way or killed; `renameIsWhole` on success. Four new tests in `UndoRenameFolderStepTests` (success of another folder, a rename that moves nothing, refused at the make, retry then re-plan refused), all red on the round-1 view. No interface change.
- L1 accepted and stated in documentation 09 and the claim's doc comment: a kill between this run's write and the put-back loses the earlier record, as before; refusing instead would be a new sentence and its own contract piece; U7 drops the record.
- L2: a put-back or clear that fails writes a `folder renamed` trail line (`SpecialFolderRenamer.renameNoteNotTidiedLine`); test `testARecordThatCannotBeTidiedIsToldOnTheTrail` (record folder made read-only during the step).
- L3: a success that renames the recorded folder (same `from` and scope) to any name clears the earlier record (`recordNamesTheFolder`); test `testRenamingTheRecordedFolderElsewhereClearsItsRecord`.
- L4: pinned, `testARefusedFinishOfTheRecordedRenameKeepsItsRecord`.
- L5: `AssistCurriculumMentionsTests` sets `UndoJournalLocation.folderOverride` to a temp folder in setUp and clears it in tearDown.
- Runs: `run-r2-good.log` SpecialFolderRenamerTests 42/0, AssistCurriculumMentionsTests 14/0, UndoRenameFolderStepTests 34/0, UndoWriterScanTests 6/0 (the allowance stays 5: the same write and remove, moved into the claim). Must-fail round 2: 5 RED of 5, plus tests first (mustfail log).
- For documentation 12: see that section (rewritten after review 2, L-C, to match Windows as it is).

## Review 2 (L-A, L-B, L-C), fixed in this branch

- L-A: `RenameRecordClaim` takes `changesTheSettings` (true from `renameFolder`, false from `rename`). Once the rename is whole, a record of this folder renamed to another name is cleared only when this run moved folders or the caller changes the settings; a `rename` that moves nothing leaves it. Test `testARenameThatMovesNothingKeepsTheRecordOfThisFoldersUnfinishedRename` (red at P1). Doc comment and documentation 09 say the same.
- L-B: `renameNoteNotTidiedLine` takes `wasRenamed`: "did not rename the folder ... and could not tidy" after a refusal, "renamed the folder ... but could not tidy" once whole. `testARecordThatCannotBeTidiedIsToldOnTheTrail` now checks the refusal wording (red at P2). The order on success (the tidy line before the main "renamed" line in `renameFolder`) is left as it is; harmless, as the review says.
- L-C: "For documentation 12" rewritten to agree with `windows-app/` as it is.
- Not pinned by a test: `renameFolder` clearing a record of the same folder with another target when nothing moved (`changesTheSettings` true). The code path is the same `oldNameIsGone` condition the L3 test drives through moved folders.
- Runs: `run-r3-good.log` SpecialFolderRenamerTests 43/0, AssistCurriculumMentionsTests 14/0, UndoRenameFolderStepTests 34/0, UndoWriterScanTests 6/0. Must-fail round 3: 2 RED of 2 (mustfail log).

## Left for the next piece

None.

## For U7

- Dropping the record removes `RenameRecordClaim`, `recordNames`, `recordNamesTheFolder` and `renameNoteNotTidiedLine` with it, and the UndoWriterScanTests allowance for SpecialFolderRenamer.swift falls back (5 today).

## For the director

- Choice (a) over (b): `rename` kept and made to clear, because removing it would mean rewriting five tests in `SpecialFolderRenamerTests` and one in `AssistCurriculumMentionsTests` onto plan/apply/make, larger than the fix. The invariant read literally ("nothing clears a record another run wrote") needed more than renameFolder's model: since the record is one file per course, a run that writes its own record has already replaced an earlier one, so `rename` reads it first and puts it back. No parked questions.

## Self-check

1. Broke each fix and watched its test fail: R0 plus M1 to M4, every new test red under at least one (log above).
2. No timed waits: none added; the tests use the existing kill-point seams, which fire on events.
3. Every sentence on the failure paths is true: `rename` throws the same errors as before and says nothing itself; no sentence changed. The doc comments of `rename`, `RenameRecordClaim`, `recordNames`, `recordNamesTheFolder` say what the code does; `recordRenameStarting`'s comment ("cleared once it is made, or refused with nothing changed") is now true of both writers.
4. `dev` merged in before proving: `origin/dev` a03fecefd is the base; both merges "Already up to date".
5. No number tuned by trial: the UndoWriterScanTests allowance 3 to 5 is the count of the two writing calls added (`write`, `removeItem`, now inside `RenameRecordClaim`); round 2's trail line adds no writing call.
6. House style and contracts: no `contracts/` change; changed files are `mac-app/` Swift, documentation 09 (one paragraph at the end of the Undo section), and these notes.
7. House style grep over added Swift lines: empty. New tests sit under their own `// MARK: -` section in the existing class.
8. Riding low L5: fixed, tests failed first (R0).
9. The rename record is still kept (written before the step, kept part way); `undoJournalIsLive` untouched, off.
10. No new or changed contract row.
