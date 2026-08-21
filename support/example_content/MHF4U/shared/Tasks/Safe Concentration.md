---
title: Safe Concentration
publish: true
created: __CREATED__
tags:
  - tasks
enableToc: true
---
> [!abstract] At a glance
> Pairs, marked as individuals · launched with rational equations, due
> on the consolidation day · one dose curve, one window, both edges
> defended

## What you are making

Swallow a pill and the medication's concentration in the blood rises
fast, peaks, and drains away slowly. You will receive a data table
for a (fictional) medication — concentration in mg/L, hour by hour —
and the model family that pharmacologists actually reach for:

$$C(t) = \frac{at}{t^2 + b}$$

This medication only works above $0.4$ mg/L, and is only safe below
$1.2$ mg/L. You finish with the **fitted model**, a paragraph on why
no polynomial could do this job (what happens as $t$ grows?), and
the **safe-and-effective window**: the interval of hours where the
concentration is high enough to work and low enough to be safe —
each edge found exactly — plus your recommendation, in plain
language, for when the second dose should be taken.

You work in a pair and you are marked as an individual. Initial the
paragraphs you wrote, write your own milestone journal entry on the due
date, and answer for your own work at the conference — those three are
what carries your mark.

## Milestones

- [ ] Data plotted by hand; the rise-then-fall shape and the long-run
      fade described before any formula appears
- [ ] The family interrogated: intercepts and the horizontal
      asymptote of $C(t)$, argued with [[Asymptotes]] thinking
- [ ] Parameters $a$ and $b$ fitted in [[Using Desmos]]; the misfit
      measured and stated in mg/L
- [ ] Each threshold crossing solved exactly as a rational equation,
      then checked against the graph
- [ ] The window stated as an interval, defended with a sign argument
      and a test value from inside it, and turned into a dosing
      recommendation
- [ ] One sentence saying plainly what the two edges are: the answers
      to an equation, while the window itself is the answer to an
      inequality

## How it is assessed

Per [[How Marks Work]], the reasoning is the product: a window that
is slightly off, with the misfit measured and its effect on the
recommendation discussed, outranks perfect numbers with no argument.
On the due date your pair defends both edges of the window out loud.
Ten minutes of that class are set aside for your milestone journal entry
on what your model ignores — food, body mass, the second dose itself —
written in the room, and belonging to this task.

Run [[Judging Your Own Work]] against the table below on the write-up
day, while there is still time in the period to act on it.

## Success criteria

| Quality | What it looks like in your work |
| --- | --- |
| Shape before symbols | Rise, peak, and fade explained from the data |
| A family understood | Intercepts and asymptote argued, not assumed |
| A measured misfit | Model-versus-data disagreement stated in mg/L |
| Exact edges | Both threshold crossings solved algebraically |
| A humane answer | The window translated into advice about hours, for a named reader |
| Equation against inequality | The edges given as solutions, the window given as an interval, and the difference stated |
| An entry that names the gap | The milestone entry names what the model leaves out and which omission would change the advice |

> [!success]- If the fit will not settle
> Work one parameter at a time: $a$ scales the whole curve up and
> down, while $b$ decides how early the peak arrives. Fit the peak's
> timing first, then its height — and if the tail of your data still
> disagrees, say so in the write-up. That disagreement is evidence,
> not failure.

%%curriculum-start%%
## Curriculum connection

![[C2.1]]

![[C3.6]]

![[C4.1]]

![[C4.2]]

![[D3.3]]
%%curriculum-end%%

%%
Triangulation — the evidence that never arrives on its own.

Pairs. Day 10 carries the conference this task is built around; the questions
below are deliberately not the one printed on that agenda.

OBSERVE — Unit 2, Day 11, the write-up period

  Watch for whether a pair decides WHO they are writing for before they
  write. The write-up is meant for somebody who has to act on it, and the
  finished page reads as addressed to a reader either way — the criteria row
  about a humane answer is satisfied by the last paragraph, whenever it was
  written. What you cannot recover afterwards is whether the reader was
  chosen at the start and shaped the whole thing, or bolted on at the end.

  Going well: a sentence gets struck out mid-write, out loud, because "a
  nurse would not know what an asymptote is". A pair naming an actual reader
  — the patient, a parent, the person on the ward at three in the morning.

  Stuck: the write-up opens with "In this task we were asked to", and the
  word "milligrams" has not appeared yet.

  Record: a tick against each pair the moment you hear a reader named, and
  the reader's word beside it. Two ticks and no words is a pair to sit with.

TALK — Unit 2, Day 10, at the conference already on that agenda

  Ask: "Somebody follows your recommendation and it turns out to be wrong.
  Who is worse off — the person who takes the second dose too early, or the
  person who takes it too late? Which of those two mistakes is your
  recommendation built to avoid?"

  Then: "If your fitted curve is out by a tenth of a milligram per litre,
  which edge of your window moves further?"

  On the first, listen for two different kinds of harm rather than one word
  for both. Too early stacks a second dose on what is left of the first and
  pushes towards the ceiling, which is a safety failure; too late drops the
  patient under the effective threshold, which is a treatment failure. A
  strong answer names which edge of their own window governs which risk and
  says which way they chose to be wrong. That is D3.3 heard — results
  interpreted inside the situation — and a recommendation that reads
  confidently on paper can be given by a pair who have never once asked
  whose problem it becomes.

  On the second, the strong answer is a method, not a direction. How far an
  edge slides is the size of the misfit divided by how steeply the curve is
  climbing or falling where the threshold cuts it — so the edge sitting on
  the flatter stretch is the loose one, and on a curve that rises fast and
  fades slowly that will usually be the late edge. "Usually" is not the
  answer, though: the answer is that they can read both steepnesses off their
  own graph and compare them. That is C4.2 heard — an interval taken off a
  graph with its reliability attached — and a page stating the window to two
  decimals tells you nothing about whether its authors believe the decimals.

  Record: one line per student on your class list.

The product evidence is the report defended on Day 13 and the milestone entry
written in class that day.
%%
