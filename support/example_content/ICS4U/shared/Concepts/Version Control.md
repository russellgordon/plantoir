---
title: Version Control
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
Three people, one program, one afternoon. In [[The Merge Conflict]]
each group discovered the same thing: the moment two people edit the
same file, somebody's work is at risk, and the usual fixes —
`roster_final.py`, `roster_final_v2_REAL.py`, emailing the file
around — do not scale past about ten minutes.

Version control is the tool professionals use instead. It is not
backup, and it is not a folder of dated copies. It is a **record of
every change, who made it, and why**, that can be inspected, undone,
and combined.

## The vocabulary, and what each word actually means

| Word | What it is |
| --- | --- |
| Repository | The project, plus its entire history |
| Commit | One saved change, with a message explaining it |
| History | The commits in order — the project's memory |
| Branch | A line of work you can develop without disturbing others |
| Merge | Combining one branch's work into another |
| Conflict | Two changes to the same lines; a human must decide |
| Diff | The lines a change removed and added |

A commit is the unit that matters. It is not "everything I did today";
it is one coherent change with a sentence attached. History from a
project that does this well reads like a story:

```text wrap
a3f21c8  Refuse holds for members with an expired card
7d9e004  Add tests for the empty hold list
1b6cf52  Fix: dequeue on an empty queue returned the wrong thing
0c4a7de  Move Queue and Stack into structures.py
```

Every one of those lines is a sentence about the program, in the past
tense, saying what changed. Compare it with the history that most
first teams produce — `update`, `stuff`, `asdf`, `final` — which
records that four things happened and nothing about what they were.

> [!info] Write the message for the person doing the archaeology
> That person is usually you, in five weeks, trying to work out why a
> line exists. "Fix bug" tells them nothing. "Refuse holds for members
> with an expired card" tells them the rule, and lets them find the
> conversation that produced it. This is the cheapest documentation
> you will ever write, and the only kind that cannot drift away from
> the code it describes.

## Branch, merge, conflict

A branch lets you build the search feature while a teammate rewrites
the report, without either of you working in a half-finished file.
When the work is done, the branch is merged back. Most merges are
automatic — the tool can see that two people changed different parts
of the file.

When two people change the *same lines*, the tool refuses to guess and
marks the file:

```text wrap
<<<<<<< HEAD
        return f"{self.name} ({self.hours} h)"
=======
        return f"{self.name}: {self.hours} hours"
>>>>>>> report-formatting
```

Everything above `=======` is what was already there; everything below
is what the incoming branch wants. A conflict is not a failure and not
an accusation. It is the tool declining to make a decision that
belongs to a person — and the resolution is a conversation, then one
edit, then a commit that says which way you went and why.

> [!warning] Never resolve a conflict by deleting the other person's work
> Read both sides. Sometimes both changes are needed; sometimes the
> other version is better; occasionally the right answer is a third
> thing. Deleting a teammate's line to make the markers go away is how
> a team loses a day's work and, more expensively, its trust.

## What the history is for

- **Finding out why.** When a line makes no sense, the commit that
  introduced it usually explains itself in one sentence — the single
  most underused technique in [[Reading Somebody Else's Code]].
- **Going back.** A change that broke something can be undone
  precisely, without anybody trying to remember what the file looked
  like on Tuesday.
- **Reviewing.** A diff is the unit of review. The whole of
  [[Read the Diff]] is practice at reading one and saying, out loud,
  whether you would approve it.
- **Sharing safely.** [[B1.7|the source-code management expectation]]
  asks you to manage shared code *securely*, and that word does real
  work: history is permanent. A password, an API key, or a file of
  real people's names committed once stays in the history even after
  you delete it in a later commit. Decide what goes in the repository
  before it goes in.

## Habits that make it work in a team

- **Commit small and often.** One idea per commit. A commit that
  changes forty files cannot be reviewed and cannot be undone
  selectively.
- **Pull before you start; push when you stop.** Most conflicts are
  caused by working for three days on a stale copy.
- **Never commit code you have not run.** The history is shared, and a
  broken commit blocks everybody.
- **Agree the interface first.** If two people agree what a function
  is called and what it returns before either writes it, their work
  merges cleanly — the practical trick behind
  [[A2.3|the code-modification expectation]] and most of
  [[Working in a Team]].

The mechanics — the actual commands, in order — are in
[[Using Version Control]]. The team habits are in
[[Software Project Management]], and both are assessed in
[[The Software Project]], where the history you leave behind is part
of the handover.

%%curriculum-start%%
## Curriculum connection

![[B1.7]]

![[B2.1]]

![[A2.3]]
%%curriculum-end%%
