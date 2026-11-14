---
id: add-next-class
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Models/Assist/AssistToolRunner.swift
- mac-app/QuartzTeachers/Views/Section/SectionDetailVerbs.swift
- mac-app/QuartzTeachers/Views/Section/SectionVerbSheet.swift
- contracts/class-planning.json
- contracts/assist-wording.json
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- add a class
- add a lesson
- next class
- new class page
- new lesson
- new day
- numbered
- dated
- unpublished
- undo
description: Add Next Class makes the next numbered class page in a section, dated from the section's class dates and not yet published.
---
Add Next Class makes the page for a section's next class. The page is named with the next number, dated with the next class day, and left unpublished until you have written it.

## Steps

1. In the sidebar, select the section.
2. Choose {{menu:addNextClass}} from the menu bar. There is nothing to fill in. A sheet titled {{control:addNextClassTitle}} opens. It says Plantoir is saving a copy of the course first, and then that it is working.

{{picture:add-next-class-1}}
alt: The Section menu open, with Add Next Class marked.

3. Read the answer on the sheet. It says the page was added, and normally gives the page's name and its date. Press {{control:ok}}.
4. Press {{control:openInObsidian}} and write the page. It is in the section's All Classes folder. See [Write a class page in Obsidian](page:write-in-obsidian).

{{picture:add-next-class-2}}
alt: Obsidian's file list with the new class page marked in the section's All Classes folder.

5. When the page is written, publish it with {{menu:publishPages}} or {{menu:publishClassForDate}}. Students see it after the section is next deployed.

The same command is in the menu that opens when you right-click the section in the sidebar.

## How the page is named and dated

- **Its name is the next day of the latest unit.** After Unit 2, Day 3 comes Unit 2, Day 4. A section with no numbered class yet starts at Unit 1, Day 1.
- **Its date is the next class day on file** for the section.
- **A page named another way is passed over.** A page such as Field Trip does not change the count.
- **The first word follows your course.** Where units are called Module or Thread, the new page is named that way. See [Change what units are called](page:unit-word).
- **A club's pages carry one number.** After Week 9 comes Week 10. A missing number earlier in the list is not filled in.

Add Next Class adds one class, after the last one in the latest unit. The Section menu has no command that starts a new unit or adds several days at once.

## If the section has no class dates yet

Plantoir cannot date the page without knowing the days the section meets. The class dates sheet opens first, and says:

{{say:assist-wording#wording.datesForTheNextPage}}

Give the dates there. When you press {{control:rememberTheseDates}}, Add Next Class carries on by itself. [Give Plantoir your class dates](page:class-dates) has the steps.

## Take the new page away again

Select the section and choose {{menu:undoLastChange}}. The new page is deleted, unless you have written in it since. A page you have changed is kept, and the sheet says so.

This works while adding the page is still the last change made from the Section menu in this window. [Show or hide pages for a section](page:publish-pages) has the rules for Undo Last Change.

The copy of the course that Plantoir saved first is in its list of backups. See [Back up a course and restore it](page:backups).

## If it does not work

- **{{menu:addNextClass}} is greyed.** The course may be kept for reference. Or the section is busy. It is being deployed, a copy of the course is being saved, or another command from the Section menu is still running in this window.
- **The answer says nothing needed adding.** A page with that name is already there. Plantoir never writes over a page that exists.
- **The new page is not in the preview.** It is unpublished. Publish it first.
