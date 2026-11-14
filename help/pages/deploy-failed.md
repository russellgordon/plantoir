---
id: deploy-failed
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Section/SectionDetailView.swift
- mac-app/QuartzTeachers/Views/Console/TaskProgressView.swift
- contracts/app-rules.json
- contracts/shared-rules.json
- mac-app/QuartzTeachers/Models/DeployTokens/DeployTokenWording.swift
keywords:
- deploy failed
- could not deploy
- deploy did not work
- deploy stopped
- deploy greyed
- deploy disabled
- token
- access token
- token not saved
- expired token
- change token
- internet
- offline
- Netlify
- Cloudflare
- file too large
description: What the sentence after a failed deploy means and what to do about it, and the reasons the Deploy button is greyed or not there.
---
When a deploy does not finish, the section's window says what went wrong and what to do. This page lists those sentences, and the reasons {{control:deployButton}} can be greyed.

## Read the sentence in the section's window

Plantoir turns a failure it recognises into one sentence. Find yours here.

- No internet connection:
  {{say:app-rules#failureExplanations.cases[14].expect}}
- Netlify asks you to wait. The time it names can differ:
  {{say:app-rules#failureExplanations.cases[9].expect}}
- No Netlify token is saved yet:
  {{say:app-rules#failureExplanations.cases[12].expect}}
- Netlify refused the token:
  {{say:app-rules#failureExplanations.cases[13].expect}}
- Cloudflare refused the token:
  {{say:app-rules#failureExplanations.cases[16].expect}}
- Plantoir could not reach Cloudflare to check the token. There is a sentence like it for Netlify:
  {{say:app-rules#failureExplanations.cases[18].expect}}
- A token you pasted during this deploy was not saved. There are five such sentences, and each ends by saying it was not saved as your token. This is one:
  {{say:app-rules#failureExplanations.cases[21].expect}}
- A science simulation that a page uses has not been downloaded yet. The sentence names the section, the page and the simulation. See [Science simulations](page:phet). This is one:
  {{say:app-rules#failureExplanations.cases[1].expect}}
- The website has not been made yet:
  {{say:app-rules#failureExplanations.cases[22].expect}}
- The section has no front page:
  {{say:app-rules#failureExplanations.cases[23].expect}}
- The front page's settings cannot be read:
  {{say:app-rules#failureExplanations.cases[25].expect}}
- A deploy to a folder could not copy every page:
  {{say:app-rules#failureExplanations.cases[8].expect}}

{{picture:deploy-failed-2}}
alt: A deploy that failed, in the section's window, with the sentence that says what went wrong and what to do.

When Plantoir does not recognise what went wrong, it adds no sentence of its own. The window then shows what the deploy itself reported.

## A token that was refused

A service refuses a token that has expired, was deleted, or was turned off. Make a new token on the service's website. Then give it to Plantoir in one of two ways:

- Deploy again, and paste the new token when Plantoir asks for one.
- Choose {{menu:settings}}, open the {{control:plantoirSettingsDeployingPane}} pane, and press {{control:deployTokensChangeToken}}. The pane also says whether each saved token still works. See [See, change or remove a deploy token](page:deploy-tokens).

These pages say where a token comes from:

- [Put your site online with Cloudflare Pages](page:cloudflare)
- [Set up Netlify](page:netlify)

## A token that was not saved

Plantoir checks a token you paste during a deploy before it saves it. When the check fails, the deploy stops and the token is not saved. There are five reasons:

- **Nothing was pasted.** Copy the token from the service's page, deploy again, and paste it.
- **A space or a line break is inside what was pasted.** More than the token was copied. Copy the token alone.
- **A character that no token has is in what was pasted**, such as a curly quote. The token was copied from a document that changed it. Copy the token again from the service's own page.
- **The token cannot reach this section's website.** The section was deployed before with a token from another account. Paste a token from that account. If the old website was deleted on purpose, save the new token in the {{control:plantoirSettingsDeployingPane}} pane instead, with {{control:deployTokensChangeToken}}.
- **Plantoir could not reach the service to check the token against this section's website.** Try again in a few minutes, when this {{machine}} is online.

## A missing front page

The section's {{control:problemsTab}} tab can put a front page back for you. See [The Problems tab](page:problems).

## A file too large for Cloudflare Pages

Cloudflare Pages refuses any single file bigger than 25 MB, and the section is not deployed there. The section's {{control:problemsTab}} tab names the file, in a row of the kind {{control:problemsTabKindFileTooLarge}}. Shorten or compress the file. Or deploy the section to Netlify, which allows larger files.

## Deploy is greyed

Hold the pointer over {{control:deployButton}}. Its help says why when the course is being previewed or deployed somewhere else on this computer. That can be another copy of Plantoir, or a scheduled deploy that is running now. {{control:deployButton}} is available again once that preview is stopped or that deploy has finished.

{{assistant}}
An assistant that is previewing or deploying the course from another app holds it in the same way. An assistant that only has a session open on the course does not.
{{/assistant}}

{{picture:deploy-failed-1}}
alt: The Deploy button greyed in the toolbar, with the help that says the course is being deployed somewhere else on this computer.

{{control:deployButton}} is also greyed:

- while the section is already being deployed;
- while a copy of the course is being saved;
- while the working folder is being got ready.

A course kept for reference has no {{control:deployButton}} button at all, and {{menu:deploy}} is greyed for it. Such a course is never deployed.

## A second deploy of the same section

A section cannot be deployed while it is still being deployed, by you or by a scheduled deploy. The same is true while its website is still being made. Plantoir refuses the second deploy before anything changes. The window says the section cannot be deployed until that has finished, and ends with the words Nothing was changed.

## If it keeps failing

If the same failure keeps coming back, see [Send a problem report](page:report).
