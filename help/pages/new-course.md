---
id: new-course
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Wizard/NewCourseWizardView.swift
- mac-app/QuartzTeachers/Models/WizardWording.swift
- mac-app/QuartzTeachers/Models/GradedFolderWording.swift
- mac-app/QuartzTeachers/Models/CourseSettingsWording.swift
- contracts/app-rules.json
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- new course
- add a course
- create course
- make a course
- course code
- course name
- province
- Ontario
- British Columbia
- ready-made pages
- example content
- pre-populate
- skeleton
- starting content
- curriculum pages
description: What each part of the New Course or Club sheet asks, from the province and the course code to Create Course.
---
A new course is made in one sheet, {{control:newCourseOrClub}}. This page goes down the sheet part by part and says what each one asks.

## Open the sheet

1. Choose {{menu:newCourse}} ({{key:newCourse}}). The sheet opens.

At its top is an offer to add the example course. [Look around with the example course](page:example-course) covers it.

## Basics

Fill in {{control:newCourseSheetBasicsPart}} first. Everything below it stays greyed until a course code is chosen.

- **{{control:newCourseSheetProvince}}**: {{control:newCourseSheetProvinceOntario}} or {{control:newCourseSheetProvinceBritishColumbia}}.
- **{{control:newCourseSheetCourseCode}}**: type a code, or type what the subject is called. The field suggests codes as you type.
- **{{control:newCourseSheetCourseName}}**: for example Chemistry. For a code Plantoir knows, two buttons offer a short name and a formal one.
- **{{control:newCourseSheetThisIsAClub}}**: see [Make a club](page:club).
- **{{control:newCourseSheetTimetableSectionNumbers}}**: the numbers of the sections you teach, with commas between them, such as 1,3.
- **{{control:newCourseSheetKeepThisCourseForReference}}**: shown for a code that has a ready-made course. With it turned on, the sheet has no {{control:newCourseSheetDeployingPart}} part, and its last button is {{control:newCourseSheetCreateReferenceCourseButton}}. See [Bring in last year's courses](page:import-for-reference).

{{picture:new-course-1}}
alt: The New Course or Club sheet with Basics filled in: the province, the course code and the timetable section numbers.

## Starting Content

What {{control:newCourseSheetStartingContentPart}} offers depends on the code.

- **A code with a ready-made course** offers {{control:newCourseSheetPrePopulateWithExampleContent}}. You get working pages written for that subject, to keep, edit or delete. The example content also chooses the folders and files.

{{picture:new-course-2}}
alt: Starting Content for a code that has a ready-made course, with the switch that fills the course with example content.

- **A code with no ready-made course** offers a switch that begins Start from and names the subject, such as Start from a science skeleton. It gives folders that suit the subject, four units of class pages to rename, and a page explaining what the site can do. It also gives placeholders that say what belongs where. The same switch is offered when you turn the ready-made course off.

{{picture:new-course-3}}
alt: Starting Content for a code with no ready-made course, with the switch that starts from a subject's skeleton.

- **A code with neither** starts with empty folders.
- **A code that has curriculum pages** offers a switch to include them, with every expectation as a page of its own. Two more switches add a curriculum map and an explanation on the map's page. The map shows every expectation, coloured by how many pages address it.

{{assistant}}
The two switches for the map are {{control:includeTheCurriculumCoverageMap}} and {{control:explainTheMapOnThePage}}.
{{/assistant}}

## Appearance and Behaviour

{{control:newCourseSheetAppearancePart}} sets how the websites look: {{control:sectionSettingsHeaderEmoji}}, {{control:sectionSettingsColourScheme}}, {{control:sectionSettingsHeaderAndBodyFonts}}, {{control:sectionSettingsCodeFont}}, {{control:sectionSettingsShowSectionMarker}} and {{control:sectionSettingsShowTheGrade}}. The choice here is applied to every section. Each section can be changed afterwards: see [Change how a section's site looks](page:section-look).

{{control:newCourseSheetBehaviourPart}} holds two choices:

- {{control:sidebarFoldersExpandWhenClicking}}: either {{control:sidebarFoldersExpandChevronOrFolderName}} or {{control:sidebarFoldersExpandChevronOnly}}.
- {{control:showPageReadTimeEstimatesToStudents}}.

## Units

{{control:unitWordField}} sets the word in the names of class pages. Leave it empty for Unit. Some teachers say Module or Thread. You can change the word later: see [Change what units are called](page:unit-word).

## Deploying

{{control:newCourseSheetDeployingPart}} sets where the sections deploy. Cloudflare Pages is the usual choice, and you can change it at any time in the course's settings. [Choose where a section deploys](page:destinations) explains the three places.

## Structure

The sheet says of {{control:newCourseSheetStructurePart}} that the defaults are fine for most courses. When you take a ready-made course, the example content chooses this part.

- **{{control:newCourseSheetFoldersAndFiles}}** folds down to four lists: the folders and files every section shares, and the folders and files each section has for itself. A fifth list, {{control:curriculumFolders}}, shows when the code has a folder of curriculum expectations to offer. See [Shared folders and section folders in Course Settings](page:course-folders).
- **{{control:foldersWhoseWorkCountsForMarks}}** names the folders that hold marked work. See [The folders Plantoir treats specially](page:special-folders).
- **{{control:newCourseSheetUseLCSSpecificTerminology}}** is an option for one school. It uses that school's own terms, with pages named Grove Time and SIC Drop-In Sessions in place of Extra Help. It also adds a College Board Curriculum folder.

## Footer and Advanced

{{control:newCourseSheetFooterPart}} is a box for the footer of the website's pages, written as HTML. {{control:newCourseSheetAdvanced}} folds down to {{control:languageAndRegion}}, which is used for dates and for the words on your website's own pages.

## Create the course

1. Press {{control:newCourseSheetCreateCourse}}. The sheet shows its progress while the course is made.
2. Press {{control:wizardClose}}. The course is now in the sidebar, with its sections under it.

Many of these choices can be changed later in the course's settings. See [Change a course's settings](page:course-settings).

## If it does not work

- **{{menu:newCourse}} is greyed.** No working folder is open, or the folder is still being made ready.
- **Orange text shows under the course code.** The code cannot be used, and the text says why.
- **Red text shows beside {{control:newCourseSheetCreateCourse}}.** Something in the form needs attention, and the text says what. One example: the course deploys to a folder on this {{machine}} and no folder is chosen yet.
