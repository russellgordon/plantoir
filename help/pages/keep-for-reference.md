---
id: keep-for-reference
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Wizard/KeepACopyForReferenceSheet.swift
- mac-app/QuartzTeachers/Models/ReferenceWording.swift
- mac-app/QuartzTeachers/Models/ReferenceCourseRule.swift
- mac-app/QuartzTeachers/Views/SidebarView.swift
keywords:
- last year's course
- old course
- reference
- reference course
- keep a copy
- read-only copy
- locked
- previous year
- school year
- next year
description: Keep a Copy for Reference records a course as it is today, as a locked copy you can read and copy pages from.
---
A copy kept for reference is a record of a course as it is today. You can read it later and copy pages from it. The course you teach stays as it is, and you carry on teaching it.

## What a reference course is

- **Its pages are locked**, so they stay as they were. In Obsidian you can read them. If you type in one, Obsidian says it could not save, and the page stays as it was.
- **It is never deployed.** Students never see it.
- **You can preview it** to read its pages, and you can copy a page from it into a course you teach.
- **It sits apart in the sidebar**, on a shelf named {{control:referenceCourses}}, filed by school year.

## Keep a copy

1. In the sidebar, select the course you teach.
2. Choose {{menu:courseKeepACopyForReference}}. A sheet opens, titled with the course's name. It says the copy records the course as it is today, and that nothing in the course you teach changes.
3. Choose the school year the course was taught in from the {{control:keepACopySheetSchoolYearPopUp}} pop-up. Choose {{control:referenceShelfSchoolYearOther}} when no year fits.
4. Check the name in the {{control:keepACopySheetFolderNameField}} field. It is the name of the copy's folder, and Plantoir fills it in for you.

{{picture:keep-for-reference-1}}
alt: The Keep a Copy for Reference sheet, with the School year pop-up and the Keep a Copy button marked.

5. Press {{control:keepACopySheetKeepACopyButton}}. The copy appears in the sidebar under {{control:referenceCourses}}, in the group for its school year.

{{picture:keep-for-reference-2}}
alt: The sidebar with the Reference Courses shelf, and the new copy in the group for its school year.

If the course has Obsidian add-ons, the copy is made without them, and the sheet says so.

## Afterwards

- To read the copy, select it and preview it, or open it in Obsidian.
- To reuse one of its pages, see [Copy a page from another course](page:copy-a-page).
- To change the year it is filed under, see [Set the school year of a reference course](page:school-year).
- To arrange the shelf, see [Organise the Reference Courses shelf](page:reference-groups).

## If it does not work

- **{{menu:courseKeepACopyForReference}} is greyed.** The course is busy, for example while it is being deployed. Wait until that has finished.
- **An orange sentence says you already have this course kept for reference from that year.** Two copies of one course cannot share a school year. Choose a different school year, or press {{control:referenceCourseReplaceItButton}} to put the new copy in place of the old one. See [Replace a reference course](page:replace-reference-course).
