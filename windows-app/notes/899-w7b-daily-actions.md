# #899 W7b1: the class pages' daily actions through the step

Branch `issue/899-w7b-daily-actions`, from W7a (`origin/issue/899-w7a-publish-through-the-door` bb6e19756) with `origin/dev` merged in (nothing newer at the start).

## For PROGRESS

## 2026-11-21 — Undo and Redo, W7b1: the class pages' daily actions through ONE step (#899, #949)

- **Add Next Class, in a New Unit, Add Classes** (`AssistWorkspace.ApplyAddClasses(plan, progress, actionKey)`): ONE step, every new page a `writeFile` with no before, read through the step (`UndoActionStep.Exists`, the mac's `fileExists`), the class folder made by the swap, never by `Directory.CreateDirectory` beforehand, no `recompute`. Keys from the tool, as the mac's `AssistToolRunner.addNextClass` names them: `add_next_class` → `addNextClass`, or `addNextClassInANewUnit` when `unit` is `next`; `add_classes` → `addClasses`. A page that cannot be planned stops every page ("Nothing was changed: …"); before, the pages before it were written. Every page appeared in between: no step, nothing written (the answer is as before).
- **Curriculum mentions** (`ApplyCurriculumMentions`, `addCurriculumMentions`): the page through ONE step, no `recompute`. A page that cannot be written now says "Nothing was changed: Plantoir doesn’t have permission to change one of them." where `plantoir-mcp` said "Plantoir doesn’t have permission to read that." (a sentence made true).
- **Class Dates** (`TimetableMemory.Write`, `rememberTimetable`): ONE step; the maker from the caller (the Class Dates dialog `sheet` by default; `remember_timetable` and the built-in assistant through `AssistWorkspace.RememberTimetable`, the workspace's surface on its own list); the folder made by the swap; never told to today's undo (it never was); the same dates again make no step; a file that cannot be written returns false, as before, and costs only the record (the re-date goes on). A step left part way returns true: the dates went in (the mac's sheet says them as remembered). The re-date's own timetable write is that same step for now, made by the re-date's surface (see "For W7b2").
- **Bring Pages into Date** (`ApplySyncDates`, the Windows-only `sync_page_dates`): ONE step under Windows' own key `syncPageDates`, each page read through the step, no `recompute` (it never rewrote the front page).
- **The Windows action on the mac's fixture** (`UndoActionStepsOnWindowsTests`, `WindowsActionsOnTheMacFixture`): the mac's `section(surface:)` laid down (each recorded step's files from their befores; the pages it does not touch checked against every recorded before that names them), the REAL Windows tool run with the mac's arguments on the mac's surface, and the one new begin line matched: key, `madeBy` word, files in order, op kinds, recomputes, each file's after. Steps 0 to 3 (W7a's) and 4 to 6, 11 and 12 run; 7 to 10 and 13 to 24 are held by name in `NamedGapLedger.UndoActionStepsOnWindows` (`Reason899W7b2`, `Reason899NoDuplicateAsNextClass`, `Reason899W7U3b`, `Reason899W8U4a`) and still fail. A held step whose Windows action exists here (`HeldButRunnable`: Make Room for Classes, Duplicate Class, Re-date Classes, How I Teach, Get Ready for the Start of the Year) is RUN with the mac's arguments and must fall short for its named reason: it changed one of the recorded step's files and left no applied begin under the recorded key (`HeldStillWritesWithoutItsStep`). One that changes nothing fails for that reason (a real failure, must-fail row 17); one that makes the recorded step reads as the gap closing. The other held steps (the sheets' records, the rollover, U4a, Duplicate as Next Class) are Windows actions (the Today's Class and Not Today sheets, the links checklist, Classes Dated Later, the menu's Duplicate as Next Class since #927) or not yet built (the rollover as one step, U4a), but have no tool this replay drives, and stop at the guard that names it.
- **A new class page carries the build's checkout line endings** (measured 2026-11-21 on the PC: `core.autocrlf true`, `AssistWorkspace.cs` `i/lf w/crlf`). `ClassSkeleton` is a C# raw string literal, so on a CRLF checkout every line of a new page from Add Next Class, in a New Unit, and Add Classes is CRLF but the unit tag's two (`"tags:\n  - unit-N\n"`). This is what Windows already wrote before W7b1 (the switch-off invariant keeps it); the fixture holds Windows' page byte for byte to exactly that transform of the mac's after (`NewClassPageSteps`, `AsThisBuildWritesANewClassPage`, decided by a raw-literal probe compiled from the same checkout; identity on an LF checkout), and those steps' traces hash the new pages with CRLF read as LF only on a CRLF build (must-fail row 18).
- **A refused step is begun and closed `failed` by the door** (W7a's door): a test of a refusal counts APPLIED steps (`WindowsActionsOnTheMacFixture.AppliedBegins`), never begin lines (`CurriculumMentionsOnAPageThatCannotBeWrittenChangeNothing`, `ReDateTests.SyncingIsOneStepUnderWindowsOwnKey`).
- **The replay hands each tool a progress**, as the MCP server always does; `null` reached `PlantoirTools.Relay` and threw.
- **The traces of a converted step run the REAL Windows action** (`UndoActionTraceContractTests`): the fixture laid in the replay's folder, the workspace's steps on the replay's own door (`AssistWorkspace.UndoDoorOfATest`), the action's `expect` and `seq` read from the newest closing line. Steps 0 to 6 so (42 traces). `addCurriculumMentions` and `rememberTimetable` keep the recorded draft: their bytes are Windows' own (below), so the mac's hashes cannot judge them.
- **Windows' own bytes, measured, never retyped** (the fixture asserts the difference is still there, so a difference that closes fails and its entry goes):
  - `addCurriculumMentions`: one line, the one under `%%curriculum-start%%`: Windows writes "Today's work points here:", the mac "## Curriculum connection". Everything else byte for byte.
  - `rememberTimetable`: `section` and `dates` the mac's; the file is System.Text.Json indented two spaces with `"key": value`, members in the order section, dates, source, recorded, no closing newline, where the mac's `JSONSerialization` writes sorted keys, `" : "` and a closing newline; `recorded` is the day it is written (the mac's test fixed it at 2026-09-08); a source not given is Windows' "the teacher", the mac's "not recorded". Both readers look members up by name.
- **The final review's lows:** LOW 1 (`LaterClassesKept`'s remarks say the record read is the question once more, and one planned then unwritable at the swap refuses the whole Publish Class for a Date; test `APublishClassForADateWhoseRecordCannotBeWrittenAtTheSwapChangesNothing`). LOW 3 (a plain write's label is `shadow-<pid>-<id>`, `UndoSwap.PlainLabel`, at both places, `UndoActionStep.WritePlainlyQuietly` and the door's list-failure write; every swap first tidies beside each target a GONE process's `shadow-…-new` and an `-orig` identical to its page, keeping a differing `-orig`, an only copy, and a running process's files: `UndoSwap.TidyPlainLeftoversOfTheGone`; tests `UndoPlainWriteLeftoversTests`, harness `w7-plain-kill`). LOW 5 below. LOW 4: see "For the director (both platforms)".
- Writer scan: `TimetableMemory.cs`'s entry gone (no writing call left); `AssistWorkspace.cs` 5 → 4 (the class folder's `Directory.CreateDirectory` gone), its reason naming what still waits (Make Room, Re-date and its front page, Duplicate Class: W7b2; the rollover's marker: W7c).
- Harness (`Plantoir.UndoHarness/W7Runs.cs`): `w7-add-classes-kill` (three new pages in a class folder that does not exist, killed at `afterBegin`, each `beforeSwap@i`, `beforeApplied`, shadow then live, recovered by a second process: each page absent or whole, live all one way, no staged file, nothing Hidden but a kept copy) and `w7-plain-kill` (LOW 3).

## For documentation 12

### What Windows has built: W7b1, the class pages' daily actions (#899, #949)

The bullets above. Correction to W7a's "For W7b": the planners read through the step while `PlanningThrough` is set (an `AsyncLocal`, per flow; never `_planningThrough`, which W7a's round four replaced): an action that plans several things in one step sets it for its planning, as `Apply` and `ApplyWholeUnit` do (LOW 5). With the switch off a teacher meets the same files and the same answers as before W7b1, except that a failure is now all or none and says "Nothing was changed: …" where nothing was.

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
- **The curriculum block's lead line differs** ("Today's work points here:" on Windows, "## Curriculum connection" on the mac): a difference nobody recorded choosing. Kept, since with the switch off nothing may change for a teacher; measured in the fixture.

## For the director: a question that is Russell's

- **Windows' page templates carry the build's line endings.** Every C# raw string literal that becomes a file (here `ClassSkeleton`; likely others) is CRLF in a build from a `core.autocrlf true` checkout, LF from any other, and the parts written with `\n` stay LF, so a new class page is mixed. A teacher's bytes therefore depend on which machine built the release. Options: (1, recommended) `windows-app/**/*.cs text eol=lf` in `.gitattributes` (or `.ReplaceLineEndings("\n")` where a literal becomes a file), so Windows writes the mac's LF bytes whatever the checkout: a byte change for teachers of PC-built releases, which is why it was not made in W7b1; then `AsThisBuildWritesANewClassPage` goes. (2) Keep it, measured as now.

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

`899w7b-mf1` at 79d71c4fd: **18 of 18 RED** (rows 1 to 16 the writer's; 17, a held row's run is real: Make Room asked of a unit that does not exist changes nothing and the held row fails; 18, the unit tag written CRLF breaks the fixture's byte-for-byte line-ending transform), each with build 0; restored tree **Passed! 1214, Failed 0, Skipped 1, Total 1215**; HEAD the same, status clean.

## Review 1 round (2026-11-25): the two mediums, the lows, Re-date proven

Merged `origin/dev` 66c9853a8 first (818f5753b; `NamedGapLedger.cs` kept both sides). The dead writer's half-written Make Room and Duplicate conversion is in `git stash` as "w7b1 half-written Make Room and Duplicate, 2026-11-21", untouched, for W7b2.

### For PROGRESS

- **M1, Class Dates left part way.** `TimetableMemory.WriteDown` returns a `TimetableWriteOutcome` (remembered, not saved, or remembered with what the file held kept, `StoppedPartWay` and `WhatWasKept`); `Write` keeps its bool (true when the dates are on disk) for setup callers. The Class Dates sheet says the mac's `savedWithWhatItHeldKept` words (`classDatesAreRemembered`, `undo.wording.classDatesKeptLead`, one `classDatesKeptBesideIt` per kept file) in its status line and stays open; Save again closes it, the same dates changing nothing. (The mac shows an alert; the kept-file alert is held for no W7b piece, so the sheet's own status line carries it.) `remember_timetable` answers `publishStoppedPartWay` ("the class dates", the mac's words) naming the kept file, never "Recorded". Re-date's timetable write names its kept file in the re-date's answer, refusal included.
- **M2.** Add Classes, Add Next Class, curriculum mentions and Bring Pages into Date failing at the step go through `AssistWorkspace.RefusalForAStepThatStopped`: "Nothing was changed: …" when the door wrote nothing, the part-way sentence naming each kept file when it left one (the mac's `saidWhenTheStepStopped`: "the classes you asked for", "the curriculum mentions"; Windows' own "the pages’ dates"), always an `AssistRefusal`, never "That couldn’t be read".
- **LOW 1.** A refused swap removes the empty folders it made (`UndoSwap.MakeTheFolderOf`, `RemoveTheEmptyFoldersMade`: innermost first, only while empty). Test `UndoAddClassesStepTests.ARefusedStepLeavesNoEmptyClassFolder`; the old test's name no longer claims it.
- **LOW 4 measured.** A read-only curriculum page says "Nothing was changed: Plantoir doesn’t have permission to change one of them." (`UndoActionStep.Reason`'s read-only case); the earlier notes were right, and the test now asserts the whole sentence.
- **LOW 5.** The re-date's and the tool's timetable steps are the workspace's (`NewUndoStep`), with its door and seams.
- **LOW 6.** `Reason899W7b2` and `Reason899NoDuplicateAsNextClass` say what is true (Windows has the menu's Duplicate as Next Class since #927, still without a step); the writer-scan line's indentation; the harness child's comment says it plans the pages itself.
- **LOW 7:** "For the director (both platforms)".
- **Not done in this round:** LOW 2 (the `addCurriculumMentions` and `rememberTimetable` traces still replay the JSON draft) and the rest of LOW 3 (sabotages of a before read at make time, and change-nothing steps for sync and curriculum mentions): left for the next piece on this code.

### For documentation 12

- A Windows step left part way is never said as "couldn’t be read" or as plainly done: every converted action says "Nothing was changed" or the part-way sentence naming each kept file; Class Dates says the dates are remembered and names the hidden file (the mac's sheet words).
- A refused swap leaves no empty folder it made.

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
