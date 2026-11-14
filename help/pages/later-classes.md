---
id: later-classes
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Section/SectionVerbSheet.swift
- mac-app/QuartzTeachers/Views/Section/SectionDetailVerbs.swift
- contracts/shared-rules.json
- contracts/class-planning.json
- contracts/assist-wording.json
keywords:
- classes dated later
- future classes
- posted early
- published early
- deploy asks
- ticks
- ticked
- untick
- deploy ticked
- later classes
- next week's class
description: When published classes are dated after the next class, Deploy asks about them. A ticked class goes to students, and an unticked class is hidden.
---
When you deploy a section, Plantoir may first show a sheet titled {{control:laterClassesTitle}}. This page says why it appears and what each answer does.

## Why Deploy asks

A deploy sends every published page. That includes a class page you published ahead of its day. Plantoir asks when a class page is published and is dated after the section's next class day.

It does not ask about the next class itself. Tomorrow's class, published the evening before, goes out without a question.

## What the sheet shows

The sheet names the next class day, and lists each published class that is dated after it. The table has a {{control:pageColumn}} column, with a tick box for each class, and a {{control:dateColumn}} column. Every class starts ticked.

{{picture:later-classes-1}}
alt: The sheet that asks about classes dated later, listing published classes with their dates, every one ticked, and the Deploy Ticked button.

For a club, the title speaks of meetings in place of classes.

## What the ticks mean

- **A ticked class goes to students** with this deploy, at the date it has.
- **An unticked class is hidden before the deploy runs**, together with any page that only it links to. It is not held back for this one deploy. It stays hidden until you publish it again.

Unticking makes the same change that {{menu:hidePages}} makes. Plantoir saves a copy of the course first. Because the class is hidden in your course, a preview shows what students see.

Under the table, the sheet says:

{{say:assist-wording#wording.laterClassesKeptNote}}

## Answer the sheet

1. Untick any class that should not go to students yet.
2. Press {{control:deployTicked}}. Plantoir hides the unticked classes, and then deploys the section.

To deploy nothing, press {{control:cancel}} or the Escape key. Nothing is hidden and nothing is deployed.

If you untick every class, all of them are hidden and the section is still deployed.

## Put an unticked class back

- **Straight away:** choose {{menu:undoLastChange}}. The classes you unticked are published again. This works while it is still the last change made from the Section menu in this window.
- **Later:** publish the class with {{menu:publishPages}} or {{menu:publishClassForDate}}.

Either way, students see the class after the section is next deployed.

## When Plantoir does not ask

- **A class you left ticked before.** Plantoir does not ask about it again unless its date changes.
- **A class published with {{menu:publishClassForDate}}.** You named its date yourself.
- **A scheduled deploy.** Nobody is there to answer, so it goes out as it is. See [Schedule a deploy for later](page:schedule-deploy).
- **{{menu:publishPages}} and {{menu:publishClassForDate}}.** Publishing never asks this question. Only a deploy does.
- **A course kept for reference.** It is never deployed.

## Related pages

- [Deploy a section](page:deploy)
- [Show or hide pages for a section](page:publish-pages)
- [Publishing and deploying](page:publish-and-deploy)
