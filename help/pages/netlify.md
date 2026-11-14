---
id: netlify
checked: 2.0.0
factsChecked: 2026-11-01
covers:
- mac-app/QuartzTeachers/Views/CourseSettings/PublishingChoiceView.swift
- mac-app/QuartzTeachers/Views/Console/CredentialRequestSheet.swift
- mac-app/QuartzTeachers/Scripting/CredentialRequest.swift
- mac-app/QuartzTeachers/Models/PublishingDestinations.swift
- scripts/deploy.py
- contracts/app-rules.json
- documentation/07-deployment.md
keywords:
- Netlify
- netlify.app
- access token
- token
- credits
- free plan
- allowance
- paused site
- site not available
- surname
- site name
description: Deploy a course's sections to Netlify, and what to know about the monthly allowance on Netlify's free plan before you choose it.
---
Netlify is one of the three places a course can deploy to. This page says what to know before you choose it, and takes you through the first deploy, which asks three questions.

## Before you choose Netlify

When you choose Netlify, the course's settings show this note:

{{say:app-rules#publishingDestinations.sentences.netlifyNote}}

The figures on Netlify's free plan for such an account, as Netlify gave them on the date at the foot of this page:

- The account gets {{fact:netlifyCreditsAMonth}} credits a month, and that is a hard limit.
- One deploy of one section uses {{fact:netlifyCreditsADeploy}} credits. Each section is a website of its own, so one deploy of each of three sections uses {{fact:netlifyCreditsToDeployThreeSections}} in all.
- Visits to your websites use credits as well.
- When the credits run out, Netlify pauses every site in the account until the next month begins. Visitors see a notice that the site is not available.

Deploying is what uses the allowance. Publishing or hiding a page uses none, because nothing is sent until you deploy.

## Choose Netlify for the course

1. In the sidebar, select the course. Its settings show.
2. In the {{control:deployingPart}} part, open {{control:deployingPartDeployTo}} and choose {{control:deployToNetlify}}.
3. Press {{control:courseSettingsSaveButton}}.

## Deploy for the first time

1. Select the section and press {{control:deployButton}}.
2. A sheet titled {{control:connectToNetlifySheetTitle}} opens. It lists the steps for making an access token on Netlify's website, and has a link named {{control:connectToNetlifySheetLink}}. Follow its steps in your browser. One of them matters months later:
   {{say:app-rules#credentialRequests.requests[0].steps[3] ~ Change the expiry — it}}
3. Netlify shows the token once. Copy it, paste it into the {{control:connectToNetlifySheetTokenField}} field, and press {{control:credentialSheetContinueButton}}. The token is saved securely on this computer, and Plantoir does not ask for it again.
4. If a sheet titled {{control:teacherSurnameSheetTitle}} opens, type your surname in the {{control:teacherSurnameSheetSurnameField}} field, using letters only. Plantoir asks once, and uses the surname in the names of your class websites.

{{picture:netlify-1}}
alt: The Teacher Surname sheet at a first deploy to Netlify, with the Surname field.

5. A sheet titled {{control:websiteAddressSheetTitle}} opens, with a suggested name already in the {{control:websiteAddressSheetAddressField}} field. Keep it or change it, and continue. If another Netlify site already has that name, a sheet titled {{control:websiteAddressTakenSheetTitle}} asks for a different one. [Your site's address](page:site-address) explains the name and both sheets.
6. Wait while Plantoir makes the website and sends it. When it has finished, the window says that your website is live, and shows the address as a link. That address is the one to give your class.

The three questions always come in this order: the token, then your surname, then the name. Each section has a website of its own, so the first deploy of another section asks for that section's name. After that, a section's deploys ask nothing.

## Scheduled deploys

A scheduled deploy uses the allowance like any other, and the sheet that schedules one carries a note about it. A section must be deployed to Netlify once by hand before a deploy can be scheduled. See [Schedule a deploy for later](page:schedule-deploy).

## If it does not work

- **Deploys stop working months later, with nothing on screen to say why.** The token has expired. Netlify's tokens start with an expiry of 7 days unless you change it when you make one.
- **Students see a notice that the site is not available.** The month's credits may have run out. Netlify brings the sites back when the next month begins.
- **The name is taken.** Add a number to the end, or your school's initials. See [Your site's address](page:site-address).
- **Something else went wrong.** See [A deploy did not work](page:deploy-failed).

If the allowance is too small for the way you deploy, Cloudflare Pages has no limit on visitors. See [Choose where a section deploys](page:destinations).
