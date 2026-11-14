---
id: working-folder
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/WorkspacePickerView.swift
- mac-app/QuartzTeachers/Models/WorkspaceModel.swift
- mac-app/QuartzTeachers/App/FileCommands.swift
- contracts/shared-rules.json
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- working folder
- course notes folder
- where are my courses
- change folder
- move courses
- move the folder
- open recent
- home folder
- external drive
- could not be opened
- Desktop
- Documents
description: Choose the folder that holds your courses, change to another one, reopen a recent one, and know which folders Plantoir can use.
---
The working folder is the folder that holds your courses. Plantoir shows one working folder in a window at a time. This page says how to choose it, change it and move it.

Inside the working folder is a folder named `courses`, and each of your courses is a folder inside that. [How Plantoir is organised](page:organised) has more.

## Choose a folder the first time

1. Open Plantoir. With no working folder, the window says {{control:workingFolderPickerTitle}}.
2. Press {{control:workingFolderPickerChooseFolder}} and choose a folder. Choose the folder that has your courses inside, or an empty folder if you are starting out.

{{picture:working-folder-1}}
alt: Plantoir's window with no working folder open, showing the words Choose Your Working Folder and the Choose Folder… button.

3. If the folder is empty, Plantoir asks whether to set it up as your working folder. Press {{control:workingFolderPickerSetUpThisFolder}}. When that is done, the {{control:newCourseOrClub}} sheet opens by itself.

## Change to another folder

1. Choose {{menu:openWorkingFolder}} ({{key:openWorkingFolder}}).
2. Choose the folder and press {{control:openWorkingFolderPanelOpenButton}}.

The window switches to that folder and shows its courses. Whatever course was selected is no longer selected.

## Go back to a folder you used before

{{menu:openRecent}} lists the folders you have opened, with the newest first. Choose one to open it. If a window is in front, that window switches to the folder. If no window is open, a new one opens.

{{picture:working-folder-2}}
alt: The File menu open on Open Recent, listing the folders opened before, with Clear Menu at the end.

{{menu:openRecentClearMenu}} empties the list.

When Plantoir opens, its first window opens on the working folder you used last.

## Which folders can be used

{{mac}}
A working folder must be inside your home folder. A folder anywhere else is refused, both when you choose it and when Plantoir opens it again. There is no way to use it anyway. Plantoir says what to do:

{{say:shared-rules#workingFolderReach.wording.whatToDo}}
{{/mac}}

A folder kept in step by iCloud Drive, Dropbox, OneDrive, Google Drive or Box can be used. Plantoir shows one explanation first. See [A working folder in iCloud Drive or Dropbox](page:synced-folder).

## Move your courses

To move a working folder, move the whole folder in Finder. Then use {{menu:openWorkingFolder}} to choose it again from its new place. Until you do, Plantoir says that the folder cannot be found.

## If it does not work

When a folder from {{menu:openRecent}} cannot be opened, an alert names the folder and gives one of these reasons. The same reasons show in the window when the folder you used last cannot be opened as Plantoir starts.

- **It was moved or deleted.**
  {{say:shared-rules#openRecent.wording.gone}}
- **It is in the Trash.**
  {{say:shared-rules#openRecent.wording.inTrash}}
- **Its drive is not connected.**
  {{say:shared-rules#openRecent.wording.driveNotConnected}}
- **You may not read it.**
  {{say:shared-rules#openRecent.wording.unreadable}}
- **Plantoir is not allowed to open it.**
  {{say:shared-rules#openRecent.wording.privacyDenied}}

Two more things can puzzle:

- **The window says there are no courses in the folder.** The folder is a working folder with nothing in it yet. Make a course: see [Make a new course](page:new-course).
- **{{menu:newCourse}} is greyed.** No working folder is open, or the folder is still being made ready.
