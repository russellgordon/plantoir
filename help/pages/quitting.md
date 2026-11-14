---
id: quitting
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Models/QuitConfirmation.swift
- mac-app/QuartzTeachers/App/AppDelegate.swift
- contracts/shared-rules.json
keywords:
- quit
- quitting
- close
- closing
- quit anyway
- keep working
- still deploying
- unfinished
- log out
- shut down
- restart
description: Plantoir asks before it quits when it is in the middle of work such as a deploy. What it asks about, what each answer does, and when it never asks.
---
When you quit while Plantoir is in the middle of certain work, it asks first. This page says what it asks about, and what each answer does.

## What Plantoir asks about

When you choose {{menu:plantoirQuitPlantoir}} ({{key:plantoirQuitPlantoir}}), Plantoir asks only if this copy of Plantoir is in the middle of one of these:

- deploying a section;
- making a preview, until its first page appears;
- saving a copy of a course.

{{assistant}}
It also asks while it is sharing a course's unit plans, changing the password for the plans, or stopping the sharing.
{{/assistant}}

## What the question says

The question says that Plantoir is still at work and names the work, for example deploying a section, with the section and the course named. When several deploys are under way, it names each. A deploy is named ahead of a preview or a copy. With a deploy and a preview both under way, the question names the deploy alone.

Under that, it says what quitting now could leave unfinished.

- During a deploy:
  {{say:shared-rules#quittingWhileWorkIsUnderWay.whileUnitPlansAreShared.words.deployMessage}}
- While a preview is made or a copy of a course is saved, it says the work could be left unfinished. It adds that nothing on the class website changes.

{{picture:quitting-1}}
alt: The question Plantoir asks when you quit during a deploy, with the buttons Keep Working and Quit Anyway.

{{assistant}}
Work on unit plans is named together with deploys. For unit plans, the message names what each kind of work could leave:

- Sharing the plans: the plans could be left part way shared. Share them again, or stop sharing them, to settle it.
- Changing the password: the new password may not be saved yet. Nothing is sent, so the shared plans do not change.
- Stopping the sharing: the plans' address could still be working. Stop the sharing again.

See [Share a unit plan with a colleague](page:share-plan).
{{/assistant}}

## Keep Working or Quit Anyway

- {{control:quitQuestionKeepWorkingButton}} is the default, so pressing Return chooses it. Plantoir stays open, and nothing is stopped.
- {{control:quitQuestionQuitAnywayButton}} quits Plantoir. Plantoir does not stop a deploy on purpose, but the deploy may be left unfinished.

## When Plantoir does not ask

- **A preview that is only open.** Quitting stops Plantoir's previews, as {{control:stopPreview}} does.
- **Work that belongs to another program.** A scheduled deploy, or a command typed in Terminal, is not Plantoir's to ask about.
- **When the {{machine}} is logging out, restarting or shutting down.** Plantoir never holds the {{machine}} up with a question.
- **An update.** An update never stops you from quitting. See [Updating Plantoir](page:updates).

{{assistant}}
An assistant working from another app is another program's work too, and Plantoir does not ask about it.
{{/assistant}}
