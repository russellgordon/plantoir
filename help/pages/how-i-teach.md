---
id: how-i-teach
checked: 2.0.0
covers:
- contracts/shared-rules.json
- contracts/assist-wording.json
- mac-app/QuartzTeachers/Views/CourseSettings/CourseSettingsView.swift
keywords:
- How I Teach
- teaching style
- how I teach
- assistant
- Claude
- Claude Code
- Codex
- private page
- never on the website
- notes for an assistant
description: A course's How I Teach page is your own account of how you teach it. Assistants read it, and it is never on a website.
---
Each course can have one page named How I Teach. It is your own account of how you teach that course. An assistant you open through Plantoir is asked to read it and keep to it. The page is never on a website.

## Make the page, or open it

1. In the sidebar, select the course itself. Its settings show in the window.
2. Find the part named {{control:contentStructurePart}}, and in it the row {{control:howITeachRow}}.
3. Press {{control:howITeachCreateAndOpen}}. A new page is made, with nothing written on it, and opens in Obsidian. When the course already has the page, the button is named {{control:howITeachOpen}}, and it opens the page you have.

{{picture:how-i-teach-1}}
alt: The Content Structure part of a course's settings, with the How I Teach page row and its Create and Open button.

Under the row, Plantoir says:

{{say:shared-rules#howITeachPage.settingsButton.caption}}

[Change a course's settings](page:course-settings) says more about the form.

## Its name and its place

The page is the one named exactly How I Teach, at the top of the course folder, beside the course's other top pages. Capital letters do not matter: a page named how i teach is the same page.

Any other name is an ordinary page. A page named `How I Teach 1` or `How-I-Teach` goes on the website like any other page.

## What to write

Write how you teach this course, in your own words. A page with nothing written on it counts as not written.

An assistant that writes the page for you may write 8000 characters at most. A page you write yourself may be longer. An assistant then reads its first 8000 characters, and is told where the rest is.

## Who reads it

- **Claude Code, Codex and GitHub Copilot**, when you open them through Plantoir, are asked to read the page and keep to it. See [Revise a course with Claude or Codex](page:revise-with).
- Any of them may offer to draft the page for you from the course's own pages. A draft is saved only once you agree.
- **The assistant that runs on this {{machine}}** does not use the page.

## It is never on a website

Plantoir keeps the page off every website it makes for the course, at every preview and every deploy. While it makes a website for a course that has the page, it says:

{{say:shared-rules#howITeachPage.keptOffTheWebsiteLine}}

{{menu:publishPages}} never lists the page.

A page at the top of the course may have a name that begins the same way but is not exactly How I Teach. Plantoir then says that the page will be on the website like any other.

To show students something like it, write a page with another name.

## If it does not work

- **The page could not be made.** Plantoir says so and gives the reason.
- **Students can see a page you meant to keep to yourself.** Check that it is named exactly How I Teach. Check too that it sits at the top of the course folder, not in a folder inside it.
