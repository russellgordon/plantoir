---
id: one-lesson
checked: 2.0.0
covers:
- support/example_course/EXC2O/Style/How This Site Is Organised.md
- support/example_course/EXC2O/course_config.json
- scripts/build_site.py
keywords:
- write once
- reuse a lesson
- reuse
- shared pages
- reference page
- concept page
- linked pages
- links
- backlinks
- agenda
- duplicate
- DUPLICATE ME
- template
description: A class page links to shared pages that are written once, and each shared page lists the classes that used it.
---
In a Plantoir course, each idea is written on one shared page, and class pages link to it. This page shows that in the example course, and then says how to start a shared page of your own.

## See it in the example course

1. In Obsidian, open `section1`, then All Classes, then Unit 1, Day 13. The page has two headings: Agenda, and Things to do before our next class.
2. Read the agenda. It names other pages, each in double square brackets. One is `[[Judging Your Own Work]]`. That is a link to a shared page, which is kept in the shared folder Portfolios. The class page says what the class did, and the shared page holds the lesson.

{{picture:one-lesson-1}}
alt: A class page in Obsidian beside a shared page it links to, with the Agenda heading and one link marked.

3. In Plantoir, preview Section 1 and open a page from Concepts on the website. The page carries a list of the pages that link to it. These are its backlinks, and they show every class that used the page.
4. Open a class page on the website. It has no such list. Backlinks are left off class pages and the front page.

{{picture:one-lesson-2}}
alt: A concept page on a section's website with its backlinks, the list of the classes that link to it.

## What this gives you

- **A fix is made once.** Correct a mistake on the shared page, and every section's website has the correction the next time it is previewed. Students see it after each section is next deployed.
- **A lesson can be used again.** A later class page links to the same shared page, and the page is not written twice.
- **Students can find when an idea was taught.** The backlinks on a shared page lead to every class that used it.

## Start a new shared page

Seven of the example's shared folders hold a page named `_DUPLICATE ME`: Concepts, Discussions, Exercises, Investigations, Portfolios, Tasks and Tutorials. It is a starting point for a new page in that folder.

1. In Obsidian, right-click `_DUPLICATE ME` in the folder where the new page belongs, and choose Duplicate.
2. Rename the copy.
3. Open the copy and change its title.

`_DUPLICATE ME` is not published for either section, so your copy starts hidden as well. Publish it for each section when it is ready: see [Show or hide pages for a section](page:publish-pages).

There is no `_DUPLICATE ME` page in All Classes. A new class page is made in Plantoir, with {{menu:addNextClass}}. See [Add the next class](page:add-next-class).
