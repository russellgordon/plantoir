---
id: second-curriculum
checked: 2.0.0
covers:
- contracts/shared-rules.json
- contracts/file-formats.json
- mac-app/QuartzTeachers/Models/SpecialNames.swift
- mac-app/QuartzTeachers/Views/CourseSettings/CourseSettingsView.swift
keywords:
- second curriculum
- two curriculums
- AP
- Advanced Placement
- College Board
- IB
- International Baccalaureate
- framework
- curriculum folders
- second map
- expectations
description: Give a course a second set of curriculum expectations, such as AP beside the provincial curriculum, each with its own map on the class website.
---
A course can follow two sets of expectations at once, such as a provincial curriculum and an AP framework. Each set is a folder of pages, and each folder gets a map of its own on the class website. This page says how to add the second.

## Make the folder and its pages

1. In Obsidian, make a folder for the framework among the course's shared folders. Put the word Curriculum in its name, as in College Board Curriculum. Plantoir offers a folder as a curriculum folder only when its name holds that word.
2. In that folder, make one page for each expectation. Name each page by the expectation's code and nothing else.

Plantoir knows a page is an expectation by its name. Codes shaped like `A1.1`, `1.A` and `CRD-1.A` are recognised.

## Tick the folder in the course's settings

1. Preview a section of the course. Plantoir learns of a folder made in Obsidian when the website is next made. If a preview is already running, choose {{menu:rebuildPreview}}.
2. In Plantoir's sidebar, select the course. Its settings appear.
3. Find the part named {{control:contentStructurePart}}.
4. Under {{control:curriculumFolders}}, tick the new folder. Leave the first folder ticked. The list is shown only when the course has two or more folders to choose from. A course that had one curriculum folder did not show it before.
5. Press {{control:saveCourseSettings}}.

{{picture:second-curriculum-1}}
alt: The Curriculum folders list in a course's settings, with two folders ticked.

## See the two maps

Preview the section again, or choose {{menu:rebuildPreview}} if its preview is still running. Each ticked folder has a map of its own on the website.

{{assistant}}
The first folder's map keeps its title, Curriculum Coverage. Each other map is titled with its folder's name and the word Coverage. The list in the course's settings carries this caption:

{{say:shared-rules#specialNames.curriculumFoldersOffer.caption}}
{{/assistant}}

{{picture:second-curriculum-2}}
alt: Two curriculum maps on the class website, one for each ticked folder.

## Link lessons to the new expectations

A lesson is linked to an expectation of the second set in the same way as the first. The lesson's page shows the expectation's page by its name. A lesson may link to expectations from both folders.

{{assistant}}
[Curriculum expectations and the coverage map](page:coverage) has the steps, and says which pages count.
{{/assistant}}

## If it does not work

- **The course's settings have no {{control:curriculumFolders}} list.** The list is shown only when at least two folders can be chosen. Check that the new folder's name holds the word Curriculum, in any capitals. Check that you previewed a section after making the folder. Then select the course again.
- **The last ticked folder cannot be unticked.** While the course has a map, one curriculum folder stays ticked. Tick another folder first, then untick this one.
- **An expectation is not on the new map.** Check that its page is named by the expectation's code, and that the page is in the ticked folder.
