---
id: folder-deploy
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/CourseSettings/PublishingChoiceView.swift
- mac-app/QuartzTeachers/Models/CourseConfiguration.swift
- mac-app/QuartzTeachers/Views/Console/TaskProgressView.swift
- contracts/shared-rules.json
- contracts/app-rules.json
keywords:
- folder
- deploy to a folder
- school web space
- school website
- web host
- SFTP
- FTP
- upload
- section1
- Show in Finder
- no account
description: Deploy a course's sections into a folder on this Mac, then upload that folder to your school's web space yourself.
---
If your school gives you web space, a course can deploy into a folder on this Mac. You then upload the folder to that web space in whatever way you normally do. Plantoir does not upload it, and you need no account with Cloudflare or Netlify.

## Choose the folder

1. In the sidebar, select the course. Its settings show.
2. In the {{control:deployingPart}} part, open {{control:deployingPartDeployTo}} and choose {{control:deployToAFolderOnThisMac}}.
3. Press {{control:deployingPartChooseFolderButton}} and choose the folder. You can make a new folder there. You can also type the folder's full location in the {{control:deployingPartFolderField}} field.

{{picture:folder-deploy-1}}
alt: The Deploying part of a course's settings set to a folder on this Mac, with the Folder field and the Choose… button.

4. Press {{control:courseSettingsSaveButton}}.

## Deploy, then upload

1. Select the section and press {{control:deployButton}}. A deploy to a folder asks no questions: no token, no surname and no name for the website.
2. Wait until the window says the deploy is done. It says that the website was deployed to a folder, and can be uploaded to a web host when you are ready.
3. Press {{control:showInFinder}} to see the folder.

{{picture:folder-deploy-2}}
alt: The chosen folder open in Finder after a deploy, with a folder named section1 inside it.

4. Upload the folder to your school's web space, for example over SFTP. Students see the website once it is there.

## What is in the folder

Each section deploys into a folder of its own inside the one you chose, named `section1`, `section2` and so on. Each of those is one whole website.

A later deploy copies only the files that have changed. Upload again after each deploy, or students keep seeing the website as it was.

## Things to know

- **The pages do not look right when opened straight from the folder.** The finished deploy says so. They display properly only once they are on a web host, and pages that run code need a web address. To look a section's website over on this Mac, use [Preview a section](page:preview).
- **A folder has no domain setting.** The address is whatever your school's web space gives it.
- **A deploy to a folder can be scheduled without a first deploy by hand.** See [Schedule a deploy for later](page:schedule-deploy).
- **A folder can be a second place.** A course that deploys to Cloudflare Pages or Netlify can also deploy to a folder. See [Choose where a section deploys](page:destinations).

## If it does not work

- **Orange text shows under the {{control:deployingPartFolderField}} field.** The text says what is wrong. No folder is chosen, or what you typed is not a full location. The folder does not exist, is a file, or cannot be written to. Press {{control:deployingPartChooseFolderButton}} to pick a folder or make one.
- **An alert titled {{control:cannotDeployYet}} appears.** No folder is chosen. Choose one in the course's settings, save, and deploy again.
- **The copy into the folder did not finish.** Plantoir counts that as a failure, even if part of the website was copied, and does not say the section was deployed. Deploy again. See [A deploy did not work](page:deploy-failed).
