---
id: import-for-reference
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Wizard/ImportCoursesForReferenceSheet.swift
- mac-app/QuartzTeachers/Models/ReferenceImportWording.swift
- mac-app/QuartzTeachers/Models/ReferenceCreationWording.swift
- mac-app/QuartzTeachers/Views/ReferenceShelfHeading.swift
keywords:
- import
- bring in
- last year's courses
- last year's folder
- old working folder
- previous year
- reference
- reference course
- backup
- archive
- external drive
description: Import Courses for Reference copies courses from last year's folder, or from a backup or archive, into this working folder and keeps them for reference.
---
Import Courses for Reference copies courses from another place into this working folder and keeps them for reference. The place can be the folder you kept last year's classes in, or a backup or an archive of a course.

A course kept for reference is locked and is never deployed. [Keep a copy of a course for reference](page:keep-for-reference) says what that means.

## Import from a folder, a backup or an archive

1. Choose {{menu:fileImportCoursesForReference}}. A panel opens for you to choose from.
2. Choose the folder you kept last year's classes in, or a backup or an archive of a course. A sheet titled {{control:importForReferenceSheetTitle}} lists the courses found there.
3. Tick each course you want. Each row shows the course's code and name, how many sections and pages it has, and its size.
4. Choose a {{control:importForReferenceSheetSchoolYearPopUp}} for each course you ticked.

{{picture:import-for-reference-1}}
alt: The Import courses for reference sheet, listing the courses found, each with a tick box and a School year pop-up.

5. Press {{control:importForReferenceSheetImportButton}}. Plantoir copies the courses and shows how far it has got.
6. Read the list under {{control:importForReferenceSheetImportedTitle}}, which has one line for each course. Press {{control:importForReferenceSheetDoneButton}}.

The sheet says where the courses now are:

{{say:shared-rules#referenceCourses.importing.wording.whereTheyAre}}

## What the import does

The sheet says three things about the import:

{{say:shared-rules#referenceCourses.importing.wording.explanation}}

{{say:shared-rules#referenceCourses.importing.wording.builtWebsitesAreNotCopied}}

{{say:shared-rules#referenceCourses.wording.pagesAreLocked}}

The place you import from does not have to be inside your home folder, because the courses are copied in.

## From a backup or an archived course in the sidebar

Right-click a backup or an archived course in the sidebar and choose {{control:sidebarRowImportForReferenceMenuItem}}. This brings that course onto the {{control:referenceCourses}} shelf.

## A ready-made course, made for reference

You can also put a ready-made course straight onto the shelf, to read and copy from.

1. Open the menu on the {{control:referenceCourses}} heading in the sidebar and choose {{control:referenceShelfNewReferenceCourseMenuItem}}. The {{control:newCourseOrClub}} sheet opens with {{control:newCourseSheetKeepThisCourseForReference}} turned on.
2. Fill in the sheet, then press {{control:newCourseSheetCreateReferenceCourseButton}}.

[Make a new course](page:new-course) describes the sheet.

## If it does not work

- **You pressed {{control:importForReferenceSheetStopButton}} while courses were being copied.** The courses already imported are kept. The one that was being copied is not.
- **Nothing is ticked.** The sheet asks you to tick the courses you want.
- **An orange sentence says you already have that course kept for reference from that year.** Choose a different school year, or press {{control:referenceCourseReplaceItButton}}. See [Replace a reference course](page:replace-reference-course).
- **You chose the working folder you have open.** The sheet tells you to use {{menu:courseKeepACopyForReference}} instead. A folder inside the open working folder, or one that holds it, is refused too.
- **A backup or archive cannot be opened**, or it holds no course, or more than one. The sheet says which.
- **There is too little room on this Mac**, or a course's settings cannot be read. The sheet says so.
- **The folder is arranged in an older way**, with the shared pages kept beside the class folders. Plantoir recognises it. If it cannot find the shared pages, press {{control:importForReferenceSheetChooseSharedFolderButton}} and point to them.
