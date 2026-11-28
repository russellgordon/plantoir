# W8b-19a3: both assistants refuse while a rename holds the course (#899, Windows #949)

Stands on 19a2 (`CourseActivity.FolderRenameRefusal`). Base `origin/issue/899-w8b-19a2-the-app-refuses-at-the-click` (f75625dd7); `origin/dev` is in the branch.

## The HELD condition: no route

`Plantoir.Mcp` sees what other processes do only through `WorkLease` files under `courses/.internal/activity/` (`OutsideChangeGate` 66 through `WorkLease.WhatAnOutsideChangeMeets`, `PlantoirTools` 377 through `HeldBy`). The rename claim (19a1) lives in the app's memory (`CourseActivity._folderRenames`). No existing kind carries it: the kinds are a contract row (`file-formats.json` → `workLease.kinds`: `import`, `build`, `preview`, `publish`, `assist`, `copy`), each with a fixed meaning. Taking `build` or `copy` for a rename would misstate what is going on, and the outside assistant could not tell a rename from a build or a zip, so it could not say `renameFolderUnderWay`. A route needs a new lease kind (for example `rename`), with its row in `workLease.kinds`, and a decline rule in `workLeases.declining`. That is Russell's question 3 in the ORDER file. Only the window's half is built here.

## Built (the window's assistant)

- `AssistToolRunner.WorkingFolder` and `AssistToolRunner.SiteWork` (`rebuild_preview`, `deploy_section`: the mac's `AssistSiteWork` 161 and 278). `schedule_deploy` is not refused: the mac's `scheduleDeploy` never reads the rename claim, so a test pins that it still goes ahead. The mac's `bringThePreviewUpToDate` is not a tool; its Windows counterpart is the preview restart after a page edit, which is the parked page-edit case, so no tool is added for it. At the top of `Run`, after the Section menu's claim, a site-work tool on a course a rename holds returns `CourseActivity.FolderRenameRefusal`'s sentence, before the later-classes question, any preview stop, any in-app press or any server call. Reading tools go on.
- Wired: `AssistAgent.WorkingFolder` (passed in `RunTool`), set by `AssistWindow` to `_folder`; the menu runner (`MainWindow.MenuRunner`) sets `folder`.
- `AssistSectionRestore.Restore` (the assistant window's Restore Section N…; the mac's `Problem.folderRenameUnderWay`) refuses with the sentence before the backup is read.
- Page edits are not refused, as on the mac (its runner refuses site work and the section restore only).

## Tests

`Plantoir.Tests/AssistantRefusesDuringARenameTests.cs`. Tests-first commit 1fc2f38f4 (a stub `WorkingFolder`, unread). Red there: the site-work cases (then three; `schedule_deploy` was taken out in fix round 1) (the sentence check), the section restore, and the three wiring cases. The reading tool, another course's rename and the ended claim pass on both.

## Self-check

- One function for the rule: every refusal calls `CourseActivity.FolderRenameRefusal`. The sentence is read by key through it.
- No tool added, no tool description changed, no `contracts/` change, no ledger row.
- No new control, no confirmation, no timed wait.
- I left no run going and removed no lock.

## Fix round 1 (review 1)

- MEDIUM: `schedule_deploy` out of `SiteWork` and the theory; new test `WhileARenameHoldsTheCourseTheAssistantStillSchedulesADeployAsOnTheMac`. Must-fail rows: the `schedule_deploy` row now takes out `deploy_section`, and a new row puts `schedule_deploy` back.
- LOW 1: the restore test's `File.Exists(backup)` check, which proved nothing, is gone.
- LOW 2 (refusal order on `rebuild_preview`) left: no teacher can see it. LOW 3 (`RestoreSectionButton` greyed during a rename) is for 19b.
