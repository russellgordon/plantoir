---
id: page-settings
checked: 2.0.0
covers:
- contracts/file-formats.json
- scripts/build_site.py
- mac-app/QuartzTeachers/Models/SectionProblemsWording.swift
keywords:
- publish a page
- hide a page
- publish
- publishForSection1
- publishForSection2
- draft
- page settings
- properties
- settings at the top
- which section sees a page
- students cannot see
description: The lines at the top of a page that decide which sections' students see it, and the forms to type.
---
The settings at the top of a page decide which sections' students see it. This page gives the lines to type and says what each one does.

Plantoir's menus write these lines for you: see [Show or hide pages for a section](page:publish-pages). They write the right line for the right section, and they publish the pages a class page links to as well. Type the lines yourself only when you want to.

## Where the settings are

A page's settings are the lines between the two `---` lines at its top. Obsidian shows them as Properties.

{{picture:page-settings-1}}
alt: The settings at the top of a shared page in Obsidian, with one publish line for Section 1 and one for Section 2 marked.

## A shared page

A page shared by every section carries one line for each section:

```text wrap
publishForSection1: true
publishForSection2: false
```

`true` shows the page to that section's students. `false` hides it from them. With these two lines, Section 1's students see the page and Section 2's do not.

## A page that belongs to one section

A page in a section's own folder carries one line:

```text wrap
publish: true
```

Change it to `publish: false` to hide the page.

[Shared pages and section pages](page:shared-and-section) says which pages are which.

## What to know before you type

- **A page with no publish line is shown.** A missing line does not hide a page. To keep an unfinished page from students, give it the line with `false`.
- **Type only `true` or `false`.** Other words are read in ways that may surprise you: `publish: no` and `publish: off` hide a page, and `publish: yes` shows it.
- **Type `publish`, not `draft`.** Older pages may carry `draft: true`, or a line such as `draftSection1`. In that older form, `true` means hidden, the opposite of `publish`. Plantoir still reads both. The first time it changes such a page, it rewrites the lines in the new form.
- **Students see a change after the next deploy.** Changing a line changes your course. The website students read changes when the section is next deployed. See [Publishing and deploying](page:publish-and-deploy).

## If the settings cannot be read

A stray tab or a quotation mark that is never closed can make a page's settings unreadable. Plantoir then cannot tell which sections the page is meant for.

- The page is hidden from students in every section.
- Your file is not changed.
- The section's {{control:problemsTab}} tab names the page, in a row of the kind Page settings.

Correct the settings in Obsidian, then preview the section again. See [The Problems tab](page:problems).
