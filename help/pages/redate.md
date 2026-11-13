---
id: redate
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Models/SectionReDatePlanner.swift
- mac-app/QuartzTeachers/Views/Section/SectionVerbSheet.swift
- mac-app/QuartzTeachers/Views/Section/SectionDetailVerbs.swift
- contracts/class-planning.json
- contracts/assist-wording.json
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- snow day
- storm day
- PA day
- cancelled class
- shift classes
- move classes
- re-date
- redate
- reschedule
- new semester
- new dates
- schedule changed
description: Re-date Classes moves every class in a section onto the class dates on file, in order, after showing a plan.
---
Re-date Classes moves the classes of a section onto the class dates Plantoir has on file for it. Use it when the days a section meets have changed, as they do after a snow day.

## What it does

Re-date Classes works on every class in the section. You do not choose classes or a date. The first class takes the first date on file, the second class takes the second date, and so on down the list. Unit and day numbers are not used, and old dates are not matched to new ones.

Other pages follow the classes:

- **A page that a class links to** takes that class's new day. If several classes use the page, the earliest one decides.
- **The pages the section uses all year**, which are the ones its Key Links lists, take the first day of class.
- **Curriculum pages** are not moved.
- **A class left over when the dates run out** is put into draft. It is hidden until you publish it again.

So the list of class dates must be right before you begin.

## Steps

1. In the sidebar, select the section.
2. Choose {{menu:classDates}} and give the section's new list of class days. The new list replaces the old one, and the plan there says what it replaces. See [Give Plantoir your class dates](page:class-dates).
3. Choose {{menu:reDateClasses}} from the menu bar. A sheet opens, works for a moment, and then shows the plan.

{{picture:redate-1}}
alt: The Re-date Classes sheet showing its plan, with the Re-date button.

4. Read the plan before you agree.
5. Press {{control:reDateButton}}. Plantoir saves a copy of the course first, and then moves the pages. To change nothing, press {{control:cancel}} instead.
6. Read the answer and press {{control:ok}}. It counts the classes that were re-dated and, separately, the pages they use.
7. Preview the section and look it over. Then deploy it. Students see no change until the section is deployed.

If the section's front page no longer shows the newest class students can see, Plantoir points it there again.

## To add a class, not move the dates

Re-date Classes does not make a new class. To put a new class in front of ones that are already planned, use {{menu:makeRoomForClasses}}. See [Make room for a class](page:make-room).

## A course copied from last year

The same command moves a course you taught before onto this year's dates. Give the section this year's class dates, then re-date. [Get ready for the start of the year](page:start-of-year) hides the later classes from a new group of students.

## Take it back

Choose {{menu:undoLastChange}}. Re-dating is one change, and it is put back as one.

- This works while re-dating is still the last change made from the Section menu in this window.
- A page you have edited since is left alone.
- Undo does not change a website that is already deployed. Deploy again when you want it to match.

The copy saved before the change is in Plantoir's list of backups. See [Back up a course and restore it](page:backups).

## If it does not work

- **The class dates sheet opens first.** The section has no dates on file. The sheet says:
  {{say:assist-wording#wording.datesToReDate}}
  Give the dates, and Re-date Classes carries on.
- **The answer says every page is already on its day.** Nothing needed to move. Check that you gave the new dates first.
- **Only the pages classes use were re-dated.** Every class was already on its day.
- **{{menu:reDateClasses}} is greyed.** The course is kept for reference, or the section is busy with a deploy, a backup or another command from the Section menu.
