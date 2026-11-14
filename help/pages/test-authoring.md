---
id: test-authoring
checked: 2.0.0
covers:
- support/agent_guidance/skills/plantoir-test-authoring/SKILL.md
- support/agent_guidance/skills/plantoir-handouts/SKILL.md
- contracts/app-rules.json
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- unit test
- test
- tests
- exam
- quiz
- quizzes
- practice test
- solutions
- marking guide
- versions
- test files
- where is my test
- handouts folder
- Claude
- Codex
- GitHub Copilot
description: Ask Claude, Codex or GitHub Copilot to draft a unit test, its solutions and a marking guide, as paper kept outside the course.
---
An assistant can draft a unit test for you: the test paper, its solutions and a marking guide. It builds them from only what your class was taught, following guidance that Plantoir gives it. The test is paper. Its files are kept in a folder outside the course, so that none of them reaches a class website.

This page is about Claude Code, Codex and GitHub Copilot, which you install yourself. See [Revise a course with Claude Code, Codex or GitHub Copilot](page:revise-with).

## Ask for the test

1. In the sidebar, select the course. Choose {{menu:courseReviseWithClaude}}, {{menu:courseReviseWithCodex}} or {{menu:courseReviseWithCopilot}}. A terminal window opens with the assistant started and connected to Plantoir. You type no command.
2. Ask for a unit test, in your own words. You can also ask for more than one version of it, a practice test, or a quiz for marks with a marking guide.
3. Check what the assistant shows you first. It asks for the day-by-day list of what was taught, or reads it from the section's class pages, and shows the list back to you. The test is built from that list.
4. Say where to keep the files. The first time, the assistant asks where this course's handouts should go. It should be a folder of its own outside the course. One example is a folder named handouts in your Documents folder, with a folder for the course inside it. The assistant remembers your answer for the course, and says the folder back each time it uses it.
5. Read what it reports at the end. The assistant tells you where the test's folder is, what was checked and by whom, and anything still open.

## What is in the test's folder

Each test has a folder of its own, named for the test, inside the handouts folder.

{{picture:test-authoring-1}}
alt: A unit test's folder in Finder, with the test paper, its solutions and the marking guide marked.

- `Version A.pdf` is the test, and `Version A - Solutions.pdf` its solutions. A second version is `Version B`, and so on.
- `Marking Guide.pdf` is the one marking guide.
- `Marking Kit` is a folder that holds the test's marks in a fixed form, with no place for a student's name. It holds three files. `README.md` is a short note on the folder. `answers.json` lists every mark on the test, for every version. `marks-template.json` is an empty record of marks for one paper.
- `Coverage.md` is a table of what the test covers.
- `Practice Test.pdf` and `Practice Test - Solutions.pdf` are there when you asked for a practice test.
- A folder named `Checks` is there when the answers can be computed.

Each PDF has beside it the file it was made from.

## Read every question and answer

The assistant says, every time, that everything it has made is a suggestion for you to review. The guidance asks that every answer be solved again by someone other than its writer. Read every question and every answer yourself all the same, before the test goes in front of students.

## Where copies may go

The assistant is asked to keep the test, its solutions and the kit out of the course. That means not in its folders, not in Media and not on a page. Every file in a course folder that is not a page is copied to the class website. An answer key kept there is one students could download.

Two kinds of copy are allowed.

- **Into a unit plan.** If the unit has a unit plan, each version's PDF may be copied into the plan's own folder. Each solutions PDF may be copied into the plan's Answer Keys folder. A plan is never part of a class website. The marking guide and the kit are not copied. See [Share a unit plan with a colleague](page:share-plan).
- **A practice test, onto the class website.** Its PDF, and only its PDF, may be copied into the course's Media folder and linked from a page. Whether its solutions go as well is your decision. The solutions of the test itself never do.

The assistant does this work, not Plantoir. Look in the handouts folder and in the course yourself to see that the files are where you expect.

## If it does not work

- **Revise With is not in the Course menu, or lacks the assistant you want.** Each item shows only when that program is installed on this {{machine}}. Plantoir does not install any of them.
- **The assistant asks again where the handouts go.** It asks again on another computer, or when the folder has been renamed.
- **You cannot find the test.** Ask the assistant where the test's folder is. It is in the handouts folder you chose, not in the course.
