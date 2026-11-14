---
id: obsidian-addons
checked: 2.0.0
covers:
- contracts/shared-rules.json
- mac-app/QuartzTeachers/Views/Settings/ObsidianSettingsView.swift
keywords:
- Obsidian
- add-on
- add-ons
- diagram shows as text
- graph shows as text
- diagrams in Obsidian
- TikZ
- functionplot
- trust author
- Restricted Mode
- community plugins
description: Plantoir can add two Obsidian add-ons that draw diagrams and graphs inside Obsidian. The class website draws them without the add-ons.
---
Obsidian by itself shows a `tikz` or `functionplot` block as text. Two Obsidian add-ons draw these blocks as pictures while you write, and Plantoir can add them to your courses.

The class website does not need the add-ons. It draws diagrams and graphs either way. The add-ons change only what you see in Obsidian. [Diagrams and graphs](page:figures) says how the blocks are written.

## The first time Plantoir asks

The offer appears when you open in Obsidian a course that has such diagrams or graphs. Your answer applies to every course. The offer's title is {{control:addOnsOfferTitle}}

- {{control:addOnsAddThem}} adds the add-ons to courses that have diagrams or graphs.
- {{control:addOnsNotNow}} adds nothing. Plantoir does not ask again until the next time it is started.
- {{control:addOnsDontAskAgain}} is a checkbox. Tick it before you press {{control:addOnsNotNow}}, and Plantoir does not make the offer again.

If Obsidian is open at that moment, the offer says so. It lists what adding them does under {{control:addOnsCloses}}, {{control:addOnsOpensAgain}} and {{control:addOnsKept}}. Obsidian closes, with every course that is open in it. Only this course opens again. Everything you have written is kept.

## Change your answer in Settings

1. Choose {{menu:settings}} and open the {{control:obsidianPane}} pane.
2. Turn the switch on or off. It is named {{control:addOnsSetting}}.

{{picture:obsidian-addons-1}}
alt: The Obsidian pane of Plantoir's Settings, with its one switch for adding the add-ons that draw diagrams and graphs.

With the switch on, Plantoir adds the add-ons to a course that has diagrams or graphs. It does so at two moments: when you open the course in Obsidian from Plantoir, and after you preview it. Turning the switch off adds nothing new. It leaves in place what was already added.

Plantoir never adds them to a course while that course is open in Obsidian, and never to a course kept for reference. For a course that is already open, it may ask {{control:addOnsReopenTitle}} with the buttons {{control:addOnsReopen}} and {{control:addOnsLater}}.

## When Obsidian asks whether you trust the author

The first time each course opens with the add-ons, Obsidian asks whether you trust the author of the course. The author is you.

1. Click "Trust author and enable plugins". Use the mouse. Pressing Return chooses the other button, "Browse vault in Restricted Mode".
2. Close the settings window that Obsidian then opens. Obsidian shows the add-ons switched on there.

These are Obsidian's own words for its buttons.

## If a course still shows a diagram as text

- **You chose Restricted Mode.** Open Obsidian's Settings, choose "Community plugins", and click "Exit Restricted mode".
- **The course was open in Obsidian when the add-ons were added.** Obsidian sees them only when it opens the course again. When Plantoir offers to reopen Obsidian, choose {{control:addOnsReopen}}.
- **The switch is off.** Turn it on in the {{control:obsidianPane}} pane, then open the course in Obsidian from Plantoir.
- **The course is kept for reference.** Plantoir does not add the add-ons to it.

The pane itself carries these directions:

{{say:shared-rules#obsidianAddOnsForFigures.wording.settingFooter}}
