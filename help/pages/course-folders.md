---
id: course-folders
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/CourseSettings/StringListEditorView.swift
- mac-app/QuartzTeachers/Views/CourseSettings/CourseSettingsView.swift
- mac-app/QuartzTeachers/Models/SpecialNames.swift
- contracts/shared-rules.json
keywords:
- folder
- folders
- shared folders
- per-section folders
- section folders
- add a folder
- rename folder
- rename a folder
- remove folder
- delete folder
- cannot be removed
- content structure
description: Add, rename or remove the folders and files that every section shares, or that each section has for itself, in a course's settings.
---
A course's settings list the folders and files that make up its websites. This page says how to add to those lists, rename a folder, and remove something, and which things cannot be removed.

## The four lists

In the {{control:courseSettingsContentStructurePart}} part of a course's settings there are four lists:

- {{control:courseSettingsSharedFoldersAllSections}} and {{control:courseSettingsSharedFilesAllSections}}: written once, and included in every section's website.
- {{control:perSectionFoldersList}} and {{control:perSectionFilesList}}: each section has one of its own by that name.

[Shared pages and section pages](page:shared-and-section) explains the two kinds. The same four lists are in the {{control:newCourseOrClub}} sheet, under {{control:newCourseSheetFoldersAndFiles}}.

{{picture:course-folders-1}}
alt: The Content Structure part of a course's settings, with the four lists and the buttons under a list that add and remove a row.

You do not have to use these lists to add things. A folder or file you make in Obsidian is added to the site at the next preview.

## Add a folder or a file

1. Press the + button under the list. A small field opens.
2. Type the name and press {{control:folderListAddButton}}.
3. Press {{control:courseSettingsSaveButton}} at the bottom of the form.

If the folder is not on this Mac yet, Plantoir makes it and tells you so. Open it in Obsidian to put pages in it.

## Rename a folder

1. In the list, double-click the folder, or press the pencil button on its row. You can also right-click it and choose {{control:folderListRenameMenuItem}} from the menu that opens. A sheet opens, with the folder's name in its title.
2. Type the name in the {{control:folderRenameSheetNewName}} field.
3. Press {{control:folderRenameSheetRenameButton}}.

{{picture:course-folders-2}}
alt: The sheet that renames a folder, with its explanation, the New name field and the Rename button.

The sheet explains what happens:

{{say:shared-rules#specialNames.renameFolder.explanation}}

Afterwards Plantoir says how many pages had links that it changed. The folder's other settings, such as whether the sidebar hides it, go with it to the new name. Only folders can be renamed here, not files.

## Remove a folder or a file

1. Select its row and press the Delete key, or press the − button under the list. You can also right-click the row and choose {{control:folderListRemove}}.
2. If Plantoir asks first, read the question and press {{control:folderListRemove}}. It asks about a folder whose work counts for marks. It also asks about a folder that holds curriculum expectations.
3. Press {{control:courseSettingsSaveButton}}.

Removing takes the folder or file off the website and nothing more. It stays on this Mac with everything in it. It also stays off the website, even if you make it again in Obsidian, until you add it back to the list.

## What cannot be removed

Some rows cannot be removed. An info button on the row says why.

- **The folder that holds the class pages.** In most courses it is named All Classes. It can still be renamed.
- **The last folder in {{control:perSectionFoldersList}}.** Each section needs at least one. Add another first.
- **The file for a section's front page.** Without it the section cannot be deployed.
- **A folder of curriculum expectations, while the curriculum map is turned on.**
- **The last folder that counts for marks, while the curriculum map is turned on.**

[The folders Plantoir treats specially](page:special-folders) says what these folders are for.

## If it does not work

- **The rename sheet refuses the name.** The sheet says why. The name is empty or unchanged, or has a / or a : in it. It begins with a dot, is Media, or is already used by another folder.
- **A rename did not finish.** Plantoir offers it again. Press {{control:folderRenameSheetRenameButton}} to finish it.
- **A rename found no folder.** No folder by that name was on this Mac, so only the course's settings changed. Make the folder in Obsidian when you need it.
- **A renamed folder still has its old name on the students' website.** Deploy each section.
