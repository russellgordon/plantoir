---
id: assistants
checked: 2.0.0
covers:
- contracts/app-rules.json
- contracts/shared-rules.json
- mac-app/QuartzTeachers/Models/OutsideAssistantPresence.swift
- mac-app/QuartzTeachers/App/SubjectMenus.swift
- mac-app/QuartzTeachers/Models/SubjectMenuRules.swift
- mac-app/QuartzTeachers/Models/PlanningTab.swift
- mac-app/QuartzTeachers/Views/Section/ProblemsTableView.swift
- mac-app/QuartzTeachers/Models/AgentGuidance.swift
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- assistant
- assistants
- AI
- outside assistant
- Claude
- Claude Code
- Codex
- GitHub Copilot
- Copilot
- do I need an assistant
- optional
- permission
- asks before
- command line
- terminal
description: Plantoir works fully without an assistant. This page says what an outside assistant is, which three Plantoir works with, and where each appears.
---
Plantoir works fully without an assistant. Every task in the rest of Help uses Plantoir's own menus. Nothing in this part of Help is needed to make, preview or deploy a website.

This page says what an outside assistant is, which ones Plantoir works with, and where each appears in the app.

## What an outside assistant is

An outside assistant is a separate program, made by another company. You install it yourself and sign in to it yourself, with your own account.

Plantoir can open that program in your working folder, on one of your courses, with what it needs to know about the course. You then type to the assistant in its own window.

- Plantoir never installs an outside assistant, and never signs in for you.
- Plantoir does not check whether you are signed in, or what kind of account you have.
- What an outside assistant reads is sent to its maker's service.

## The three Plantoir works with

Plantoir works with three, and names them as its menus do: Claude, Codex and GitHub Copilot. Each is a program that runs in a terminal window: Claude Code, Codex, and GitHub Copilot's command-line tool.

Plantoir looks for each program on this Mac and finds it where its installer put it. An assistant that is not installed is not shown anywhere in Plantoir. Its items are hidden, not greyed. Each of the three is shown or hidden on its own.

## Where each appears

- **In the Course menu and the Section menu**, under Revise With. The same items are in the menu that opens when you right-click a course's row or a section's row in the sidebar. See [Revise a course with Claude or Codex](page:revise-with).
- **On a section's {{control:problemsTab}} tab**, as buttons under the table that hand the problems you ticked to an assistant. See [Fix a problem with Claude or Codex](page:fix-with).
- **On a course's {{control:courseDetailPlanningTab}} tab**, as buttons that start the planning of a unit. The tab itself shows only while one of the three is installed. See [Plan a unit](page:plan-a-unit).

{{picture:assistants-1}}
alt: The Course menu with Revise With open, listing Claude, Codex, GitHub Copilot and the Local AI Assistant.

## What Plantoir gives the assistant

- **A place to start.** The assistant opens in your working folder with an opening message already sent. The message names the course and reads as your own words.
- **Guidance.** Plantoir keeps its guides for writing pages in the working folder, where these programs read them before they start. You never need to open them.
- **What Plantoir can do.** The assistant can ask Plantoir to do what its menus do. It can publish and hide pages, rebuild a preview, add classes and deploy a section, among other things. It also changes page files itself, following the guides.

The assistant can reach every course in the working folder, not only the one it was opened on. The opening message is what points it at one course. A course kept for reference can be read, but never changed or deployed.

## What Plantoir does not give it

Plantoir gives an outside assistant no permissions of its own. The assistant asks you, in its own window, before each change it makes through Plantoir and before it deploys a section.

You can tell the assistant not to ask again. If you have told your assistant it need not ask, it will not. A school's own settings for the assistant can do the same. Plantoir cannot see those settings.

Plantoir saves a backup of a course before an assistant changes it. See [Back up a course and restore it](page:backups).

## The assistant that runs on this Mac

Plantoir also has an assistant of its own, which runs on this Mac. Nothing you have written is sent anywhere by it. It is not an outside assistant. See [The local assistant](page:local-assistant).

## Read next

- [Revise a course with Claude or Codex](page:revise-with): open an assistant on a course, and what the course cannot do meanwhile.
- [Fix a problem with Claude or Codex](page:fix-with)
- [Plan a unit](page:plan-a-unit)
- [Use GitHub Copilot with Plantoir](page:copilot): what is particular to GitHub Copilot.
- [Apply for GitHub's education benefits](page:github-education): what GitHub's own pages say about teachers.
- [The How I Teach page](page:how-i-teach): your account of how you teach a course, which an assistant is asked to read.
