---
id: problems
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Section/ProblemsTableView.swift
- mac-app/QuartzTeachers/Models/SectionProblemsWording.swift
- mac-app/QuartzTeachers/Models/SiteHealthRepair.swift
- mac-app/QuartzTeachers/Views/Section/SectionDetailView.swift
- contracts/shared-rules.json
keywords:
- problems
- problem
- problems tab
- warning
- warning triangle
- warning symbol
- error
- broken
- repair
- fix button
- Put the Media folder back
- Add the missing page
- missing front page
- missing Media folder
- file too large
description: The Problems tab lists what a section's last preview or deploy found wrong and names the page of each problem. Two kinds have a repair button.
---
A section's {{control:problemsTab}} tab lists what its last preview or deploy found wrong. It names the page of each problem and says what to change. The tab is in the section's window only while that last preview or deploy found at least one problem.

## The warning beside a section

A section's row in the sidebar shows a warning symbol while its last preview or deploy found at least one problem. Hold the pointer over the symbol and it says:

{{say:shared-rules#sectionProblems.words.markerHelp}}

The same symbol marks a scheduled deploy that was stopped. The help then names both.

{{picture:problems-1}}
alt: The sidebar, with a warning symbol on the row of a section whose last preview found problems.

## The alert about new problems

When a preview or deploy finds a problem that was not there before, a short alert names the course and the section. It says:

{{say:shared-rules#sectionProblems.words.alertMessage}}

- {{control:newProblemsAlertShowButton}} opens the tab.
- {{control:newProblemsAlertNotNowButton}} closes the alert.
- When Plantoir can repair the new problem itself, the alert has that repair button too.

## Read the tab

1. In the sidebar, select the section.
2. Click {{control:problemsTab}}, beside {{control:websiteTab}}, at the top of the section's window.

{{picture:problems-2}}
alt: The Problems tab, a table with one row for each problem, giving its kind, its page and what is wrong.

Each row is one problem. The columns are:

- {{control:problemsTabColumnInclude}}: a tick box. A tick does not mark the problem as dealt with, and it repairs nothing.
- {{control:problemsTabColumnKind}}: what sort of problem it is.
- {{control:problemsTabColumnPage}}: the page it is on, or {{control:problemsTabPageWholeSection}} or {{control:problemsTabPageWholeCourse}}.
- {{control:problemsTabColumnProblem}}: what is wrong. Hold the pointer over it to read all of it.
- {{control:problemsTabColumnFirstFound}} and {{control:problemsTabColumnLastFound}}: when.

Click a column's heading to sort by it.

{{assistant}}
The ticks in {{control:problemsTabColumnInclude}} choose the rows that are handed to an assistant with the Fix with buttons under the table. There is one button for each of Claude Code, Codex and GitHub Copilot that is installed. See [Fix a problem with Claude or Codex](page:fix-with).
{{/assistant}}

## Two kinds Plantoir can repair

Two kinds of row carry a repair button, in the {{control:problemsTabColumnProblem}} column after the sentence.

- **{{control:problemsTabKindMediaFolder}}**: the course's Media folder is not there. {{control:problemsRepairPutTheMediaFolderBackButton}} makes an empty folder named Media. It does not bring back the pictures and files that were in it. For those, restore a backup: see [Back up a course and restore it](page:backups).
- **{{control:problemsTabKindFrontPage}}**: the section has no front page. {{control:problemsRepairAddTheMissingPageButton}} writes a new front page that holds only the course's name as its title. Write the rest in Obsidian.

Neither button writes over anything. If the folder or the page is already there, nothing changes.

Afterwards an alert says what was done. Your preview still shows how things were before. The alert offers {{control:problemsRepairOutcomePreviewAgainButton}} and {{control:problemsRepairOutcomeCloseButton}}. When a deploy found the problem, the alert adds that students do not have the change until you deploy again.

## Every other kind: change the page

The other kinds have no button:

- {{control:problemsTabKindCurriculumMap}}
- {{control:problemsTabKindPageSettings}}
- {{control:problemsTabKindLinkToAHiddenPage}}
- {{control:problemsTabKindHandout}}
- {{control:problemsTabKindDiagramOrGraph}}
- {{control:problemsTabKindSwiftProgram}}
- {{control:problemsTabKindSelfCheckQuestion}}
- {{control:problemsTabKindRunnableCode}}
- {{control:problemsTabKindGeoGebraSketch}}
- {{control:problemsTabKindFileTooLarge}}

1. Read the row and change the page it names, usually in Obsidian.
2. Preview or deploy the section again.

A problem leaves the list when a preview or deploy no longer finds it. Nothing else removes a row.

Two kinds have more to say:

- For {{control:problemsTabKindLinkToAHiddenPage}}, choose {{menu:publishPagesThatLinksLeadTo}}. See [Publish the pages a class page links to](page:links-checklist).
- {{control:problemsTabKindFileTooLarge}} comes from a deploy to Cloudflare Pages, which refuses any single file bigger than 25 MB. The section was not deployed there. Shorten or compress the file, or deploy the section to Netlify, which allows larger files.

## If it does not work

- **The row says the problem is fixed in the source.** It reads:
  {{say:shared-rules#sectionProblems.words.fixedInTheSource}}
  The problem was put right, and another section's preview or deploy found that. Preview or deploy this section too. Until then the row and the warning symbol stay.
- **You changed the page and the row is still there.** Preview or deploy the section again. A row is checked only then.
- **There is no {{control:problemsTab}} tab.** The section's last preview or deploy found no problem, so there is nothing to list. The tab comes back when a preview or deploy finds one. The window shows no tabs at all when {{control:websiteTab}} would be the only one.
- **A row has no repair button.** Only the two kinds above have one, and only while the problem is current. A course kept for reference never has one.
