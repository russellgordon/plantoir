# #1020 and #1024: the Windows halves of the mac's #1012 and #997 (night 3, lane C)

Plan: `vm-tools/reference/night3-c-plan.md` (private setup repository).

## For PROGRESS

- **#1020 (mirror of #1012): every box that showed only a placeholder has a name of its own**, the mac's words, the placeholder kept as the hint: the assistant's box "Ask about this section"; the console's answer box and a plain question's answer box "Your answer"; the credential field by the label printed above it; Class Dates' dates box "Class dates", sheet link "Google Sheet address" and source "Where these came from"; the sidebar's rename box "Course code" and filter "Filter"; the list editor's add field "New folder name" or "New file name" and its rename field "New name"; both footer boxes "Footer"; both deploy-folder boxes "Folder". `AboutDialogLinksSourceTests` now pins each About link's address too (the 993b review: the old pattern took any address). Tests: `PlaceholderFieldNamesSourceTests` (9), `PlaceholderFieldNamesUiTests.EveryBoxThatShowedOnlyAPlaceholderHasANameOfItsOwn`.
- **#1024 (mirror of #997), what applied:** the sidebar's row text trims with an ellipsis and a course code cut short carries the whole code as its tooltip and help text (`ACourseCodeCutShortShowsTheWholeCode`); Class Dates opens with the keyboard in the dates box, opened from the menu by pointer or keyboard, and only the dialog's own first placement is moved there, so focus sent by Narrator or UI Automation stays where it was sent; Tab moves on to "Where these came from" typing nothing (`TabLeavesTheDatesBoxAndTypesNothing`, `FocusSentByAssistiveTechnologyStaysWhereItWasSent`, `OpenedFromTheKeyboardTheSheetStartsInTheDatesBox`). What did not apply, and why, is below.

## For documentation 12

### Placeholder-only boxes (#1020)

A placeholder is a hint that goes when the teacher types; the mac named each such field in #1012 (documentation 09, "Placeholders are not names"). Windows sets `AutomationProperties.Name` to the mac's words on each box listed above. Boxes built through `FormBuilders.LabeledRow` were already named by their printed label, and Find a Page and Cloudflare Account ID were named before.

MEASURED, VM `Windows 11 B`, 2026-11-20: on the base commit, the sidebar filter (`PlaceholderText="Filter"`, no Name) already read as "Filter" through UI Automation, so WinUI's TextBox hands its placeholder text over as the automation Name when nothing else names it. The fault on Windows is therefore sharpest where the placeholder is an example rather than a name ("e.g. ICS3U", a Google Sheets address, "For example: This site is licensed…", "If you're asked a question, type your answer here…"), which were read out as the box's name: with the names taken out and the ids kept, Course Settings' footer box read as "For example: This site is licensed under <a href="…">CC BY 4.0</a>." Naming every box keeps the two apps saying the same words and does not depend on that fallback.

Not named, on purpose: Schedule Deploy's day picker (its placeholder is "Pick a day"; the mac's picker is one "Deploy at" control where Windows has a day and a time picker, so the words are not the mac's to copy one for one), and the task's progress bar (the mac named its spinner "Running"; Windows draws a bar with a value). Both are listed in the lane's report.

### The sidebar row's text and a cut-short course code (#1024, the mac's D44)

The row was a horizontal StackPanel, which gives its children all the width they ask for, so a long code ran past the 230-epx column: clipped with no ellipsis, and a section's clock or warning badge after it drawn out of sight. The row is now a Grid (icon, text in a star column, the two badges), left aligned so the badges still sit just after a short title, with margins rather than `ColumnSpacing` (spacing stays between columns whose badge is collapsed). The text trims with an ellipsis. A course's row (`SidebarRow.ShowsWholeTitleWhenCutShort`) gives its text the whole code as its tooltip and as its UI Automation help text while it is cut short, and nothing when it fits, as the mac's `CourseCodeLabel` does; whether it is cut short comes from `TextBlock.IsTextTrimmedChanged`, raised by layout, so nothing measures or waits. A recycled container takes its new row's state on `DataContextChanged`. Reference-course rows are left as they were: they already carry the course's folder as their tooltip.

### Class Dates' keys (#1024, the mac's ruling Q-C)

WinUI's TextBox has no accept-tab mode, so Tab already left the dates box. What was missing was where the keyboard starts: the dialog put its first focus on the route picker. `SectionScheduleDialog` now sends the dialog's own first placement of the focus to the dates box while the route is Type or paste, and touches nothing after it: the first focus move whose new element is inside the dialog and whose old element is not (`SendTheFirstFocusToTheBox`, `TrySetNewFocusedElement`, WinUI's documented place to change where focus lands). Every later move stays where it was going, whoever makes it, so a person using a keyboard or a screen reader always moves focus where they asked. Shift-Tab from the box goes to the route picker, as on the mac with Keyboard Navigation on.

MEASURED, VM `Windows 11 B`, 2026-11-20, with every `GettingFocus` logged (scratch probe, not merged):

- **Focus moved by UI Automation is `FocusState.Programmatic`** (input device Mouse or Keyboard, after the last real input): a UI Automation SetFocus on "Where these came from", on the "A file" radio button and on Cancel, and Narrator's own navigation (Narrator running, Insert+Right and Insert+Left, focus following its cursor) all arrived as Programmatic, exactly as the dialog's own placement does. The fix's first version redirected every Programmatic move until a Keyboard or Pointer one, so each of those moves was pulled back to the dates box (the review's M1, confirmed: 3 of 3 SetFocus and 4 of 4 Narrator moves). The state therefore cannot tell the dialog from assistive technology and is not read.
- **Opened from the menu by UI Automation (Invoke):** the placement (old: the menu bar item; new: "Type or paste") came before `Opened` in some opens and after it in others (5 of 9 after), and was raised on the dialog's own `GettingFocus`.
- **Opened from the keyboard (Down to Class Dates…, Enter):** the placement was raised ONLY on the app-wide `FocusManager.GettingFocus`, never on the dialog's own, and came after `Opened` in 3 of 6 opens, so the first version's focus-on-Opened was overtaken and the sheet started on the route picker (the review's L1, confirmed). The fix listens to `FocusManager.GettingFocus` from construction until `Closed` (it is static, so it is removed on `Closed`) and focuses nothing on `Opened`.
- **Rejected:** redirect once while `OldFocusedElement` is null or the box (the review's example): with the box focused on `Opened`, a later placement and a Narrator move both come from the box. Telling them apart by time (a window after `Opened`) is a timed guess.

Tests: `FocusSentByAssistiveTechnologyStaysWhereItWasSent` (no key pressed; SetFocus to the source box, the route picker, Cancel and back), `OpenedFromTheKeyboardTheSheetStartsInTheDatesBox` (three keyboard opens; the Enter types nothing), `TabLeavesTheDatesBoxAndTypesNothing`.

### What did not apply

- **Settings pane heights and the screen cap (D42): not built; Russell's question.** Windows' Settings is a window the person can resize, opened at 760 x 600 effective pixels capped by its own display's work area, and every pane scrolls, so nothing runs off the screen. The mac's pane-fitting needs a window the person does not resize; doing it here means taking the resize away.
- **The Backups total's margin (D45):** the Windows Backups row draws no total; the summary is the row's tooltip.
- **The picker's column widths (D48):** already set widths, Folder 140 and Date 170 (`PageTableLayout.PickFolder`, `PickDate`), Page takes the rest.
- **An empty state with a next step (D12):** the Planning tab is absent with no assistant installed (`PlanningTab.IsShown`, the shared `tabCases`), as on the mac.

### How the tooltip was proven

`ACourseCodeCutShortShowsTheWholeCode` reads the text's help text (the whole code on `WWWWWWWWWWWW`, none on `ICS3U`) and then rests the real pointer on the code with the harness's glide (`FixWithButtonsUiTests.RestThePointerOn`, now internal): FlaUI's `Mouse.MoveTo` places the cursor and WinUI opens no tooltip for that, which this test met too. The tooltip came up holding the whole code (capture `1024-cut-short-code-tooltip-rest1.png` in the private run folder `night3-c-captures`). With the row put back to a horizontal StackPanel the text never trims and the test fails at the help text. A bound on the text's rectangle against its row passed with the StackPanel too, so it was taken out.
