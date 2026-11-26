# #899 W7b2-10: W7b1's proof gaps (Windows Undo, #949)

Branch `issue/899-w7b2-10-w7b1-proof-gaps` from `issue/899-w7b-daily-actions` 6f48d833c. Tests and the harness only; no product line moved.

- `origin/dev` merged before proving: "Already up to date" at 6f48d833c (it holds `dev` bfe28b848).
- `origin/dev` merged again before hand-back: 721833253 (`dev` c367a1ad6, U4b). The c3 run below is on that merged tree.

## For PROGRESS

- **Every converted step's traces run the REAL Windows action** (`UndoActionTraceContractTests`), the measured ones included. The exclusion of `WindowsOwnJson` and `WindowsOwnFileInTheStep` steps is gone. A step named in either dictionary is judged through `MeasuredStates`. The lookup goes by the dictionaries, so W7b2-7's and W7b2-8's entries are covered the moment they are added, with no change to the trace test.
  - Each state the replay reaches is recorded twice, as the hash of Windows' bytes and as the hash of the mac's bytes for that state. The states are the laid before, what the action wrote, and each hand edit, which is made to both.
  - Each hash in the trace's `afterUndoingAll` and `final` is turned into Windows' hash of the same state, and the file is compared with that. Nothing is ever compared with the mac's bytes. A hash naming a state Windows never reached fails.
  - After the action, the members `SameMembers` names are compared with the mac's after. A file that is not in `WindowsOwnJson` must be the mac's bytes exactly.
  - The one file more (`reDateClasses`' timetable) is judged on Windows' own bytes alone. After every call it holds what the action wrote while the step is done, and its before while the step is undone. Its op is expected before the recomputes, and its path after the recorded files.
- **The change-nothing tests** (review 1 L3):
  - `CurriculumMentionsTests.AMentionAlreadyOnThePageMakesNoStepAndNoWrite`
  - `ReDateTests.SyncingPagesAlreadyInDateMakesNoStepAndNoWrite`
  - Each checks for no begin line, and that every file under the working folder (the list's own aside) is unchanged, a backup included (`WindowsActionsOnTheMacFixture.EveryFileBut`).
  - The timetable's case was already `UndoClassDatesStepTests.TheSameDatesAgainMakeNoStep`.
- **The harness drives the real Re-date** (review 3 L3).
  - `W7Runs.ChildReDate` now plans and applies `AssistWorkspace.PlanReDate` and `ApplyReDate` on the scratch course (block F, three meetings over three classes), on the run's list and through the run's kill seams (`AssistWorkspace.UndoSeams`).
  - The re-dated pages are measured once on a reference course that is never killed (`REFERENCE` line), never retyped. `ReDatedPage` and `NewMeetings` are gone.

## For documentation 12

- The traces of a converted step whose bytes are Windows' own (`WindowsOwnJson`, `WindowsOwnFileInTheStep`) run the real Windows action. They are judged state by state on Windows' own hashes, each mapped from the mac's hash of the same state. The one file more is judged on Windows' bytes as the step leaves it.
- The `w7-redate-kill` harness run drives `ApplyReDate` itself.

## Riding lows

1. **Review 1 L2** (the `rememberTimetable` traces replayed the JSON draft): closed by `MeasuredStates`, which also covers `WindowsOwnFileInTheStep["reDateClasses"]`. Proven by must-fail rows 1 to 3.
2. **Review 1 L3** (the sabotages and tests still owed):
   - A change-nothing run making a step, for curriculum mentions, Class Dates and sync: rows 4, 5 and 6. Sync cannot be made to step on an unchanged page, because the step's `ChangesAnything` and the door's own rule both refuse one. Its row removes the action's own guard, so a change-nothing sync goes on to write its backup.
   - A recompute where the mac names none, for Class Dates and sync: rows 7 and 8.
   - The missing change-nothing tests: the two named above.
   - A before read at make time, one row per action family: NOT done. See "For the director".
3. **Review 3 L3** (the harness did not call `ApplyReDate`): closed by `ChildReDate`. See "Runs".

## Must-fail lines

`vm-tools/guest/899-w7b2-10-mustfail.json`; results under "Runs".

1. The timetable written for section + 1: the rememberTimetable traces (SameMembers `section`).
2. The re-date's timetable written under a source without "block ": the reDateClasses traces (Windows' own bytes of the one file more).
3. The re-date plans no timetable: the reDateClasses traces (files and ops).
4. Curriculum mentions plan a code already on the page: `AMentionAlreadyOnThePageMakesNoStepAndNoWrite`.
5. Class Dates recorded as the moment, not the day: `TheSameDatesAgainMakeNoStep`.
6. Sync's `ChangesNothing` guard removed: `SyncingPagesAlreadyInDateMakesNoStepAndNoWrite`.
7. Class Dates keeps the front page true: `TheWindowsActionLeavesTheRecordedStep(rememberTimetable)`.
8. Sync keeps the front page true: `SyncingIsOneStepUnderWindowsOwnKey`.

## Runs

All three were on the PC (LENOVO 20QES70500, i5-8365U, 16 GB, Windows 11 Pro 26200), under `wt-compare.lock`, through `vm-tools/guest/899-w7b2-10-go.ps1` (a copy of `899-w7b-pc-run.ps1`), with the brief's seven classes.

- **`899w7b2-10-c1`** at 98cd48401: both builds 0; Passed 243, **Failed 2** (`action-062` and `action-063`). A line edit redone over a hand edit makes a merged state that no mapping holds. Fixed in 32aa6f704: only `WindowsOwnJson` files are mapped state by state. Every other file of the step is checked to be the mac's bytes after the action, and its hashes pass through unchanged.
- **`899w7b2-10-c2`** at 32aa6f704 (classes, must-fail, harness):
  - Classes: **Passed 245, Failed 0**.
  - Must-fail: **8 of 8 RED**, build 0 each. Rows 1 to 3 each failed 6 traces; row 4 failed 2; rows 5 to 8 failed 1 each. Restored: Passed 245, Failed 0; HEAD the same, status clean.
  - Harness: the real `ApplyReDate` refused the scratch folder, which had no launcher marker ("isn't a Plantoir working folder yet"), so no kill point ran. The marker was added in 9dd5be229.
- **`899w7b2-10-c3`** at 9dd5be229 (holds `dev` c367a1ad6):
  - Classes: both builds 0; **Passed 245, Failed 0**.
  - **`w7-redate-kill`: 12 of 12 WHOLE outside OneDrive and 12 of 12 inside, failures 0.** The `REFERENCE` line shows timetable=after with 3 pages moved. Killed at `afterBegin`, `beforeSwap@0` to `@3` (the fourth file is the timetable) and `beforeApplied`, shadow then live.
  - Live is all-before (Failed or RolledBack) or all-after (Done). Shadow's interrupted steps leave each file whole.
  - stagedNew 0 everywhere; both scratch folders removed; HEAD the same, status clean.
  - The brief allowed one harness run. c2's harness never reached a kill point, so c3 holds the one real run.

## Self-check

1. **Broke each fix and watched its test fail:** must-fail rows 1 to 8 RED (c2). The new change-nothing tests are the ones rows 4 and 6 turn red.
2. **No timed waits:** none added.
3. **Failure-path sentences:** no product line moved, so no sentence changed.
4. **`dev` merged before proving** (6f48d833c, "Already up to date") and again before hand-back (721833253), proven in c3.
5. **No number tuned by trial:** none. The re-dated pages are measured on a reference course, never retyped.
6. **House style and contracts:** no `contracts/` or `mac-app/` change; tests and the harness only.
7. **Fixture rows:** no row changed (none was converted here); the ledger is untouched; all named classes are green.
8. **Writer scan:** no product writer moved, so no count changed.
9. **Riding lows:** L2 and review 3's L3 fixed. Review 1's L3 is fixed except the "before read at make time" rows, which are parked under "For the director" with the reason.
10. **File order and befores:** the traces now also check that the re-date's own file comes after the recorded files and before the recomputes.

## Left for the next piece

- The "before read at make time" rows, one per action family. They wait on the director's ruling below.

## For the director

**The before read at make time cannot be sabotaged per action family without a product seam.**

Every converted action plans through `UndoActionStep.Write`, and `Plan` reads each before there, once, for all five families. The only way to tell a plan-time read from a make-time read is a file that changes between the plan and the make, and that window sits inside one action call. It has no hook: the door's seams (`BeforeTheBegin`, `AfterTheCheck`) fire after `RecordableChanges` has built the draft, so a sabotaged read gives the same draft. W7a's row (`899-w7a-mustfail.json`, "a before read at make time") proves the shared line with `UndoActionStepTests.ABeforeIsReadAtPlanTimeSoAPageChangedInBetweenRefusesTheStepAndNothingIsWritten`. The fixture proves that every family's befores are the recorded ones.

Options:

- **(A, recommended)** Add a test-only seam to `UndoActionStep` that runs between the last `Write` and `Make` (an `init` action, null in the app), in W7b2-11, the piece that carries the small code lows. One real-action test per family then edits a planned file in that window and expects "Nothing was changed" with the edit kept. The five rows follow, each reverting `Plan`'s read to `RecordableChanges`.
- **(B)** Rule that W7a's single row covers all five families, because the read is one shared line, and close the item.
