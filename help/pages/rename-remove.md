---
id: rename-remove
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/SidebarView.swift
- mac-app/QuartzTeachers/Models/CourseRenamer.swift
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- rename course
- change course code
- course code
- remove course
- delete course
- remove section
- delete section
- archive
- archived
- no longer teach
- get it back
description: Change a course's code with Course ▸ Rename, and remove a course or a section, which moves it to Archived without deleting anything.
---
This page covers two things: changing a course's code, and removing a course or a section you no longer teach. Removing deletes nothing. What you remove moves to Archived, and can be brought back.

## Change a course's code

{{menu:courseRename}} changes the course's code, the short name it has in the sidebar. It does not change the course's name. The name is a field in the course's settings: see [Change a course's settings](page:course-settings).

1. In the sidebar, select the course.
2. Choose {{menu:courseRename}}, or press Return. You can also right-click the course and choose {{control:sidebarRenameMenuItem}}. The course's row becomes a field, with the code selected.

{{picture:rename-remove-1}}
alt: A course's row in the sidebar turned into a field, with the course's code selected for typing.

3. Type the new code and press Return. To leave the code as it was, press Escape.

What changes and what does not:

- The course's name, its backups and the addresses of its websites stay as they are.
- If a section of the course was set to deploy on a schedule, the rename turns that off, and an alert tells you. Schedule it again from the Section menu if you still want it. See [Schedule a deploy for later](page:schedule-deploy).
- If the course is open in Obsidian, an alert says so. Press {{control:renameCourseCloseObsidianAndRename}}: Plantoir closes Obsidian, renames the course, and opens Obsidian again.

## Remove a course

1. In the sidebar, select the course.
2. Choose {{menu:removeCourse}}. You can also press the Delete key, or the minus button under the sidebar.
3. An alert asks whether to remove the course. It says that nothing is deleted, and that the course and all of its sections move to {{control:sidebarArchived}}, at the bottom of the sidebar. If a deploy is scheduled for the course, the alert warns you, and the scheduled deploy is turned off.

{{picture:rename-remove-2}}
alt: The alert that asks whether to remove a course, saying that nothing is deleted, with the Remove and Cancel buttons.

4. Press {{control:removeCourseAlertRemoveButton}}. The course now sits under {{control:sidebarArchived}}.

To bring it back, choose {{menu:restoreFromArchive}}. [Bring back a removed course](page:archive) has the steps.

## Remove a section

1. In the sidebar, select the section.
2. Choose {{menu:removeSection}}.
3. An alert asks whether to remove that section, and says that nothing is deleted. Press {{control:removeCourseAlertRemoveButton}}, and the section moves to {{control:sidebarArchived}}.

If the section is the only one the course has, the alert asks about the whole course instead, and the whole course moves to {{control:sidebarArchived}}.

## If it does not work

- **{{menu:courseRename}} is greyed.** The course is kept for reference, or it is being previewed or deployed. Stop the preview, or wait for the deploy to finish.
- **Text under the field says the code cannot be used.** It says why. Type a different code.
- **An alert titled {{control:renameCourseCouldNotRename}} appears.** It gives the reason. One reason is that the working folder already has something with that code.
- **An alert says a scheduled deploy may still run.** Plantoir could not turn off a deploy that was scheduled under the old code. It may still try to deploy under that code.

{{assistant}}
{{menu:courseRename}} is also greyed while Claude, Codex or GitHub Copilot is open on the course from Plantoir. Finish with the assistant first.
{{/assistant}}
