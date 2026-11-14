---
id: add-next-class
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Models/Assist/AssistToolRunner.swift
- mac-app/QuartzTeachers/Models/SubjectMenuRules.swift
- mac-app/QuartzTeachers/Views/Section/SectionDetailVerbs.swift
- mac-app/QuartzTeachers/Views/Section/SectionVerbSheet.swift
- mac-app/QuartzTeachers/Views/SidebarView.swift
- contracts/class-planning.json
- contracts/shared-rules.json
- contracts/assist-wording.json
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- add a class
- add class
- add a lesson
- next class
- new class page
- new lesson
- new day
- new unit
- start a unit
- next unit
- copy a class
- copy
- duplicate
- duplicate a class
- repeat a lesson
- numbered
- dated
- hidden
- unpublished
- undo
description: Add Class makes the page for a section's next class. It can be the next class in the unit under way, the first class of a new unit, or a copy of an earlier class.
---
{{menu:addClass}} makes the page for a section's next class. There are three ways to add it. It can be the next class in the unit under way, the first class of a new unit, or a copy of an earlier class. Each way gives a page dated with the section's next class day and left unpublished until you have written it.

## Steps

1. In the sidebar, select the section.
2. Choose {{menu:addClass}} from the menu bar. A sheet opens and asks how the new class should be added.

{{picture:add-next-class-1}}
alt: The Section menu open, with Add Class marked.

{{picture:add-next-class-3}}
alt: The sheet that asks how the new class should be added, with its three ways and the Add button.

3. Choose a way:
   - {{control:addClassWayNextInThisUnit}} adds one class after the last one in the latest unit.
   - {{control:addClassWayInANewUnit}} starts the unit after the latest one.
   - {{control:addClassWayAsACopy}} makes the new class from one you choose. The steps for a copy are below.
4. Press {{control:addClassAddButton}}. The sheet says Plantoir is saving a copy of the course first, and then that it is working.
5. Read the answer on the sheet. It says the page was added, and normally gives the page's name and its date. Press {{control:ok}}.
6. Press {{control:openInObsidian}} and write the page. It is in the section's All Classes folder. See [Write a class page in Obsidian](page:write-in-obsidian).

{{picture:add-next-class-2}}
alt: Obsidian's file list with the new class page marked in the section's All Classes folder.

7. When the page is written, publish it with {{menu:publishPages}} or {{menu:publishClassForDate}}. Students see it after the section is next deployed.

The same command is in the menu that opens when you right-click the section in the sidebar. It opens the same sheet.

## Add a class as a copy

A copy is for a lesson you want to teach again, or one that makes a good start for the next. The copy becomes the section's next class. The class you copied stays where it is, and no other page is renamed or given a new date.

1. On the sheet, choose {{control:addClassWayAsACopy}}. A list of the section's class pages shows, each with its date. Pages named another way, such as Field Trip, are in the list too.
2. Select the class to copy. Type in {{control:findAPage}} to shorten the list.
3. Press {{control:continueButton}}. The sheet shows what it is about to do.
4. Press {{control:addClassDuplicateButton}}.
5. Read the answer. It names the class that was copied and the new page, gives the new page's date, and says the copy is hidden. Press {{control:ok}}.

The copy holds everything the first page held. Change what differs in Obsidian, then publish the page.

## How the page is named and dated

- **The next class in the unit under way is the next day of the latest unit.** After Unit 2, Day 3 comes Unit 2, Day 4. A section with no numbered class yet starts at Unit 1, Day 1.
- **A new unit starts at its first day.** After any day of Unit 2 comes Unit 3, Day 1.
- **A copy takes the name the next class would have.** It does not keep the name of the class it was copied from.
- **The date is the next class day on file** for the section, in all three ways.
- **A page named another way is passed over.** A page such as Field Trip does not change the count.
- **The first word follows your course.** Where units are called Module or Thread, the sheet and the new page use that word. See [Change what units are called](page:unit-word).
- **A club's pages carry one number.** After Week 9 comes Week 10. A missing number earlier in the list is not filled in. A club has no units, so the way that starts a new unit is greyed, and the sheet speaks of meetings.

Each use of {{menu:addClass}} adds one page. The Section menu has no command that adds several days at once.

## If the section has no class dates yet

Plantoir cannot date the page without knowing the days the section meets. The class dates sheet opens first, and says:

{{say:assist-wording#wording.datesForTheNextPage}}

Give the dates there. When you press {{control:rememberTheseDates}}, the sheet that asks how to add the class opens by itself. [Give Plantoir your class dates](page:class-dates) has the steps.

## Take the new page away again

Select the section and choose {{menu:undoLastChange}}. The new page is deleted, unless you have written in it since. A page you have changed is kept, and the sheet says so. This is the same for all three ways.

This works while adding the page is still the last change made from the Section menu in this window. [Show or hide pages for a section](page:publish-pages) has the rules for Undo Last Change.

The copy of the course that Plantoir saved first is in its list of backups. See [Back up a course and restore it](page:backups).

## If it does not work

- **{{menu:addClass}} is greyed.** The course may be kept for reference. Or the section is busy. It is being deployed, a copy of the course is being saved, or another command from the Section menu is still running in this window.
- **A way on the sheet is greyed.** A line under the ways says why. There are three reasons.
  - The course has no units:
    {{say:assist-wording#wording.menuAddClassGreyedNoUnits}}
  - The section has no class page to copy:
    {{say:assist-wording#wording.menuAddClassGreyedNothingToCopy}}
  - A change to what the course calls a unit did not finish. The line names the ways it holds back. This is its fullest form:
    {{say:assist-wording#wording.menuAddClassGreyedRenameUnfinished}}
    [Change what units are called](page:unit-word) says how to finish the rename. The first way is never greyed.
- **The answer says nothing needed adding.** A page with that name is already there. Plantoir never writes over a page that exists.
- **The answer says nothing was copied, because a page is already where the copy would go.** The same rule applies to a copy. Look in the section's All Classes folder for the page it names.
- **The answer says the class was not copied, because the copy could not be made hidden.** Plantoir cannot read the settings at the top of the class you chose for certain. It will not make a copy that students might see before you have written it. Open that class in Obsidian and look at the settings at its top. See [Page settings](page:page-settings).
- **The answer says a rename stopped part way and nothing was changed.** Finish the rename in the course's settings, then add the class again.
- **The new page is not in the preview.** It is unpublished. Publish it first.
