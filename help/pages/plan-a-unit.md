---
id: plan-a-unit
checked: 2.0.0
covers:
- contracts/app-rules.json
- contracts/shared-rules.json
- mac-app/QuartzTeachers/Models/PlanningTab.swift
- mac-app/QuartzTeachers/Views/Planning/PlanningTabView.swift
- mac-app/QuartzTeachers/Models/OutsideAssistantPresence.swift
- support/agent_guidance/skills/plantoir-unit-planning/SKILL.md
keywords:
- plan a unit
- unit plan
- unit plans
- unit planning
- Planning tab
- Planning
- All Plans
- Open in Browser
- No Unit Plans Yet
- assistant
- Claude
- Claude Code
- Codex
- GitHub Copilot
- Copilot
- lesson cards
- calendar
description: Ask Claude, Codex or GitHub Copilot to plan a unit with you, then read the plan on the course's Planning tab.
---
An outside assistant can plan a unit with you: Claude, Codex or GitHub Copilot. You agree the plan in conversation, and the assistant builds it only when you say go. The finished plan shows on the course's {{control:courseDetailPlanningTab}} tab. It is never part of a class website.

The {{control:courseDetailPlanningTab}} tab shows only while one of the three assistants is installed on this Mac, and never for a course kept for reference. [About the assistants (optional)](page:assistants) says what an outside assistant is.

## Start a plan

1. In the sidebar, select the course itself, then click the {{control:courseDetailPlanningTab}} tab, beside {{control:courseDetailSettingsTab}}.
2. Read the empty tab. Before the course has a plan, the tab is titled {{control:planningTabNoUnitPlansYetTitle}} and says:
   {{say:shared-rules#unitPlanning.tab.words.emptyDescription}}
3. Press a button under it: {{control:planAUnitWithClaudeButton}} or {{control:planAUnitWithCodexButton}} or {{control:planAUnitWithGitHubCopilotButton}} There is one button for each assistant installed.
4. Wait for the window. A terminal window opens in your working folder with the assistant started, as it does for Revise With. An opening message has been sent, in your own words.
5. Answer the assistant's questions. It has been told to list the course's sections and read your How I Teach page. Then it asks which unit you want to plan, which sections the plan covers, and whether a colleague teaches the unit on other dates.
6. Agree the plan in conversation. The assistant has been told to build nothing until you say go.
7. Say go. The assistant builds the plan, and asks you in its window before it changes anything.

## Read the plan

1. Select the course and click {{control:courseDetailPlanningTab}}. Once a plan is built, the tab shows it.

{{picture:plan-a-unit-1}}
alt: The Planning tab of a course showing one unit's plan, with the Unit pop-up and the Open in Browser button marked.

2. Choose a unit in the {{control:planningTabUnitPopUp}} pop-up. It lists each unit that has a plan, and {{control:planningTabAllPlansChoice}}. The tab opens on the unit you are teaching today. When that unit has no plan, it opens on {{control:planningTabAllPlansChoice}}.

{{picture:plan-a-unit-2}}
alt: The Planning tab with All Plans chosen in the Unit pop-up.

3. Move through the plan with {{control:planningTabBackButton}}, {{control:planningTabForwardButton}} and {{control:planningTabReloadButton}}.
4. Press {{control:planningTabOpenInBrowserButton}} to read the page in your web browser, or to print it from there.

## Plan another unit

The buttons on the empty tab are there only until the course has a plan to show. For the next unit, open the assistant with Revise With and ask it to plan a unit. In its first reply the assistant reminds you which units already have a plan. See [Revise a course with Claude or Codex](page:revise-with).

## Where the plan is kept

The plan is kept inside the course folder, out of sight, so it travels with the course in backups. It is never on a class website. To give it to a colleague, see [Share a unit plan with a colleague](page:share-plan).

A section's Coverage tab shows what the course's pages reach. See [Curriculum expectations and the coverage map](page:coverage).

## While the session is open

Plantoir holds the course while the assistant's session is open. [Revise a course with Claude or Codex](page:revise-with) says what waits meanwhile and how to end the session.

## If it does not work

- **The course has no {{control:courseDetailPlanningTab}} tab.** None of the three assistants was found on this Mac, or the course is kept for reference.
- **The tab is titled {{control:planningTabUnitPlansCannotBeShownTitle}}.** Plantoir says:
  {{say:shared-rules#unitPlanning.tab.words.cannotShowDescription}}
- **{{control:planningTabOpenInBrowserButton}} does not open the page.** When the page has gone from the plan, Plantoir says:
  {{say:shared-rules#unitPlanning.tab.words.openInBrowserPageIsGone}}
- **Plantoir says the course is already being revised.** A session is already open on the course. Finish that session, then press the button again.
