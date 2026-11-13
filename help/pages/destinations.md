---
id: destinations
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/CourseSettings/PublishingChoiceView.swift
- mac-app/QuartzTeachers/Views/CourseSettings/CourseSettingsView.swift
- mac-app/QuartzTeachers/Views/CourseSettings/SectionSettingsView.swift
- mac-app/QuartzTeachers/Models/PublishingDestinations.swift
- mac-app/QuartzTeachers/Models/CourseConfiguration.swift
- contracts/app-rules.json
keywords:
- destination
- destinations
- where the site goes
- deploy to
- Cloudflare Pages
- Netlify
- folder
- redundancy
- second copy
- custom domain
- own domain
- school domain
description: Choose whether a course deploys to Cloudflare Pages, Netlify or a folder on this Mac. Add a second place, or use a domain of your own.
---
A course's sections can deploy to Cloudflare Pages, to Netlify, or to a folder on this Mac. You choose once for the course, in its settings, and every section of the course deploys there.

## The three places

- **Cloudflare Pages** puts each section's website on the web. It is where a new course deploys unless you choose otherwise, and the settings say of it:
  {{say:app-rules#publishingDestinations.sentences.cloudflareCaption}}
  See [Put your site online with Cloudflare Pages](page:cloudflare).
- **Netlify** also puts each section's website on the web. Its free plan has a monthly allowance that deploys use up. See [Set up Netlify](page:netlify).
- **A folder on this Mac** receives the website's files, and you upload them to your school's web space yourself. It needs no account. See [Deploy to a folder for your school's web space](page:folder-deploy).

## Choose where the course deploys

1. In the sidebar, select the course. Its settings show.
2. Find the {{control:deployingPart}} part, and open {{control:deployingPartDeployTo}}.
3. Choose {{control:deployToCloudflarePages}}, {{control:deployToNetlify}} or {{control:deployToAFolderOnThisMac}}. What the choice needs appears under it:
   - For Cloudflare Pages, your {{control:plantoirSettingsCloudflareAccountID}}, or the words {{control:deployingPartAccountIDNotSetYet}} and an {{control:openSettings}} button.
   - For Netlify, a note about its free plan.
   - For a folder, a {{control:deployingPartFolderField}} field and a {{control:deployingPartChooseFolderButton}} button.

{{picture:destinations-1}}
alt: The Deploying part of a course's settings with Deploy to open, showing the three places and the Also deploy to switches under it.

4. Press {{control:courseSettingsSaveButton}}. The next deploy of each section goes to the place you chose.

The same part is in the {{control:newCourseOrClub}} sheet, so you can choose when you make the course.

## Deploy to a second place as well

Under {{control:deployingPartAlsoDeployTo}} there is one switch for each place other than the one you chose above. Most teachers leave them off.

1. Turn on a switch. That place's own fields appear.
2. Fill them in, and press {{control:courseSettingsSaveButton}}.

A deploy then sends the website to each place, one after another. If one of them cannot be reached, the others still receive it. The finished deploy lists each place that received the website.

## Use an address on a domain you own

A section's website can use an address on a domain that you or your school owns. An example is `ics3u.yourschool.ca`. Plantoir does not set the domain up. You set it up in Cloudflare or in Netlify first, so that the website already answers there. Then you tell Plantoir, so that it uses that address.

1. Select the course, and scroll to the end of its settings. There is one part for each section, headed with the section's number.
2. In that section's part, open {{control:sectionSettingsAdvanced}}.
3. Type the domain in the {{control:sectionSettingsCustomDomain}} field. If you paste a whole address, Plantoir keeps only the domain.
4. Press {{control:courseSettingsSaveButton}}.

After the section's next deploy, the link to the live website uses your domain. Leave the field empty to use the address that Cloudflare or Netlify gives.

- A course that deploys to both Cloudflare Pages and Netlify has two fields, each named for its service. A domain typed for one is never used for the other.
- A folder on this Mac has no domain. For a course that deploys only to a folder, {{control:sectionSettingsAdvanced}} is empty.
- Each section has its own field, so two sections can have two addresses.

## If it does not work

- **{{control:courseSettingsSaveButton}} is refused for Cloudflare Pages.** No Cloudflare Account ID is saved in Plantoir's settings. See [Put your site online with Cloudflare Pages](page:cloudflare).
- **Orange text under the domain says it does not look like a domain.** It has a space in it, or no dot. Plantoir still accepts what you typed, so correct it before you save.
- **A course says Netlify and you never chose it.** A course made before these choices existed, and the example course, deploy to Netlify until you choose another place.
- **The website does not open at your domain.** Plantoir only uses the domain in its links. The domain must be set up in Cloudflare or Netlify.
- **A change here did not take effect.** A deploy uses the settings as they were last saved.

[Your site's address](page:site-address) says how the address that Cloudflare or Netlify gives is made.
