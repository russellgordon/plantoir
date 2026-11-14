---
id: publish-and-deploy
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/App/ProblemReportCommands.swift
- contracts/assist-wording.json
keywords:
- publish
- publishing
- published
- deploy
- deploying
- deployed
- difference
- hide
- hidden
- go live
- online
- students cannot see
description: Publishing marks a page to be included in a section's website. Deploying sends the section's website to where students read it.
---
Publishing and deploying are two different acts. Students see a page only after both: the page is published for their section, and then their section is deployed.

## Publishing marks a page

To publish a page is to mark it as one that students in a section may see. To hide a page is the opposite.

- You publish a page for a section. The same shared page can be published for one section and hidden in another.
- Publishing changes the page's settings in your course folder, and what Preview shows you. Nothing leaves your {{machine}}.
- Students see no change until the section is next deployed.

[Show or hide pages for a section](page:publish-pages) has the steps.

## Deploying sends a section's website

To deploy a section is to send its whole website to where students read it: Cloudflare Pages, Netlify, or a folder on this {{machine}}.

- You deploy a section, never a single page.
- A deploy carries every page that is published for that section at that moment.
- Pages that are hidden in that section are left out.

[Deploy a section](page:deploy) has the steps, and [Choose where a section deploys](page:destinations) explains the three places.

## What follows from this

- **Publishing alone shows students nothing.** A page can be published for days before students see it. It reaches them at the section's next deploy.
- **A deploy sends everything that is published.** If you published a page last week and forgot about it, the next deploy puts it in front of students.
- **Preview first.** Preview shows the section's website on your {{machine}}, with the pages that are published for that section. Looking it over before you deploy is the safer order.

## The usual order

1. Write or change the page in Obsidian.
2. Publish the page for the section.
3. Preview the section and look the page over.
4. Deploy the section.

## The same explanation in the app

Choose {{menu:publishingAndDeploying}} from the menu bar. A box titled {{control:publishingAndDeployingTitle}} opens and says:

{{say:assist-wording#wording.publishingAndDeployingExplained}}

Press {{control:ok}} to close it.

{{picture:publish-and-deploy-1}}
alt: The Publishing and Deploying box, opened from the Help menu, with its explanation and an OK button.

> [!note]
> The box says that deploying sends the website out to the web. A section that deploys to a folder on this {{machine}} is sent to that folder instead. It reaches the web when you upload the folder to your web host.

## If students cannot see a page

Check both halves: that the page is published for their section, and that the section has been deployed since. [A page is missing from the site](page:missing-page) lists the other causes.
