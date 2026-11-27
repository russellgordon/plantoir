# day27 integration-7: the two gate failures (2026-11-27)

Both came from "a restore settles a stopped step" (#899; notes in
`899-restore-settles-a-stopped-step.md`).

## 1. Mac: `UndoRestoreSetAsideTests.testAStepStoppedBeforeARestoreIsNeverJudgedAgainstTheRestoredCourse`

**Cause: the TEST, not the product.** The test used the Undo list the whole
unit suite shares (the throwaway home's `Application Support/Plantoir/undo`)
and ran recovery "as at a launch" with `processIsAlive` false and a
`resolveRoot` that answered its own working folder for EVERY step's folder.
Earlier classes leave steps in flight on that shared list:

- `UndoActionStepsTests`: `testTodaysClassLeftPartWayIsAnsweredByWhatThePageShows`
  (`showTodaysClassOnTheFrontPage`), `testClassDatesLeftPartWayAreSaidAsRemembered`
  and `testTheClassDatesSheetCarriesOnWhenTheDatesWentInPartWay`
  (`rememberTimetable`) leave their part-way steps in flight there (only
  `record(...)` and a few tests pointed the list at a folder of their own).
- `StartOfYearRestoreOfferTests` leaves its stopped Get Ready steps there.

The test's recovery judged those foreign ICS3U steps against ITS course,
found their files changed by hand, closed them `interrupted` and wrote their
`cleared` line, whose `seq` is the highest in the journal at that moment
(`UndoRecovery.write`, by design: ruling 7). That clearing took the second
Get Ready (done) off the list: `["889:interrupted", "890:cleared"]`. Reproduced
in a diagnostic run: steps 46, 68 and 70 (UndoActionStepsTests) closed
`changedByHand`, three `cleared` lines at seq 105.

Why it is not the product: on a teacher's disk recovery resolves each step's
own working folder (`UndoReach.root`), so a step from another folder is never
judged against this course; the clearing is the intended rule. No `done`
restore record was involved (restore records live in each working folder's
own `restoring` folder, and every test makes a fresh one).

**What changed (tests only):**

- `StartOfYearRestoreOfferTests.setUp` points `UndoJournalLocation.folderOverride`
  at a list of its own; `tearDown` puts it back to nil and deletes it.
  `UndoRestoreSetAsideTests` calls those, so it gets its own list too.
- `UndoActionStepsTests.setUp` gives each test its own list (removed in
  `tearDown` with the others); `record(...)` now puts back the list it found
  instead of nil.
- `UndoRestoreSetAsideTests`' recovery resolves only its own working folder.

**Proof** (one `xcodebuild test` with 24 `-only-testing:` classes in the gate's
order: CourseRestorerStaged, CourseRestorer, RestoreDuringAFolderRename,
RestoreRecovery, RestoreWholeCourseContract, StartOfYearNaming,
StartOfYearPlanTable, StartOfYearRestoreOffer, StartOfYear, then every Undo*
class from UndoActionSteps to UndoRestoreSetAside): RED before (the same two
assertions, `["104:interrupted", "105:cleared"]`), green after (427 tests, 0
failures); `UndoRestoreSetAsideTests` alone green (2 tests). A narrower set
of 7 classes without UndoActionStepsTests was green even before, which is
how the culprit was narrowed.

## 2. Windows: `PythonToolchainTests` → `scripts/test_make_undo_traces.py`

**Cause:** `contracts/file-formats.json` → `undoJournal.events` gained
`filesReplacedByARestore`, and the format test's fixed set did not.

**What changed:** the test's set names the event. The shared model
(`scripts/make_undo_traces.py`, `Model`) now folds it as `folding.moves`'
row says: `files_replaced_by_a_restore(seq, paths)` leaves a step in flight
(`begun`) in its phase and adds the paths to its `setAside`, each once; a
step not in flight ignores it. A new test,
`test_files_replaced_by_a_restore_folds_as_the_contracts_row_says`, reads the
row from the contract and checks the model against it. 42 tests, all green
on this Mac; `make_undo_traces.py --check` says `undo-traces.json` is current.

**Why the Mac gate missed it:** `verify.sh` runs a written LIST of the
shared Python tests, not a discovery (its header says so), and
`test_make_undo_traces.py` is not on it: 111 of the 133 `scripts/test_*.py`
are listed. Only Windows' `PythonToolchainTests`, which discovers them, ran
it. `verify.sh` was not changed.
