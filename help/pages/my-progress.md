---
id: my-progress
checked: 2.0.0
covers:
- contracts/shared-rules.json
- contracts/file-formats.json
- scripts/my_progress.py
keywords:
- progress
- My Progress
- success criteria
- test of success
- tests of success
- learning goals
- tick box
- tick boxes
- checklist
- track progress
- self-assessment
description: Tick boxes under a success-criteria heading give a section's website a My Progress page that counts each student's ticks in their own browser.
---
Students can tick boxes under a page's success criteria, and a page named My Progress counts their ticks. A section's website gets that page by itself when your pages have such boxes. This page says what to write.

## Write the success criteria

1. In Obsidian, open a page that students can see.
2. Add a heading named Success criteria, Test of success or Tests of success. Capital letters do not matter, and a colon or other mark at the end is ignored.
3. Under the heading, type the criteria as a checklist:

```text wrap
## Success criteria

- [ ] I can name the parts of a circuit.
- [ ] I can explain why a switch stops the current.
```

4. Preview the section. If a preview is already running, choose {{menu:rebuildPreview}}.

{{picture:my-progress-1}}
alt: A page in Obsidian with a Success criteria heading and tick boxes under it.

The heading must be a heading of the page itself. A heading inside a box or a list does not count.

## What the website gains

The section's website gains a page named {{control:myProgressTitle}} when at least one page that students can see has a box under such a heading. Plantoir makes it when the website is made. There is nothing to turn on.

- It is listed first in Key Links.
- It is pinned in the sidebar.
- A section with no such box has no {{control:myProgressTitle}} page.

If your course has a page of its own named My Progress at the top of the course folder, yours is used. Plantoir writes nothing over it. Capital letters in the name do not matter.

## What students see

On each page, a student ticks the boxes under the success criteria. [Checklists students tick](page:task-boxes) says how the boxes work.

The {{control:myProgressTitle}} page counts the boxes that student has ticked. The counts are given page by page, grouped by the class that first linked each page. The page begins:

{{say:shared-rules#myProgress.words.intro}}

{{picture:my-progress-2}}
alt: The My Progress page on the class website, with a count of ticked boxes for each page.

Nothing reaches you. You cannot see a student's ticks or counts.

## What a student may notice

The ticks are kept in one browser, for one website.

- Another computer or another browser starts without the student's ticks.
- If you change the first line of a criterion, its box goes back to how you wrote it.
- If you rename or move a page, every box on it goes back to how you wrote it.

A box written as `- [ ]`, as in the example above, is empty.

## If it does not work

- **The website has no My Progress page.** Check the heading's words against the three names above. Check that the page with the boxes is published for this section: see [Show or hide pages for a section](page:publish-pages).
- **The My Progress page says this:**
  {{say:shared-rules#myProgress.words.unreadable}}
  The website was opened as a file on a computer. Open it from its web address.
