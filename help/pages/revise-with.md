---
id: revise-with
checked: 2.0.0
covers:
- contracts/app-rules.json
- contracts/shared-rules.json
- contracts/assist-wording.json
- mac-app/QuartzTeachers/App/SubjectMenus.swift
- mac-app/QuartzTeachers/Models/SubjectMenuRules.swift
- mac-app/QuartzTeachers/Models/OutsideAssistantPresence.swift
- mac-app/QuartzTeachers/Models/Assist/ClaudeCodeLauncher.swift
- mac-app/QuartzTeachers/Models/Assist/CodexLauncher.swift
- mac-app/QuartzTeachers/Models/Assist/CopilotLauncher.swift
- mac-app/QuartzTeachers/Views/SidebarView.swift
- mac-app/QuartzTeachers/Models/AgentGuidance.swift
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- Revise With
- revise
- assistant
- Claude
- Claude Code
- Codex
- GitHub Copilot
- Copilot
- terminal
- session
- finish the session
- busy
- greyed
- already being revised
- trust folder
- sign in
- Add a section to
description: Open Claude, Codex or GitHub Copilot on a course from the Revise With menu, and what the course cannot do while that session is open.
---
Revise With opens an outside assistant on a course: Claude, Codex or GitHub Copilot. The assistant starts in a terminal window, already told which course you are working on. You type to it there.

You install the assistant and sign in to it yourself. [About the assistants (optional)](page:assistants) says what an outside assistant is.

## Open the assistant on a course

1. In the sidebar, select the course.
2. Choose {{menu:courseReviseWithClaude}} from the menu bar. For another assistant, choose {{menu:courseReviseWithCodex}} or {{menu:courseReviseWithCopilot}} instead. Each item shows only when that program is installed on this {{machine}}.

{{picture:revise-with-1}}
alt: The Course menu with Revise With open and the item for Claude marked.

3. Wait for the window. A Terminal window opens in your working folder, or an iTerm window when iTerm is already running. The assistant is started and connected to Plantoir, and an opening message has been sent. You type no command.
4. Answer the assistant's own questions, if it has any. The first time it starts in a folder, Claude Code or GitHub Copilot asks whether to trust the folder. If you are signed out, the assistant asks you to sign in. Plantoir answers neither for you.
5. Read the assistant's first reply, then type what you want changed, in your own words.
6. Read the plan it shows you, and agree or say what to change.
7. End the session when you are done. Type `/exit`, or close the window.

With a section selected, use the Section menu instead. Its items are {{menu:sectionReviseWithClaude}}, {{menu:sectionReviseWithCodex}} and {{menu:sectionReviseWithCopilot}}. They open the same session, on that section's course. The same items are under Revise With in the menu that opens when you right-click a course's row or a section's row.

## What the assistant has been told

The opening message is the same for all three assistants. You see it in the window as your own words. It tells the assistant:

- that you are a teacher working on this course in Plantoir;
- to use Plantoir's own actions for anything to do with the course;
- to start by listing the course's sections;
- to read your How I Teach page and keep to it;
- to show you its plan in plain words, and wait for you to agree, before it changes anything;
- when you keep earlier copies of the course for reference, that they can be read and built on, but are never changed or deployed;
- to say in its first reply that it can help plan a unit, or to remind you which units already have a plan.

## What the assistant asks you

Plantoir gives the assistant no permissions. The assistant asks you in its window before each change it makes through Plantoir, and before it deploys a section. You can tell it not to ask again. If you have told your assistant it need not ask, it will not.

## Tell it how you teach

Each course can have a page named How I Teach, your own account of how you teach it. The assistant is asked to read it first. See [The How I Teach page](page:how-i-teach).

{{picture:revise-with-2}}
alt: A course's How I Teach page open in Obsidian, at the top of the course.

## While the session is open

Plantoir holds the course while a session opened from Plantoir is open on it. Meanwhile:

- **Every item under Revise With is greyed for that course.** A line under the items says they are available once you finish revising, and names the assistant at work.
- **{{menu:courseRename}} and {{menu:addSection}} are greyed.** A line under the first says it is available once you finish revising, and names the assistant.
- **{{menu:courseRestoreFromBackup}} is not greyed, but waits.** When you choose it, Plantoir says that a session of the named assistant is working on the course. It asks you to finish that session first.
- **A backup the session made is kept.** It cannot be deleted until the session ends.

Everything else goes ahead as usual: a preview, a deploy, a scheduled deploy, removing a section or the course, and quitting Plantoir.

The course is free again once you end the session. Plantoir notices when you bring it to the front.

## Look at the changes before you deploy

Choose {{menu:rebuildPreview}} to see the section's website with the assistant's changes. A preview that was already open does not pick up the changes by itself. Deploy the section only when you are satisfied. See [Preview a section](page:preview) and [Deploy a section](page:deploy).

## The question about a file in your working folder

Plantoir keeps guidance for assistants in your working folder: two files at its top, named `AGENTS.md` and `CLAUDE.md`, and its guides for writing pages. It writes them when it gets the working folder ready, not when you choose Revise With.

If you already have a file of your own by one of those names, Plantoir asks before it touches it. A sheet asks whether to add a section to the file, and says that your own text stays as it is.

- {{control:agentGuidanceSheetShowWhatWouldBeAdded}} folds down the section Plantoir would add at the end of the file.
- {{control:agentGuidanceSheetAddButton}} puts the section in the file.
- {{control:agentGuidanceSheetNotNowButton}} leaves the file alone.

## If it does not work

- **Revise With lacks the assistant you want.** That program was not found on this {{machine}}. Plantoir does not install it. Plantoir looks again each time you come back to it from another app, so a program installed a moment ago shows without quitting Plantoir.
- **The items are greyed.** A session is already open on the course, or the course is kept for reference, which no assistant is opened on. They are also greyed while the assistant that runs on this {{machine}} has its window open on the course. A line under them says to close that window first. In the Course menu the items are also greyed while a section's row is selected: use the Section menu.
- **The item for the Local AI Assistant is greyed in the Course menu.** It always is. See [The local assistant](page:local-assistant).
- **Plantoir says the course is already being revised.** A session is open on it. Finish that session, then start again.
- **An alert titled {{control:outsideAssistantClaudeDidNotOpenTitle}} appears.** Plantoir could not start the session. If the assistant was updated or moved recently, quitting Plantoir and opening it again may be enough. The alerts for the other two are titled {{control:outsideAssistantCodexDidNotOpenTitle}} and {{control:outsideAssistantGitHubCopilotDidNotOpenTitle}}.
