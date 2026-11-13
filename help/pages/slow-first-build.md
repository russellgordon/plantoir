---
id: slow-first-build
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Scripting/TaskMilestones.swift
- mac-app/QuartzTeachers/Views/Console/WhyTakingLongView.swift
- mac-app/QuartzTeachers/Views/Console/TaskProgressView.swift
- mac-app/QuartzTeachers/Models/ToolchainReadiness.swift
- contracts/app-rules.json
keywords:
- slow
- stuck
- taking forever
- taking a long time
- first time
- first preview
- waiting
- getting this Mac ready
- website builder
- still working
- after an update
description: The first preview on a Mac takes a couple of minutes while Plantoir sets up its website builder. Later previews usually take a few seconds.
---
The first preview on a Mac takes a couple of minutes, because Plantoir sets up its website builder first. Later previews and deploys usually take a few seconds. This page says how to tell that Plantoir is working, and when the wait comes back.

## How to tell it is working

While Plantoir works, the section's window shows a line that says what is happening now. The line changes with each step. For a preview, the lines are, in order:

- {{say:app-rules#milestones.preview[0].label}}
- {{say:app-rules#milestones.preview[1].label}}
- {{say:app-rules#milestones.preview[2].label}}
- {{say:app-rules#milestones.preview[3].label}}
- {{say:app-rules#milestones.preview[4].label}}
- {{say:app-rules#milestones.preview[5].label}}
- {{say:app-rules#milestones.preview[6].label}}
- {{say:app-rules#milestones.preview[7].label}}

The first two appear only when that part is needed.

{{picture:slow-first-build-1}}
alt: The section's window while a first preview is made, with the line that says what is happening now.

The window also counts the seconds while it is still working, so you can see that it has not stopped. When the work can be cancelled, there is a {{control:progressViewCancelButton}} button.

## Why might this take a while?

The link {{control:progressViewWhyMightThisTakeAWhileLink}} is in the window whenever Plantoir is working. Click it and a small box opens beside it, with four headings:

- {{control:whyTakingLongFirstTimeSetupHeading}}: setting up your website builder takes a couple of minutes. Previews and deploys after that are much faster.
- {{control:whyTakingLongFirstTimeDeployingHeading}}: the first deploy uploads the whole website. Later deploys upload only the pages that changed.
- {{control:whyTakingLongPhotosAndAttachmentsHeading}}
- {{control:whyTakingLongInternetConnectionHeading}}

## When the wait comes

- **The first time on a Mac.** When you first open Plantoir, it starts getting the Mac ready while you choose a folder and make a course. One line at the foot of the sidebar says so:
  {{say:app-rules#builderWarmUp.wording.statusLine}}
  You can carry on working. If you preview before that has finished, the preview waits for it. If the Mac was offline, the work is done at the first preview instead.
- **After an update.** The first preview after Plantoir updates can be slow again, once.
- **A course with Swift programs students can run.** The first time, Plantoir downloads what it needs to make them. The download is large. It takes a few minutes and needs the internet. See [Code students can run](page:code).
- **A working folder that was only now opened.** A notice says Plantoir is getting the folder ready, and that Preview and Deploy will work in a moment.

## If it does not work

- **The notice says the folder could not be got ready.** Choose {{menu:fileReloadCourses}} ({{key:fileReloadCourses}}) to try again.
- **The line has not changed for a long time.** Look at the count of seconds. If it is still going up, Plantoir is still working. Click {{control:progressViewWhyMightThisTakeAWhileLink}} for the likely reasons.
- **It stops and says something went wrong.** For a deploy, see [A deploy did not work](page:deploy-failed). If it keeps happening, see [Send a problem report](page:report).
