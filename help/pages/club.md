---
id: club
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Wizard/NewCourseWizardView.swift
- mac-app/QuartzTeachers/Models/WizardWording.swift
- mac-app/QuartzTeachers/Models/UnitWordRenameWording.swift
- contracts/shared-rules.json
- contracts/class-planning.json
keywords:
- club
- clubs
- extracurricular
- team
- society
- meeting
- meetings
- week
- not a course
description: Make a website for a club in the New Course or Club sheet, and choose its meeting words, which cannot be changed later.
---
A club gets a website the same way a course does, from the {{control:newCourseOrClub}} sheet. A club meets, and does not hold classes, so the sheet asks a few different questions.

## Steps

1. Choose {{menu:newCourse}} to open the {{control:newCourseOrClub}} sheet.
2. In the {{control:newCourseSheetCourseCode}} field, type a short code for the club, such as CODING. A club's name typed there is accepted.
3. Check that {{control:newCourseSheetThisIsAClub}} is on. Plantoir turns it on already for a code that is not a course code, such as CODING. The fields are then labelled {{control:newCourseSheetClubCode}} and {{control:newCourseSheetClubName}}.
4. Fill in the {{control:newCourseSheetClubShortLabel}} field. It shows for a code that is not shaped like a course code, whichever way the switch is set. The short label is shown beside the club's emoji, and holds 12 characters at most.

{{picture:club-1}}
alt: The New Course or Club sheet with This is a club turned on, and the Meetings part with the club's words.

5. Fill in the {{control:newCourseSheetMeetingsPart}} part, which a club has in place of {{control:newCourseSheetUnitsPart}}:
   - {{control:newCourseSheetFolderForMeetingPages}}: the folder that holds a page for each meeting.
   - {{control:newCourseSheetFrontPageHeading}}: the heading on the front page, in your own words. A club starts with Most Recent Meeting.
   - {{control:newCourseSheetPagesAreNamed}}: the word in each page's name. With Week, the pages are named Week 1, Week 2 and so on.
6. Fill in the other parts as you would for a course. [Make a new course](page:new-course) describes them.
7. Press {{control:newCourseSheetCreateClub}}. When the sheet has finished, close it. The club is in the sidebar.

{{assistant}}
The {{control:newCourseSheetMeetingsPart}} part has one more choice, which sets whether an assistant calls one of the club's pages a class or a meeting.
{{/assistant}}

## How a club differs from a course

- Its pages are numbered one after another, with no units and days.
- It has no curriculum, and no ready-made pages or starting skeleton.
- It starts with empty folders and one page, for its first meeting.

Everything else works as it does for a course. You write the pages in Obsidian, then preview and deploy.

## What cannot be changed later

The words in the {{control:newCourseSheetMeetingsPart}} part can be changed while the sheet is open. Once the club is made, they are fixed.

- In the club's settings, they are shown in a part named {{control:courseSettingsClassPagesPart}}, which is locked.
- The {{control:unitWordRename}} button beside the club's word is greyed, and this sentence is under it:
  {{say:shared-rules#specialNames.renameUnitWord.renameLockedNumbered}}

The club's name, its short label and how its website looks can still be changed. See [Change a course's settings](page:course-settings).
