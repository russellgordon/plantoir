---
title: The Efficiency Case
publish: true
created: __CREATED__
tags:
  - tasks
enableToc: true
---
> [!abstract] At a glance
> Pairs · launched Unit 2, Day 16 and due Unit 2, Day 19 · three
> working periods · one slow program made fast, measured properly, and
> argued as an environmental case rather than a technical one

## What you are making

Take a program that is genuinely slow — one of yours, one from
[[The Inherited Program]], or one I supply — and make it substantially
faster. Then write the case for the change in the terms a decision-maker
would use: time, cost, energy, and what it means at scale.

Three deliverables: the **improved program**, a **measurement table**,
and a **two-page case**.

## Working in a pair

You optimise together, because two people reading the same timing
output is how this work is actually done. What is evaluated separately
is the argument: **each of you writes your own two-page case**, from
the pair's shared measurements, and hands it in under your own name.
The program and the table are joint. The reasoning about what the
saving is worth, and what you would still be wrong about, is yours —
and it is the half of this task that carries the most weight.

## What must be in it

**1. The baseline, measured.** Time the original on inputs of several
sizes — not one. [[Profiling and Timing Code]] is the method; a single
timing on one input is an anecdote, and the shape of the growth is the
whole point.

**2. The bottleneck, identified before it is fixed.** Say which part
dominated and how you know. Guessing and then improving something is not
a case; it is a coincidence.

**3. The change, and its complexity.** State the before and after in
Big-O and say what you traded — memory for speed, precision for speed,
generality for speed. There is always a trade.

**4. The measurement table**, with the same inputs on both versions:

| Input size | Before (s) | After (s) | Ratio |
| --- | --- | --- | --- |
| 1 000 | | | |
| 10 000 | | | |
| 100 000 | | | |

**5. Correctness, proven.** A faster wrong answer is worthless. Show the
tests that pass on both versions, including the boundary cases — and
watch for the arithmetic traps in [[How Numbers Actually Fit]], because
"optimising" a sum into floats is a classic way to get fast and wrong at
the same time.

**6. The environmental argument.** Scale your measurement: if this ran
ten thousand times a day on a server, what does the saving amount to in
energy over a year, and what would you compare it with? Be honest about
the uncertainty in that estimate — an order of magnitude, defensible, is
worth more than a precise-looking number you cannot justify.

**7. What else you would change**, beyond the code: batching, caching,
scheduling, supporting older devices, and where equipment goes at end of
life. [[Computing's Footprint]] names the Ontario programs and
agencies to cite, and expects you to verify them rather than trust the
page.

## The working periods

| Day | What it is for |
| --- | --- |
| Unit 2, Day 16 | Baseline measured across input sizes; bottleneck identified |
| Unit 2, Day 17 | The rewrite, with tests passing on both versions. In the last ten minutes you bring me both measurement tables and I mark one thing to change |
| Unit 2, Day 18 | The marked change first; then the scaling, and the case drafted and challenged by another pair |

## How this is assessed

| Quality | What it looks like |
| --- | --- |
| Measured, not guessed | Several input sizes, before and after |
| Bottleneck found first | The evidence precedes the fix |
| Complexity stated | Before and after, with the trade named |
| Still correct | Tests pass on both, boundaries included |
| Scaled honestly | An estimate with its uncertainty admitted |
| Beyond the code | At least one non-code measure, correctly sourced |
| Your own case | Written by you, from the pair's shared measurements |

## Reflect

A [[Code Journal]] entry: what did you assume was slow before you
measured, and what actually was? Then: does the environmental argument
change how you would write the next program, or is it a story told after
the fact?

%%curriculum-start%%
## Curriculum connection

![[D1.1]]

![[D1.2]]

![[A1.4]]

![[A1.2]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

OBSERVE — Unit 2, Day 18, the working period, at the point where a
pair leaves the code and starts on what else they would change
  Watch for: where the non-code measures come from. Some pairs look
  up — at these machines, this printer, the way this room is left at
  four o'clock — and ask whether the thing they have named could be
  checked. Others write down a list that could have been produced in
  the first week, before any of the measuring. The case will carry a list
  of measures either way, and the criteria row asking for one that is
  correctly sourced is satisfied by both, so read this as corroborating
  that row: what it adds is whether the measure was found or recalled.
  Going well: somebody names a particular machine, room or habit and
  asks how you would find out the number.
  Stuck: reduce, reuse, recycle, written inside a minute, and straight
  back to the graph.
  Record: two columns on the day plan — from this building, from
  memory. Initials only.
  That is D1.1, outlining strategies to reduce the impact of computers
  on the environment and on human health, watched at the moment a
  strategy is either grounded in something observed or is not.

TALK — Unit 2, Day 17, at the ten-minute table check that ends the
period
  You have both tables in front of you, so the arithmetic is already
  the subject and you do not have to open with it. The day has raised
  precision in general terms twice already, in the warm-up and in the
  lesson, which is exactly why this asks about their own two programs
  rather than about the idea.
  Ask: "Where do your two versions disagree, even slightly? If they
  never do, what would have to change about the input to make them?"
  Then: "Which of the two would you trust with money, and why that
  one?"
  A strong answer names a place where precision or rounding could
  separate them and can say which way the error would fall. That is
  A1.4 — the limits of finite data representations, met while an
  algorithm is being designed rather than described afterwards — and
  it is the one thing the pair's evidence cannot show you: a table of
  tests that pass on both versions looks the same whether the pair
  understood why they pass or never asked. Put the question to
  whichever partner has said less and let the other add afterwards;
  the case is written individually, so the note has to be individual
  too.
  Record: one line each, on the same sheet as the marked change.

The product evidence is the improved program, the table, and two
separately written cases handed in on Day 19.
%%
