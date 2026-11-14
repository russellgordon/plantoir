---
id: make-room
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Models/ClassInsertionPlanner.swift
- mac-app/QuartzTeachers/Views/Section/SectionVerbSheet.swift
- mac-app/QuartzTeachers/Views/Section/SectionDetailVerbs.swift
- contracts/class-planning.json
- contracts/assist-wording.json
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- make room
- insert a class
- add a class in the middle
- extra class
- extra day
- new class before
- renumber
- push classes back
- move classes later
description: Make Room for Classes puts new, blank class pages in front of a class you choose, and moves that class and every later one along.
---
Make Room for Classes puts one or more new class pages in front of a class that is already planned. That class and every later one move along to later class days.

## Steps

1. In the sidebar, select the section.
2. Choose {{menu:makeRoomForClasses}} from the menu bar. A sheet opens and says:
   {{say:assist-wording#wording.menuMakeRoomAt}}
3. Choose the class from the pop-up menu. It lists the section's numbered classes, and starts on the first one.
4. Set how many classes to make room for, from 1 to 10.

{{picture:make-room-1}}
alt: The Make Room for Classes sheet, with the pop-up menu of classes, the number of classes to make room for, and the Continue button.

5. Press {{control:continueButton}}. The sheet shows the plan in words. It says how many new classes go in and where, named the way your pages are named.
6. Read the plan. It includes this sentence:
   {{say:assist-wording#wording.makingRoomCannotBeUndoneFromTheMenu}}

{{picture:make-room-2}}
alt: The plan for making room, with its sentence about Undo Last Change and the Make Room button.

7. Press {{control:makeRoomButton}}. Plantoir saves a copy of the course first, and then makes the room. To change nothing, press {{control:cancel}} instead.
8. Read the answer and press {{control:ok}}. It says how many pages were renamed, how many were moved, and how many links were updated.
9. Open the new pages in Obsidian and write them. Preview the section and look it over before you deploy.

## What moves, and what is made

- **Later days of the same unit are renamed.** Make room for one class at Day 3, and the old Day 3 becomes Day 4. The old Day 4 becomes Day 5, and so on to the end of that unit.
- **Every class from that point on moves to a later class day.** This includes the classes of later units. They keep their names: the first day of the next unit is still its Day 1.
- **Links follow the pages.** A link that pointed at a renamed page is changed to point at it under its new name.
- **The new class pages are blank and unpublished.** Plantoir makes them in the room it opened. Publish each one when it is written.
- **A page named another way is passed over.** A page such as Field Trip keeps its name and its date.

Students see none of this until the section is next deployed.

## The way back is the backup

{{menu:undoLastChange}} does not take this back, because other classes move. The copy of the course that Plantoir saves before it makes room is in its list of backups. Restore that copy to put the course back as it was. See [Back up a course and restore it](page:backups).

## If it does not work

- **The class dates sheet opens first.** The section has no dates on file. The sheet says:
  {{say:assist-wording#wording.datesToMakeRoom}}
  Give the dates, and Make Room for Classes carries on. See [Give Plantoir your class dates](page:class-dates).
- **{{menu:makeRoomForClasses}} is greyed.** The course is kept for reference, or the section is busy with a deploy, a backup or another command from the Section menu.
- **You wanted to move dates, not add a class.** Use {{menu:reDateClasses}}. See [Move classes when the schedule changes](page:redate).
- **You wanted a class at the end.** Use {{menu:addClass}}. See [Add a class](page:add-next-class).
