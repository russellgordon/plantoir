---
id: updates
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/App/AppUpdates.swift
- mac-app/QuartzTeachers/Models/UpdateWording.swift
- contracts/shared-rules.json
keywords:
- update
- updates
- updating
- new version
- check for updates
- install
- upgrade
- administrator
- administrator password
- restart
description: Plantoir checks for a new version once a day and installs one only when you choose to. It waits for a deploy or a preview to finish first.
---
Plantoir checks for a new version of itself once a day. It never downloads or installs one unless you choose to.

## Check now

1. Choose {{menu:plantoirCheckForUpdates}}.
2. If there is a new version, a window offers it. Follow the window to install it.

{{picture:updates-1}}
alt: The window that offers a new version of Plantoir.

When the new version is installed, Plantoir closes and opens again by itself.

## Plantoir waits for work to finish

Plantoir never installs a new version while it is deploying or making a preview. It also waits while a scheduled deploy, or another program, is making the website of a course it has open.

When it has to wait, a notice says that Plantoir will finish updating once that work is done, and names the work. Under that it says:

{{say:shared-rules#appUpdates.wording.heldExplanation}}

Once the new version has begun to install, the notice says this instead:

{{say:shared-rules#appUpdates.wording.heldExplanationOnceInstalling}}

Press {{control:updateNoticeOk}} and carry on.

## If an administrator is needed

Installing a new version can need the name and password of an administrator of this {{machine}}. If none is given, a notice says:

{{say:shared-rules#appUpdates.wording.needsAdministratorTitle}}

{{say:shared-rules#appUpdates.wording.needsAdministratorExplanation}}

## Updates and quitting

An update never stops you from quitting. [Quitting while something is running](page:quitting) says when Plantoir does ask before it quits.

After an update, the first preview can be slow again, once. See [The first preview is slow](page:slow-first-build).
