---
id: publish-class-for-date
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Section/SectionVerbSheet.swift
- mac-app/QuartzTeachers/Models/SectionVerbs.swift
- mac-app/QuartzTeachers/Models/SectionIndexPointer.swift
- contracts/assist-wording.json
- contracts/shared-rules.json
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- publish a class
- publish a day
- publish tomorrow
- publish by date
- one day
- tomorrow's class
- class for a date
- front page
- most recent class
description: Publish Class for a Date publishes the class page dated on one day, together with the pages it links to.
---
Publish Class for a Date publishes one day's class in a section. You choose the day, and Plantoir publishes the class page with that date together with the pages it links to.

## Steps

1. In the sidebar, select the section.
2. Choose {{menu:publishClassForDate}} from the menu bar. A sheet opens and says:
   {{say:assist-wording#wording.menuPickClassDay}}
3. Set the date to the day of the class. The date starts at the section's next class day after today. If the section has no class date after today on file, it starts at tomorrow.

{{picture:publish-class-for-date-1}}
alt: The Publish Class for a Date sheet with its date field set to a class day, and the Continue button.

4. Press {{control:continueButton}}. The sheet shows the plan: the class page, the pages it links to, and what changes for each in the {{control:whatChangesColumn}} column.

{{picture:publish-class-for-date-2}}
alt: The plan for one day's class, listing the class page and the pages it links to, with the Publish button.

5. Read the plan, then press {{control:publishButton}}. Plantoir saves a copy of the course first, and then publishes the pages.
6. Read the answer, which gives the date of the class that was published, and press {{control:ok}}.
7. Deploy the section when you want students to see the class. See [Deploy a section](page:deploy).

The same command is in the menu that opens when you right-click the section in the sidebar.

## What students see after the next deploy

- **The class page and the pages it links to.** They are published for this section only. Another section's copy of the class is not changed.
- **The front page shows the newest class students can see.** If this class is the newest one published, the front page shows it under Most Recent Class. If a class with a later date is already published, the front page stays on that later class. See [Class pages: Unit 1, Day 1](page:class-pages).

Nothing reaches students until the section is deployed. [Publishing and deploying](page:publish-and-deploy) explains why.

## A class published for a day ahead

You can publish a class for a day that is still some way off. Because you named its date yourself, the next deploy does not ask whether that class should go out. [Classes dated after the next class, at Deploy](page:later-classes) describes the question Plantoir asks about other classes dated ahead.

## Take it back

Choose {{menu:undoLastChange}}. The class and the pages published with it are hidden again. This works while publishing the class is still the last change made from the Section menu in this window. [Show or hide pages for a section](page:publish-pages) has the rules for Undo Last Change.

## If it does not work

- **The sheet says no class is dated that day.** Choose another day. Or publish the page by its name with {{menu:publishPages}}.
- **The date offered is not a class day.** The section has no class date after today on file, so the sheet offers tomorrow. See [Give Plantoir your class dates](page:class-dates).
- **A page stays exactly as it is.** Its settings are written in a way Plantoir cannot add to. Open the page in Obsidian and set it there.
- **Students cannot see the class.** The section has not been deployed since you published it.
