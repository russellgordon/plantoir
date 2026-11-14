---
id: links-checklist
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Section/LinksChecklistSheet.swift
- contracts/shared-rules.json
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- links
- dead links
- broken links
- hidden pages
- links to hidden pages
- linked pages
- publish linked pages
- checklist
- not now
description: When pages students can see link to pages that are still hidden, Plantoir lists the hidden pages and publishes the ones you tick.
---
A page that students can see may link to a page that is still hidden. Students cannot follow that link. Plantoir lists such hidden pages for a section, and publishes the ones you tick.

## When the list appears

- **After a preview or a deploy** that you start in the section's window, when Plantoir finds links from pages students can see to hidden pages.
- **When you next open the section's window** after a deploy that ran without you, such as a scheduled one.
- **When you ask for it.** Choose {{menu:publishPagesThatLinksLeadTo}} from the menu bar.

The list is made each time the section is previewed or deployed.

## Steps

1. Read the list. The sheet says:
   {{say:shared-rules#linksChecklist.wording.intro}}

{{picture:links-checklist-1}}
alt: The Links to Hidden Pages sheet, its pages in groups with a tick box beside each.

2. Look at each group. There may be up to three:
   - {{control:linksUsedByAClass}}
   - {{control:linksFromOtherPages}}
   - {{control:linksClassesNotYetPublished}}
3. Read the second line of a row. It says which page links to this one, or what date the page will have once it is published.
4. Tick the pages to publish, and untick the ones to leave hidden. A ticked box always means the page is included.

{{picture:links-checklist-2}}
alt: The Links to Hidden Pages sheet, with its two notes, the Not Now button and the Publish button.

5. Press the Publish button, which names the number of pages it will publish. Or press {{control:linksNotNow}} to publish nothing.
6. Deploy the section when you want students to see the pages. See [Deploy a section](page:deploy).

## How the ticks start

- **A class starts unticked.** Tick it if you want it published now.
- **A page that only a hidden class links to starts unticked.** It comes with that class.
- **Every other page starts ticked.**
- **A page that a ticked class brings with it is shown ticked.** It cannot be unticked while that class is ticked.

## What Publish does, and does not do

Publish marks the ticked pages as published for this section. Two notes on the sheet say what it leaves alone:

{{say:shared-rules#linksChecklist.wording.frontPageStaysPut}}

{{say:shared-rules#linksChecklist.wording.nothingChangesUntilYouDeploy}}

Plantoir remembers your answer, whether you press Publish or {{control:linksNotNow}}. It does not show you the same set of pages again. When a new hidden page joins the list, the sheet comes back, with the pages you unticked before still unticked.

## When the list is not shown

- **For a course kept for reference.**
- **When every page on it has already been answered.**
- **When the course has changed since the list was made.** Preview the section again for a list that is up to date.
- **During a scheduled deploy.** The deploy goes out as it is, and the list is shown to you afterwards.

## If it does not work

- **The sheet says pages have changed since the section was last previewed or deployed.** Preview the section, then choose the command again.
- **The Publish button is greyed.** No page is ticked.
- **The sheet says the course is being deployed.** Try again when the deploy has finished.
- **The sheet says the pages have all been published or removed.** There is nothing left to do.
- **A page was left as it is.** It changed after the list was made. Preview the section again and look at the new list.
