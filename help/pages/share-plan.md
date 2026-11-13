---
id: share-plan
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Planning/PlanShareBar.swift
- mac-app/QuartzTeachers/Views/Planning/PlanShareListsSheet.swift
- mac-app/QuartzTeachers/Models/PlanShareTables.swift
- mac-app/QuartzTeachers/Models/PlanSharing.swift
- mac-app/QuartzTeachers/Models/PlanningTab.swift
- contracts/shared-rules.json
- contracts/app-rules.json
keywords:
- share
- share plans
- unit plan
- unit plans
- colleague
- colleagues
- password
- username
- answer keys
- answer key
- stop sharing
- Planning tab
- Cloudflare
description: Share a course's unit plans with colleagues as a small website of their own, with or without a password.
---
You can share a course's unit plans with a colleague. Plantoir puts them on a small website of their own and gives you its address to send. This page says how to share the plans, how to protect them with a password, and how to stop.

## Before you start

- **The Planning tab.** The share bar is at the foot of a course's {{control:courseDetailPlanningTab}} tab. The tab shows only when Claude Code or Codex is installed on this Mac, and never for a course kept for reference. See [Plan a unit](page:plan-a-unit).
- **A Cloudflare account.** The share bar says:

{{say:shared-rules#unitPlanning.share.words.sharedThroughCloudflare}}

- **Your Cloudflare Account ID.** Choose {{menu:settings}}, open the {{control:plantoirSettingsDeployingPane}} pane and fill in {{control:plantoirSettingsCloudflareAccountID}}. [Put your site online with Cloudflare Pages](page:cloudflare) says where to find it.

If your class websites go to Netlify, the plans are still shared through Cloudflare Pages. The share bar says so, and the first time you are asked for a Cloudflare token.

## Share the plans

1. In the sidebar, select the course, then open the {{control:courseDetailPlanningTab}} tab. The share bar is at its foot.

{{picture:share-plan-1}}
alt: The share bar at the foot of the Planning tab before the plans are shared, with its two switches and the Share Unit Plans button.

2. Decide who may open the plans. Turn on {{control:sharePlanProtect}} if colleagues should type a username and a password first. Without a password, answer keys are left out unless you turn on {{control:sharePlanIncludeAnswerKeys}}.
3. Press {{control:sharePlanShareUnitPlans}}.
4. Read the sheet titled {{control:sharePlanListsTitle}} It holds two tables, Shared and Not shared, each with a count. Every share shows this sheet.
5. Move any document that is in the wrong table. Select it, then press {{control:sharePlanDontShare}} or {{control:sharePlanMoveToShared}}, or drag it to the other table.
6. Press {{control:sharePlanListsShareButton}}. Pressing Return chooses Cancel, not this button.
7. For a share with no password, read the warning that follows, titled {{control:sharePlanWarningTitle}} Press {{control:sharePlanShareWithoutPassword}} to go on, or Cancel to go back to the tables.
8. Wait while a sheet titled {{control:sharePlanConsoleTitle}} shows the progress. When it is done, the share bar shows the address.
9. Press {{control:sharePlanCopyLink}} and send the address to your colleague. For protected plans, send the username and the password as well.

> [!note]
> The first time you share protected plans, Plantoir asks for a username and then a password. The sheets are titled {{control:sharePlanUsernameTitle}} and {{control:sharePlanPasswordTitle}}. A username is 1 to 32 letters, digits, dots, dashes or underscores. A password is 8 to 64 characters. Keep a copy of the password somewhere safe, because Plantoir does not show it again. Choose ones made for your colleagues, not the password to your own accounts.

Plantoir keeps the username and password securely on this Mac. There is one pair for each course, and it stays the same from one school year to the next.

## Read the two tables

The sheet says this of its tables:

{{say:shared-rules#unitPlanning.share.openShareLists.byName}}

- Each row gives a document's name, its unit, its folder, its kind and a note.
- Anything in a unit's {{control:sharePlanAnswerKeysFolder}} folder is an answer key, and its note says so. A file kept elsewhere whose name looks like an answer key is noted as one that may be.
- To find a document, type in the {{control:sharePlanSearch}} field. The {{control:sharePlanUnitPopUp}} pop-up shows one unit or {{control:sharePlanAllUnits}}, and {{control:sharePlanAnswerKeysOnly}} shows the answer keys alone.
- The plan's own pages, pictures, stylesheets and fonts always go, and are not listed.

## What the warning says

A share with no password can be opened by anyone who has the address. The warning says so, and adds that search engines and AI crawlers are asked not to read or keep the plans, but can ignore that. It also counts the documents shared and held back, and says when an answer key is among the shared ones.

## After the plans are shared

The share bar says how the plans are shared: with a username and password, or open to anyone with the address. It also says when they were last shared. Its buttons are:

- {{control:sharePlanShareAgain}}, which shares the plans again.
- {{control:sharePlanChangePassword}}, {{control:sharePlanAddPassword}} or {{control:sharePlanRemovePassword}}, as fits how the plans are shared now. A new password is in use once the plans are shared again. Until then, people who open the address are asked for the old one.
- {{control:sharePlanStopSharing}}.

There is one such website for each school year. The school year changes on 1 August and is written like 2026-27. An earlier year's plans keep the password they were shared with.

## Stop sharing

Press {{control:sharePlanStopSharing}}. Plantoir asks first, and names the school year. The address stops working within a minute, and anyone you gave it to can no longer open the plans. The plans themselves are still on this Mac.

## If it does not work

- **The course has no Planning tab.** Neither Claude Code nor Codex is installed on this Mac, or the course is kept for reference.
- **Answer keys were left out.** The plans have no password. Protect them, or turn on {{control:sharePlanIncludeAnswerKeys}}, then share again.
- **The plans were not shared because the course is busy.** Plantoir says:

{{say:shared-rules#unitPlanning.share.words.courseBusy}}

- **A share did not finish.** Plantoir says:

{{say:shared-rules#unitPlanning.share.words.lastShareUnfinished}}

- **Stop Sharing did not work.** The address still works. Press {{control:sharePlanStopSharing}} again in a few minutes.
