---
id: fix-with
checked: 2.0.0
covers:
- contracts/app-rules.json
- contracts/shared-rules.json
- mac-app/QuartzTeachers/Models/Assist/FixWithAssistant.swift
- mac-app/QuartzTeachers/Views/Section/ProblemsTableView.swift
- mac-app/QuartzTeachers/Models/OutsideAssistantPresence.swift
keywords:
- Fix with
- fix
- fix problems
- problem
- problems
- Problems tab
- assistant
- Claude
- Claude Code
- Codex
- GitHub Copilot
- Copilot
- tick
- Include
description: Hand the problems you ticked on a section's Problems tab to Claude, Codex or GitHub Copilot, and check that they are gone.
---
The Fix with buttons hand problems from a section's {{control:problemsTab}} tab to an outside assistant: Claude, Codex or GitHub Copilot. The assistant opens already told which problems to fix and on which pages.

[The Problems tab](page:problems) explains the tab itself. Two kinds of problem have a repair button of Plantoir's own, and every problem can be fixed by hand. No assistant is needed.

## Hand problems to an assistant

1. In the sidebar, select the section, then click {{control:problemsTab}} at the top of its window.
2. In the {{control:problemsTabColumnInclude}} column, see that the problems you want fixed are ticked. Only ticked rows are handed over.
3. Press one of the buttons under the table: {{control:fixWithClaudeButton}}, {{control:fixWithCodexButton}} or {{control:fixWithGitHubCopilotButton}}. Each button shows only while that program is installed on this {{machine}}.

{{picture:fix-with-1}}
alt: The Problems tab with rows ticked, and the Fix with buttons under the table.

4. Wait for the window. A terminal window opens in your working folder with the assistant started, as it does for Revise With. The opening message lists the problems.
5. Read what the assistant says it will change, and agree or say what to change. It has been told to show you this in plain words and wait.
6. Answer when the assistant asks before each change. Plantoir gives it no permissions, so it asks in its own window.
7. Let it check its work. The assistant has been told to preview the section again when it is done, so that the tab clears.
8. Look at the {{control:problemsTab}} tab. A problem leaves the list when a preview or deploy no longer finds it.

## What the assistant has been told

The opening message reads as your own words. It names:

- the course and the section;
- whether a preview or a deploy found the problems;
- each ticked problem, numbered, in the tab's own words, with the page it is on;
- which of Plantoir's guides to use for each kind of problem.

At most ten problems are named. When more are ticked, the message says how many more are on the tab. A problem that is already fixed in the page is left out.

One kind of problem can be cleared only by a deploy. For that kind the assistant is told to deploy the section to Cloudflare Pages again. It asks you in its window before it deploys.

## While the session is open

Plantoir holds the course, as it does for any session opened from Plantoir. [Revise a course with Claude or Codex](page:revise-with) says what waits meanwhile and how to end the session.

## If it does not work

- **There are no Fix with buttons.** None of the three assistants was found on this {{machine}}, or the course is kept for reference.
- **The buttons cannot be pressed.** They need at least one ticked row for a problem the section still has. A row that says the problem is fixed in the source does not count.
- **Plantoir says the course is already being revised.** A session is already open on the course. Finish that session, then press the button again.
- **An alert says the assistant did not open.** Plantoir could not start the session. If the assistant was updated or moved recently, quitting Plantoir and opening it again may be enough.
- **A row is still there afterwards.** Preview the section again. A row is checked only by a preview or a deploy.
