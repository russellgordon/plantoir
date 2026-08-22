---
title: "Git and Version Control Fundamentals"
publish: true
created: __CREATED__
tags:
  - tutorial
enableToc: true
---
Version control is an undo history for your entire project. If you have ever named files `project_final.py`, `project_final_v2.py`, and `project_final_really.py`, you already know why version control is necessary. Git is the tool we use to track changes properly.

## Setting up Git

Before using Git, it needs to know who you are, because every change is stamped with an author. Open your terminal and run:

```
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

## The Git workflow

Think of Git like taking photographs of your project's progress.

### 1. Initialize (`git init`)
Turn a normal folder into a Git repository. You only do this once per project.

```
cd my_python_project
git init
```

### 2. Stage (`git add`)
Tell Git which files you want to include in the next photograph. If you wrote a script for tracking Fraser Valley rainfall, you add it:

```
git add rainfall.py
```

### 3. Commit (`git commit`)
Take the photograph. A commit permanently records the staged changes. You must include a message describing *why* you made the change.

```
git commit -m "Add initial script to parse rainfall data"
```

### 4. Review (`git log` and `git diff`)
To see the history of your project's photographs:

```
git log
```

If you made a change to `rainfall.py` and want to see what is different before staging it:

```
git diff
```

## Your commit history is your prototype record

Every task in this course asks you to record how your program changed
and why — and if you are committing properly, you have already written
most of that record without noticing. A commit is a prototype, dated,
with a note attached saying what you were trying.

That only works if the messages are worth reading later. Compare:

```
update stuff
fixed it
more changes
```

against:

```
Add avalanche check for freezing-level input
Fix hypothermia branch firing before the guard condition
Replace nested ifs with a single elevation lookup after peer review
```

The second set is a story about a program's development. The first set
is three photographs of a room with the lights off.

Two habits make the history usable:

- **Commit at each decision, not at each save.** When you have tried
  something and it now works differently than it did — that is a
  prototype. When you have changed a variable name, that is not.
- **Say what changed and why, in that order.** "Replace the dictionary
  with a list because lookups were never the slow part" tells your
  future self something they cannot recover from the code itself.

When you write up your iterations in [[Learning Journey Log]], run
`git log --oneline` first and read down it. The turning points in your
project are the commits where the message stops describing an addition
and starts describing a change of mind — those are the ones worth a
paragraph, and they are very hard to remember three weeks later without
the log in front of you.

## Common mistakes and fixes

> [!warning] Committing everything blindly
> Never use `git add .` unless you know exactly what changed in every file. It is the easiest way to accidentally commit passwords, giant datasets, or junk files. Add files specifically by name.

> [!tip] Bad commit messages
> "Fixed stuff" is a useless message when you are reading it three months later. "Fix off-by-one error in average calculation" tells the story.

If you commit and realize you made a typo in the message, you can fix the very last commit:

```
git commit --amend -m "New, corrected message"
```

%%curriculum-start%%
## Curriculum connection

![[D4.5]]

![[D7.1]]

![[S1.1]]
%%curriculum-end%%
