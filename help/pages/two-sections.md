---
id: two-sections
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Section/SectionVerbSheet.swift
- mac-app/QuartzTeachers/Models/SectionIndexPointer.swift
- mac-app/QuartzTeachers/Models/Assist/AssistPublishPlan.swift
- contracts/assist-wording.json
- contracts/class-planning.json
keywords:
- two sections
- two classes
- same course two blocks
- one class ahead
- one class behind
- different days
- hide a class
- hide pages
- most recent class
- front page
- undo
description: Two sections of one course can be on different classes. Hiding a class in one section changes that section's website and leaves the other alone.
---
Two sections of one course rarely stay on the same class. This page uses the example course to show that each section's website follows its own classes, while the shared pages stay the same in both.

## Where the example starts

In the example, Section 2 meets one school day after Section 1. Unit 5, Day 17 is dated 18 January 2027 in Section 1 and 19 January 2027 in Section 2.

Both front pages show Unit 5, Day 17 under Most Recent Class. It is the newest class that is published in either section.

## Hide a class in Section 2 only

1. Select Section 2 in the sidebar and choose {{menu:hidePages}} from the menu bar. A sheet opens with a list of the pages that are published in Section 2, classes first. It says:
   {{say:assist-wording#wording.menuPickPagesToHide}}
2. Tick Unit 5, Day 17. If you cannot see it, type part of its name in the {{control:findAPage}} field.
3. Press {{control:continueButton}}. The sheet now lists every page that would change, and what would change for each.

{{picture:two-sections-2}}
alt: The Hide Pages sheet for Section 2, listing the pages that would change, with the Hide button.

4. Press {{control:hideButton}}. Plantoir first saves a copy of the course to its list of backups, and then hides the page. The sheet says what was done.
5. Press {{control:ok}}.

## See what changed, and what did not

1. Preview Section 2. Its front page now shows Unit 5, Day 16 under Most Recent Class. That is the newest class Section 2's students can still see.
2. Preview Section 1. Its front page still shows Unit 5, Day 17. Hiding the page in Section 2 changed nothing in Section 1.
3. On both websites, open a page from Concepts, Exercises or Tasks. The shared pages are the same in both.

{{picture:two-sections-1}}
alt: The websites of Section 1 and Section 2 side by side, each front page showing a different class under Most Recent Class.

Nothing has been sent to students by these steps. Hiding a page changes your course folder and what Preview shows. A section's students see the change only after that section is next deployed. [Publishing and deploying](page:publish-and-deploy) explains why.

## Put it back

1. Select Section 2 and choose {{menu:undoLastChange}}. Unit 5, Day 17 is published in Section 2 again, and Section 2's front page shows it again.

## If it does not work

- **{{menu:undoLastChange}} is greyed.** It is live only when the last change made from the Section menu in this window was made in the section that is selected. Select Section 2 and look again. [Show or hide pages for a section](page:publish-pages) lists the other times it is greyed.
- **A page was not put back.** Undo leaves alone a page that has been edited since the change, and says so.
- **The section had already been deployed.** Undo does not change a website that students can already see. Deploy the section again when you want that website to match.
