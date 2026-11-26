# Plantoir for Windows — Progress

## Where the app stands (2026-10-22, `dev` after the v1.8.5 release; branch `issue/565-trail-wording-red` in flight)

Read this first; the dated entries below are history, newest first, and an earlier batch's "the ledger holds…" or "comes with #514" was true on its own day only.

- **Windows has caught up to the mac's 1.7.1.** Sixteen issues' Windows halves are on this branch: the menu bar and Open Recent (#488, #483), the Section menu's functions (#489) and classes dated after the next class at Deploy (#475), the one Settings window — Assistant, Preview, Deploying — with the Account ID edited only there and Help ▸ Plantoir Help (#491 part A, #490), the HIG sweep (#491 part B), hiding rebuilds and the rebuild-question sentences (#479, #478, #481, #482), the scheduled run's Queue policy, its own tools refresh and the close that waits for a copy (#470, #477, #484), printable pages (#496), the runtime's diagram and graph engines (#503), and Preview at Last Viewed (#514). `RELEASING.md` → "Landed since v1.7.1" lists them with their platforms.
- **1.7.2's catch-up wording and endings are on `dev` since 1bc61e09d** (2026-10-16): scheduled deploys no longer ask for a cable and say a PC on battery sleeps sooner (#547); `plan_write_how_i_teach` refuses a course kept for reference (#540); the assistant's Make Room card says Undo will not take it back, with a scenario proposed to the mac (#530); and the Section menu's trail endings, "took part of the last change back" among them, with Re-date Classes… that stops part way saying so (#550). Details: documentation/07 ("Plugged in…" removed), 10 and 12 ("Writes with no new undo entry, and Undo's three endings").
- **`NamedGapLedger` is empty again** (2026-11-11): #734 held two activity-trail events for v1.9.3; #739 wrote "deploy refused for the Cloudflare Account ID" and #736 wrote "asked an assistant to fix problems", each deleting its entry. Before that: **it was empty again since #720** (2026-11-10, branch `issue/720-assistant-obsidian-lap-cap`), which took mac #698's regenerated contract: `wording.obsidianIsNotOnThisMachine` is said with `{machine}` filled ("this PC"), and the two entries #690 held against #698 (v1.9.1) from 2026-10-28 — `wording.obsidianIsNotOnThisMac` and the scenario "open in Obsidian on a Mac without Obsidian presses nothing (#610)" — are deleted. (Empty from #581, 2026-10-22, which recorded its four Obsidian add-on events; it held those from `issue/565-trail-wording-red` the same day; before that it was empty from 2026-10-16.)
- **Every clone and worktree must run `windows-app\Vendor\fetch-obsidian-addons.ps1` once** (since #581, 2026-10-22): the app's build REFUSES without the seven pinned add-on files (`CheckObsidianAddOns`), as it refuses a stale runtime.
- **The version on `dev` is 2.0.0, the release being built; the last Windows release is 1.9.3** (`<Version>` in `Plantoir.csproj`, raised 2026-11-13 by #862, the Windows half of the mac's #861: the number is now raised when work on a release starts and the cut checks it, `RELEASING.md` → "When the number is raised". The named-gap ledger compares with the last release Windows SHIPPED, read from `website/site.json` and `website/updates/windows.xml`, and `publish.ps1 -Sign` compares it with `<Version>`; `documentation/12-windows-app.md` → "Named gaps". This line said "The version is 1.9.3" until then: bumped 2026-11-12 when Windows went from 1.9.0 straight to 1.9.3 and joined the v1.9.3 release. This line said 1.8.7 until then, through 1.8.8 to 1.9.0. Before that: 2026-10-23 when Windows joined v1.8.7 the same day as the mac; it had been 1.8.6 since Windows joined v1.8.6 earlier that day). Windows 1.7.1 joined the v1.7.1 release on 2026-10-16 (#481), and the bump to 1.7.2 followed with its catch-up wording. (This line said 1.7.1 until 2026-10-22, after the csproj had moved.)
- **Gates** (since #542's piece, 2026-10-16: the last FULL unit run was at `issue/542-polish-172` 76364b50b — Failed 0, Passed 2779, Total 2779, 6 m 12 s; the commits after it had targeted and UI re-runs only, and the merged dev gets its own full run at the version bump). **At the earlier branch's last commit** (Intel i5-8365U, 16 GB, Windows 11 Pro 26200, one 1920 × 1080 screen at 150%, 2026-10-15/16): `dotnet test` Failed 0, Passed 2725, Skipped 0, Total 2725 (6 m 21 s); the FULL UI suite, unlocked, once: Failed 2, Passed 80, Skipped 0, Total 82 (40 m 8 s) — `GettingReadyUiTests.ClosingDuringTheCopyWaitsForItThenQuits` passed alone straight after (2 of 2, a load flake), and `NewCourseWizardUiTests.EscapeClosesTheCodeListThenTheWizard` failed alone too ("TextBox is off screen" — the harness window is short at 150%) and passes (8 of 8) since the test brings the app forward instead of clicking a box below the window's edge.
- **What was owed on an unlocked desktop is done** (2026-10-15, on the console): the eleven `[UiFact]`s pass (four test fixes and one app fix — the corner sketch's ids; see the entry below), the two print pictures are taken (`print-page`, `print-handout` now `windows: true`), and WebView2's own printing, the hand-over through ShellExecute and the toolbar's width are measured (`documentation/12-windows-app.md` → "Printable pages" and "Toolbar width"). Two decisions they raise are the director's: the hand-over could be dropped (WebView2 prints the handout itself), and the window's minimum. **Corrected 2026-10-16 (#542):** the minimum was already 900 epx (1350 px at 150%; measured, nothing drags below it); what was wrong is that the window OPENED below it, at 793 epx on a first run at 150%, because its size was set before the minimum. It now opens at the minimum or wider — `documentation/12-windows-app.md` → "Toolbar width".

## 2026-11-25 — #899 W7b2-9: the kept-file alert for Show on Front Page (branch `issue/899-w7b2-9-kept-file-alert`)

- W7b2-9 (#899): Show on Front Page left part way (`ShownWithWhatItHeldKept`) shows ONE alert in the section window. The alert has `keptTitle`, `kept` and the hidden-items sentence (`class-planning.json` → `todaysClassOnTheFrontPage.keptOnWindows.hiddenItems`), OK as the default and Close (so Enter and Escape give OK), and Open Folder. Open Folder opens the front page's folder (`FolderActions.OpenFolder`) and never selects the file, which stays hidden (Russell's ruling of 2026-11-25 (a)). A kept file gone by the press says `keptGone` and opens nothing. The four held keys (`keptTitle`, `kept`, `showKept`, `keptGone`) and `Reason899W4cKeptAlert` are gone from the ledger.
- The part-way trail line is pinned by a test (W7b2-6 review 1 L2). The two "could not be read" timetable sentences have the curly apostrophe (L1).

## 2026-11-25 — #899 W7b2-6: Show on Front Page is ONE step (branch `issue/899-w7b2-6-todays-class`)

- W7b2-6 (#899): Show on Front Page (`TodaysClassOnTheFrontPage.ShowOnTheFrontPage`, reached by `AssistWorkspace.ShowTodaysClass`, key `showTodaysClassOnTheFrontPage`, made by `sheet`) writes the front page through ONE `UndoActionStep`, the page as the step's content (`writeFile`), never a `recompute`: the teacher's own choice of class, as the mac's `TodaysClassOnTheFrontPage.show(_:in:)`. The step is asked for (`newStep`) only once the page is to be written, so `AlreadyShows` and `NoLongerOffered` make no step. The fixture row is converted (driven on the mac's `morning()` for 2026-09-30, its offer, Unit 2, Day 5 in place of Unit 2, Day 4; out of the ledger; it was never in `HeldButRunnable`), and its traces run the real Windows action.
- `TodaysClassOnTheFrontPage.Outcome` is now a closed record family (`Written`, `ShownWithWhatItHeldKept(KeptOriginals)`, `AlreadyShows`, `NoLongerOffered`, `CouldNotSave`) so the part-way case carries each kept file (full paths; `KeptNames` gives the names), as the mac's `shownKeepingWhatItHeld(from:to:keptOriginals:folder:)`.
- Riding lows: W7b2-5 review 1 L1 (notes), L2 (`PlaceInTheFolder` removed, the step sorts by `Relative`), L3 (`APlanThatChangesNothingMakesNoStep` checks the declined sentence); W7b2-11 review 2 L1 (#1043 named in its notes) and L2 (the held-timetable sentence now has a curly apostrophe: "Nothing was changed: another program, such as a syncing service, is using this section’s class dates. Try again in a moment."; its test changed to match). PROGRESS's and documentation 12's copies of that sentence are curly since this fold.

## 2026-11-25 — #899 U4b2-1, U4b2-2 and U4b2-3 on the Mac: a linked page written through, the place that leads out named, the rename record (notes for W7b2 and W8)

- Mac, U4b2-1: with `undoJournalIsLive` off, a daily action whose page is a symbolic link now writes the file the link leads to, and the link stays a link (Russell's ruling on #899, 2026-11-25). Before, the Mac refused such a page from U3 on. Windows already behaved so; no Windows code owed.
- Mac, U4b2-2: the plan already named the first of `path`, `from`, `to` that leads out (U4b part I); since review 1 the check made again just before each change (staging and swap) names it too (`UndoSwap.placeLeadingOut`). Pinned by six `undo.stackCases` rows (three Undo, three Redo) read through a new key `refusalNamed`, a sentence in `undo.rule.stagedThenSwapped`, and nine `UndoDoorGuardTests` (Undo and Redo; only the new place, only the old place for Redo, both; four at the staging and swap checks). The Python model (`scripts/make_undo_traces.py` `plan`) names the same place now; it named `path or from` before. `undo-traces.json` unchanged (`make_undo_traces.py` says current).
- Windows, U4b2-2: six stack rows held under `Reason899W8U4b` (sentence extended to name the calls and key): the three U4b2-2 Undo rows and the three U4b2-2 Redo rows. The U2 link row is unchanged and still runs on Windows.
- Mac, U4b2-3: `SpecialFolderRenamer.rename` (the one-call rename for a caller with no settings to change; no caller in the app, tests only) now clears the interrupted-rename record it wrote once its step is made or refused with nothing changed, and puts back byte for byte any record an earlier run left there (which its own had replaced on disk). Only a step left part way (`leftPartWay`) or killed (`stoppedByATest`) keeps its record. A success that finishes the recorded rename (the record names this same rename) clears it. Fixes the U4b final sweep's L5. Since review 1 `CourseSettingsView.renameFolder` owns its record the same way, through the one model type `RenameRecordClaim` (documentation 09, "U4b2: rename-record-owned"). Twelve new tests in `SpecialFolderRenamerTests`, four in `UndoRenameFolderStepTests`.

## 2026-11-25 — #899 W7b2-11: W7b1's small lows (branch `issue/899-w7b2-11-w7b1-small-lows`)

- **W7b2-11, W7b1's small lows (#899).** `undo.wording.classDatesKeptLead` and `classDatesKeptBesideIt` stay retyped and are pinned against the contract by `TheSheetsWordsForAKeptTimetableAreTheContracts`. A swap cut short by an exception leaves no empty folder it made (`RemoveTheEmptyFoldersMade` in the `finally`). On the second and later change of an assistant chat, a re-date or rollover whose hidden timetable is held by another program says "Nothing was changed: another program, such as a syncing service, is using this section’s class dates. Try again in a moment.", never .NET's sentence with the `.internal/timetable/…` path. From the Section menu, and on a chat's first change, the course backup refuses first with .NET's message and the full path: an older fault, its own issue (the director's).
- **The re-date's front page is now DATED as well as repointed (W7b1 review 2, LOW 3).** It goes through the step's front-page recompute (`RederiveTheFrontPage` → `ApplyIndexChange`, `PointedAndDated`, the mac's `sectionFrontPage` maintainer) where the old code only repointed (`SectionIndex.Repointed`). Right, and the publish rule; but a byte change on the Windows front page after Re-date Classes and Roll Over: its `created` date moves with the section's classes.

## 2026-11-25 — #899 W7b2-5: Get Ready for the Start of the Year is ONE step (branch `issue/899-w7b2-5-start-of-year`)

- W7b2-5 (#899): Get Ready for the Start of the Year (`PrepareForStartOfYear`, key `getReadyForTheStartOfTheYear`) plans every page it puts into draft into ONE `UndoActionStep` and names the section front page as a `recompute` (`sectionFrontPage`), never a file of the step: all or none, the mac's `StartOfYearPlanner.apply`. The app's Go is made by `sheet` (the mac's `UndoStepMaker.sheet`); the assistant's by its conversation. The fixture row `getReadyForTheStartOfTheYear` is converted (out of `HeldButRunnable` and the ledger), and its six traces (action-091 to 096) run the real Windows action.
- Undo Getting Ready (the sheet's own undo) now goes through today's undo, `UndoHistory`, as the mac's `StartOfYearPreparation.undo` records the held change on a fresh `AssistChangeHistory` and undoes it. `AssistWorkspace.StartOfYear.cs` has no writer of its own: its writer-scan entry is gone.

## 2026-11-25 — #899 W7b2-10: W7b1's proof gaps (branch `issue/899-w7b2-10-w7b1-proof-gaps`)

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

## 2026-11-25 — #899 W7b2-4: the How I Teach page through ONE step (branch `issue/899-w7b2-4-how-i-teach`)

- #899 W7b2-4: Write How I Teach (`write_how_i_teach`, key `writeHowITeach`) and Start the How I Teach Page (Course Settings' row, key `startHowITeachPage`, `madeBy` `sheet`) each write the page as ONE `UndoActionStep` through the door, held by the course (`holds: course`, no section), as the mac's `JournaledStep(course:section: nil, holds: "course")`. Both fixture rows run the real actions and are out of the ledger; the writer-scan entries for `AssistWorkspace.HowITeach.cs` and `HowITeachSettingsRow.cs` are gone.

## 2026-11-25 — #899 W7b1: the class pages' daily actions through ONE step (branch `issue/899-w7b-daily-actions`)

#### W7b1

- **Add Next Class, in a New Unit, Add Classes** (`AssistWorkspace.ApplyAddClasses(plan, progress, actionKey)`): ONE step, every new page a `writeFile` with no before, read through the step (`UndoActionStep.Exists`, the mac's `fileExists`), the class folder made by the swap, never by `Directory.CreateDirectory` beforehand, no `recompute`. Keys from the tool, as the mac's `AssistToolRunner.addNextClass` names them: `add_next_class` → `addNextClass`, or `addNextClassInANewUnit` when `unit` is `next`; `add_classes` → `addClasses`. A page that cannot be planned stops every page ("Nothing was changed: …"); before, the pages before it were written. Every page appeared in between: no step, nothing written (the answer is as before).
- **Curriculum mentions** (`ApplyCurriculumMentions`, `addCurriculumMentions`): the page through ONE step, no `recompute`. A page that cannot be written now says "Nothing was changed: Plantoir doesn’t have permission to change one of them." where `plantoir-mcp` said "Plantoir doesn’t have permission to read that." (a sentence made true).
- **Class Dates** (`TimetableMemory.Write`, `rememberTimetable`): ONE step; the maker from the caller (the Class Dates dialog `sheet` by default; `remember_timetable` and the built-in assistant through `AssistWorkspace.RememberTimetable`, the workspace's surface on its own list); the folder made by the swap; never told to today's undo (it never was); the same dates again make no step; a file that cannot be written returns false, as before, and costs only the record. (In a re-date or rollover the timetable is a file of the re-date's own step since W7b1 review 2's M1, so one that cannot be written refuses the whole re-date: see M1 below.) A step left part way returns true: the dates went in (the mac's sheet says them as remembered).
- **Bring Pages into Date** (`ApplySyncDates`, the Windows-only `sync_page_dates`): ONE step under Windows' own key `syncPageDates`, each page read through the step, no `recompute` (it never rewrote the front page).
- **The Windows action on the mac's fixture** (`UndoActionStepsOnWindowsTests`, `WindowsActionsOnTheMacFixture`): the mac's `section(surface:)` laid down (each recorded step's files from their befores; the pages it does not touch checked against every recorded before that names them), the REAL Windows tool run with the mac's arguments on the mac's surface, and the one new begin line matched: key, `madeBy` word, files in order, op kinds, recomputes, each file's after.
- **A new class page is the mac's bytes on every checkout** (#1040, merged into this branch): `ClassSkeleton` is `PageTextFromLiteral(ClassSkeletonLiteral(…))`, LF whatever the checkout, so a new page from Add Next Class, in a New Unit, and Add Classes is held byte for byte to the mac's after on the PC's CRLF checkout too. The checkout-line-ending transform the fixture and the traces once applied (`NewClassPageSteps`, `AsThisBuildWritesANewClassPage`, the raw-literal probe, `checkoutLineEndings`) is gone, and must-fail row 18 of `899w7b-mf1` with it.
- **A refused step is begun and closed `failed` by the door** (W7a's door): a test of a refusal counts APPLIED steps (`WindowsActionsOnTheMacFixture.AppliedBegins`), never begin lines (`CurriculumMentionsOnAPageThatCannotBeWrittenChangeNothing`, `ReDateTests.SyncingIsOneStepUnderWindowsOwnKey`).
- **The replay hands each tool a progress**, as the MCP server always does; `null` reached `PlantoirTools.Relay` and threw.
- **The traces of a converted step run the REAL Windows action** (`UndoActionTraceContractTests`): the fixture laid in the replay's folder, the workspace's steps on the replay's own door (`AssistWorkspace.UndoDoorOfATest`), the action's `expect` and `seq` read from the newest closing line. Steps 0 to 6 so (42 traces). `rememberTimetable` keeps the recorded draft: its bytes are Windows' own (below), so the mac's hashes cannot judge it. `addCurriculumMentions` now runs the real Windows action too (#1039 gave the block the mac's heading, so its bytes are the mac's).
- **Windows' own bytes, measured, never retyped** (the fixture asserts the difference is still there, so a difference that closes fails and its entry goes):
  - (`addCurriculumMentions` is no longer here: since #1039 the line under `%%curriculum-start%%` is the mac's "## Curriculum connection", so `WindowsOwnLine` is gone and the page is compared byte for byte.)
  - `rememberTimetable`: `section` and `dates` the mac's; the file is System.Text.Json indented two spaces with `"key": value`, members in the order section, dates, source, recorded, no closing newline, where the mac's `JSONSerialization` writes sorted keys, `" : "` and a closing newline; `recorded` is the day it is written (the mac's test fixed it at 2026-09-08); a source not given is Windows' "the teacher", the mac's "not recorded". Both readers look members up by name.
- **The final review's lows:** LOW 1 (`LaterClassesKept`'s remarks say the record read is the question once more, and one planned then unwritable at the swap refuses the whole Publish Class for a Date; test `APublishClassForADateWhoseRecordCannotBeWrittenAtTheSwapChangesNothing`). LOW 3 (a plain write's label is `shadow-<pid>-<id>`, `UndoSwap.PlainLabel`, at both places, `UndoActionStep.WritePlainlyQuietly` and the door's list-failure write; every swap first tidies beside each target a GONE process's `shadow-…-new` and an `-orig` identical to its page, keeping a differing `-orig`, an only copy, and a running process's files: `UndoSwap.TidyPlainLeftoversOfTheGone`; tests `UndoPlainWriteLeftoversTests`, harness `w7-plain-kill`). LOW 5 below. LOW 4: see "For the director (both platforms)".
- Harness (`Plantoir.UndoHarness/W7Runs.cs`): `w7-add-classes-kill` (three new pages in a class folder that does not exist, killed at `afterBegin`, each `beforeSwap@i`, `beforeApplied`, shadow then live, recovered by a second process: each page absent or whole, live all one way, no staged file, nothing Hidden but a kept copy) and `w7-plain-kill` (LOW 3).

#### Review 1 round

- **M1, Class Dates left part way.** `TimetableMemory.WriteDown` returns a `TimetableWriteOutcome` (remembered, not saved, or remembered with what the file held kept, `StoppedPartWay` and `WhatWasKept`); `Write` keeps its bool (true when the dates are on disk) for setup callers. The Class Dates sheet says the mac's `savedWithWhatItHeldKept` words (`classDatesAreRemembered`, `undo.wording.classDatesKeptLead`, one `classDatesKeptBesideIt` per kept file) in its status line and stays open; Save again closes it, the same dates changing nothing. (The mac shows an alert; the kept-file alert is held for no W7b piece, so the sheet's own status line carries it.) `remember_timetable` answers `publishStoppedPartWay` ("the class dates", the mac's words) naming the kept file, never "Recorded". Re-date's timetable write names its kept file in the re-date's answer, refusal included.
- **M2.** Add Classes, Add Next Class, curriculum mentions and Bring Pages into Date failing at the step go through `AssistWorkspace.RefusalForAStepThatStopped`: "Nothing was changed: …" when the door wrote nothing, the part-way sentence naming each kept file when it left one (the mac's `saidWhenTheStepStopped`: "the classes you asked for", "the curriculum mentions"; Windows' own "the pages’ dates"), always an `AssistRefusal`, never "That couldn’t be read".
- **LOW 1.** A refused swap removes the empty folders it made (`UndoSwap.MakeTheFolderOf`, `RemoveTheEmptyFoldersMade`: innermost first, only while empty). Test `UndoAddClassesStepTests.ARefusedStepLeavesNoEmptyClassFolder`; the old test's name no longer claims it.
- **LOW 4 measured.** A read-only curriculum page says "Nothing was changed: Plantoir doesn’t have permission to change one of them." (`UndoActionStep.Reason`'s read-only case); the earlier notes were right, and the test now asserts the whole sentence.
- **LOW 6.** `Reason899W7b2` and `Reason899NoDuplicateAsNextClass` say what is true (Windows has the menu's Duplicate as Next Class since #927, still without a step); the writer-scan line's indentation; the harness child's comment says it plans the pages itself.
- **LOW 7:** "For the director (both platforms)".
- **Not done in this round:** LOW 2 (the `rememberTimetable` traces still replay the JSON draft; the `addCurriculumMentions` half closed with #1039, see the last section) and the rest of LOW 3 (sabotages of a before read at make time, and change-nothing steps for sync and curriculum mentions): left for the next piece on this code.

#### Review 2 round

- **M1 (the director's ruling: one teacher action is one step, as on the mac).** The timetable a re-date or rollover writes down is now a file of the re-date's own step (`reDateClasses` / `rollOver`), planned after the pages by `TimetableMemory.PlanInto` (writeFile, never told to today's undo, Windows' own bytes as before); there is no `rememberTimetable` step before it. `WriteDown` (the Class Dates sheet, `remember_timetable`) plans through the same `PlanInto` and makes its own one step. One change of behaviour: a timetable file that cannot be swapped in now refuses the whole re-date (all or none), where before it cost only the record.
- **Pins:** `WindowsOwnStepBefore` is gone (test side only, `UndoActionStepsOnWindowsTests.cs`); in its place `WindowsOwnFileInTheStep["reDateClasses"]` measures the one file more (`courses/ICS3U/.internal/timetable/section1.json`, writeFile, after the recorded files, before the recompute), and the fixture row now asserts ONE new begin. `UndoActionTraceContractTests` reads the new dictionary (its traces still make the recorded draft). Nothing under `contracts/` and nothing in `NamedGapLedger` changed (the ledger never named the pair).
- **M2.** A refusal leaves the timetable as it was, so "Nothing was changed" and the trail's "changed nothing" are true. `AndTheTimetableKept` is gone: a part-way stop names every kept file through `StoppedPartWay`, the timetable's included. This also settles LOW 2 (the kept-file lead's "their" is no longer appended to the re-date's answer).
- **LOW 1.** The assistant's dates card says what is on disk however the sheet closed (`dialog.SavedDates`), so a Cancel after the part-way message no longer says "No class dates were recorded". The menu path still stops the action on Cancel and says nothing (comment updated).
- Tests: `ReDateTests.AReDateWhosePagesAreRefusedLeavesTheTimetableAsItWas`, `ReDateTests.AReDateStoppedPartWayLeavesTheTimetableAsItWas`; `RolloverWebsiteTests.RollOverWhoseSecondPageCannotBeWritten_ChangesNothing` now checks the timetable. Harness `w7-redate-kill` (three pages and the timetable in one step, killed at afterBegin, beforeSwap@0..3, beforeApplied, shadow and live, recovered by a second process).
- Not this round: LOW 3 (front page dated), LOW 4, LOW 5 and review 1's LOW 2 and rest of LOW 3 ride to W7b2.

#### With #1039 and #1040 merged

- `WindowsOwnLine` (the `addCurriculumMentions` entry and its one-differing-line check) is gone from `UndoActionStepsOnWindowsTests.cs`, and with it its exclusion in `UndoActionTraceContractTests`, so the `addCurriculumMentions` traces run the REAL Windows action (half of review 1's LOW 2).
- `NewClassPageSteps`, `RawLiteralProbe`, `RawLiteralsCarryCrLf`, `AsThisBuildWritesANewClassPage` and the traces' `checkoutLineEndings` are gone: `addCurriculumMentions`, `addNextClass`, `addNextClassInANewUnit` and `addClasses` are compared with the contract's recorded step with no Windows-own difference, on every checkout.
- Must-fail row 18 of `899w7b-mf1` (the unit tag written CRLF against the fixture's transform) is retired from `vm-tools/guest/899-w7b-mustfail.json`; its place is `899-w7b1-mustfail-4.json` (below).

## 2026-11-25 — #1039 and #1040: a new class page's bytes match the Mac's (branch `issue/1039-1040-win-class-skeleton`)

- **#1039, #1040 (2026-11-25):** a new class page written by Windows is LF whatever checkout built the app (`AssistWorkspace.PageTextFromLiteral` at the point the skeleton literal becomes text), and a new curriculum block opens with the Mac's `## Curriculum connection`. Existing pages are never rewritten; a block is found by its markers, so pages with the old "Today's work points here:" line are still added to. Tests: `NewClassesTests.ANewClassPageIsWrittenWithLfWhateverCheckoutBuiltTheApp`, `NewClassesTests.TheSkeletonFromACrlfCheckoutStillBecomesLfText` (the literal given CRLF in the test, so it fails on any checkout if the normalising step breaks), `CurriculumMentionsTests.ANewBlockIsTheBlockTheMacWrites` (from `undo-action-steps.json`, step `addCurriculumMentions`), `CurriculumMentionsTests.AnExistingBlockIsAddedToRatherThanReplaced` (now a theory over the old line and the new heading).

## 2026-11-25 — #955, #769 items 1 and 2, #806 and #816, #913 (branches `issue/955-win-custom-domain-reading`, `issue/769a-win-one-folder-however-spelled`, `issue/769b-win-assist-busy-off-screen`, `issue/806-win-webview`)

#### #955: a section's custom domain is read by `customDomainReading`

- #955: `CourseConfiguration.CustomDomain(section, destinationType)` now runs every case of `contracts/file-formats.json` → `customDomainReading` (17 cases, read from the JSON at run time by `CourseConfigurationTests.ACustomDomainIsReadTheContractsWay`, the mirror of the Mac's `FileFormatsContractTests.testACustomDomainIsReadTheContractsWay`). New `CourseConfiguration.DestinationTypesWithAnAddress` (`netlify`, `cloudflare_pages`, the Mac's and the Python's list, same order); the reader returns `""` first for any other type, so `local_folder` never has a domain. Before the change cases 8 ("the older bare string, a folder primary: the folder has no address (#904)") and 10 ("a folder never has a domain, even one written under its name") failed, both reading `ics3u.school.ca`; the other 15, case 6 (empty `deploy_target`) included, already passed, case 6 through `DeployTarget`'s getter.
- Not built, on purpose: `SetCustomDomain` can still carry an old bare string into a `local_folder` map entry when the primary is a folder (the Mac does the same); the reader now ignores that entry, so nothing a teacher sees follows from it.
- Not changed: `CourseSettingsView.xaml.cs` (about line 1053) filters `d.Type != "local_folder"` for the domain fields; it could ask `CourseConfiguration.DestinationTypesWithAnAddress` instead, so GitHub Pages (#669) is picked up when it joins the list. An interface file, outside #955.
- What a folder leg shows now: `MultiDestinationDeployRunner` asks `CustomDomain(section, "local_folder")`, gets `""`, and sets the folder runner's `CustomDomainForLinks` to null, so its link is the folder path (`ScriptRunner.PublishedFolder`), never a domain; before, a folder-primary course with an old bare string or a `local_folder` map entry had that domain on the folder runner (it reached a link only if the folder's transcript held a site URL, which a folder publish does not print).

#### #769 item 1: one folder however it is spelled

- #769 item 1: `CourseActivity` (`IsPreviewing`, `IsPublishing`, `IsPublishingSection`) and `PreviewLeases` (`Take`'s same-section refusal, `Take`'s same-folder ports, `ReleaseLeftBehind`, `Release` by folder) compare working folders through `WorkingFolder.IsTheSame`, never `==`; `UnderWay()` counts preview builds once per `SectionKey`, so two claims on one section under two spellings count once. The two view lease questions (`SectionDetailView.xaml.cs` repair's "open in another window", `AssistWindow.xaml.cs` `PreviewIsShowing`) ask it as `MainWindow.Verbs.cs` already did. The stored spelling is unchanged. The issue's own case: a section deploying under `C:\x` now refuses a preview asked as `C:\X\`, with the existing sentence. Tests: `CourseActivityTests` (five new facts, `Respelled` = upper case plus a trailing separator) and `PreviewWhileDeployingTests.ADeployUnderOneSpellingRefusesAPreviewAskedUnderAnother`.
- The two view lines have no unit test of their own; they ask the same comparison as `MainWindow.Verbs.cs` line 86.
- Not folded, by design: a mapped drive (`Z:\` for `\\server\share`) is not folded by `WorkingFolder.Resolved`, so it is still two folders here, as everywhere else in the app; `Resolved` was not extended.
- Not changed: course code case. `IsPreviewing`, `IsPublishing` and `IsPublishingSection` compare the code with `==`; `SectionKey`, `ReleaseLeftBehind` and `Release` by folder compare it case-insensitively. Each line kept what it had.
- Grep after the change of `windows-app/Plantoir.Core` and `windows-app/Plantoir` for `FolderPath ==`, `== folderPath`, `== _folder`, `== workspacePath`: no hits remain, so there are no other comparisons to name.

#### #769 item 2: the assistant's busy answer does not depend on what is on screen

- #769 item 2 (Windows): the assistant window asked "is this section busy?" of a main window showing the section's folder (`MainWindowShowingThisSection()?.IsSectionBusy(...) == true`), so with no window on that folder a deploy of the section running in this app read as idle, and the assistant went on to the deploy path instead of saying `AssistWording.SectionIsBusy`. Core now has `SectionRuns.DeployIsUnderWay(folder, course, section)` (= `SectionDeployRun.UnderWay(Find(...), ...)`, the section's run if a view made one and the in-process publish record either way), the mac's `SectionDetailView.deployIsUnderWay`; `AssistWindow`'s `SectionIsBusy` calls it. `MainWindow.IsSectionBusy` had no other caller and is removed (its comment moved to the Core method), so there is one path.
- Busy keeps its meaning: a deploy on its way, never a preview. The issue's proposal to also ask the preview leases is not built: `IsSectionBusy`'s comment (now on `DeployIsUnderWay`) and the deploy-during-preview port settle it (the deploy stops a preview itself).
- Not changed: the menu surface (`MainWindow.Verbs.cs` `MenuRunner`) sets no `StartDeployInApp`, so its `deploy_section` never asks `SectionIsBusy`. `MainWindowShowingThisSection` and `MainWindowForBuilds` stay for what needs a window (stopping a preview, the classes-dated-later question, starting the deploy).
- Tests: four facts in `SectionRunsTests` (no run made and a publish record: under way, also under a second spelling; nothing: not; another section: not; record disposed: not). `AssistSurfaceContractTests.TheAssistantAsksTheSectionsDeployStateAppWide` reads the single `SectionIsBusy =` line of `AssistWindow.xaml.cs`. It is its own fact rather than an assertion inside `TheArrowsAreLetThroughInBothCasesTheContractNames` (the one test that already read the file), because that test walks the arrow-key contract and must name only its cases. `SectionDeployRunSourceTests.IsSectionBusyAsksTheRunsByTheCallersFolder` became `NoWindowKeepsItsOwnBusyAnswer` (`MainWindow.xaml.cs` has no `IsSectionBusy(`).

#### #806, #816: the GeoGebra browser check in headless Edge

- #806, #816: browser-checks/geogebra_applet.mjs run once in headless Edge 158.0.4370.33 on the first Windows VM (dev 45be52fbf, Node v22.23.4), on verify.sh's GeoGebra fixture planted into EXC2O and built by preview.ps1 --build-only, a clone with the publish's own _headers served on [::1]: OK in both phases. Item 11 (reset icon, both sketches back as they opened: 5 objects and a = 3; A,B,f,m, dragged again), item 12 (393 and 388 Shift+Tab/Space presses while a 150-line sketch ran: all 150 points, and after reset), item 13 (opening words inside the card while the engine was held, contrast 12.13/7.24 light and 16.27/13.28 dark, figure 433.58 px throughout, a refused file back to its button). The touch-laptop press is not possible in a VM. Notes: windows-app/notes/806-win-webview.md.

#### #913: what the preview's WebView2 contacts

- #913: the section preview's WebView2 now runs on its own environment with IsCustomCrashReportingEnabled = true (crash reports are not sent to Microsoft) and IsReputationCheckingRequired = false on its view (no SmartScreen check of the pages shown), per Russell's rulings of 2026-11-25 (PreviewBrowserEnvironment.cs, SectionDetailView.EnsurePreviewBrowserAsync; PreviewBrowserPrivacySourceTests). Measured before and after in the first Windows VM (runtime 158.0.4370.33, net-log plus the DNS Client log, 300 s from the page): the same contacts both times, with no page address in any request's address, query string or Referer (the request bodies were not captured, only their sizes): Edge's configuration fetch from config.edge.skype.com (2 GETs, first start only), the component updater at edge.microsoft.com (8 POSTs first start, 1 on the next), and WPAD lookups on the local network; the site's own fonts and cdnjs still reached. Those three are left on purpose and documented. Notes: windows-app/notes/806-win-webview.md.

## 2026-11-21 — Lane H, 2026-11-21 night: #805 and #911 (branch `issue/873-win-restore`)

#### #805: a restore keeps the kept copies; a rename carries the builds folder

- `BuildOutputLocation.DiscardBuiltSitesFor(buildsRoot, code)` (the mac's
  `discardBuiltSites`): every entry of `builds\<id>\<CODE>` goes except a
  REAL `.geogebra-cache` folder; one that is a file, a junction or a link to
  itself goes with the rest, as a link (never what it points at); a course
  builds folder that is itself a link is removed as a link and never
  enumerated; the workspace `builds\<id>\work\<CODE>` still goes.
- Both `CourseRestorer.RestoreBackup` paths call it (through
  `CourseArchiver.DiscardBuiltSites`) in place of `DiscardBuilds`; nothing
  else in `RestoreBackup` moved. Archiving and `Restore(ArchivedItem)` still
  discard everything.
- `CourseRenamer.Rename` carries `builds\<id>\<OLD>` to `builds\<id>\<NEW>`
  (`BuildOutputLocation.MoveBuild`, the mac's `moveBuild`): built sites and
  kept copies together; a folder already under the new code is replaced, as
  the mac's `removeItem` then `moveItem`; an old folder that is missing moves
  nothing; the old code's build workspace is discarded (it is made again).
  Silent on failure, as the mac's (`try?`, nothing said).
- The one-section restore's discard (`DiscardBuildsFor(root, code, N)`) never
  reaches `.geogebra-cache`, which lives at course level:
  `SectionSwapTests.ARestoreThatFinishesPutsTheSectionBackAndLeavesNoStaging`
  asserts the kept copy byte for byte after a section restore.
- Ported by hand from the unreviewed `issue/873-restoring-from-a-backup`:
  `DiscardBuiltSitesFor`, `MoveBuild`, `DiscardEntry`, `KeptCopiesFolderName`,
  `CourseArchiver.DiscardBuiltSites`/`BuildsRootOf`, `KeptCopiesTests` (the
  gone-course test now also asserts the copy's bytes and the workspace gone).
- **#805's owed items: all done** (the clear in both paths with the workspace
  discarded, the folder name pinned against
  `buildOutputLocation.keptCopiesSurviveTheClear.folder`, the real-folder rule
  over a file, a junction outside and a junction to itself, and the rename
  carry with its test). #805 can close on its own.

#### #911: one section from a backup made for it, staged and swapped

Built tonight, each a commit:

1. **Step 1, the assistant window's route, staged** (`CourseRestorer.RestoreSection`):
   unpacked into `courses\.internal\restoring\<GUID>\backup\` (never
   `%TEMP%`), checked, live children of `section<N>\` moved to
   `…\<GUID>\as-it-was\section<N>\`, the backup's moved in, every move undone
   last first on a failure (`wording.leftAsItWas`, which the window shows after
   its usual "Nothing was put back:", true then). A way back that did not
   finish: the aside folder moves to
   `courses\_backups\<CODE>\Section N before a restore <yyyy-MM-dd_HHmmss>`,
   `section restore stopped part way` is written (the #911 ledger entry and
   `Reason911` are gone), and the window says `wording.stoppedPartWay` (or
   `stoppedPartWayNothingToOpen`) WITHOUT "Nothing was put back:"
   (`AssistSectionRestore.StoppedPartWay`). If even that move fails, the files
   stay in `courses\.internal\restoring\<GUID>\as-it-was` and that path is
   said. `restoring` and `.internal` are removed non-recursively when empty.
   The `%TEMP%` unpack, the delete-first `ReplaceContents` and its copy
   fallback are gone. Success says nothing new.
2. **Step 2, the offer and naming rules**, pure functions in
   `OneSectionRestore` (`OfferedSection`, `Naming.DifferenceFromBackup`,
   `RenameIsUnfinished`, `ReadFacts`), run from `offerCases` (8) and
   `namingCases` (12). `ReadFacts` reads the zip's listing and its
   `course_config.json` entry from the entry stream (`CourseConfiguration.FromBytes`);
   an unreadable zip holds nothing. Nothing calls `ReadFacts` yet: the dialog
   (step 4) is where it is asked, once per backup, when the dialog is about to
   open.

3. **Step 3, the menu's one-section restore** (`CourseRestorer.RestoreSectionFromTheMenu`,
   the mac's `restoreSectionFromTheMenu`): the same staging and swap, now
   over the section folder AND the nine `filesOutsideTheSection` (each
   `fromTheBackup`, `discarded` or `leftAsItIs`; a `fromTheBackup` file the
   backup lacks is removed, kept aside until the swap is good); the
   per-section keys on shared pages as before; a shared page the backup
   lacks hidden from this section unless the build already reads it hidden
   (`HidingAPageMadeSinceTheBackup`, the ordinary `PageFrontmatter.SetDraft`
   with `publishForSection<N>: false`; pages under `private\`, `templates\`,
   `.obsidian\` or any dot folder never touched, `OneSectionRestore.IsPublishable`,
   pinned to `geogebraFences.files.notPublished.folders`); the section-number,
   reference and naming refusals asked again of the live settings and the
   UNPACKED backup (`namingChanged`, `foldersChanged`, `sectionNotInCourse`,
   the mac's `sectionMissingFromBackup` and `archiveUnreadable` sentences);
   the legacy `.netlify_site.json` in the section's build root kept across the
   discarded build; the `Outcome` (`PagesNotPutBack`, `PagesNotSaved`,
   `PagesMadeSinceHidden`, `WebsiteRecordDiffers`, the markers compared as
   parsed JSON); and the Undo seam `keepingWhatWasReplaced`, handed the aside
   folder before it goes (no caller passes it; a test does).
4. **Step 4, the dialog and the order around it.** `ConfirmRestoreBackup`
   reads the zip once per backup (`_backupFacts`, off the interface thread)
   when the dialog is about to open, asks `OneSectionRestore.OfferFor`, and
   for an offered section shows ONE `ContentDialog`: title `wording.title`,
   content `wording.message` (`BackupMaker.DescriptionFor` and
   `WhenDescription`), Restore Section N (primary, `DefaultButton`), Restore
   Whole Course (secondary: today's whole-course restore, unchanged, moved
   into `RestoreWholeCourse`), Cancel (close, Escape). Otherwise today's
   two-button dialog. The click is `MenuSectionRestore.Run`, the mac's
   `restoreOneSection` in its order: the busy refusal (preview or deploy, in
   the mac's words; an assistant's hold; the Section menu or the assistant
   changing THIS section, `wording.busy`) and every offer condition asked
   again (`RefusalAtTheClick`) BEFORE the archive; the whole course archived
   (`ArchiveCourseWithoutRemoving`); the busy refusal asked again; the
   restore; `section restored` (`RestoredOneSectionFromTheMenuLine`, the
   mac's words) and, when pages could not take a key, `page settings left as
   they were`; then `doneTitle` and `done` with its pieces in the one result
   dialog (`ShowError`'s OK dialog, the backup alert's slot). A failure is
   said under `BackupProblemTitle.Restoring` with the restorer's own sentence.
   The busy refusals before the dialog keep their existing Windows titles.

**HIG (Alerts, read 2026-11-21):** the page puts the default button on the
trailing side and Cancel on the leading side, and says never to make Cancel
the default; it gives no three-button macOS rule. Windows' ContentDialog
lays out primary, secondary, close left to right, and every other
three-button question in this app uses that order, so the brief's "the
Windows order the app already uses" decides: Restore Section N (default,
leftmost), Restore Whole Course, Cancel (rightmost, Escape). No control the
Mac lacks; nothing invisible.

**#911's five "Windows owes" bullets: all DONE** (the third button and the
offer rule; the widened one-section restore; the staged swap with a way back
for BOTH routes; the archive first, the `section restored` line and the
`page settings left as they were` count; the finished line in its notice
slot). #911 can close on its own once reviewed.

**The review of steps 1 and 2 (`vm-tools/briefs/2026-11-21-lane-h-review-1.md`), lows fixed here:**
- LOW 3: only WORK a backup leaves out keeps a replaced section aside:
  `CourseRestorer.LeftOutWork` = `.git`, `node_modules`, `dist`, `build`,
  `out` (a project's history, its packages, what its own tools made). The
  rest of `ExcludedFromArchives` is litter made again on its own and never
  keeps anything: `.DS_Store`, `__pycache__`, `.cache`, `.quartz-cache`,
  `.merged_output`. Tests: `ADeeperFolderOfWorkABackupLeavesOutKeepsTheAsideCopy`,
  `SystemLitterDeeperInTheSectionNeverKeepsTheAsideCopy`,
  `TheLeftOutListSplitsIntoWorkAndLitter` (a name added to the list must be
  decided).
- LOW 1: `RestoreKillTests(staged)` (and the unpack kills) assert `section2\`
  byte for byte and no `as-it-was` folder.
- LOW 2: kills part way through the unpack (`unpack:2`, through a new
  `SectionSwapHooks.UnpackedAnEntry`; the staging unpack now extracts entry by
  entry with ExtractToDirectory's outside-the-folder guard), during the moves
  in (assistant `move:5`, `move:6`; menu `move:7`, `move:10`), and during a way
  back started by a REAL refusal (the harness holds `zz notes\n.md` without
  delete sharing; `back:1`, `back:2`), on both routes: 18 kill cases.
- LOW 4: every sweep case asserts what the teacher is told
  (`SectionSwapFixture.AssertToldTruly`): `leftAsItWas` when the way back
  finished, else `stoppedPartWay` naming the kept folder or
  `stoppedPartWayNothingToOpen`, with the archive sentence on the menu's
  route, and the trail line naming that folder.
- LOW 5: the stacked summary tags in `ActivityTrail.cs`.
- LOW 6 (a section on another volume) and LOW 7 (a kill leaves the unpacked
  backup) are the brief's design, unchanged; said here only.

## 2026-11-21 — #794, #795, #796, #798: Windows reads the guidance-skill pins from the contract
Branch `issue/794-win-skill-pins`. Test code only: `windows-app/Plantoir.Tests/AgentGuidanceSkillPinsTests.cs` (new, `public partial class AgentGuidanceTests`, sharing its `_folder`, `Contract` and `Pass()`), and one word in `AgentGuidanceTests.cs` (`sealed partial`). No product code, nothing under `support/`, `contracts/`, `scripts/` or `mac-app/`. No source-text test reads either file (grepped `Plantoir.Tests` and `Plantoir.UiTests`; the only hit, `NamedGapLedger.cs`, names another test in a comment).

- **#794 done.** `EverySkillSaysWhatTheContractSaysItMust` walks `printablePages.agentGuidance.mustSay` after one real `AgentGuidance.Write`: `rule` skipped; a skill in `held.skills` must have no `SKILL.md` in either home and its phrases are not read; every other key must name a skill written in both homes whose `SKILL.md` holds each phrase by either folded form; at least one skill pinned. Every problem is collected and printed one per line, so a run names all of them. `APhraseIsMatchedAsMustSaysRuleSays` (a `[Theory]`, four rows) proves the matching rule on literal text: a phrase wrapped across CRLF matches by the first form; one wrapped inside `> ` or `>> ` lines only by the second; a changed word by neither.
- **#795 done.** `TheHandoutStartersDefineEveryMacroTheSkillNames`: for each `handoutsSkill.starterMacros` entry, in both homes, the written starter defines each macro (`\newcommand{m}` or `\newlength{m}`) and the skill has a backtick then the macro. A separate test beside `TheHandoutsSkillIsWrittenWithItsStartersAndEveryRouteToItNamesIt`, not inside it, because `issue/953-win-deny-test` changes that file tonight; the assertions are the Mac handouts test's, so the done-state is the same.
- **#796 done.** `TheHintsWrapperIsWrittenAndTheOfferedTemplateIsNamedOnce`: `hintsStarter` written in both homes, defines `\showhints`, named in the skill in backticks, not in `starters`; each `offeredTemplate.namedIn` skill names `offeredTemplate.name` exactly once, white space folded (a count, as the Mac counts it). `\hint` for `starters/Handout.tex` is covered by #795's walk and the new `mustSay` phrases by #794's: nothing added for them.
- **#798 item 1 done.** `TheTestAuthoringSkillIsWrittenWithItsTemplatesAndBothRootFilesNameIt`: in both homes the `testAuthoringSkill.skill` is written with every `templates` file (spaces included); its `SKILL.md` names `usesStyleOf` in backticks and contains `kitChecker`; each `mentionedBy` skill names it in backticks; it is not in `pageAuthoringSkill.routesTo`; both root files name it and no longer contain "a quiz or test for marks". That phrase is the one literal: it is the wording the contract's rule says was removed, so the contract holds no value for it, and the Mac's twin types the same literal. The Mac's other literal checks in that test (`name:`, "This working folder holds courses for Plantoir", `handouts.json`, `read_how_i_teach`) are not copied: the brief allows no literal but the one, and the pinned rules of that skill are `mustSay`'s, which #794 walks.
- **#798 item 2:** see "#798 measured".
- Where Windows differs from the Mac, by design: every assertion in a walk is collected and the test fails once with the list (xUnit stops at the first failed `Assert`, XCTest does not); a key naming a skill that is not written is a problem line, never a crash or a pass on nothing. .NET's `\s` and ICU's differ only in `\v` and U+0085, which no skill contains.
- **Review LOW 1 (held names):** `EachHeldSkillIsKeptInHeldPlaceAndWrittenInNeitherHome`, the held half of the Mac's `testHeldSkillsAreNotWrittenAndNothingWrittenNamesThem`: every `held.skills` key must have a `SKILL.md` under `held.place` (both read from the contract) and no folder of its name in either home after one `Write`. Run on VM B, `8c1da92da` (dev `45be52fbf` merged): both builds 0 errors, `AgentGuidanceTests` 32 of 32. Must-fail: scratch `b0b22debd` (never pushed) added `plantoir-held-nothing` to `held.skills`; 1 failed of 32, `held.skills names plantoir-held-nothing, and no such skill is kept in held/agent_guidance/skills`. Log `vm-tools/runs/794-vm-turn3.log`.
- Run on the second VM, `e2bb8ff5d` (dev `2f50d1fa3` merged): `Plantoir.csproj` and `Plantoir.UiTests.csproj` built (0 errors); `AgentGuidanceTests` 30 of 30 passed.

## 2026-11-21 — #927 Classes ▸ Add Class… on Windows, with #990's review-3 and sweep lows

- **Classes ▸ Add Class…** replaces Add Next Class (#927, the mac's #897 piece A), in the menu bar's Classes menu (Meetings in a club, #990) and on the section row's right-click menu in Add Next Class's place (ruled 2026-11-13 on #897). Its dialog (`SectionVerbDialog.ChooseHowToAddAClass`) asks how: the next class in the unit under way, the first class of a new unit, or a copy of one of this section's class pages; a way that cannot be used is drawn greyed, with the reason lines under the ways (`subjectMenus.addClassSheet`, 8 of 8 cases in `AddClassContractTests`). The first two add at once (Add); a copy is picked from a searchable Page/Date list (7 rows before it scrolls, the mac's), then its plan, then Duplicate. The item's title is "Add Class…" in every course, a club included, as the mac's `SubjectMenus.title` draws it.
- **The copy** (`class-planning.json` → `duplicatingAsTheNextClass`, 6 of 6 cases through the menu's server): the source named by FILE in `duplicateFileFromTheMenu`, an argument no schema declares, read by `plantoir-mcp`'s call filter on the menu's server only (`PlantoirTools.FromTheMenuIfACopy`), so the tool surface every client is shown does not move. Planned as Add Next Class plans the next class; per-section keys out before the date and `publish: false`; read back hidden BEFORE anything is written; planned again after the copy of the course and held to the one shown; written with `FileMode.CreateNew`; a file this call created and could not finish is removed. Refused on the menu while a unit-word rename is unfinished, for a copy and for `unit: "next"` (`UnitWordRenamer.InterruptedRenameTarget(…, clearingAStaleRecord: false)`, new parameter: a stale record is read as stale and LEFT).
- **No entry on the old undo list** for the copy (the night-3 settled list: the entries #927 describes are the in-memory list's; the journal step is W7's). Held by case in `NamedGapLedger` → `MenuCopyUndoEntries` against #899 (5 cases); a held case must still record none. The next-class and new-unit ways keep `add_next_class`'s existing entry.
- **Trail:** `ran from a menu` reads "Classes ▸ Add Class… — carried out, the next class in this unit" (or "in a new unit", "as a copy of a class"), "Meetings ▸" in a club; the copy is "carried out" through `NoteAChangeWithNoUndoEntry`. `class copy not made` gains "did not copy a class from the Classes menu — the copy could not be made certainly hidden, so nothing was written", noted at the plan and at the write.
- **Wording:** 34 keys of `assist-wording.json`, each a member of `AssistWording` (`AssistWording.AddClass.cs`), the noun-and-word forms in `AddClassWords`; the 34 `AssistWordingKeys` ledger entries, the `addClass` older-name entry and `Reason927` removed.
- **#990 review 3's Windows lows:** `AssistAgent.CourseNoun` and `AssistToolRunner.CourseNoun` are `required` (no Class default; 44 test sites and the menu's runner name it; `CourseNounRequiredTests`); `SeparatorGaps` fails "all of one kind" when the gaps span no more than one spacing's rounding (`OneSpacingSpan`, 2: the rule tests' own 7-and-9 reading), so no-separator-with-rounding, every-gap-a-separator and all-equal fail rather than guess. `NothingToUndoFromTheMenu`'s comment gives the true reason (U7/W11b in the same milestone).
- **#990 sweep's three texts:** `contracts/shared-rules.json` "ran from a menu" carries the Classes paths (Meetings in a club); documentation 09 (a club's twins name the Meetings menu); `help/outline.json` start-of-year (Section > Undo Getting Ready).

## 2026-11-21 — #889 piece 889b: Open in Browser for a section deployed to a folder

- **One Open in Browser for both** (#889, the mac's #850): the toolbar's button and Section ▸ Open in Browser open the preview while one shows and the section's deployed folder otherwise; the button's tooltip and Narrator name are `previewHelp`, `help`, or the greyed reason (`DeployedFolderOffer.Sentence`), read on events (`SectionDetailView.RefreshOpenInBrowser`, from `RefreshChrome`: the section showing, a deploy ending, navigation, and `DeployedFolderShows.Changed`). `subjectMenus` gains `stopShowingDeployedFolder` and the situation keys `deployedFolderReady` and `deployedFolderShown` (read in `SituationFor`); the six #889 ledger entries are gone.
- **Under a finished folder deploy**, Open in Browser beside Show in File Explorer (`publishedFolderBrowserButton`; `destinationFolderBrowserButton` in a multi-destination result), with `renderNote` under it in place of the old sentence (same `publishedFolderRenderNote` id, which `PanelHeightUnderSqueezeUiTests` measures).
- **The section row's menu**: Open in Browser while the folder can be opened, Stop Showing Deployed Folder while it is shown, a group of their own after Open in Obsidian, hidden otherwise (the context menus' rule; the mac's D43 placement). The row's Open in Browser is the one Open in Browser: the preview there if one shows (`MainWindow.OpenInBrowserFromARow`).
- **While shown**: the notice `deployedFolderNotice` with Stop (`stopHint` as its tooltip and help text); `stoppedFolderGone` with Dismiss once the folder went away; `couldNotOpen`'s dialog (`couldNotOpenTitle`, OK) for a failure (`Services/DeployedFolderOpening.cs`, the one path every place uses).
- **App-wide**: `RememberPortsIn(App.Settings, …)` and `Diagnostic` at start-up; the three trail events (`deployed folder opened in the web browser`, `… no longer shown`, `… could not be opened`) written from `Happened` in `App`; `StopEverything()` in `QuitTime`; `QuitConfirmation.UnderWay` carries `DeployedFoldersShown` (never asks), and the quit cases read `given.deployedFoldersShown`.
- **Core, the fixes review's L-c**: a press that started a show whose browser refused stops it only if no other press joined it (`_joinedStarts`); a joined press re-checks the show is still running before handing its address over (`IsRunning`). `DeployedFolderShowsTests.AJoinedShowIsNotStoppedByTheStartersRefusingBrowser`; the re-check has no test of its own (the two awaits' order cannot be fixed from a test without a seam).
- **UI test**: `DeployedFolderInBrowserUiTests.OpenInBrowserShowsTheDeployedFolder_AndStopEndsIt` (the address read from `links-opened.txt`, fetched over HTTP, the notice, the menu item, Stop, the trail lines with no path or address).

## 2026-11-21 — #1027: in a club the Meetings menu's items say meeting (Windows half)

- **Club item titles** (#1027, Russell, 2026-11-20 night). `SubjectMenuLayout.TitleHere(item, noun)` has no default; `TitleSayingTheNoun(item, noun)` gives Publish Meeting for a Date…, Add Meeting…, Meeting Dates…, Re-date Meetings…, Make Room for Meetings… in a club (`subjectMenus.layout.itemTitles`). `ApplyMenuEnablement` re-titles those items live with the menu's title; the section row's menu titles Publish… for a Date and Add… by the row's course; `SectionVerbDialog.MenuPath` gives "Meetings ▸ Add Meeting…" on the trail. `AddClassWords.NeedsClassDatesFirst` names "Meetings ▸ Meeting Dates…". `NothingToUndoFromTheMenu(noun)`: the window sends the section's course in the call's `_meta` (`AssistWorkspace.CourseMetaKey`, `IHearsTheMenu.CourseOfTheNextCalls`), `plantoir-mcp`'s filter sets `MenuCourseOfTheCall` for one call. Tests: `ClubNounTests` (four new facts, walking the contract), `ContractTests` (`nothingToUndoFromTheMeetingsMenu`), UI `MenuBarUiTests.TheClassesMenuIsTitledMeetingsWhileAClubIsSelected` reads every Meetings item and Section's Publish Meeting for a Date… from `TitleHere`.

#### Lane B review lows, fixed on this branch (#927/#889)

Open in Browser's offer (`SectionDetailView.ReadTheOfferAgain`) is read off the window's thread, only on `offeredWhen`'s events (the section showing, a deploy ending, a menu opening, the pointer reaching the button, a show starting or stopping); a chrome redraw and `ApplyMenuEnablement` draw the last answer, so a deploy folder on a share that does not answer never stalls the window. The button is named "Open in Browser" for Narrator, the sentence its help text. A create that fails at `CreateNew` is "already there" only when the file is there; otherwise "Nothing was created: …". The ledger's `Reason899MenuCopy` says Undo Last Change after a copy takes back the change before it, until W7. The pointer read has no test: a UI test that made the folder behind the window and glided the pointer onto the button failed with and without the read (runs/1027-vm-turn6.log), so it was removed.

#### Review 1 fixes (MEDIUM 1, lows 2, 3, 5)

the Class Dates dialog says meeting in a club. Its purpose line, the status once dates are read (now the mac's "Remember N class dates for … from … to …"), the refusal of a date too far from today (now the mac's `classDatesTooFarFromToday`, replacing "can't be a class date. Check the year…") and the half-read column refusal (`SectionScheduleSource`, now joined "a, b and c" as the mac joins it) come from `AssistWording.ClassDates.cs`, each a `classDates…` contract key with its `…ForAMeeting` twin; `ClassDatesDialogWords` picks the course's noun. The trail line when remembered dates are set aside is the mac's `classDatesSetAside` now ("remembered class dates set aside: they include …"), said in the course's noun read from its settings. Open in Browser's offer is read again on every route a menu opens by (pointer, keyboard focus, a flyout drawing), and a press the offer no longer holds shows the could-not-open dialog with the greyed reason, then redraws dimmed. A copy from the menu that could not be made says "Nothing was created: " with a permission in plain words (`NothingWasCreated`). A `_meta` value that is not text reads as absent (`AssistWorkspace.MetaText`). Tests: `ClubNounTests.TheClassDatesDialogSaysMeetingInAClub`, `AMetaValueThatIsNotTextReadsAsAbsent`, `TimetableSetAsideTrailTests.InAClubTheLineSaysMeeting`, `DeployedFolderOfferTests.APressNoLongerOfferedSaysTheGreyedReason`, `PublishStoppedPartWayTests.ACopyThatCouldNotBeMadeSaysWhyInPlainWords`, UI `DeployedFolderInBrowserUiTests.AMenuOpenedWithoutThePointerReadsTheOffer_AndAPressNoLongerOfferedSaysWhy` and the Meeting Dates dialog step of `MenuBarUiTests.TheClassesMenuIsTitledMeetingsWhileAClubIsSelected`.

Must-fail record (review 1 fixes): scratch commits never pushed. Mac `runs/1027-r2-mac-mustfail.log`: with each noun use reverted, `testTheClassDatesSheetSaysMeetingInAClub` fails at every sentence (purpose, six refusals, the part-way title, the proposal both ways, the trail line, the missing-course line). Windows `runs/1027-r2-vm-turn3.log` (scratch 7afc52a08): `TheClassDatesDialogSaysMeetingInAClub` (purpose), `TimetableSetAsideTrailTests.InAClubTheLineSaysMeeting`, `APressNoLongerOfferedSaysTheGreyedReason`, `ACopyThatCouldNotBeMadeSaysWhyInPlainWords`, `AMetaValueThatIsNotTextReadsAsAbsent` fail; UI `AMenuOpenedWithoutThePointerReadsTheOffer…` fails at the menu read and `TheClassesMenuIsTitledMeetingsWhileAClubIsSelected` at the dialog's purpose line. `runs/1027-r2-vm-turn4.log` and `turn5.log` (scratch 4e8670cde): the dialog's too-far refusal alone reverted fails `TheClassDatesDialogSaysMeetingInAClub`; the silent press alone fails the UI test's second half.

#### Round 3: review 2 fixes (MEDIUMs 1 and 2, lows 3, 4, 5)

in a club the trail counts of Add Meeting… say "the next meeting" or "as a copy of a meeting" (`addClassCounts…`, walked from `subjectMenus.layout.itemTitles.countsCases`), and Deploy's hide counts "N meetings dated later, unticked at Deploy" (`untickedAtDeployCounts`). A make-room plan's problems (`timetableTooShortFrom`, `timetableTooShortAfter`, `noDaysAfterTheLastPage`, `pagesNotNamedTheCoursesWay`; the mac's `unusedDatesRunShort` too) are held in both nouns (`PlanProblem`, both platforms): the card shows the course's, the model reads class, and a write refused for them tells the teacher in the course's noun (`AssistRefusal.ForTheTeacher` on Windows, `AssistToolOutcome.refused(_:showingTheTeacher:)` on the mac). The deploy-held-back, copy-not-made, not-a-numbered-page and add_classes refusals have club twins the same way. Mac VoiceOver names on the club's sheets say meeting. Mac `plan_remember_timetable` gives the card in the course's noun and both summaries say meeting (`workedOutTheClassDates`, `rememberedTheClassDates`). Windows' assistant dates card says the club's lines (`ClassDatesDialogWords.CouldNotOpen`, `NoneRecorded`, `Remembered`, and the mac's `datesNotGivenYet` for Not Now), and the Class Dates dialog names every date too far from today (`TimetableMemory.EveryUnbelievable`). Publish Pages…' sentence above the ticks says "as far as the next meeting" on both. Tests: mac `ClubNounTests` (`testEveryClassSentenceInTheContractHasAClubFormOrAReason`, `testTheRanFromAMenuCountsSayMeetingInAClub`, `testAPlanShortOfDatesSaysMeetingToAClubsTeacher`, `testTheDatesCardAndItsSummariesSayMeetingInAClub`, `testVoiceOverNamesSayMeetingInAClub`); Windows `ClubNounTests` (`EveryClassSentenceInTheContractHasAClubFormOrAReason`, `TheRanFromAMenuCountsSayMeetingInAClub`, `APlanShortOfDatesSaysMeetingToAClubsTeacher`, `TheDatesCardLinesSayMeetingAndTheRefusalNamesEveryDate`), `ContractTests` pairs for every new key.

#### Sentences still to do (issue #1031)

Searched: every string literal matching `\bclass(es)?\b` (any case) in `mac-app/QuartzTeachers` (453 lines) and in `windows-app/Plantoir`, `Plantoir.Core`, `Plantoir.Mcp` (501 lines), and every key of `contracts/assist-wording.json`. Marks: **A** has a club form already; **F** fixed in this round; **S** correctly stays class (why); **N** person-read in a club and NOT yet fixed (budget; one line each).

Contract wording (both platforms):
- A: every key with a `…ForAMeeting` twin before this round (classDates…, menu…, dates…, laterClasses…, madeRoom, wouldMakeRoom, pages…, reDated…, and the rest listed by the test), and `nothingToUndoFromTheMenu` / `sectionIsChangingFromTheMenu` (twins `…FromTheMeetingsMenu`).
- F: `addClassesNeedsAUnit`, `addClassesNeedsACount`, `menuPickPagesToPublish`, `notANumberedClassPage`, `thePlaceForTheCopyIsStillTaken` (+`NamingTheBackup`), `theCopyCouldNotBeMadeHidden` (+`NamingTheBackup`), `deployHasClassesDatedLater` (+`NamingSeveral`, `AndNoWindow`); new keys `addClassCountsNext`, `addClassCountsAsACopy`, `untickedAtDeployCounts`, `timetableTooShortFrom`, `timetableTooShortAfter`, `noDaysAfterTheLastPage`, `unusedDatesRunShort`, `pagesNotNamedTheCoursesWay`, `workedOutTheClassDates`, `rememberedTheClassDates`.
- S (on `staysClass`): `howITeachDraftingBrief`, `otherClassesMoved` (appended to a detail only: the model); `openEndedPublishRefused` (written to the model, names tool arguments); `menuAddClassGreyedRenameHoldsANewUnit`, `nextClassNeedsItsOwnPhrasing` (units; a club is numbered, and the numbered form takes the noun); the three `…InAModuleCourse` keys (module courses only).

Mac literals outside the contract:
- F: `SectionDetailVerbs` counts (both); `ClassInsertionPlanner` problems (four); `PlaceholderClassPlanner` problem; `AccessibilityNames.classDate`, `classDates`, `makeRoomClass`, `makeRoomHowMany`, `sourceTable`, `laterClassesTable`; `AssistToolRunner` remember_timetable summaries and card, timetable refusals' summaries (`SectionTimetableStore.Problem.sentence(noun:)`).
- A: `SubjectMenuLayout` titles; `StartOfYearWording` (lists filled by the noun); `AssistSupportingViews` prompt shelf (the club's own shelf); the wizard (`WizardWording.panelWords(isClub:)`).
- S: `AssistToolSurface` (tool descriptions: the model); `AssistContract` notes (contract text); `AssistCardCommand` and `AssistNextClassUnits` (phrasings matched in code, never said); enum raw values, file and folder names and JSON keys (`ActivityTrail` event names, `UndoFormat.actionClass`, `.later-classes-kept.json`, `classes-section`, `class-site`, `All Classes`/`All Prior Classes.md`/`Class Website` (a course's default and older-layout names), `TodaysClassOnTheFrontPage` JSON "class", `QuartzCheckoutLayout`/`ClassFolder`/`SpecialFolderRenamer` folder-name matching); "class website" as the product's name for any site it builds, said also where no course is chosen (`AboutView`, `CredentialRequest`, `QuitConfirmation`, `PlanSharing`, `ObsidianFigureAddOnsOffer`, `DeployTokenWording`, `ScheduledDeploy:3702`); `UnitWordRename*` and `ReferenceImportWording` (a course's unit word and course imports, not a club's meetings: not re-audited line by line).
- F (round 4): refusal summaries `ClassInsertionPlanner` count and no-dates, `PlaceholderClassPlanner` count and no-dates, `NextClassPlanner` no-dates, `SectionReDatePlanner` no-dates and no-pages, `AssistPublishPlan` no-class-on-a-day, `AssistToolRunner` "There is no class date left for another class." and "Which day should the new class take?".
- N: `AssistToolRunner`'s other literal refusals not yet walked one by one; card line `PlaceholderClassPlanner:316` ("Nothing to add — every class asked for…"); trail lines `ClassesDatedLater:336-357`, `TodaysClassOnTheFrontPage:368-376`, `PreviewStartPage:296`, `PagesDatedByTheBuild:67`, `SectionReDatePlanner:353-356`, `ClassInsertionPlanner:289,437`, `AssistToolRunner` "did not copy a class — …" (two) and "did not copy a class from the … menu", `AssistAgent:1506`; `CopyPageWording:149-194`; `OneSectionRestore:363,428`; `SpecialNames:40,43`, `SpecialFoldersHelpView:76`, `CourseSettingsView:170` "Class Pages", `CourseSettingsWording.printingBlankClassNumber`.

Windows literals outside the contract:
- F: `SectionVerbs.AddClassCounts`, `ClassesDatedLater.UntickedAtDeployCounts`, `AssistWorkspace` make-room problems (four) and the refusals named above, `SectionVerbDialog` pick sentence, `AssistWindow` dates-card lines (four), `ClassDatesDialogWords.CannotBeADate` (every date).
- A: `SubjectMenuLayout`, `StartOfYearSheet`/`StartOfYear` (noun), `AssistWording.Meetings/ClassDates/Menu/AddClass/LaterClasses/PlanTable` twins, `MainWindow.xaml` "Classes" (retitled live by `ApplyMenuEnablement`), `AssistPromptShelf` (club shelf).
- S: `PlantoirTools` and `McpInstructions` descriptions and tool results' text (the model; the teacher copies go through `_meta`); `LogDiagnostic` lines (the log, not a sentence on screen); `NewCourseDialog` "class"/"meeting" choice values; registry key `Software\Classes`; "class website" (`AboutDialog`, `CredentialRequests`, `QuitConfirmation`) as on the mac; `UnitWordRename*`, `LinksChecklistWording` as on the mac.
- F (round 4): `AssistWorkspace` make-room and add-classes count refusals, make-room, add-classes and next-class no-dates refusals, the copy-as-next-class no-date-left refusal (`ClassChangeWording.NoClassDateLeft` removed), `NextClassPlanner.Date`'s refusal, `PlantoirTools` re-date no-dates answer.
- N: `AssistWorkspace` refusals and messages that the menu's teacher copy carries unchanged (the remaining lines of `:661,674,887,1579-1594,2093,2201,2621,3048,3119,3200,3242-3243,3260,3288,3744,4482,4632,4652,4671`; line numbers as of round 3), progress lines `:4069,4147`, trail lines `:3160,4145,4176,4309,4337` and `AssistWorkspace.MenuDuplicate:132`, `ClassesDatedLater:179-203`, `DateAudit`, `ReDatePlan:77-129`, `NewClassesPlan:57-97`, `SyncPlan:42-43`, `PublishPlan:437`, `Timetable:245,313`, `MissingArguments` (add_classes' questions are said to both in one copy).

Must-fail record (round 3): mac `runs/1027-r3-mac-mustfail.log` (working-tree reverts, restored): a twin removed fails `testEveryClassSentenceInTheContractHasAClubFormOrAReason` (`notANumberedClassPage`); counts in class fail `testTheRanFromAMenuCountsSayMeetingInAClub`; a VoiceOver name in class fails `testVoiceOverNamesSayMeetingInAClub`; card problems and the refusal in class fail `testAPlanShortOfDatesSaysMeetingToAClubsTeacher` (lines 649-656); the summary in class fails `testTheDatesCardAndItsSummariesSayMeetingInAClub`. Windows: `runs/1027-r3-vm-turn1.log` did not build (a duplicate helper in the test); `turn2.log` (head 66d447f80) showed `APlanShortOfDatesSaysMeetingToAClubsTeacher` failing on the head, which found a real gap: `plan_make_room_for_classes` answered a plan that adds nothing in the class form to both copies; fixed (af0045924). `turn3.log` (head af0045924, scratch e9384a888 never pushed: a twin removed from the JSON, counts in class, `ProblemsIn` and `ForTheTeacher` reverted, `NoneRecorded` in class, `EveryUnbelievable` keeping the first date only) proves the four new facts both ways; it also showed the make-room write answering "Nothing needed moving." when the dates ran out, now refused with the reason as the mac does (fb650b1be). `turn4.log` (head 16577fe95, dev da5af161e merged): 360 of 360 across the own and source-reading classes.

Also fixed this round, from the director: `RemovalQuestionsContractTests.RemovingAScheduledDeploy_PutsUpNoDefaultButton` searched `MainWindow.Menus.cs` for a call the previous round changed. It now reads what it means: `SubjectMenuLayout.TitleHere(CancelScheduledDeploy, noun)` is the removal wording's menu item in both nouns, no club retitles it, and the menu bar draws by `TitleHere`. `ClassesDatedLaterAtDeployTests.TheHideIsCountedAsUntickedAtDeploy` reads the counts by the course's noun. Every Windows test class that reads a touched file as source ran in turns 2 and 3.

#### Round 4: the N sentences (writer 4)

the planners' refusals say meeting to a club's teacher on both platforms: nine new contract keys with twins (`askForAtLeastOneClass`, `cannotMoveClassesWithoutDates`, `cannotDateNewClassesWithoutDates`, `cannotDateANewClassWithoutDates`, `cannotReDateWithoutDates`, `noNumberedClassPagesToReDate`, `noClassOnThatDay`, `noClassDateLeftForTheCopy`, `whichDayShouldTheNewClassTake`). Mac: each planner `Problem` adopts `SaidInACoursesNoun` (`sentence(noun:)`; `errorDescription` is the class form, which the model reads), and `AssistToolRunner.refusalForTheTeacher` gives the teacher's copy at every plan and write refusal of the next class, make room, add classes, re-date and copy-as-next-class; `PlannedRoomOutcome.couldNot` carries the teacher's sentence. Windows: `AssistRefusal`'s `forTheTeacher` carries the course's form; Windows' make-room and add-classes no-dates refusals keep their own words for the model (what the model is told does not change); the teacher reads the mac's make-room sentence in the course's noun, and in a club add_classes' teacher copy is `cannotDateANewClassWithoutDatesForAMeeting`, whose question still offers the dates sheet: `AssistWindow` now offers it for either noun's question (it matched only the class form, so a club's next-class refusal offered no sheet). Tests: mac `ClubNounTests.testThePlannersRefusalsSayMeetingInAClub`, `testEveryClubTwinSaysMeetingAndNeverClass` (the guard's other half: a twin that still says class fails); Windows `ClubNounTests.ThePlannersRefusalsSayMeetingToAClubsTeacher` (through `plan_make_room_for_classes`, both copies), `EveryClubTwinSaysMeetingAndNeverClass`, `ContractTests` pairs for the nine keys.

Must-fail (round 4): mac `runs/1027-r4-mac-mustfail.log` (working-tree reverts, restored): the count refusal in class fails `testThePlannersRefusalsSayMeetingInAClub` (line 743), a twin saying class fails `testEveryClubTwinSaysMeetingAndNeverClass` (line 722). Windows `runs/1027-r4-vm-turn1.log` (scratch d0f10a16e, never pushed: the count refusal's noun reverted and one twin saying class) fails `ThePlannersRefusalsSayMeetingToAClubsTeacher` ("Ask for at least one class.") and `EveryClubTwinSaysMeetingAndNeverClass` (line 519); its head run found `NewClassesTests.WithoutATimetableItAsksForOneRatherThanGuessing` red, which showed the Windows add_classes refusal had lost its dates question (fixed in 8166c57f1). `runs/1027-r4-vm-turn2.log`: head 8166c57f1, 375 of 375 across the own and source-reading classes; scratch 3e090ce14 (make room's teacher copy in class) fails `ThePlannersRefusalsSayMeetingToAClubsTeacher`. The window's offer for either noun's question has no unit test (it is in `AssistWindow`'s exchange loop); not proven by a UI test this round.

Still N after round 4 (search re-run: string literals matching `\bclass(es)?\b` outside comments, 290 lines in `mac-app/QuartzTeachers`, 388 in the three Windows projects; the marks above updated): mac trail lines (`ClassesDatedLater` heldBack/asked/wentOut, `TodaysClassOnTheFrontPage` lines, `PreviewStartPage`, `PagesDatedByTheBuild`, `SectionReDatePlanner` undo line, `ClassInsertionPlanner` trail and page-settings lines, `AssistToolRunner` did-not-copy lines, `AssistAgent` chose-to-add line; most are `activityTrail.mustRecord` lines in `shared-rules.json`, so each needs a club line in the contract), `CopyPageWording` four (authored `shared-rules.json` copy-page keys; the source course's noun must reach `CopyPageChecklist` and `CopyPageResultView`), `OneSectionRestore` two, `SpecialNames`, `SpecialFoldersHelpView`, `CourseSettingsView` "Class Pages", `CourseSettingsWording.printingBlankClassNumber`, `AssistToolRunner`'s other literal refusals; Windows: the remaining `AssistWorkspace` lines above, progress lines, trail lines, `ClassesDatedLater`, `DateAudit`, `ReDatePlan`, `NewClassesPlan`, `SyncPlan`, `PublishPlan:437`, `Timetable:245,313`, `MissingArguments`, and the Windows copy-page wording.

#### Round 5: review 3 fixes (MEDIUMs 1 and 2, lows 5 and 11), Windows only

In a club, Publish Meeting for a Date…, Re-date Meetings… and Make Room for Meetings… now give the teacher the mac's line (`PublishedTheClassOnForAMeeting`; `ReDatedForAMeeting` / `ReDatedOnlyPagesTheyUseForAMeeting` through `AssistResult.ForTheTeacher`; `MadeRoomForAMeeting` plus what was left undone, never the counts sentence or `OtherClassesMoved`, which stay the model's, so `staysClass.otherClassesMoved` is true again with no contract change); Narrator names the dates box `ClassDatesDialogWords.DatesBoxName(noun)` ("Meeting dates"); `deploy_section` answers with the refusal's club form for the teacher; `RemovalQuestionsContractTests` again checks the Section menu's `Add(into, LayoutTitle(item, ClassNoun.Class), id, item);`. `ClubNounTests.EveryMeetingsItemsResultLineNeverSaysClassToAClubsTeacher` walks every Meetings item (and every Section item a club retitles) from `SubjectMenuLayout`. Proved on 355d4c6ed (dev 41f30f5c6 merged): 431 of 431 in the own and source-reading classes. Must-fail `vm-tools/runs/1027-r5-vm-turn2.log` (scratch 61c58df58, never pushed, all six fixes reverted): the five changed or new facts each fail, the walk naming Meeting Dates…'s box, Re-date and Make Room.

## 2026-11-21 — #954 Classes ▸ Roll Over to a New Year… on Windows

- **Classes ▸ Roll Over to a New Year…** (#954, the mac's #897 piece B), in the Classes menu (Meetings in a club) above Get Ready for the Start of the Year…, live exactly where Re-date Classes… is (`SubjectMenuRules`, no situation key of its own). Not on the section row's menu (`rollOverSheet.rejected`). Class dates first, with `datesToReDate`'s reason, as Re-date Classes….
- **Its dialog** (`SectionVerbDialog.ChooseHowToRollOver`, the mac's `rollOverChoosing`): the intro, the dates on file first to last ("2026-09-08 (Tuesday)"), the dates-are-old line when the last has passed (naming Classes ▸ Class Dates…, Meetings ▸ Meeting Dates… in a club), then the website: `rolloverWebsiteQuestion` over Start a new website / Keep last year's website, NOTHING chosen and Continue dimmed until one is; or, with no question, the line the website rule gives (`menuRollOverNotDeployedYet`, `menuRollOverDeploysToAFolder`, `menuRollOverANewWebsiteWouldReuseItsAddress`). Continue → the plan → Roll Over (`menuRollOverButton`) → the finished line. Cancel at the plan writes "cancelled at the plan".
- **The rule** (`RollOverFromTheMenu`): the three facts and `cloudflareAddressReuse`, 8 of 8 and 7 of 7 cases from the JSON (`RollOverFromTheMenuTests`). `sectionIsPinned` reads `AssistWorkspace.MarkersTheReleaseWalks`, the one list `ReleaseSite` now walks too (the legacy `.netlify_site.json` in the build root and in `.merged_output`). The "ReleaseSite returns after the first marker folder" debt #954 listed was already gone: it walks every folder.
- **The call** is `plan_re_date_classes` / `re_date_classes` with `rollover: "yes"` and `website` "new" or "same" (`SectionVerbs.RollOver`), so the tool code is the window's. On the menu's server only (`SpeaksFromTheMenu`): the plan's card adds the website line and `menuRollOverPlanSetsTheRecordAside`; with the dates already right a fresh copy of the course is saved first (`BackUpBeforeARolloverFromTheMenu`); with no copy, on either path, the rollover is refused with `startOfYearNeedsABackup` before anything is written; the finished lines are the `…FromTheMenu` ones (`finishedInPlaceOf`), and a "new" that would reuse a Cloudflare address is kept, never started. The window's rollover, its words and the tool surface are unchanged.
- **Trail:** "Classes ▸ Roll Over to a New Year… — <ending>, website: new|kept|not deployed yet|deploys to a folder|kept, a new one would have the same address"; the website lines from the menu say "kept deploying the section to its folder…", "kept the section's website… a new one would have had the same address", "…it was not on a website at the moment".
- **Wording:** the 20 keys, in `AssistWording.RollOver.cs` (noun forms in `RollOverWords`); the ledger's `rollOverToANewYear` item hold and its 20 wording holds (`Reason897RollOver`) are removed.
- **Not built (seams, by the night-3 settled list):** the ONE undo entry and `onlyTheHalvesMovedAway` #954's body describes are the old in-memory list's; the menu's rollover records what the window's path records (the re-date's entry with the published-pages record inside it, and `ReleaseSite`'s own "cut section N loose" entry; on the dates-already-right path `ReleasePublishedPagesForARollover`'s entry). The rollover as one journal step, with a stale Netlify record set aside inside it and the deploy set for later turned back on at undo, is Windows Undo W7's (from the mac's U3b). #957 and #960 (a custom address with a new website; a record from a host no longer used counted as none) reach Windows as contract cases from the mac.

## 2026-11-21 — #1035 and #953's deny test: the harness's key rules run in the merge gate; the permission test split

#### #1035: the harness's key rules run in the merge gate

- **#1035 (2026-11-21): `HarnessSourceRuleTests` moved from `Plantoir.UiTests` to `Plantoir.Tests`**, so the merge gate (which builds and runs `Plantoir.Tests` only; read from `C:\vm-setup\win-suite-int-d4.ps1`) now runs the key rules. On `dev` 41f30f5c6 two of them had been failing unseen: `StopByKeyboardUiTests.AHeldEscapeOpensTheQuestion_AndItsRepeatsDoNotAnswerIt` sent a bare key-down Escape (#1009), and `MenuBarUiTests.CopyAPageAnswersCtrlShiftK` named `KEY_K`, not watched (#990).
- The rule tests read the UI test sources from `windows-app/Plantoir.UiTests` and the watched keys from `HeldKeys.cs`'s own `Watched` array, so there is one copy of each. `Plantoir.Tests` is plain `net9.0` and cannot load FlaUI, so keys are compared by NAME: the three `VirtualKeyShort.ENTER` in the UI tests are now `RETURN` (the same key, 0x0D), the spelling `Watched` uses. A new test file `TheWatchedListIsReadFromHeldKeys` pins that the list is really read.
- The held-key imitation (several key-downs, one key-up) is now one helper, `HeldKeys.HoldWithRepeats(key, firstDelayMs, repeats, repeatMs, whileHeld)`, with its release in a `finally`; it is the one method on the rule's allowed list (it replaces `PageTablesUiTests.HeldSpace` there, which now calls it). `StopByKeyboardUiTests`' held Escape calls it too, so a failing step can no longer leave Escape down. `KEY_K` is in `HeldKeys.Watched`.
- `TheHeldKeyMessageNamesTheTestsAndTheFix` stays in the UI project, in `HeldKeysMessageTests.cs` (it tests `HeldKeys` itself, not the sources).
- Proved on VM B (see the must-fail lines below).

Must-fail (scratch commit db41c4f50, never pushed: `KEY_K` taken out of `Watched`, a bare `Keyboard.Press(VirtualKeyShort.ESCAPE)` put back in `StopByKeyboardUiTests`, the helper's `finally` turned into a `catch`):

```text wrap
VM B, fixed 4352d97a7: HarnessSourceRuleTests (Plantoir.Tests, run-tests.ps1 -Filter) Passed 5 of 5.
VM B, fixed 4352d97a7: StopByKeyboardUiTests + MenuBarUiTests + PageTablesUiTests + HeldKeysMessageTests: PASSED - 18 passed, 0 skipped, 18 total (10 m 54 s).
VM B, broken db41c4f50: Failed 3, Passed 2:
Failed Plantoir.Tests.HarnessSourceRuleTests.EveryKeyATestNamesIsWatched: HeldKeys.Watched does not watch these keys a test names (add the key there, spelled the same way): KEY_K (MenuBarUiTests.cs:478)
Failed Plantoir.Tests.HarnessSourceRuleTests.NoTestSendsAKeyDownWithNoKeyUp: These send a key DOWN and never UP ... StopByKeyboardUiTests.cs:424 (in AHeldEscapeOpensTheQuestion_AndItsRepeatsDoNotAnswerIt)
Failed Plantoir.Tests.HarnessSourceRuleTests.TheAllowedMethodStillReleasesItsKey: Assert.Contains() Failure: Not found: "finally { Keyboard.Release("
```

Logs: `vm-tools/runs/1035/prove.log`, `vm-tools/runs/1035/prove-ui.log`.

#### #953's permission test split, so the merge gate's PC run is honest

- **#953's permission test split so the merge gate's PC run is honest.** `AgentGuidanceTests.APermissionIsRefusedAtOnceAndNotSaidAsInUse` failed on the PC over SSH (`Assert.Equal() Failure: Expected: "Access is denied." Actual: null`). Measured on the PC over SSH (2026-11-21, a PowerShell probe sent over SSH, calling `MoveFileEx` with replace in `%TEMP%`): the account is elevated with `SeBackupPrivilege`, `SeRestorePrivilege` and `SeTakeOwnershipPrivilege` enabled. A read-only target refuses the rename (error 5), but the file's deny rule (Delete and WriteData), the folder's deny rule (DeleteSubdirectoriesAndFiles) and both together all let the rename through (0), and so does a write in place. The listing probe of `DenyBitesFact` reads "does not bite" there too, so it would have skipped the test, but only by luck: it probes listing, not replacing.
- The test is now two. `AReadOnlyFileIsRefusedAtOnceAndNotSaidAsInUse` is a plain `[Fact]` that runs everywhere and now also checks that no temporary is left. `ADenyRuleIsRefusedAtOnceAndSaidAsAccessDenied` is a `[DenyReplaceBitesFact]`. That new attribute sits beside the test in `AgentGuidanceTests.cs`, the way `DenyReadBitesFact` sits in `UndoCheckContractTests.cs`. Its probe applies the test's own two rules (shared through `FileDeny()` and `FolderDeny()`) to a temporary file and makes the same `File.Move(…, overwrite: true)`. Where the rename goes through, the test is skipped with a sentence that says why and names the tests that cover the rest. No assertion was weakened.
- Proof: on the PC over SSH (`953-deny-p1`, head 4567ce847), both builds passed and `AgentGuidanceTests` had 22 passed, 1 skipped (the deny half, with its reason) and 0 failed. On VM B (same head), 23 of 23 passed, the deny half among them. Must-fail on VM B (scratch 7307a036f, `HeldFiles.Replace` asks again after every access-denied rename, the pre-#953 behaviour): both halves fail, the read-only one at line 556 (`Assert.NotEqual() Failure: Strings are equal`, said as in use) and the deny one at line 590 (`Assert.Equal() Failure: Strings differ`).
- What the PC can tell us about deny rules is still limited: over SSH the deny-rule tests cannot run there. The VMs are where they run (whether they bite in the PC's desktop session was not measured).

## 2026-11-21 — Lane F, Windows test reliability: #971, #964, #916 items 3 and 4, #770

Branch `issue/770-win-test-reliability`. Issues #971, #964, #916 items 3 and 4, #770. All runs in the second Windows VM (B, Windows 11 ARM64, account `russellgordon`); logs on the main Mac under `vm-tools/runs/night4-f/`, the per-run test output in the VM under `C:\vm-setup\770f\`. Guest scripts `vm-tools/guest/770f-run.ps1` (named filter sets, repeats, hang bound, own TEMP, CPU spinners), `770f-build-ui.ps1`, `770f-cat.ps1`, `964-hang.ps1`.

#### #971: four door tests that failed only in the VMs

- **Pair A (`OutsideDoorRefusalTests.ALongNameIsCutInThePlainGreeting_AndTheDoorOpens`, `OutsideGreetingOpenTests.OpenReadsTheShelfAtTheClick`).** `ClaudeCodeLauncher.FindServer()` looked for `plantoir-mcp.exe` only beside `Environment.ProcessPath`, which under the Windows ARM test host is `C:\Program Files\dotnet\dotnet.exe`. It now searches two roots, the process folder and `AppContext.BaseDirectory`, each with the existing walk-up and nothing wider; in the installed app they are one folder. The search is `FindServer(processFolder, baseFolder)`, so `ServerLookupRootsTests` gives it a process folder without the server and a base folder with it on any machine, plus the installed case (`Plantoir.exe` and `plantoir-mcp.exe` side by side, with and without a trailing separator), process-only, neither, and the dev walk-up from a test `bin` folder. `LocalModel.FindServer` had the same shape and is decided the same way (same two roots via `ClaudeCodeLauncher.DistinctRoots`, then PATH as before), with two cases of its own.
- **Pair B (`OutsideDoorTests.FixWithDropsRowsToTheShimsRealBound`, `…TheLongestShimLineAllowedArrivesWhole_AndOneMoreIsRefused`).** The deep shim folder was 180 characters below `%TEMP%`, so the account name decided the stub `node.exe`'s path length (257 under `russellgordon`, over the 252 the .NET Framework 4.8 stub starts from). The folder is now exactly `DeepShimFolderLength` = 240 characters (the length `ShimExpansionAllowance` was measured from), padded from a run-owned scratch root (`RunOwnedTempFolders.Create("plantoir-door-")`), and `StubShimIn` asserts the stub's path is within `StubStartsFromAtMost` = 252 with the reason in the constant's comment. No product change.
- **Before** (`origin/dev` da5af161e, VM B, run `base-doors`): filter `FullyQualifiedName~OutsideDoor|FullyQualifiedName~OutsideGreetingOpen`, **4 failed of 91** (the four above: "nothing arrived" twice, "Claude's door did not open" twice). Log `runs/night4-f/base-doors.log`.
- **After** (branch 43fa8b150, VM B): **0 failed of 91, 10 runs in a row** (run `br4-doors`, 45 to 68 s each); after merging `origin/dev` (c16f6cc89) the lane's whole filter, 227 tests, passed (run `fin1-lane`). TEMP and TMP 40 characters longer than the default (`C:\Users\russellgordon\AppData\Local\Temp\plantoir-971-a-temp-forty-longer-0123456`, 81 characters, made and removed by the run, 20-minute hang bound): pair B's class **84 of 84 passed** (run `br4-longtemp`, 46 s; TEMP removed afterwards). Must-fail (scratch branch `scratch/770f-mustfail`, not pushed for merge): with the base folder ignored, `TheToolsServerIsFoundBesideTheBaseFolderWhenTheProcessIsTheDotnetHost` fails ("No tools server was found although one sits in the base folder …", line 52) and `TheLocalAssistantsServerIsFoundBesideTheBaseFolder…` fails (expected the path, actual null, line 107); with `DeepShimFolderLength` 250, `FixWithDropsRowsToTheShimsRealBound` fails at `StubShimIn` ("the stub node.exe's path is 259 characters, over the 252 it can start from", line 289), run `mf1`. Log `runs/night4-f/br4.log`.

#### #964: CopyAPageFuzzTests hung where it should fail

- `oracle.py` imports `build_site` and `frontmatter` in the parent before it makes the pool, and exits naming the package (`python -m pip install python-frontmatter`). `BuildFrontmatterOracle.Ask` reads both streams in the background (a pool's workers inherit them, so reading stderr to its end waited on the workers, not the parent) and takes an optional hang bound, used only by the new test.
- `BuildFrontmatterOracleTests.APythonWithoutFrontmatterFailsByItselfNamingThePackage` makes the missing package on demand: a run-owned folder on `PYTHONPATH` whose `sitecustomize.py` puts a finder at the front of `sys.meta_path` that refuses `frontmatter`, in the parent and every spawned worker. It reads that the oracle exited by itself with "No module named 'frontmatter'" and "python-frontmatter". The 5-minute bound only turns the old hang into a failure.
- **Hang shown on `origin/dev`:** `vm-tools/guest/964-hang.ps1` runs da5af161e's own `oracle.py` with the same refusing `sitecustomize.py` (run `mf1`, 01:03): 15 s apart the `--multiprocessing-fork` children were 6328,12128, then 1240,11372,672,6136, then 10984,10676,9212,10852 (recreated), the parent never exited, stderr had 755 "No module named 'frontmatter'" in 45 s; the tree was ended by hand, `taskkill /T /F /PID 2680`. Must-fail on the branch's test with the parent import removed: `Assert.Throws() Failure … Actual: typeof(System.TimeoutException) … had not exited after 00:05:00: it hung (#964)` (run `mf1`). After: the test passes in every lane run (`br4-lane`, `fin1-lane`).
- CLAUDE.md ("Setting up on a new machine", Windows app) and WINDOWS-BOOTSTRAP.md section 6 now name `python-frontmatter` for PATH's Python and Developer Mode (or the symbolic-link privilege another way, WinError 1314). Claude Code's CLI on PATH: **not written**: in the second VM `where claude` finds nothing, and with #971 fixed the three door classes pass there (91 of 91, ten times), so Claude Code's CLI is not a prerequisite of the suite and the issue's third item was the pair A fault.

#### #916 items 3 and 4: two shared temp paths

- **Item 3.** `TestAppDataRedirect.ScratchRoot` is `%TEMP%\plantoir-tests-<pid>-<start ticks>` (`RunOwnedTempFolders.OwnerTag`), removed at process exit (`AppDomain.ProcessExit`), with no sweep of any other folder. `TwoRunsWithOneProcessIdAndDifferentStartsGetTwoFolders` gives two runs one process id and two start times and gets two folders; `ThisRunsFoldersCarryItsProcessIdAndStartTime` pins the live names.
- **Item 4.** `TestTrailRedirect.ScratchTrailPath` is `%TEMP%\plantoir-tests-trail-<pid>-<start ticks>\activity.txt`, removed with the settings folder. Its many users (they only restore it) are unchanged.
- **Before** (`origin/dev`, run `base-doors`): `%TEMP%` held `plantoir-tests`, `plantoir-tests-9364`; after the filtered run it also held `plantoir-tests-1052`, that run's own, left behind.
- **After** (branch, runs `br2`, `br4-doors` and `fin1-lane`): the listing before and after every run is the same three entries (`plantoir-tests`, `plantoir-tests-1052`, `plantoir-tests-9364`, none of them this branch's): no `plantoir-tests-<pid>-<ticks>` and no `plantoir-tests-trail-…` left behind. The shared `plantoir-tests\activity.txt` was last written 16:06:32 (an older run) and not touched since.
- **#916 items 3 and 4 are done, and #916 can close** (items 1 and 2 merged 2026-11-19 at 4e7c1d84d). For the director: old `plantoir-tests-<pid>` folders on a machine (1,603 on the PC in November) are not this code's to sweep; delete them by hand once if wanted.

#### #770

- **Item 3, `ObsidianFigureAddOnsTests.ASecondPassChangesNoByteAndWritesNoLine`.** History (`git log -L`): the `< 5000` ms check on the FIRST pass came in with the test itself, 6252bf239 (#581, 2026-10-22), with no reason recorded; documentation 12 measured that pass at 74 ms (second pass 87 ms), and #770 saw 9,258 ms on a loaded PC. It held nothing the name says (no byte, no date, no line on the second pass). What the first pass is for is now checked instead: every pinned file at `.obsidian\plugins\<id>\<name>` has the pinned length and SHA-256. The `< 3000` ms in `TwoThousandPagesAreScannedQuickly` is a declared performance test and is the one wall-clock bound left in the class. Fail on demand on `origin/dev`: **not shown.** Run alone on da5af161e: passed idle (`dev-idle`), and passed 2 of 2 with the test host pinned to one core shared with three spinning processes (`dev-load`, `-Affinity 1 -Spinners 3`); a first attempt with twelve spinners at High priority starved the whole VM and was stopped (the VM was restarted). The must-fail for the new check does bite: with the add-on's first file written one byte short, the test fails at the new length check, "Expected: 7861284 Actual: 7861283", line 147 (run `mf2`). Under invariant 3 the old failure's cause is not shown on demand, so **item 3 stays open** even though the wall-clock bound is gone.
- **Item 2, `NativeFiguresTests.ABuildWithADiagram…`.** The test's own wait is the `Run` helper's `WaitForExit(600_000)` on the build's exit; no 5 s is in the test. Not run: no time left after item 3. The 5 s in the issue is not a wait in the test (its `Run` helper waits up to 600 s for the build's exit), so it is the time the build took to FAIL, or a wait inside the build (`scripts/figures.py` has `process.wait(timeout=5)` when it stops the drawing engine, lines 381, 392, 417); which one is not found. **Item 2 stays open**; if it is `figures.py`, it is outside this lane.
- **Item 1, `AcceleratorUnderDialogUiTests`.** Not run (stopping rule). **Item 1 stays open**; nothing recorded beyond the issue.
- **The `UpdateInstallQuitUiTests` message.** Every failure's evidence now ends with each running `plantoir-mcp.exe`, its process id and path (`ToolsServersRunning`). With a copy of `plantoir-mcp.exe` running from `C:\vm-setup\stray-mcp` (pid 1812, serving a folder of its own), both tests failed "the installer was never started" (run `fin3`, c16f6cc89), which shows the hold; the last lines of the message, where the new list is printed, were cut by the runner (`770f-ui.ps1` prints 14 lines per failure) and the VM was parked before the full log was read, so **the new lines themselves were not seen**. Without the stray copy both pass (runs `fin1-update`, `fin2-update`). To see it: the same run with the whole message printed.
- Items done: none. The `UpdateInstallQuitUiTests` message's new lines were never seen in a run, so it is not counted as done. Items 1, 2 and 3 stay open, so **#770 does not close**.

#### Last item: the two other VM-only failures

Written as a new issue, **#1034** (v2.0.0). (1) `PublishAndLauncherContractTests.EveryQuestionTheMacDeployLauncherAsksIsGuardedAtTheTopLevel` is not a machine fault: "line 1472 is inside run_token_mode() … does not start with assert_can_ask" (run `dev-1899`); `deploy.sh`'s `read -rsp "Paste the token: "` behind `[[ -t 0 ]]` came in with 72355843d (#696, 2026-11-13), and `File.ReadAllLines` reads CRLF and LF alike, so it should fail everywhere since then; the fix is in `deploy.sh` or the test's rule, not this lane. (2) `scripts/test_deploy_sh_destination.py` alone: 22 failures, 3 skipped, on PATH's and on the runtime's Python; first failing case answers `UNREADABLE` where two `REFUSED` lines are expected. Ruled out: `deploy.sh`'s CRLF in the VM's checkout (`core.autocrlf=true`; rewritten with LF, still 22 failures, run `fin2`). Seen: no `bash` on the VM's PATH. Cause not found.

#### For the machines skill

On the branch in the second VM: the four #971 door tests now pass (91 of 91, ten runs; pair B also with TEMP 40 characters longer). `PublishAndLauncherContractTests.EveryQuestionTheMacDeployLauncherAsksIsGuardedAtTheTopLevel` still fails, and is not VM-only: a `deploy.sh` content fault since 72355843d (#1034). `test_deploy_sh_destination.py` still fails in the VM, cause not found; not the checkout's CRLF (#1034). Also for the skill: a reviewer's `park` returns B to snapshot 02 (checkout ce8e7bc1a), so every lock session must `sync` and `refetch-runtime.ps1` again; twelve spinning processes at High priority froze B until a `prlctl restart`. Not mine but seen: after merging `origin/dev` c16f6cc89, `HarnessSourceRuleTests` fails twice (a key down with no key up, lines 424 and 429 of `StopByKeyboardUiTests.cs`; and the `KEY_K` rule, which fails at `MenuBarUiTests.cs:478`). Both `HarnessSourceRuleTests` failures are on `dev` and are issue #1035; this branch does not touch them

## 2026-11-21 — Lane G, a file another program holds for a moment: #953, #874

Branch `issue/874-win-held-files`. Windows only; nothing under `mac-app/`, `contracts/` or `scripts/` changed.

#### #953 (a write by rename refused silently)

- New `Plantoir.Core/Models/HeldFiles.cs`: ONE bounded retry (`Pauses` 50, 100, 200, 400 ms, about 0.75 s, the shape `ObsidianFigureAddOns.Retrying` already uses, #1016 row 45), a delete-access probe (`IsHeld`), a three-way read (`ReadBytes`: Read, NotThere, CouldNotReadNow), `TemporaryBeside` (hidden, unique, `.tmp`) and `FileInUseException` (message `HeldFiles.InUseSentence`, HResult the sharing violation). The pause is a parameter; `PausingWith` sets a test's pause for its own async flow only.
- `AgentGuidance.WriteAtomically` renames through `HeldFiles.Replace`; still held after the bound it throws `FileInUseException`, the file unchanged and its temporary removed. `SystemReason` then gives the system's sentence for a sharing violation ("The process cannot access the file because it is being used by another process."), not "Access is denied.".
- `LastViewedPages.Load` and `AgentGuidanceDeclined.Load` read three ways. After "could not read just now": `PageFor` and `SignatureFor` answer null; `Remember`, `Forget` write nothing and answer false. `AgentGuidanceDeclined.Remember` and `Forget` now return whether they wrote (`ToolchainReadiness` passes `Forget` through a lambda; `Answer` otherwise unchanged).
- A file that is there but not valid JSON keeps today's behaviour: it reads as nothing remembered and is replaced on the next write.
- Owed items: the bounded retry in `WriteAtomically` DONE; `Load` telling "could not read" from "empty" DONE (both files); the root-file write and `AppendAfterYes` report as before through `ApplyGuidance`, now with the true reason, DONE. The other renames: surveyed below, none changed (next piece of #953).
- Not done: a trail line for a refused save of the app's own records (parked as a question for Russell: no `mustRecord` event says it truly).

#### #874 (the app's readers and writer of course_config.json)

- `CourseConfiguration.ReadBytes(path)` is the one reader of the file's bytes (through `HeldFiles.ReadBytes`). `Load` throws `FileNotFoundException` (not there), `FileInUseException` (held past the bound) or a JSON / `InvalidDataException` (not valid JSON).
- `Write`: a held merge read REFUSES the Save (`FileInUseException`, message "course_config.json is in use by another program, so it was not changed."); not valid JSON keeps the whole-object write. The fixed `path + ".tmp"` became a hidden temporary of its own (`ReplaceWith`), removed on every failure; the rename asks again; still held, it throws the same sentence with the file unchanged. `RecordOnDisk` reads through the one reader and replaces through `ReplaceWith`; its three-tries compare-and-swap is unchanged in meaning.
- `RevertToFile` now returns bool: false on a held file, the window's copy (edits included) kept; `CourseSettingsExclusions.Revert` returns false then and writes no `exclusions reverted` line. `ReferenceCourseUpkeep.SetSchoolYear` discards its own year change when the revert is refused, as it did before. `RereadIfNothingUnsaved` answers false on a held file without touching the copy.
- `Workspace.DiscoverCourses(path)` keeps this run's LAST GOOD READ of every `course_config.json` (by full path, in Core), and a course whose settings could not be read just now is listed with those settings. Round 1 passed the caller's list as `previous`, and `WorkspaceViewModel.Reload` had cleared it first (review 1, H1), so the course vanished on every reload; the memory now lives in discovery, so the reload, the assistant's lists and every door hold the same answer and no caller can hand over the wrong list. On a folder's FIRST read in a run there is no earlier read, and a course refused past the bound is not listed until the next read (showing it with no settings would need a "not read" course through every view).
- The reference doors FAIL CLOSED (review 1, low 3): `Workspace.CourseIsKeptForReference(folder, code)` (now used by `MainWindow.Verbs.cs` and `AssistWindow.xaml.cs`) and `ReferenceCourse.KeptOnDisk` answer, for settings that could not be read just now, as this run last read them, and with no earlier read, as kept. Known limit: a never-read ordinary course refused for the bound is then refused at Deploy with the reference sentence ("… is kept for reference …"), which is untrue for that moment; the MCP gate's "cannot tell" sentence would be truer, but `KeptOnDisk`'s callers include `SectionDetailView.xaml.cs` (lane D's tonight) and take only a code.
- Every reader treats ACCESS DENIED on a file that is there as "cannot tell now" (review 1, H2): asked again for the same bound, then "could not read just now"; after the bound, the probe decides the words: held, `HeldFiles.InUseSentence`; not held, `HeldFiles.NotReadSentence` ("course_config.json could not be read, so it was not changed. Windows said: Access is denied."). Any other IO refusal of a file that is there is "could not read just now" at once, in the system's words. `HeldFiles.ReadBytes` no longer throws for a file that is there; `Write`'s `catch { read = NotThere }`, `RevertToFile`'s `catch { DiscardChanges() }` and `RecordOnDisk`'s `catch (IOException) { unchanged }` are gone (`RecordOnDisk` still counts a file that has GONE since its first read as unchanged, as before). A Save merges or refuses; it never writes the window's whole copy over a file it could not read.
- Revert on a file that could not be read says so in the Settings window's status line, where a Save's failure shows (review 1, low 2): "course_config.json is in use by another program, so nothing was reverted." (or "… could not be read, so nothing was reverted. Windows said: …"), red, and the form keeps the edits (`CourseConfiguration.RevertToFile(path, out notReverted)`, `CourseSettingsExclusions.Revert(…, out notReverted)`).
- Temporaries (review 1, low 5): `course_config.json`'s and the guidance writer's temporaries are `HeldFiles.TemporaryBeside` (leading dot, unique, `.tmp`) and carry Windows' Hidden attribute while they exist (`HeldFiles.Hide`; the Hidden temporary is renamed onto the real file and `Unhide` runs after the rename, so a kill between the two can leave the settings file Hidden until the next write by the app or a build). Every failure removes the temporary. A kill between write and rename still leaves one (the app has no sweep; the build's `_remove_stale_config_temporaries`, prefix `.course_config.`, older than 60 s, does remove it).
- `ScheduledRun`'s course read went from `File.ReadAllBytes` to `CourseConfiguration.Load`. Every other listed reader already called `Load` and now asks again: `SavedSettings.Read` (refuses with its "could not be read just now" sentence), `DeployedFolderOffer.LookUp` (absent), `ReferenceCourse.KeptOnDisk` (fails closed since round 2, see below), `ReferenceImport.Measure` (settings could not be read), `ReferenceCopier.MakeIntoAReferenceCourse` (the exception goes up, with the sentence), `CoursePageCopy` (falls back to the window's sections), `Plantoir.Mcp/ReferenceWriteGate` (refuses as cannot tell).
- `CourseRestorer.cs:173` (restore's `Load`) is left for the restore batch (#873, #805, #911); it gets the retry through `Load` already and was not otherwise read for behaviour.
- `CourseSettingsView.xaml.cs`'s Save before-read now uses `CourseConfiguration.Load` (round 2; the view was opened for Revert's sentence anyway), so the source-text test excepts only `CourseRestorer.cs`.
- #874's "left" list: the C# readers retry and never take a hold as "no settings" DONE; the access-denied open during a build's replace DONE (every access denied on a file that is there is asked again, then refused truly; proved against a real second process replacing the file in a loop with `MoveFileExW(…, MOVEFILE_REPLACE_EXISTING)`, `CourseSettingsHeldFileTests.ABuildReplacingTheSettingsInALoopNeverLosesTheCourseOrItsChange`); the app's writes against a build reading DONE (a reader with `FileShare.Read` in a second process, refused past the bound, landing when released); every Windows C# reader asks again DONE.

### Every place that shows the sentence

The sentence is `HeldFiles.InUseSentence(name)` = "{name} is in use by another program, so it was not changed." ("it" is the file; "nothing was changed" was rejected because after a folder rename something HAS changed.) Where a `FileInUseException` from these calls reaches words:

- `CourseSettingsView.xaml.cs` Save: status line "Could not save: course_config.json is in use by another program, so it was not changed."; trail `settings could not be saved` "could not save the settings for ICS3U — course_config.json is in use by another program, so it was not changed."
- `CourseSettingsView.xaml.cs` folder rename (RecordOnDisk): "“Tasks” was renamed to “Assignments”, but Plantoir could not write the change to this course's settings: course_config.json is in use by another program, so it was not changed." The folder HAS moved, which is why the sentence says the FILE "was not changed" rather than "nothing was changed": it must read truly after every caller's lead-in.
- `UnitWordRenamer` (RecordOnDisk): `UnitWordRenameWording.SettingsNotWritten(to, message)`.
- `CourseRenamer.cs:105`: "The course's settings could not be saved: course_config.json is in use by another program, so it was not changed."
- `ReferenceCopier.MakeIntoAReferenceCourse` (Load and Write): the exception goes to its caller's existing message path.
- `CourseArchiver.cs:276`, `SectionAdder.cs:90`: the exception goes to their callers as before, with the new message instead of .NET's.
- The guidance notice: `couldNotWrite` with "The process cannot access the file because it is being used by another process" (the system's words, as the contract says); trail line "…first: AGENTS.md: The process cannot access…".
- `Revert` in Course Settings: the status line shows "course_config.json is in use by another program, so nothing was reverted." (or the not-read form); the window keeps its edits.
- A read refused by a rule (not a hold), after the bound: "course_config.json could not be read, so it was not changed. Windows said: Access is denied." after "Could not save: " and on the trail; the folder rename's lead-in reads "… could not write the change to this course's settings: course_config.json could not be read, so it was not changed. Windows said: Access is denied." (true: the folder moved, the file did not).

### The rename survey (#953)

Every other `File.Move(…, overwrite: true)` in `Plantoir.Core` and `Plantoir` outside `Undo/` and `CourseRestorer.cs`:

| Place | File it writes | Who else may hold it | Asks again | A refusal |
|---|---|---|---|---|
| `LaterClassesKept.cs:94` | the later-classes record in the course's `.internal` | a scanner, another window | no | `return false` (caller told, teacher not) |
| `LinksChecklist.cs:317` | moves a fragment back into the checklist record | a scanner | no | throws to the undo's caller |
| `ScheduledPublishOutcome.cs:279` | a scheduled run's outcome record | the window's watcher reading it | no | caught, temporary removed, swallowed |
| `ScheduledPublishOutcome.cs:793-794` | sweeps outcome records | the watcher | no | swallowed ("left for the next sweep") |
| `TaskScheduling.cs:52` | puts the kept job file back | Task Scheduler | no | swallowed |
| `ReferenceCopier.cs:197` | `.obsidian/app.json` (fixed `.tmp`) | OBSIDIAN, which the teacher has open | no | `return false` |
| `ReferenceStaging.cs:166` | a staging lease | another window | no | swallowed (in-app set still holds) |
| `SectionPublishState.cs:402` | a section's publish state | a build, the watcher | no | `return false` |
| `ToolchainMirror.cs:361` | `.toolchain/` files | a running launcher, a scanner | no | throws (counted as Failed) |
| `ToolchainReadiness.cs:713` | the readiness marker | a scanner | its own marker retry elsewhere | `(null, null)` |
| `ProblemsAcknowledgements.cs:117` | acknowledgements | a scanner | yes, `Patiently` (IOException only) | swallowed |
| `ObsidianFigureAddOns.cs:487` | the add-ons' files | Obsidian | yes, `Retrying` | reported (couldNotWrite) |

None was changed tonight. The next piece of #953: `ReferenceCopier.cs:197` first (a file a teacher's Obsidian holds, with a fixed `.tmp`), then `SectionPublishState` and `LaterClassesKept`. Shapes that should fold onto `HeldFiles` then: `ObsidianFigureAddOns.Retrying`, `ProblemsAcknowledgements.Patiently`, `ToolchainReadiness`'s marker retry and `UndoJournal`'s.

### Where this meets the Undo door

`UndoWriterScanTests` lists `AgentGuidance.cs` and `CourseConfiguration.cs` as `waitsFor: W8` (the Windows mirror of the mac's U4: settings, renames, New Course). When W8 routes those writes through `UndoDoor`, the door's staged swap and its `fileIsInUse` refusal take over the final rename. At that point the door should use this lane's held-file test (`HeldFiles.IsHeld`, the delete-access probe, and `HeldFiles.Replace`'s bound), or the two become one in whichever place the door's owner chooses; and the teacher's sentence for a held settings file (`HeldFiles.InUseSentence`) and the door's "is in use by another program" must stay the same words. Nothing tonight calls into `Undo/`, and the merge, the per-key rule and the trail lines stay where they were. Counts changed in `UndoWriterScanTests`: `CourseConfiguration.cs` 6 → 5 (the two writes now share `ReplaceWith`, which adds the temporary's removal), `HeldFiles.cs` new at 3 (the probe opens for delete access; `Hide` and `Unhide` set the Hidden attribute of a caller's own temporary).

### Must-fail lines

Each behaviour reverted in a scratch branch (`scratch/874-mf-*`, deleted after), the four classes (`HeldFilesTests`, `CourseSettingsHeldFileTests`, `AgentGuidanceTests`, `LastViewedPagesTests`) run on the first VM, Debug, tests-only build. Real branch: 45 of 45 passed before and after.

| Reverted | Failing test, line, assertion as printed |
|---|---|
| A: `LastViewedPages.Load` takes a refused read as empty | `LastViewedPagesTests.ARefusedReadNeverReplacesTheListWithOneEntry`, PreviewStartPageTests.cs:252, `Assert.False() Failure Expected: False Actual: True` |
| B: `AgentGuidanceDeclined.Load` takes a refused read as empty | `AgentGuidanceTests.NotNowAnswersAreNeverReplacedByOneAndARefusedWriteSaysSo`, AgentGuidanceTests.cs:484, `Assert.False() Failure Expected: False Actual: True` |
| C: `Write` takes a refused merge read as "unreadable" (whole-object write) | `CourseSettingsHeldFileTests.ASaveWhoseMergeReadWasRefusedNeverWritesTheWholeCopy`, CourseSettingsHeldFileTests.cs:133, `Assert.Throws() Failure: No exception was thrown` |
| K: a file that is not valid JSON refuses instead of the whole write | `AFileThatIsNotValidJsonStillTakesTheWholeCopy`, :189 (the thrown `InvalidDataException`) |
| I: `ReplaceWith` no longer removes its temporary | `HeldByAReaderTheRenameIsRefusedPastTheBoundAndTheFileIsUnchanged`, :153 and `HeldWhole…`, :112, `Assert.Empty() Failure: Collection was not empty` |
| H: `ScheduledRun` reads with `File.ReadAllBytes(config)` again | `EveryReaderOfTheSettingsGoesThroughTheOneReader`, :232 (`Assert.True` with the file named) |
| D: the probe never sees a hold | `HeldFilesTests.ARenameOntoAHeldFile…`, HeldFilesTests.cs:49, `Expected: FileInUseException Actual: UnauthorizedAccessException`; `TheProbeSees…`, :87; `AHoldThatEnds…`, :64; `LastViewedPagesTests.ARememberRefused…`, :218 `Expected [50, 100, 200, 400] Actual []`; `AgentGuidanceTests.AddOntoAHeldFile…`, :518 `Expected "The process cannot access the file…" Actual "Access is denied."`; `NotNowAnswers…`, :489; `CourseSettingsHeldFileTests.AReaderThatLetsGo…`, :170; `HeldByAReader…`, :148 |
| F: `RevertToFile` discards the edits on a held file | `HeldWhole…`, CourseSettingsHeldFileTests.cs:100, `Assert.False() Failure Expected: False Actual: True` |
| E: `FileInUseException` without the sharing-violation code | `ARenameOntoAHeldFile…`, HeldFilesTests.cs:51 `Expected: -2147024864 Actual: -2146232800`; `AddOntoAHeldFile…`, AgentGuidanceTests.cs:518 `Actual: "could not be written"` |
| G: `DiscoverCourses` drops a held course | `HeldWhole…`, :106, `Assert.Single() Failure: The collection was empty` |
| J: every access-denied rename asked again (no probe) | `AReadOnlyFileIsAPermission…`, HeldFilesTests.cs:76 `Value is the exact type FileInUseException`; `AgentGuidanceTests.AReadOnlyFileIsRefusedAtOnceAndNotSaidAsInUse` (then one test, `APermissionIsRefusedAtOnce…`; since #953 two, with `ADenyRuleIsRefusedAtOnceAndSaidAsAccessDenied`, skipped where a deny rule cannot stop a rename, as over SSH on the PC), :551 `Assert.Empty() Failure` |

Not reverted: `ATemporaryIsHiddenUniqueAndBesideItsFile` (reads the name's shape), `TheScanSeesBothShapesOfAReader` (the scan's own self-test; H proves the scan), `AFileThatIsNotValidJsonReadsAsNothingRememberedAndIsReplaced` (pins today's behaviour, unchanged). A first version of the refused-read tests used a holder sharing delete; it passed under A and B (Windows refuses a replace onto ANY open file without POSIX rename, so the write could not land either way), and was replaced by the race the issue names, driven by the pause.

### Review 1's lows not done in round 2 (one line each)

- Low 4: `HeldFiles.Replace` names the TARGET when only the temporary was held; naming the temporary would put ".tmp" in front of a teacher, so it stays, and the "was not changed" half is true.
- Low 6: a Save or reload on a held file waits up to the bound on the UI thread (about 0.75 s per read, 1.5 s for a Save); moving it off the thread is #986's Save rewrite.
- Low 7: a holder that shares delete makes the rename refuse with access denied while the probe sees no hold; said as "Access is denied." and not retried. The probe is the brief's; for the Undo door.
- Low 8: `AgentGuidance.Write` and `AppendAfterYes` read the root files with `ReadStrict`, not asked again; outside the lines this lane may touch in `AgentGuidance.cs` tonight (lane E's file), and nothing is written after a failed read there.
- `HeldFiles.cs` 119 to 122 carries the same wrong 'access denied' comment, and `CourseConfiguration.cs` 120 to 145 has two `</summary>` closings; for the next piece on this code.

- For W8 (the Undo door): a retried rename replays a merge made before the pause, so a build's replace during that pause is put back; the fix is a compare-and-swap before each retry (review 2).

### Must-fail lines, round 2 (review 1's fixes)

Scratch branches `scratch/874-mf-s1` to `s5` (deleted after), `HeldFilesTests` and `CourseSettingsHeldFileTests` run on the first VM with `874-run.ps1 -TestsOnly`. Real branch: 21 of 21 in those two classes.

| Reverted | Failing test, line, assertion as printed |
|---|---|
| s1: an access-denied read asked again only when the probe sees a hold (round 1); and the reference door failing open with no earlier read | `HeldFilesTests.AnAccessDeniedReadIsAskedAgain…`, HeldFilesTests.cs:129 (the read threw); `CourseSettingsHeldFileTests.AReadDeniedByARuleRefuses…`, :326 `Expected: typeof(FileRefusedException) Actual: typeof(System.UnauthorizedAccessException)`; `AHeldCourseNeverReadBeforeIsTreatedAsKeptForReference`, :296 `Assert.True() Failure Expected: True Actual: False` |
| s2: `Write` takes "could not read just now" as not there (whole-object write); `KeptOnDisk` fails open; Revert gives no sentence; `RecordOnDisk` counts a refused second read as unchanged | `ARecordWhoseSecondReadWasRefusedWritesNothing`, :361 `Assert.Throws() Failure: No exception was thrown`; `ASaveWhoseMergeReadWasRefused…`, :194 the same; `AReadDeniedByARule…`, :326 the same; `ARevertOnAHeldFileSaysNothingWasRevertedAndWhy`, :384 `Expected: "course_config.json is in use by another p"… Actual: null`; `AHeldCourseNeverRead…`, :297 `Expected: "ICS3U" Actual: null`; `ABuildReplacingTheSettingsInALoop…`, :470 "1 of 82 rounds (a reader that does not ask again was refused 0 times with access denied, 4 with a sharing violation, 0 otherwise): a Save put the window's whole copy over the build's" (in an earlier run of the same revert the loop did not meet a refusal that outlasted the bound, and passed: this case is caught by `ASaveWhoseMergeReadWasRefused…` every time, by the loop only when the race lasts) |
| s3: discovery drops a course it could not read (H1's outcome) | `HeldWhole…`, :165 `Assert.Single() Failure: The collection was empty`; `TheReloadsOwnCallKeepsAHeldCourseAndItsDoorsStayShut`, :281 `Expected ["ICS3U", "MPM2D"] Actual []` |
| s4: no read asked again at all and no last good read (the code before this lane), and no Hide | `ABuildReplacingTheSettingsInALoop…`, :470 "78 of 476 rounds (… refused 0 times with access denied, 86 with a sharing violation, 0 otherwise): the course vanished from a reload"; `TheTemporaryIsHiddenWhileItExists…`, :409; and every bound test (`Expected [50, 100, 200, 400] Actual []`, HeldFilesTests.cs:104 and :138, CourseSettingsHeldFileTests.cs:153, :328; `Expected 4 Actual 0` :198, :369) |
| s5: the settings file not unhidden after the rename | `TheTemporaryIsHiddenWhileItExistsAndTheSettingsAreNot`, :410 `Assert.False() Failure Expected: False Actual: True` |

**What the real replace loop measured (VM A, Windows 11 ARM64, Plantoir x64 under emulation, 2026-11-21).** A second PowerShell process replacing `course_config.json` with `MoveFileExW(…, MOVEFILE_REPLACE_EXISTING)` (CPython's `os.replace` on Windows) while the app read, listed and saved: a C# reader that does not ask again was refused 86 times in 476 rounds and 4 in 82, every one a SHARING VIOLATION, none ACCESS DENIED. So review 1's H2 mechanism (an access-denied open of a delete-pending file) was not reproduced here; #874's "access denied" was Python's `PermissionError`, which CPython raises for a sharing violation too. Round 1 already asked a sharing violation again; what the loop proves is the whole path: without asking again and without the last good read, the course vanishes from a reload (s4), and a Save that takes a refused read as "not there" puts the window's whole copy back (s2). Access denied on a file that is there is asked again all the same, because a deny rule and a delete-pending file cannot be told apart by the probe, and the cost is only the bound; `AReadDeniedByARule…` and `AnAccessDeniedRead…` prove that branch.

## 2026-11-21 — Lane D, Windows preview starts and stops: #928, #1026, #1022 item 1

Branch `issue/928-win-preview-starts`. #1022 item 1 is done here; #1022 item 2
(the 13 timed waits) is not touched, so #1022 stays open for it.

#### #928 (the mac's #812 and #813)

- The decisions are in `Plantoir.Core/Models/PreviewStarts.cs`
  (`HowTheRunStands`, `AStartIsUnderWay`, `TheStartStillBelongs`, `Begin`,
  `CouldNotStartLine`) and `PreviewAgainPresses` in the same file; the view
  only asks them.
- A start asked for while the window's own start waits in
  `WaitForStopsToFinish` or builds does nothing and writes
  `preview already starting`, in `PressPreviewAsync` (after the Stop branch)
  and FIRST in `StartAutomatedPreview`. The second press used to reach
  `PreviewLeases.Take` and show the other-window sentence;
  `StartAutomatedPreview` used to release that start's lease and overwrite its
  `_previewBuildRecord` (quit then asked for ever).
- Both starts take through `PreviewStarts.Begin` (lease, then this start's
  own record) and `TookTheStart`; the view no longer calls
  `CourseActivity.BeginPreviewBuild` itself. `StartAutomatedPreview`'s
  folder-keyed `PreviewLeases.Release(workspacePath, …)` is now the view's own
  `ReleaseLease()` (it also let go a `WorkLease` the old code leaked when it
  re-took `_previewWork`).
- A parked start runs its launcher only if it still holds its own lease (by
  reference), is the window's latest start (`_latestPreviewStart`), the page
  is not torn down and the quit has not gone ahead
  (`Plantoir.Core.Models.QuitGoingAhead`). Since review 1 (M1) the closing
  handler runs one `QuitGoingAhead.Pass` per run: the quit goes ahead in one
  place (`pass.GoAhead()`, which also abandons every repair press) and is
  taken back in one place, the pass's end, unless the pass said the close
  went through, was handed to the next pass, or was no quit. Keep Working
  when asked again after the wait for a tools copy used to leave it set, and
  Preview then started nothing until relaunch.
- A press while the window's own stop finishes (`StopPreviewAsync`, counted
  by `_stopsUnderWay`) does nothing and writes a true line to the diagnostic
  log ("…while this window's preview was still stopping: nothing was
  started"), not `preview already starting` (review 1, L1). No trail event
  names it and adding one needs a contract key, so it is the diagnostic log.
- An exception escaping either start after it took its lease hands back what
  that start still holds (`HandBackAfterAFailure`: stopped the way Stop
  stops it, only if `PreviewStarts.TheStartStillHoldsItsOwn`) (L2). The
  repair's refusal after the stop is shown through its own catch (L5).
- `AssistWorkspace`'s refusal for a folder that is not set up, which Section ▸
  Rebuild Preview shows a teacher, no longer names `preview.ps1` or the full
  path (`AssistWorkspace.NotAWorkingFolderYet`, the folder by its name) (L6).
- A run that never started (`HowTheRunStands` → `CouldNotStart`: not running,
  `LaunchProblem` set, asked before the exit code) ends the wait at once
  (`AbandonWait`: wait, record, lease), writes `preview could not start` with
  the sentence and `LaunchProblemDetail`, and shows the sentence under
  "Cannot Preview Yet". The console stays up with the sentence
  (`RefreshChrome`'s `showConsole` counts `LaunchProblem`).
- The repair's Preview Again records its press at once
  (`PreviewAgainPresses.Shared.Press`), is abandoned in `OnUnloaded` and on
  quit, starts only through `CarryOutAsync` if the press survived the stop,
  and writes `preview again abandoned` with "replaced" kept apart.
- `CourseActivity.UnderWay` counts each section once however many claims
  (`whatCountsAsUnderWay`).
- Sentences (items 8, 9): `ScriptRunner.CouldNotGetStarted` ("Could not get
  started. Try again, or restart this computer if it happens again.") and
  `ScriptRunner.FolderIsMissingAPiece` (no file name); the system's text and
  the file name go to `ScriptRunner.LaunchProblemDetail`, trail only.
  `TaskScheduling.NothingToSchedule` replaces the refusal that named
  `deploy.ps1` and the full folder path.
- Trail lines, in the mac's words: `preview already starting` writes "asked
  to preview while this window's preview was still starting: the start
  already under way goes on, and nothing else was started"; `preview could
  not start` writes "the preview could not start, and the teacher was told
  why: <sentence> (<detail>)" (`PreviewStarts.CouldNotStartLine`).
- Ledger: the `Owed(ActivityTrailEvents, 928, …)` entry and `Reason928` are
  removed; the three events are in `ActivityTrail.Event`.
- Tests: `PreviewStartRecordTests` (every `pressCases` and `previewAgainCases`
  case from the JSON, with windows A and B as two lease owners, the
  per-section count, `HowTheRunStands`, `TheStartStillBelongs`, a replaced
  press, two owners on one section, release by reference, a press during a
  stop, and source readings that both starts ask the model in order, release
  only their window's rows and hand back on a failure),
  `QuitGoingAheadTests` (every way out of the quit question, and a reading
  that the handler uses one pass), `LaunchProblemWordingTests` (refuses
  ".sh", ".ps1", ".py", "launcher", "script" in every launch problem and in
  the folder-not-set-up refusal; a missing launcher met for real). Review 1's
  L3: the two vacuous tests (`TwoStartsThenTheEnd…`, `TheViewRecordsABuild…`)
  are removed; the pressCase "a second press while the first waits for its
  stop" and the source-order theory cover item 4.
- Not met for real: the ConPTY launch failure (`CouldNotGetStarted`); the
  runner always launches `powershell.exe`, so the test reads the constant.
  The mac's test points its shell at a missing program.

- Must-fail (review 1), all reverts at once in scratch commit bd4b1bb5c (local only), each test failing on its own revert: VM B, 2026-11-21 00:31, 11 of 28 failed, the other 17 passed:
  - `QuitGoingAheadTests.KeepWorkingWhenAskedAgainAfterTheWait` line 56 and `AWindowOpenedDuringTheWait` line 71: the pass's default ending reverted from TakenBack (M1).
  - `QuitGoingAheadTests.TheClosingHandlerUsesOnePass` line 148: `LetHeldCopiesGo()` put back on the handler's Keep Working path.
  - `PreviewStartRecordTests.AnotherWindowsStartNeverEndsThisWindowsLease` line 258: `ReleaseLeftBehind` made to ignore the owner (M2).
  - `PreviewStartRecordTests.TheViewReleasesOnlyItsOwnWindowsLeases` line 381: `ReleaseLease`'s sweep put back to `PreviewLeases.Release(wp, …)` (M2).
  - `PreviewStartRecordTests.AReleaseRemovesOnlyTheLeaseItsStartTook` line 281: `Release(lease)` put back to `_active.Remove(lease)` (value equality).
  - `PreviewStartRecordTests.AStartHoldsItsOwnLeaseByReference` line 292: `TheStartStillHoldsItsOwn` made to compare with `Equals`.
  - `PreviewStartRecordTests.APressDuringAStopIsNotAStartUnderWay` line 301: the stop branch of `WhatAPressMeets` removed (L1).
  - `PreviewStartRecordTests.ThePressAsksWhetherTheWindowsStopIsUnderWay` line 392: `_stopsUnderWay++` removed from `StopPreviewAsync` (L1).
  - `PreviewStartRecordTests.AFailedStartHandsBackWhatItHolds` line 404: `HandBackAfterAFailure` removed from `StartAutomatedPreview`'s catch (L2).
  - `LaunchProblemWordingTests.TheFolderNotSetUpRefusalNamesNoFileOrPath` line 84 (via line 21): the old sentence naming `preview.ps1` put back (L6).
- Proven on VM B, head 90598c6b9 (dev 10d04bfbd merged): the piece's classes and every class that reads a changed file as source text, 44 classes in batches, all green except `PublishAndLauncherContractTests.EveryQuestionTheMacDeployLauncherAsksIsGuardedAtTheTopLevel` (deploy.sh line 1472 inside `run_token_mode()`; `deploy.sh` is untouched by this branch, so it is dev's, unrelated). `DialogTitleScanTests` needed the census at 17 for the "Cannot Preview Yet" alert. `PreviewThatCannotStartUiTests` passed twice.

- Review 2 (`vm-tools/briefs/2026-11-21-lane-d-review-2.md`), fixed:
  - M3: `StartAutomatedPreview` now answers its caller once the start is
    decided (`Task<string?>`: null went ahead, otherwise the sentence shown).
    `PreviewStarts.Begin` stays the one place that decides; a lease refusal
    (and an outside build's decline, and this section's deploy) is shown under
    "Cannot Preview Yet" through `ShowPreviewRefusal`, the press's own way,
    and the answer goes back through `RebuildPreviewAsync`,
    `MainWindow.RebuildPreviewFor` and the `RebuildPreviewInApp` seam (now
    `Func<Task<string?>>`). The runner answers that sentence
    (`ShownInTheWindow`, so the Section menu does not show it a second time),
    the trail ends "not rebuilt", and the assistant's two own rebuild routes
    (card and plain words) say it instead of "is opening". The runner now
    waits for the stop before it answers, as the Mac's `bringThePreviewUpToDate` does.
    Census: `SectionDetailView.xaml.cs` 17 to 15, the four "Cannot Preview
    Yet" dialogs of the start (press refusal, press decline, run that never
    started, and the new automated one) being one `ShowPreviewRefusal`.
  - Left as they were (each already shows its own dialog; `RebuildPreviewFor` asks the
    same thing first, but the runner does not: the third review found this): the folder getting ready,
    no folder, a view replaced during the stop. Those still answer null.
  - Mac difference (not touched, Windows only): the Mac's
    `bringThePreviewUpToDate` returns `previewIsRebuilding` after
    `startPreview()` whatever it did, and `SectionVerbs` writes "rebuilt", so
    on the Mac the assistant and the trail are wrong for a refused start
    while the window does show "Cannot Preview Yet".
  - L10: `MainWindow.Closed`, after the view lets go, sweeps and releases by
    reference every row the window still holds (`PreviewLeases.HeldBy`), so
    a replaced view's row cannot outlive its window. A crashed process takes
    its table with it; a replaced view in a live window is swept by that
    window's next start of the section, as before.
  - L11: not measured (whether `Close()` raises `AppWindow.Closing` at once
    or later). The model showed the state reachable whenever it is later, so
    it is made impossible either way: a pass handed the quit by its own
    window's earlier pass, finding the close no longer quits, takes the quit
    back (`QuitGoingAhead.BeginPass(..., window:)`).
- Must-fail (review 2), all six reverts at once in scratch commit 7ffbb49e2 (local only, deleted after), VM B 2026-11-21 01:42, 6 of 6 failed. The log names the tests, not lines; the line given is the first assertion each revert reaches:
  - `SectionVerbsTests.ARebuildTheWindowRefuses_IsAnsweredWithItsSentence_NeverRebuilding` line 514: the runner put back to ignore the window's answer (M3).
  - `SectionVerbsTests.ThePlainRebuildTheWindowRefuses_SaysTheWindowsSentence` line 531: the plain route put back to "is opening" (M3).
  - `PreviewStartRecordTests.TheAutomatedStartAnswersWithTheRefusalItShows` line 423: the automated start's answer and dialog removed (M3).
  - `PreviewStartRecordTests.AClosingWindowHandsBackEveryRowItHolds` line 284: `HeldBy` made to return nothing (L10).
  - `PreviewStartRecordTests.TheClosingWindowLetsGoOfWhatItStillHolds` line 438: the call in `Closed` removed (L10).
  - `QuitGoingAheadTests.AHandedOnQuitThatIsNoLongerAQuitIsTakenBack` line 93: `NotAQuit` made unconditional again (L11).
- Proven on VM B, head ad119f41b (dev 10d04bfbd in): 31 classes (the piece's and every class that reads a changed file as source text), 470 of 470 passed; `PreviewThatCannotStartUiTests` passed.

#### #1022 item 1

Done. Both shapes go one way: a `preview.ps1` missing before the press used to
throw inside today's-class question (`new AssistWorkspace` outside its try)
and the press did nothing, logged only. The construction is now inside the
try, the press goes on, the run cannot start, and the wait shows "Cannot
Preview Yet" with `FolderIsMissingAPiece` (see #928 above); a launcher gone
after the press's checks meets the same wait. Proven in the window by
`PreviewThatCannotStartUiTests` in the second VM (launcher moved aside before
the press; the alert's sentence read through UI Automation, the console
keeps it, the trail has `preview could not start`, and a second Preview after
the launcher is back starts).

#### #1026

`ScriptRunner.CancelByUser`'s fallback remembers its run's number and process
and terminates only while that run is still current and running; it returns
the fallback's completion. Control-C's two seconds stay (behaviour,
`ControlCGrace`). `StopFallbackOwnsItsRunTests`: a second run started inside
the grace is still running after the first's fallback has completed; a run
that ignores Control-C is still terminated by its own fallback. (Review 1, L4: the first test's `IsRunning` assertion was dropped, since staged runs have no process and it held under the old code too; `FallbackTerminations` is what fails on revert.)

The mac's `ScriptRunner.swift` has the same shape (`DispatchQueue.main.asyncAfter`
near line 583, no run check); not touched here (Windows only tonight). #1015
probably holds it.

#### Left out

- Four ways out, and a stop already under way, still answer the assistant "rebuilding" with nothing rebuilt (review 3, L14); recorded on #1022.

## 2026-11-21 — Undo and Redo, W7a (part): the step for a daily action, and Publish Pages and Hide Pages through it (#899, #949)

Branch `issue/899-w7a-publish-through-the-door`, from W4c (2e10771f6) with `origin/dev` c446f5f64 merged in (3dc806224).

- `UndoActionStep` (`Plantoir.Core/Undo/UndoActionStep.cs`, the mac's `JournaledStep`): an action plans each file (`Write`), reads through the plan (`ReadText`), names the front page as a `recompute` (`KeepsTheFrontPageTrue`), and `Make()` hands ONE draft to `UndoDoor.Perform(UndoStepDraft)`: key, `pageCount`, `madeBy`, `class: A`, course, section, `holds`. Each before is read when the file is FIRST planned. A step that cannot be named (no `courses\` above the folder, a path out through a link, a target that is a link) is staged and swapped in together without the list in shadow, with one trail line; live, refused before anything is written. A target that is a folder, or a file unreadable at plan time, stops the action before anything is written.
- Refusals: `UndoStepRefusedException` (nothing written: the caller says "Nothing was changed: …") and `UndoStepLeftPartWayException` (a file could not be put back: the message names each kept original with `undo.wording.keptBesideIt`; the caller says `publishStoppedPartWay`). `UndoOutcome.LeftPartWay` is new on the door.
- Publish Pages and Hide Pages (`AssistWorkspace.Apply(PublishPlan …)`): one step, keys `publishPages` / `hidePages`; the front page is re-derived once after the step by the door (never a file of the step), or by the step itself when the door made none. `UndoHistory` is told each file's before and after as `Save` told it, the re-derived front page included.
- `madeBy` from `AssistWorkspace.Surface`: `menu`, `builtInAssistant:<id>`, `outsideAssistant::<id>`; the id is one GUID per workspace (the window's conversation, or the `plantoir-mcp.exe` session).
- "undo could not record a step" (`ActivityTrail.Event.UndoCouldNotRecordAStep`, `UndoTrail.CouldNotRecordWords`, the mac's `couldNotRecordLine`): written by the door when the list cannot take a step given as files (went ahead, nothing was changed, stopped part way), and by the step for a step it cannot name. Its ledger row and `Reason899` are gone.

### Fix round one (review 1 of W7a part one, NOT CLEAN; and W4c review 1's lows), 2026-11-21

- **M1, measured** (PC LENOVO i5-8365U, Windows 11 Pro 26200, desktop session by `schtasks /it`, "Show hidden files" off: `Hidden=2`; script `vm-tools/guest/899-w7a-explorer-measure.ps1`, result `C:\vm-setup\899w7a-explorer\result.txt`). A kept `-orig` made as the door makes it (a hard link to the page, the page then replaced by rename) has attributes `Archive` only, link count 1 after the rename; a copy the same. Outside OneDrive and inside it (OneDrive running): File Explorer LISTS both dot files and SELECTS each, by `explorer.exe /select` and by `SHOpenFolderAndSelectItems` (hr 0), read back through `Shell.Application.Windows()` (`Document.SelectedItems()`, `Document.Folder.Items()`). A copy marked Hidden is not listed and nothing is selected, by either call. So a leading dot hides nothing on Windows. The director's call (Windows imitates the Mac; to be confirmed with Russell): the swap marks every kept original Hidden once the page's rename is in (`UndoSwap.HideTheKeptFile`, after `wentIn`, so a hard link never hides the live page), and shows it again before a put-back renames it onto the page (`ShowTheKeptFile`; only an attribute the swap set: a page the teacher hid stays hidden). Every kept file is made by `SwapAFile` (the door, the plain write, recovery's put-backs), so this is the one place. Enumeration in recovery and the tidies uses `Directory.Enumerate*` without options (`EnumerationOptions.Compatible`, hidden included). Consequence for W7b's alert: with "Show hidden files" off, a Show in File Explorer button cannot show the kept file.
- **M2:** `ARecordedStepLeftPartWayIsSaidAsPartWayAndNamesTheKeptFile`, `AnUnrecordedStepLeftPartWayIsSaidAsPartWayWithItsTrailLine` (a read-only second page, the first page's put-back failing by seam).
- **M3:** `UndoHistory.FileState.BeforeBytes`; `MakeTheUndoStep` gives today's undo each page's bytes, written back as they were; `TextOf` reads as `File.ReadAllText` (byte-order marks). `AUtf16PageComesBackByteForByteAtTodaysUndo`.
- **M4:** the door's `Rederive` and the step's `RederiveTheFrontPages` catch whatever a re-derivation throws after the swap. `AFrontPageThatThrowsAfterTheSwapIsNeverSaidAsNothingChanged`.
- Lows done: couldNotWrite said "(the disk may be full, or Plantoir may not have permission to write there)"; a plain write names its page by full path, so the read-only sentence finds it; doc comments moved back; a test's stop (`StoppedByATest`) is an `InvalidOperationException`, never "Nothing was changed"; `KeepsTheFrontPageTrue` once per page. The doubled phrase in `editJSONCasesHow` is gone with W6's move of the rows to `contracts/undo-json-cases.json` (merged in); this branch's net `contracts/` change is W4c's README line only.
- W4c review 1: LOW 1 (`TakeTree` takes the next free kept name), LOW 2 (every kept name taken is couldNotWrite, folder and page), LOW 3 (`LeftNewestWords` names the list's content when the refusal has no path), LOW 5 (`PruningsTidyRemovesAKeptOriginalThatIsACopyOfItsPage`). Tests in `UndoSwapTests`, `UndoTrailWordsContractTests`, `UndoDoorTests`.
- B: pruning's tidy passes `onAside` (`UndoJournal.Prune(writer, trail)`, from `RecoverThenPrune`): `PruningsTidyWritesTheLineForAFolderItKeepsVisibly`.
- Runs (PC LENOVO i5-8365U, Windows 11 Pro 26200, filter `FullyQualifiedName~Plantoir.Tests.Undo`): `899w7a-d2` at 3aee10d3c, 826 passed, 2 failed (the UTF-16 test's publish wrote nothing, so it was rewritten to make the step as an action does; the writer scan's counts for `UndoHistory.cs` 3 and `UndoSwap.cs` 23, now listed with reasons). `899w7a-d3` at 39147eb3b: both builds 0, 828 passed, 0 failed, 1 skipped (829).
- Must-fail: `vm-tools/guest/899-w7a-mustfail-2.json` (12 sabotages, `899w7a-d2`): 11 RED; B was NOT-RED (recovery tidied again in a later hold and wrote the line), so the two pruning tests now lay their leftover after every recovery tidy and check the last one, which only pruning meets. `899-w7a-mustfail-3.json` (`899w7a-d3`): LOW 5, B and M3 all RED; restored 828 passed; HEAD SAME.
- Contract wording lows (the director's): `undo-json-cases.json` note names `ContractFilesWindowsPowerShellReadsTests`; `contracts/README.md` "the eight authored files"; `WINDOWS-BOOTSTRAP.md` thirteen JSON files, eight authored. `origin/issue/899-w6-op-kinds` 9f3e16b85 merged in. Merged `origin/issue/899-w6-op-kinds` (6437a9b89) and `origin/dev` da5af161e (3aee10d3c).

### Round three (the next writer), 2026-11-21

- **C, a whole unit** (`ApplyWholeUnit`): ONE step, key `publishPages` / `hidePages` (the mac's `publishPagesAWholeUnit`). While a step is planned, `_planningThrough` routes the planners' page reads through it (`ReadPlanned`: `PlanPublish`, `IndexChangeFor`, `WriterDeclines`, the visibility and link reads, `SiblingTimeAndOffset`), so each class is planned seeing the classes before it. `DateOf` is static and still reads the disk (no publish moves a class page's date). Tests: `UndoWholeUnitAndByDateStepTests` (one step with one recompute and today's undo; hiding a unit takes down the page both classes use; a unit that cannot be written whole changes nothing).
- **C, Publish Class for a Date**: `Apply(…, keepingTheClassByItsDate: true)` from `publish_class_on`, key `publishClassForADate`; `later-classes-kept.json` is planned INSIDE the step (`KeepTheClassesItPublished(…, step)`, `ClassesDatedLater.FlaggedIn(readPage, readRecord)`, `LaterClassesKept.RecordKeeping`), written only if the pages are, never told to today's undo (`UndoActionStep.Write(…, todaysUndoKeepsIt: false)`; Undo Last Change leaves it, as on the mac). When the pages need no change, the record is a step of its own (`KeepTheClassesPublishedByTheirDateOnAStepOfTheirOwn`); before, Windows kept nothing there. Changed for a teacher: the record now goes in with the pages even when the preview build then fails (the mac's U3 LOW 10).
- **The front page's recompute is named on every publish and hide** (the sweep, 2), as the mac's step names it; on a unit only when a class changes (round four, M1).
- **E**: `UndoActionTraceContractTests` replays every `actionTraces` trace through the real door from `undo-action-steps.json` (front page re-derived by `UndoSectionFrontPage`). Held by name in `NamedGapLedger.UndoActionTraces`: action-121 to 132 (rollover, `moves`, `Reason899W7U3b`) and action-133 to 150 (U4a `members`/`trees`, new `Reason899W8U4a`). The contract now has 150 traces, not 120: the 18 U4a ones are W8's.
- **E, `rule.recovery`'s U3 sentence was NOT true on Windows**: recovery tidied closed steps only live. Now `TidyClosedSteps(…, onlyStepsOfFiles: mode == Shadow)` (`UndoRecovery.ChangesOnlyFiles`, the mac's `changesOnlyFiles`). Test: `UndoShadowClosedStepTidyTests`.
- **F**: the weak `NotEqual` and the front page in today's entry (`UndoActionStepTests`); the stale remark in `PublishStoppedPartWayTests`, whose theory now goes part way only by the door's own put-back failure (`AssistWorkspace.UndoSeams`, a test's seams for every step of a workspace) and names the kept file; the could-not-write sentence pinned (`ACouldNotWriteRefusalSaysTheDiskOrThePermissionAndChangesNothing`). Contract wording: `WINDOWS-BOOTSTRAP.md` "eight authored files"; `contracts/README.md` names `undo-json-cases.json` for `editJSONCases`.
- `SectionVerbsTests.AWholeUnitThatStoppedPartWay_IsCarriedOut` now asserts all or none ("Nothing was changed", "changed nothing, 1 unit"). The replay found one real difference: action-047 (an Undo after one page is edited by hand and a later one deleted) names the deleted page first where the contract names the edited one; held by name under `Reason899W7aFirstInTheWay` for W7b.
- Run `899w7a-e5` at f9cd037be (PC LENOVO i5-8365U, Windows 11 Pro 26200; dev da5af161e merged, nothing newer): both builds 0; Undo classes, `PublishStoppedPartWayTests`, `SectionVerbsTests`, `AssistWorkspaceTests` (AssistTests.cs), `ClassesDatedLater*`, `FutureDatedClasses*`, `DeclinedPagesAreNamed`, `SectionMenuServerTests`, `PublishTomorrowsClass`, `SameNamedClassPage`, the ledger: 1225 passed, 0 failed, 1 skipped.
- Must-fail: `vm-tools/guest/899-w7a-mustfail-4.json`, 11 sabotages in `899w7a-e5`: all 11 RED (the planners reading the disk; the classes asked about read from the disk; the record outside the step; today's undo told of the record; no step of its own; no front page in a unit; part way said as nothing changed, 4 of 4; could-not-write naming the disk only; the front page not told to today's undo; shadow recovery tidying no closed step; a held rollover trace released, 1 of 150). Restored 1225 passed; HEAD SAME.

### Round four (part three review 1 and the remaining lows), 2026-11-21

- `origin/dev` 10d04bfbd merged in (6c9987e42; conflicts in documentation 09 and 12 resolved keeping dev's `undo-json-cases.json` name and the branch's sentences; W6's notes deleted as on dev).
- **Part three M1:** a whole unit names the front page only when a class of it changes (`if (step.ChangesAnything)`, the mac's `if changedAnything`): a unit that changes no page answers `unitAlreadyPublished`/`unitAlreadyHidden` and touches nothing. Publish Pages and Hide Pages still repoint the front page when nothing changes, as the mac's `apply` repoints it after its step, with no step made. Test `AUnitThatChangesNoPageIsAlreadyPublishedAndTouchesNothing`.
- **Part three M2:** the kept record is planned under `try … catch (IOException or UnauthorizedAccessException)` (the mac's `try?`): a record that cannot be read costs only the record, the class is published. Test `APublishClassForADateWhoseRecordCannotBeReadStillPublishes` (record held `FileShare.None`).
- **action-047, released:** `UndoDoor.Perform(UndoStepDraft)` sorted a step's files by path (since W2b); it now keeps the order the action planned them, as the mac's `JournaledWrite` does, so the begin line, the Undo check (newest first) and the swap order match the mac. The replay now also checks each begin line's files in the recorded order (`LastBeginsFilePaths`), so no trace passes by an accident of order. Ledger row and `Reason899W7aFirstInTheWay` gone. The ledger says the held rollover and U4a traces fail by the replay's own guard (L2).
- **L3:** the planning step is per flow (`AsyncLocal`, `PlanningThrough`). Test `AnotherCallersPlanNeverReadsThroughThisActionsStep`. **L4:** `AShadowStepWithAMoveIsLeftAloneByTheTidy`. **L5:** indentation.
- **Part two LOW 1:** a kept file whose Hidden cannot be cleared is never renamed onto its page (`ShowTheKeptFile` returns false; the step is left part way, the kept file Hidden under its name). Seam `ShowingTheKeptFileFailsAt`; test `AKeptFileThatCannotBeShownIsNeverPutBackSoNoPageIsLeftHidden`.
- **LOW 2:** every kept file named as "the hidden file" is marked Hidden where it is named (`UndoSwap.HideAKeptFileLeft`: recovery's lines, the part-way sentence, the kept-what-it-replaced line), only when it has one name (`UndoFileIdentity.LinksOf`), so a kept file that is still a hard link to its page never hides the page. Test `AKeptOriginalRecoveryLeavesAndNamesIsHiddenAndThePageIsNot`.
- **LOW 3:** recovery's tidy and pruning each meet a Hidden kept file (`[Theory]` variants), and the closed-step tidy asserts the kept file it met is Hidden.
- **LOW 4:** `UndoRefusal.EveryKeptNameTaken`; the sentence is "nothing could be written beside “…”: every name Plantoir keeps an earlier copy of it under is already taken there." Test `APageWhoseEveryKeptNameIsTakenIsSaidSoAndNothingIsWritten`.
- **LOW 5:** the plain write's part way finds kept files beside a link's target too (`PlaceWritten`). Test `APlainWriteLeftPartWayIsSaidAsPartWayAndNamesTheKeptFile` (plain, and through a symbolic link).
- **The sweep, 1:** `WithTheSwitchOffALinkedPageIsWrittenThroughItsLinkAndStaysALink` (a real symbolic link, `File.CreateSymbolicLink`); documentation 12's sentence corrected in this branch at the director's word.
- **D:** `Plantoir.UndoHarness/W7Runs.cs`, `w7-publish-kill`: three pages published through `UndoActionStep` by a child killed at `afterBegin`, each `beforeSwap@i`, `beforeApplied`, shadow then live, then a second process recovers; each page judged by content.

### Round five (the proof of round four), 2026-11-21

- Run `899w7a-f4` at 01078db83 found three failures, each fixed in 03c1155b7:
  - **The harness, shadow `beforeSwap@0`, NOT-WHOLE (outside and in OneDrive): a real product gap.** A shadow step of files killed before its first swap closes `failed` (nothing took effect); the closed-step tidy meets only `interrupted` steps, and the settled tidy ran only live, so its three staged `-new` files stayed beside the pages until the switch flips. With the switch off a teacher would have met dot-files that never existed before this piece. Now recovery in shadow tidies a `nothingTookEffect` step whose every op changes a file in place (`ChangesOnlyFiles`), keeping only copies, writing no trail line (`UndoRecovery.Settle`). Test `UndoShadowClosedStepTidyTests.AShadowStepOfFilesKilledBeforeItsFirstSwapLeavesNoStagedNewContent`.
  - **`APublishClassForADateWhoseRecordCannotBeReadStillPublishes`: the test was wrong.** It held the record `FileShare.None` across the whole publish, so the course backup (which includes `.publish_state`) could not read it and the publish was refused, truly, with "couldn't be backed up, so nothing was changed", as before this piece. The product's M2 catch was right. The test now uses the assistant's window (one backup a conversation), publishes tomorrow's class first so the backup is made, then holds the record for Publish Class for a Date; the replies are the assertions' messages. The Section menu backs up before every change, so there a held record always meets the backup's refusal first.
  - **`UndoWriterScanTests`: `UndoSwap.cs` 24 writing calls, not 23.** The 24th is `HideAKeptFileLeft`'s `File.SetAttributes` (LOW 2); the allowance and its reason now name it.
- **For the mac (to KNOW, and maybe to DO):** the mac's `UndoRecovery` has the same shape: its settled tidy runs `if mode == .live`, and `tidyClosedSteps` takes only `.interrupted`, so a shadow step killed before its first swap may leave its staged files there too. Not measured on the mac. The director decides whether that needs a `mac` issue.
- `origin/dev` 41f30f5c6 merged in (f4e27e3ed, clean).
- Run `899w7a-f5` at 03c1155b7, and `899w7a-f6` at f4e27e3ed (PC LENOVO 20QES70500, i5-8365U, 16 GB, Windows 11 Pro 26200): app build 0 errors, test build 0; the Undo classes (the trace replay `UndoActionTraceContractTests` and the symbolic-link test `WithTheSwitchOffALinkedPageIsWrittenThroughItsLinkAndStaysALink` among them), `PublishStoppedPartWayTests`, `SectionVerbsTests`, `AssistWorkspaceTests` (AssistTests.cs), the ledger: **1149 passed, 0 failed, 1 skipped** (the skip is `UndoWebsiteContractTests.ARecordFolderThatDeniesListingCannotTell`, as before). Harness `w7-publish-kill`: 10 of 10 WHOLE outside, 10 of 10 inside OneDrive (OneDrive running), shadow and live; scratch removed.
- Must-fail: `vm-tools/guest/899-w7a-mustfail-6.json` (set 5's 11 sabotages, unchanged, plus a twelfth for the shadow tidy) in `899w7a-m6` at 03c1155b7: **all 12 RED** (action-047 sorted by path, 12 of 152; LOW 1 kept file put back unshown, 1 of 1; LOW 3 tidy skipping Hidden files, 2 of 4; LOW 2 recovery naming without hiding, 1 of 1; LOW 4 said as disk or permission, 1 of 1; LOW 5 kept names beside the planned path only, 1 of 2; sweep 1 the link replaced, 1 of 1; M1 the front page named on a unit that changes nothing, 1 of 1; M2 the record refusing the publish, 1 of 1; L3 one planning step for every flow, 1 of 1; L4 the shadow tidy taking every closed step, 1 of 1; F5 shadow leaving a failed step's staged files, 1 of 1). Restored: 1149 passed, 0 failed, 1 skipped; HEAD SAME. (Set 5 alone, `899w7a-m5` at b3f8d5ea6, before the fixes: all 11 RED, but its M2 row is void, that test then failing either way, and its restore was the same 2 failures as `899w7a-f4`.)

### For W7b

- Entry points: `AssistWorkspace.NewUndoStep(key, course, section)`, then `step.ReadText` / `step.Write` / `step.KeepsTheFrontPageTrue`, then `MakeTheUndoStep(step)` inside the action's `UndoHistory.Record`, and in its `catch (IOException or UnauthorizedAccessException)` `StoppedWhileWriting(error is UndoStepLeftPartWayException, error)`.
- Still to go through it: every action W7b lists (writer scan entries `waitsFor: W7`; `LaterClassesKept.Keep` stays for Deploy's and the links checklist's records).
- The planners read through the step while `_planningThrough` is set: an action that plans several things in one step sets it for its planning, as `Apply` and `ApplyWholeUnit` do.

### Changed tests (the failure is now all or none)

`PublishStoppedPartWayTests.APageThatCannotBeWrittenIsAnsweredAndTheCopyIsNamedOnlyInTheWindow` (the page-list rows), `SectionVerbsTests.APublishThatStoppedPartWay_IsCarriedOut` and `UndoAcrossToolsTests.AnOperationThatThrewPartWayLeavesNothingOpenToSwallowTheNext` asserted the old file-by-file part-way outcome. A publish of pages is now one step, so a page that cannot be written leaves every page as it was, and the sentence is "Nothing was changed: …". Since round three the whole-unit rows are one step too.

### Runs (PC, LENOVO i5-8365U, Windows 11 Pro 26200)

- `899w7a-c2` at 338ba328e: both builds 0; classes (Undo, ledger, trail, `Publish*`, `UndoHistory`) 1069 passed, 1 failed, 1 skipped. The failure is `PublishAndLauncherContractTests.EveryQuestionTheMacDeployLauncherAsksIsGuardedAtTheTopLevel`, which also fails without this piece (W4c review 1, `int-n4-2`).
- Must-fail (`vm-tools/guest/899-w7a-mustfail.json`, 5 sabotages): all RED. A publish written file by file: 4 of 6 failed. A before read at make time: 1 of 6. The front page planned inside the step: 1 of 6. The trail line not written: 1 of 6. Today's in-memory undo not told: 1 of 6. After the restore, the same single unrelated failure; HEAD SAME.

## 2026-11-21 — Undo and Redo, W4c: a kept original puts a page back (#899, #949)

899 W4c: a kept original puts a page back; nothing that is an only copy is deleted

Branch `issue/899-w4c-kept-original-recovery`, on W6 (`origin/issue/899-w6-op-kinds` 368e5377d) with `origin/dev` 5cf38d656 merged in (merge commit a32ee10de; the ledger's two conflicting hunks resolved by keeping W6's built rows out and every U3b and U3c hold).

- W4c (the Mac's U3c on Windows) is built: recovery and the door's Undo and Redo put a page back from the step's own kept original (`-orig`, `-<n>-orig`) when its SHA-256 is exactly the journal's, write both of the page's contents back into the list inside the lock before the swap, keep beside the page what the list will not take, and answer "cannot tell now" (list kept) for a kept original that cannot be read just now. Every tidy (recovery's first, the settled one, a could-not-put-back closing, a closed step's, pruning's) keeps a kept original that is the only copy of what it holds. A swap never removes, overwrites or reuses a kept name: it takes the next free `-<n>-orig`, kept exclusively.
- Four trail events: "undo could not put back a change that stopped", "undo kept what a page held", "undo kept what it replaced", "undo refused for a change left part way".
- The ledger: the 4 `ActivityTrailEvents`, 12 `UndoStackCases` ("U3c: …") and 10 `UndoRecoveryCases` held under `Reason899W4c` now run from the JSON; the reason is gone. Still held: `Reason899W4cWithW7` (2 rows, W7's rollover calls) and `Reason899W4cKeptAlert` (`keptTitle`, `kept`, `showKept`).

### For W7

- **Pruning's tidy writes no folder line** (W6's final sweep, finding 3). `UndoJournal.TidyTheStagedFilesOf` (`UndoJournal.cs`, the prune's tidy, live only) passes no `onAside`, so a teacher's folder it puts back changed, or keeps as `<name> (kept by Undo)`, leaves no "undo found a folder set aside" line; the Mac writes one on every tidy (`UndoRecovery.swift`, `tidyStagedFiles`). Unreachable until a tree op goes through the door with the switch on; fix in W7, before then. (W4c made the same tidy keep only copies of kept originals.)
- **Show on Front Page through the door** is W7's; the kept-file alert (`keptTitle`, `kept`, `showKept`) connects to the door's `Refused { LeftPartWay }` and recovery's "undo kept what a page held" line, and is built only once File Explorer has been measured on a desktop session (below).
- The four U3c trail sentences are checked against `activityTrail.mustRecord`'s example lines by `UndoTrailWordsContractTests`, read from the JSON: if the Mac rewords "undo kept what it replaced" (its sweep found it untrue on one Mac path), that test goes red here until `UndoTrail.KeptWhatItReplacedWords` follows.

### Not measured in this piece

- **File Explorer and the kept file.** Not done: it needs the PC's desktop session (the SSH session cannot show or read Explorer's selection), and this piece ran out of its budget before a UI Automation probe could be written. So the alert's three keys stay held, and the brief's question (is the word "hidden" true on Windows, where a hard-link `-orig` shares its page's attributes and Explorer has no dot-file convention?) is open for W7's writer to measure first.
- An online-only OneDrive placeholder as the unreadable kept original: the replays use a real deny entry on the PC's disk (outside and inside OneDrive), not a placeholder.

## 2026-11-21 — Lane E, Windows trail lines: #946, #821, #774

### #946 (the mac's #879, #887, #791)

- **Item 1, the place.** `ActivityTrail.Place(course, section)` is the one
  place function (`activityTrail.lineShape.placeCases`): `{course}/{section} · `,
  `{course} · ` for a section of 0 or less, nothing with no course, the course
  trimmed. Both `Note(…, course, section)` and `NotePrompt` use it.
  `TrailLinesContractTests.EveryPlaceCaseIsThePlaceOfAWrittenLine` runs the
  five cases from the JSON against the function and against lines really
  written by `Note` and `NotePrompt`.
- **Callers that passed a missing section as 0, or built their own prefix:**
  - `Plantoir.Mcp/OutsideChangeGate.Refusal` (Windows' equivalent of the mac's
    `AssistToolRunner.outsideChangeHeldBack`): read a missing `section` as 0
    and then wrote the line with NO place at all. Now always
    `Note(…, course, section)`, so it reads `ICS3U · an outside assistant's … held back`.
  - `Plantoir.Core/Assist/TodaysClassOnTheFrontPage.cs` built
    `{course.Code}/{section} · ` itself, twice; now through `Note(…, course, section)`.
  - Left, and named for their owners: `ScriptRunner.cs` about line 660
    (`preview closed for a deploy` chooses between the two overloads by
    `section > 0`; harmless now, lane D's file), `Plantoir/Views/SectionDetailView.xaml.cs`
    about line 1266 (`left the front page as it was` builds `{course}/{section} · `
    itself; the section is always a real one there; the file was out of this
    lane's scope tonight), and `BuildBeforeDeployingQuestion.cs:138`, which is
    a PowerShell expression for the launcher's own `note_on_the_trail`, not an
    app line.
  - `AssistAgent.NotePrompt(text, _courseCode, _section)`: the in-app
    assistant always has its window's section; a 0 would now read `{course} · `.
- **Item 2.** `AgentGuidanceWording.AskFound` is the contract's `askFound`
  (Claude Code, Codex and GitHub Copilot). The `Owed(AgentGuidanceWordsSaidDifferently, 946, …)`
  entry and `Reason946` are gone from `NamedGapLedger.cs`; the area constant
  and its hook stay for the next such sentence.
- **Item 3.** `OutsideGreetingContractTests.EveryDoorsGreetingSaysWhatTheContractSaysWhereItSays`
  reads `key` and `where` from each `greetingMustSay` entry and checks each
  `where` as `greetingMustSayHow` defines it, over each door's real `Prepare`
  greeting in the three variants it names; an unknown `where` fails. The
  Copilot door is held by name already (`NamedGapLedger.OutsideDoorsHeld`,
  #884), so `Doors()` leaves it out. `NoGreetingOffersAHeldSkill` is replaced
  by `NoGreetingSaysWhatTheContractForbids`, which proves the
  `greetingMustNotSay` expressions on `mustMatch` and `mustNotMatch` first,
  then matches them over every message the doors compose (Revise in the
  handouts, reference and variant shapes, Fix with…, Plan a Unit…, the 18
  unit-plan greetings). No greeting needed a change.

### #821 (#780 on Windows)

- **Item 1.** New `Plantoir.Core/Models/OneLineText.cs` (`IsSpacedOut`,
  `IsRemoved`, `Cleaned(text, keepingLineBreaks)`, `CourseName`).
  `CourseConfiguration.CourseName` cleans in its getter and setter; `Write`
  cleans the stored `course_name` after the per-key merge, so a Save writes it
  cleaned whatever was edited; the New Course window cleans before it trims,
  so a name that is only controls gets the default. `UnitPlans.OneLine` now
  runs the cleaner first, as the mac does (its comment said so was owed).
  Tests: the 41 `cases` code unit by code unit with idempotence; `spacedOut` /
  `removed` pinned against the predicates over U+0000 to U+FFFF; every case
  read, set and saved through `CourseConfiguration`.
- **Item 2.** `ActivityTrail.SafeTrailLine(line, keepingLineBreaks)` is the
  one clean-and-redact function, in `trailLines.order` (redact once when
  cleaning changes nothing; otherwise redact, clean, redact). Both `Note`
  overloads, `NotePrompt` and the private writer behind `NoteClosed` go
  through it; nothing else in `ActivityTrail.cs` calls `LogRedactor`. The 14
  `trailLines.cases` run from the JSON against it, and the one-line cases
  again through a real `Note`. `knownLimits` is named in its comment.
- **Item 3.** Nothing was needed: `dev` already has `(?!\[removed: )` in
  `labelledSecret` and `bearerHeader`, and `LogRedactorTests.RedactingTwiceChangesNothing`
  already runs `redactedAgainCases` from the JSON.
- **Item 4.** `NotePrompt` builds its record with `PromptRecord`: the head line
  cleaned to one line, the sentence cleaned to one line (then trimmed, as
  Windows always trimmed it) behind `PromptPrefix`, and the record through
  `SafeTrailLine(…, keepingLineBreaks: true)`. `promptCases` (2) run.
- **Item 5.** `OutsideDoor.Clean` and its tests are unchanged.

### #774 (the headless path's task lines)

- `LauncherRunner.Run` (plantoir-mcp.exe) writes `task started` once the
  process has started and `task finished` when it exits or is cancelled,
  through a small private `TrailedTask` and shared helpers in
  `ActivityTrail.cs`: `TaskStartedWords` (the window's "started deploy.ps1
  ICS3U 2 …"), `TaskFinishedWords` and `DurationWords` (the window's
  " after 12s" / " after 3m 4s"), `HeadlessOutcome` (exit 3 is
  "stopped at a question nobody was there to answer (exit 3)", the contract's
  words; every other exit is `ScriptRunner.FinishedOutcome`'s), and
  `PlaceOfLauncherArguments` (course first, section second). A cancelled call
  is "stopped before it finished" (the runner's own sentence; "stopped by the
  teacher" would not always be true from an MCP client). A launcher that is
  missing, or a folder another Plantoir is getting ready, or a process that
  cannot start, writes "could not start {launcher} — {message}", as the window
  does. Every line carries the place, and the arguments are redacted with the
  whole line.
- `ScriptRunner.cs` is unchanged (lane D's tonight): its `NoteTaskStarted` /
  `NoteTaskFinished` are private instance methods on a ConPTY runner, so they
  cannot be called headless. The duration format is now written twice (there
  and `ActivityTrail.DurationWords`); when lane D's work has merged,
  `ScriptRunner.NoteTaskFinished` can call `ActivityTrail.TaskStartedWords` /
  `TaskFinishedWords` / `DurationWords`, and its `FinishedOutcome` may want
  the exit-3 words the mac's `outcomeDescription` has (the window's own
  `--non-interactive` runs, such as a scheduled deploy, would then say so too).
- Test: `HeadlessTaskLinesTests` runs a stub `deploy.ps1` (exit 3, 0, 1) with
  a made-up 32-hex account ID behind `--account`, and reads both lines from a
  redirected trail: no ID, the right place, exit 3 in its own words.
- **Owed to the director:** the issue asks for one MCP deploy on the Mac
  before closing, to confirm the mac's headless path writes both lines. Not
  run (no Mac work tonight).
- No new `mustRecord` event and no contract change.

### Runs (first Windows VM, 2026-11-21)

- Merged `origin/dev` at 2dcc9a722 (before proving: up to date at da5af161e)
  and again at e18157a2a (dev 10d04bfbd, Undo W6; clean merge, its new event
  untouched). At e18157a2a: the app (x64), the unit tests and the UI tests
  build; 127 + 136 tests in the touched and source-reading classes, all
  passed (`TrailLinesContractTests`, `HeadlessTaskLinesTests`,
  `OutsideGreetingContractTests`, `AgentGuidanceTests`, `LogRedactorTests`,
  `LauncherRunnerCaptureTests`, `ActivityTrailWritersTests`,
  `ActivityTrailWiringTests`, `OutsideAssistantWhilePreviewingTests`,
  `NamedGapLedgerTests`, `UnitPlansGreetingTests`, `TodaysClassContractTests`,
  `UndoWriterScanTests`, `BuildMachineLinesTests`, `ContractTests`, the
  `NewCourseDialog.cs` source scanners, `StopQuestionsContractTests`,
  `TwoWindowSettingsTests`).
- Must-fail: three sabotage commits (local branches `sab774-1`, `-2`, `-3`,
  never pushed; delete with `git branch -D`). Every new or changed test failed
  on its revert, with the case named: the place without `{course} · `
  ("no section was named"), U+202A not removed, the getter and the Save not
  cleaning ("a NUL at the end becomes a trailing space, which is kept: read" /
  ": saved unedited"), the prompt not cleaned, askFound's old words, a
  greeting saying "marks" (caught by `greetingMustNotSay`, and by `where:
  last`), exit 3 in the old words, the started line without its place, the
  unit plan's name not cleaned, and both single orders of the trail writer
  (clean-then-redact: "a NUL inside a Bearer token does not let its tail
  through"; redact-then-clean: "a NUL after Bearer does not hide the token").
- The first VM's fetched runtime predated #965, so the app build refused
  (`CheckNativeRuntimeManifest`) until `fetch-runtime.ps1` placed the
  Visual C++ runtime (`vm-tools/guest/774-app-build.ps1`). The VM was parked
  on its dev snapshot afterwards, so the next writer meets the same refusal;
  the dev snapshot wants refreshing once.

### Round 2 (review 1: M1, L1, L2)

- **M1.** `ActivityTrail.PromptRecord` cleaned the teacher's sentence before
  redacting it, so a NUL inside a token wrote the token's tail. Each of the
  record's two lines now goes through `SafeTrailLine` on its raw text
  (`trailLines.order`), then the joined record once more keeping its line
  break. Every other writer was checked: the two `Note` overloads and the
  lock-wait `Note` pass the raw line to `SafeTrailLine`; no caller cleans a
  line before handing it over (`UnitPlans.OneLine` and the course-name
  cleaning are stored values, the contract's own rule). New tests:
  `APromptIsRedactedOnItsRawTextAsEveryLineIs` (the 13 one-line
  `trailLines.cases` asked as prompts, from the JSON) and
  `ASecretSplitInsideAPromptDoesNotGetPast` (NUL inside a Bearer token,
  U+202E before an email's `@`, LF inside a token: the LF tail is the
  contract's `knownLimits`, so only the head's removal is pinned).
- **L1.** `AssistWorkspace.HowITeach.cs` (both lines) and `UnitWordRenamer.cs`
  (both lines) take their place from `ActivityTrail.Place(code, 0)`; output
  unchanged. `ActivityTrailWiringTests.NoCallerBuildsACoursesPlaceByHand`
  scans every product file for `{…Code} · `. Not caught by that scan, and not
  this lane's: `Undo/UndoRecovery.cs:93` (`line.Course + " · " + …`, the Undo
  line's) and `SectionDetailView.xaml.cs:1266` (`{code}/{section} · `).
- **L2 left as it is.** The contract (`activityTrail.mustRecord` → `task
  finished` → `why`) says the outcome tells a stop made on purpose from a
  failure but gives no words for a run ended because the client left, so the
  headless line still reads the window's "failed (exit code -1)" there.
- **Mac parity (for a mac issue, not made tonight):** `origin/dev`
  `mac-app/QuartzTeachers/Models/Assist/AssistTurnRecord.swift:107`
  (`askedLines`) cleans the prompt (`OneLineText.cleaned(prompt)`) before the
  record is redacted, the same leak.

#### Runs, round 2 (first VM, bd11f7444; dev 10d04bfbd already merged)

- App x64 and unit tests build. 74 of 74 passed in `TrailLinesContractTests`,
  `ActivityTrailWiringTests`, `ActivityTrailWritersTests`,
  `HeadlessTaskLinesTests`, `UndoWriterScanTests`, `BuildMachineLinesTests`,
  `HowITeachTests`, `UnitWordRenameContractTests`, `LogRedactorTests`
  (`vm-tools/guest/774-r2.ps1`, `774-r2b.ps1`).
- Must-fail, each reverted on the VM with `git checkout`:
  - prompt cleaned before redacted: `APromptIsRedactedOnItsRawTextAsEveryLineIs`
    "a NUL inside a Bearer token does not let its tail through" (`… [removed: token] SECRETTAIL`)
    and `ASecretSplitInsideAPromptDoesNotGetPast` "NUL".
  - prompt redacted once on its raw text, then cleaned, no pass over the
    record: `APromptIsRedactedOnItsRawTextAsEveryLineIs` "a NUL after Bearer
    does not hide the token" and `ASecretSplitInsideAPromptDoesNotGetPast`
    "bidi" (`teacher@school.on.ca` written).
  - prompt keeping its line breaks: both new tests ("a line break inside a
    page title …", "newline") and `APromptIsOneLineBehindItsPrefix`.
  - `UnitWordRenamer.cs:216` built by hand again:
    `NoCallerBuildsACoursesPlaceByHand` "UnitWordRenamer.cs:216".

## 2026-11-20 — Undo and Redo, W6: the six op kinds U2b defines (#899, #949)

Branch `issue/899-w6-op-kinds` (on W4 with its review fixes, `dev` 2ba8490e7 in it). Lenovo 20QES70500 (i5-8365U, 16 GB, Windows 11 Pro 26200) over SSH. Nothing a teacher sees changed; the switch stays off; no action goes through the door yet (W7 on).

- Reader (`UndoFormat`): `replaceText`, `editJSON`, `move`, `createTree`, `removeTree`, `external` read with the mac's shapes (`shapeIsKnown`), `opKinds.wholeOps` on the step, places compared without case, `element` and `heldBy` unreadable, a listing's hash among the blobs kept, a step of external ops alone needs no working folder.
- `UndoJson.cs` (any JSON, compared as the contract says, exactness beyond 2^53, the compact spelling), `UndoOpKinds.cs` (`UndoHunk`, `UndoJsonMember` with its byte scanner, `UndoTreeListing`/`UndoTreeReading`, `UndoLinks`, move sides, `IUndoExternalPlaces` and the app's `UndoAppSettingsPlaces`).
- Check, plan, swap and recovery for each kind (`UndoCheck.WholeStateOf`, `UndoSwapChange`, `UndoSwap.SwapAWholeOp`, `TidyLeftovers` putting a folder set aside back or keeping it as `<name> (kept by Undo)`, `-gone` before a delete, `UndoRecovery.FoldersKeptAside`, the `undo found a folder set aside` trail line).
- Contract from the JSON: all 110 `checkCases` (move sides, trees, links, preferences placed on the disk), the 5 `listingCases` and 16 `editJSONCases` (new, `UndoOpKindsContractTests`; 8 added by the fix round), U2's 19 `stackCases`, the 15 traces holding a `move`, U2's 21 `recoveryCases`. Every W6 entry left `NamedGapLedger`, `undo found a folder set aside` with them.
- PC `899w6-c3` (head 400083f60): the Undo classes 665 passed, 1 not run (the `[DenyBitesFact]` that cannot bite over SSH), 0 failed. Must-fail (`vm-tools/guest/899-w6-mustfail.json`, 20 sabotages): all red (`899w6-c1`, and `899w6-c3` for three made real: the contract's link rows and its key-written-twice row pass a reader that follows links or picks the first duplicate only because the content they lead to differs or the read-back refuses, so `AJunctionToTheVeryContentIsStillNeverFollowed` was added and the duplicate sabotage picks the last one). Killed-step harness (`Plantoir.UndoHarness kinds-kill`): 132 runs, every one whole, outside and inside OneDrive: `documentation/12-windows-app.md` → "What Windows has built: W6, the op kinds".

- **Fix round (the first review of W6, NOT CLEAN; and the final sweep of W3 and W4).** MEDIUM: `UndoAppSettingsPlaces` reads `settings.json` as it is on the disk and sets one member by replacing it exactly (lists and dictionaries whole), checked before a temporary file and one rename, nothing written on a mismatch, the running copy then given the member; the kill harness's preference is now `AcceptedSyncedFolders` in the real store (`UndoAppSettingsPlacesTests`, 6). LOW 1: editJSON byte for byte with the mac (`UndoMacKeyOrder`, `UndoJson.SpellNumber`, `UndoJson.ReadAsTheMacReads`), measured through the mac's own code and pinned as 8 new contract rows the mac's `UndoJournalContractTests` passes (this piece now touches `contracts/`). LOW 2: a file starting with a byte-order mark judged as on the mac. LOWs 3 and 4 and W4's front-page note: "For W7" below. The sweep: pruning stops at a step kept for a re-deriving recovery; the launch-call comments say W4; the owed-pieces table's corrections are below. PC `899w6f-a3` (head 6c5d2281a, `dev` 6b2a48a99 merged in): the Undo classes 681 passed, 1 not run (the `[DenyBitesFact]`), 0 failed; must-fail (`vm-tools/guest/899-w6f-mustfail.json`, 14 sabotages) all red, restored green; `kinds-kill` 132 runs, every one whole, the settings file's other member kept and no `settings.json.undo-writing` left in all 132 (no kill point falls inside the settings write itself, so this says nothing about a kill between its temporary and its rename: see fix round two), outside and inside OneDrive (settled as before: done 26, undone 22, rolled back 14, failed 4 in each place; 0.6 to 2.0 s a run). Mac (this Mac, macOS 26.7.3, Xcode 27.0): `UndoJournalContractTests` 17 of 17 with the 16 editJSON rows, and red when one new row's result is changed.

- **Fix round two (the second review of W6, NOT CLEAN: two MEDIUMs, three LOWs).** The rule now is: for an editJSON op, Windows writes exactly the bytes the mac would write, proven by a contract row run on both, or it writes nothing. M1: a key beyond printable ASCII (a new value's, a key path part, or any key of an object the path passes through) and text starting with a byte-order mark are refused (`UndoJson.IsMeasured`, `UndoJsonMember.PathIsMeasured`): cannot tell when judged, never written. M2: a file's number spelled with an exponent and more than 17 digits, or more than 38 without, makes the whole file cannot tell (`UndoJson.SpellingIsMeasured`). Also measured and matched: a negative number beyond a double's range is minus infinity on the mac (cannot tell when it is the member, judged as usual beside it); a positive one, and text holding half a surrogate pair, make the file unreadable on both (half a pair used to throw out of Windows' reader). 18 contract rows (7 `editJSONCases`, 11 `checkCases`), every result and verdict measured through the mac's own code; 13 of them carry what the mac does and Windows refuses, held by name in `NamedGapLedger` (`UndoEditJsonCasesRefusedHere`, `UndoCheckCasesRefusedHere`), where each must be REFUSED. The Python reference model (`scripts/make_undo_traces.py`) follows the same rules and holds the same 13: its test had failed on round one's 8 rows since that round (ordinal keys, Python's shortest numbers, no read-back), unseen because only the Undo classes ran. LOWs 2 and 3: tests for a stale `settings.json.undo-writing` (never read, gone after the next set) and a rename refused while the file is held open (nothing changed). LOW 1 is W8's ("For W8" below). Runs on the PC (LENOVO i5-8365U, Windows 11 Pro 26200): `899w6g-a1` at 6e3743a94 (classes, then the 26 sabotages of `vm-tools/guest/899-w6f-mustfail.json` each alone, then `kinds-kill`): all 26 sabotages red (build 0, test failed); `kinds-kill` 66 of 66 whole outside OneDrive and 66 of 66 inside it, 0 failures, A and B the same at every point; its class run had 1 failure of 726 (`WhatCanBeUndoneCanThenBeRedone` running a held row), the same 1 after the sabotages were restored. `899w6g-a2` at 901241af6 (the Undo classes): 716 passed, 0 failed, 1 skipped, 717 in all. The 9 fewer than a1's 726 are a different filter, not a lost test (review 3 compared the two `results.trx`): a1 was started with a wider `-Filter`, which took in the 8 `NamedGapLedgerTests` facts and `PythonToolchainTests.SharedPythonTestFilePasses("test_make_undo_traces.py")`, all 9 green there; a2 ran the script's default `FullyQualifiedName~Plantoir.Tests.Undo`, which matches none of them.

- **Fix round three (the third review of W6, NOT CLEAN: one MEDIUM, three LOWs).** M1: an exponent the mac does not read (more than 4 characters after the `e`, sign included, measured) makes the file not JSON on both platforms, by one rule in the contract (`undo.numberSpellingRule`, 37 `numberSpellingCases`, one `checkCases` row for `1e-0001`), held in `UndoJson` and `scripts/make_undo_traces.py` and checked against the contract by both (documentation 12 section below). L3: the 9-test gap is explained in the round-two paragraph. L1 (the Mac's runners on round two's 18 rows and this round's row) needs the Mac gate: no xcodebuild in this piece. L2 (the 13 held rows) is Russell's ruling, carried by the director. `dev` 5cf38d656 merged in (1aaa6577e; the ledger keeps W6's built rows gone and takes dev's U3b and U3c holds). PC `899w6h-a1` at 5be9984b3 (filter: the Undo classes, `NamedGapLedgerTests`, `test_make_undo_traces.py`): 814 passed, 0 failed, 1 skipped, 815; the 37 new rows, the limits fact, the 8 ledger facts and the Python file all passed. Sabotages (`vm-tools/guest/899-w6h-mustfail.json`): 1 (exponent check out) red, 13 of 37 `EveryNumberSpellingCase`; 2 (the same) red, 1 of 129 `EveryCheckCase`; 3 and 4 both went red. On this Mac `python3 scripts/test_make_undo_traces.py`: 26 OK, and with the Python check taken out red on the `1e-0001` check case and the notJSON spelling rows.

- **The integration fix (`night4/integration-2`, three tests red that pass on `dev`).** (1) Windows PowerShell 5.1's `ConvertFrom-Json` could not read `shared-rules.json`: it builds each object as a case-insensitive dictionary, and the editJSON rows added in fix round two hold objects with keys `X1` and `x1`, `Ab`/`aB`/`ab`, `E`/`e`, `A`/`a` (its message: "a dictionary that was converted from the string contains the duplicated keys 'X1' and 'x1'"). Only the launcher RUNNERS read the file that way (`test_launcher_rules.ps1`, `test_stop_preview.ps1`); the shipped launchers name it in comments only, so no teacher's launcher was affected. `editJSONCases` (23) and `editJSONCasesHow` moved, unchanged, to `contracts/undo-json-cases.json`, which no PowerShell reads; Windows' `UndoOpKindsContractTests` (through `UndoContract.JsonCases`), the mac's `UndoContractReplay`, `scripts/test_make_undo_traces.py` and the ledger area (`undo-json-cases.json → editJSONCases (refused here)`) read it there. New guards: Windows `ContractFilesWindowsPowerShellReadsTests` runs the real `ConvertFrom-Json` on every other contract file; `test_make_undo_traces.py` → `ContractFileReadabilityTests` checks the same rule on the Mac; the mac's `UndoJournalContractTests.testEveryContractFileIsOneObjectToJSONSerialization`. (2) `ActivityTrailWiringTests` did not see `UndoRolledBack` and `UndoFoundAFolderSetAside`: W6 had turned dev's `Note(ActivityTrail.Event.UndoRolledBack, …)` into `case` labels passing `line.Event` on, which the scan does not read. Both ARE written; `UndoTrail.ToTheActivityTrail` now names each on the right of a switch arm, the shape W4c already uses, so nothing is ledgered. W4c will conflict there when it takes this head: keep W4c's (a superset).

### For W8: the settings write and `AppSettings.Save` (the second review of W6, LOW 1)

`AppSettings.Save` is a plain `File.WriteAllText` that swallows every error,
called from about 24 places on the app's thread; the undo settings write
(`UndoAppSettingsPlaces.Write`) holds the undo lock, which `Save` does not
take. Three windows follow: an app save between the write's read and its
rename is lost on the disk until the app's next save; an app save between the
rename and the running copy being given the member writes the old member back
while the write says it succeeded (the file then disagrees with the journal's
`applied`, and an Undo of that step would read changed since and clear the
list); and while the write reads the file, an app `Save` cannot open it and is
silently dropped. None of this is reachable before W8 (no action writes an
external op, and recovery acts only on journal ops). **W8 owes one settings
lock taken by `AppSettings.Save` and by this write, or the write done on the
app's thread through the running copy**, together with the cross-process point
above. Also W8's: populating the running copy bypasses `ChangePreviewOpensAt`
and `ChangeCloudflareAccountId` and their events, so an open Settings pane or
a window title would not follow an undone preference. And a write killed
between its temporary and its rename leaves `settings.json.undo-writing`:
harmless (nothing reads it, and the next set writes over it and renames it in,
`UndoAppSettingsPlacesTests.ATemporaryLeftByAKilledWriteIsNeverReadAndGoesWithTheNextSet`),
but no harness kill point falls inside the write, so W8's harness adds one
there.

### For W7: shadow leftovers (the first review of W6, LOW 3)

In shadow, recovery never tidies a working folder and `TidyClosedSteps` runs
live only (the mac's rule, unchanged here). So a `removeTree` killed after its
folder went aside leaves the teacher's folder under its staged dot name
(`.<name>.plantoir-undo-<step label>-orig`), which Explorer does NOT hide (a dot name is
not hidden on Windows), and a `-gone` folder half deleted, until the switch
goes on; the same if the step is pruned before a put-back succeeds. Nothing
reaches this before W7, because no teacher action writes a tree op through the
door in shadow yet. Before any teacher action sends a tree op through the door
in shadow, W7 must prove, on the PC's disk and inside OneDrive, with the kill
harness: a take-out killed at every point, in shadow, leaves the teacher's
folder in its place or in a visible place the teacher is told about, never
under a staged name; a `-gone` remnant left in shadow is finished or reported
at the next live recovery; and pruning a shadow step never strands either.
Until W7 proves that (or the rule changes for both apps), tree ops stay out of
shadow writes.

### For W7: the "(kept by Undo)" folder is a real folder (LOW 4)

`<name> (kept by Undo)` (and `(kept by Undo 2)` and on) is an ordinary folder
beside its place, so under `courses/` it is part of the course: a build and a
deploy include its pages. That follows Russell's ruling of 2026-11-19 and the
mac; the director is telling him. No sentence on screen says it yet (the only
sentence is the trail line `undo found a folder set aside`, contract wording);
whatever sentence a teacher is first told about a kept folder (W7 on, with the
mac) must say plainly that it is a real folder that a build and a deploy
include, until a ruling says otherwise.

### For W7: the front page re-derived twice (from W4's re-review)

In shadow the door, not the action, re-derives the front page: a W7 action that
keeps its own front-page write and also routes a `recompute` through the door
writes the page twice. W7 keeps one: the action's own write, or the door's.

## 2026-11-20 — The Windows halves of the mac's #1012 and #997 (#1020, #1024)

Plan: `vm-tools/reference/night3-c-plan.md` (private setup repository).
- **#1020 (mirror of #1012): every box that showed only a placeholder has a name of its own**, the mac's words, the placeholder kept as the hint: the assistant's box "Ask about this section"; the console's answer box and a plain question's answer box "Your answer"; the credential field by the label printed above it; Class Dates' dates box "Class dates", sheet link "Google Sheet address" and source "Where these came from"; the sidebar's rename box "Course code" and filter "Filter"; the list editor's add field "New folder name" or "New file name" and its rename field "New name"; both footer boxes "Footer"; both deploy-folder boxes "Folder". `AboutDialogLinksSourceTests` now pins each About link's address too (the 993b review: the old pattern took any address). Tests: `PlaceholderFieldNamesSourceTests` (9), `PlaceholderFieldNamesUiTests.EveryBoxThatShowedOnlyAPlaceholderHasANameOfItsOwn`.
- **#1024 (mirror of #997), what applied:** the sidebar's row text trims with an ellipsis and a course code cut short carries the whole code as its tooltip and help text (`ACourseCodeCutShortShowsTheWholeCode`); Class Dates opens with the keyboard in the dates box, opened from the menu by the keyboard or by UI Automation (a pointer open was not measured), and only the dialog's own first placement is moved there, so focus sent by Narrator or UI Automation stays where it was sent; Tab moves on to "Where these came from" typing nothing (`TabLeavesTheDatesBoxAndTypesNothing`, `FocusSentByAssistiveTechnologyStaysWhereItWasSent`, `OpenedFromTheKeyboardTheSheetStartsInTheDatesBox`). What did not apply, and why, is below.

## 2026-11-20 — #899 U4a, Course Settings, Add folder and Set School Year (notes for W8)

- Mac U4a: Course Settings' Save, Add folder and Set School Year are each one step through the door (`saveCourseSettings`, `addFolder`, `setSchoolYear`). Windows owes the same in W8.
- `undo-action-steps.json` has 25 steps; the three new ones carry `members` (editJSON) and `trees` (createTree). `undo-traces.json` has 150 action traces (the first 132 unchanged).
- New contract text: `shared-rules.json` → `undo.wording` (8 sentences), `undo.rule.shadow` reworded, `activityTrail.mustRecord` "undo could not record a step" `carries` reworded, one new stack row, one stack row renamed; `class-planning.json` → `todaysClassOnTheFrontPage.wording.keptGone`.

## 2026-11-20 — #899 U3b, the rollover, fix round four (notes for W7)

Nothing new for Windows to show yet: the rollover as one step is W7. When W7 lands, its PROGRESS line should say the rollover moves only what must move (documentation/12 → "The rollover, U3b fix round four") and names every kept file through one chooser.

## 2026-11-20 — Undo and Redo, W4: the switch, off, and the list wired to the app's processes (#899, #949)

Branch `issue/899-w4-switch` (on W3, `dev` 2ba8490e7 merged). Lenovo 20QES70500 (i5-8365U, 16 GB, Windows 11 Pro 26200) over SSH, the window in the desktop session through a scheduled task. Nothing a teacher sees changed; the switch stays off; no action goes through the door yet (W7 on).

- `Plantoir.Core/Undo/UndoSwitch.cs`: `UndoJournalIsLive = false` (a `static readonly` field, never a setting), `UndoRefusedForMissingContentClearsTheList = true` (ruling 22, read by the door's refusal answer), `CurrentMode`.
- `Plantoir.Core/Undo/UndoForThisProcess.cs`: the composition root, the only reader of the switch and of `UndoJournalLocation` for Undo. One `UndoProcessMemory` and one `UndoJournal` per process, a `Door()` per action with the real trail sink. `UndoAtLaunch.Recover()` runs recovery at launch on a thread of its own and never throws; called once from `App.OnLaunched` (after `--state-dir` and the marketing scenes, before the windows) and once from `plantoir-mcp`'s `Program` (after `--state-dir`, before the host).
- Shadow made total: with the switch off, ANY failure of the list (not only disk and permission errors) lets the teacher's change go ahead unrecorded, at the begin, at the closing and when a step is given up. A step given only as its ops is refused (`couldNotRecordTheStep`) before anything changes in either mode, as on the mac.
- The writer scan (`UndoWriterScanTests`, the mac's): 75 product files that write, each `door` (5), `notAStep` with its reason (37) or `waitsFor` (33: W7 8, one of them also W8; W8 21; W9 3; W11a 1); a new writer or a stale count fails; `TheSwitchStaysOffWhileWritersWait`. `TaskScheduling.cs` waits for W8 by ruling 23 (the mac's entry still says held, M10).
- W3's review lows 2, 3 and 4 and the final sweep's recompute finding fixed, each with a test.
- W4's own review (one MEDIUM, four LOWs), each fixed with a test that fails without it (`vm-tools/guest/899-w4r-mustfail.json`): a shadow step whose list failed re-derives the files a rule keeps true, as the recorded path does (MEDIUM); recovery at launch that cannot have the list says why in the window's startup log (`UndoRecoveryRun.NotRun`); the writer scan sees a launcher run by its constant (`Workspace.MarkerLauncher`, `DeployCommand.ScriptName`), a tool at the start of a command line and a zip made or updated (`ScriptRunner.cs` now listed, W8); a page held with no read sharing during recovery is a file in use, never cannot tell; every door the process makes has the app's own front-page runner (`UndoSectionFrontPage`, Windows' publish rule through `AssistWorkspace.RederiveTheFrontPage`), so a draft holding a recompute is never refused for want of one. On the mac the runner is registered with the switch (U7); on Windows it is given from W4, because a shadow step's door makes the change itself.
- Tests: `UndoShadowTests` (13), `UndoForThisProcessTests` (7), `UndoWriterScanTests` (5), `UndoRecoveryReviewFixesTests` (3), `UndoDoorTests` extended. PC `899w4-c1`: the Undo classes (contract classes included) 639 passed, 1 not run (`UndoWebsiteContractTests.ARecordFolderThatDeniesListingCannotTell`, a `[DenyBitesFact]` that cannot bite over SSH), 0 failed. Thirteen must-fail proofs, every one red (`899w4-mf1`, `899w4-mf2`; `vm-tools/guest/899-w4-mustfail.json`).
- The real `plantoir-mcp.exe` and `Plantoir.exe` find one list, under `--state-dir` and under the default, and settle at launch a step a killed process left (`899w4-p1`): `documentation/12-windows-app.md` → "What Windows has built: W4, the switch".

## 2026-11-20 — Escape stops a running preview or deploy, with the mac's stop question (#1009, the mac's #988)

Branch `issue/1009-win-stop-by-keyboard`. Built and tested on the Windows VM (Parallels, Windows 11 Pro ARM64, the app win-x64 under emulation), not on the PC.

- The console's visible Cancel holds Escape through a `KeyboardAccelerator` on the button (no hidden control, and no key handler gives Escape its action; the only key filter is on the visible stop question, which drops a held Escape's repeats and acts on no key), decided as each key arrives: not while an editable text box has the focus, a dialog is up, the preview's site covers the console, or Cancel is off screen. A preview stops at once; a deploy asks "Stop the deploy?" (Stop Deploy the default, Cancel on the right) with "Don't ask again", counted only with Stop. File ▸ Settings ▸ Deploying opens with Stopping. Trail: `stop question setting changed`, off the ledger.
- The words moved into `shared-rules.json` → `stopQuestions` (added from Windows; both apps now run its cases: Windows' and the mac's `StopQuestionsContractTests`). Windows' footer names Escape alone: Windows has no Command-Period.
- Not built: "Stop this share?" has nothing to stop until #824. Tests: `StopQuestionsContractTests`, `StopByKeyboardUiTests` (9 real-key tests since the second review, each red under its sabotage). Details: documentation/12, "Escape stops a running preview or deploy, and the stop questions (#1009, the mac's #988)".
- First review's fixes: the console's own Stop goes the way Cancel goes (asks, is swept, reads "Cancelled"); every stop decision reads one "under way" rule (`ScriptRunner.IsUnderWay`: running, or between a leg's build and its deploy), so the question stays across that change and a press in the gap asks; an open Settings follows the question's Don't ask again; a held Escape's repeats no longer answer the question it opened (measured: they did, up to 4 holds of 4).
- Second review's fixes: the panel's one rule also counts the whole deploy run (`MultiDestinationDeployRunner.ShownTaskIsUnderWay`), so between two destinations the question stays, Cancel shows and a press asks, and a cancel there starts no later leg; `RunAsync` clears every leg's `IsBetweenPhases` when it ends, however it ends; the console's Stop in the New Course wizard now stops with `CancelByUser` ("Cancelled"), not `Terminate`.
- Third review's fixes: a stopped deploy is never every destination deployed (a destination the stop kept the run from reaching counts as not deployed: no published stamp, and the window and the assistant hear `deployPartiallySucceeded` naming it), as `stopQuestions.aStoppedDeploy` says, run by both apps; a stop once the last leg has ended stops nothing (`CanStillBeStopped`); no outcome badge beside Cancel between two destinations; a throw in `RunAsync`'s ending still ends the run; `StopByKeyboardUiTests` deploys only to folders in its own temp tree, never a real account.
- Fourth review's fixes: `dev`'s #1016 merged in (the gaps are now one turn of the window's thread; every gap path re-read and re-tested); `RunAsync` checks `WasCancelled` immediately before each `Run`, so a cancel as a leg is announced keeps it from starting; the contract case "stopped during the second of three" (a sentence the mac now says differently); the text-box UI test runs on a held deploy, where no site draws (measured: the box keeps the focus as the site draws; the site drawn inside the test's presses was the race); destinations held by the test (`HeldDestination`) replace the stale-file padding, and the multi-destination test uses three folders.
- Fifth review's fixes: a stopped task is recorded as stopped whatever the launcher exited with. Escape or Cancel on a preview sends Control-C and `preview.ps1` ends its serve with exit 0, and the trail line read "finished preview.ps1 — succeeded". `ScriptRunner.FinishedOutcome` now takes the mac's order (`ScriptRunner.outcomeDescription`): stopped by the teacher, closed for a deploy, backed out at a question, then the exit code ("succeeded", or "failed (exit code N)"). Test: `StopQuestionsContractTests.AStopIsRecordedAsAStop_WhateverTheLauncherExitedWith` (the function over exit codes 0, 1 and -1, and a staged runner cancelled by the teacher that ends with exit 0, whose trail line must read "— stopped by the teacher"); red with the exit code checked first again. A stale comment on `IsBetweenPhases` no longer names the 100 ms poll #1016 removed. Proven on the first Windows VM (Parallels, Windows 11 Pro ARM64, the app win-x64 under emulation), 2026-11-20, commit 4dd3908d0: `StopQuestionsContractTests` 21 of 21; the new test red under the sabotage ("Expected: stopped by the teacher, Actual: succeeded"); `StopByKeyboardUiTests` 9 of 9 ten times in a row (4 m 53 s to 10 m 31 s a run), so `EscapeStopsARunningPreviewAtOnce`'s earlier unexplained failure did not recur in ten.

## 2026-11-20 — Section and Classes, drawn from the contract (#990, grouping A)

Branch `issue/990-section-and-classes-menus`, both platforms in one piece. Windows 11 VM (Parallels, ARM64, x64 under emulation).

- The Section menu splits in two (Russell's ruling of 2026-11-20): **Section** (Preview, Preview at Last Viewed, Rebuild Preview, Open in Browser · Publish Class for a Date…, Publish Pages…, Hide Pages…, Publish Pages That Links Lead To…, Undo Last Change, Undo Getting Ready… · Deploy…, Schedule Deploy…, Remove Scheduled Deploy · Revise With ▸ · Open in Obsidian, Show in File Explorer, Open in Terminal · Remove Section) and a new **Classes** menu after it (Add Next Class · Class Dates…, Re-date Classes…, Make Room for Classes… · Get Ready for the Start of the Year…). Menu bar: File · Course · Section · Classes · View · Help.
- Both menus are drawn from `Plantoir.Core/Models/SubjectMenuLayout.cs`, the contract's `subjectMenus.layout` less this app's named gaps (Stop Showing Deployed Folder #889, Copilot #884, Roll Over #954; Add Class… drawn as Add Next Class until #927). Keys unchanged but one: Copy a Page from This Course… takes Ctrl+Shift+K (ruled), checked against every key in the app.
- Remove Section and Remove Scheduled Deploy lost their ellipsis (they only confirm), in the menu bar and the row's menu. The trail's menu path follows the item ("Classes ▸ Re-date Classes… — carried out").
- Tests: `SubjectMenuLayoutContractTests` (new, 5), `RemovalQuestionsContractTests` (source check moved), `SectionAndClassesUiTests` (new, 2, in `MenuBarUiTests.cs`). Unit suite in the VM: 4,677 tests, exactly the six known VM failures.
- Review round (Russell's ruling "name the real menu"): the copy the menu's server saves before a Classes item is `_classes-section<N>`, "before a change from the Classes menu", with "the Classes menu backed up the course as …" on the trail; the window sends the menu in the call's `_meta` (`plantoirMenu`), so no tool schema changed. `NothingToUndoFromTheMenu` and `SectionIsChangingFromTheMenu` say "the Section or Classes menu". A layout item with no words now fails a contract test. The UI test reads separators by gap because WinUI gives a `MenuFlyoutSeparator` no UI Automation element (raw view measured). New: `SectionMenuServerTests.ACopyBeforeAClassesItemIsNamedForTheClassesMenu`, `SectionVerbsUiTests.AddNextClassFromClassesSavesTheClassesMenusCopy` (end to end).
- Details: documentation/12, "Section and Classes, drawn from the contract (#990, grouping A)".
- **Meetings in a club** (Russell, 2026-11-20 evening, on #990: "in a club the menu itself is titled Meetings, on both platforms, so no sentence a club's teacher reads says 'class'"). Classes ▸ is titled Meetings while the selected course's pages are meetings (`class_noun`), live: `ApplyMenuEnablement` sets both layout menus' titles from `SubjectMenuLayout.Title(menu, noun)`, which has no default. The contract carries `subjectMenus.layout.menus[].titleForAMeeting`. Backups (`DescriptionFor`, `SubtitleFor`, `KeptDescriptionFor`, the All Backups column), the menu copy's trail lines (`MenuBackedUpLine`/`MenuCouldNotBackUpLine`), the "ran from a menu" path (`SectionVerbDialog.MenuPath(item, noun)`) and the refusal `SectionIsChangingFromTheMenu(course, section, noun)` (new key `sectionIsChangingFromTheMeetingsMenu`) name the Meetings menu in a club. UI test: `SectionAndClassesUiTests.TheClassesMenuIsTitledMeetingsWhileAClubIsSelected`.
- **No default menu** on `BackupMaker.Menu(SectionNumber, InMenu)` or `SectionVerbs.Perform(…, menu, …)`: a caller that forgets it does not compile.
- **Separators read without a pixel margin**: `SectionAndClassesUiTests.SeparatorGaps` splits the gaps at their widest jump and requires the jump to be wider than the spread inside either set, so the same rule reads every scaling; plain facts in `SeparatorGapsRuleTests`.

## 2026-11-20 — the preview's wait is woken by the run (#1016, the mac's #998)

Branch `issue/1016-win-timed-polls`. Lenovo 20QES70500 (i5-8365U, 16 GB, Windows 11 Pro 26200) over SSH.

- Before the launch line and the address, `WaitForPreviewServer` no longer looks once a second: `ScriptRunner` collects "Launching Quartz preview" and "Started a Quartz server" as lines arrive (as it already did the address), and a `StandingWatch` wakes the wait on the run's next change of standing or when the 45 s quiet bound runs out. The transcript is no longer stripped and searched each second. The HTTP tries keep their second (#1011).
- `WaitUntilFinished` and `WaitUntilFinishedOrKill` end on `FinishRun` instead of looking every 100 ms; the force-finish bound stays.
- Nothing to replace for #998's other two shapes: Windows restores each window from its own remembered entry, and no view polls for its window.
- Every timed wait in `Plantoir` and `Plantoir.Core` was inventoried with a verdict (47 rows: 31 kept, 3 replaced here, 13 owed, the ContentDialog slot nine of them). The owed list and the reasons: documentation/12, "What the preview's wait waits on (#1016, the mac's #998)".
- Measured (throwaway test, this PC): the old look cost 0.04 to 0.47 ms a second (300 to 4,000 lines); the new wake on the launch line, median 0.027 ms where the old loop resumed up to 1 s later. Unit suite `1016-full1`: 4,659 tests, exactly the six known failures. Sabotage run `1016-sab1` (the watch woken by any property, `WaitUntilFinished` polling again, the view searching the transcript): 4 of the 11 fail, each sabotage caught.
- Tests: `PreviewWaitWakesOnTheRunTests` (11). No `mac` issue: the mac already has the same design (#998); nothing shared changed.
- UI tests in the desktop session (the console, 1280 x 720): `PreviewStartPageUiTests` 4 of 4 (4 m 3 s), `PublishToFolderUiTests` 1 of 1, `WizardToPreviewUiTests` 1 of 1, `ReturningToASectionMidDeployUiTests` 1 of 1.
- After the first review: each posted finish carries its run's number, so the build's late second finish can no longer end the deploy leg started on the same runner (it finished the deploy with the build's exit code and reported the leg a success); `FinishRun` takes the run's task before notifying; the bounded wait force-finishes only its own run. The launch and server lines are read in the unfinished line too (the server line is the last before a quiet server). `QuartzLaunchLine` pinned to the contract's marker and to `build_site.py`'s print. Sabotage run `1016-sab2` (the three fixes undone): 7 of the new tests fail. Unit suite `1016-full3`: 4,671 tests, exactly the six known failures. `PreviewWaitWakesOnTheRunTests` now 21. Desktop session: `PublishToFolderUiTests` 1 of 1 (`ui-1016-publish2`, the real build then `deploy.ps1 --to-folder`); `PreviewStartPageUiTests` 4 of 4 on a throwaway branch whose preview wait wrote a line the first time it read `ServerStartedAt` set: two real previews each wrote one (`ServerStartedAt` about a second before the read, `launched=True`, the next step TryTheAddress). In both, Quartz's last output, "hint: exit with ctrl+c", had no line end yet, which is the case the unfinished-line reading covers.
- After the second review: a finish claims its run in one compare-and-exchange (`_unfinishedRun`), and the bounded-wait test starts the next run inside the first run's finish, so it no longer depends on thread timing (sabotage `1016-sab3`: it fails with the fault back). The rule reading a run that set only `LaunchProblem` as over was withdrawn: it took the console down with the sentence in it. A window test for it could not be built, because a `preview.ps1` missing before the press is refused earlier, by the press's own check (logged only, not shown). Unit suite `1016-full5`: 4,672 tests, exactly the six known failures; `PreviewWaitWakesOnTheRunTests` 22.

## 2026-11-20 — a dimmed Fix with button's reason reaches a mouse user (#1017)

Branch `issue/1017-win-fixwith-tooltip-and-test`. Lenovo 20QES70500: unit suite over SSH, UI tests in the desktop session.

- The tooltip on a dimmed Fix with button never showed: WinUI 3 has no `ShowOnDisabled`, and a disabled control handles no input itself. Each button now sits in a `Border` of exactly its box that owns the tooltip; `HelpText` stays on the button. Measured with a real pointer: before, the sidebar's + showed its tooltip and the dimmed Fix with Codex… none; after, "Not set up on this PC." shows above it, on screen and to UI Automation.
- `FixWithButtonsUiTests`: the Codex door's six `-c` pairs checked by name (it expected 12 arguments; #884 made it 14 on purpose), and a new test of a Codex this PC lacks: drawn, dimmed, its help text, and the tooltip on hover. `ReviseWithPresenceTests`: `ApplyMenuEnablement` dims a missing door and never hides it. `SectionProblemsSourceTests`: the tooltip stays on the frame.
- Details: documentation/12, "Revise With: dimmed in the menu bar, hidden in a row's menu (#990)".

## 2026-11-19 — a missing assistant dimmed in the menu bar and on Fix with (#990, the mac's D11 and Q14)

Branch `issue/990-menus-windows`, on the mac's `issue/990-menus`. Lenovo 20QES70500 over SSH.

- Fix with Claude… / Codex…: both drawn on every live course, each enabled only when its assistant is installed and a row is handed over (`buttonCases`' `claudeEnabled`/`codexEnabled`); a missing one says "Not set up on this PC." to Narrator (its `HelpText`) and, since #1017, as a tooltip on the button's frame, seen on the PC's screen with the pointer resting on the dimmed button (a tooltip on the disabled button itself never showed). The contract's second sentence (Settings ▸ Other Assistants) is held by name against #903, which builds that page.
- Course ▸ and Section ▸ Revise With ▸ Claude… and Codex…: always drawn, dimmed when not installed (`SubjectMenuRules.EnabledInTheMenuBar`, re-read on `OutsideAssistantPresence.Changed` and at the click). A row's context menu still hides them.
- Course ▸ Rename's grey reason line is gone (ruling Q14); the row's context menu keeps its notes.
- Not on Windows, so nothing done: Set Up an Assistant… (no set-up until #903, so no Help item to remove), the deployed folder's context-menu group (#889).
- Shortcuts unchanged; whether Windows follows the mac's ⌘Y / ⇧⌘K is a question for Russell (Ctrl+Y is Redo). Tests: `ReviseWithPresenceTests` (new), `FixWithAssistantContractTests`. Details: documentation/12, "Revise With: dimmed in the menu bar, hidden in a row's menu (#990)".

## 2026-11-19 — the installer opens on a Licence Agreement page (#1010, piece 1010b)

Branch `issue/1010b-installer-licence-page` (on `night2/integration-2`). Built and proven on the Windows VM (Parallels, Windows 11 Pro ARM64, the installer x64 under emulation), not on the PC.

- Russell's rulings of 2026-11-19 (option A): Inno Setup's License Agreement page, first, titled "Licence Agreement", with Plantoir's MIT text (a new root `LICENSE`, carried word for word), the third-party notice and the terms for Microsoft's `vcruntime140.dll`; neither choice made when it opens, Next disabled until "I accept the agreement"; skipped by Plantoir's own `/VERYSILENT` update, so a teacher already on 1.x is updated silently and not asked (ruling 5); a newer installer run by hand asks again. The notice is installed as `{app}\THIRD_PARTY_LICENSES.txt`, and the portable zip carries it and `LICENSE` beside the app (ruling 6).
- Keyboard (first review's MEDIUM): clearing both choices had taken them out of the Tab order; the refusal gets the pair's Tab stop back, so Tab lands on "I do not accept" (Next stays disabled) and the up arrow chooses "I accept the agreement". Measured key by key on the VM (documentation/12).
- The first-install rehearsal's driver chooses "I accept the agreement" by name and stops PRODUCT STOPPED if it cannot, or if an install of 2.0.0 or later never showed the page; a choice whose state it cannot read is DRIVER PROBLEM, never "not chosen".
- Second review: the terms for `vcruntime140.dll` are in `THIRD_PARTY_LICENSES.md` too (a section that says only the Windows app carries the file), so the zip's and `{app}`'s notice carry them; the same words as the page, held equal by a test. The driver reads a refusal it cannot find as DRIVER PROBLEM, and gains `--self-test-install <file>` (step 2 alone on an installer already on the machine, never PASSED) so `AnswerLicencePage` can run before a signed candidate exists.
- Tests: `InstallerLicencePageTests` (12 facts, 1 theory), `WindowRulesTests` (9: 2 at first, 5 since the first review, 2 since the second). No `mac` issue: the Mac has no licence screen and carries nothing of Microsoft's. Details: documentation/12, "The Licence Agreement page in the installer (#1010)".

## 2026-11-19 — the About panel's links are links of their own (#993, the mac's D46)

Branch `issue/993b-about-window-links`. Built and tested on the Windows VM (Parallels, Windows 11 Pro ARM64, the app win-x64 under emulation), not on the PC.

- As Russell ruled for the mac (option A): the sponsor sentence whole and plain with "Quartz" and "Sponsor Jacky Zhao on GitHub" beneath it; Icon, Design and Made with as label-and-value rows like Website and Email. Each of the six links is a `HyperlinkButton` of its own with an AutomationId, in place of inline `Hyperlink`s.
- `AboutDialogLinksSourceTests` (4 facts) and `AboutDialogLinksUiTests` (opens Help ▸ About Plantoir; six Hyperlink elements, enabled and focusable, Tab reaches each). Details: documentation/12, "The About panel's links (#993, the mac's D46)".

## 2026-11-19 — the question dialogs' keys follow the mac's #973 and #987 (#979)

Branch `issue/979-windows-question-dialogs`. Proven on the Windows VM (Windows 11 ARM64 in Parallels, the x64 app under emulation), not yet on the PC.

- **Measured first:** the quit question, with no default since #987, opened with the focus on Quit Anyway, so Enter quit; WinUI focuses the first button in the row when nothing in the content can take the focus. Escape while a course was being made closed the wizard; Enter on a complete form made nothing.
- `DialogButtons.AskWithNoDefault`: no default, the focus moved to Cancel when the dialog opens. Twelve questions use it; eight of them had Cancel as the default until now (Remove, the three deletes, the assistant's put-back, a list entry's Remove, Get Ready's go-ahead, and Get Ready's undo when nothing would go back, whose Undo is otherwise the default).
- New Course: Create Course is the default once the form is complete and no code list is drawn; Escape does nothing while the course is being made (`QuestionKeys`, the mac's two rules).
- Tests: `QuestionDialogScanTests` (unit), `QuestionDialogKeysUiTests` (4 real-key tests, 3 red before, 4 green after). Ledger: nothing held for #973 or #987, so nothing removed.
- Ruled by Russell (2026-11-19): keep Windows' own button order, go-ahead left and Cancel right; on a question with no default the focus starts on Cancel and Enter or Space cancels. `documentation/12-windows-app.md` → "The question dialogs' keys (#979)".
- **After the review (NOT CLEAN, two MEDIUM, four LOW), 8e099e291:** the wizard's `LayoutRoot` Escape catcher is gone: while the course is made Cancel is the Secondary button and `Closing` refuses a close with no answer (measured on the VM: Escape does nothing then, a click on Cancel stops it, Escape closes afterwards). Create Course is plain (`PrimaryKind.NotTheDefaultYet`, no default, no accent) until it is the default. The update offer's Escape catcher is deleted (Escape still closes it, `UpdateOfferUiTests`). Undo Getting Ready is greyed when nothing would go back. `AskWithNoDefault` keeps the go-ahead out of the tab order until the dialog is open, so it never holds the first focus. The scan sees `new() { }` dialogs.

## 2026-11-20 — Undo and Redo, W3: recovery (#899, #949)

Branch `issue/899-w3-recovery` (on W2b). Lenovo 20QES70500 (i5-8365U, 16 GB, Windows 11 Pro 26200) over SSH. Core only: nothing calls it, nothing a teacher sees changed, the built-in assistant's surface did not move; the switch stays off.

- `Plantoir.Core/Undo/UndoRecovery.cs`: a step whose work stopped part way settled by content (failed, completed, rolled back, or interrupted with the list cleared; shadow writes nothing into a folder), the refused-swap schedule (at once at an Undo, a Redo or `UndoDoor.Recover`; otherwise one minute, doubling, at most an hour; a step pruning would close tried at once), the closed-step tidy, re-derivation on settle, the `undo rolled back` trail line (`ActivityTrail.Event.UndoRolledBack`; the ledger entry is gone). Run in the begin hold, the Undo/Redo hold, before every prune (pruning refuses a hold without it) and by `Recover()`.
- W2b's eight review LOWs fixed, each with a test: a reversal that did not go in leaves the step in flight (abandoned, settled by this process's next recovery), staged files hold their folder in place during the swap, the identity check before the rename, read-only never cleared on a link to the page, blobs asked again inside the begin hold, an ops step with no folder refused, recovery before every prune, Pinned/Unpinned carried.
- `recoveryCases` from the JSON: 20 run, 21 (U2b's kinds) held on the ledger for W6. The harness's kill test (233 pages, 14 kill points of a step, an undo and a redo, recovery by a second process, the recovery itself killed and run again), outside and inside OneDrive: `documentation/12-windows-app.md` → "What Windows has built: W3, recovery".

## 2026-11-20 — Undo and Redo, W2b: the staged swap and the door (#899, #949)

Branch `issue/899-w2b-staged-swap-door` (on W2a, `dev` 8f3f64349 merged). Lenovo 20QES70500 (i5-8365U, 16 GB, Windows 11 Pro 26200) over SSH. Core only: nothing calls it, nothing a teacher sees changed, no trail line, the built-in assistant's surface did not move; the switch stays off.

- `Plantoir.Core/Undo/`: `UndoSwap` (staged beside each page, then one POSIX-semantics rename each, MoveFileEx only on 87/50; re-read, read-only refused `couldNotWrite`, attributes and creation time kept, the hard-linked original read back after the rename; reversed on any refusal; nothing staged left), `UndoPlaces` (containment and the volume by a handle's final path), `UndoDoor` (step from files or from ops, undo, redo, clearing, dropping, the flip's clearing; blobs and begin in one hold that never prunes), `UndoLineOps`/`JournaledSetting` moved into the product, pruning's tidy of an unsettled step's staged files. The test scribe now goes through the door; `stepCases` run with a real holder.
- W2a's six review LOWs fixed, each with a test that fails without it. Sixteen must-fail proofs on the PC (`vm-tools/guest/899-w2b-mustfail.json`).
- Measured outside and inside OneDrive, and the two-process kill test (233 pages, six kill points, every page whole): `documentation/12-windows-app.md` → "What Windows has built: W2b, the staged swap and the door".

## 2026-11-20 — Undo and Redo, W2a: the lock, the store, blobs, reading on, pruning carried out (#899, #949)

Branch `issue/899-w2a-lock-store-pruning`. Lenovo 20QES70500 (i5-8365U, 16 GB, Windows 11 Pro 26200) over SSH. Core only: nothing calls it, nothing a teacher sees changed, no trail line, the built-in assistant's surface did not move; the switch stays off.

- `Plantoir.Core/Undo/`: `UndoLock` (`LockFileEx` without `LOCKFILE_FAIL_IMMEDIATELY` on a `CreateFileW` overlapped handle, cancel-then-wait on a timeout), `UndoProcessMemory` (shadow try-once, closings kept for a busy lock; an object, never a static), `UndoJournal.WithLock` / `Prune` / reading on, `UndoJournalWriter` (sorted keys, LF, no BOM, 4 MiB segments, `FlushFileBuffers` every hold that wrote, blobs by a no-replace move, `WriteBlobs` four at a time), `UndoFileIdentity`, `UndoJournalLocation`. A reading that is not fresh inside the lock refuses the hold.
- `UndoScribe` now writes through the real store, so the stack cases and traces W1 walks run through the lock, append, segments, blobs and deletion. New: `UndoLockTests` (8), `UndoStoreTests` (18), `UndoPruningCarriedOutTests` (4); six must-fail proofs red and restored.
- Measured outside and inside a signed-in OneDrive with `Plantoir.UndoHarness` (in no solution): 1,600 of 1,600 live holds from 8 processes; a killed holder's lock granted in about 24 ms; `FlushFileBuffers` 0.9 ms; reading on at 10.6 MB 35 to 64 ms against 360 read whole; a 233-page step's 466 blobs held the lock 1.3 to 1.5 s one at a time, 0.4 s four at a time. `documentation/12-windows-app.md` → "What Windows has built: W2a, the lock and the store".

## 2026-11-19 — Undo and Redo: the mac's U2b rows met by the W1 reader (#899)

Branch `issue/899-u2b-op-kinds` (the mac's U2b, with `dev` merged in). Lenovo 20QES70500 over SSH.

- Held on the named-gap ledger against #899 for W6 (the six op kinds and `recompute` run): 60 `checkCases`, 19 `stackCases`, 15 traces. Each held row must still fail for its named gap and fails the day it passes, proved on a real held row of each kind; a check case whose `current` cannot be placed yet is judged on a placeholder while its op cannot be read, so the nine such rows that expect `notReadable` are met, not held (the review's MEDIUM). The 15 held traces are asserted only to their first `move` (002, 012 and 020 check nothing): coverage W6 restores. `documentation/12-windows-app.md` → "What U2b's rows met here".
- Built (W1's part): a page that cannot be read for any reason but a sharing or lock violation is `cannotTell` (refused `cannotTellNow`, list kept), the contract's two `cannotBeRead` rows on known kinds. Pinned before content missing; a real deny-read ACE test, which runs and passes over SSH on the PC (`899u2b-win-11`).

## 2026-11-19 — never closes Obsidian without asking (#1003, the mac's #995)

Branch `issue/1003-windows-obsidian-never-quit-unasked`. Built and tested on the Windows VM (Parallels, Windows 11 Pro ARM64, 4 CPUs, 12 GB; the app is win-x64 under emulation), not on the PC.

- Every route that hands Obsidian a file asks "Close Obsidian to open {course}?" before closing a running Obsidian that has never seen the course: the menus, both toolbars, the assistant's press, a course kept for reference, and Course Settings' How I Teach row (the last two used to call `FolderActions.OpenInObsidian` directly and now take the route's `OpenWithoutTheScanAsync`). `FolderActions.OpenInObsidian` never closes Obsidian; the close is `FolderActions.CloseObsidianAndRegister`, on the answer only.
- The add-ons offer's yes reads "Close Obsidian and Add Them" when it closes Obsidian; a course opened in Obsidian while the offer was up goes to the reopen question; the reopen button is "Close and Reopen Obsidian" (ruling 1 on #995). An answer that cannot finish shows "Could not open {course} in Obsidian" (ruling 2 on #995, `couldNotOpen`, Windows first; the mac owes it).
- `ObsidianNeverClosedUnaskedTests` (new) and the "#1003" block of `ObsidianOpenRouteTests`; checked by mutation on the VM. Details: documentation/12, "Windows never closes Obsidian unasked (#1003)".
- Ledger: "asked to close Obsidian to open a course" (#1003) removed; Windows records it.

## 2026-11-14 — Undo and Redo, step 8: was what a move takes back already deployed? (#899 piece W5, #949)

Branch `issue/899-w5-was-it-deployed`. Lenovo 20QES70500 (i5-8365U, 16 GB, Windows 11 Pro 26200). Core only, behind nothing because nothing calls it: a teacher sees no change, and the built-in assistant's surface is untouched.

- `Plantoir.Core/Undo/UndoWebsite.cs`: `Answer` is `undo.rule.deployed`, pure (no clock, no statics); `Inputs(course, section)` reads the published-pages record (`.publish_state\section<N>.published-pages\`, newest fragment per destination only), the destinations from `course_config.json` (`local_folder` → `folder`, `cloudflare_pages` → `cloudflare`) and the markers `DeployCommand.FirstDeployMarkerPath` names. W10 (U6) will call it to offer a deploy.
- `UndoWebsiteContractTests`: the 18 `deployedCases`, pure and through a real course folder; `Proposed_` tests for what the contract does not say (an unlistable record folder, a fragment's version, a non-page op path, a never-deployed content change, an unknown destination type). Nineteen sabotages each turn named cases red. `documentation/12-windows-app.md` → "Step 8 built: was it deployed?".
- Ledger: nothing added or removed (no #899 entry exists on `dev` for `deployedCases`, which were unrun rather than red).

## 2026-11-14 — Undo and Redo, W1: the journal READ, folded, limited and checked (#899, #949)

Branch `issue/899-w1-reading-the-journal`. Lenovo 20QES70500 (i5-8365U, 16 GB, Windows 11 Pro 26200), other agents sharing the CPU. Nothing a teacher sees changed, nothing writes a journal, no trail line, the built-in assistant's surface did not move.

- `Plantoir.Core/Undo/`: `UndoFormat` (lenient, keeps what it cannot read), `UndoFold` (`folding.moves` as text), `UndoLimits.Offer`, `UndoPruning` (pure decisions), `UndoEntries` and `UndoCheck` (a read that fails is never "changed since": it ends as `fileIsInUse`, proposed to the mac), `FolderIdentityFile`, and `UndoJournal`, an instance taking its folder, clock, liveness, reach and switch (no statics). `documentation/12-windows-app.md` → "What Windows has built: W1, reading the journal" and "The pieces still owed for #899 on Windows".
- Walked from the contract: `checkCases` 30, `folding.moves` 20, `stackCases` 46, all 20 traces and 612 calls (through a test-only stand-in for W2's door, `UndoScribe`). Ten must-fails red and restored.
- Ledger: no entry added or removed.

## 2026-11-13 — a deployed folder opened in the browser: the Core (#889 piece 889a, the mac's #850)

Branch `issue/889a-deployed-folder-core`. Lenovo 20QES70500 (i5-8365U, 16 GB, Windows 11 Pro 26200), other agents sharing the CPU.

- Core only, nothing a teacher sees: `DeployedFolderResolver` (790a's `ILocalFiles` disk layer, which gains `List`; one handle, its final path checked inside the folder), `DeployedFolderServer` (a `TcpListener` on 127.0.0.1, `ExclusiveAddressUse`, the contract's limits, `NoDelay`), `DeployedFolderOffer` (the offer rule; the folder resolved as `deploy.ps1`'s `Resolve-PublishFolder` does, held against that function run for real), `DeployedFolderAddress`, `DeployedFolderShows` (the app-wide registry, the stop rules, the `Happened` event 889b writes the trail from), `DeployedFolderWording`, `AppSettings.DeployedFolderPorts`. `browser-checks/crawl_deployed_folder.py` gains `--url`. The surface 889b calls, what was measured and what was rejected: `documentation/12-windows-app.md` → "A deployed folder opened in the browser (#889, the mac's #850)".
- No ledger entry removed: the six #889 entries are 889b's (window, menus, quit, trail, UI tests).
- **Two firewall prompts were raised by mistake** (a bind to 0.0.0.0 while measuring, once from PowerShell and once from a test since changed); they and their four "Query User" block rules are on the desktop for Russell. A loopback-only listener raises none (measured).
- After the implementation review (M1 events that cannot end the app, L1 a junction answers as missing, L3 ports saved on the UI thread, L4 opened only once the browser took it, L5 to L7): gate on ae2b9e8cc (dev d75c36543 inside) Failed 0, Passed 4032, Skipped 3, Total 4035 (20 m 44 s); the three skips by name; x64 Debug build succeeded.

## 2026-11-13 — what an outside assistant is told: the handouts and reference-courses sentences, and a call that names no section (#895, #856, #791, #885)

Branch `issue/880-what-an-outside-assistant-is-told`. Lenovo 20QES70500 (i5-8365U, 16 GB, Windows 11 Pro 26200). Core and `plantoir-mcp` only; the built-in assistant's surface did not move (`scripts/test_tool_surface_digest.py` OK, `tools/list` identical over stdio).

- Every door says `greetingHandoutsSentence` (Revise and Fix with since this piece; Plan a Unit since 790a); a Revise door names the courses kept for reference with the same code (`ReferenceCoursesToMention`, read from the folder by each door's `Open` at the click). `OutsideGreetingContractTests` and `OutsideGreetingOpenTests`. `documentation/12-windows-app.md` → "What an outside assistant is told when a door opens".
- `plantoir-mcp` answers a call with no section, or `add_classes` with no unit or count, in the contract's four sentences, and a one-section course for its section (`MissingArguments`, `MissingSectionTests`). Before, the SDK's "An error occurred invoking '…'.". `documentation/12-windows-app.md` → "A call that names no section (#885, the mac's #865)".
- Ledger: the six `FixWithGreetingCases` entries (#895) and the four `AssistWordingKeys` (#885) are gone.

## 2026-11-13 — unit planning's Core: the plan reader, the greeting's sentence, the Planning tab's rules and its guard (#790 piece 790a; #801, #820)

Branch `issue/790a-unit-plans-core`. Lenovo 20QES70500 (i5-8365U, 16 GB, Windows 11 Pro 26200), other agents sharing the CPU. Nothing a teacher sees changed: 790b builds the tab and turns the greeting's sentence on.

- `UnitPlans` (the `plan.json` reader, never throwing; the greeting's last sentence and trail clause through both doors' `Prepare`, NOT wired), `PlanningTab`, `PlanAUnit` (its message ends with the handouts sentence: #895's Plan a Unit part), `PlanningAssets` (the `assets` mirror, never through a link and never overwriting in place), and the guard's Core (`LocalSiteGuard`, `PlanNavigation`, `PlanInTheBrowser`). `documentation/12-windows-app.md` → "Unit planning on Windows (#790, #801, #820)".
- After two implementation reviews: unit names drop from the end to keep the door's command line under cmd's limit; a page over MAX_PATH is served; COM0 and LPT0 refused; a hard link in `assets` is replaced, never written through; the three file-link cases this account cannot make are a SKIPPED fact, not passes.
- Gates: `dotnet test` (with `PLANTOIR_RUNTIME` at the main checkout's runtime) after merging `dev` 77a341b02: Failed 0, Passed 3715, Skipped 1, Total 3716 (16 m 43 s, at 46c7ece21); the one skip is `PlanInTheBrowserTests.TheFileLinkCasesHoldOnDisk`, by name (this account cannot make a file symbolic link). x64 Debug build succeeded. The must-fails for every review fix are in the closing comment on #790.

## 2026-11-12 — the installer waits for work still running from its own folder (#700)

Branch `issue/700-installer-runtime-in-use`. Lenovo 20QES70500 (i5-8365U, 16 GB, Windows 11 Pro 26200).

- `installer-running-work.iss`, included by `installer.iss` and called from `PrepareToInstall` and again at `ssInstall`: before any file changes, a preview's server (`node.exe` running `bootstrap-cli.mjs` with `--serve`) is ended, `llama-server` on the update path too, `plantoir-mcp` on the update path refuses at once, and every other process under `{app}` is waited for — up to ten minutes when silent, then exit 7 with nothing changed; Retry/Cancel when hand-run. A refused Install and Reopen reopens Plantoir with `--update-not-installed-for-work` (its own trail sentence; 1.9.0 writes none for it). `[InstallDelete]` empties `Toolchain\scripts\__pycache__`; `publish.ps1` restores `Plantoir.Mcp` for win-x64 (NETSDK1004 on a fresh clone). Measured on the real 1.9.0 → 1.9.3 candidate the night before (without the fix): a preview serving gave exit 5 and a broken install.
- After the implementation review: every refusal leaves `update-not-installed.txt` in the state folder (`/STATEDIR=` when redirected), which the next launch writes on the trail with the version that waited (`AppUpdates.ConsumeNotInstalledMarker`); the app passes `/LOG=` (two kept); a Plantoir opened during the wait refuses at once and no second copy is ever started; `installing.<pid>` spans the copy and a scheduled run that sees it stands down at once (third review: waiting held `Plantoir.exe` and broke the copy; the 1.9.0 → 1.9.3 upgrade itself is not protected); the process list grows its buffer; `publish.ps1` refuses a bundle without the assistant's engine (1.9.0 shipped with no `llama\`) and `fetch-llama.ps1` pins the zip's SHA-256.
- `windows-app/installer-tests/` proves the include on a HARNESS installer with its own AppId (never the real Plantoir); `RELEASING.md` step 3a runs it, and one measured upgrade, every Windows cut. Not part of `dotnet test`. `documentation/12-windows-app.md` → "The installer waits for work that is still running (#700, Windows 1.9.3)".
- Gates: `dotnet test` (with `PLANTOIR_RUNTIME` at the main checkout's runtime) Failed 0, Passed 3446, Total 3446 (9 m 28 s, after the third review and merging `dev`; 3330 after the second, 3317 before it); the harness 14 of 14 cases (234 s, the scheduled-run must-fail among them) and 6 of 6 include must-fails, the real Plantoir untouched in every run; four source must-fails red and restored.

## 2026-11-11 — Fix with Claude… and Fix with Codex…, and how both outside doors start (#736)

Branch `issue/736-fix-with-assistant` off `dev` 644634b70. Lenovo 20QES70500 (i5-8365U, 16 GB, Windows 11 Pro 26200), another agent sharing the CPU.

- Two buttons under the Problems table hand the ticked rows still this section's problem to the Claude and Codex doors with `fixWith`'s message (`FixWithAssistant`, `OutsideAssistantPresence`, `OutsideDoorWording`); the trail event "asked an assistant to fix problems" is recorded and its ledger entry deleted. `documentation/12-windows-app.md` → "Fix with Claude… and Fix with Codex… (#736, the mac's #717 part two)".
- **A 1.9.0 fault fixed:** the Claude door handed the course's name to cmd outside quotes. Both doors now start through `OutsideDoor.StartInfo` — an `.exe` with nothing in front, an npm shim through `cmd /v:off /s /k` with every `%` neutralised — and Windows Terminal is no longer in front of either (measured expanding `%NAME%`). Revise With ▸ shares it; an `.exe` door's window now closes when the session ends. doc 12 → "What the outside doors hand to Windows, and how".
- Gates: after the security review's fixes and merging `dev` (#739), the full unit run with `PLANTOIR_RUNTIME` set is Failed 0, Passed 3417, Skipped 0, Total 3417 (11 m 19 s). UI, targeted, BEFORE those fixes: `FixWithButtonsUiTests` 1/1 and `ProblemsTabUiTests` 6/6; **not re-run after them** (the desktop was given to an upgrade measurement). Must-fails, all run and restored, are in the closing comment on #736.
- **Security review (2026-11-12):** control characters cleaned in every argument and the working folder before quoting (a NUL let a second command run through an npm shim); `(` `)` pinned with npm's older shim shape; a door refuses over 8,191 units; an `.exe` gone non-zero within ~400 ms is not reported as opened; Open in Terminal takes its folder as an argument (`OutsideTerminal`). doc 12 → "What the outside doors hand to Windows, and how" and "What a teacher sees in place of Windows Terminal".

## 2026-11-11 — a new course starts on Cloudflare Pages (#739 items 1 to 6, the mac's #668)

Branch `issue/739-saved-destinations-window`. Lenovo 20QES70500 (i5-8365U, 16 GB, Windows 11 Pro 26200, the laptop's display at 150 %), another agent sharing the CPU.

- `PublishingDestinations` (Core) holds every rule of `app-rules.json` → `publishingDestinations`; the new-course dialog writes `cloudflare_pages`, lets a missing Account ID wait (one orange block: the ID's sentence, `accountIDCanWait`, the 25 MB note) and still refuses one that cannot be an ID; the picker is Cloudflare, Netlify, folder; Netlify's note wherever Netlify is configured and in Schedule a deploy; the Deploy refusal offers Open Settings… for the ID's sentence (OK the default) and writes "deploy refused for the Cloudflare Account ID" by kind. `plantoir-mcp`'s deploy no longer refuses every Cloudflare section: it refuses as the window does and otherwise passes `--account` (stub-launcher proof only). `documentation/12-windows-app.md` → "A new course starts on Cloudflare Pages (#739)".
- Window tests choose a destination by TYPE (`DeployPicker`), never by index: the order changed under them.
- Gates: `dotnet test` Failed 0, Passed 3305, Total 3305; the new and changed window tests 8 of 8; the neighbours 11 of 12, the twelfth (MenuBarReachUiTests, a UIA timeout in Copy a Page) passing alone; ten must-fails red and restored.

## 2026-11-11 — a section's Problems tab, its warning and its one alert (#734, the mac's #717)

Branch `issue/734-problems-tab`. Measured on the Lenovo 20QES70500 (i5-8365U, 16 GB, Windows 11 Pro 26200, the laptop's display at 150 %), with another agent's suites sharing the CPU.

- The section's `.problems.json` (written by the shared Python since #717) is read by `SectionProblems` (Core), where the LAUNCHERS build (`BuildOutputLocation.WhereTheLaunchersBuild`, which `--state-dir` does not move); Website | Problems, the table, one sidebar warning, and ONE alert only when a build found something new replace the per-build folder-problem dialog (`FolderProblemQueue` deleted). The links checklist follows the alert. `documentation/12-windows-app.md` → "A section's Problems tab, its marker and its alert (#734, the mac's #717)".
- `NamedGapLedger` holds two events for v1.9.3: #736's "asked an assistant to fix problems" and #739's "deploy refused for the Cloudflare Account ID"; `SharedRules_ActivityTrailEvents_Exist` is green.
- Gates, after the third review (3aebf0e2c): `dotnet test` Failed 0, Passed 3278, Total 3278 (8 m 46 s); `LinksChecklistUiTests` 10 of 10 in a row (54–58 s a run, build included; 94 s the first); `ProblemsTabUiTests` (6) and `LaterClassesAtDeployUiTests` (4) 10 of 10 together. Before it, the full UI suite once: Failed 4, Passed 108, Total 112 (1 h 40 m) — `AcceleratorUnderDialogUiTests` (#770), two `UpdateInstallQuitUiTests` (an outside `plantoir-mcp`), and the dropped-answer fault since fixed in 1a77d2e2c.

## 2026-11-11 — the toolchain index is pruned (#735, the mac's #683)

Branch `issue/735-prune-toolchain-index`. Each mirror pass marks its folder's index used when it reads it; once a launch, off the UI thread, `ToolchainMirror.PruneIndexes` removes indexes unused for 90 days (never one for a folder the settings still name) and leftover temporary ones over a day old (plain files at the top of the folder only); the builds sweep takes a gone folder's index by its builds entry's name. The real folder on the Lenovo 20QES70500 held 2 indexes of 2,011,308 bytes, nothing yet old enough to go. No contract case, no trail line, no `mac` issue. Doc 12 → "Pruning the index (#735)".

## 2026-11-11 — a scheduled deploy runs on the runtime of the app running it (#702)

Branch `issue/702-scheduled-wrapper-runtime`. `ScheduledRun.WrapperStartInfo` hands the wrapper `LauncherEnvironment.Current` (`PLANTOIR_RUNTIME` as well as the trail), so a task registered from a Debug build no longer builds and deploys with the installed copy's runtime; for an installed copy nothing changes. Older tasks are not re-registered: their `<Command>` is the installed `Plantoir.exe`, which rewrites the wrapper at run time. The launcher-start scan now ignores comments. No contract case, no trail line, no `mac` issue. Doc 03 → "Where a launcher's own trail lines go".

## 2026-11-11 — at Deploy a tick means it goes out, Publish Pages… never asks, and a section's deploy outlives its view (#726, #728; the mac's #694, #706)

Branch `issue/726-deploy-flow-later-classes-and-mid-deploy`. Measured on the Lenovo 20QES70500 (i5-8365U, Windows 11 Pro 26200).

- **#726:** the question about classes dated later is asked at Deploy only; every row starts ticked to go out, one button (Deploy Ticked), unticked classes are hidden first (backup, Undo). Publish Pages… goes straight to its plan. `ContractTests.AssistWording_MatchesContract` is green again. The scheduled deploy is unchanged (#727). `documentation/12-windows-app.md` → "Classes dated after the next class, at Deploy (2C)".
- **#728:** `SectionDeployRun` / `SectionRuns` (Core) own a section's deploy; the view binds to it, Deploy is unavailable while this app has the section's deploy on its way, the ending is shown once, and the deploy's leases are the run's — they used to ride on the view's preview build claim, given back on Unloaded mid-deploy. `SectionKey` is meant for #734 too. `documentation/12-windows-app.md` → "A section's deploy outlives its view (#728, the mac's #706)".
- Gates (after merging `origin/dev` with #764's Python 3.14.10, run with `PLANTOIR_RUNTIME` at the main checkout's runtime): `dotnet test` Failed 5, Passed 3215, Total 3220 (10 m 41 s) — the five reds `dev` carries (`AppRules_FailureExplanations`, `SharedRules_ActivityTrailEvents_Exist`, `AppRules_DeployArguments`, two `TheRebuildLinesAreDeploySHsWordForWord` rows). UI: the full suite, before the review fixes, 103 of 107 — `AcceleratorUnderDialogUiTests` fails on dev's own code on this PC too, `UpdateInstallQuitUiTests` (2) waits on an outside `plantoir-mcp`, `ReferenceCourseUiTests` was a UI Automation timeout and passed again; `ReturningToASectionMidDeployUiTests`, `ReferenceCourseUiTests` and `GuidanceQuitUiTests` 8 of 8 after them. The same-window hand-on of a deploy's question was NOT driven (see doc 12).

## 2026-11-11 — wrangler 4.156.0, a brand-new site's files asked again, and the loopback guard (#719, #743, #730)

Branch `issue/719-wrangler-runtime-harness`. Measured on the Lenovo 20QES70500 (i5-8365U, 16 GB, Windows 11 Pro 26200, wired Ethernet), with another worktree's test suites running at times.

- **#743:** `verify-deploy.ps1 -FirstPublish` asks a brand-new site again, every 5 s for up to 60 s, for a file that does not yet answer as its check wants, and counts the retries per site; a plain run and the preview ask once. `-SelfTest` gained the mac's five #740 cases: 13 passed, 0 failed, ten runs in a row (about 30 s each); with the retry taken out, 4 of the 5 fail.
- **#719:** wrangler 4.80.0 → 4.156.0 in `fetch-runtime.ps1`; the `mustStayBelow` test is deleted; `installer.iss` empties `{app}\runtime\wrangler` so an install over 1.9.0 keeps none of 4.80.0's files (to be proved by #700's upgrade). `audit-runtime.ps1`: 54 advisories, 54 accepted, 0 blocking (4.80.0: 14 blocking). `verify-deploy.ps1` fails a Cloudflare leg wrangler delegated to Workers (none did, with `CLAUDECODE` and `AI_AGENT` reaching wrangler): `-FirstPublish` 170 passed, 0 failed, 0 skipped; plain 168 passed, 0 failed, 0 skipped. Transcript: `research/wrangler/2026-11-10-windows-first-upload.md`.
- **#730:** the loopback rewrite requires both of Quartz's bind sites, each exactly once, and keeps `handlers.js`'s bytes (it had been rewritten with a BOM and mojibake bullets in every runtime); `FetchRuntimeLoopbackGuardTests` (5).
- **Gates:** `dotnet test` Failed 11, Passed 3142, Total 3153: the baseline on `dev` (17c126331 with the dev runtime) was Failed 13 of 3149, the same eleven (other pieces' contract-ahead-of-app cases) plus `TheWindowsRuntimeRecipeCarriesTheSamePins` and the deleted ceiling test; none added. Details: documentation/12, "wrangler 4.156.0, a brand-new site's files asked again, and the loopback guard (#719, #743, #730)".

## 2026-10-28 — the console keeps lines apart, the Cloudflare wait needs this run's mark, and two decisions written down (#661, #680, #671, #659)

Branch `issue/661-console-preview-verify`. Measured on the Lenovo 20QES70500 (i5-8365U, Windows 11 Pro 26200).

- **#661:** `ScriptRunner.ReceiveOutput` passes every read through `CursorMoveLineBreaks` first, so a blank line ConPTY draws as a cursor jump no longer glues two lines together in the console, the saved transcript, the question box or a `PLANTOIR_HEALTH` line. Confirmed in the window first. The setup wizard's colour picker is still answered (measured browsing 0, 2 and 5 times per section). `ScriptRunnerCursorJumpTests`, from captured bytes. Gaps, not yet proved here: a Cloudflare deploy's repaints were not captured (the saved token was rejected and cleared), so the credentialed run on this PC skipped every Cloudflare leg and #680's wait has run live only on the mac (#665) — the nothing-skipped `verify-deploy.ps1` run before the Windows cut is the proof; and the UI wizard-to-preview test's preview half was not driven (its wizard half passed twice, then the screen was locked). `documentation/12-windows-app.md` → "Line breaks ConPTY draws as cursor moves (#623, #661)".
- **#680:** `verify-deploy.ps1` marks the borrowed page for each run, snapshots each Cloudflare upload as the leg returns, and waits for production to serve BOTH pages; `-SelfTest` runs the mac's eight cases offline (8 passed, 20 s). The real run here: 79 passed, 0 failed, 4 skipped (the four Cloudflare cases; no Cloudflare credential on this PC).
- **#671:** documented, no code: a running preview never re-reads `courses/`, on either platform; Quartz 4.5.0's watcher on Windows also misses edits to the merged copy (backslash paths), not patched, follow-up #703. `documentation/05-build-pipeline.md` → "A running preview does not follow edits (#671)".
- **#659:** documented: accept the Windows store; Windows Update removed "AAA Certificate Services" on 2026-10-26. `documentation/02-docker-image.md` → "The certificate store" → "On Windows".

## 2026-10-28 — Open in Obsidian opens the page the preview shows, and the assistant presses it (#681, #690; the mac's #518, #610)

Branch `issue/681-obsidian-previewed-page`. A section's Open in Obsidian (toolbar, Section menu, section row) reads WebView2's address once at the press, looks it up in the build's `.page-sources.json` (`PreviewedPageSource`, every contract case run against the fixture on disk) and opens that file through the route's page door, through the reference note, the add-ons offer and the reopen question; every fallback opens the section as before, and one "page opened in Obsidian" line is written per section press that goes ahead. "Open this in Obsidian" and its seven siblings reach `open_in_obsidian` in code (not on the local list); the window presses the main window's own button (`MainWindow.PressOpenInObsidianFor`) and replies from what the press came to, reported early because Windows' questions are awaited dialogs. `plantoir-mcp.exe` serves the tool and refuses: 42 → 43. `wording.obsidianIsNotOnThisMac` and its scenario are held in `NamedGapLedger` against mac #698 (v1.9.1); Windows says "this PC". Measured live on Obsidian for Windows 1.14.5: links with `+`, `&` and a comma each opened their file and created none. Gates (i5-8365U, Windows 11 Pro 26200, another worktree's runs sharing the CPU): `dotnet test` Failed 2, Passed 3074, Skipped 7, Total 3083 (7 m 54 s, after the implementation review's fixes) — the two are other pieces' (`TheWindowsRuntimeRecipeCarriesTheSamePins`, `test_geogebra_engine.py`). Details: documentation/12, "Open in Obsidian opens the page the preview shows on Windows (#681, the mac's #518)" and "The assistant's Open in Obsidian on Windows (#690, the mac's #610)".

## 2026-10-23 — a driven run leaves the real trail alone, and every key sent down is sent up (#641, #638, v1.8.7)

Branch `issue/641-ui-harness`.

- **#641:** UI tests started with `--state-dir` still wrote "got the working folder ready" lines to the REAL trail.
  - The writer was the harness's OWN process: `DrivenApp` sets the working folder up in-process, and only the app was redirected. It now redirects itself first.
  - The window's `plantoir-mcp` is now handed `--state-dir` too (`AppDataRoot.ArgumentsToHandOn` / `StateDirFrom`, pinned by `StateDirHandOnTests`).
  - `RealTrailUntouchedUiTests` drives both writers. It fails on an added real-trail line that names the run's folder or its one-off course code.
  - The launchers' refusal lines still bypass it: #664 (both platforms, v1.9.0).
- **#638:** 24 FlaUI key-downs had no key-up. They are now `Keyboard.Type`, or `using (Keyboard.Pressing(...))` for a held modifier.
  - `HarnessSourceRuleTests` (plain facts) keeps them out. The one exception, allowed by name, is `HeldKeys.HoldWithRepeats` (it was `PageTablesUiTests.HeldSpace` until #1035). Since #1035 the rules run in the unit project `Plantoir.Tests`, which the merge gate runs, not in the UI test project.
  - `HeldKeys` releases any key still down. `DrivenApp.Dispose` records it without throwing, and the `HeldKeyLedger` collection fixture fails the cleanup naming the keys and tests. This was seen working when F2 was put back to a bare key-down.
- **Measured** (i5-8365U, RDP session, other worktrees' unit runs on the PC at times):
  - Full UI run 1: **101/101**, 51 m 13 s, OpenRecentUiTests and PreviewStartPageUiTests included.
  - Full UI run 2: **100/101**, 57 m 21 s. `AcceleratorUnderDialogUiTests` failed: "the second window would not close". It failed again in five runs alone, one of them with the F2 change reverted, so it is not this piece. The new dump shows a real WinUI window ignoring `WindowPattern.Close`, not a tooltip; it is recorded as a known flake in `documentation/12-windows-app.md`, and the idle RDP session with LogonUI running is the unproven suspect.
  - Real trail across both runs and every re-run: **0** lines naming a `plantoir-ui-` folder.
  - Unit suite: Failed 6, Passed 2989, Total 2995. One was a load timeout that passed alone; five are #614's unimplemented curriculum contract cases.
- `documentation/12-windows-app.md` → "The flags the app answers" and "A key sent DOWN must be sent UP".

## 2026-10-23 — the tools copy compares by fingerprint (#559, #663)

Branch `issue/559-mirror-timestamps`. The build writes `Toolchain\.hashes` (path, length, UTC ticks, SHA-256); each working folder gets an index under `AppDataRoot\toolchain-index`; a same-length, different-time file is compared by hash when both fingerprints still describe their files, else read as before. The trail line now says "N brought up to date, M compared (K read in full)" and is written when anything was read. Measured (i5-8365U, 16 GB, Windows 11 Pro 26200, warm, 12,909 files) — Debug tree, no rounding: a restamped bundle read 12,909 files in 6.7–10.8 s before, 0 files in 4.5–5.1 s after; rounded down to 2 s as an installed bundle is: 12,909 files in 10.1–10.2 s (156.0 s the first, cold) before, 0 files in 6.1–7.2 s after. Inno rounds installed times DOWN to 2 s, so the manifest side trusts a time up to 2 s below its own (one-sided); `installer.iss` now sets `TimeStampsInUTC=yes` so a clocks change between build and install cannot shift times an hour. The mac's mirror has the same flaw: #663. `documentation/12-windows-app.md` → "Comparing without reading (#559)".

## 2026-10-23 — the plan's checkbox; Working keeps the dialog's height (#655, the mac's #654, v1.8.7)

Branch `issue/655-plan-sheet`. The control under Publish Pages… / Hide Pages…'s plan table is a `CheckBox` (same `menuPlanShowAlready…` words, same id, unticked for every new plan, a second click takes the rows out); `PlanTableLayout.FoldHeight` 36 → 40, the platform's 32-epx checkbox + 4 gap measuring 36, an exact fit with no margin. The mac's second fault (the answer kept the plan's height) was never on Windows: a `ContentDialog` sizes to its content. Windows had a third: Working's one-line spinner SHRANK the dialog (to 184 epx) and the answer grew it again. Working now holds the stage before's height — the content plus the button row, which collapses when Working clears the buttons (the content alone still shrank the box to 342) — after Choose, the later-classes question and the plan, clamped to the window on every resize. REJECTED: dropping the hold on a resize (a minimise and restore mid-publish shrank the dialog to the spinner). Measured, the dialog's box at a 1000 × 698-epx window (x64 Debug, 200% scale; the box from the app's own log in a `--state-dir` run, because UI Automation reads it stale):

| Plan | Choose | Working | Plan | Working | Answer |
|---|---|---|---|---|---|
| Publish, 1 change + 4 folded | 769×417 | 769×417 | 769×422 | 769×422 | 769×189 |
| Hide, 1 change | 769×430 | 769×430 | 769×258 | 769×258 | 769×189 |

Gates: `PageTablesUiTests` + `PlanTableUiTests` 12 of 12 through `run-ui-tests.ps1`; must-fails red (no hold: Working 184; content-only hold: 342). `dotnet test` Failed 7, Passed 2981, Total 2988 — #647's five curriculum cases, `ReferenceMarkerAgreementTests` (another worktree deploying REF at the same moment) and `ObsidianFigureAddOnsTests` (`offerMessage`, not this piece). `documentation/12-windows-app.md` → "The plan's checkbox, and the answer fitted to its sentence (#655, the mac's #654)".

## 2026-10-23 — verify-deploy.ps1: this checkout's recipe, a real first publish, Netlify page addresses (#630, #623, #657)

Branch `issue/657-verify-deploy`.

**#630.** `verify-deploy.ps1` first mirrors its own checkout's launchers and recipe into the working folder's `.toolchain\`. It is a true mirror, as `ToolchainMirror.SyncDirectory` is: stale files are deleted and `__pycache__` is left alone. It rebuilds from scratch only when something changed. `PLANTOIR_RUNTIME` is required and defaults to `windows-app\Vendor\runtime`; a runtime without `vendor\pyodide` is refused. A running Plantoir or plantoir-mcp gets a warning, not a refusal. Each Cloudflare leg waits, for at most 120 s, until production serves the `index.html` it uploaded; a timeout fails.

**#623.** A new flag, `-FirstPublish`, renames the saved surname and the section's site records aside behind a per-path sentinel. It answers with a random surname and restores everything on every exit path. The prompts used to join because, before ConPTY's 30-row screen scrolls, it draws "text, blank line, text" as `…only asked once.\e[8;1HFirst time setup…` and stripping the escape joined the lines. PtyDriver now passes its output through `CursorMoveLineBreaks` first, and gained `--bytes-log`.

**#657.** `Check-PageLinks` runs verify-deploy.sh's own `check_page_links` program on six legs. The folder legs also check that no page carries the marker and that `plantoirPaths` appears exactly 3 times.

**Measured** (i5-8365U, Ethernet):
- `-FirstPublish`: **167 passed, 0 failed, 0 skipped**. It answered exactly the surname and site-name questions.
- The plain run against the section's own sites: **166 passed, 0 failed, 0 skipped**.
- The re-run after the review fixes, `-FirstPublish` again: 166 passed, 0 failed, 0 skipped.
- Every Netlify and Cloudflare leg: 23 of 23 links answered 200.

New issues: #661 (the app's own console very likely shows the same joins; confirmed and fixed 2026-10-28, `ScriptRunner` now runs the same stage) and #665 (the mac's Cloudflare race). `documentation/12-windows-app.md` → "verify-deploy.ps1".

**Gate:** `dotnet test` Failed 7, Passed 2986, Total 2993. The seven are `dev`'s curriculum-folder and Obsidian-wording cases, plus one `PythonToolchainTests` 3-minute load timeout; a different file timed out when it was re-run alone.

## 2026-10-23 — a folder the course declares in curriculum_folders is curriculum, whatever it is called (#647, the mac's #614)

Branch `issue/647-curriculum-folders`. One rule, `CurriculumRules.IsCurriculum(folderSegments, declared)`, the twin of the mac's `isCurriculum(folderSegments:declared:)`. It sets aside a leading `section<n>` folder (`HowITeachPage.IsASectionFolderName`). A page is curriculum when its first folder equals a declared name (NFC both sides, `OrdinalIgnoreCase`) or any folder contains "curriculum". It is reached through `PagePaths.IsCurriculum(courseDirectory, fullPath, declared)`, where `declared` is required. Every caller now passes `course.Configuration.CurriculumFolders`: `ProtectedFromHiding`, `ReasonToKeep` and the #617 trim, `ReferenceDates`, the Start of Year kinds and count, `CurriculumExpectations`, and `LinkGraph.Unreferenced`. `LinkGraph.Build` keeps the course root and the list, and `LinkGraph.IsCurriculum` is gone. Side fix: the expectations list and the orphan list used to test the FULL path, so a working folder named "Curriculum Work" counted; they read folders inside the course now. All four harnesses read `curriculumFolders`, so the five red contract cases pass with no named gaps. New tests: the accent case and the section folder being set aside. Details: `documentation/12-windows-app.md` → "A folder the course declares is curriculum, whatever it is called (#647, the mac's #614)".

Gates: `dotnet test` Failed 3, Passed 2987, Skipped 0, Total 2990 (16 m 46 s, with another worktree's suite running). None of the three is this piece's:
- `ObsidianFigureAddOnsTests.TheWordsAreTheContractsWithWindowsOwnTwo` ("wording.offerMessage differs") is red on the base commit too.
- `ReferenceMarkerAgreementTests.EveryRowAgainstTheRealLauncher` and `test_starting_content_prompts.py` timed out under load and passed when re-run alone.

## 2026-10-23 — the Code page's Swift pictures on Windows (#590)

Branch `issue/590-swift-pictures`. `preview_pages_windows.py` no longer leaves `code-swift` and `code-swift-live` out (`NOT_ON_WINDOWS` is gone); both were taken at 2x by `capture_windows.py --code code-swift-live,code-swift` (fitted scale 2.000 in a 3840 x 2160 Remote Desktop session at 200%, taskbar showing), read back against `expectText`, promoted to `windows: true`, and taken off `WINDOWS_PICTURE_OWED`; `site.json` → `runnable-swift` is `windows: true`, so the Code page drops its Mac-only line, and its download sentence gives both sizes. The first ICS4U preview compiled its one block in 4.73 s (Swift already ready). `documentation/12-windows-app.md` → "The Code page's Swift pictures (#590)". Gates: `website/test_build_data.py` and `build.py --check`.

## 2026-10-22 — the picker as a table, the plan folds, the page dialogs follow the window (#634, the mac's #608 #621 #622, v1.8.6)

Branch `issue/634-page-sheets-windows`. Publish Pages… and Hide Pages…'s first stage, and #475's question at Publish Pages… and at Deploy, are banded tables (`Views/TickTable`: Page — the box is the title — Folder, Date); a click on a box ticks it, selecting ticks nothing, Space ticks the row the focus is in (on key-down, a held Space's repeats ignored; no key-up guard is needed — both measured with a real key-up on 2026-10-22, after the first measurement turned out to send none: FlaUI's `Keyboard.Press` is key-down only), Return reaches the main button, and each row tells Narrator "ticked"/"not ticked". The plan draws `PlanTable.RowsToRead` and folds the pages already visible/hidden behind a borderless toggle under the table (`MenuPlanShowAlready`), the table's height fixed at `RowsWhenClosed` so opening never grows the dialog. The page dialogs and Start of Year follow the window: today's width at the 900-epx minimum, up to 300 epx more (a Windows-only cap, pending Russell), Page taking the width; every fit unchanged up to 756 epx tall, one more row per 32 epx above. The five wording keys have members and hand asserts (`ContractTests` green again). Details and what was rejected: `documentation/12-windows-app.md` → "The picker as a table, the plan folds, the dialogs follow the window". Gates: `dotnet test` Failed 0, Passed 2974, Skipped 0, Total 2974 (10 m 46 s). Through the window (2026-10-22, 200% remote session): `PageTablesUiTests` 6/6, with `PlanTableUiTests` 10/10, `LaterClassesAtDeployUiTests` and `SectionVerbsUiTests` passing; three must-fails red; the picker's chrome 285 epx (estimate 300), the disclosure 27 + 4 (estimate 36), the dialog 680 → 980 across a 400-epx wider window.
## 2026-10-22 — Swift blocks run on Windows (#570, the mac's #493, v1.8.6)

Branch `issue/570-swift-on-windows`. The first preview with a ```` ```swift run ```` block now gets Swift ready on the PC, in the foreground as the mac builds its Swift image. It downloads the pinned swift.org Windows installer (SHA-256 and Authenticode checked), the cabinet carved at its pinned offset, four payloads against Apple's SHA-512, `msiexec /a` with no elevation, trimmed, plus the mac's SDK and wasm-opt, and a smoke compile. It keeps about 0.9 GB in `%LOCALAPPDATA%\Plantoir\swift\6.4.0`. Then it compiles with `support/swift/compile.py`, unchanged, through `scripts/swift_windows_compile.py`. `notOnWindows` and the 1.8.5 stopgap are gone, and `verify-deploy.ps1` checks the program instead of asserting it absent. There are two new trail events ("Swift got ready on this computer", "Swift could not be got ready") from the `PLANTOIR_SWIFT:` line (`SwiftGotReady.cs`).

Measured (i5-8365U, 16 GB, Ethernet):
- **The fetch:** 2.3 GB downloaded, 164 s on its own (download 21.5 s), 126 s resumed after a kill, peak 4.8 GB on disk.
- **The swift-gate** through the wrapper: 165 s, the mac's sizes exactly, `wasi_run.mjs` OK.
- **The 7-block Swift Playground preview:** a full-library block took 60 s (wasm-opt), embedded blocks 5–12 s. The second preview compiled nothing (28 s).
- **`swift_runner.mjs` in headless Edge 155:** OK.
- **`verify-deploy.ps1`:** 148 passed, 0 failed, 0 skipped (14 min).

The two Swift marketing pictures stay owed (the 2x picture); `site.json` `runnable-swift` stays false. (Taken and promoted 2026-10-23, `runnable-swift` true: the entry above.) `documentation/12-windows-app.md` → "Runnable Swift on Windows". Gate: `dotnet test` once, alone: Failed 2, Passed 2959, Skipped 0, Total 2961 (9 m 35 s). `ContractTests.AssistWording_MatchesContract` is the five #634 assist-wording keys on `dev` (not this piece). `test_baked_modules.py` was this piece, fixed by baking the two new scripts into the Dockerfile; after the fix, `PythonToolchainTests` passed 78 of 78.

## 2026-10-22 — the daily check's Install and Reopen quits the app (#632, v1.8.6)

Branch `issue/632-daily-check-install`. Accepting the DAILY check's offer left the old Plantoir running and installed nothing, because the quit ran on the thread that started the check — a timer thread for the daily check — and `Current.Exit()` reached from there returns having done nothing (red run: `QuitForUpdate on thread 5, UI thread: no` … `Current.Exit returned`, the process still up 30 s later). `App.QuitForUpdate` now hands the quit to the UI thread's `DispatcherQueue` when it is not on it. New `UpdateInstallQuitUiTests` (daily offer, and Check for Updates… as the control) against a signed localhost feed through a Debug-only seam: red 1 of 2 before, green 2 of 2 after (old process gone 0.9 s and 0.6 s after the click, i5-8365U). `documentation/12-windows-app.md` → the Updates bullet; `RELEASING.md` carries a "Landed since" row and a warning for the 1.8.6 notes.

## 2026-10-22 — the 1.8.5 measurement sitting (#593, #571 items 2–3, #618, #620, #598, #605)

Branch `issue/593-measurement-sitting`. Measured, nothing built: no product code, contract or test changed. A native build (`preview.ps1 --build-only` with `PLANTOIR_RUNTIME`) of verify.sh's own EXC2O fixtures was run through headless Edge 155.0.4283.60 (Lenovo 20QES70500, i5-8365U, 16 GB, UHD 620, Windows 11 Pro 26200).

- **#571 item 2.** LF and CR LF quiz pages were built separately and read alike, byte for byte (kinds, data, hashes, the 18 error lines), with no `readDifferently` line. On a CR LF page the nested answer renders under its title.
- **#598.** No `plausible.io` anywhere in `public\`. `mermaid_draws.mjs` drew 2 of 2 under the `_headers` a deploy to Netlify writes; the engine comes from cdnjs, as designed.
- **#618 / #620.** The PNGs carry 600 × 200 and 400 × 1800 with `data-pl-sized`; the hand fixtures give 40 × 120, 40 × 120, 302 × 151 and auto. `picture_heights.mjs` OK, 3 runs of 3.
- **#593.** `task_boxes.mjs` OK. Its paper half has no poppler here, so ink was read by pdf.js plus the check's own `boxInk`: all four sheets pass. With site data blocked by the profile, the handout keeps the ticks. The one-blank line is exactly `feedback.blanks` {1, 0}.
- **#571 item 3.** `quiz_check.mjs` fails only on its two Swift lines (#570). The four kinds pass wrong then right by keyboard, in light and dark. Neither Ctrl+P's paper nor the handout carries a quiz answer (with the quizzes unanswered; paper after Show answer is owed).
- **#605.** `test_my_progress.py` passes (27 tests).

`PythonToolchainTests`: Passed 77, Failed 0. **WebView2 pane** (this build, `--state-dir`, `--auto-preview EXC2O 1`, driven over its debugging port): the four kinds pass wrong then right by keyboard, in light and dark. The one-blank line is exact. Under print media, neither the paper nor the pane's own handout frame carries a quiz answer (quizzes unanswered; paper after Show answer is owed). **Owed:** real Narrator speech (only the DOM's labels, the proxy, are measured), Ctrl+P's paper with a quiz answer revealed (Edge and the pane), and the WebKit leg when #597 lands. Details: `documentation/12-windows-app.md` → "The 1.8.5 measurement sitting".

## 2026-10-22 — a club's plan card says "meeting", two skill tests, and a window whose display is gone (#556, #600, #571 item 1, #558)

Branch `issue/556-small-fixes`. **#556:** `PublishPlan.Describe(ClassNoun, int)` is the teacher's card in the course's noun and `Describe(int)` the class form (the model's copy, byte for byte); the kept reason goes through `PublishPlan.ReasonFor`, shared with #548's table, whose output did not move. `plan_publish_pages`, `plan_unpublish_pages` and `plan_publish_class_on` send `Proposing(Describe(), Describe(noun))`, and the unknown-name answer carries both copies. `Describe()` printed for every branch before and after: identical. `ClubNounTests` pins it. **#600 / #571 item 1:** `AgentGuidanceTests.ThePageAuthoringSkillIsWrittenAndBothRootFilesRouteToItFirst` and `TheQuizzesSkillIsWrittenAndBothRootFilesNameIt`, ports of the mac's; doc 12 points at 06 → J. #571's CR LF measurement and Edge/WebView2/Narrator checks are still owed. **#558:** `WindowFrameFit` keeps a remembered frame exactly when its title-bar strip (32 epx) overlaps some work area by 100 epx across and a third of the strip down, and otherwise fits and centres it on the nearest display (`MainWindow.OnADisplay`). Measured (Intel i5-8365U, Windows 11 Pro 26200, one 1920 × 1080 screen at 150%, work area 1920 × 1008): a frame seeded at X = 5000 opened at (5009, 200) before, and at (269, 54) after (`WindowOnScreenUiTests`, run alone, red then green). `WindowFrameFitTests` holds the geometry.

Gates: `dotnet test` once, alone: Failed 3, Passed 2869, Skipped 5, Total 2877 (5 m 22 s). Two of the failures are #581's add-on cases (`ReferenceCopierTests.EveryAddOnCaseThroughKeepACopy`, `ReferenceImportTests.EveryAddOnCaseThroughAnImport`), red on dev too. The third, `ScheduledRunTests.TheRunBringsTheFoldersToolsUpToDateBeforeItWritesTheWrapper`, passes alone (30 of 30), so it is a load flake. The five skips are the runtime-dependent facts; this worktree has no `Vendor\runtime`.
## 2026-10-22 — Obsidian's add-ons for diagrams and graphs (#581, the mac's #495)

Branch `issue/581-obsidian-addons`. Open in Obsidian offers, once and before Obsidian opens, to add TikZJax 0.5.2 and Functionplot 1.2.1 to courses with ```` ```tikz ```` / ```` ```functionplot ```` fences; after the yes a course gets what it uses at Open in Obsidian and after a preview, never under a course open in Obsidian (the reopen question instead), never into a reference course. **Run `windows-app\Vendor\fetch-obsidian-addons.ps1` once per clone — the build refuses without it.** The whole key runs headless in `ObsidianFigureAddOnsTests` and `ObsidianOpenRouteTests` (the route is Core, behind `IObsidianWorld`); File ▸ Settings ▸ Obsidian holds the toggle; the archiver leaves Plantoir's add-ons out; `ObsidianAddOns.Found` keeps them apart (the two reference tests green). `QuitObsidianAndWait` now closes every Obsidian window in this session (the registration and rename paths kept a two-vault Obsidian running before). Measured live on Obsidian 1.14.4: Enter on the trust question chooses Restricted Mode (`windowsWording` is true); Trust opens Obsidian's Settings ▸ Community plugins, which #582 measured NOT happening on the mac's 1.13.7 — a decision for the mac; the reopen of two vaults (one minimised, a pop-out) closed in 0.4 s and reopened in 2.8 s with typed text kept. Details: documentation/12, "Obsidian's add-ons for diagrams and graphs on Windows (#581)".

## 2026-10-22 — one curriculum test, folder segments only, and a linked curriculum page is not "already visible" (#615, #617)

Branch `issue/615-curriculum-predicate`. `PagePaths.IsCurriculum` reads only FOLDER segments inside the course (a relative path, or a page outside the course, is false), and `AssistWorkspace.IsCurriculum` calls it. Hiding a class now takes down a page merely CALLED "Curriculum …" in an ordinary folder, as the mac does. `ReasonToKeep` resolves the page from the working folder before asking, where it used to pass a working-folder-relative path that was read against the process's directory. A publish plan leaves out an already-visible curriculum page the walk reached (the mac's #607), so the card, the Section menu table and its summary, and the MCP text all drop it. `FollowingLinksContractTests.Lay` reads `folder` and `expectAlreadyRight`, so the #607 case no longer passes vacuously, and `followingLinks.unpublishing.cases` gains the #615 case (authored here). New: `CurriculumPredicateTests`. Details: `documentation/12-windows-app.md` → "One curriculum test, folder segments only (#615) …". Gates: `dotnet test` Failed 4, Passed 2852, Skipped 4, Total 2860. The four failures belong to other pieces: #581's two add-on cases, the runtime pins and `test_katex_assets.py`.
## 2026-10-22 — a folder added later gets its index page and a page to duplicate; titles quoted (#580, #586)

Branch `issue/580-folders-added-later`. A folder added in Course Settings gets setup's `index.md` and the generic skeleton's `_DUPLICATE ME.md` — shared, or in every section for a per-section folder — only in a folder the click made and never over a file (`Plantoir.Core/Models/FolderScaffold.cs`, a port of the mac's #506; `SpecialFolderRenamer.CreateFoldersOnDisk` now returns its `Outcome`). The "folder created" trail line names the pages written. One title rule, `FolderScaffold.FrontmatterTitle` (`foldersAddedLater.titleQuoting`), now also quotes a section's front page in `SectionAdder` (which reads a quoted sibling title back first, `PlainTitle`) and `SiteHealthRepair.RestoreIndex` — #586, the mac's #575: a course called "Physics: Mechanics" no longer gets a front page the build cannot read. The template is read CRLF → LF, because this checkout and the bundle carry it CRLF. Tests: `FolderScaffoldContractTests` (7 folder cases in memory as bytes, 15 title cases, 6 front-page cases twice each, every skeleton template, the click on disk) and one `SiteHealthRepairTests` case; must-fail by copy-and-restore, 13 and 7 failures. Write-up: `documentation/12-windows-app.md` → "A folder added later, and titles YAML can read".

## 2026-10-22 — the trail's open and close lines, My Progress's trail line, undo's three verdicts and the Start of Year table (#565, #599, #564, #619)

Branch `issue/565-trail-wording-red`. "Plantoir opened" prints the three-part version (1.7.2, not "1.7 (2)") and a new "Plantoir closed — {reason} · pid N" says why it closed (quit by the teacher; to install a new version, including Restart Manager's ENDSESSION_CLOSEAPP from the installer; asked to close by Windows). `my progress page built` is read from `PLANTOIR_MY_PROGRESS:` by the console reader, the scheduled record reader and the wrapper's scan; `include_my_progress` and `success_criteria_headings` are read-only. Undo gives each file one verdict (already back / put back / left alone), so a change taken back in part comes off once the edited page is dealt with; the start-of-year undo sheet previews by the same rule. The Start of Year sheet shows the pages going into draft as a Page / Folder / Why table, with the no-room note before Go and a height rule derived from the window. `NamedGapLedger` holds #581's four Obsidian add-on events (v1.8.0).

Measured (Intel i5-8365U, Windows 11 Pro 26200, 1920 × 1080 at 150%, 2026-10-22): a native build makes `My-Progress.html` and `progress-manifest.json`, and headless Edge 155 reads 2 / 3 after two ticks; the Start of Year sheet in its worst case is 699 epx in a 700 epx window and 563 in the 563 epx minimum, with the warnings never cut and the must-read notes scrolling. Details: `documentation/12-windows-app.md` → the four sections dated #565, #599, #564 and #619. Gates: `dotnet test` Failed 4, Passed 2833, Skipped 4, Total 2841 — the four are other pieces' (#581's add-on cases, the runtime pins, `test_katex_assets.py`).
## 2026-10-22 — the runtime carries Pyodide 314.0.7 (#568); live input and the editor's colours inherited (#591, #592)

Branch `issue/568-python-runtime`. `fetch-runtime.ps1` fetches `pyodide-core-314.0.7.tar.bz2` (6,757,104 bytes, the contract's SHA-256), keeps its five runtime files at the contract's hashes in `runtime\vendor\pyodide` with the MPL-2.0 README, and records `pyodide` in the manifest — +13,531,290 bytes. **`pyodide` is a fifth vendor key, so the app's build STOPS on every clone whose runtime predates 2026-10-22** (`CheckNativeRuntimeManifest`, "…the TikZ engine, Pyodide): its manifest.json lacks their keys") **until `windows-app\Vendor\fetch-runtime.ps1` is re-run**, and that re-run redoes the WHOLE vendor phase, not just Pyodide (49 s here). Unpacked with the runtime's Python, though this PC's bsdtar reads bzip2. KaTeX in the runtime is 0.16.21, the mac's, byte for byte. `scripts/test_katex_assets.py`'s red was a path-separator bug in the test (`.as_posix()` now). The native preview already sends the isolation headers (#591: COOP/COEP on a runner page, COEP on both engine folders, the `plantoir: note:` line for a page with a frame), the publish too; #592's files ride the `support\**` glob. `verify-deploy.ps1` gained the mac's engine checks (140 passed, 0 failed, 8 skipped; #623 is a first-publish prompt join it found). Edge measurements: first Run to the first prompt 2.38 s median cold, 0.12 s warm. Details: documentation/12, "Runnable code (#455) and KaTeX served by the site (#494)".

## 2026-10-15 — Windows catch-up to 1.7.1, batch 6 (#514) and batch 5B's review fixes

Same branch. First, 5B's implementation review: the guidance question stays down while the quit question is being put up and until it closes (a `_quitQuestionUp` flag; the re-ask is the 2 s timer's — before, it came back inside the quit question's waits and the close did nothing), a later guidance pass that succeeds clears the notice, the bundled guidance bodies are read with LF endings, and the print shim acts only on `localhost`/`127.0.0.1`.

Then #514, **Preview at Last Viewed** (the mac's #504): File ▸ Settings ▸ **Preview** (front page by default, or the page last viewed); the Preview button titled by what a press will do and re-titled while Alt is held in the active window (Ctrl+Alt, AltGr, is not the modifier); **Section ▸ has a second item**, always the opposite, absent while a preview runs, never a stop; the page remembered per folder, course and section in `last-viewed-pages.json` — only from the teacher's navigations, every app load going through a ledger keyed on WebView2's NavigationId and ended at `ContentLoading`; once the root answers, the remembered page is asked (3 × 5 s) and opened, or the front page with a trail line saying why. Every other start opens the front page. The section title now gives way to the longer button. `NamedGapLedger` is **empty**. Measured: WebView2 155's event orders, Alt with no access keys (no KeyTips, no menu mode), the menu's first-item `Unloaded` on every close, the real serve handler's statuses — `documentation/12-windows-app.md` → "Preview at Last Viewed on Windows". OWED: the `[UiFact]`s in `PreviewStartPageUiTests` and `GuidanceQuestionAndTheQuitQuestionUiTests` (the desktop was locked), and the toolbar's width at 900 epx.

Then batch 6's own review fixes: the navigation ledger captures one id per app load requested (two in one dispatcher turn no longer let the cancelled first end the second), and a preview that ended during the remembered page's ask opens nothing rather than a dead port. Then the whole-branch documentation pass. Gates: `dotnet test` Failed 0, Passed 2725, Skipped 0, Total 2725 (5 m 31 s).

## 2026-10-15 — Windows catch-up to 1.7.1, batch 5B (#496) and batch 5A's review fixes

Same branch. First, 5A's implementation review: `fetch-runtime.ps1` rewrites the manifest WITHOUT the four vendor keys before `runtime\vendor` is touched (on a fresh clone, a base-only manifest right after the base phases), so a vendor phase that dies leaves a runtime the build refuses and a re-run repairs by the vendor-only path (L1, L3); the vendor addresses are literals beside their version variables, the script refuses when they disagree, and `ToolchainContractTests.TheWindowsRuntimeRecipesVendorVersionsAreTheContracts` holds each variable against the contract (L2).

Then #496, printable pages: **Course Settings → Printing** (school name, Name/Date/Class # switches, two pickers, the corner sketch; getters never write and a setter given what it would read back is a no-op, so an unknown blank, an unknown place or a `"   "` school name opens clean); the **`settings saved` line** says what printing changed (`SettingsSavedLine`); **the guidance for assistants** (`AgentGuidance`, the mac's port: skills in `.claude\skills` and `.agents\skills`, the managed section in `AGENTS.md`/`CLAUDE.md`, the question before a teacher's own file is changed) runs after the tools copy on a task of its own and never holds the folder back — atomic writes, a path-free notice from the Win32 error code, the quit question taking it down unanswered; **the preview pane** hands new-window links and Print to the default browser (a `window.webkit` shim forwarding to WebView2's channel, no shared file changed). New authored corners case: a null `print_blanks` is Name and Date, as the build prints it (a request to the mac). `.gitignore` hides the graphs skill this repository is given as a working folder — and **in a checkout of this repository, answer Not Now** to the question about its own CLAUDE.md and AGENTS.md. `NamedGapLedger` now holds only #514's two events.

Measured (Intel i5-8365U, 16 GB, Windows 11 Pro 26200, Edge 155.0.4283.45 headless = the WebView2 Runtime's build; no Chrome on this PC): the mac's `print_handout.mjs` and `print_plain_page.mjs` pass unchanged on a native build — handout pages 12 / 1 / 13 portrait, 14 / 2 / 16 landscape; #501's Plain Long Page 4 and 5 pages, 40/40 inked, light and dark; `printPdf: "WORKSHEET 3.PDF"` links the folder's spelling. Measured on an unlocked desktop afterwards (2026-10-15, see the entry above it): Ctrl+P in the pane prints 2 sheets with the corners, `window.print()` blocks and `afterprint` fires, the hidden frame prints the handout in the pane too, and `#plantoir-print=…&paper=…` survives ShellExecute — Edge prints at once, 1 sheet; the four UI tests pass. Details: `documentation/12-windows-app.md` → "Printable pages".

## 2026-10-15 — Windows catch-up to 1.7.1, batch 5A (#503) and batch 4's review fixes

Same branch. First, batch 4's implementation review: a close that waited for the tools copy and then did not quit (Keep Working when asked again, a window opened meanwhile, the handler failing, or the installer not starting) releases the copies it held, so they no longer wait for the life of the process (M1); a window held open for ANOTHER folder's copy says "Finishing getting a folder ready…" (M2); a finished copy tries five times to remove its marker (L1); the mixed scheduled-run "waited" line names the copy's process (L3).

Then #503: `fetch-runtime.ps1` fetches `runtime\vendor` — Paged.js 0.4.3, Latin Modern (Debian's `fonts-lmodern_2.005-1_all.deb`, the image's own bytes), function-plot 1.25.4 and node-tikzjax 1.0.5 from the lockfile — each checked by the contract's SHA-256s. An existing runtime is brought up to date from its manifest's keys, fetching only `vendor` (42 s here); the app's build REFUSES a runtime whose manifest lacks those keys, so **re-run `windows-app\Vendor\fetch-runtime.ps1` once on every clone**. `NamedGapLedger` no longer holds any runtime pin. memfs's `/tex_files/` works under win32 paths: the contract's triangle is byte-identical in two processes (1,540 bytes, SHA-256 `8c68b085…6827b37`); the mac is asked for the image's hash.

Measured (Intel i5-8365U, 16 GB, Windows 11 Pro 26200): engine load 1.4–1.8 s; a section with three diagrams, a graph and a printable page 19.2 s first, 5.7 s cached; an endless diagram stopped at its 20 s clock (23.5 s for it and the next); a runtime under a path with spaces works; `tikz-engine\` 5,450 files, 40,838,241 bytes; graphs and Computer Modern lettering checked in headless Edge 155.0.4283.45 (the WebView2 Runtime's build) in light and dark. Details: `documentation/12-windows-app.md` → "Diagrams and graphs".

Gates: `dotnet test` Failed 0, Passed 2649, Skipped 0, Total 2649 (5 m 36 s); UI: `GettingReadyUiTests.ClosingDuringTheCopyWaitsForItThenQuits` passed; `TheWindowAppearsWhileTheFolderIsGotReadyAndPreviewWaitsForIt` could not run — the desktop was locked (no foreground window), twice.

## 2026-10-15 — Windows catch-up to 1.7.1, batch 4 (#470, #477, #484)

Same branch. Three scheduled-deploy and copy faults, by Russell's rulings. #470: a scheduled deploy's task QUEUES a second start (`MultipleInstancesPolicy` Queue, not IgnoreNew) — measured, the queued start runs 2.1 s after the first ends with the newest definition, a re-set replaces a queued start and a delete throws it away; the run's own token, lateness and lease checks decide. #477: the scheduled run waits (inside its ten minutes) for another program's live copy of the folder's tools and then brings them up to date itself, holding its leases, before it writes the wrapper; a failed copy or one still running at ten minutes stands it down `couldNotRunAsSetNow` with the contract's `wrapperCouldNotBeWritten`; copies take turns by their markers' moments (measured: two copies at once failed with sharing violations, 36 times in 5 runs). #484: closing the last window while a copy is writing keeps it up with its banner until the copy finishes, then quits (not at sign-out); the installer's quit waits too. No new trail event; two lines changed. Also 3B's review fixes (M1, L1–L4). Details: documentation/07, "Set again while the run works (#409)" and "On Windows since bundle 3: the scheduled run is Plantoir"; documentation/12, "Getting a folder ready after an update (#473)".

Gates (Intel i5-8365U, Windows 11 Pro 26200): `dotnet test` Failed 0, Passed 2642, Total 2642 (5 m 27 s); UI: `GettingReadyUiTests` (2, the new `ClosingDuringTheCopyWaitsForItThenQuits` measured closed at 3.6 s, quit at 18.9 s, every file in place; must-fail with the wait off: quit at 5.3 s, red), `AcceleratorUnderDialogUiTests`, `ReferenceCourseUiTests.OpenInObsidianLocksAnUnlockedPageAgainFirst` and `TheCalmNoteIsShownBeforeObsidianOpens`.

## 2026-10-15 — Windows catch-up to 1.7.1, batch 3B (#491 items 1–9)

Same branch. The rest of #491, the mac's HIG sweep: a disabled main button is never the default (`PrimaryButtonLook` / `DialogButtons.EnablePrimary`, every dialog by source scan; the wizard's Create Course never takes Enter; Class Dates reads, then remembers); Escape is never trapped by Copy a Page's or the wizard's picker (`PickerEscape`; measured, the AutoSuggestBox swallowed every Escape); one explanation shape under a dialog title (`FormBuilders.DialogExplanation`, a census of every dialog); Open in Obsidian locks a reference course again first; Delete and − run the menu's removal under its own enablement (a reference section's − used to remove the whole course), and every row menu ends with Remove…; All Backups sorts, has a context menu and takes Delete; the rows' Revise With ▸ with the menu bar's titles (`outsideAgents.menuItem` now read here); title-case buttons, problem titles that name the act, OK only alone, and a 12 epx font floor. Also 3A's review fixes (the ID's trail line when the teacher switches windows; a tighter single-writer scan; Course Settings' Save following the ID live, by UI test). `sidebarDeleteKey` is now run here. Details: documentation/12, "The HIG sweep, screen by screen, on Windows (#491 part B)".

## 2026-10-15 — Windows catch-up to 1.7.1, batch 3A (#491 part A, #490)

Same branch. File ▸ Settings… is ONE window (`SettingsWindow`: Assistant and Deploying; Preview comes with #514), not a dialog — WinUI allows one ContentDialog per window, measured per XamlRoot, and the wizard is one. The Cloudflare Account ID is edited only in Settings ▸ Deploying (a source scan holds every write to `DeployingSettingsPane`); a course's Deploying section and the wizard show it read-only with Open Settings… and follow it live. The in-app deploy's and Schedule a Deploy's refusals name File ▸ Settings ▸ Deploying. Help ▸ Plantoir Help (F1) opens plantoir.app/support. #490: both launchers' non-interactive refusal says "Add your Cloudflare Account ID in Plantoir ▸ Settings ▸ Deploying, then deploy again." (`deploy.ps1` via `[char]0x25B8`). Also 2C's review fixes (M-A: an open question refuses the assistant's deploy and stops nothing; L-1: a deploy the window will refuse keeps the preview; L-2; L-4). The #491 ledger entry is gone; the ledger holds #496, #503 and #514. Details: documentation/12, "The Settings window, Plantoir Help and the Account ID's refusals (#491 part A, #490)".

**The publishing path changed** (`deploy.sh`, `deploy.ps1`): `verify-deploy.ps1` must run at the 1.7.1 cut on Windows, and `./verify-deploy.sh` on the mac before its next release. Neither was run in this batch.

Gates (Intel i5-8365U, Windows 11 Pro 26200): `dotnet test` Failed 1, Passed 2560, Total 2561 (5 m 47 s) — the one, `ConPtyRedirectedParentTests` (#427), passed alone straight after; UI: `SettingsUiTests` (2), `PlantoirHelpUiTests`, `MenuBar*UiTests`, `AcceleratorUnderDialogUiTests`, `LaterClassesAtDeployUiTests` (2) — 8 of 8; `python scripts/test_deploy_non_interactive.py` OK, `python scripts/test_deploy_words.py` 6 OK.

## 2026-10-15 — Windows catch-up to 1.7.1, batch 2C (#475, the rest of #489)

Same branch. Classes dated after the next class are caught at Deploy: `ClassesDatedLater` (the contract's 24 `futureDatedClasses` cases on real files, now run here), `LaterClassesKept` (released on rollover). The window asks after every refusal and before anything is claimed or stopped — Hide Ticked and Deploy (through Hide Pages…'s own call, backed up, undoable, no preview either side) or Keep All and Deploy; the in-app assistant asks the window before it stops the preview (`DeployWillBeRefused` first); an outside assistant is held back until answered once; a scheduled deploy records what went out only on the wrapper's success record; Publish Pages… leaves ticked later classes out; `publish_class_on` and the links checklist keep what they publish. Also 2B's review fixes (M1 `plantoir.app/changed`, M2, L3–L8). The ledger now holds only #491, #496, #503 and #514. Details: documentation/12, "Classes dated after the next class, at Deploy (2C, 2026-10-15)".

Gates (Intel i5-8365U, Windows 11 Pro 26200): `dotnet test` Failed 0, Passed 2544, Total 2544 (5 m 40 s); UI: `LaterClassesAtDeployUiTests` (2) and `SectionVerbsUiTests` (2) pass, real launchers; `python scripts/test_tool_surface_digest.py` OK (digests unmoved), `python scripts/test_deploy_words.py` 6 OK.

## 2026-10-15 — Windows catch-up to 1.7.1, batch 2B (#489 items 1–2)

Same branch. The assistant's nine functions in the Section menu — Publish Pages…, Hide Pages…, Publish Class for a Date…, Rebuild Preview (Ctrl+Shift+B), Undo Last Change · Add Next Class, Re-date Classes…, Make Room for Classes…, Class Dates… — and four of them on the section row: the tools' own code through one runner entry (`AssistToolRunner`, extracted from `AssistAgent.RunTool`), behind a `plantoir-mcp` each window starts on first use (476–490 ms to answer, measured), in the menu's own voice (55 `…FromTheMenu` and dialog sentences), a `_menu-section<N>` copy before every change, an in-process claim against the assistant's window, and one dialog that moves through Choose → Plan → Working → Result. Rebuild Preview — and the assistant's rebuild_preview — now really restarts a serving preview. Pages are named by folder (`AssistWorkspace.Page` resolves inside the course). The Deploy question (#475) is 2C. Details and what was rejected: documentation/12, "The Section menu's functions (2B, 2026-10-15)".

Gates (Intel i5-8365U, Windows 11 Pro 26200): `dotnet test` Failed 0, Passed 2501, Total 2501 (5 m 46 s); UI: `SectionVerbsUiTests` (both, real launcher for Rebuild Preview), `MenuBarReachUiTests`, `MenuGreysUnderADialogUiTests` pass; `python scripts/test_tool_surface_digest.py` OK (digests unmoved), `python scripts/test_deploy_words.py` 6 OK.

## 2026-10-15 — Windows catch-up to 1.7.1, batch 2A (#488, #483)

Same branch. The menu bar the mac grew in #457: File, Course, Section, View and Help, every course and section action greyed by `SubjectMenuRules` (the contract's `subjectMenus`, 21 cases run by `SubjectMenusContractTests`), each running its row's or toolbar's own code; keys on menu items only (the root Grid's, Save's Ctrl+S and the section window's view-scoped keys are gone — measured to add nothing); File ▸ Open Recent (`openRecent`, `OpenRecentContractTests`; "recent working folders cleared" on the trail); row menus select their row first; one Open in Obsidian route; Help ▸ Publishing and Deploying…. #483 measured: every wizard field 32, nothing forced. The Section menu's functions (#489) are 2B, the Deploy question (#475) 2C. Details, numbers and what was rejected: documentation/12, "Menus, the Section menu's functions and #475 on Windows".

Gates (Intel i5-8365U, Windows 11 Pro 26200): `dotnet test` Failed 1, Passed 2480, Total 2481 — the one, `ConPtyRedirectedParentTests`, passed alone straight after and in the run before; UI: `MenuBarReachUiTests`, `MenuGreysUnderADialogUiTests`, `OpenRecentUiTests`, `AcceleratorUnderDialogUiTests` pass; `python scripts/test_deploy_words.py` 6 OK.

## 2026-10-15 — Windows catch-up to 1.7.1, batch 1

Branch `issue/windows-catch-up-1.7.1`. The first batch of catching Windows up from 1.4.5 to the mac's 1.7.1: the suite is green again, with every debt a later batch owns held open by name.

- **The ledger** (#481): each `NamedGapLedger` entry carries its own milestone (v1.5.0–v1.7.1), and `NamedGapLedgerTests` fails for any entry not LATER than `Plantoir.csproj`'s `<Version>`, so the 1.7.1 cut cannot go out over one. Four more lists are wired in: runtime pins, zip names, prune cases and assistant scenarios. Held open: 13 trail events, 72 wording keys, 4 config keys, 3 runtime pins, 3 scenarios, 1 prune case and 2 zip names, against #488, #489, #491, #496, #503 and #514.
- **#481**: an outside assistant's failed preview build says `previewDidNotBuildBecause` or `previewDidNotBuildForACallerWithNoWindow` — never the raw log, never a pointer at a window it does not have.
- **#479**: hiding a page rebuilds the preview, as publishing one does; the seventh `refusedBuildAnswers` case runs green.
- **#478**: a publish's, hide's or unit's rebuild that stops for a question says so.
- **#482**: the Netlify rate-limit sentence only for "Netlify API error 429" or "rate limit".
- **`scripts/figures.py`**: a cache write Windows refuses no longer leaves its temporary file behind.

Gates on this project's Windows PC (Intel i5-8365U, 16 GB, Windows 11 Pro build 26200): `dotnet test` Failed 0, Passed 2470, Skipped 0, Total 2470 (5 m 44 s), from Failed 13 at the start; `python scripts/test_figures.py` 35 OK; `python scripts/test_deploy_words.py` 6 OK.

## 2026-10-07 — the 1.4.3 release branch

Branch `issue/windows-1.4.3-release`. The Windows version is 1.4.3 (`<Version>` in `Plantoir.csproj`, `AppVersion` in `installer.iss`), and `PlantoirSetup.exe` joins the EXISTING v1.4.3 release, which the mac cut on 2026-10-04 with its DMG — no new tag. It is the first version the Windows updater installs (1.4.2 offers it). `website/updates/windows.xml` gains a 1.4.3 item (built with `--reparse-existing --change-log-path`, notes in `windows-app/release-notes/1.4.3.md`) and the Windows download card is unpinned. `WINDOWS-DIRECTOR-PROMPT.md` is deleted.

What landed on `dev` since 1.4.2, one line each (GUI rows 712–721 have the detail):

- **Bundle A, the assistant** (#432, #430, #436, #424, #411; rows 716–719): "Publish Unit 4, Day 3" in its exact form, "schedule a deploy at 6:30 am" and "cancel that scheduled deploy" are answered in code without the model; "schedule a deploy" with no time asks for one; a reply the smaller assistant is still writing after 30 seconds ends as cut off (measured: it ends 5 of 10 such replies — the other 5 had no line break — so a reply can still run to about 80 s); the Claude door works on every course in the folder; an outside assistant is held back only while a site is being BUILT, and a preview a deploy closed says "Closed for a deploy". #424 stays open for the conversational "don't send it in the morning after all".
- **Bundle B, rules and wording** (#438, #431, #426; rows 712–714): the computer is named by the contract's own `{machine}` sentences; a folder deploy that rebuilds says "deployed"; only "All Classes" or the recorded class folder is protected from removal; a screen reader names every icon-only button and tells a reference course from the live one.
- **Bundle C1, the updater and the feed** (#428 items 1 and 2; row 715): the update offer carries the notes of every newer release; the trail says when Plantoir updated itself; the feed ADDS an item per release, checked by `website/windows_feed.py` in every `build.py` run.
- **#448** (row 720): a scheduled deploy tells the teacher how it went, in a notification, every time.
- **The pictures** (#380, #370, #442, #428 item 6; row 721): every Windows picture on plantoir.app is a real window, photographed whole, staged by `--stage-scene`.

**Moved to v1.4.4 by Russell on 2026-10-07:** the dark title bar fix and the dark pictures.

Gates on this project's Windows PC (Intel i5-8365U, 16 GB, Windows 11 Pro build 26200), at `dev` `ac6d5f576`:

- `dotnet test`: Failed 0, Passed 2338, Skipped 0, Total 2338 (6 m 19 s).
- UI suite (`run-ui-tests.ps1`): first run Failed 2, Passed 51, Total 53 (23 m 18 s); both failures reproduced alone and were real — a `ToggleSwitch` and the icon-plus-text Preview and Deploy buttons had no accessible name (app fix, GUI row below), and the two-backups test sent its Ctrl-click too fast for the app (test fix). Second run Failed 0, Passed 53, Skipped 0, Total 53 (22 m 35 s). The installer was re-signed after that fix, so the shipped bytes carry it.
- `verify-deploy.ps1`: 37 passed, 0 failed, 0 skipped.
- `NamedGapLedger`: empty.

## 2026-10-03 — the 1.4.2 release branch

Branch `issue/windows-1.4.2-release`. The Windows version is 1.4.2 and its installer joins the v1.4.2 release; #424 moved to milestone v1.4.3. The updater (#337) is switched on: the feed and the public key are set, and `website/updates/windows.xml` is signed and committed. Gates on this project's Windows PC (Intel i5-8365U, 16 GB, Windows 11 Pro build 26200): `dotnet test` Failed 0, Passed 2243, Skipped 0, Total 2243; the UI suite 44 of 44 (20 m 35 s); `verify-deploy.ps1` 37 passed, 0 failed, 0 skipped; `NamedGapLedger` empty. The installer paths `/PLANTOIRUPDATE`, `/RELAUNCH`, `/NOCLOSEAPPLICATIONS` and `/RETURNTO` were run for the first time (documentation/11 has the table). The UI suite's first run was 41 of 44: at 200% display scale the Copy a Page picker gave its clickable point at twice its real coordinates, so three tests clicked the window behind and typed there — a harness fault, fixed in `DrivenApp.ClickMiddleOf` (documentation/12 → "Driving the real interface"). #380: the hero and the two colour figures are whole native window captures (`website/shots/windowshot`). #370: the six availability flags are true and the Windows card is unpinned. Still open on #380: the single-window Windows shots; on #370: Windows scenes for the v1.4.0 pictures.

## 2026-10-01 — bundle 10 ("parity remainder")

Branch `issue/bundle10-parity`. Done: #421 (start of year and the links checklist's Publish name a page whose settings cannot be added to, and count only what was put into draft or published), #422 (make room counts renames and links from what was written, names a write it could not finish — trail `making room did not finish every page`, `appliesOn: ["windows"]` — and matches declined pages by path), #420 step (a) (`includeLinked` gone: publish always takes what a page links to; the `followingLinks` cases run with no flag). #420 step (b), the two held descriptions, was MEASURED (pre-registered; this PC, the smaller assistant) and FAILED — EXC2O 161→150/220, ICS3U 160→123/220, teachers-say 220→210/250, `unpublish_pages` −11 trials, 0 inversions — so the text stays held in `measuredDepartures` — a permanent measured departure by Russell's decision, and #420 closes; the surface that ships (flag gone, text held) is better on EXC2O (161→190/220), level on ICS3U (160→160: `card: plan a publish` gained, `schedule a deploy` LOST 10→0 to `deploy_section`) and 4 points lower on teachers-say (220→210: `ctl cancel_scheduled` 10→0, declined) with, separately, ten turns at the token cap on "next day's lesson" that the score cannot see — those three regressions have their own issue (`research/ai-assist/windows-description-convergence-results.txt`, the dated note). Also (review R5): `PlanPublish` keys pages and links by path, so two pages sharing a file name no longer swap links, and an ambiguous name is asked about, each page named with its folder in the contract's `pageNameInFolder` shape. Also from Russell's answers: a section restore drops blank lines before a shared page's fence, as the mac does (Q8); the installer is per-user only (Q9); the club noun's `_meta` decision is in `file-formats.json` (Q10). `NamedGapLedger` still **empty**.

## 2026-10-01 — bundle 9 ("finish")

Branch `issue/bundle9-finish`. Done: #419 (the robocopy scan reads tracked files), #417 (the watcher's reds were a refused READ, not a partial record — the record is now read sharing ReadWrite|Delete; 30 of 30 runs green), #157 (`noCoursesYet`, `whatPublishingMeans`; `Briefing` retired), #308 (declined pages named on the plan and in every reply), #318 (already wired since bundle 5b; confirmed by a must-fail), #356 (SHA-256 pins in `fetch-runtime.ps1`). `NamedGapLedger` is **empty**. Open by ruling: #191 and #214 (a `[UiFact]` now MAKES each measurement — owed one run on an unlocked desktop), #414 (the one-process re-run found 0; the 856 run's certified count proves it ran a binary no commit contains, but not which part differed, and that is not a reproduction). #352: measured (pre-registered; this PC, the smaller assistant: model-seen 160→161 and 150→160 of 220, teachers-say 210→220 of 250, 0 inversions, 0 cut-offs) and moved — one description per tool, except `publish_pages`/`unpublish_pages`, held for the `includeLinked` behaviour (`research/ai-assist/windows-description-convergence-results.txt`). New: a `windows` issue for `publish_pages`' `includeLinked` (the behaviour #352's check found).

## 2026-10-01 — overnight parity run

Windows parity run, 2026-09-30 to 2026-10-01: eight bundles landed on `dev` in ten merges (every merge `--no-ff`), 106 issues worked. The suite went from **61 red to 0**: baseline `Failed: 61, Passed: 1486, Total: 1547` at `30c78344`; now `Failed: 0, Passed: 2209, Skipped: 1, Total: 2210` at `7a3890a1` (the skip is the native-build test, which needs a runtime).

| Bundle | dev | Totals after |
|---|---|---|
| 1 plumbing | `1ecc107c` | 53 / 1509 / 1562 |
| 2 writers | `ba73616f` | 34 / 1576 / 1610 |
| 3 trail, leases, scheduled deploys, quit | `e8bca385` | 32 / 1636 / 1668 |
| 4 preview and publish | `14600c03` | 27 / 1697 / 1724 |
| 5a assistant chain | `04d56db9` | 19 / 1774 / 1793 |
| 5b assistant, the rest | `77557c49` | 17 / 1940 / 1957 |
| 6a course creation | `87f65e7d` | 9 / 2016 / 2025 |
| 6b reference, import, Copy a Page | `4d1d1057` | 7 / 2118 / 2126 |
| 7 clubs and settings | `89fda2e4` | 0 / 2159 / 2160 |
| 8 Windows-only UI, runner, updates | `7a3890a1` | 0 / 2209 / 2210 |

- **Handed to the mac** (issues labelled `mac`): #407, #408, #409, #410, #411, #412, #413, #415, #416, #418.
- **`verify-deploy.ps1`** was run three times, after bundles 4, 5b and 6b: 37 passed, 0 failed, 0 skipped each time.
- **UI tests written and UNPROVEN** (the desktop was locked, so none has been seen passing): `ReferenceCourseUiTests`, `CopyAPageDialogUiTests`, `ClubSettingsUiTests`, `CourseSettingsSaveUiTests`, `ListTablesUiTests`, `MarksPoolRemovalUiTests` (updated), the four new `[UiFact]`s in `NewCourseWizardUiTests`, and the toast and All Backups dialog tests from bundle 8. `LinksChecklistUiTests` is the one that was run (passed 1/1, bundle 5b). Their first green run is owed on an unlocked desktop.
- **Leftover worktree folders** that `git worktree remove` could not delete (path too long; git no longer lists them, delete by hand): `plantoir-bundle5a`, `plantoir-bundle5b`, `plantoir-bundle5b-b`, `plantoir-bundle5b-c`, `plantoir-bundle6a`, `plantoir-bundle6b`, `plantoir-bundle6b-copy`, `plantoir-bundle7`, `plantoir-bundle8`, all beside the main clone in `Desktop\Developer`.
- **Still open:** #157 (two wording keys kept against it), #308 and #318 (partly landed), #352 (the #114 half needs a routing measurement), #370 and #380 (website flags and picture retake; no installer cut), #191 and #214 (unmeasured), #414 (Copy a Page fuzz: reproduce or explain the 856), #417 (a timing flake in `ScheduledPublishWatcherTests`).
- **#337 (updates)** was on `dev` but inert on this date (switched on 2026-10-03, above): no feed, no key, no release, and the download stays at 1.1.0. What Russell must do and test before a release is in the closing comment on #337 (key generation, the feed, and the unexercised installer paths `/PLANTOIRUPDATE`, `/RELAUNCH`, `/NOCLOSEAPPLICATIONS`, `/RETURNTO`, the refusal relaunch).

What each project in the solution is, and what state the app is in. First take
built overnight 2026-08-11 by Claude Code, per `WINDOWS-HANDOFF.md` — a file
since absorbed into [`documentation/`](../documentation/README.md) and deleted;
the assist subsystems folded
into `main` on 2026-08-14. Everything below was **verified live on the
maintainer's Windows 11 machine** (WSL2 + Ubuntu-24.04 + Docker Engine 29, no
Docker Desktop) unless marked otherwise.

## Layout

| Project | Role |
|---|---|
| `Plantoir/` | The WinUI 3 app (unpackaged, self-contained Windows App SDK, PerMonitorV2 DPI). Bundles the full toolchain recipe under `Toolchain/` and mirrors it into each working folder's `.toolchain/`. |
| `Plantoir.Core/` | All logic, UI-free: config round-trip, container naming, port leases, build freshness, archiver/restorer, section adder, ConPTY process, transcript builder, script runner, milestones, question parsing, failure explainer, catalogs, workspace/toolchain services — **and the whole assist subsystem** under `Assist/` (18 files): `AssistWorkspace`, `AssistAgent`, the plans (`PublishPlan`, `ReDatePlan`, `SyncPlan`, `InsertPlan`, `NewClassesPlan`, `CurriculumMentionsPlan`), `LinkGraph`, `SectionIndex`, `Timetable` and `TimetableMemory`, `DateAudit`, `UndoHistory`, `ScheduledDeploy` and `TaskScheduling`, and `WorkLease` (`Briefing` was retired on 2026-10-01, #157: `explain_publishing` says `AssistWording.WhatPublishingMeans`). |
| `Plantoir.Tests/` | xUnit suite that runs **without Docker**: `dotnet test`. No count is given here on purpose — it rots. Classes touching process-wide state (preview leases, the publish registry) share a serialized collection — see `SharedActivityState`. |
| `PtyDriver/` | Console harness that drives the launchers under a ConPTY with scripted prompt replies — how the E2E runs below were performed. |
| `Plantoir.UiTests/` | Drives the REAL built app through UI Automation (FlaUI/UIA3), for what a unit test cannot reach — see "Driving the real interface" below. Opt-in: skipped unless `PLANTOIR_UI_TESTS=1`, and compiled by a SOLUTION build (not by the per-project commands used day to day). References `Plantoir.Core` only, never the app project — the Windows App SDK has no business in a test host. |
| `Plantoir.UiTests.FirstInstall/` | The first-install rehearsal driver (#976). Not a test project and in no solution or suite: a self-contained single-file `win-arm64` console program that runs inside a CLEAN Windows machine's desktop session and does what a teacher does — downloads `PlantoirSetup.exe` through Edge (so it carries the from-the-internet mark), runs it, opens Plantoir, sets up a working folder, adds the example course and previews it. Each step names the windows it expects (`WindowRules.cs`); any other window or dialog ends the run, named, with a screenshot. Three kinds of window get a 20 s grace instead of an answer: one of Plantoir's still being made (no readable class or title), one with no title and no words, and one UI Automation lists but cannot read at all (its properties throw). A window in its grace is tolerated, not allowed. Each unreadable window is numbered and recorded when it appears, and again when it can be read or is gone. UI Automation's element comparison tells such windows apart, because their handles all read 0x0, and a comparison that throws is recorded. A readable window is then judged by the ordinary rules; one still unreadable after 20 s ends the run. Separately, if at least one unreadable window has been present at every look for 20 s, the run ends whichever windows they were, so a window the comparison cannot follow is still caught. No watch and no step may finish while any window is in its grace: when the time is up, the driver goes on looking (a SETTLING line in the log) until each such window is judged, has gone, or has ended the run, for at most 60 s more, and running out of that time is not PASSED. After the last step the driver watches the desktop for 60 s more (step 7: a firewall alert raised when the preview server binds comes a second after the address answers). It writes PASSED only if that minute, and any settling after it, is clean, with at least one successful look per three seconds of the minute and no stretch of it longer than 10 s without one. Every look is recorded: a look that could not read the desktop is counted as failed, not as a look, and the record's gaps run on through it. No step, watch or PASSED is decided except on a successful look made within the last 5 s; when the last look failed, or is older, the driver looks again, and if no look succeeds in 60 s the run is a DRIVER PROBLEM, cause coverage (the fifth review: a final minute whose last 40 s were all failed reads used to end clean on the pending set of an older look). A popup inside Plantoir's window that cannot be read is pending like any unreadable window. PASSED is written straight after a look made for it; the notes, screenshot and uploads come after `result.txt`. The installer's launch call must have had real looks too. `result.txt` carries the record as values (looks, failed looks, the largest gap and the stage it was in, the age of the last look at the decision, the final watch's largest gap, and the times of the final watch's start, the decision and the first sighting of the window stopped on); `--self-test-fail-looks-after N` makes every look from N s into the final watch fail, for the Mac's failed-looks self-test. Driven from a Mac by `vm-tools/win-rehearsal.py`, which restores the Parallels VM's clean snapshot. It also watches for a UAC prompt from outside the guest, asking as SYSTEM whether consent.exe is running, on a thread of its own: once a second (a probe takes about 0.2 s) from before the driver, and so the installer, is launched until the decision, with a probe asked after the driver's result that must be answered. Its screen captures and their OCR, every 5 s, run beside it and cannot delay a probe. Failed probes are counted by the gap they leave between answered ones, not in a row: a PASSED needs no gap over 10 s anywhere in the run, and a gap of 120 s stops it. Measured, not assumed: Windows did not withdraw an unanswered UAC prompt in 20 minutes (`win-rehearsal.py --measure-uac-timeout`, snapshot 00, run `win-uac-timeout-2026-11-18-192158`: consent.exe seen 5.6 s after the request, still running, with the prompt's words on the capture, when the measurement stopped at 20 minutes), so a prompt cannot come and go inside a 10 s gap. A UAC prompt is reported ahead of any stray window found beside it. The driver sees nothing of a UAC prompt, so UAC is caught by the Mac side alone. In `--self-test uac` (runs `win-rehearsal-2026-11-18-180608-selftest-uac` and `-182736-selftest-uac`, snapshot 00 with PromptOnSecureDesktop 0) the prompt was on the ordinary desktop and on the Mac's capture for 45 s. In those 45 s the driver kept looking every second, and it recorded no new top-level window and no unreadable one: UI Automation gave it no element for the prompt at all. Its consent rule in `WindowRules.cs` and its unreadable-window rules therefore cannot catch a UAC prompt. So the uac self-test proves the Mac side is enough on its own, deciding by values. It requires that a periodic probe, not the one after the result, saw consent.exe while the prompt was held up, that the capture taken at once shows the prompt (OCR reads its words), and that the run's outcome is PRODUCT STOPPED with UAC as its cause whatever the driver said (a driver PASSED included); a test pins that the rehearsal's own decision path makes that call. It records what the driver noted only as information. One earlier run (`win-rehearsal-2026-11-18-132158-selftest-uac`) noted one unreadable window, handle 0x0, 2 s before the Mac saw consent.exe; later runs never saw one, so it was not the prompt, or not reliably. The Mac decides the outcome. The driver's `result.txt` carries fixed fields (status, stage, cause, the window's process, whether it stopped while settling, and the look record above), it sends small value files as it goes (`driver-started-PID.txt`, `step-N.txt`, `final-watch-began.txt`), and the Mac and its self-tests decide by those values, never by searching a sentence or a log. A driver PASSED stands only with proof of looking on both sides for the whole run: the Mac's probes as above, the driver's record with no gap over 10 s and its decision on a look under 5 s old, and the final minute seen by the Mac to run its length; otherwise the outcome is DRIVER PROBLEM, cause coverage. The failed-looks and probe-gap self-tests make each kind of gap happen for real and show it refuses a clean result. The last line of every report is the Mac's final outcome (PASSED, PRODUCT STOPPED or DRIVER PROBLEM); the driver's own line in it is labelled as the driver's. References nothing in this repository, because the machine it runs on has only the released app. |
| `Plantoir.UiTests.FirstInstall.Tests/` | Plain xUnit tests of that allow-list, `net9.0` (not `-windows`), compiling `WindowRules.cs` alone, so they run on any machine with the .NET 9 SDK, a Mac included, with no desktop and no VM: `dotnet test windows-app/Plantoir.UiTests.FirstInstall.Tests`. In no solution and no suite; every build of the driver runs them first. |
| `Plantoir.Mcp/` | On `main` (`Plantoir.sln` lists it) and **it ships**: `publish.ps1` publishes it, copies `plantoir-mcp.exe` into the app's own output beside `Plantoir.exe`, and includes it in the signing list. A standalone MCP server exposing one working folder to an AI assistant. Load-bearing at runtime — `Plantoir/Services/ClaudeCodeLauncher.cs` looks for it beside the app, and `Plantoir/Services/McpClient.cs` launches it. See [its README](Plantoir.Mcp/README.md). |

## Where parity stands

> **"item N" in this file means the retired numbered list.** Until 2026-09-08
> outstanding work lived in a numbered list inside `WINDOWS-HANDOFF.md` (a file
> since deleted), and
> prose written before then cites it by number. Those numbers no longer resolve
> to anything: what was still open became [GitHub
> issues](https://github.com/russellgordon/plantoir/issues), and what was done
> is recorded in `GUI-IMPROVEMENTS.md`. The numbers are left in historical
> sentences rather than rewritten, because the sentence around one usually says
> what it was; `git log` has the list itself if a number ever needs chasing.

**The open work is in [GitHub
issues](https://github.com/russellgordon/plantoir/issues?q=is%3Aopen+label%3Awindows),
and this file no longer keeps a second copy of it.** Until 2026-09-08 it did —
a table here mirroring that numbered list — and the two drifted
exactly as often as anybody edited one and not the other. The count in this
section was wrong the last three times it was read, which is what settled the
argument for having one home rather than two.

Five items were open when the cutover happened, and they are now issues #66
and #68–#70 plus #99 (which absorbed the old item 42). Everything else on that
list was struck through as done; the shipped record of it is
`GUI-IMPROVEMENTS.md` and
[`documentation/13-windows-port-archive.md`](../documentation/13-windows-port-archive.md).

```bash
gh issue list --repo russellgordon/plantoir --label windows
```

Two more things worth knowing here:

- **The deploy gate exists, and item 36 decided what runs it (2026-09-07).**
  `verify-deploy.ps1` publishes to every destination and every pairing against
  real sites and fetches each one back: 36 passed, 0 failed on 2026-09-06. It
  needs three credentials, the network and about twenty minutes, and it creates
  real sites that nothing deletes — so **it stays opt-in and no suite runs
  it**, which was the right posture all along; what was missing was anybody
  being told. Now `.githooks/pre-commit` says so when a commit touches the
  publishing path (a warning — it never blocks, because those files change on
  16 of every 22 active days and a blocking hook would be `--no-verify`'d once
  and never fire again), and `RELEASING.md` requires a run with **nothing
  skipped** for a release that changes that path.

  **The bigger find was underneath it.** `verify.sh` runs fifteen shared
  `scripts/test_*.py` files on the mac; Windows ran **none** of them. All
  fifteen pass here, so `PythonToolchainTests` now runs every one inside
  `dotnet test` — 156 tests in about eight seconds, no Docker, no network, no
  credentials. A rejected first design (a stamp file recording when
  `verify-deploy.ps1` last passed, with a unit test reddening when the
  publishing files changed afterwards) is written up in `documentation/07-deployment.md`
  `git log -- WINDOWS-HANDOFF.md`, with the measurements that killed it — that
  write-up went with the retired list rather than into `documentation/`.
- **The unit suite is green**: 911 passed, 0 failed at the time this section
  was written; 945 after the folder-problems front end, and 979 once
  parity-tail was merged into it and the overnight capture was added. `dev` stood
  at 668 passed with 5 failing contract tests before this series; those five
  were each a real gap between what the contract says Windows does and what it
  did. **1,029 passed with 2 skipped** after item 29 wired the contract case
  lists this suite was not reading (2026-09-06), and **1,125 with 2 skipped**
  after item 31 wired the twelfth of them — `linkRewriting`, which item 29's
  audit missed because it was added the same day (2026-09-07); 1,150 with 2
  skipped once items 26, 31, 33 and 34 were all merged; and **1,153 with 1
  skipped** once item 25 made the wizard ask the skeleton question; and **no
  skips at all** once the frontmatter-key divergence was decided in this
  app's favour on 2026-09-07 (item 38) and its test rewritten to assert
  migration.

## Every contract case list is now RUN here (2026-09-06)

Closing the gap the 2026-09-06 contract audit found. Twenty-three lists the mac
suite ran and this one did
not read — none unreachable, each simply a test nobody had written.
`contracts/README.md` now names which class runs which, so the audit does not
have to be repeated.

**What matters for anyone adding to this suite** is the shape those tests
take, because the old ones were the wrong shape rather than absent:

- **Ask each list both ways.** Walking the contract and looking each case up in
  the code cannot notice a case the CODE has and the contract does not. Every
  gap item 29 found came from the reverse direction — an extra credential
  request, twelve extra MCP tools, sixteen extra tool arguments.
- **Assert completeness.** A hand-written mirror answers the cases that existed
  when somebody read the contract, and stays green when the mac adds one. Where
  cases are prose keyed to behaviour, map each to a named test by `nameof` and
  assert nothing is unmapped. Map to NAMES rather than draining a shared set:
  xUnit builds a fresh instance per `[Fact]` and fixes no order, so a set filled
  by ten tests and emptied by an eleventh passes on whatever happened to run,
  and reports nothing under `--filter`.
- **Read the source only against the thing that decides.** Several rules live in
  `Plantoir/` — the wizard, the composer, the report dialog — which this project
  does not reference. Reading their source is legitimate (`ParsingTests` does it
  for the `.ps1` launchers) but must be anchored: bare containment passed with a
  guard moved into a comment, and with it deleted from one of two arrow keys.
- **A new collection, `ProcessEnvironment`**, beside `SharedActivityState`, for
  tests that read or write process-wide environment variables. Same reason:
  `PLANTOIR_BUILD_ROOT` is global, and a class setting it while another calls
  `BuildOutputLocation.BuildsRootFor` is a rare flake that looks exactly like a
  production bug about where built sites go.

## Driving the real interface — what the table points at (2026-09-06)

The Layout table above says "see 'Driving the real interface' below" and, until
now, there was no such section: the prose lives in
[`documentation/12-windows-app.md`](../documentation/12-windows-app.md). Rather
than move it, here is what a session needs to know before running the suite,
and the one thing measurement added.

Run it **from the repository root**, not from `windows-app/`:

```powershell
.\run-ui-tests.ps1                 # all of it, about 4 minutes
.\run-ui-tests.ps1 -Filter "FullyQualifiedName~TheSheetCloses"
```

**Two switches, both added 2026-09-07 with item 35.** `PLANTOIR_UI_KEEP=1`
stops the run deleting its temporary folders — every test's, not just a failed
one's, since the teardown cannot know the outcome — and the runner prints each
path. A test that fails INSIDE the app has almost nothing to say from outside
it, and the evidence (that run's `startup.log`, its trail, its per-run
launcher log, its working folder) was being deleted on the way out. And the
runner now sweeps orphaned `powershell.exe`/`python.exe` children afterwards,
matched on **this run's token** — minted by the runner and folded by
`DrivenApp` into every folder name (`plantoir-ui-<run>-<8 hex>`) — because
matching the folder prefix would kill a parallel run's live launchers and a
developer tailing a kept folder's log. Killing `Plantoir.exe` kills only
`Plantoir.exe`: the whole-tree kill lives in `ConPty.Kill()` and runs when the
APP ends a task, not when the app is ended from outside.

It closes a running Plantoir before it starts, says so, and does not reopen it.
`--state-dir` moves the whole state folder for the run, so nothing of the
teacher's is touched.

**One test is intermittent, and it is worth knowing which.**
`SpecialFoldersHelpUiTests.TheSheetShowsAMarksFolderTickedButNotYetSaved`
failed once in a full run on 2026-09-06 and then passed twice — once alone (30
s) and once in a full run (6/6, 3 m 16 s). It is the test that ticks a marks
folder and waits for the sheet to be rebuilt through the dispatcher, and it
already retries for 20 seconds at half-second intervals. Nothing in that run
had touched the app or the UI project.

**It did it again on 2026-09-07**, on the item 35 branch: one failure in a
full run, then a pass alone (23 s) and a pass in a full run (9/9, 4 m 13 s) —
so roughly one full run in four across two days, on a branch that had touched
neither this test nor the view it drives. Second data point, same conclusion.

**So: if it fails, re-run it alone before believing it.** Recorded because an
intermittent nobody writes down is rediscovered as a regression by the next
session, which then goes looking for a cause that is not there. If it starts
failing in isolation, that is different and is a real finding — the retry is
generous enough that a genuine break would not hide behind it.

## A model layer exists ahead of its UI — four types nothing calls yet (2026-09-06)

`SpecialFolderRenamer`, `FolderPathRewriter`, `CloudSyncedFolder` and
`CloudSyncWording` are built, documented and under test, and **nothing in
`windows-app/Plantoir` calls any of them.** That is deliberate, not an
oversight: items 13 and 18 were taken as far as they could go without
inventing teacher-facing wording and dialogs, so the rules landed first and
the views are what remains.

Grep for callers and you will find none — that is the expected answer, and it
is written here so nobody concludes they have missed a wiring step or deletes
the types as dead code.

## Parity run, bundle 8: test hygiene, backups, the toast, updates (2026-10-01)

Branch `issue/bundle8-windows-ui`. Manual: doc 12 → "Bundle 8"; doc 11 →
"Updating itself on Windows".

- **The unit suite keeps out of the teacher's state** (#285, #179): a
  module-initializer redirect, a per-file source tripwire (Plantoir, Core,
  Mcp; PowerShell-in-strings too), a guard that throws on a real schtasks
  registration, and the wrapper's two run-time folders behind a TEMP-only test
  variable.
- **Backups** (#283, #187, #161): sizes (logical), All Backups with Extended
  selection and one counted button, held backups kept (this app's open
  conversations; an outside assistant's newest via its `assist` lease); a
  same-second backup waits for the next second; zipNames moments read against
  the Gregorian calendar. #101 confirmed by test, no change.
- **The scheduled-publish toast** (#324): posted by the run, a click decided
  from the contract's `onClick` cases. Unproven on a real click.
- **Accelerators** (#191): guarded under a ContentDialog; NOT measured.
  **#302**: the picker path bar's 520 limit dropped; not checked by eye.
  **#214**: not measured. (Bundle 9: both now have a `[UiFact]` that MAKES
  the measurement — `AcceleratorUnderDialogUiTests`,
  `PanelHeightUnderSqueezeUiTests` — owed one run on an unlocked desktop.)
- **The UI-test runner** (#155): startup.log says when stdio is redirected;
  never closes a busy Plantoir; sweeps only the killed pid's leases;
  `ConPtyProcess.Start` zeroes its std handles (measured: leak reproduced, then
  gone).
- **Updates** (#337): the rules, gates, wording, installer flags, the
  NetSparkle engine with our own dialogs, Check for Updates…, and all eight
  trail events. Inactive by design: the feed and key are empty until the
  first release that ships it.

## Parity run, bundle 6a: course creation and the smaller course pieces (2026-09-30)

Issues #169, #250, #252, #349 (the wizard's skeleton: declining the ready-made
pages offers the subject's skeleton and keeps its curriculum, the toggle
restores both ways, "an English skeleton"), #348 (the marks floor counts
folders on disk; Revert records the exclusions it put back), #316 (an
unreadable trail in a problem report), #320 (reopening the last working
folder, or saying why not), #355 + #389 (Get Ready for the Start of the Year:
the rule, the MCP pair, the section menu sheet and its undo; check_section's
third group), #345 (one coverage map per curriculum folder: the code rule,
plural resolution from the disk, protection, checkboxes, the rename, the
folders help, `curriculum maps built`) and #360 (the How I Teach row; every
assistant zip on the trail). The Starting Content decisions moved into Core
(`WizardStructure`, `NewCourseAnswers`) with six goldens from the old rule.
Ledger entries deleted: ten trail events, three wording keys from #355 plus
two from #360, `curriculum_folders`, and the declined-skeleton newCourse case.
Still open from these issues, said in `documentation/12-windows-app.md`: the
start-of-year Go does not stop and restart the preview, the club case waits for
#274, and
`courseIsBeingCopied` (the course is not counted busy while `plantoir-mcp`
zips it).
## Parity run, bundle 6b: reference courses, importing, Copy a Page (2026-10-01)

- **#241 / #298 — courses kept for reference.** Marker read strictly, school
  years, the shelf rule, Keep a Copy (staged, claimed, one failure line), the
  NTFS lock (deny entries; `ReferenceLock`), every deploy door refusing on the
  marker alone (15, tabled in `documentation/12-windows-app.md`), the MCP write
  gate on each tool's own ReadOnly flag, the withheld interface and the
  read-only summary, upkeep on every folder read. The shared build no longer
  publishes a hidden page whose file is read-only (`_writable`).
- **#244 / #245 — Import Courses for Reference….** Modern layout only (the
  older layouts are mac-only by decision). Stream copy with a bytes progress
  bar and Stop; 507 MB in ~5.4 s on this PC.
- **#247 / #258 / #384 — Copy a Page** (see the bundle's ready note).
- **Not measured yet:** OneDrive with locked files, an elevated token, and
  what Obsidian for Windows shows on a locked page (so
  `obsidianOpensThemForReading` is not said here).

## Parity run, bundle 5a: the assistant chain through AssistAgent (2026-09-30)

Branch `issue/bundle5a-assistant-chain` (built on `issue/159-settle-the-day-once`).
Done, in order, all at the seam where `AssistAgent` makes a call: #159 (the day
settled once — reviewed, and #144's four excusals retired), #180 (course and
section bound to the window, another course refused), #196 (`finish_reason`
carried out of `IChatModel.Ask`; stopped or unreadable replies run nothing and
are wound back), #262 (an empty call runs only when the window supplies
everything; `noCourseNamed`), #217 (hide is unpublish; an echoed reply refused
and wound back), #193 + #260 (deploy at a time in code, settled once with DST
handled, scheduled card asks about the moment; `plantoir-mcp` refuses a bare
time), #281 + #288 (asked, or spelled, in the transcript only), #261 (what a
schedule replaces, read by task name). New test classes:
`WindowBindingContractTests`, `CutOffAnswerTests`, `HideAndEchoContractTests`,
`DeployAtATimeContractTests`, `TimeAskedInCodeTests`, `ScheduleReplacesTests`.
The reasoning is in `documentation/10-local-ai-assistant.md` → "The Windows
half of the assistant chain".

## Parity run, bundle 5b: the assistant, the rest (2026-09-30)

Branch `issue/bundle5b-assistant-rest` (with bundle 5a merged in). Done: #350
(a tool the model was not offered is refused), #352's #197 half (a page list
naming no page; whole-unit openings; an open-ended publish refusal Windows never
had), #344 (settings read at the call; the schedule card read the window's
snapshot), #165 (a partial publish answers), #164 (argument names on the
trail), #203/#342 (the walk stops at a class both ways, and says so), #359
(Markdown-style links; check_section names ten), #305 ("What does X link to?"
in code, transcript only), #340 (How I Teach tools), #210 (Codex door; start-up
not measured, Codex not installed; since #468 it holds its course as the Claude
door does), #440 (add_next_class's unit and days hidden from the router; units
and counts answered in code; settler S3). Partly: #114 (needs a routing
measurement), #392/#399/#405 (the links checklist's LOGIC, record and release
are done and contract-tested; the WinUI sheet, the menu item and when it is
shown are not built). Manuals: doc 10's "On Windows" sections; doc 12 → "The
links checklist on Windows".

## Parity run, bundle 4: preview and publish mechanics (2026-09-30)

Branch `issue/bundle4-preview-publish`. Done: #278 (address read by whole
lines), #233 (the quiet after the server line bounded, three outcomes, trail
line), #286 (forty port blocks, the sentence, the launcher trail line),
#386 (no preview of a section being deployed: window, assistant, preview.ps1),
#391 (windowless deploy/rebuild `--non-interactive`, exit 3 named), #395
(Cloudflare remade, from the app's and plantoir-mcp's own runs), #304 (partial
publish folder refused; deploy.ps1 resolves once), #358 (fingerprint rule 2),
#319 and #307 (measured; the re-probe now binds loopback too). Checked, nothing
to change: #393, #401. Then completed on the same branch: #272 (Preview
Again, the saved-settings sentences, both events), #357 (Deploy and the
schedule sheet read the saved file), #395 (the overnight Cloudflare leg is
captured). Measurements and reasons:
`documentation/12-windows-app.md` → "Preview and publish mechanics that match
the mac (bundle 4)" and `documentation/03-launcher-scripts.md` →
"preview.ps1's own port walk…".

## Parity run, bundle 3: the trail, leases, scheduled deploys and quit (2026-09-30)

Branch `issue/bundle3-trail-leases`. The scheduled deploy is Plantoir now, not a
baked PowerShell script, and every rule decided at its moment lives there.

- **The trail keeps every line** (#303): a named mutex round each append.
  Measured two processes × 500 lines: 4,444 of 5,000 kept before, 5,000 after;
  the share-flag fix alone kept 4,512 and was rejected.
- **Leases both ways, take-then-check** (#289): another program's build,
  publish OR preview declines a build (never a write); Deploy claims before it
  stops the preview; `plantoir-mcp` stops its own launcher before leaving.
  `workLeases.declining` (32 since #438; the two `copy` cases
  marked `appliesOn: ["windows"]` run here only), `.liveness` (17 of 19), `workLease.bodyCases` (7).
- **A scheduled task runs `Plantoir.exe --run-scheduled-deploy "<name>"`**
  (#347): the lateness window (#239), a ten-minute wait for the course (#289),
  whether it still stands, the settings as they are now, then the wrapper.
  Verified end to end through the real Task Scheduler on this PC. Old tasks
  drain. `theDestination` (11 of 12), `howLateIsTooLate` (10),
  `storedValueCases` (7), `savingSettings.scheduledDeploys` (5).
- **One task per section per working folder** (#309), found by the folder its
  job names; records filed under the folder id.
- **Removing a course turns its deploys off FIRST** (#239), asked of the
  scheduler, this folder only; the contract's sentences.
- **A failed build is `buildDidNotFinish`** (#297); `whichKind` (6) through the
  real wrapper.
- **The notice arrives while the section is open** (#218): one app-wide
  watcher; records moved in whole (40 of 40 readable at the first event,
  against 18–21 of 40 written in place).
- **Quitting asks** before leaving a publish or preview build (#231), never on
  a log-off; the WSL release is hardened (leases, a launcher scan, docker must
  answer, System32 paths). Both `appliesOn: ["mac"]` keys deleted.
- **Every destination named** (#400, #404); the unpublished-classes note gone.

Not built: #324 (clicking the toast — the toast itself, #212's Windows half, is
first; both built minimally in bundle 8). Manuals: doc 07 → "On Windows since bundle 3"; doc 09 → "On Windows
since bundle 3 (#289)" and "(#231)"; doc 09 → "On Windows: a sharing violation".

## Parity run, bundle 2: frontmatter and page writers (2026-09-30)

Branch `issue/bundle2-writers` (on top of bundle 1). Every writer of a page's
frontmatter now finds the block the way the build does and takes a key's whole
value with it; every link reader and rewriter shares one definition of code.

- **Dates are Gregorian whatever the PC's region** (#144): `DateText`, taken
  from the cloud branch `claude/nifty-mendel-q8ixto` (cherry-picked, not
  re-derived).
- **One fence rule, asymmetric** (#308/#188): the closing fence is column-0
  dashes only; the opening may be indented. **One `ReplaceKeyLine`** (#284) for
  `SetTitle`, `SetCreated` and the section copy and scaffold. **No key goes
  where the block has no column-0 place for it** (#186): `SetDraft` and
  `SetCreated` answer `NoRoomForAKey`. *Not yet*: the plan, re-date and
  make-room callers naming the declined pages (four wording keys still ledgered
  on #308).
- **Adding a section** (#282) finds `----`, a blank line before the fence and a
  trailing space, splices by line, keeps CR LF, and records `section added`.
- **Restoring a section** (#177/#182) uses the shared finder, carries each key
  WITH its lines, and counts and says the pages it had no room on.
- **Duplicating a class** (#200): a forced-hidden copy can be published again
  (B), the guard asks what the insertion created (A), the refusal admits other
  classes may have moved (C); the plan card warns the undo will not help (#346).
- **Renaming the word for a unit** (#158): Course Settings → Rename…, the whole
  feature, off the UI thread. The sheet is compiled, not driven.
- **Links** (#339/#318/#338): `MarkdownCode` (0 disagreements with
  `markdown_code.py` over 12,490 pages), escaped pipes, angle-bracket links in a
  folder rename.
- **The unreadable front page gets its own card** (#300).

Contract lists run here for the first time: `datesAndTitles.writingCases` (16),
`sectionNumbers.addingKeysToAPage` (8), `backups.restoringOneSectionsKeys` (6),
`readingALink.cases` (52), `renamingTheUnitWord.cases` + `.linkCases` (7 + 6).

## Parity run, bundle 1: red means something again (2026-09-30)

The suite pulled on 2026-09-30 (dev `30c78344`) was **61 failed, 1486 passed**,
every red mapped to an open issue (`plantoir-windows-run\logs\baseline-red-list.md`
on Russell's machine). Bundle 1 (branch `issue/bundle1-plumbing`) was plumbing,
so that "did I break something?" has an answer again:

- **`NamedGapLedger` is the parity milestone's burn-down list** — 58 trail
  events, 140 wording keys, 7 config keys, 3 model requirements and 3 contract
  cases held open BY NAME against their issues; `documentation/12-windows-app.md`
  → "Named gaps" has the table. A green totals line now means "green with the
  debts the ledger names", and the ledger fails the day one is paid.
- **`AssistWording_MatchesContract` walks `assist-wording.json`** by reflection
  in both directions (#157); green since parity bundle 5a (#193's `deployApproval`).
- **`ActivityTrailWiringTests`** is the source scan the mac has: every declared
  event must have a call site. All do; `assistant asked` is written by
  `NotePrompt`, and the scan knows that.
- **`PLANTOIR_DATED:`** is hidden from the console and recorded on the trail,
  from the console and from a scheduled publish's record (#279).
- **A payload course gets its manifest's marks pool** (#317).
- **Five shared Python test files that failed on Windows pass or skip with a
  reason** — one was a real shared bug (`build_site._is_draft` did not read
  CR LF, and the native build writes CR LF copies).

## ONE activity-trail event is declared without an emitter (2026-09-06; six were then, and all six have callers since 2026-09-07)

> **Superseded 2026-09-30:** `ActivityTrailWiringTests` now checks this on
> every run, including `AssistantAsked`'s helper; the paragraph below is kept
> as the history of why the scan exists.

`ActivityTrail.Event` named `folder renamed`, `folder created`,
`synced folder noticed`, `synced folder accepted` — and, found 2026-09-06,
`settings saved` and `settings could not be saved`, which belonged to no
unbuilt view at all: `CourseSettingsView.Save_Click` wrote the config and
recorded nothing, while the mac records both. All six are emitted now: the
settings pair since item 28 (2026-09-07), the synced-folder pair the same day
with item 18's views, and `folder renamed` / `folder created` with item 13's
rename sheet (`CourseSettingsView`, `RenameFolderAsync` and
`CreateFolderForNewEntry`). The one member still without a caller is
`AssistantAsked`, whose line is written by `NotePrompt` without going through
the enum — a recount should not be surprised by it. Check with `grep -c` per
member rather than trusting this paragraph: a green suite that is green on a
promise is exactly the kind of thing a later session should be able to find,
and `ReclaimedProcesses` is the worked example of parsing something out and
putting it on the trail.

**There was a FIFTH, and this section did not name it: `folder problem
repaired`.** Declared when the trail was built, still with no call site on
2026-09-06 — it got one that day, when item 21's front end landed (`Models/
SiteHealthRepair.cs`). It is recorded here because the omission is the
interesting part: this section was written by listing the events somebody
remembered were promised, and a fifth had been dead long enough to stop being
remembered. The honest way to keep this list right is
`grep -c` per enum member, not recollection.

## The subsystems that table does not name

- **A built-in local AI assistant.** `Views/AssistWindow.xaml` holds the
  conversation, `Plantoir.Core/Assist/LocalModel.cs` runs a small model natively on
  the Windows host with Vulkan GPU acceleration (no account and no internet), and
  `Services/McpClient.cs` drives the same `plantoir-mcp` Claude Code drives — one
  tool surface, two front ends.
- **Claude Code integration.** `Services/ClaudeCodeLauncher.cs` writes
  `%LOCALAPPDATA%\Plantoir\assist\mcp-<CODE>.json` and launches `claude` with
  `--mcp-config … --strict-mcp-config`, so a teacher's own MCP servers are
  neither used nor disturbed. The doors sit on the rows' context menus, under
  **Revise With ▸** since #491 (2026-10-15): **Claude…** (only when Claude
  Code and the server are both present), **Codex…** (#210) and, on a section
  row, **Local AI Assistant…** — until #491 "Revise with Claude…" and
  "Revise with local AI assistant…" at the top level.
- **A cross-process lease protocol**, `Plantoir.Core/Assist/WorkLease.cs`.
  Four kinds — `assist`, `preview`, `publish`, `build` — as files under
  `courses/.internal/activity/`, so the app and the server can see each
  other's work. Only a *build* is exclusive; previewing during a conversation
  is the point.
- **Scheduled deploys**, `Assist/ScheduledDeploy.cs` + `TaskScheduling.cs`,
  reached from the sidebar's Schedule Deploy… and from the assistant, sharing
  one refusal path so the two cannot drift.
- **Three publishing destinations**, not one: `deploy.ps1` handles Netlify,
  Cloudflare Pages and a plain folder. Since 1.9.3 it reads the course's own
  destinations when none is typed (#739), keeps a saved token it could not
  check (#705), and rebuilds a site an earlier version built before a folder
  publish (#749); the app names every leg, Netlify included.
- **Folder-problem checks, surfaced in two of the three places they can
  happen.** The shared Python checks a course's folders during every build and
  prints one `PLANTOIR_HEALTH:` line per problem;
  `Plantoir.Core/Models/SiteHealthFinding.cs` parses them,
  `SiteHealthRepair.cs` puts right the two that can be put right, and —
  since #734 — the section's Problems tab, its sidebar warning and its one
  alert show them, from the record the build writes (`SectionProblems`;
  before that `Views/FolderProblemsDialog.cs` showed them on every build). The app's preview and
  publish are covered, and so is the assistant (`Plantoir.Mcp/
  LauncherRunner.cs` lifts findings out and `SiteHealthFinding.Appending`
  says them). **The scheduled deploy is covered too, differently**: it runs
  with the app closed, so its wrapper captures the build's output per run,
  copies the marker lines into a per-course-and-section record, and the
  section's own view reads that record the next time it is opened — consumed
  as it is read, and cleared by a clean run.

## Proven end to end

Screenshot- or exit-code-verified on real hardware: the launchers
(`setup.ps1 --install-example` built the image locally from the recipe and
installed EXC2O; `preview.ps1 EXC2O 1` served HTTP 200; `deploy.ps1 EXC2O 1`
took its token from Windows Credential Manager and put 233 files live over
https); the app itself (folder picker → sidebar → section view, with Preview
building and embedding the live site in the app's WebView2, and Deploy running
end to end in-app — "Uploading your pages… 25 of 230" at Step 7 of 8, the
count parsed from launcher output); and the wizard's answer pump against the
real `setup_course.py`, exit 0 with a full course scaffolded, using the same
`NewCourseCreator.PumpAnswers` the Create Course button uses.

**Since bundle 11 (2026-10-01) through the real window, by `[UiFact]`s that run
the real launchers** (opt-in, `run-ui-tests.ps1`): the wizard's Create then
Preview, with the served front page read back over HTTP, the preview pane
shown to have loaded that same address (status 200), and Stop silencing it (`WizardToPreviewUiTests`); Import Courses for
Reference… through the Windows folder picker, the course shelved by year and
locked on disk (`ImportForReferenceUiTests`); a course kept for reference —
summary, no Deploy, pages locked, Keep a Copy and its refusal
(`ReferenceCourseUiTests`); Copy a Page through its checklist, both copies
hidden, the published destination without them, and three refusals
(`CopyAPageEndToEndUiTests`); and Deploy to a folder, the published folder
read back (`PublishToFolderUiTests`). Doc 12 → "A test that runs a launcher".

## The hard-won platform lessons (do not relearn these)

1. **ConPTY std-handle hygiene.** A process whose own stdio is redirected leaks
   stale pipe handles into its pseudo-console child; `wsl.exe` then reports
   "the input device is not a TTY". A GUI app is naturally clean; test
   harnesses must get their own console (ShellExecute / `Start-Process`).
2. **ConPTY soft-wrap duplication.** A line longer than the screen that wraps
   on the bottom row while something redraws arrives as two lines, the second
   starting with the boundary character again. 400 columns turned out NOT to
   be wider than every real line (a 611-character `PLANTOIR_HEALTH:` line,
   #662), so the app's runs now get 8,192 (`ConPtyProcess.LauncherColumns`);
   PtyDriver keeps 400. Doc 12 → "How wide the console is, and why".
3. **PowerShell 5.1 + `$ErrorActionPreference='Stop'` + wsl stderr.** Any
   redirected call site (`*> $null`) turns wsl's stderr into terminating
   ErrorRecords; the launchers' `docker` wrapper relaxes the preference around
   the wsl call.
4. **Container-name parity.** Everything hashes the folder's PHYSICAL path
   (true on-disk casing via `GetFinalPathNameByHandle`, symlinks resolved)
   plus `"\n"`, SHA-256, first 8 hex — `FolderContainers` in Core and all
   three launchers agree byte for byte.

## Spec coverage

Tracked until 2026-10-08 in the **Windows status** section of
[`GUI-IMPROVEMENTS.md`](../GUI-IMPROVEMENTS.md) (264 rows as of 2026-08-18,
entries 1–264 assessed), frozen with the log when it closed to new entries
(#480); since then the open `windows` issues are the list, and the closed
issues by milestone are what shipped. Nothing here duplicates either, because
a second copy is a copy that goes stale — that count itself had been reading
"179 rows" for days after the log passed 250.

**What to do with that assessment** is the open `windows` issues, plus
[`documentation/12-windows-app.md`](../documentation/12-windows-app.md) →
"What is built and what is missing". Much of that page was written by reading
this app's source from the mac, read rather than run — `dotnet` is not
installed there — so treat it as a starting point, and report anything it gets
wrong in a `mac` issue.

## Work done from a cloud (Linux) session — 2026-09-27

The first piece of this port built off the Windows PC: [#144](https://github.com/russellgordon/plantoir/issues/144),
in a Claude Code cloud session (Ubuntu 24.04, no Windows App SDK). What that
kind of session can do, measured on the day and written for the next one:

- `Plantoir.Core`, `Plantoir.Mcp`, `PtyDriver` and `Plantoir.Tests` build and
  run on Linux with the .NET 10 SDK (Microsoft's apt repository no longer
  carries 9.0) plus the .NET 9 runtime from `dotnet-install.sh`. `Plantoir/`
  (WinUI 3) and `Plantoir.UiTests` do not build there at all.
- `dotnet test` on Linux: **1538 tests, 111 red before the change** — every
  red one either a Windows path (`C:\Users\…` expected, `CreateFileW` in
  `FolderContainers`) or a handover the parity plan already lists. The gate
  for a cloud session is therefore **"no NEW red"**, judged by diffing the
  failing-test list before and after, not by the totals line alone.
- The WinUI project's edits (#144: one line in `App.xaml.cs`, one line plus a
  refusal block in `SectionScheduleDialog.cs`) were NOT compiled. The first
  `dotnet build Plantoir/Plantoir.csproj -c Debug -p:Platform=x64` on the PC
  is the check, and "PT - Dev" is stale until then.

## Known rough edges for the next session

- **The native (containerless) toolchain shipped in v1.1.0 — this is no
  longer a branch, and the container path is gone, not merely deprecated.**
  `windows-native-toolchain` merged (`4adcd5b7` onward) and the WSL2/Docker
  fallback was deleted outright in `df317f52` — a copy of the app with no
  bundled runtime now fails fast with "This copy of Plantoir is missing its
  website builder. Reinstall Plantoir, then try again." (`setup.ps1`,
  `preview.ps1`, `deploy.ps1`); there is no fallback path left to take. Run
  `windows-app/Vendor/fetch-runtime.ps1` once before building — it fetches
  Node (22.23.4 since #675; 20 before), Python 3.14.10 embeddable (3.11.9 until #764), patched Quartz with win-x64 node_modules,
  wrangler and the emoji font into `windows-app/Vendor/runtime/` (~600 MB,
  gitignored), which the build robocopy-mirrors beside the app. The
  launchers run natively whenever `PLANTOIR_RUNTIME` (set by `ScriptRunner`)
  or the installed app's own runtime folder exists — that is now the only
  code path. Builds land in `%LOCALAPPDATA%\Plantoir\builds\<folder-id>`
  (OneDrive-safe). Verified by hand, both before and after an adversarial
  pass (`2b968c70`) that found and fixed six real defects (a stop sweep that
  silently did nothing, a preview-port announce race, a course-creation
  failure mode, and stale WSL2/container wording leaking into the trail and
  the UI): native build (57 s cold), serve (HTTP 200), stop (kills the tree,
  frees both ports), Netlify delta deploy — all with no container, and the
  app-driven flow end to end, including the setup wizard's keyboard path
  under ConPTY (auto-answered course creation, no ConPTY stall).
- **The WSL2 auto-install path (`Install-WindowsSubsystem`) described here
  previously is gone, not merely superseded.** It existed to provision WSL2
  + Docker on a fresh PC for the container toolchain; the native runtime
  removed that need entirely, and `Install-WindowsSubsystem` is no longer
  present in the launchers (confirmed by search — no remaining references).
  A fresh PC now needs only the .NET 9 runtime the app is self-contained
  against; there is no VM, no reboot-for-VM-platform-features case, and
  nothing here to verify.
- The toolbar can still truncate at narrow widths. The window minimum **is**
  enforced at 900×600 epx (`MainWindow.ApplyMinimumSize`, `PreferredMinimumWidth` /
  `PreferredMinimumHeight`, which the presenter scales); the opening size is a
  share of the display's work area, clamped, and since #542 (2026-10-16) never
  below that minimum — it used to open at 793 epx at 150%. Below 900 epx (a
  225%+ display, where the minimum is clamped to the work area) the toolbar
  can still truncate.
- The preview accelerators exist — Ctrl+R, Alt+Left, Alt+Right — on View ▸
  Reload Page, Back and Forward since #488 (2026-10-15; they were declared at
  view scope in `Views/SectionDetailView.xaml` until then, and a measurement
  showed that scope added nothing: documentation/12, "Menus, the Section
  menu's functions and #475 on Windows").
  ~~What is missing is a **Preview menu-bar item**~~ — added 2026-08-22
  (`MainWindow.xaml`, handoff item 1). Corrected 2026-09-06: this paragraph
  outlived the work by a fortnight, and anyone planning from it would have
  built it twice.
- ~~Two paths proven underneath but never click-driven in-app: the wizard's
  Create button (the `setup.ps1` + answer-pump path ran to completion via
  PtyDriver), and the new-site dialog a BRAND-NEW section's deploy raises —
  the verified deploy was a repeat publish to an existing site.~~ Closed
  2026-09-07 as handoff item 35. The Create button is now click-driven by
  `NewCourseWizardUiTests`; the new-site dialog is a hand-driven check with a
  written procedure (`documentation/12-windows-app.md`), because reaching it
  needs a real saved Netlify token and creates a real site. It was listed as
  item 35 on 2026-09-06 — before that it was written down here and indexed
  nowhere, so no session planning from the numbered list could see it, which
  is the whole reason the audit added it.
- Smoke-test hooks, all driving the real button code paths
  (`MainWindow.xaml.cs`, `RunAutomationHooks`): `--auto-select CODE N`,
  `--auto-preview CODE N`, `--auto-deploy CODE N`, `--auto-course CODE`,
  `--auto-wizard`, `--auto-createcourse CODE [SECTIONS]`,
  `--auto-addsection CODE`.

## Parity run, bundle 7: clubs, Course Settings, today's class (2026-10-01)

- **#274 — clubs.** `ClassPageNaming` on every class-planning path with no
  default; numbered next page after the latest date, make room keeping gaps,
  no whole-unit path, numbered refusals before the dates are asked for; the 60
  class/meeting sentences in the teacher's copy only (`_meta`), the model's
  copy byte-identical (`ClubNounTests`); the meeting card phrasings and the
  numbered make-room family; a club's shelf; "This is a club" in the wizard;
  Course Settings' locked rows and the disabled Rename…; `course created` says
  a club; the front-page pointer found by the class it names (`writtenAs`).
- **#390** — the panel's words follow the box. **#387** — `SettingsSaveState`,
  `settings save held back`, legacy per-section seeding, "Language and region",
  "Standard colours", the label-word scan. **#269** — the lists are tables
  (+/−, Delete) and Hide/Expandable one table. **#406** — Preview offers today's
  class (42 cases), Not Today, two trail events.
- **#392 / #399 remainders** — published-before pages keep their date in the
  assistant's publish; `linksIntoHiddenPagesWillBeOffered` only when the build
  made the checklist; the two laid-out naming cases run.
- Ledger entries deleted: every one owned by #274, #387, #392 and #406
  (3 config keys, 51 wording keys + 1, 3 trail events, 2 case lists).
  [UiFact]s written and UNPROVEN (desktop locked): `ClubSettingsUiTests`,
  `CourseSettingsSaveUiTests`, `ListTablesUiTests`, `MarksPoolRemovalUiTests`
  (updated).
