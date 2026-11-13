---
id: course-settings
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/CourseSettings/CourseSettingsView.swift
- mac-app/QuartzTeachers/Views/CourseSettings/CourseDetailView.swift
- mac-app/QuartzTeachers/Views/CourseSettings/SidebarVisibilityTableView.swift
- mac-app/QuartzTeachers/Models/CourseSettingsWording.swift
- mac-app/QuartzTeachers/Models/SpecialNames.swift
- contracts/shared-rules.json
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- course settings
- settings
- course name
- change the name
- footer
- licence
- license
- language
- sidebar
- hide folder
- save
- revert
- saved
description: Where a course's settings are, what each part of the form holds, and how Save and Revert work.
---
A course's settings are one long form. This page says how to open it, what each part holds, and when a change takes effect.

## Open the settings

1. In the sidebar, select the course itself, not one of its sections. Its settings show in the window.

{{picture:course-settings-1}}
alt: A course's settings at the top of the form, with the Course name field, and the Save button at the bottom of the form.

{{assistant}}
A bar with two tabs shows above the form when Claude Code, Codex or GitHub Copilot is installed on this Mac. The tabs are {{control:courseDetailSettingsTab}} and {{control:courseDetailPlanningTab}}. The settings are on the first.
{{/assistant}}

## The parts of the form

The parts come in this order.

| Part | What it holds |
|---|---|
| {{control:courseSettingsOverallPart}} | {{control:courseSettingsCourseName}}, {{control:languageAndRegion}}, {{control:showPageReadTimeEstimatesToStudents}}, {{control:sidebarFoldersExpandWhenClicking}}, and {{control:unitWordField}} with its {{control:unitWordRename}} button. |
| {{control:deployingPart}} | Where the sections deploy, and {{control:howLateSetting}}. |
| {{control:courseSettingsFooterPart}} | The footer of the website's pages. |
| {{control:courseSettingsPrintingPart}} | What is printed in the corners of a handout: the school's name, the blanks to fill in, and the course's code. |
| {{control:courseSettingsContentStructurePart}} | The lists of folders and files that every section shares, and that each section has for itself. |
| {{control:courseSettingsMarksPart}} | {{control:foldersWhoseWorkCountsForMarks}}, with a link under it to the list of folders Plantoir uses. |
| {{control:courseSettingsSidebarVisibilityPart}} | A table with three columns: {{control:sidebarVisibilityHideColumn}}, {{control:sidebarVisibilityExpandableColumn}} and {{control:sidebarVisibilityFolderOrFileColumn}}. Each folder or file has a row, with a tick box in the first two columns. |
| One part for each section | How that section's website looks, and its {{control:sectionSettingsAdvanced}} fold-down. |

A club has one more part, {{control:courseSettingsClassPagesPart}}, after the first. It shows the words chosen when the club was made, and they cannot be changed there. A club's first part also has a field for its short label.

{{picture:course-settings-2}}
alt: The Content Structure and Marks parts of a course's settings, with the lists of shared folders and the folders whose work counts for marks.

{{picture:course-settings-3}}
alt: The Sidebar Visibility table, with a row for each folder or file and tick boxes under Hide and Expandable.

These pages cover the parts in detail:

- [Choose where a section deploys](page:destinations) and [Schedule a deploy for later](page:schedule-deploy)
- [A handout that prints](page:printing)
- [Shared folders and section folders in Course Settings](page:course-folders)
- [The folders Plantoir treats specially](page:special-folders)
- [Change what units are called](page:unit-word)
- [Change how a section's site looks](page:section-look)

{{assistant}}
{{control:courseSettingsOverallPart}} also holds the two switches for the curriculum map, {{control:includeTheCurriculumCoverageMap}} and {{control:explainTheMapOnThePage}}. The second is greyed unless the first is on.
{{/assistant}}

## What Hide and Expandable do

The two tick boxes in the {{control:courseSettingsSidebarVisibilityPart}} table change the sidebar of the class website, and nothing else.

- **{{control:sidebarVisibilityHideColumn}}** keeps the folder or file out of the website's sidebar. Its pages are still on the website. Students can follow a link to them and can find them by searching, and a published page stays published. A tick here does not keep a page from students. To do that, hide the page: see [Show or hide pages for a section](page:publish-pages).
- **{{control:sidebarVisibilityExpandableColumn}}** makes a folder open in the sidebar, with its pages listed under it. A folder without the tick shows as its name alone, and clicking the name opens the folder's own page.

## Change the course's name

Type the new name in the {{control:courseSettingsCourseName}} field and save. The name is not the code. To change the code, see [Rename or remove a course](page:rename-remove).

## Save or revert

1. Make your changes in the form.
2. Press {{control:courseSettingsSaveButton}} at the bottom of the form, or choose {{menu:saveCourseSettings}} ({{key:saveCourseSettings}}). The words {{control:courseSettingsSavedConfirmation}} show.

To drop changes you have not saved, press {{control:courseSettingsRevertButton}}, or choose {{menu:revertCourseSettings}}. The form goes back to what was last saved.

A saved change reaches students at each section's next deploy.

## Changes that do not wait for Save

Renaming a folder and renaming the unit word both happen at once, when you press the button in their own sheet. {{control:courseSettingsRevertButton}} does not undo them.

## If it does not work

- **A preview does not show a change you made.** A preview uses the settings as they were last saved. Save first. If a preview of the course is open when you save, a notice appears with a {{control:courseSettingsPreviewAgain}} button:
  {{say:shared-rules#specialNames.settingsSavedWhilePreviewing.message}}
- **A deploy went out without a change you made.** A deploy, and a scheduled deploy, also use the settings as last saved, and a notice says so when there are unsaved changes.
- **You saved while the course was being deployed.** That deploy uses the settings from before the save:
  {{say:shared-rules#specialNames.settingsSavedWhilePublishing.message}}
- **A folder you removed here, and made again in Obsidian, is not on the site.** Anything removed in these settings stays off the site until you add it back here. Other new folders and files made in Obsidian are added to the site at the next preview.
