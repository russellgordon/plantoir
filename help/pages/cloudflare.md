---
id: cloudflare
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Settings/DeployingSettingsView.swift
- mac-app/QuartzTeachers/Views/CourseSettings/PublishingChoiceView.swift
- mac-app/QuartzTeachers/Views/Console/CredentialRequestSheet.swift
- mac-app/QuartzTeachers/Scripting/CredentialRequest.swift
- mac-app/QuartzTeachers/Models/PublishingDestinations.swift
- mac-app/QuartzTeachers/Views/Console/TaskProgressView.swift
- scripts/deploy.py
- contracts/app-rules.json
keywords:
- Cloudflare
- Cloudflare Pages
- pages.dev
- account ID
- API token
- token
- put online
- go live
- first deploy
- free
- web address
description: Put a section's website on the web with Cloudflare Pages, from a new Cloudflare account to an address you can give your class.
---
Cloudflare Pages is a free service that keeps a section's website on the web. A new course deploys there unless you choose another place. This page goes from no Cloudflare account to a website with an address.

Cloudflare needs two things from you. Your Account ID says which account your websites go into, and you save it once in Plantoir's settings. A token lets Plantoir deploy to that account, and Plantoir asks for it at the first deploy.

## Copy your Account ID from Cloudflare

1. Make a free account on Cloudflare's website, and sign in to [the Cloudflare dashboard](https://dash.cloudflare.com).
2. Find the Account ID and copy it. Plantoir's own sheet about the Account ID gives the way:
   {{say:app-rules#credentialRequests.requests[3].steps[1]}}
   {{say:app-rules#credentialRequests.requests[3].steps[2]}}

The ID is also the long run of letters and digits in your browser's address bar, after `dash.cloudflare.com/`.

## Save the Account ID in Plantoir

1. Choose {{menu:settings}} and open the {{control:plantoirSettingsDeployingPane}} pane.
2. Paste the ID into the {{control:plantoirSettingsCloudflareAccountID}} field. An ID is 32 letters and digits, and orange text says so when what you pasted cannot be one.

{{picture:cloudflare-1}}
alt: The Deploying pane of Plantoir's settings, with the Cloudflare Account ID field and the Where do I find this? button.

You do this once. Every course that deploys to Cloudflare Pages uses the same account. The {{control:plantoirSettingsWhereDoIFindThis}} button opens a sheet titled {{control:accountIDHelpSheetTitle}}, which repeats the steps above and has a field of its own and a {{control:accountIDHelpSheetUseThisID}} button.

## Check where the course deploys

1. In the sidebar, select the course. Its settings show.
2. In the {{control:deployingPart}} part, look at {{control:deployingPartDeployTo}}. A new course already says {{control:deployToCloudflarePages}}. If yours does not, choose it and press {{control:courseSettingsSaveButton}}.

{{picture:cloudflare-2}}
alt: The Deploying part of a course's settings, with Deploy to set to Cloudflare Pages and the saved Account ID under it.

## Deploy the section

1. Select the section and press {{control:deployButton}}.
2. The first time this Mac deploys to Cloudflare, a sheet titled {{control:connectToCloudflareSheetTitle}} opens. It lists the steps for making a token on Cloudflare's website, and has a link named {{control:connectToCloudflareSheetLink}}. Follow its steps in your browser. Two of them decide whether the token works:
   {{say:app-rules#credentialRequests.requests[1].steps[3]}}
   {{say:app-rules#credentialRequests.requests[1].steps[4]}}
3. Cloudflare shows the token once. Copy it, paste it into the {{control:connectToCloudflareSheetTokenField}} field, and press {{control:credentialSheetContinueButton}}. The token is saved securely on this computer, and Plantoir does not ask for it again.

{{picture:cloudflare-3}}
alt: The Connect to Cloudflare sheet, with its steps, the Cloudflare token field and the Continue button.

4. If a sheet titled {{control:teacherSurnameSheetTitle}} opens, type your surname. Plantoir uses it to name the website. Cloudflare Pages does not ask you for a name for the website: Plantoir names it. [Your site's address](page:site-address) says how.
5. Wait while Plantoir makes the website and sends it. When it has finished, the window says that your website is live, and shows the address as a link.

{{picture:cloudflare-4}}
alt: A finished deploy in the section's window, saying the website is live and showing its address as a link.

6. Click the address to open the website and check it. That address is the one to give your class.

{{picture:cloudflare-5}}
alt: The class website open in a browser, at an address that ends in pages.dev.

Later deploys of this section ask nothing. [Deploy a section](page:deploy) describes an ordinary deploy.

## If it does not work

- **An alert titled {{control:cannotDeployYet}} appears.** No Account ID is saved, or the one saved cannot be an Account ID. Press {{control:openSettings}}, paste the ID, and deploy again.
- **The token stops working months later.** A token made with an end date expires on that date, and nothing on screen says why deploys have stopped. When you make the token, set its end date to after the end of your school year, or give it none.
- **One file is too large.** Cloudflare has a limit on the size of any one file:
  {{say:app-rules#publishingDestinations.sentences.cloudflareSizeNote}}
- **Something else went wrong.** See [A deploy did not work](page:deploy-failed).
