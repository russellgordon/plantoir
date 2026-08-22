---
title: Code Journal
publish: true
created: __CREATED__
tags:
  - portfolio
enableToc: true
---
> [!abstract] At a glance
> Individual · ongoing all course · one short entry after every class,
> kept for you · one milestone entry per unit, written in class, which
> is the entry read against the criteria

## What you are making

A developer's log of your course: one short entry after every class,
written the same day while the details are still warm. Ten honest
minutes beat thirty performed ones — and entries are **private**. I
read them; other students never do. That matters more this year than
last, because you are working in a team, and the journal has to stay
a place where you can write that you do not understand the module
your teammate finished on Tuesday.

## How entries work

Each entry answers four prompts, in whatever order helps:

- **What I built or changed** — the facts, briefly, and where they
  landed. A commit message is a good starting point; the entry is
  what the commit message could not hold.
- **What I decided, and what I turned down** — the design choice of
  the day and the alternatives you rejected. One sentence each is
  plenty.
- **What broke** — the specific failure in its own words. Paste the
  traceback. A stack captured on the day it happened is still the
  best artifact this journal collects.
- **What I would try next** — one concrete move for next class. Not
  "get better at recursion": something you could type.

## The three threads that make this Grade 12

Last year's journal followed one thread: you, and the person you were
building for. This year three run through it, and the entries that
matter most are the ones that touch them.

### Decisions, with their rejected alternatives

"Used a dictionary" is a fact. "Used a dictionary keyed by member ID
because we were doing a linear search through a list on every
sign-in, and the two other options were a sorted list with binary
search — rejected, we would have to re-sort on every insert — and
parallel lists, rejected because they can fall out of step" is a
decision. Six months from now, only the second one still has a
reason attached to it.

Write the rejected options down while they are still live. They are
the single hardest thing to reconstruct, and they are exactly what
[[The Structure Study]] and [[The Handover]] will ask you to defend.

### What a teammate's review changed

Every code review either changes something or it does not, and both
outcomes are worth an entry. What did someone else see in your code
that you could not? What did you see in theirs? And when you
disagreed, what actually settled it — evidence, a test, a timing
measurement, or someone getting tired?

> [!note] Reviews are about code; entries are about you
> Record what the review taught you, not what you thought of the
> reviewer. If an interaction on your team is genuinely a problem,
> that is a conversation to have with me directly, and
> [[Getting Help]] says how.

### What you learned from code you did not write

Every time you understand a piece of somebody else's program, write
down the thing that unlocked it — the experiment you ran, the line
you changed, the commit message that finally explained a mystery. You
will be doing this all year, in [[The Inherited Program]], in
[[The Maintenance Sprint]], and every day of a team build, and the
techniques transfer far better than the specific programs do.

## Success criteria and collection

The last period of each unit sets aside its final fifteen minutes for
a **milestone entry**, written here, in class: what this unit changed
about how you work, with the entries from the unit open beside you.
That milestone entry is what is read against the criteria below, and
it is what [[How Marks Work]] counts. Unit 4 is the exception, and
only in form: its milestone is the [[Final Reflection]], which is
longer, is begun in class on Unit 4, Day 19 and finished in class on
Day 21, and does the same job across the whole course rather than
across one unit. The daily entries between
classes are yours — they are the raw material the milestone entry is
made from, and practice you do at home is never something I mark.
[[Journal Checklist]] turns the criteria into a self-check.

| Quality | What it looks like |
| --- | --- |
| Grounded in the day | The moments cited were written down when they happened, not reconstructed afterwards |
| Honesty | Real breakage and real confusion recorded, not only wins |
| Precision | Bugs located and quoted; decisions stated with their alternatives |
| Contribution | What *I* did, in a form a reader could check against the history |
| Growth | "Try next" items reappearing as things actually tried |
| People | Evidence that you kept thinking about who has to live with this |

That fourth row does double duty. It is how you see your own
progress, and it is the individual evidence inside a team project
that [[How Marks Work]] relies on.

%%curriculum-start%%
## Curriculum connection

![[A4.1]]

![[B2.2]]

![[D4.4]]
%%curriculum-end%%
