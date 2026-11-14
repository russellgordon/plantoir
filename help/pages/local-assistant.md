---
id: local-assistant
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Settings/AssistantSettingsView.swift
- mac-app/QuartzTeachers/Views/Settings/PlantoirSettingsView.swift
- mac-app/QuartzTeachers/Models/Assist/AssistModelTier.swift
- mac-app/QuartzTeachers/Views/Assist/AssistWindowView.swift
- mac-app/QuartzTeachers/Views/Assist/AssistSupportingViews.swift
- mac-app/QuartzTeachers/Models/OutsideAssistantPresence.swift
- mac-app/QuartzTeachers/Models/SubjectMenuRules.swift
- mac-app/QuartzTeachers/App/QuartzTeachersApp.swift
- contracts/shared-rules.json
- contracts/assist-wording.json
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- assistant
- local assistant
- local AI
- AI
- chat
- ask
- smaller assistant
- larger assistant
- download
- memory
- undo that
- Go
- Apple silicon
description: Open the assistant that runs on this {{machine}}, agree to its one-time download, and ask it to change a section.
---
The local assistant runs on this {{machine}}. You type what you want done in a section, in a sentence, and it does it once you agree. It runs entirely on this {{machine}}, and nothing you have written is sent anywhere.

Plantoir does not need it. Everything it does is also in the Section menu.

{{mac}}
It needs a Mac with Apple silicon.
{{/mac}}

## Open it

1. In the sidebar, select a section.
2. Choose {{menu:sectionReviseWithLocalAssistant}}. A window titled {{control:assistantWindowTitle}} opens for that section.

The same item is under Revise With in the menu that opens when you right-click the section's row in the sidebar.

## The one-time download

The first time, the window says that the assistant needs a one-time download. It names the assistant Plantoir picked to suit this {{machine}}'s memory, the small assistant or the larger assistant. A button that begins with the word Download gives the size.

Nothing is downloaded until you press that button. You can carry on working while it downloads, and the window is ready when it finishes. A button named {{control:assistantStopButton}} ends the download.

## Ask for something

1. Type what you want in the box, then press Return. Above the box is a shelf of examples, in groups. Clicking an example puts its words in the box and does not send them, so you can change them first.

```text wrap
Publish tomorrow's class
Unpublish Unit 2, Day 3
What would students see in this section right now?
Add the next class page
Undo that
```

2. Read the answer. The assistant says what it will do, then asks:
   {{say:assist-wording#wording.planQuestion}}
3. Press {{control:assistantGo}} to let it go ahead, or {{control:assistantCancel}} to leave things as they are.

{{picture:local-assistant-2}}
alt: The Assistant window for a section, where the assistant has said what it will do and waits with its Cancel and Go buttons.

## When you ask it to deploy

A request to deploy always asks first, whatever your settings are. The question is this one, and the button is {{control:assistantDeploy}}:

{{say:assist-wording#wording.deployQuestion}}

With the question, the assistant says:

{{say:assist-wording#wording.deployApproval}}

## Take a change back

Type Undo that. The assistant takes back its last change.

The assistant's undo list is its own. It is separate from {{menu:undoLastChange}}, which takes back a change made from the Section menu.

## Settings for the assistant

Choose {{menu:settings}} and open the {{control:assistantSettingsPane}} pane. It has three groups.

{{picture:local-assistant-1}}
alt: The Assistant pane of Settings, with the three choices of which assistant runs on this {{machine}}.

**{{control:assistantBeforeItChangesGroup}}** holds one switch, {{control:assistantAskBeforeChanging}}.

- Turned on, the assistant says what it is about to do and waits before it publishes or hides pages.
- Turned off, it publishes and hides pages without asking.
- Deploying always asks.

After you have agreed a few times, the assistant may tell you, once, that there is a setting for this, and offer to stop asking.

**{{control:assistantWhichRunsGroup}}** holds three choices.

- {{control:assistantChooseForMe}} is the choice Plantoir starts with. It picks the assistant that suits this {{machine}}'s memory.
- {{control:assistantSmaller}} starts fast, its row says. It misunderstands more often, so it always shows what it is about to do before doing it.
- {{control:assistantLarger}} understands what you ask far more reliably, its row says. The row names the memory a {{machine}} should have for it.

Each of the two named rows gives its download size and the memory it uses while it works. If you pick one that is too big for this {{machine}}'s memory, an orange caution names both amounts. The caution does not stop you.

**{{control:assistantOnThisMacGroup}}** has a row for each assistant. The row says whether it is downloaded and how large it is. Its button is {{control:assistantDownloadButton}}, {{control:assistantStopButton}} while it downloads, or {{control:assistantRemoveButton}}.

## If it does not work

- **The item is greyed in the Course menu.** It always is. The local assistant works on one section at a time, so select a section and use the Section menu.
- **The course is kept for reference.** The local assistant does not work on a course kept for reference.

{{mac}}
- **The pane says the assistant needs an Apple silicon Mac.** The assistant cannot run on this Mac. Everything else in Plantoir works as usual.
{{/mac}}

- **The assistant did not understand.** It changes nothing, and says:

{{say:assist-wording#wording.didNotFollowThat}}

- **It asks for your class dates.** Some requests need them. See [Give Plantoir your class dates](page:class-dates).
- **{{control:assistantRemoveButton}} is refused.** An assistant cannot be removed while an assistant window is open. Plantoir names the section whose window to close.

To work with an assistant from outside Plantoir instead, see [About the assistants (optional)](page:assistants).
