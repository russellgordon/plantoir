# #899 W7b1: the class pages' daily actions through the step

Branch `issue/899-w7b-daily-actions`, from W7a (`origin/issue/899-w7a-publish-through-the-door` bb6e19756) with `origin/dev` merged in (nothing newer at the start).

## For PROGRESS

## 2026-11-21 — Undo and Redo, W7b1: the class pages' daily actions through ONE step (#899, #949)

- **Add Next Class, in a New Unit, Add Classes** (`AssistWorkspace.ApplyAddClasses(plan, progress, actionKey)`): ONE step, every new page a `writeFile` with no before, read through the step (`UndoActionStep.Exists`, the mac's `fileExists`), the class folder made by the swap, never by `Directory.CreateDirectory` beforehand, no `recompute`. Keys from the tool, as the mac's `AssistToolRunner.addNextClass` names them: `add_next_class` → `addNextClass`, or `addNextClassInANewUnit` when `unit` is `next`; `add_classes` → `addClasses`. A page that cannot be planned stops every page ("Nothing was changed: …"); before, the pages before it were written. Every page appeared in between: no step, nothing written (the answer is as before).
- **Curriculum mentions** (`ApplyCurriculumMentions`, `addCurriculumMentions`): the page through ONE step, no `recompute`. A page that cannot be written now says "Nothing was changed: Plantoir doesn’t have permission to change one of them." where `plantoir-mcp` said "Plantoir doesn’t have permission to read that." (a sentence made true).
- **Class Dates** (`TimetableMemory.Write`, `rememberTimetable`): ONE step; the maker from the caller (the Class Dates dialog `sheet` by default; `remember_timetable` and the built-in assistant through `AssistWorkspace.RememberTimetable`, the workspace's surface on its own list); the folder made by the swap; never told to today's undo (it never was); the same dates again make no step; a file that cannot be written returns false, as before, and costs only the record (the re-date goes on). A step left part way returns true: the dates went in (the mac's sheet says them as remembered). The re-date's own timetable write is that same step for now, made by the re-date's surface (see "For W7b2").
- **Bring Pages into Date** (`ApplySyncDates`, the Windows-only `sync_page_dates`): ONE step under Windows' own key `syncPageDates`, each page read through the step, no `recompute` (it never rewrote the front page).
- **The Windows action on the mac's fixture** (`UndoActionStepsOnWindowsTests`, `WindowsActionsOnTheMacFixture`): the mac's `section(surface:)` laid down (each recorded step's files from their befores; the pages it does not touch checked against every recorded before that names them), the REAL Windows tool run with the mac's arguments on the mac's surface, and the one new begin line matched: key, `madeBy` word, files in order, op kinds, recomputes, each file's after. Steps 0 to 3 (W7a's) and 4 to 6, 11 and 12 run; 7 to 10 and 13 to 24 are held by name in `NamedGapLedger.UndoActionStepsOnWindows` (`Reason899W7b2`, `Reason899NoDuplicateAsNextClass`, `Reason899W7U3b`, `Reason899W8U4a`) and still fail.
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

- **Re-date Classes** (`ApplyReDate`, `reDateClasses`, the front page as `recompute`). The mac's `SectionReDatePlanner.apply` writes NO timetable (it reads the remembered one; it plans each page through `JournaledStep`, `into outerStep` for the rollover). Windows' `ApplyReDate` writes `plan.AllMeetings` through `TimetableMemory.Write` before its pages (now a `rememberTimetable` step of its own, made by the re-date's surface). W7b2 decides by the brief's rule: match the mac (neither), or keep it as its own step, and says which. `isARollover: true` makes the same step under `rollOver`; `SettleTheWebsiteAfterARollover`, `ReleaseSite` and the record's release stay outside it for W7c.
- **Make Room for Classes** (`ApplyInsertClasses`, `makeRoomForClasses`): needs `UndoActionStep.Remove` (the mac's `remove`) and a list-of-pages reader through the plan; `carryPastAFailedNewPage`'s write-failure path and #550's part-way trail endings go.
- **Duplicate Class** (`ApplyDuplicateClass`, `duplicateClass`): the room and the copy in ONE step.
- Then the brief's W7b2 list (How I Teach, Start of the Year, Today's Class and Not Today, the links checklist, Classes Dated Later at Deploy).
- In `WindowsActionsOnTheMacFixture.Run`, add each converted action with the mac's arguments (`recordEveryAction`), add its name to `Converted`, and take it out of the ledger.

## For U7

- `syncPageDates` is a Windows key no recorded step holds (the mac has no Bring Pages into Date): when U7 names Edit ▸ Undo's titles, it needs a title for it, and `undo-action-steps.json` has no row to run it from (its test is `ReDateTests.SyncingIsOneStepUnderWindowsOwnKey`).

## For the director

- **Duplicate as Next Class:** the mac's Section menu has it (`SectionVerbs.duplicateAsNextClass`, the recorded step `duplicateAsTheNextClass`); Windows has no such command (no `DuplicateAsNextClass` anywhere in `windows-app/`). None was built; the step is held by name under `Reason899NoDuplicateAsNextClass`. Whether Windows owes the menu command is for #949's owner.
- **The curriculum block's lead line differs** ("Today's work points here:" on Windows, "## Curriculum connection" on the mac): a difference nobody recorded choosing. Kept, since with the switch off nothing may change for a teacher; measured in the fixture.

## For the director (both platforms)

- **LOW 4 (step numbers across two computers) is NOT narrowed in W7b1.** The tidies that remove `-new` and identical `-orig` files for `<seq>-apply|undo|redo` (the live settled tidy, the closed-step tidy, W7a's shadow tidy) match by step number alone, and step numbers are per computer, so a PC settling its step 5 could remove another computer's in-flight step 5 `-new` in one synced folder. The narrowing inside Windows (remove a staged `-new` only when its bytes are the step's own recorded after for that page) needs each tidy to be handed the step's after hashes per page; that plumbing through `TidyLeftovers`'s three callers did not fit this piece. The whole cure (a staged name that carries the computer or the process, as the plain write's `shadow-<pid>-<id>` now does) needs the staged-name format in `contracts/file-formats.json` (`undoJournal.stagedFiles`), which W7b1 does not change. Both platforms have the same shape.

## Changed tests and sentences (the failure is now all or none)

- No existing test pinned Add Classes', curriculum mentions', Class Dates' or Bring Pages into Date's old file-by-file failure (searched `NewClassesTests`, `NextClassUnitsTests`, `CurriculumMentionsTests`, `TimetableMemoryTests`, `TimetableTests`, `UndoAcrossToolsTests`).

## Runs (PC, LENOVO i5-8365U, Windows 11 Pro 26200)

(filled in below as they complete)

## Must-fail (`vm-tools/guest/899-w7b-mustfail.json`)

(filled in below)
