---
title: The Gadget
publish: true
created: __CREATED__
tags:
  - tasks
enableToc: true
---
> [!abstract] At a glance
> Groups of two or three · launched Unit 3, Day 15 · five bench periods
> on Days 18 to 22 · demonstrations on Day 23 · one working gadget, one
> service package

## What you are making

A small breadboarded device that code controls: a door alarm, an
indicator, a reaction-time game buzzer — your group chooses, and your
own idea is welcome if you can pitch it in one sentence.
[[Breadboard a Circuit]] gave you the hardware hands,
[[Control Something with Code]] the software ones; now, as
[[Code Meets Hardware]] promised, they build something together.

The gadget ships with a service package: the circuit diagram, code
with comments a stranger could follow, and a **demonstrated failure
mode** — on demo day you show it working, show one way it fails or
once failed, and walk the room through how you traced the fault.

## How to work

1. Write the gadget's one-sentence job: what it senses or accepts,
   and what it does. A working buzzer beats an ambitious pile of wires.
2. Diagram the circuit before building it. Predict what each part
   will do, [[Predict the Circuit]]-style, and let
   [[Electronics Fundamentals]] check the arithmetic first.
3. Build on the breadboard, [[Anti-Static Habits]] on, measuring as
   you go — a reading taken now is a diagnosis saved later.
4. Write the code in passes: make the simplest thing happen, then add
   the decisions and repetition the gadget needs. Comment as you go.
5. Trace the whole chain — code to interface to circuit to output —
   until you can narrate every link. When it misbehaves, and it will,
   [[Debugging Basics]] and [[Getting Unstuck]] are the way through.
6. Log every fault you chase — **each of you keeps your own log**,
   dated, saying what you tried and what the gadget did — then rehearse
   the demo: working run, failure mode, diagnosis story, service
   package on the bench.

Powered circuits mean the [[Safety in the Lab]] absolutes apply every
period, partner within arm's reach, and a strap on the mat before an
integrated circuit is touched. Every bench period is class time on
purpose: work that carries a mark gets done here, where I can watch it
happen and you can ask. On Day 20 I read each group's circuit and
code-so-far against the criteria table below and leave one written
note; Day 21 opens with fifteen minutes for acting on it.

## Your own mark

Two or three of you build one gadget, and you are marked one at a
time. What is yours alone:

- **Your fault log**, in your own words, kept as you work.
- **The chain, narrated by you.** Any member may be asked to trace
  code to interface to circuit to output — that row of the table is
  answered by whoever I ask, not by whoever knows it best.
- **Your own journal entry**, written at the bench before tools away.

## Success criteria

| Quality | What it looks like at your bench |
| --- | --- |
| A gadget that works | The one-sentence job is done, repeatably, on demand |
| A diagram that matches | The circuit on paper is the circuit on the board |
| Readable code | Comments let a stranger follow every decision and loop |
| A traced system | Any member can narrate code to circuit to output |
| An earned diagnosis | The failure is shown; its cause found, not guessed |
| Safe electrical habits | Strap on the mat before an IC is handled; power off at the rail before a wire moves |
| Your own fault log | Dated entries in your words: what you tried, what it did |

## Reflect

Your [[Tech Journal]] entry, written at the bench before tools away,
is the fault log turned into a story:
which failure taught your group the most, and what does the gadget do
now because of it? [[What a Strong Entry Looks Like]] shows the way.

> [!success]- If nothing is failing yet (click to expand)
> Lucky you — so break it on purpose. Pull one wire, swap one value,
> and predict what will happen before you look. A failure you caused
> and explained counts fully; technicians call it testing.

%%curriculum-start%%
## Curriculum connection

![[B2.1]]

![[B2.3]]

![[B2.4]]

![[B5.4]]

![[A3.3]]

![[D1.1]]

![[B2.2]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

Two or three to a gadget, so ask each member on their own — a group
answer tells you which of them is confident, not which of them knows.

OBSERVE — Unit 3, Day 21, the build-wire-test workday
  Watch for: which HALF of the chain a group suspects first when the
  gadget misbehaves. Hardware or software — does somebody check that
  the pin actually has voltage, or does the loop get rewritten three
  times before anything is measured? The finished gadget and its
  service package look identical whichever route got there, and the
  fault log records the fault that was found, not the ones that were
  looked for in the wrong place.
  Going well: a meter comes out of the drawer before the editor opens.
  Stuck: three code edits in a row, meter untouched, and the group
  getting louder.
  Record: two columns in your day plan, bench numbers under "hardware
  first" and "software first".
  That is B2.4 in the doing: tracing a system means knowing which link
  to interrogate, and only the period shows you where the group's
  instinct goes first.

TALK — Unit 3, Day 22, while the fault documentation is being written
  Ask, of each member separately: "The bench beside you has the same
  circuit and only theirs behaves. What is different, and what single
  measurement would prove you right?"
  Then: "Your gadget does the job in its one sentence. Now name
  something it does that nobody ever told it to do."
  A strong answer names a specific link in the chain and a reading that
  would settle it, and on the second names a real side effect — the LED
  dimming while the buzzer runs, an input missed because the loop is
  waiting — and where in the chain it comes from. That is B2.4 again: a
  service package can carry a correct diagram while its author has
  never once looked at the system as a whole.
  Record: initials plus H or S in the margin of the fault log you are
  reading — whether they reasoned from hardware or from software.

The product evidence is the gadget, the service package, and the
demonstration on Day 23. Those arrive on their own.
%%
