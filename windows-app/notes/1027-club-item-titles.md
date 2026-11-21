# #1027: in a club the Meetings menu's items say meeting (Windows half)

## For PROGRESS

- **Club item titles** (#1027, Russell, 2026-11-20 night). `SubjectMenuLayout.TitleHere(item, noun)` has no default; `TitleSayingTheNoun(item, noun)` gives Publish Meeting for a Date…, Add Meeting…, Meeting Dates…, Re-date Meetings…, Make Room for Meetings… in a club (`subjectMenus.layout.itemTitles`). `ApplyMenuEnablement` re-titles those items live with the menu's title; the section row's menu titles Publish… for a Date and Add… by the row's course; `SectionVerbDialog.MenuPath` gives "Meetings ▸ Add Meeting…" on the trail. `AddClassWords.NeedsClassDatesFirst` names "Meetings ▸ Meeting Dates…". `NothingToUndoFromTheMenu(noun)`: the window sends the section's course in the call's `_meta` (`AssistWorkspace.CourseMetaKey`, `IHearsTheMenu.CourseOfTheNextCalls`), `plantoir-mcp`'s filter sets `MenuCourseOfTheCall` for one call. Tests: `ClubNounTests` (four new facts, walking the contract), `ContractTests` (`nothingToUndoFromTheMeetingsMenu`), UI `MenuBarUiTests.TheClassesMenuIsTitledMeetingsWhileAClubIsSelected` reads every Meetings item and Section's Publish Meeting for a Date… from `TitleHere`.

## For documentation 12

- The menus' item titles in a club come from one function per platform, checked against `subjectMenus.layout.itemTitles`; nothing else retypes them. A sentence with no course of its own (Undo Last Change's nothing-to-undo) learns the selected section's course from the call's `_meta` key `plantoirCourse`, never a tool argument, so no schema changes. Still saying class in a club, outside #1027: the Class Dates dialog's body (`SectionScheduleDialog`'s purpose line). Roll Over to a New Year… (still a named gap here) needs no club title.
