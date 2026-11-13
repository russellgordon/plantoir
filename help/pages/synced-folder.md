---
id: synced-folder
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Models/CloudSyncedFolder.swift
- mac-app/QuartzTeachers/Views/WorkspacePickerView.swift
- contracts/shared-rules.json
keywords:
- iCloud
- iCloud Drive
- Dropbox
- OneDrive
- Google Drive
- Box
- sync
- synced
- syncing
- cloud
- Desktop and Documents
- working folder
- slow
description: Plantoir works with a working folder kept in sync by iCloud Drive, Dropbox, OneDrive, Google Drive or Box. It says first what syncing can mean.
---
A working folder can be in a folder that iCloud Drive, Dropbox, OneDrive, Google Drive or Box keeps in sync. Plantoir never refuses such a folder. It tells you what syncing can mean, and you choose.

## When you choose a synced folder

When you choose a synced folder as your working folder, Plantoir stops at the folder picker. It shows the folder's path, then a line that names the service the folder is kept in sync with. Under that it explains, in this order:

- Your notes are not moved:
  {{say:shared-rules#cloudSyncedFolders.wording.notesStayPut}}
- Some pages may be slow to read. The service may have moved pages off this computer to save space. Plantoir has to download each one before it can read it. Renaming a folder can take a while, because it reads every page.
- A move or a rename can fail. This happens if the service is busy copying a file at the moment Plantoir needs to move it. Plantoir checks before it moves anything. If a step fails, try again once syncing has settled.
- What you can do:
  {{say:shared-rules#cloudSyncedFolders.wording.whatToDo}}

{{picture:synced-folder-1}}
alt: The folder picker's note about a folder kept in sync, with the buttons Use This Folder Anyway and Choose a Different Folder.

Then choose one of the two buttons:

- {{control:syncedFolderUseThisFolderAnywayButton}} carries on with the folder.
- {{control:syncedFolderChooseADifferentFolderButton}} lets you pick another.

Neither button is the default, so pressing Return chooses neither.

Plantoir remembers that you went ahead with that folder and does not ask about it again. If you rename or move the folder, it asks again.

## When a folder you already use is synced

A folder can become synced after you set it up. You may have moved it into iCloud Drive, or turned on Desktop & Documents in iCloud.

When Plantoir opens such a folder, it shows a notice inside the window, above the line that names the working folder. It is never a dialog. The notice names the service and says:

{{say:shared-rules#cloudSyncedFolders.wording.summary}}

{{control:syncedFolderNoticeShowDetailsButton}} opens the full explanation in place, and {{control:syncedFolderNoticeHideDetailsButton}} closes it. {{control:syncedFolderNoticeGotItButton}} dismisses the notice.

## Where to keep a working folder

- To avoid the slow moments, keep the working folder inside your home folder, somewhere that is not synced.
- On a Mac with Desktop & Documents in iCloud, the Desktop is synced.
- A working folder must be inside your home folder in any case. See [Choose or change the working folder](page:working-folder).

Plantoir recognises a synced folder by how the Mac marks it, never by its name.
