---
id: school-year
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Wizard/SetSchoolYearSheet.swift
- mac-app/QuartzTeachers/Models/SchoolYear.swift
- mac-app/QuartzTeachers/Models/ReferenceWording.swift
- mac-app/QuartzTeachers/Models/SubjectMenuRules.swift
keywords:
- school year
- set school year
- reference year
- which year
- year taught
- reference course
- shelf
- greyed
description: Set School Year says which school year a reference course was taught in, and so where it sits on the Reference Courses shelf.
---
Set School Year says which school year a course kept for reference was taught in. The course is then filed under that year on the {{control:referenceCourses}} shelf.

The command is for reference courses only. It changes nothing about a course you teach, and it is greyed when such a course is selected.

## Steps

1. In the sidebar, select a course on the {{control:referenceCourses}} shelf.
2. Choose {{menu:courseSetSchoolYear}}. A sheet opens and asks which school year the course was taught in.
3. Choose the year from the {{control:setSchoolYearSheetSchoolYearPopUp}} pop-up. Choose {{control:referenceShelfSchoolYearOther}} when no year fits.

{{picture:school-year-1}}
alt: The sheet that asks which school year a reference course was taught in, with the School year pop-up and the Set School Year button marked.

4. Press {{control:setSchoolYearSheetSetSchoolYearButton}}. The course moves to the group for that year on the shelf.

## The years you can choose

The pop-up lists the school years newest first. It runs from the current school year back to the one that began in 2022. A new school year joins the list on 1 August.

The last choice is for no year at all. It is named {{control:referenceShelfSchoolYearOther}}, unless you have given that group on the shelf another name.

A school year is one way to arrange the shelf. You can also make groups of your own: see [Organise the Reference Courses shelf](page:reference-groups).

## If it does not work

- **{{menu:courseSetSchoolYear}} is greyed.** The selected course is not kept for reference. Select a course on the {{control:referenceCourses}} shelf.
- **An orange sentence appears under the pop-up.** Another reference course with the same code is already filed in that year. Pick another year for this one.
- **The sheet says the school year could not be saved.** Wait a moment, then try again.
