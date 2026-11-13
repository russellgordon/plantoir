---
id: add-section
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Wizard/AddSectionSheet.swift
- mac-app/QuartzTeachers/Models/SectionAdder.swift
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- add section
- add a section
- another class
- second section
- new section
- new block
- same course twice
- section number
description: Add a section to a course when you teach it to another class. The new section starts as a copy of the lowest-numbered one.
---
When you pick up another class of a subject you already teach, add a section to its course. The new section gets a website of its own, and starts as a copy of the section with the lowest number.

## Steps

1. In the sidebar, select the course or one of its sections.
2. Choose {{menu:addSection}} ({{key:addSection}}). A sheet opens. Its title names the course, and a line under the title says which sections the course already has.
3. Check {{control:addSectionSheetSectionNumber}}. Plantoir has filled in a suggested number. Type another, or use the stepper beside the field, so that it matches your timetable.

{{picture:add-section-1}}
alt: The sheet that adds a section, with the Section number field and the Add Section button.

4. Press {{control:addSectionSheetAddSectionButton}}. The new section appears under the course in the sidebar.

## What the new section starts with

The new section is a copy of the lowest-numbered section the course has:

- its class pages and its notes;
- which pages are published and which are hidden;
- its display settings.

Each shared page also gets a date and a published or hidden setting for the new section, copied from the same section.

So the new section's website starts out showing what that section's shows, and you do not need to publish its pages again. Nothing that is already on this Mac is written over.

## What to do next

- **Check the class dates.** The new class probably meets on different days. [Give Plantoir your class dates](page:class-dates) gives the section its own dates, and [Move classes when the schedule changes](page:redate) moves its class pages to them.
- **Hide what this class has not reached.** If the new class is behind the other, hide the classes it has not had. [Show or hide pages for a section](page:publish-pages) has the steps, and [Two sections on different days](page:two-sections) shows the idea.
- **Preview it.** See [Preview a section](page:preview).
- **Deploy it.** The section's first deploy to Cloudflare Pages or Netlify sets up its website's address. See [Your site's address](page:site-address).

## If it does not work

- **{{menu:addSection}} is greyed.** The course is kept for reference, or another change to the course has to finish first.
- **Orange text says the section already exists.** Choose a number the course does not have.
- **Orange text says a folder for that section is already on this Mac.** Plantoir will not write over it, because it may hold work you want to keep. Move that folder aside first, then add the section.
