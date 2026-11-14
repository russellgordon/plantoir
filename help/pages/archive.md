---
id: archive
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/SidebarView.swift
- mac-app/QuartzTeachers/Models/CourseArchiver.swift
- mac-app/QuartzTeachers/Models/SubjectMenuRules.swift
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- archive
- archived
- removed course
- deleted course
- removed section
- bring back
- restore
- restore from archive
- undo remove
- delete archive
description: A removed course or section is moved to Archived in the sidebar, not deleted. You can put it back, keep it for reference, or delete it for good.
---
Removing a course or a section does not delete it. Plantoir moves it to {{control:sidebarArchived}} in the sidebar, and you can put it back.

## Put it back

1. In the sidebar, find the {{control:sidebarArchived}} group and select the row of the course or section. The group is shown once something has been archived.

{{picture:archive-1}}
alt: The sidebar with the Archived group, and a removed course listed in it.

2. Choose {{menu:restoreFromArchive}}, or right-click the row and choose {{control:sidebarRowRestoreMenuItem}}. A question opens.
3. Read the question. For a course, it says the course will be put back into {{control:sidebarCoursesAndClubsGroup}} and will no longer be listed as archived. For a section, it says the section will be put back into its course.
4. Press {{control:sidebarRestoreQuestionRestoreButton}}.

## Keep an archived course for reference instead

Right-click the archived course and choose {{control:sidebarRowImportForReferenceMenuItem}}. The course goes onto the {{control:referenceCourses}} shelf, where you can read it and copy pages from it. See [Bring in last year's courses](page:import-for-reference).

## Delete it for good

1. Select the row under {{control:sidebarArchived}}.
2. Choose {{menu:courseDeleteArchive}}. A question says that this deletes the archive for good and that nothing is kept.
3. Press {{control:sidebarDeleteQuestionDeleteButton}}, or {{control:cancel}} to keep it.

## What else is under Archived

Restoring a backup also puts something here. The version of the course you had before the restore moves to {{control:sidebarArchived}}. See [Back up a course and restore it](page:backups).

[Rename or remove a course](page:rename-remove) has the steps for removing.

## If it does not work

- **{{menu:restoreFromArchive}} is greyed.** Select a row under {{control:sidebarArchived}} first.
- **There is no {{control:sidebarArchived}} group.** Nothing has been archived in this working folder.
