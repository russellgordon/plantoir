---
title: The Maintenance Sprint
publish: true
created: __CREATED__
tags:
  - tasks
enableToc: true
---
> [!abstract] At a glance
> Teams · launched Unit 4, Day 2 and due Unit 4, Day 3 · a working
> program your team did not write, one bug to fix and one feature to
> add, without breaking anything that already worked

## What you are making

Nothing. That is the point.

Your team is handed a program somebody else wrote — another team's
project from a previous semester, or one I have prepared with its own
habits and its own history. It works. It has users. It has at least one
bug that its authors never noticed and at least one thing it does not
do that somebody now needs.

You will read it, run it, test it, and change it. Two changes only:

1. **One fix.** A reported bug, described the way real bugs are
   reported: by a person, in a sentence, with no line numbers.
2. **One extension.** A small feature the current owner asked for.

The assessed skill is not the change. It is that **everything that
worked before still works afterwards**, and that you can prove it.

## The bug report you are handed

```text
From: the music room
Every Monday the notices print fine. This Monday it stopped
partway through and showed a wall of red text. Nothing printed
for anyone after the cello. Nothing has changed at our end.
```

Here is the wall of red text:

```text
Traceback (most recent call last):
  File "/loans/signout.py", line 23, in <module>
    main()
    ~~~~^^
  File "/loans/signout.py", line 19, in main
    loans = load_loans("loans.csv")
  File "/loans/signout.py", line 14, in load_loans
    loans.append(Loan(item, borrower, int(days)))
                                      ~~~^^^^^^
ValueError: invalid literal for int() with base 10: ''
```

Read it from the bottom up. The last line is what went wrong; the lines
above it are how the program got there. Notice what it tells you and
what it does not: it names a file, a line, and a value that could not
be converted — and it says nothing at all about *why* a row of the data
file has an empty days field, or what the program should do about it.
That decision is yours, and it is a design decision, not a syntax
fix. [[Reading a Traceback in Someone Else's Code]] is the method.

## The order of work

Do not skip step three. Every team wants to.

1. **Run it** on ordinary input, then on strange input. Write down what
   it does, in three sentences, before you have an opinion about it.
2. **Find the entry point**, name the nouns, and follow exactly one
   path end to end. Ignore everything else on purpose. The method is
   [[Reading Somebody Else's Code]].
3. **Characterise it with tests, before you change a line.** Write
   tests that capture what the program currently does correctly — not
   what you think it should do. These are the tests that will tell you,
   tomorrow, whether your fix broke something quiet. See
   [[Writing Tests]] and [[Testing and Regression]].
4. **Reproduce the bug** with a test that fails. Only now do you know
   what you are fixing.
5. **Fix it**, in the smallest change that makes the failing test pass
   and leaves the characterisation tests green.
6. **Add the extension**, on its own branch, with its own tests.
7. **Leave a note.** Whatever you worked out about this program that
   was not written down anywhere — write it down. A comment, a line in
   the README, an entry in the journal. You are the only people who
   will ever have that understanding for free.

## Read charitably

You will find code you would not have written. Before you rewrite it,
assume the author had a reason you have not discovered yet: a
constraint, a bug they were working around, a partner who insisted.
Ask what would break if you removed it. Sometimes the answer is
"nothing", and you have improved the program. Sometimes the answer
arrives three weeks later at the worst possible moment.

You are not marked on how much of this program you replaced. You are
marked on how little you had to.

## What you hand in

1. **The changed program**, with your two changes and nothing else.
2. **Your characterisation tests**, written before the changes.
3. **The failing test that reproduced the bug**, now passing.
4. **A change log**, half a page, **written by each of you
   separately**: what the bug actually was, what you changed, why you
   chose that fix over the alternatives, and what you deliberately did
   not touch. The program is the team's; this is the piece that is
   yours, and it is read under your own name.
5. **The note you left** for the next team, quoted in your submission.

## Milestones

- [ ] **Unit 4, Day 2 — it runs on your machines**, and every member
      can say in one sentence what the program does.
- [ ] **Unit 4, Day 2, in the sprint period — characterisation tests
      written**, and the bug reproduced by a failing test.
- [ ] **Unit 4, Day 3, last twenty minutes — submitted.** Fix,
      extension, tests green, a change log from each of you, and the
      note. The finishing happens here, in class, not the night
      before.

## How this is assessed

Per [[How Marks Work]], the reading is assessed as heavily as the
writing. A team that fixes the bug by rewriting half the file has
demonstrated less than a team that fixed it in four lines and can
explain the four lines they did not touch.

Your [[Code Journal]] wants the honest entry: the moment you understood
what the original author was doing, and how long it took. Compare that
number with how long the author would have needed. That difference is
the real subject of [[Who Maintains This]], and it is about to be true
of your own project.

## Success criteria

| Quality | What it looks like in your submission |
| --- | --- |
| Read before changed | Three-sentence description, written before edits |
| Characterised first | Tests capturing existing behaviour, dated earlier |
| Bug reproduced | A test that failed, then passed, unchanged otherwise |
| Smallest sufficient fix | Change log defends what you did not touch |
| Nothing quiet broken | All characterisation tests still green |
| Extension isolated | Own branch, own tests, honest scope |
| A note left behind | Something the next team gets for free |
| Yours, under your name | Your own commits, and your own change log |

## Reflect

In your journal: what did this program's author know that they never
wrote down, and how did you find it out? Then turn it around — name one
thing about *your* team's project that only one of you currently knows,
and put a date on when it gets written down.

> [!question]- If the program is genuinely awful
> Some of them are. Inheriting a badly written program is not a
> punishment and it is not a trap: it is the ordinary condition of
> professional work, and the skill of staying useful inside it is worth
> more than any amount of writing greenfield code. Two rules keep you
> sane. **Do not rewrite what you have not tested** — a rewrite with no
> characterisation tests is a new program wearing the old one's name,
> and its bugs are now yours. **Write the change log as you go**, not
> at the end; the reasoning that makes your fix defensible is obvious
> to you at 2pm and gone by 4pm. If you truly cannot make progress by
> the end of the launch class, come to me and we will read the entry
> point together.

%%curriculum-start%%
## Curriculum connection

![[A2.3]]

![[A4.1]]

![[A4.2]]

![[B1.2]]

![[B1.3]]

![[B2.2]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

OBSERVE — Unit 4, Day 2, the sprint period, once a team has the bug
reproduced and is deciding what to do about the empty field
  Watch for: whether anybody opens the data itself before proposing a
  fix. The program is falling over on one blank value, and what the
  program ought to do about it — skip the row, treat it as zero,
  refuse the file, print the line number and carry on — depends
  entirely on whether that is one damaged row or a hundred rows
  written by somebody who had no value to give. The change log will
  defend whichever choice they made, so read this as corroborating
  that row rather than as a substitute for it: what the log cannot
  show you is whether the decision came before the typing.
  Going well: the data file is open and somebody is counting.
  Stuck: the first edit of the period wraps the line in a try/except,
  chosen because it makes the red text stop.
  Record: two columns on the day plan, one row per team — decided then
  typed, typed then justified.
  That is A2.3, changing existing modular code to enhance it, caught
  while it is still a design choice rather than an escape from an
  error message.

TALK — Unit 4, Day 3, during the twenty minutes at the end when teams
are finishing and handing in
  You are circulating anyway, and by then the tests are green, which
  is the moment this question is worth asking.
  Ask: "Which of your characterisation tests would have caught your
  own fix, if the fix had been wrong?"
  Then: "The original authors wrote no tests at all. If they had
  written exactly one, which one should it have been?"
  A strong answer names a particular test of their own and a
  particular behaviour of the inherited program that was worth
  protecting. A weak one says the tests cover everything. That is A4.2
  — testing to ensure program correctness — heard rather than counted:
  a green run proves the tests pass, and proves nothing whatever about
  what they reach.
  Record: one line per team, and the initials of whoever answered,
  because on a four-person team that is the finding.

The product evidence is the changed program, the tests, and the
separate change logs handed in on Day 3.
%%
