---
id: shared-and-section
checked: 2.0.0
covers:
- support/example_course/EXC2O/course_config.json
- scripts/build_site.py
keywords:
- shared pages
- shared folders
- section pages
- section folder
- section1
- section2
- two sections
- two classes
- same course two blocks
- publishForSection1
- replace a shared page
- Key Links
description: Which pages every section's website gets, which belong to one section, and how a section's page replaces a shared one.
---
A course holds two kinds of page. Shared pages go into every section's website. Section pages belong to one section and go into that section's website only.

The examples on this page are from the example course. [Tour the example course](page:tour-example-course) shows where to find them.

## Shared pages

Shared pages are kept in folders at the top of the course. The example has ten such folders: Concepts, Curriculum, Discussions, Exercises, Investigations, Portfolios, Setup, Style, Tasks and Tutorials. It also has two shared pages outside any folder, Learning Goals and Help Sessions.

You write a shared page once. Every section's website gets it.

## Section pages

Each section has a folder of its own, beside the shared folders: `section1` for Section 1, `section2` for Section 2. In the example, a section's folder holds:

- the section's front page;
- the folder All Classes, with one page for each class;
- the pages Key Links, Private Notes and Scratch Page.

Each section has its own copy of these. Key Links is an example. Both sections start with the same list of links, but the two lists are separate pages. You can change one section's list without touching the other's.

{{picture:shared-and-section-1}}
alt: Obsidian's file list with the section1 folder open beside the shared folders, showing its front page, All Classes and Key Links.

## One shared page, published for some sections

A shared page is one page, but each section decides for itself whether its students see it. The page's settings, at the top of the page, carry one line for each section:

```text wrap
publishForSection1: true
publishForSection2: true
```

When Section 1's website is made, only the line for Section 1 is read. Change a line to `false` and the page is hidden in that section and still shown in the other.

A section page has no need of a line for each section, because each section has its own copy. Its settings carry the single line `publish: true`.

{{picture:shared-and-section-2}}
alt: The settings at the top of a shared page in Obsidian, with one publish line for Section 1 and one for Section 2.

You do not have to type these lines yourself. [Show or hide pages for a section](page:publish-pages) changes them from Plantoir's menus, and [Which classes see a page](page:page-settings) has the rules for typing them.

## When a section's page replaces a shared one

Sometimes one section needs its own version of a shared page. Make a folder inside that section's folder, with the same name as the shared folder. Put a page in it with the same name as the shared page. On that section's website, the section's page takes the place of the shared one. Every other section still gets the shared page.

For example, make a folder named Setup inside `section2`. Put a page in it with the same name as a page in the shared Setup folder. On Section 2's website only, your page takes the place of that shared page.

Plantoir notices such a page by itself when the website is next made. The example course has no page of this kind.
