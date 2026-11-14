---
id: backups
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/AllBackupsView.swift
- mac-app/QuartzTeachers/Views/SidebarView.swift
- mac-app/QuartzTeachers/Models/CourseArchiver.swift
- contracts/course-management.json
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- backup
- backups
- back up
- back up now
- restore
- restore from backup
- undo everything
- go back
- delete backup
- all backups
- disk space
- storage
description: A backup is a copy of a whole course saved at one moment. You can make one, see the ones Plantoir made, restore one, and delete the ones you no longer need.
---
A backup is a copy of a whole course, saved at one moment. You can make one whenever you like, and Plantoir makes some by itself. Restoring a backup puts the course back as it was at that moment.

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

## Delete a backup

1. Select the backup's row. In {{control:sidebarAllBackupsRow}} you can select several: hold Command or Shift as you click.
2. Choose {{menu:courseDeleteBackup}}, right-click the row and choose {{control:sidebarRowDeleteBackupMenuItem}}, or press the Delete key. In {{control:sidebarAllBackupsRow}}, the {{control:allBackupsDeleteBackupButton}} button does the same.
3. Read the question. It gives the backup's size and says the course itself is not touched. Press {{control:sidebarDeleteQuestionDeleteButton}}.

A deleted backup is gone for good. This is unlike removing a course, which only moves it to {{control:sidebarArchived}}.

## If it does not work

- **{{menu:courseBackUpNow}} is greyed.** A copy of that course is already being saved. Wait until it has finished.
- **{{menu:courseRestoreFromBackup}} or {{menu:courseDeleteBackup}} is greyed.** Select a backup's row in the sidebar first.
- **A backup could not be made.** An alert says so.
