---
id: organised
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Models/WorkspaceModel.swift
- mac-app/QuartzTeachers/Views/SidebarView.swift
- mac-app/QuartzTeachers/Views/WorkspacePickerView.swift
keywords:
- working folder
- courses folder
- course
- courses
- section
- sections
- sidebar
- organised
- organized
- how it works
- Obsidian
description: What the working folder, a course, a section and the sidebar are, and how they fit together.
---
Plantoir uses four words all through Help: working folder, course, section and sidebar. This page says what each one is and how they fit together.

## The working folder

The working folder is the folder you chose when you first opened Plantoir.

It holds a folder named `courses`, and each of your courses is one folder inside that. Plantoir also keeps a few files of its own in the working folder.

{{picture:organised-2}}
alt: The courses folder open in Finder, with one folder inside it for each course.

To work in a different folder, use {{menu:openWorkingFolder}} as [Choose or change the working folder](page:working-folder) describes.

## A course

A course is one folder of pages. It holds everything you write for that course, for every class you teach it to.

A course has two kinds of page:

- **Shared pages** are written once, and every section's website gets them.
- **Section pages** belong to one section. Each section has a folder of its own for them, and that is where its class pages are kept.

[Shared pages and section pages](page:shared-and-section) explains the two kinds.

## A section

A section is one class you teach the course to. If you teach the same course to two classes, the course has two sections.

Each section gets a website of its own. On Cloudflare Pages or Netlify, each section's site has its own address. In a folder on this {{machine}}, each section's site has its own folder, named `section1`, `section2` and so on. [Your site's address](page:site-address) says how an address is made.

## The sidebar

The sidebar, at the left of Plantoir's window, lists the courses in your working folder. Under each course are its sections, as rows named Section 1, Section 2 and so on.

Courses you keep for reference sit apart, on a shelf named {{control:referenceCourses}}. See [Keep a copy of a course for reference](page:keep-for-reference).

{{picture:organised-1}}
alt: Plantoir's main window, with the sidebar listing two courses, the sections under each, and the Reference Courses shelf.

## Where the writing happens

You write your pages in Obsidian. Plantoir opens a course there for you, and Obsidian shows the whole course folder.

Plantoir does the rest. It previews a section, which shows you that section's website on this {{machine}}. It deploys a section, which sends that section's website to where students read it.

- [Write a class page in Obsidian](page:write-in-obsidian)
- [Preview a section](page:preview)
- [Deploy a section](page:deploy)

Before students see a page, it must also be published for their section. [Publishing and deploying](page:publish-and-deploy) explains the difference between the two.
