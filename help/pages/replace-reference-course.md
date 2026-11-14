---
id: replace-reference-course
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Models/ReferenceReplaceWording.swift
- mac-app/QuartzTeachers/Models/ReferenceCourseRule.swift
- mac-app/QuartzTeachers/Views/Wizard/KeepACopyForReferenceSheet.swift
- mac-app/QuartzTeachers/Views/Wizard/ImportCoursesForReferenceSheet.swift
keywords:
- replace
- replace it
- swap
- newer copy
- fresher copy
- already have
- reference course
- backup
- undo
description: Replace It puts a newer copy of a course in place of the one on the Reference Courses shelf. The old one is backed up first.
---
Replace It puts a newer copy of a course in place of the one already on the {{control:referenceCourses}} shelf. Plantoir backs the old one up first, so you can get it back.

## Where Replace It appears

Two reference courses with the same code cannot share a school year or a group. When a new copy would clash with one already on the shelf, an orange sentence says you already have that course there. The {{control:referenceCourseReplaceItButton}} button is beside it. This happens in three places:

- the sheet that {{menu:courseKeepACopyForReference}} opens;
- each row of the sheet that {{menu:fileImportCoursesForReference}} opens;
- under the course code in {{control:newCourseOrClub}}, when the course is being made for reference.

You can choose a different school year or group instead, and keep both.

## Steps

1. Press {{control:referenceCourseReplaceItButton}}. A question opens. Its title names the course and the group it is in. It says:
   {{say:shared-rules#referenceCourses.replacing.wording.message}}
2. Read the facts under it:
   - {{control:replaceReferenceCourseQuestionBeingReplacedRow}}: how many sections and pages the course on the shelf has, and its size.
   - {{control:replaceReferenceCourseQuestionKeptOnRow}}: the day it was kept, when Plantoir knows it.
   - {{control:replaceReferenceCourseQuestionBackedUpFirstAsRow}}: the name the backup will have under {{control:sidebarBackupsGroup}} in the sidebar.
   - {{control:replaceReferenceCourseQuestionToUndoRow}}: restore that backup.

{{picture:replace-reference-course-1}}
alt: The question asked before a reference course is replaced, with its facts and the Replace button.

3. Press {{control:replaceReferenceCourseQuestionReplaceButton}}, or {{control:cancel}} to leave the shelf as it is.

Plantoir backs up the old reference course and checks the backup. Only then does it replace the course. Afterwards a note names the backup.

## Get the old one back

Restore the backup the note names. It is listed under {{control:sidebarBackupsGroup}} in the sidebar. See [Back up a course and restore it](page:backups).

## If it does not work

- **The backup could not be made, or it is incomplete.** Nothing is replaced, and Plantoir says so.
- **The course on the shelf is busy.** Wait until Plantoir has finished working on it, then try again.
- **The course on the shelf is open in Obsidian.** Plantoir says so, and nothing is replaced.
- **The course is no longer on the shelf.** Plantoir says so, and there is nothing to replace.
