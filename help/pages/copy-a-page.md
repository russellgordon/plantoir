---
id: copy-a-page
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/CopyPage/CopyPageSheet.swift
- mac-app/QuartzTeachers/Models/CopyPageWording.swift
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- copy a page
- reuse a page
- reuse
- last year's page
- another course
- bring a page over
- linked pages
- hidden
- reference course
description: Copy a Page copies one page, and the pages it links to if you wish, from one course into another course you teach. The copies arrive hidden.
---
Copy a Page copies one page from a course into another course you teach. The pages it links to can come with it. The copies arrive hidden, so no website changes until you publish them and deploy.

## Steps

1. In the sidebar, select the course you are copying from. It can be a course kept for reference or a course you teach.
2. Choose {{menu:courseCopyAPageFromThisCourse}} ({{key:courseCopyAPageFromThisCourse}}). A sheet opens, titled with the name of the course you are copying from.
3. Under {{control:copyAPageSheetPageLabel}}, type part of the page's name in the {{control:copyAPageSheetSearchField}} field and choose the page.
4. Under {{control:copyAPageSheetCopyIntoPopUp}}, choose the course the page goes to. The pop-up lists the other courses you teach.
5. Under {{control:copyAPageSheetFolderPopUp}}, choose where in that course the page goes.
6. To bring linked pages too, turn on {{control:copyAPageSheetAlsoCopyLinkedPages}}. A checklist of those pages opens. Tick the ones you want. The sheet says how many pictures and files come with them.

{{picture:copy-a-page-1}}
alt: The Copy a Page sheet, with the page, the course it goes to, and the checklist of pages it links to.

7. Press {{control:copyAPageSheetCopyButton}}. Plantoir first saves a copy of the course you are copying into, and says so. That copy is listed under {{control:sidebarBackupsGroup}} in the sidebar.
8. Read the result. It says how many pages were copied, and into which course and folder. {{control:showInFinder}} shows them to you.

{{picture:copy-a-page-2}}
alt: The result of Copy a Page, saying how many pages were copied and where, with a Show in Finder button.

9. Press {{control:copyAPageSheetCopyAnotherButton}} to copy another page, or {{control:copyAPageSheetDoneButton}} to close the sheet.

## What the copies are like

The sheet says three things about the copies:

{{say:shared-rules#copyingAPageBetweenCourses.wording.copiesStartHidden}}

{{say:shared-rules#copyingAPageBetweenCourses.wording.nothingIsWrittenOver}}

{{say:shared-rules#copyingAPageBetweenCourses.wording.datesAreKept}}

Two more things to know:

- **Pictures and files come too.** A picture with the same name as one already there, but different contents, comes in under a new name. The result says so.
- **Some links may lead nowhere yet.** The result names any link in the copied pages that does not lead anywhere yet.

## Then publish and deploy

1. Publish the copied pages for each section that should have them. See [Show or hide pages for a section](page:publish-pages).
2. Preview the section, then deploy it. See [Deploy a section](page:deploy).

## Pages that are not copied

The sheet says when a page will be left where it is. These are never copied:

- a class page, because it is one of that course's classes;
- a folder's own page;
- a page at the top of the course, outside every folder;
- a page inside one section's folder.

## If it does not work

- **The sheet says there is no other course to copy into yet.** A page is copied into a course you teach, so you need one besides the course you selected.
- **The sheet says the course is deploying right now.** Wait until the deploy of the course you are copying into has finished, then copy.
- **No page matches what you typed.** The sheet says so. Type a different part of the page's name.
- **You want the course back as it was before the copy.** Restore the backup that was saved first. See [Back up a course and restore it](page:backups).
