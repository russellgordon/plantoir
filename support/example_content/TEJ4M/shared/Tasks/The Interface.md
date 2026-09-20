---
title: The Interface
publish: true
created: __CREATED__
tags:
  - tasks
enableToc: true
---
> [!abstract] At a glance
> In pairs · launched in Unit 2, due at the end of it · a real
> peripheral, working, on a bus you designed · with scope evidence that
> the signals are healthy and not merely lucky

## What you are making

A microcontroller talking to a peripheral it was not sold with — a
sensor, a display, an expander, a converter — brought up from its
datasheet rather than from an example program somebody else wrote.

Getting it to answer is roughly half the task. The other half is
proving, with captured traces, that it will *keep* answering: correct
logic levels at both ends, rise times inside the specification, a clean
acknowledgement, and a signal that survives the wire length your device
would actually use.

You are not being assessed on picking a difficult peripheral. You are
being assessed on evidence.

## Milestones

- [ ] **Datasheet reading**, submitted before wiring: the supply range,
      the absolute maximum input voltage, the logic levels, the
      address or chip-select arrangement, and the timing diagram with
      the numbers you will need circled.
- [ ] **Interface plan**: a schematic of your connection, including
      pull-up values with the rise-time calculation behind them, and
      level translation if the two devices disagree about voltage.
- [ ] **First transaction**, captured on the logic analyzer, with every
      field labelled — address, direction, acknowledgement, data.
- [ ] **Working read or write**, in code kept in version control from
      the first commit, structured as
      [[Talking to a Peripheral]] describes.
- [ ] **Bytes turned into a quantity**, worked on paper before it is
      written into the code: one reading converted by hand from the
      datasheet's own format into a number with a unit, and then a
      second conversion of a value **below zero**, showing the two's
      complement arithmetic step by step. If your device cannot report
      a negative quantity, do the negative case on the worked example
      in [[Talking to a Peripheral]] instead — the arithmetic is the
      point, not the sensor. **Both partners do this one**; it is
      paper work and it costs nothing to do twice.
- [ ] **Signal integrity evidence**: scope captures of the rise time at
      your chosen pull-up value, at the shortest and longest wiring you
      tested, with the measurements marked on the traces.
- [ ] **Stress test**: the wire length, bus speed, or supply voltage at
      which it stops working, and the trace at the moment it fails.
- [ ] **Handover note**: one page telling the next person what is
      connected where, what the pull-ups are, and what not to change.

## How it is assessed

The criteria table, weighted as [[How Marks Work]] sets out. This task
rewards the pair whose evidence is complete over the pair whose device
is impressive. A working display with no traces scores below a working
sensor with four labelled captures and a documented breaking point.

Growth is assessed from your [[Tech Journal]]. The bring-up will not go
smoothly — nobody's does — and the journal is where the wrong
assumptions get recorded as they happen: the pin you had backwards, the
address you read from the wrong table, the pull-up you inherited from a
tutorial without checking. An entry written at the bench at the moment
of confusion is worth five written afterwards from memory.

Safety is part of the assessment, not beside it. Levels checked before
connection, supply limits set first, and no probing a powered board with
loose leads. That standard is in [[Safety in the Lab]] and it does not
relax because the voltages are small.

## What is marked as yours

You work in pairs and you share one bus, one scope and one set of
readings. The mark is still individual, so the evidence divides before
you start: **one of you owns the electrical side** — the level
comparison, the pull-up calculation, and the rise-time captures at each
value — and **the other owns the digital side**: the driver code and the
stress test. The byte conversion is the exception and belongs to both
of you, for the reason the milestone gives. Say at
launch which of you has which, and write it at the top of the handover
note.

Each of you captions your own captures in your own words, writes your
own half of the handover note under your own name, and answers for the
whole build — not just your half — at the conference on the second day.
Neither of you receives a mark for the other's half, and neither of you
is excused from understanding it.

## Success criteria

| Quality | What it looks like at your bench |
| --- | --- |
| Read from the source | The datasheet, not a tutorial, decides every connection |
| Levels verified before power | Both devices' limits written down and compared |
| Calculated pull-ups | The value follows from a rise-time calculation you can show |
| Labelled captures | Address, direction, acknowledgement, and data all identified |
| A documented breaking point | You know where it fails, and you have the trace |
| Bytes become a quantity | Both conversions worked by hand, units included, with the two's complement arithmetic shown for the negative one |
| Code somebody could maintain | Named constants, one place for pin numbers, in version control |
| An honest handover note | A stranger could rewire it correctly from your page alone |
| Your half, under your name | Your captures, captioned by you, and the section of the note that is yours |
| Recorded reasoning | The journal shows what you assumed and what corrected you |

> [!example]- What "scope evidence" actually means here
> Not a photograph of a screen with a squiggle on it. A capture with
> the timebase and voltage scale visible, the measurement cursors
> placed, and a caption in your own words: *"Clock line rise time,
> $30\%$ to $70\%$, $4.7\ \text{k}\Omega$ pull-ups, $300\ \text{mm}$ of
> ribbon cable: $0.9\ \mu\text{s}$, inside the $1\ \mu\text{s}$ limit
> with little to spare — which is why the final build uses
> $2.2\ \text{k}\Omega$."* One capture like that is worth a folder of
> screenshots, because it states a number, a condition, and a decision.

%%curriculum-start%%
## Curriculum connection

![[A2.4]]

![[A3.2]]

![[B1.3]]

![[B3.4]]

![[A5.1]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

OBSERVE — Unit 2, Day 13, while benches lengthen the ground lead
  Watch for: one variable at a time. A pair that adds ten centimetres,
  re-tests, and writes the length down has bracketed the boundary; a
  pair that swaps in the long cable and raises the bus speed together
  has found A failure and cannot say which change caused it. Both hand
  in a trace at the moment it broke, and the two traces look the same.
  Going well: a short list of lengths with a pass or fail beside each,
  growing while you watch.
  Stuck: two hands on two different variables, and nobody writing.
  Record: bracketed or jumped, one letter per pair on the class list.

TALK — Unit 2, Day 14, while benches make the fix and write the
handover note
  The stress test happened yesterday, so both of these have an answer
  by now; on the Day 12 checkpoint they would not.
  Ask: "Your partner says this bus is healthy because it answers. Take
  the other side — using only what is in your own captures, what would
  worry a reviewer about it?"
  Then: "What would the trace look like if the device were there but
  not ready, rather than absent — and which of those two does your code
  handle today?"
  A strong first answer argues against its own evidence and finds a
  real weakness — a rise time with no margin, a capture taken at the
  shortest wiring only, an acknowledgement nobody checked — which is
  the half of B3.4 a working device hides completely. A strong second
  answer separates a refusal from a silence and knows which of the two
  the code is currently blind to, which is A2.4 held rather than
  recited.
  Record: two ticks or two dashes per student, in the margin of your day
  plan. A minute a pair, while they are working anyway.

The product evidence is the traces, the code and the handover note,
in at the end of Day 14. Those arrive on their own.
%%
