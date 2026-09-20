---
title: The Engineering Design Project
publish: true
created: __CREATED__
tags:
  - tasks
enableToc: true
---
> [!abstract] At a glance
> Individually or in pairs · the final block of the course · a device
> nobody specified for you, designed, built, documented, and defended ·
> demonstrated at [[The Engineering Review]]

## What you are making

An original device that solves a problem you chose, built from the three
years of this shop: circuitry you calculated, an interface you brought
up from a datasheet, and embedded code somebody else could maintain.

Everything you built before this was a job handed to you. This one
starts with a problem you found and a proposal you had to defend, and it
ends with a handover package — because in this trade a device that only
its maker can service is not finished, it is a hostage.

Scope it honestly. A device that does one job dependably, measured,
documented, and defended, beats an ambitious pile of wires every time.
The proposal stage exists so that somebody can tell you that before you
spend three weeks finding out.

## Milestones

- [ ] **Proposal**, in writing, at launch: the problem in one sentence;
      who has it; a block diagram; a parts list with real part numbers
      and prices; the three things most likely to go wrong; and the
      test plan that will prove the device works.
- [ ] **Specification**, in the form you learned in Unit 1 — testable
      requirements, interfaces, a power budget, and acceptance tests.
      This is where [[The Specification]] stops being an exercise.
- [ ] **Design review**, at your bench, with your calculations and
      budget open. The questions come from the published list in
      [[The Engineering Review]]; none of them is a surprise.
- [ ] **Schematic and state diagram** before the first component is
      soldered, with derating figures marked on the parts that carry
      real current. The schematic is drawn in the schematic-capture
      tool on the bench machines rather than on paper — not for
      neatness, but because you will revise it four times and a
      stranger has to receive the version that matches the board.
- [ ] **Build log**, kept as you go and never written afterwards:
      dated, what you did, what failed, what you tried, what happened,
      and what you decided. Version control carries the firmware
      history, as [[Version Control for Firmware]] sets out.
- [ ] **Test plan executed**, with the data recorded — including the
      trials that failed and the measurements that disagreed with your
      predictions.
- [ ] **Handover package**: schematic matching the board, code a
      stranger could follow, the build log, the test results, and a
      plain statement of the known limitations.
- [ ] **Demonstration and defence** at [[The Engineering Review]].

## How it is assessed

The criteria table, weighted as [[How Marks Work]] sets out. Three
things are worth saying plainly.

First, the build log is assessed as work rather than as paperwork. An
engineer who cannot say what they did yesterday cannot be trusted with
tomorrow, and the log is the only honest record of the decisions you
made under time pressure.

Second, a device that does not fully work, whose log shows disciplined,
documented, well-reasoned engineering, scores well above a device that
works by accident. Cutting scope for a stated reason is engineering, and
it is assessed as engineering.

Third, this project is the main evidence in your [[Tech Journal]] for
the year. [[Showing Growth]] asks you to set it beside your first entry
from Unit 1, and [[Final Reflection]] asks what specifically you can now
do that you could not do at the start of the course.

Safety runs through every bench period: separate supplies for loads,
protection on anything inductive, current budgets checked before power,
derating figures on the parts that get warm, and the standing agreement
in [[Safety in the Lab]] applied without being asked. The discussion in
[[When Good Enough Is Not Safe]] is the question this task answers in
practice.

## What is marked as yours

Build alone and everything here is yours already. Build in a pair and
the mark is still individual, so say at the proposal which **block**
each of you owns — its circuitry, its firmware, and its test results —
and keep your own build log rather than a shared one. The handover
package names who built what, block by block, and at
[[The Engineering Review]] you each demonstrate and answer for your own
block. Shared credit for a shared build is not something this course
gives out, in either direction.

## Success criteria

| Quality | What it looks like at your bench |
| --- | --- |
| A problem worth solving | The one-sentence problem names a person and their difficulty |
| A defensible design | Block diagram, calculations, and power budget all agree |
| A schematic held in the capture tool | Drawn there before the build, kept in step as the board changed, and exported with the package |
| Margin chosen, not inherited | Derating figures marked, with the worst case named |
| Three strands combined | Analogue circuitry, an interface, and code, all yours |
| A log kept as it happened | Dated entries, failures included, written at the bench |
| A test plan executed | The measurements you promised, taken, including the bad ones |
| A handover a stranger could use | Schematic, code, log, results, and known limits |
| An honest account of limits | You can name what it does not do, and why |
| Professional safety practice | Supplies separated, loads protected, no reminders needed |
| Your block, under your name | Built in a pair: the block you own is named, logged and defended by you |

> [!warning]- If your scope is slipping and two periods remain
> Cut, and cut early. Decide today which single function *is* the
> device, and make that one work completely — measured, logged,
> documented, demonstrable. A finished half of an ambitious project is
> a project; an unfinished whole one is a story about what you meant to
> do. Write the cut and its reasoning into the build log, with the date
> and the state of things when you made it. Deciding what to abandon,
> on evidence and on time, is one of the harder professional skills in
> this trade, and we will assess it as such.

%%curriculum-start%%
## Curriculum connection

![[A3.3]]

![[A3.5]]

![[B3.1]]

![[B3.3]]

![[B5.3]]

![[B1.1]]

![[D1.1]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

OBSERVE — Unit 4, Day 23, the first build period, when parts start
being substituted
  Nothing on that agenda mentions the power budget, which is what makes
  it worth watching. A part comes out of the drawer at a different
  rating from the one on the list — does the budget come back up on the
  screen in the next few minutes, or not until the package is
  assembled? Either way the folder arrives with a schematic and a
  budget that agree, because making them agree is the last thing
  anybody does. Only the room shows you whether the budget was ever a
  design instrument or only a document.
  Going well: a substitution, then a calculator, then a changed total.
  Stuck: three substitutions and no window opened.
  Record: a tick beside anyone who reopened it without being asked.
  That list is short, and it is the honest evidence for A3.3 that the
  tidy final pair of documents cannot give you.

TALK — Unit 4, Day 26, while benches integrate and close review findings
  Ask: "Open your schematic. Show me one thing you changed after you
  first drew it, and tell me what made you change it."
  Then: "Name a standard this device would fail today if somebody
  inspected it, and tell me what meeting it would cost you — parts,
  periods, or scope."
  A strong first answer points at a revision driven by a calculation or
  a review finding rather than a tidy-up, which is the design-process
  half of B3.1 — the captured file shows the final state and carries no
  history into the handover. A strong second answer names something real
  — an enclosure, a fuse, isolation, a strain relief — names who the
  requirement protects, and prices it honestly rather than promising to
  add it. That is D1.1 as a decision with a cost, which is the only
  form in which anybody ever meets it after school.
  Record: one line per project, in your day plan, naming the revision
  and the standard. Two minutes each, spread across the period.

The product evidence is the device, the build log, the test data and
the handover package, demonstrated at the Engineering Review on Unit 4,
Day 32. Those arrive on their own.
%%
