---
id: deploy-failed
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Section/SectionDetailView.swift
- mac-app/QuartzTeachers/Views/Console/TaskProgressView.swift
- contracts/app-rules.json
- contracts/shared-rules.json
keywords:
- deploy failed
- could not deploy
- deploy did not work
- deploy stopped
- deploy greyed
- deploy disabled
- token
- access token
- internet
- offline
- Netlify
- Cloudflare
- file too large
description: What the sentence after a failed deploy means and what to do about it, and the reasons the Deploy button is greyed.
---
When a deploy does not finish, the section's window says what went wrong and what to do. This page lists those sentences, and the reasons {{control:deployButton}} can be greyed.

## Read the sentence in the section's window

Plantoir turns a failure it recognises into one sentence. Find yours here.

- No internet connection:
  {{say:app-rules#failureExplanations.cases[9].expect}}
- Netlify asks you to wait. The time it names can differ:
  {{say:app-rules#failureExplanations.cases[4].expect}}
- No Netlify token is saved yet:
  {{say:app-rules#failureExplanations.cases[7].expect}}
- Netlify refused the token:
  {{say:app-rules#failureExplanations.cases[8].expect}}
- Cloudflare refused the token:
  {{say:app-rules#failureExplanations.cases[11].expect}}
- Plantoir could not reach Cloudflare to check the token. There is a sentence like it for Netlify:
  {{say:app-rules#failureExplanations.cases[13].expect}}
- The website has not been made yet:
  {{say:app-rules#failureExplanations.cases[15].expect}}
- The section has no front page:
  {{say:app-rules#failureExplanations.cases[16].expect}}
- The front page's settings cannot be read:
  {{say:app-rules#failureExplanations.cases[19].expect}}
- A deploy to a folder could not copy every page:
  {{say:app-rules#failureExplanations.cases[3].expect}}

{{picture:deploy-failed-2}}
alt: A deploy that failed, in the section's window, with the sentence that says what went wrong and what to do.

When Plantoir does not recognise what went wrong, it adds no sentence of its own. The window then shows what the deploy itself reported.

## A token that was refused

Deploy again, and paste a new token when Plantoir asks for one. These pages say where a token comes from:

- [Put your site online with Cloudflare Pages](page:cloudflare)
- [Set up Netlify](page:netlify)

## A missing front page

The section's {{control:problemsTab}} tab can put a front page back for you. See [The Problems tab](page:problems).

## A file too large for Cloudflare Pages

Cloudflare Pages refuses any single file bigger than 25 MB, and the section is not deployed there. The section's {{control:problemsTab}} tab names the file, in a row of the kind {{control:problemsTabKindFileTooLarge}}. Shorten or compress the file. Or deploy the section to Netlify, which allows larger files.

## Deploy is greyed

Hold the pointer over {{control:deployButton}}. Its help says why when the course is being previewed or deployed somewhere else on this computer. That can be another copy of Plantoir, or a scheduled deploy that is running now. {{control:deployButton}} is available again once that preview is stopped or that deploy has finished.

{{assistant}}
An assistant working on the course from another app holds it in the same way.
{{/assistant}}

{{picture:deploy-failed-1}}
alt: The Deploy button greyed in the toolbar, with the help that says the course is being deployed somewhere else on this computer.

{{control:deployButton}} is also greyed:

- while the section is already being deployed;
- while a copy of the course is being saved;
- while the working folder is being got ready;
- for a course kept for reference, which is never deployed.

## A second deploy of the same section

A section cannot be deployed while it is still being deployed, by you or by a scheduled deploy. The same is true while its website is still being made. Plantoir refuses the second deploy before anything changes. The window says the section cannot be deployed until that has finished, and ends with the words Nothing was changed.

## If it keeps failing

If the same failure keeps coming back, see [Send a problem report](page:report).
