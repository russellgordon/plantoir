---
id: start-of-year
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Section/StartOfYearSheet.swift
- mac-app/QuartzTeachers/Models/StartOfYear/StartOfYearWording.swift
- mac-app/QuartzTeachers/Models/SubjectMenuRules.swift
- contracts/shared-rules.json
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- start of the year
- start of year
- new school year
- new year
- new semester
- rollover
- hide last year
- last year's classes
- draft
- put into draft
- reuse a course
description: Get Ready for the Start of the Year puts every class after the first into draft, with the pages students do not need yet.
---
Get Ready for the Start of the Year takes a section back to its first class. Every later class goes into draft, and so do the pages students will not need until later. A page in draft is hidden from students. Plantoir sets its publish line to `false`, as [Which classes see a page](page:page-settings) describes.

Use it on a course you have taught before, when a new group of students should start with the first class only.

## What goes into draft, and what stays

Going into draft:

- every numbered class after the first;
- pages that are first used by a later class;
- pages that nothing students can still see links to.

Staying as they are:

- the first numbered class, and the pages it links to;
- Key Links, and every page it lists;
- the rest, in the sheet's words:

{{say:shared-rules#startOfYear.wording.staysEverythingElse}}

It only hides pages. It publishes nothing, and it changes no dates. To move the classes onto this year's dates, see [Move classes when the schedule changes](page:redate).

## Steps

1. In the sidebar, select the section.
2. Choose {{menu:getReadyForStartOfYear}} from the menu bar. A sheet opens.
3. Read the lists. The first holds the classes going into draft. The second holds the other pages going into draft. The {{control:whyColumn}} column gives the reason for each page. A fold-down list shows the pages that stay as they are.

{{picture:start-of-year-1}}
alt: The sheet for getting a section ready, with the pages going into draft, the Why column, and the Put These into Draft button.

4. Read any warning on the sheet. It warns you when classes dated before today are going into draft, because students lose them at the next deploy. It warns you when the section is set to deploy on its own. It also warns you when the first class is in draft itself. A fold-down list names links that will lead to pages students cannot see yet.
5. Press {{control:putTheseIntoDraft}}. Plantoir makes a new backup of the course first. If it cannot, nothing is changed. To change nothing yourself, press {{control:cancel}}.
6. Read the answer, then press {{control:done}}.
7. Preview the section and look it over. Then deploy it. Students see no change until the section is deployed.

## Publishing after this

From now on, each class you publish needs the pages it uses published with it. {{menu:publishPages}} and {{menu:publishClassForDate}} do that for you. Publishing a class by changing its page in Obsidian does not, and leaves it with links students cannot follow.

## Undo it

1. Choose {{menu:undoGettingReady}}. A sheet lists the pages that would go back to how they were. The finished sheet from the steps above also has an {{control:startOfYearUndo}} button.
2. Press {{control:putThemBack}}. A page that was changed after you got the section ready stays as it is, and the sheet names it.

This undo is separate from {{menu:undoLastChange}}. Plantoir holds one for each section, and it ends at the first of these:

- the section is next deployed, a scheduled deploy included;
- a page of the section is next published or put into draft;
- you quit Plantoir.

The sheet says of the last one:

{{say:shared-rules#startOfYear.wording.undoEndsWhenYouQuit}}

After that, the backup made before the change is the way back. See [Back up a course and restore it](page:backups).

## If it does not work

- **The sheet says the section has no numbered class yet.** There is no first class to keep, and nothing is changed.
- **The sheet says there is nothing to do.** Every later class is already in draft.
- **The sheet says the course is being deployed.** Nothing is changed. Try again when the deploy has finished.
- **The list changed while you were reading it.** Nothing is changed, and the sheet shows the list as it now stands. Read it again.
- **{{menu:undoGettingReady}} is greyed.** No undo is held for this section. The backup is the way back.
- **You are looking for Set School Year.** That command belongs to courses kept for reference. See [Set the school year of a reference course](page:school-year).
