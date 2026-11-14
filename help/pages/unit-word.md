---
id: unit-word
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/CourseSettings/UnitWordRenameSheet.swift
- mac-app/QuartzTeachers/Models/UnitWordRenameWording.swift
- mac-app/QuartzTeachers/Views/CourseSettings/CourseSettingsView.swift
- contracts/shared-rules.json
- contracts/class-planning.json
keywords:
- unit
- units
- unit word
- module
- modules
- thread
- threads
- rename unit
- rename units
- what units are called
- class page names
description: Change the word a course uses for a unit, such as Module or Thread. Plantoir renames every class page and the links to them.
---
Class pages are named with the course's word for a unit, as in Unit 1, Day 1. If your school says Module or Thread, you can change the word, and Plantoir renames the class pages to match.

## Steps

1. In the sidebar, select the course. Its settings show.
2. In the first part of the form, the row {{control:unitWordField}} shows the word the course uses now. Press the {{control:unitWordRename}} button beside it. A sheet opens, with the present word in its title.
3. Type the new word. The grey word in an empty field is only a prompt, and an empty field is refused. To go back to Unit, type Unit.
4. Wait a moment while Plantoir looks over the pages. The sheet then says how many class pages would be renamed, in which sections, and how many links would be changed to match.

{{picture:unit-word-1}}
alt: The sheet that renames the unit word, saying how many class pages and links would change, with the Rename button.

5. Press {{control:unitWordRenameSheetRenameButton}}. Plantoir saves a backup of the whole course first, then renames the pages.

The sheet explains what the rename does:

{{say:shared-rules#specialNames.renameUnitWord.explanation}}

When it has finished, Plantoir says what the word is now, and how many pages and links it changed.

## What is renamed and what is not

- **Every numbered class page, in every section.** With the word Module, Unit 1, Day 1 becomes Module 1, Day 1, and so on.
- **Links to those pages.** They follow the new names, including links that show other words.
- **New class pages.** They are named with the new word from now on.
- **Not the other pages.** A page such as Field Trip, and each section's front page, keep their names.
- **Not your sentences.** The sheet says:
  {{say:shared-rules#specialNames.renameUnitWord.proseIsLeftAlone}}

## What students see

Students see no change until a section is next deployed. Plantoir reminds you when the rename is done:

{{say:shared-rules#specialNames.renameUnitWord.donePublish}}

## Change it back

Rename the word again, back to what it was. The backup Plantoir saved first is a last resort. It is listed with the course's other backups: see [Back up a course and restore it](page:backups).

## If it does not work

- **{{control:unitWordRename}} is greyed.** The course numbers its pages one after another, as a club does. Its word was chosen when it was made and cannot be renamed.
- **The course is being previewed or deployed.** Stop that first, then rename.
- **A page is in the way.** A section already has a page with one of the new names, and nothing is renamed. Move or rename that page first.
- **A page could not be read.** Nothing is renamed. If the course is kept in iCloud Drive, wait for it to finish downloading and try again.
- **The rename stopped part way.** Plantoir recognises this. Open the sheet again, type the same new word, and press {{control:unitWordRenameSheetRenameButton}} to finish.
- **The word is refused.** A word with a digit or a comma in it cannot be used. Neither can an empty field, or the word the course already uses.
