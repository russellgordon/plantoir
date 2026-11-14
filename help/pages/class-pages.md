---
id: class-pages
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Models/UnitWordRenameWording.swift
- mac-app/QuartzTeachers/Views/Wizard/NewCourseWizardView.swift
- mac-app/QuartzTeachers/Models/SectionIndexPointer.swift
- mac-app/QuartzTeachers/Models/Assist/AssistPublishPlan.swift
- contracts/class-planning.json
- support/example_course/EXC2O/section1/index.md
keywords:
- class page
- class pages
- day pages
- lesson pages
- Unit 1 Day 1
- unit
- module
- thread
- All Classes
- most recent class
- front page
- home page
- naming
- dates
description: How class pages are named and dated, where they are kept, and how a section's front page shows the most recent class.
---
A class page is the page for one class of one section. It holds that day's agenda and what to do before the next class. This page says where class pages are kept, how they are named and dated, and how a section's front page shows the newest one.

## Where class pages are kept

Each section's folder holds a folder named All Classes. It has one page for each class that section has.

{{picture:class-pages-1}}
alt: The All Classes folder of one section in Obsidian, its class pages listed in order by unit and day.

## How class pages are named

Class pages are named by unit and by day: Unit 1, Day 1, then Unit 1, Day 2, and so on. The days start again at Day 1 in each new unit.

The first word of the name is yours to choose. When you make a new course, the {{control:newCourseOrClub}} sheet asks for it, in the field {{control:unitWordField}} Leave the field empty and the word is Unit. Some teachers say Module or Thread, and their pages are named Module 1, Day 1 or Thread 1, Day 1.

{{picture:class-pages-2}}
alt: The New Course or Club sheet, at the field that asks what you call a unit.

The word is chosen when the course is made. It can be changed later from the course's settings, where {{control:unitWordRename}} sits beside the same question. See [Change what units are called](page:unit-word).

Two kinds of page are named differently:

- **A page you name another way**, such as Field Trip or Exam Review, is not numbered. When Plantoir renumbers classes it passes over that page, and the page keeps its own date.
- **A club's pages** carry one number each, such as Week 1 and Week 2. See [Make a club](page:club).

## Each section has its own copy, with its own date

A class is taught to each section on its own day. So each section has its own copy of every class page, and each copy carries that section's date.

In the example, Section 2 meets one school day after Section 1. Unit 1, Day 13 is dated 24 September 2026 in Section 1 and 25 September 2026 in Section 2. Across a weekend the gap is longer. Unit 3, Day 5 is on Friday 30 October in Section 1 and on Monday 2 November in Section 2.

## Making the next class page

Choose {{menu:addClass}}. A sheet asks how the class should be added. It can be the next class in the unit under way, the first class of a new unit, or a copy of an earlier class. Plantoir then makes the page in the selected section, named and dated. [Add a class](page:add-next-class) has the steps.

## Most Recent Class on the front page

A section's front page opens with the heading Most Recent Class and shows one class page under it. Students who open the site see the newest class first.

Plantoir keeps the front page up to date when you publish or hide pages from its menus:

- {{menu:publishPages}}
- {{menu:hidePages}}
- {{menu:publishClassForDate}}

Each time, it sets the front page to show the newest class that the section's students can see. The front page's date follows.

If you publish a class by changing its settings in Obsidian instead, the front page is not changed. The next time you preview, Plantoir may ask whether to show today's class on the front page. Press {{control:showOnFrontPage}} to change it, or {{control:notToday}} to leave it.

{{picture:class-pages-3}}
alt: The front page of a section's website, where the heading Most Recent Class is followed by the newest class students can see.

A club's front page uses the heading Most Recent Meeting.
