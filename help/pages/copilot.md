---
id: copilot
checked: 2.0.0
covers:
- contracts/app-rules.json
- contracts/shared-rules.json
- mac-app/QuartzTeachers/Models/Assist/CopilotLauncher.swift
- mac-app/QuartzTeachers/Models/OutsideAssistantPresence.swift
- mac-app/QuartzTeachers/App/SubjectMenus.swift
- mac-app/QuartzTeachers/Models/PlanningTab.swift
- mac-app/QuartzTeachers/Views/Section/ProblemsTableView.swift
- documentation/10-local-ai-assistant.md
keywords:
- GitHub Copilot
- Copilot
- GitHub
- Copilot CLI
- command-line tool
- command line
- assistant
- asks before
- permission
- trust folder
- sign in
- stopped as soon as it started
- school account
- handout
description: What is particular to GitHub Copilot when you open it from Plantoir. It asks before each command, and Plantoir uses only GitHub's own program.
---
GitHub Copilot is one of the three outside assistants Plantoir works with. Plantoir opens GitHub Copilot's command-line tool, which runs in a terminal window. This page says what is particular to it.

You install the tool and sign in to it yourself, with your own GitHub account. Plantoir needs no assistant: see [About the assistants (optional)](page:assistants).

## Where it appears

Once GitHub's program is installed, GitHub Copilot is listed after Claude and Codex in three places.

- **Revise With.** {{menu:courseReviseWithCopilot}} in the menu bar, and {{menu:sectionReviseWithCopilot}} for a section. See [Revise a course with Claude Code, Codex or GitHub Copilot](page:revise-with).
- **The {{control:problemsTab}} tab of a section.** {{control:fixWithGitHubCopilotButton}} is under the table. See [Fix a problem with Claude Code, Codex or GitHub Copilot](page:fix-with).
- **The {{control:courseDetailPlanningTab}} tab of a course.** {{control:planAUnitWithGitHubCopilotButton}} is there until the course has a plan. See [Plan a unit](page:plan-a-unit).

Plantoir writes the name in full, GitHub Copilot, so that it is not taken for another product with a similar name.

## The first time

1. Choose one of the three items above. A terminal window opens in your working folder with GitHub Copilot started and an opening message sent.

{{picture:copilot-1}}
alt: A Terminal window with a GitHub Copilot session opened from Plantoir, the opening message already sent.

2. Answer its question about the folder. The first time GitHub Copilot starts in a folder, it asks whether to trust it. Plantoir does not answer for you. Answering No ends the session.
3. Sign in, if it asks. The sign-in is GitHub Copilot's own, in the window. Plantoir does not check whether you are signed in, or what your account includes.

## It asks before each command

Plantoir gives GitHub Copilot no permissions of any kind. So it asks you, in its own window:

- before each change it makes through Plantoir;
- before it deploys a section;
- before each command it runs on this {{machine}}, such as the one that makes a handout's PDF.

{{picture:copilot-2}}
alt: GitHub Copilot asking in its window whether it may run a command, with its own answers to choose from.

You can tell it not to ask again. If you have told GitHub Copilot it need not ask, it will not. A school's settings for GitHub Copilot can also let it act without asking. Plantoir cannot see either.

## Plantoir uses only GitHub's own program

Another program can have the same name as GitHub Copilot's command-line tool. Plantoir checks which program it has found, and uses it only when it is GitHub's.

A program that is not GitHub's is passed over, and Plantoir shows no message about it. If no program from GitHub is found, there are no GitHub Copilot items anywhere in Plantoir, as when nothing is installed.

{{mac}}
One case is known on a Mac. Homebrew has two packages that install a program named `copilot` in the same place. The package named `copilot` is another company's tool. GitHub's package is `copilot-cli`.
{{/mac}}

## If it does not work

- **There is no GitHub Copilot item.** GitHub's program was not found on this {{machine}}. Check that the program you installed is GitHub's own.
- **You have only now installed it.** Plantoir looks again each time you come back to it from another app, so a program installed a moment ago shows without quitting Plantoir.
- **The window says that GitHub Copilot stopped.** It reads:
  {{say:app-rules#outsideAgents.agents[2].stoppedAtOnce.sentence}}
  To open it on its own, start GitHub Copilot yourself, outside Plantoir.
- **An alert titled {{control:outsideAssistantGitHubCopilotDidNotOpenTitle}} appears.** Plantoir could not start the session. If GitHub Copilot was updated or moved recently, quitting Plantoir and opening it again may be enough.
- **The session opens, but GitHub Copilot cannot use Plantoir.** There are three known causes. A school account's administrator may not have turned on GitHub Copilot's command-line tool. A school's policy may stop it from working with other programs. Or you once turned Plantoir off inside GitHub Copilot, and it has stayed off. For the first two, ask the person who manages your school's GitHub account. For the third, turn Plantoir on again inside GitHub Copilot.
- **Your account does not include GitHub Copilot.** GitHub decides what an account includes. [Apply for GitHub's education benefits](page:github-education) reports what GitHub's pages say about teachers.
