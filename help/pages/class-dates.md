---
id: class-dates
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Section/SectionScheduleSheet.swift
- mac-app/QuartzTeachers/Models/SectionScheduleSource.swift
- mac-app/QuartzTeachers/Models/SectionTimetable.swift
- mac-app/QuartzTeachers/Views/Section/SectionDetailVerbs.swift
- contracts/schedule-rules.json
- contracts/assist-wording.json
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- class dates
- dates
- timetable
- schedule
- calendar
- which days
- CSV
- ics
- Google Sheet
- Google Sheets
- day first
- month first
- paste dates
description: Give Plantoir the days a section meets, by pasting them, choosing a file or naming a Google Sheet, so that it can date class pages.
---
Plantoir dates class pages from a list of the days a section meets. You give that list once for each section, and replace it when the timetable changes.

## Steps

1. In the sidebar, select the section.
2. Choose {{menu:classDates}} from the menu bar. A sheet opens that asks when the section meets.
3. Choose where the dates are:
   - {{control:typeOrPaste}}: type or paste the dates into the box, one date on each line. A heading row and blank lines do no harm.
   - {{control:aFile}}: press {{control:chooseAFile}} and choose a .csv file with one column of dates, or a .ics calendar export.
   - {{control:aGoogleSheet}}: paste the sheet's address, copied from your browser's address bar.
4. In the {{control:whereTheseCameFrom}} field, say where the dates came from, in your own words. The name of your timetable file and the block is enough. It is what you will read months later. Choosing a file fills the field with the file's name if it is empty.

{{picture:class-dates-1}}
alt: The class dates sheet with dates pasted in, the field that says where they came from, and the Read the Dates button.

5. Press {{control:readTheDates}}. While you type dates, the Return key makes a new line and does not press the button.
6. If Plantoir asks which way round the dates are, answer it. The next part of this page explains the question.
7. Read the plan. It says how many dates there are, and gives the first and the last with their weekdays. It also says where they came from, and what they replace if the section already had dates.
8. Press {{control:rememberTheseDates}}. The sheet closes. {{control:classDatesBack}} returns to the dates, and {{control:cancel}} closes the sheet with nothing remembered.

The dates are kept inside the course's folder. They travel with the course when it is backed up, archived or restored.

## Day first or month first

A date such as 08/09/2026 can be read two ways: the 8th of September, or the 9th of August. When nothing in the list settles it, Plantoir shows one of your dates and asks which it is. One button begins Day First and the other begins Month First, and each spells out the date it would mean.

{{picture:class-dates-2}}
alt: The question asked when dates can be read two ways, with one button for day first and one for month first.

Your answer is used for every date in the list. If any date in the list has a number above 12 in one of the two places, that settles it and Plantoir does not ask.

## How a date may be written

Each of these is read as 8 September 2026:

```text wrap
2026-09-08
Sep 8, 2026
September 8 2026
8 September 2026
8 Sept. 2026
2026/09/08
```

A date written the first way, year then month then day, is always read correctly.

## A Google Sheet

Reading a Google Sheet sends the sheet's link to Google over the internet. Plantoir's sheet carries a notice that says so. Typing, pasting and choosing a file all stay on this Mac.

The Google Sheet must be shared. In Google Sheets, choose Share, and under General access choose **Anyone with the link**. A link to one tab of the sheet reads that tab.

## When the sheet opens by itself

Three commands need the class dates:

- {{menu:addNextClass}}
- {{menu:reDateClasses}}
- {{menu:makeRoomForClasses}}

If you choose one for a section with no dates on file, this sheet opens first, with a line that says why. After you press {{control:rememberTheseDates}}, the command you chose carries on.

## If it does not work

- **Some lines cannot be read.** The sheet names them and refuses the whole list. Correct those lines and read the dates again.
- **No dates were found.** There is nothing to remember.
- **The dates are written both ways round.** Write them all one way.
- **The address is not a Google Sheet's.** Copy it from the browser's address bar while the sheet is open. A link made with Google's Publish to the web does not work.
- **Google sent a sign-in page.** The sheet is not shared. Share it as described above.
- **The file is refused.** It is not a .csv or .ics file, or it is a calendar file with no events in it.
- **{{menu:classDates}} is greyed.** The course is kept for reference, or the section is busy with a deploy, a backup or another command from the Section menu.
