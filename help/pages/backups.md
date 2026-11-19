---
id: backups
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/AllBackupsView.swift
- mac-app/QuartzTeachers/Views/SidebarView.swift
- mac-app/QuartzTeachers/Models/CourseArchiver.swift
- mac-app/QuartzTeachers/Models/OneSectionRestore.swift
- contracts/course-management.json
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- backup
- backups
- back up
- back up now
- restore
- restore from backup
- restore one section
- restore a section
- one section
- undo everything
- go back
- delete backup
- all backups
- disk space
- storage
description: A backup is a copy of a whole course saved at one moment. You can make one, see the ones Plantoir made, restore one, and delete the ones you no longer need.
---
A backup is a copy of a whole course, saved at one moment. You can make one whenever you like, and Plantoir makes some by itself. Restoring a backup puts the course back as it was at that moment. Some backups can put back one section alone.

## Back up a course

1. In the sidebar, select the course, or one of its sections.
2. Choose {{menu:courseBackUpNow}}, or right-click the course and choose {{control:sidebarCourseBackUpNowMenuItem}}.

The backup is listed under {{control:sidebarBackupsGroup}} in the sidebar, and that group opens. A backup holds the whole course, with its Media folder. You can back up a course while its preview is running.

## The backups Plantoir makes by itself

Plantoir saves a copy of a course by itself before certain changes:

- before every change made from the Section menu, such as publishing pages or re-dating classes;
- before it gets a section ready for the start of the year;
- before it renames what the course calls a unit;
- before a page is copied into the course with Copy a Page;
- before a reference course is replaced.

{{assistant}}
Plantoir also saves a copy before an assistant changes a course.
{{/assistant}}

## See your backups

The {{control:sidebarBackupsGroup}} group appears in the sidebar once there is a backup. Its first row is {{control:sidebarAllBackupsRow}}, and each backup has a row of its own below. Hold the pointer over a backup's row to read when it was made and why.

Select {{control:sidebarAllBackupsRow}} to see every backup in a table:

- {{control:allBackupsColumnCourse}}: the course the backup is of.
- {{control:allBackupsColumnMade}}: when it was made.
- {{control:allBackupsColumnMadeBy}}: {{control:allBackupsMadeByYou}}, or the Section menu with the number of the section.
- {{control:allBackupsColumnSize}}: how much room it takes.

{{picture:backups-1}}
alt: All Backups, a table of every backup with the course, when it was made, who made it and its size.

Above the table, Plantoir says how much room the backups take, with a line for each course. A working folder may be kept in sync with a service such as iCloud Drive. Plantoir then notes that the backups take that much of the service's storage too.

{{assistant}}
A backup made before an assistant changed a course reads as made by the assistant, with the number of the section.
{{/assistant}}

## What Plantoir keeps

- Plantoir never deletes a backup you made.
- Of the backups the Section menu made, Plantoir keeps the five most recent for each course.

{{assistant}}
Of the backups made for an assistant, Plantoir also keeps the five most recent for each course, counted apart. It never deletes one that an open conversation with an assistant could still restore from.
{{/assistant}}

## Restore a backup

1. Under {{control:sidebarBackupsGroup}} in the sidebar, select the backup's row.
2. Choose {{menu:courseRestoreFromBackup}}, or right-click the row and choose {{control:sidebarRowRestoreMenuItem}}. A question opens.
3. Read the question. It gives the date and time the backup was made, and says the course goes back to how it was then. Anything added since is not in the backup.

{{picture:backups-2}}
alt: The question asked before a backup is restored, with the date and time of the backup and a Restore button.

4. Press {{control:sidebarRestoreQuestionRestoreButton}}.

Nothing is lost. The version you had moves to {{control:sidebarArchived}} in the sidebar, and the backup is kept. [Bring back a removed course](page:archive) says what you can do with what is listed there.

## Restore one section

A backup that Plantoir made before a change to one section can put back that section alone. This matters when you have worked on your other sections since. Restoring the whole course would take that work back too.

For such a backup the question has two buttons in place of one:

- **{{control:sidebarRestoreQuestionRestoreSectionButton}}**, where {N} is the number of the section. It puts back that section's pages, its settings on the pages every section shares, its class dates and its record of what was published. It leaves your other sections alone.
- **{{control:sidebarRestoreQuestionRestoreWholeCourseButton}}** puts every section back, as the steps above do.

The button for one section is the default. Pressing Return restores that one section, not the whole course.

Either way, the course as it is now moves to {{control:sidebarArchived}} first, and the backup is kept.

After one section is restored, an alert says the section is back and gives the backup's date and time. It may add one of these:

- A shared page made since the backup is now hidden from that section. The backup has no such page, so that section's students could not see it then.
- A shared page kept the setting it has now, because Plantoir could not change the settings at the top of it.
- A shared page could not be saved, so it was left as it is. Its setting for that section may not be what the backup had.
- The section still goes to the website address it has now. A restore never changes where students read a section.

The website students read does not change until the section is next deployed.

The question offers one section only when all of these are true:

- Plantoir made the backup before a change to one section. A backup you made with {{menu:courseBackUpNow}} is of the whole course, and is restored whole.
- The backup holds that section's folder.
- The course still has that section.
- The course is not kept for reference.
- No rename is left unfinished in the course. This is a rename of what the course calls a unit, or of a folder, that stopped part way. Some pages then carry the new names and some the old, and the section can only come back with the whole course.
- The course names its class pages and its folders as it did when the backup was made. The naming differs after a finished change to what units are called, or after a folder was renamed or removed. The section can then only come back with the whole course.

{{assistant}}
A backup made before an assistant changed one section offers that section in the same way.
{{/assistant}}

## Delete a backup

1. Select the backup's row. In {{control:sidebarAllBackupsRow}} you can select several: hold Command or Shift as you click.
2. Choose {{menu:courseDeleteBackup}}, right-click the row and choose {{control:sidebarRowDeleteBackupMenuItem}}, or press the Delete key. In {{control:sidebarAllBackupsRow}}, the {{control:allBackupsDeleteBackupButton}} button does the same.
3. Read the question. It gives the backup's size and says the course itself is not touched. Press {{control:sidebarDeleteQuestionDeleteButton}}.

A deleted backup is gone for good. This is unlike removing a course, which only moves it to {{control:sidebarArchived}}.

## If it does not work

- **{{menu:courseBackUpNow}} is greyed.** A copy of that course is already being saved. Wait until it has finished.
- **{{menu:courseRestoreFromBackup}} or {{menu:courseDeleteBackup}} is greyed.** Select a backup's row in the sidebar first.
- **The question has no button for one section.** The backup is of the whole course, or the course has changed in one of the ways listed under Restore one section. Restore the whole course, or leave things as they are.
- **You pressed the button for one section and an alert says it cannot be put back on its own.** The course changed after the question opened. Nothing was changed and nothing was moved to {{control:sidebarArchived}}. The whole course can still be restored.
- **An alert says the section is being changed right now.** Restore the section once that has finished.
- **An alert says the section was left as it was.** The restore could not finish, and the alert gives the reason. Nothing in the section changed.
- **An alert says the restore stopped part way.** The section may hold some files from the backup and some as they were. Nothing was deleted. The alert names the folder that holds the files set aside, and the course as it was is in {{control:sidebarArchived}}.
- **A backup could not be made.** An alert says so.
