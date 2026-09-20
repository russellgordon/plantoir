---
title: Computational Thinking
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
You met this before any computer did — the day you programmed a
classmate to make a sandwich in [[The Sandwich Robot]] and watched your
"obvious" instructions produce chaos. Computational thinking is the
craft of thinking so clearly that even a machine — which brings no
common sense whatsoever — can follow you. It has four moves.

## Decomposition

Break the big problem into small ones. "Make a quiz program" is
paralysing; "ask a question, read an answer, check it, keep score,
repeat" is five little problems, each solvable in an afternoon. When a
task feels impossible, the task is almost never the problem — the size
of the bite is.

## Pattern recognition

Notice what repeats. If checking answer 1 looks exactly like checking
answer 2, that is not a coincidence — it is a
[[Loops|loop]] waiting to be written, or a
[[Subprograms and Modules|subprogram]] waiting to be named. Programmers
are professionally lazy: they refuse to write the same thing twice.

## Abstraction

Ignore what does not matter *right now*. A map of the school leaves out
the bricks; your quiz program's plan does not care what colour the
screen is. Choosing what to leave out is a skill — leave out too much
and the plan is useless, too little and you drown.

## Algorithms

Write the steps so precisely that no judgement is needed to follow
them. That is all an algorithm is —
[[Algorithms in Everyday Life|you have followed hundreds this week]] —
and precision is the whole game:

> [!success]- The sandwich test (click to expand)
> "Put the peanut butter on the bread" — with the jar closed and the
> knife still in the drawer, a literal-minded robot puts the *jar* on
> the bread. If your instructions survive the most literal reading
> possible, they are ready to become code.

The four moves show up in everything this course does: planning
[[The Quiz Machine]], reading a
[[Programs/index|working program]] someone else wrote, even deciding
[[Which One Doesn't Belong]] in a warm-up. When you are stuck on
anything — code or otherwise — the first question is always the same:
*which of the four moves am I missing?*

## Designing for diverse users and contexts

Computational thinking is not an abstract puzzle — it exists to create
useful computational artifacts for real people. When decomposing a problem
and planning an artifact (as in [[The Quiz Machine]],
[[The Remix Project]], or [[Launch Day]]), deliberate design choices ensure
the artifact supports diverse users:

- **Input flexibility and forgiveness** — anticipating varied spelling,
  casing, accents, and typing speeds rather than requiring rigid exactness.
- **Audience context** — considering whether the user is a child, a language
  learner, someone using screen magnification, or someone working on a slow
  connection.
- **Clear feedback** — providing descriptive, supportive output that explains
  what occurred rather than cryptic errors.

Designing an artifact that functions only for the person who built it is an
incomplete solution. True computational design considers the user at every
step of decomposition and algorithm design.

%%curriculum-start%%
## Curriculum connection

![[A1.1]]

![[A1.2]]

![[A1.3]]
%%curriculum-end%%
