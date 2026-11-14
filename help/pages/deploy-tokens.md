---
id: deploy-tokens
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Settings/DeployingSettingsView.swift
- mac-app/QuartzTeachers/Models/DeployTokens/DeployTokenPanel.swift
- mac-app/QuartzTeachers/Models/DeployTokens/DeployTokenWording.swift
- contracts/shared-rules.json
- contracts/app-rules.json
keywords:
- token
- tokens
- deploy token
- access token
- API token
- change token
- new token
- remove token
- expired token
- token expired
- end date
- expiry
- Netlify
- Cloudflare
- Cloudfare
- connected
- not connected
- check again
description: See whether the Netlify and Cloudflare tokens saved on this {{machine}} still work, change one, or remove one, in the Deploying pane of Plantoir's settings.
---
A token is what lets Plantoir deploy to your Netlify or Cloudflare account. Plantoir asks for one at the first deploy and saves it on this {{machine}}. This page says where to see whether a saved token still works, how to change it, and how to remove it.

## See your tokens

1. Open a working folder, if none is open. Plantoir checks a token from an open working folder.
2. Choose {{menu:settings}} and open the {{control:plantoirSettingsDeployingPane}} pane.

{{picture:deploy-tokens-1}}
alt: The Deploying pane of Plantoir's settings, with a Netlify part and a Cloudflare Pages part, each with a status line and its buttons.

The pane has a {{control:deployTokensNetlifySection}} part and a {{control:deployToCloudflarePages}} part. Plantoir checks both tokens when the pane opens. Each part then has a status line and three buttons: {{control:deployTokensChangeToken}}, {{control:deployTokensRemoveToken}} and {{control:deployTokensCheckAgain}}.

The status line says one of these things:

- **Connected.** The token is saved and the service accepts it.
- **Connected, with an end date.** Cloudflare tells Plantoir when a token ends, so the line gives the date. In the last 30 days before that date the line turns orange and asks you to make a new token. Netlify gives no end date, so nothing can warn ahead for a Netlify token.
- **Not connected.** No token is saved. The next deploy to that service asks for one.
- **The token is no longer accepted.** It was refused, has expired, or was turned off at the service. Change the token before you next deploy.
- **The token cannot deploy to the Cloudflare account above.** The token belongs to another account, or lacks the permission it needs.
- **The token could not be checked.** Plantoir could not reach the service. The token is still saved. Press {{control:deployTokensCheckAgain}} when this {{machine}} is online.

A check never changes or removes a token.

## Change a token

1. Make a new token on the service's website. [Set up Netlify](page:netlify) and [Put your site online with Cloudflare Pages](page:cloudflare) say how.
2. In the {{control:plantoirSettingsDeployingPane}} pane, press {{control:deployTokensChangeToken}} in that service's part. A sheet opens with the same steps the first deploy showed.
3. Paste the new token into the field. Press {{control:deployTokensCheckAndSave}}. Plantoir checks the token with the service, and then against every class website this working folder has deployed. The sheet's Cancel button waits while it checks.
4. When the token is accepted, it is saved and the sheet closes. The status line says the service is connected.

When the token is not saved, the reason shows under the field, and your old token stays as it was. Correct what the reason names, and press {{control:deployTokensCheckAndSave}} again.

## A token that cannot reach your class websites

A token belongs to one account. A token from a different account is a good token, but it cannot reach the websites your sections were deployed to with the old one. A deploy with it would make a new website at a new address, and the links your students have would stop working.

So Plantoir asks before it saves such a token. The question names the sections that were deployed with your old token.

{{picture:deploy-tokens-2}}
alt: The question asked when a new token cannot reach some class websites, with the sections named and a button for each choice.

- **{{control:deployTokensKeepMyOldToken}}** changes nothing. When no token was saved before, this button reads {{control:deployTokensDontSaveIt}}.
- **{{control:deployTokensUseTheNewToken}}** saves the new token anyway. Choose it only when you mean those sections to go to new websites, for example because the old ones were deleted on purpose.

## Remove a token

1. Press {{control:deployTokensRemoveToken}} in that service's part. A question opens.
2. Press {{control:deployTokensRemoveConfirm}}.

Deploys to that service then stop until a new token is saved. A deploy set for later will not run. The next deploy you start yourself asks for a token.

Removing a token here does not delete it at the service. To stop a token working everywhere, delete it on the service's website too.

## The warning before a Cloudflare token ends

A warning shows for the last 30 days before a Cloudflare token's end date, and after that date. It is above the website of every section that deploys to Cloudflare Pages. The same sentence shows in the Cloudflare part of the course's settings. The warning has an {{control:deployTokenEndOpenSettings}} button, which opens the {{control:plantoirSettingsDeployingPane}} pane.

Make a new token at Cloudflare, with an end date after the end of your school year or with none, and change it here. The warning goes once the new token is saved.

## If it does not work

- **The status line says to open a working folder.** No window with a working folder is open. Open one, then press {{control:deployTokensCheckAgain}}.
- **The reason under the field says what was pasted has a space, a line break, or a character no token has.** More than the token was copied, or it was copied from a document that changed it. Copy the token again from the service's own page.
- **Cloudflare did not accept the token.** Check that the token has the permission the sheet's steps name, and that the {{control:plantoirSettingsCloudflareAccountID}} above is your own.
- **The reason says the Account ID is not a whole ID.** Correct the {{control:plantoirSettingsCloudflareAccountID}} first. See [Put your site online with Cloudflare Pages](page:cloudflare).
- **Plantoir could not check the token against your class websites.** Nothing was changed. Try again when this {{machine}} is online.
- **A deploy stopped and said a token was not saved.** A token pasted during a deploy is checked in the same way. See [A deploy did not work](page:deploy-failed).
