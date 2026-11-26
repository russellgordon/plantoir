# #899 W7b1: the class pages' daily actions through the step

Branch `issue/899-w7b-daily-actions`, from W7a (`origin/issue/899-w7a-publish-through-the-door` bb6e19756) with `origin/dev` merged in (nothing newer at the start).

## Left unfolded (a later section may contradict it; which is later could not be told)

- **The Windows action on the mac's fixture**, remaining sentences: Steps 0 to 3 (W7a's) and 4 to 6, 11 and 12 run; 7 to 10 and 13 to 24 are held by name in `NamedGapLedger.UndoActionStepsOnWindows` (`Reason899W7b2`, `Reason899NoDuplicateAsNextClass`, `Reason899W7U3b`, `Reason899W8U4a`) and still fail. A held step whose Windows action exists here (`HeldButRunnable`: Make Room for Classes, Duplicate Class, Re-date Classes, How I Teach, Get Ready for the Start of the Year) is RUN with the mac's arguments and must fall short for its named reason: it changed one of the recorded step's files and left no applied begin under the recorded key (`HeldStillWritesWithoutItsStep`). One that changes nothing fails for that reason (a real failure, must-fail row 17); one that makes the recorded step reads as the gap closing. The other held steps (the sheets' records, the rollover, U4a, Duplicate as Next Class) are Windows actions (the Today's Class and Not Today sheets, the links checklist, Classes Dated Later, the menu's Duplicate as Next Class since #927) or not yet built (the rollover as one step, U4a), but have no tool this replay drives, and stop at the guard that names it.
- Writer scan: `TimetableMemory.cs`'s entry gone (no writing call left); `AssistWorkspace.cs` 5 → 4 (the class folder's `Directory.CreateDirectory` gone), its reason naming what still waits (Make Room, Re-date and its front page, Duplicate Class: W7b2; the rollover's marker: W7c).
- **LOW 5.** The re-date's and the tool's timetable steps are the workspace's (`NewUndoStep`), with its door and seams.

## For W7b2

Not converted in W7b1 (each still writes file by file; each held by name in `UndoActionStepsOnWindows` under `Reason899W7b2`):

- **Re-date Classes** is converted after all (5a3eae568, proven in review 1's round): no longer W7b2's.
- **Make Room for Classes** (`ApplyInsertClasses`, `makeRoomForClasses`): needs `UndoActionStep.Remove` (the mac's `remove`) and a list-of-pages reader through the plan; `carryPastAFailedNewPage`'s write-failure path and #550's part-way trail endings go.
- **Duplicate Class** (`ApplyDuplicateClass`, `duplicateClass`): the room and the copy in ONE step.
- Then the brief's W7b2 list (How I Teach, Start of the Year, Today's Class and Not Today, the links checklist, Classes Dated Later at Deploy).
- In `WindowsActionsOnTheMacFixture.Run`, add each converted action with the mac's arguments (`recordEveryAction`), add its name to `Converted`, and take it out of the ledger.

## For U7

- `syncPageDates` is a Windows key no recorded step holds (the mac has no Bring Pages into Date): when U7 names Edit ▸ Undo's titles, it needs a title for it, and `undo-action-steps.json` has no row to run it from (its test is `ReDateTests.SyncingIsOneStepUnderWindowsOwnKey`).

## For the director

- **Duplicate as Next Class:** `dev` now has it on Windows (#927, `AssistWorkspace.MenuDuplicate.cs`), still written without a step; held under `Reason899NoDuplicateAsNextClass`, whose sentence now says so. W7b2 converts it with Duplicate Class (`duplicateAsTheNextClass`).
- **The curriculum block's lead line** is settled by #1039: a new block carries the mac's "## Curriculum connection"; a block already on a page is found by its markers and left as written. Nothing for Russell.

## For the director: a question that is Russell's

- **Settled by #1040, no longer a question:** a new class page is written LF whatever the checkout (`PageTextFromLiteral`), so a teacher's bytes no longer depend on which machine built the release. Other raw literals that become files are #1040's scope, not this piece's.

## For the director (both platforms)

- **LOW 4 (step numbers across two computers) is NOT narrowed in W7b1.** The tidies that remove `-new` and identical `-orig` files for `<seq>-apply|undo|redo` (the live settled tidy, the closed-step tidy, W7a's shadow tidy) match by step number alone, and step numbers are per computer, so a PC settling its step 5 could remove another computer's in-flight step 5 `-new` in one synced folder. The narrowing inside Windows (remove a staged `-new` only when its bytes are the step's own recorded after for that page) needs each tidy to be handed the step's after hashes per page; that plumbing through `TidyLeftovers`'s three callers did not fit this piece. The whole cure (a staged name that carries the computer or the process, as the plain write's `shadow-<pid>-<id>` now does) needs the staged-name format in `contracts/file-formats.json` (`undoJournal.stagedFiles`), which W7b1 does not change. Both platforms have the same shape.

- **The plain write's tidy across computers (review 1, LOW 7).** `UndoSwap.TidyPlainLeftoversOfTheGone` judges a `shadow-<pid>-<id>` leftover "gone" by a pid on THIS computer, so in a folder two computers sync, this one can remove the other's in-flight `-new` (and an identical `-orig`); its swap then refuses, or is left part way if a raced edit needed that `-orig`. The same shape as LOW 4 above; the cure is the same (a staged name carrying the computer), which needs `contracts/file-formats.json` and so is the director's.

## Changed tests and sentences (the failure is now all or none)

- No existing test pinned Add Classes', curriculum mentions', Class Dates' or Bring Pages into Date's old file-by-file failure (searched `NewClassesTests`, `NextClassUnitsTests`, `CurriculumMentionsTests`, `TimetableMemoryTests`, `TimetableTests`, `UndoAcrossToolsTests`).

## Runs (PC, LENOVO i5-8365U, Windows 11 Pro 26200)

- `899w7b-a6` at 9d90bf3c5: both builds 0; 51 failed of 1215 (the replay's null progress, 28; the new class pages' checkout line endings, 18 traces and 3 fixture rows; two refusal tests counting begin lines). Fixed in a6a03f07d and 79d71c4fd (with `origin/dev` 8117678f8 merged in, which brought W4c and W7a).
- `899w7b-a8` at 79d71c4fd: both builds 0; **Passed! Failed: 0, Passed: 1214, Skipped: 1, Total: 1215, 47 s** (the Undo classes and every class covering a converted action; the skip is `UndoWebsiteContractTests.ARecordFolderThatDeniesListingCannotTell`, as before).
- `899w7b-h1` at 79d71c4fd, the kill harness, outside and inside OneDrive (running): `w7-add-classes-kill` total=10 failures=0 in each place (Shadow and Live, killed at afterBegin, beforeSwap@0..2, beforeApplied; Live all one way: NothingTookEffect, RolledBack or Completed; no staged file, nothing Hidden); `w7-plain-kill` total=3 failures=0 in each place (leftNew=0 leftCopies=0). Scratch folders removed.

## Must-fail (`vm-tools/guest/899-w7b-mustfail.json`)

`899w7b-mf1` at 79d71c4fd: **18 of 18 RED** (rows 1 to 16 the writer's; 17, a held row's run is real: Make Room asked of a unit that does not exist changes nothing and the held row fails; 18, the unit tag written CRLF breaks the fixture's byte-for-byte line-ending transform; row 18 is retired since the transform is gone with #1040, replaced by `899-w7b1-mustfail-4.json`), each with build 0; restored tree **Passed! 1214, Failed 0, Skipped 1, Total 1215**; HEAD the same, status clean.

## Review 1 round (2026-11-25): the two mediums, the lows, Re-date proven

Merged `origin/dev` 66c9853a8 first (818f5753b; `NamedGapLedger.cs` kept both sides). The dead writer's half-written Make Room and Duplicate conversion is in `git stash` as "w7b1 half-written Make Room and Duplicate, 2026-11-21", untouched, for W7b2.

### Runs (PC)

- `899w7b1-c3` at 2cff6e384: both builds 0; **Passed 1344, Failed 0, Skipped 1, Total 1345** (the Undo classes, the ledger, every class covering a converted action, `PublishStoppedPartWayTests`, `DateTextTests`). Kill harness, outside and inside OneDrive: `w7-publish-kill` 10/10, `w7-add-classes-kill` 10/10, `w7-plain-kill` 3/3 WHOLE, scratch removed. Re-date (5a3eae568) is proven by this run: its fixture row, `SectionVerbsTests`, `RolloverWebsiteTests` and must-fail rows 1 to 3.

### Must-fail (`vm-tools/guest/899-w7b1-mustfail-2.json`)

`899w7b1-c3` (rows 1 to 7, 9, 10), `899w7b1-mf2` (11) and `899w7b1-mf3` (8, after its filter was corrected from `TimetableTests` to the class `ReDateTests`, and the file written with ASCII escapes so PowerShell reads the curly apostrophes) at 2cff6e384: **11 of 11 RED**, each with build 0; restored tree Passed 1344, Failed 0, Skipped 1 each time; HEAD the same, status clean.

1. Re-date written file by file (`Save`): `TheWindowsActionLeavesTheRecordedStep` (reDateClasses).
2. Re-date names no recompute: the same row.
3. Re-date refused, the old rethrow: `ReDateWhoseSecondPageCannotBeWritten_ChangesNothing`, `RollOverWhoseSecondPageCannotBeWritten_ChangesNothing`.
4. M1, a timetable left part way answers a plain remembered: `ATimetableLeftPartWayNamesTheKeptFile`, `TheToolSaysATimetableLeftPartWayAsPartWay`.
5. M1, `remember_timetable` says Recorded: `TheToolSaysATimetableLeftPartWayAsPartWay`.
6. M2, Add Classes rethrown: `ClassesLeftPartWayAreSaidAsPartWay` (both tools).
7. M2, curriculum mentions rethrown: `CurriculumMentionsLeftPartWayAreSaidAsPartWay`.
8. M2, Bring Pages into Date rethrown: `ReDateTests.SyncingLeftPartWayIsSaidAsPartWay`.
9. LOW 1, the empty folders left: `ARefusedStepLeavesNoEmptyClassFolder`.
10. M1, the sheet's lead not the contract's: `TheSheetsWordsForAKeptTimetableAreTheContracts`.
11. LOW 4, a read-only page said as a full disk: `CurriculumMentionsOnAPageThatCannotBeWrittenChangeNothing`.

## Review 2 round (2026-11-25): Re-date and Roll Over are ONE step

### Runs (PC)

- `899w7b1-r2a` at e025a638d (`dev` bfe28b848 merged): both builds 0; ReDateTests, RolloverWebsiteTests, SectionVerbsTests, UndoActionStepsOnWindowsTests, NamedGapLedgerTests, UndoClassDatesStepTests, UndoActionTrace/OpKinds/Website/Trace contract tests, UndoWriterScanTests: **Passed 407, Failed 0, Skipped 1**. Harness outside OneDrive: `w7-redate-kill` total=12 failures=0; scratch removed; HEAD the same, status clean.

### Must-fail (`vm-tools/guest/899-w7b1-mustfail-3.json`)

The separate `rememberTimetable` step put back (`WriteDown` through `NewUndoStep("rememberTimetable", …)` in place of `PlanInto`): **4 of 4 RED**, build 0 each: the fixture row `TheWindowsActionLeavesTheRecordedStep`, `AReDateWhosePagesAreRefusedLeavesTheTimetableAsItWas`, `AReDateStoppedPartWayLeavesTheTimetableAsItWas`, `RollOverWhoseSecondPageCannotBeWritten_ChangesNothing`. Restored: Passed 407, Failed 0, Skipped 1.

## With #1039 and #1040 merged (2026-11-25): the two Windows-own differences gone

Merged `origin/issue/1039-1040-win-class-skeleton` (3fbe4eb13; no conflict). The final sweep (`vm-tools/briefs/2026-11-25-w7b1-skeleton-sweep.md`) found this branch's tests pinned the two differences that branch closes. Tests and notes only:

### Runs (PC, CRLF checkout)

- `899w7b1-r3a` at 7d7962b07 (holds 79871a6f8 and `dev` bfe28b848): both builds 0; **Passed 217, Failed 0, Total 217** (UndoActionTraceContractTests 152, UndoActionStepsOnWindowsTests 30, NewClassesTests 16, CurriculumMentionsTests 11, NamedGapLedgerTests 8). No step differs from the Mac's recorded bytes with the pins gone, `addCurriculumMentions`' traces through the real Windows action included.

### Must-fail (`vm-tools/guest/899-w7b1-mustfail-4.json`)

**2 of 2 RED**, build 0 each: (1) `PageTextFromLiteral` made the identity (#1040 reverted): 21 failed; (2) `CurriculumHeading` put back to "Today's work points here:" (#1039 reverted): 4 failed. Restored: Passed 217, Failed 0; HEAD the same, status clean.
