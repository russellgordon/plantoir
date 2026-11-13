---
id: schedule-deploy
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Section/ScheduleDeploySheet.swift
- mac-app/QuartzTeachers/Models/ScheduledDeploy.swift
- mac-app/QuartzTeachers/Models/ScheduledDeployLateness.swift
- mac-app/QuartzTeachers/Views/CourseSettings/ScheduledDeployLatenessPicker.swift
- mac-app/QuartzTeachers/Views/SidebarView.swift
- mac-app/QuartzTeachers/App/SubjectMenus.swift
- contracts/shared-rules.json
- contracts/app-rules.json
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- schedule
- scheduled
- scheduled deploy
- schedule a deploy
- deploy later
- deploy tomorrow morning
- overnight
- timer
- automatic deploy
- deploy on its own
- cancel scheduled deploy
- notification
- clock
- asleep
description: Schedule Deploy sets a section to deploy on its own at a date and time, as long as this Mac is on and awake then.
---
A scheduled deploy sends a section's website at a date and time you choose, without you pressing Deploy. This Mac must be switched on and awake at that time.

## Before you schedule

A section that deploys to Netlify or Cloudflare Pages must have been deployed there once by hand. The first deploy asks questions, and nobody is there to answer them at the scheduled time. See [Deploy a section](page:deploy). A section that deploys to a folder does not need this.

## Schedule the deploy

1. In the sidebar, select the section.
2. Choose {{menu:scheduleDeploy}} from the menu bar, or right-click the section in the sidebar and choose the same command. A sheet titled {{control:scheduleADeploy}} opens. The command is greyed when the section already has a deploy scheduled: see the part on changing the time, below.
3. Set {{control:deployAt}} to the date and time. It starts at 6:30 tomorrow, and it cannot be set in the past.
4. Read the plan under the time. It names the section, where it deploys to, and when. It also says what this Mac needs at that moment:
   - The Mac must be switched on and awake, with its lid open if closing the lid puts it to sleep.
   - A Mac running on its battery goes to sleep sooner.
   - Plantoir does not wake the Mac. If it is asleep at the time, macOS runs the deploy when the Mac next wakes.
   - Anything you write before then goes out with the deploy.

{{picture:schedule-deploy-1}}
alt: The Schedule a deploy sheet, with the Deploy at date and time, the plan under it, and the Schedule button.

5. Press {{control:scheduleButton}}. The first time, macOS asks whether Plantoir may send notifications. Allow them, so that Plantoir can tell you how the deploy went.

A clock appears beside the section in the sidebar. Hold the pointer over it to read when the deploy will run. The text also says that this Mac must be on and awake, and that a right-click cancels.

{{picture:schedule-deploy-2}}
alt: The sidebar with a clock beside one section, and the text that appears when the pointer rests on it.

A section holds one scheduled deploy at a time.

For a course that deploys to Netlify, the sheet also carries a note about Netlify's monthly allowance. See [Set up Netlify](page:netlify).

## What happens at the time

The deploy runs whether Plantoir is open or not. It makes the website again first if the section has changed. If the website cannot be made, nothing is deployed.

A scheduled deploy asks no questions. It does not ask about classes dated later, so every published class goes out. See [Classes dated after the next class, at Deploy](page:later-classes).

Afterwards, one notification says how it went. When all is well, it names the section, says where it deployed to on its own, and says your website has the new pages.

Click the notification to open that section in Plantoir. The section's window shows the same sentence. If the deploy did not run or did not finish, a warning also appears beside the section in the sidebar.

{{picture:schedule-deploy-3}}
alt: The notification macOS shows after a scheduled deploy, which opens the section when clicked.

## How late a deploy may still run

A Mac that was asleep runs the deploy when it next wakes. You choose how long after the set time that is still worth doing.

1. Select the course, and open the {{control:deployingPart}} part of its settings.
2. Under {{control:howLateSetting}}, choose one day, three days, one week or two weeks. One week is the choice to begin with.

If the Mac wakes later than that, Plantoir cancels the deploy, leaves the website as it was, and tells you so.

## Cancel a scheduled deploy

1. Select the section and choose {{menu:cancelDeployAt}} from the menu bar. In the menu, the command's name includes the time of the deploy. The command is also in the menu that opens when you right-click the section.
2. An alert titled {{control:cancelScheduledDeployQuestion}} opens. Press {{control:cancelIt}}, or press {{control:leaveItScheduled}} to keep the deploy.

Plantoir also turns a scheduled deploy off when you remove the section or the course, or rename the course. It does the same when you start the section on a new website for a new year. Making a copy of a course to keep for reference leaves the course's own scheduled deploys as they are.

## Change the time of a scheduled deploy

While a section has a deploy scheduled, it cannot be given a second one. {{menu:scheduleDeploy}} is greyed in the menu bar, and the menu that opens on a right-click offers only the command that cancels the deploy.

1. Cancel the scheduled deploy, with the steps above.
2. Choose {{menu:scheduleDeploy}}, which is live again, and set the new time.

{{assistant}}
The assistant can change the time in one step. Ask it to schedule a section that already has a deploy set. The new deploy takes the place of the old one, and the assistant's plan says:

{{say:assist-wording#wording.scheduleReplaces}}
{{/assistant}}

## If it does not work

- **Orange text takes the place of the plan, and {{control:scheduleButton}} is greyed.** The text says why the deploy cannot be scheduled. The time may have passed, or a folder may need attention. A Cloudflare Account ID may be missing, or the section may never have been deployed to that place.
- **No notification came.** Notifications for Plantoir are turned off in macOS. The section's window still says how the deploy went.
- **{{menu:scheduleDeploy}} is greyed.** The section already has a deploy scheduled. Cancel it, then schedule again.
- **{{menu:scheduleDeploy}} is greyed and the section has no clock beside it.** The course is kept for reference. Such a course is never deployed, and the menu that opens on a right-click does not offer the command.
