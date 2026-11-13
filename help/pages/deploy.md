---
id: deploy
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Section/SectionDetailView.swift
- mac-app/QuartzTeachers/Views/Console/TaskProgressView.swift
- mac-app/QuartzTeachers/Views/Section/DeployDestinationLinks.swift
- contracts/app-rules.json
- contracts/shared-rules.json
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- deploy
- upload
- go live
- put online
- update the site
- send the site
- students cannot see
- site address
- cannot deploy yet
description: Deploy sends a section's whole website, with every page published for that section, to the place the course deploys to.
---
To deploy a section is to send its website to where students read it. A deploy carries every page that is published for that section at that moment.

## Steps

1. In the sidebar, select the section.
2. Press {{control:deployButton}} in the toolbar, or choose {{menu:deploy}} ({{key:deploy}}).
3. If a sheet titled {{control:laterClassesTitle}} opens, answer it. Plantoir asks only when published classes are dated after the next class. [Classes dated after the next class, at Deploy](page:later-classes) says what the ticks mean.
4. Wait while Plantoir makes the website and sends it. The section's window says what is happening. If the section's preview was running, it is stopped.

{{picture:deploy-2}}
alt: The section's window during a deploy, with a line that says what is happening now.

5. Read the result when the window says the deploy is done.
   - For Netlify or Cloudflare Pages, it says that your website is live, and shows the website's address as a link.
   - For a folder on this Mac, it says so, and has a {{control:showInFinder}} button.
   - For a course that deploys to more than one place, it shows a link or a {{control:showInFinder}} button for each.

{{picture:deploy-3}}
alt: A finished deploy in the section's window, with the website's address shown as a link.

6. Click the address to open the website and check it.

## The first deploy to a new place

The first deploy of a section to Netlify or Cloudflare Pages may stop to ask you something. It may ask for a token from your account, your surname, or a name for the website. The window says it is waiting for your answer. These pages say what each question means:

- [Put your site online with Cloudflare Pages](page:cloudflare)
- [Set up Netlify](page:netlify)
- [Your site's address](page:site-address)

[Choose where a section deploys](page:destinations) explains the three places a course can deploy to.

## What a deploy sends

- **The whole website of one section.** You deploy a section, never a single page.
- **Every page published for that section.** A page you published last week and have not looked at since goes out too.
- **Nothing that is hidden in that section.**

Previewing first shows you what the deploy will send. See [Preview a section](page:preview). [Publishing and deploying](page:publish-and-deploy) explains how the two acts differ.

## After the deploy

Plantoir may show a list of hidden pages. It appears when pages students can now see link to pages that are still hidden. See [Publish the pages a class page links to](page:links-checklist).

To have a section deploy at a later time without you, see [Schedule a deploy for later](page:schedule-deploy).

## If it does not work

- **An alert titled {{control:cannotDeployYet}} appears.** Something the deploy needs is missing, and the alert says what. Two examples are a Cloudflare Account ID, and the folder a course deploys into. When the Account ID is missing, the alert also has an {{control:openSettings}} button.
- **{{control:deployButton}} is greyed.** The section is already being deployed, a copy of the course is being saved, or the working folder is still being made ready. Hold the pointer over the button: when the course is being previewed or deployed somewhere else on this Mac, the button's help says so.
- **There is no {{control:deployButton}} button.** The course is kept for reference. A course kept for reference is never deployed.
- **You pressed {{control:cancel}} on the question about later classes.** Nothing was deployed.
- **The window says something went wrong.** It gives an explanation. See [A deploy did not work](page:deploy-failed).
- **A change to the course's settings did not go out.** A deploy uses the settings as they were last saved, and a notice says so. Save them, then deploy again.
