# U4b2-3: a rename record exists only while the rename that wrote it is unfinished (#899)

Branch `issue/899-u4b2-3-rename-record-owned`, from `origin/dev` a03fecefd. Mac only; no `contracts/` change; no ledger row.

## For PROGRESS

- Mac, U4b2-3: `SpecialFolderRenamer.rename` (the one-call rename for a caller with no settings to change; no caller in the app, tests only) now clears the interrupted-rename record it wrote once its step is made or refused with nothing changed, and puts back byte for byte any record an earlier run left there (which its own had replaced on disk). Only a step left part way (`leftPartWay`) or killed (`stoppedByATest`) keeps its record. A success that finishes the recorded rename (the record names this same rename) clears it. Fixes the U4b final sweep's L5. Eight new tests in `SpecialFolderRenamerTests`.

## For documentation 12

- Any rename path that writes the interrupted-rename record clears it the same way: after the rename is whole, and after a refusal that changed nothing; only a rename that stopped part way or was killed leaves it; and nothing clears a record another run wrote (an earlier record replaced by this run's is put back as it was). Checked in `windows-app/` today: Windows' `SpecialFolderRenamer.Rename` (Plantoir.Core/Models/SpecialFolderRenamer.cs, about line 269) writes the record only once every destination is checked and folders are about to move, and its one caller, `CourseSettingsView.xaml.cs` (about line 501), clears it only after the settings are written; a move that fails part way, or a settings write that fails, leaves it, which matches. Windows has no journaled step yet, so there is no "refused at the make with nothing changed" path there; when W8 makes the rename one step, a refusal at the make clears the record (or puts back an earlier one), as above.

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

## Left for the next piece

- `CourseSettingsView.renameFolder` (out of scope here): renaming a folder whose moves are non-empty while ANOTHER folder's interrupted-rename record is on disk overwrites that record with its own (`recordRenameStarting`, one file per course), then clears it on success or on a refusal at the make, so the earlier run's record is lost and the sheet no longer offers to finish the other rename. `rename` now reads and puts back the earlier record; `renameFolder` could do the same with `recordNames` and `putBackRecord` (both added here, `nonisolated static`). Its success clear is also unconditional. Not changed, as the brief puts `renameFolder` out of scope; low.

## For U7

- Dropping the record removes `recordNames` and `putBackRecord` with it, and the UndoWriterScanTests allowance for SpecialFolderRenamer.swift falls back (5 today).

## For the director

- Choice (a) over (b): `rename` kept and made to clear, because removing it would mean rewriting five tests in `SpecialFolderRenamerTests` and one in `AssistCurriculumMentionsTests` onto plan/apply/make, larger than the fix. The invariant read literally ("nothing clears a record another run wrote") needed more than renameFolder's model: since the record is one file per course, a run that writes its own record has already replaced an earlier one, so `rename` reads it first and puts it back. No parked questions.

## Self-check

1. Broke each fix and watched its test fail: R0 plus M1 to M4, every new test red under at least one (log above).
2. No timed waits: none added; the tests use the existing kill-point seams, which fire on events.
3. Every sentence on the failure paths is true: `rename` throws the same errors as before and says nothing itself; no sentence changed. The doc comments of `rename`, `recordNames`, `putBackRecord` say what the code does; `recordRenameStarting`'s comment ("cleared once it is made, or refused with nothing changed") is now true of both writers.
4. `dev` merged in before proving: `origin/dev` a03fecefd is the base; both merges "Already up to date".
5. No number tuned by trial: the UndoWriterScanTests allowance 3 to 5 is the count of the two writing calls added (`write`, `removeItem` in `putBackRecord`).
6. House style and contracts: no `contracts/` change; changed files are `mac-app/` Swift, documentation 09 (one paragraph at the end of the Undo section), and these notes.
7. House style grep over added Swift lines: empty. New tests sit under their own `// MARK: -` section in the existing class.
8. Riding low L5: fixed, tests failed first (R0).
9. The rename record is still kept (written before the step, kept part way); `undoJournalIsLive` untouched, off.
10. No new or changed contract row.
