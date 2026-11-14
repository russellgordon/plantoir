---
id: write-in-obsidian
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Section/SectionDetailView.swift
- mac-app/QuartzTeachers/App/SubjectMenus.swift
- contracts/shared-rules.json
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- write a page
- edit a page
- Obsidian
- open in Obsidian
- class page
- lesson page
- notes
- All Classes
- where do I write
- change not showing
description: Open a section in Obsidian from Plantoir, find the class page, write it, and see it in the section's preview.
---
The pages of a course are written in Obsidian, a separate app for notes. This page says how to open a class page there from Plantoir, write it, and see it on the section's website.

## Open the section in Obsidian

1. In Plantoir's sidebar, select the section.
2. Press {{control:openInObsidian}} in the toolbar, or choose {{menu:sectionOpenInObsidian}} from the menu bar. Obsidian comes to the front with the course open.

{{picture:write-in-obsidian-1}}
alt: A section selected in Plantoir's sidebar, with the Open in Obsidian button marked in the toolbar.

When the section's preview is showing a page, Obsidian opens on that same page. This works for a hidden page too. With a course selected in place of a section, {{menu:courseOpenInObsidian}} opens the course.

## Find the class page

1. In Obsidian's file list, open the section's folder. It is named `section1` for Section 1.
2. Open the folder All Classes. It holds one page for each class, named by unit and day: Unit 1, Day 1 and so on.
3. Click the class page you want to write.

{{picture:write-in-obsidian-2}}
alt: Obsidian with a class page open from the All Classes folder, and the page's settings at the top of the page.

If the page for the next class does not exist yet, make it in Plantoir first. See [Add the next class](page:add-next-class). [Class pages: Unit 1, Day 1](page:class-pages) says how these pages are named and dated.

## Write the page

Write the page as ordinary notes, under its settings.

- **Leave the settings at the top where they are.** They decide which sections' students see the page. Plantoir's menus change them for you: see [Show or hide pages for a section](page:publish-pages). [Which classes see a page](page:page-settings) has the rules for typing them yourself.
- **Link to a shared page by its name in double square brackets.** An example is `[[Judging Your Own Work]]`. [One lesson, written once](page:one-lesson) shows why a class page links to shared pages.

## See the page on the website

1. In Plantoir, select the section and press {{control:previewButton}}. The section's website opens in Plantoir's window.
2. If a preview was already running, choose {{menu:rebuildPreview}}. A preview shows the pages as they were when it was made. A change made since is not in it.

The preview shows only the pages that are published for the section. A class page made with {{menu:addClass}} starts unpublished. Publish it when it is written, and it appears in the preview. [Preview a section](page:preview) has more.

Students see the page after two more things: the page is published for their section, and the section is deployed. [Publishing and deploying](page:publish-and-deploy) explains both.

## If it does not work

- **{{control:openInObsidian}} is greyed.** Obsidian is not installed on this {{machine}}. Install it from [obsidian.md](https://obsidian.md), then press the button again.
- **An offer of add-ons for Obsidian appears.** It may appear the first time you open a course that has diagrams or graphs. See [See diagrams and graphs in Obsidian too](page:obsidian-addons).
- **A change is not in the preview.** Choose {{menu:rebuildPreview}}. {{control:reload}} does not show a change made in Obsidian.
- **The page is not in the preview at all.** It is not published for that section. Publish it, then look again.
