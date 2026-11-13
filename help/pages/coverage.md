---
id: coverage
checked: 2.0.0
covers:
- contracts/shared-rules.json
- mac-app/QuartzTeachers/Views/Section/CoverageTabView.swift
- mac-app/QuartzTeachers/Views/CourseSettings/CourseSettingsView.swift
- scripts/build_site.py
keywords:
- coverage
- coverage map
- curriculum
- curriculum expectations
- expectations
- map
- Curriculum connection
- Make the Map
- Make the Map Again
- which expectations
- strands
description: Link lessons to the curriculum expectations they address, then read the map of them on the class website and on the section's Coverage tab.
---
A course that has a page for each curriculum expectation can show which expectations its lessons address. The result is a map, on the class website and on the section's {{control:coverageTab}} tab in Plantoir. This page says how to link a lesson to its expectations and how to read the map.

## What the course needs

- **A page for each expectation**, kept in the course's curriculum folder. A course made with its curriculum pages included has them.
- **The map switched on**, for a map on the class website. Select the course in Plantoir's sidebar and look for {{control:includeCoverageMap}} in its settings. The map is then a page of the website, linked from Key Links and kept out of the sidebar.

## Link a lesson to its expectations

1. In Obsidian, open the lesson's page.
2. Add a heading named Curriculum connection.
3. Under it, show each expectation the lesson addresses, by the name of its page:

```text wrap
## Curriculum connection

![[D2.1]]
```

In the example course, the page Testing Conductivity in the Investigations folder is written this way.

Showing the expectation's page this way is what counts. An expectation's code typed as plain words in a lesson counts for nothing.

The Curriculum connection part of a page is never printed.

## Which pages count

A page counts when the course teaches it:

- a class page;
- a page that a class page links to;
- a page that one of those pages links to.

A page in a folder that counts for marks is counted as assessed work. The folders that count for marks are set in the course's settings, under Marks.

## The map on the class website

Preview or deploy the section. The map is made with the website each time, and it counts only the pages that are published for that section.

{{picture:coverage-2}}
alt: The curriculum map page on the class website, with each expectation coloured by how many pages address it.

## The Coverage tab

1. In Plantoir's sidebar, select the section.
2. Click {{control:coverageTab}} in the section's tabs, beside {{control:websiteTab}} and {{control:problemsTab}}.

The tab is there whenever the course's curriculum folder holds an expectation page, whether or not the website's map is switched on. It needs no assistant.

The tab's map has the heading {{control:coverageHeading}}, and it counts hidden pages as well as published ones. It shows what the course would cover once every page is published. A line under the heading says how many of the pages it counted are ones students cannot see yet.

{{picture:coverage-1}}
alt: A section's Coverage tab with its map, and the Make the Map Again button under it.

Under the map, Plantoir says when the map was made and whether pages have changed since. Click an expectation's code to open its page in Obsidian.

## Make the map again

The map is made each time the section is previewed or deployed. To make it without leaving the tab:

1. Press {{control:makeTheMap}}. When the section already has a map, the button is named {{control:makeTheMapAgain}}.
2. Wait while Plantoir makes the section's website again. If the section's preview is open, the preview starts again when the work is done.

## If it does not work

- **The tab says {{control:coverageEmptyTitle}}.** The section has not been previewed or deployed yet. Press {{control:makeTheMap}}.
- **The tab says this:**
  {{say:shared-rules#coverageTab.tab.words.emptyNoCurriculum}}
- **The tab says this:**
  {{say:shared-rules#coverageTab.tab.words.emptyOtherVersion}}
- **There is no {{control:coverageTab}} tab.** The course's curriculum folder holds no expectation page.
- **A lesson is missing from the map.** Check that the lesson links to the expectation's page, and that a class page leads to the lesson.
- **The tab says the section is being deployed, or that another program is working on the course.** Wait for that to finish.
