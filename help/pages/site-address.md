---
id: site-address
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Console/CredentialRequestSheet.swift
- mac-app/QuartzTeachers/Scripting/CredentialRequest.swift
- scripts/deploy.py
- contracts/app-rules.json
keywords:
- site address
- web address
- URL
- link
- surname
- last name
- site name
- name taken
- already taken
- pages.dev
- netlify.app
- school year
description: What the address of a section's website is made from, the surname question, and what to do when Netlify says a name is taken.
---
Each section's website has an address of its own, and the address comes from a name given to the website at its first deploy. This page says what the name is made from and which questions Plantoir asks about it.

A section that deploys to a folder on this {{machine}} has no such name, and is asked none of these questions.

## What the name is made from

Plantoir puts four things together, with hyphens between them:

| Part | Example |
|---|---|
| The course's code, in small letters | `mcv4u` |
| The letter s and the section's number | `s1` |
| The calendar year at the first deploy | `2026` |
| Your surname | `quillfeather` |

Together they make `mcv4u-s1-2026-quillfeather`. On Netlify the website's address ends in `netlify.app`. On Cloudflare Pages it ends in `pages.dev`.

## The surname question

The first time a new website is being named, a sheet titled {{control:teacherSurnameSheetTitle}} opens.

1. Type your surname in the {{control:teacherSurnameSheetSurnameField}} field, using letters only.
2. Press {{control:credentialSheetContinueButton}}. The deploy carries on.

Plantoir asks once for a working folder, and keeps the answer on this computer. The question comes up for Netlify and for Cloudflare Pages alike. The surname makes the address one that students and families recognise, and keeps it apart from other teachers' websites for the same subject.

## Netlify asks you to confirm the name

At a section's first deploy to Netlify, a sheet titled {{control:websiteAddressSheetTitle}} opens.

1. Read the name in the {{control:websiteAddressSheetAddressField}} field. Plantoir has filled it in from the four parts above.
2. Keep it, or type another. You may put your school's abbreviation in front. The sheet gives the rule:
   {{say:app-rules#credentialRequests.requests[5].steps[2] ~ Use only lowercase letters, numbers}}
3. Press {{control:credentialSheetContinueButton}}.

{{picture:site-address-1}}
alt: The Choose a Website Address sheet at a first deploy to Netlify, with the suggested name in the Website address field.

## If Netlify says the name is taken

Names on Netlify are shared by everyone who uses it, anywhere in the world. If another site has the name, a sheet titled {{control:websiteAddressTakenSheetTitle}} opens, with a number already added to the end of the name, such as `-01`.

1. Keep the name with its number, or add your school's initials to make it different.
2. Press {{control:credentialSheetContinueButton}}.

## Cloudflare Pages asks no name

For Cloudflare Pages, Plantoir makes the name from the same four parts and does not ask you about it. The address is the one Cloudflare gives that name, and the finished deploy shows it.

If your Cloudflare account already has a website with that name, because the section was deployed before, Plantoir uses that website again.

## After the first deploy

- Plantoir remembers each section's website. Later deploys of the section ask nothing and go to the same address.
- The year in the name is the year of the first deploy. Plantoir does not change it afterwards.
- Changing a course's code does not change the address. See [Rename or remove a course](page:rename-remove).

## An address on a domain you own

A section can use an address on a domain that you or your school owns, in place of the one Netlify or Cloudflare gives. [Choose where a section deploys](page:destinations) says where to type it and what must be set up first.

These pages take you through a first deploy from the start:

- [Put your site online with Cloudflare Pages](page:cloudflare)
- [Set up Netlify](page:netlify)
