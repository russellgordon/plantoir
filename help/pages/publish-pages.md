---
id: publish-pages
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Section/SectionVerbSheet.swift
- mac-app/QuartzTeachers/Models/SectionVerbs.swift
- mac-app/QuartzTeachers/Views/Section/SectionDetailVerbs.swift
- contracts/assist-wording.json
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- publish
- publish pages
- unpublish
- hide
- hide pages
- show
- make visible
- release
- students cannot see
- one class and not the other
- undo
- take back
description: Publish Pages and Hide Pages choose which pages a section's students may see. Each shows a plan first, and Undo Last Change takes the change back.
---
To publish a page is to mark it as one a section's students may see. To hide it is the opposite. This page shows how to do both from the Section menu, for one section at a time.

Publishing and hiding change your course, not the website students read. Students see the change after the section is next deployed. [Publishing and deploying](page:publish-and-deploy) explains the two words.

## Publish pages

1. In the sidebar, select the section.
2. Choose {{menu:publishPages}} from the menu bar. A sheet lists the pages that are hidden in this section, and says:
   {{say:assist-wording#wording.menuPickPagesToPublish}}
3. Tick the pages to publish, in the {{control:pageColumn}} column. Classes come first, by date. The other pages follow by folder and title, and the {{control:folderColumn}} and {{control:dateColumn}} columns say where and when each belongs. To find a page, type part of its name in the {{control:findAPage}} field.

{{picture:publish-pages-1}}
alt: The Publish Pages sheet with its list of hidden pages, two of them ticked, and the Continue button.

4. Press {{control:continueButton}}. The sheet now shows the plan: a count of the pages that would change, and a table of them. The {{control:whatChangesColumn}} column says what happens to each page. Pages that are already as they should be are folded away behind a checkbox.

{{picture:publish-pages-2}}
alt: The plan in the Publish Pages sheet, listing each page that would change and what changes, with the Publish button.

5. Read the plan, then press {{control:publishButton}}. Plantoir saves a copy of the course first, and then publishes the pages. Until it starts work, {{control:cancel}} closes the sheet and nothing is changed.
6. Read the answer and press {{control:ok}}.
7. Deploy the section when you want students to see the pages. See [Deploy a section](page:deploy).

## Hide pages

Choose {{menu:hidePages}} and follow the same steps. The list holds the pages that are published in this section, and the last button is {{control:hideButton}}. The sheet says:

{{say:assist-wording#wording.menuPickPagesToHide}}

Every page you tick is hidden, a page in the section's Key Links included.

Pages that only the ticked pages link to are hidden with them, and the plan lists each one. Five kinds of page are never hidden along with another page. The plan says why each of them stays:

- a folder's own page;
- a page in the section's Key Links;
- a curriculum page;
- another class page;
- a page that a page staying visible still links to.

## One section, not the other

Each command works on the section that is selected. To let one section see a page and keep it from another, publish it in the first and leave it hidden in the second. [Two sections on different days](page:two-sections) works through an example.

## Take the last change back

Choose {{menu:undoLastChange}}. A sheet titled {{control:undoLastChangeTitle}} says what was put back.

{{picture:publish-pages-3}}
alt: The Section menu open, with Undo Last Change marked.

- It takes back the last change made from the Section menu in this window. It does not reach a change made in another window.
- It is live only while the section that change was made in is selected. Select that section first.
- A page you have edited since the change is left alone, and the sheet says so.
- It does not change a website that is already deployed. The sheet says:
  {{say:assist-wording#wording.undoDoesNotReachTheLiveSite}}

{{assistant}}
Undo Last Change does not take back a change the assistant made. The assistant's window keeps its own list of changes.
{{/assistant}}

Anything older is in Plantoir's list of backups, because a copy is saved before each change. See [Back up a course and restore it](page:backups).

## Related commands

- {{menu:publishClassForDate}} publishes one day's class by its date. See [Publish the class for a date](page:publish-class-for-date).
- {{menu:publishPagesThatLinksLeadTo}} lists hidden pages that published pages link to. See [Publish the pages a class page links to](page:links-checklist).

## If it does not work

- **The sheet says every page is already published**, or that no page is published. There is nothing to tick.
- **{{control:continueButton}} is greyed.** No page is ticked yet. Space ticks the selected row.
- **A page stays exactly as it is.** Its settings are written in a way Plantoir cannot add to. Open the page in Obsidian and set it there: see [Which classes see a page](page:page-settings).
- **{{menu:undoLastChange}} is greyed.** It is live only when the last change made from the Section menu in this window was made in the section that is selected. It is also greyed while the section is being deployed, and while a copy of the course is being saved. The same holds while another command from the Section menu is still running in this window. For a course kept for reference it is always greyed.
- **Students still cannot see the page.** The section has not been deployed since you published it.
