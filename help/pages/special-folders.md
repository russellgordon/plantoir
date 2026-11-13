---
id: special-folders
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/CourseSettings/SpecialFoldersHelpView.swift
- mac-app/QuartzTeachers/Models/SpecialNames.swift
- mac-app/QuartzTeachers/Models/GradedFolderWording.swift
- contracts/shared-rules.json
keywords:
- special folders
- folders Plantoir uses
- All Classes
- Media
- Media folder
- Key Links
- curriculum folder
- graded folder
- marks
- front page
- rename a folder
- delete a folder
description: The few folders and pages in a course that Plantoir relies on, what each is for, and what happens if one is renamed or deleted.
---
Most of a course is yours to arrange as you like. A few folders and pages have a job, and Plantoir relies on finding them. This page says which they are, and what happens when one is renamed or deleted.

## See the list for your own course

The list is different for each course, because it names that course's own folders.

1. In the sidebar, select the course. Its settings show.
2. In the {{control:courseSettingsMarksPart}} part, click {{control:specialFoldersLink}} A sheet titled {{control:specialFoldersSheetTitle}} opens.
3. Read the rows. Each names a folder or page of this course and says what it is for.
4. Press {{control:done}}.

{{picture:special-folders-1}}
alt: The Folders Plantoir uses sheet for one course, with a row for each special folder, naming the folder and saying what it is for.

The sheet begins:

{{say:shared-rules#specialFoldersHelp.intro}}

## What each row is

The rows are always in this order.

| Row | What it names | What Plantoir does with it |
|---|---|---|
| {{control:specialFoldersRowLessons}} | The folder that holds the class pages, usually All Classes. | Puts new classes there, keeps them in date order, and uses them to work out which pages the classes teach. |
| {{control:specialFoldersRowCurriculum}} | The folder of curriculum expectations, one page for each. | Builds the curriculum map from them. Without them the map is left out. |
| {{control:specialFoldersRowMarks}} | The folders you chose under {{control:foldersWhoseWorkCountsForMarks}}. | Shows an expectation as evaluated on the curriculum map when a page in one of them addresses it. |
| {{control:specialFoldersRowMedia}} | The Media folder. | Looks after it and keeps it out of the sidebar. If it goes missing, pictures stop appearing on the site. |
| {{control:specialFoldersRowFolderPage}} | The page each section, and each folder, opens on. | Uses it as the way in. It is not a lesson. |
| {{control:specialFoldersRowKeyLinks}} | Key Links. | Adds the curriculum map to this list on the website. Your own copy is left as you wrote it. |
| {{control:specialFoldersRowWrittenForYou}} | The page of the curriculum map. | Writes it again each time the site is made. Do not write a page of your own with its name, because it would be replaced. |

A course with no folder of curriculum expectations shows the words Your curriculum folder in that row. A course with no folders chosen for marks shows None chosen.

{{assistant}}
The page of the curriculum map is named Curriculum Coverage. A course with a second curriculum has a second such page: see [A second curriculum](page:second-curriculum).
{{/assistant}}

## Renaming one

Rename a folder in the course's settings, not in Finder or Obsidian. Plantoir then renames it in every section and points your pages' links at the new name. [Shared folders and section folders in Course Settings](page:course-folders) has the steps.

Nothing else can be named Media, because Plantoir looks after that folder itself.

## If one is renamed or deleted outside Plantoir

Plantoir notices the next time the section is previewed or deployed, and the section's Problems tab says what is missing.

- **The Media folder is gone.** The Problems tab says the Media folder is not there, and pictures stop appearing on the site.
- **A section's front page is gone.** The Problems tab says the section has no front page.
- **The curriculum expectations are gone.** The curriculum map cannot be made, and the Problems tab says so.

[The Problems tab](page:problems) says how to put each of these right. A backup can bring back what a folder held: see [Back up a course and restore it](page:backups).

## Removing one from the website

Removing a folder in the course's settings takes it off the website and leaves it on this Mac. Some of these folders cannot be removed there at all. [Shared folders and section folders in Course Settings](page:course-folders) lists them.
