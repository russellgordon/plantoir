---
id: reference-groups
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/ReferenceShelfHeading.swift
- mac-app/QuartzTeachers/Views/Wizard/ReferenceGroupNameSheet.swift
- mac-app/QuartzTeachers/Models/ReferenceGroupWording.swift
- mac-app/QuartzTeachers/Models/ReferenceGroupActions.swift
- mac-app/QuartzTeachers/App/SubjectMenus.swift
keywords:
- groups
- group
- organise
- organize
- reference courses
- shelf
- new group
- move to group
- rename group
- remove group
- school year
description: The Reference Courses shelf groups its courses by school year. You can make groups of your own, move courses into them, and rename or remove them.
---
The {{control:referenceCourses}} shelf in the sidebar groups its courses by school year. You can also make groups of your own and move courses into them.

## How the shelf is arranged

Each course kept for reference sits in the group for the school year it was taught in. A course with no year sits in a group named {{control:referenceShelfSchoolYearOther}}. [Set the school year of a reference course](page:school-year) changes a course's year.

## The shelf's menu

The {{control:referenceCourses}} heading has a button that shows three dots in a circle. A screen reader names it {{control:referenceShelfActionsButton}}. It opens a menu with two items: {{control:referenceShelfNewReferenceCourseMenuItem}} and {{control:referenceShelfNewGroupMenuItem}}.

{{picture:reference-groups-1}}
alt: The menu on the Reference Courses heading, open, with New Reference Course and New Group.

{{control:referenceShelfNewReferenceCourseMenuItem}} puts a ready-made course on the shelf. See [Bring in last year's courses](page:import-for-reference).

## Make a group

1. Open the shelf's menu and choose {{control:referenceShelfNewGroupMenuItem}}. A sheet titled {{control:referenceGroupSheetNewGroupTitle}} opens.
2. Type the group's name in the {{control:referenceGroupSheetNameField}} field.
3. Press {{control:referenceGroupSheetCreateButton}}.

A group's name can be at most 40 characters. It cannot be a school year, because each school year has a group of its own. It cannot be a name another group already has.

## Move a course into a group

1. In the sidebar, select the reference course.
2. Choose {{menu:courseMoveToGroup}}, or right-click the course and choose {{control:referenceShelfMoveToGroupMenuItem}}. A list of groups opens. The group for the course's own school year comes first, then the groups you made, from A to Z. A checkmark shows the group the course is in now.
3. Choose a group. Or choose {{control:referenceShelfNewGroupMenuItem}} at the end of the list, which makes a group and moves the course into it.

{{picture:reference-groups-2}}
alt: The Reference Courses shelf with a group the teacher made, and a course inside it.

## Rename a group

1. Right-click the group and choose {{control:referenceShelfRenameGroupMenuItem}}. A sheet titled {{control:referenceGroupSheetRenameGroupTitle}} opens.
2. Type the new name and press {{control:referenceGroupSheetRenameButton}}.

## Remove a group

Right-click the group. For an empty group the item is {{control:referenceShelfRemoveGroupMenuItem}}, and the group is removed without a question. For a group with courses in it the item is {{control:referenceShelfRemoveGroupAskingMenuItem}}, and Plantoir asks first.

The question says the group is removed from the shelf, and lists two facts:

- {{control:removeGroupQuestionItsCoursesRow}}: they go back to the group their school year puts them in.
- {{control:removeGroupQuestionTheCoursesThemselvesRow}}: they are not removed, and nothing in them changes.

Press {{control:removeGroupQuestionRemoveGroupButton}}, or {{control:cancel}} to keep the group.

## If it does not work

- **{{menu:courseMoveToGroup}} is greyed.** The selected course is not kept for reference. Groups are for reference courses only.
- **Plantoir says you already have that course kept for reference in that group.** Two reference courses with the same code cannot share a group. Choose a different group. To put a newer copy in place of an older one, see [Replace a reference course](page:replace-reference-course).
- **The shelf's menu shows {{control:referenceShelfStartTheGroupsAgainMenuItem}}.** This item appears only when Plantoir cannot read how the shelf is arranged. Choose it and read the question, which says:
  {{say:shared-rules#referenceCourses.groups.wording.startAgainSentence}}
  The groups you made are taken off the shelf. Nothing inside the courses changes. Press {{control:startTheGroupsAgainQuestionStartAgainButton}} to go ahead.
