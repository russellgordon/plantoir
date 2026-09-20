---
title: Documenting Your Build
publish: true
created: __CREATED__
tags:
  - tutorials
enableToc: true
---
Every task in this course opens its criteria table with a row about
whether the thing works, and every one of them then has a second row
that decides far more marks than the first: **could a competent
stranger, holding only your documentation, rebuild it, test it, and
repair it?**
A circuit that works and has no record is a one-off. A circuit with a
proper record is a design, and the difference is entirely paperwork.

This is not busywork invented by a school. It is the actual deliverable
in technical work. Nobody buys a prototype; they buy the ability to
make more of them and to fix the ones already out there.

## What a build record contains

Six things, none of them long.

- [ ] **A schematic** — drawn, not photographed. Every component
      labelled with a reference and a value, every supply rail named,
      ground shown.
- [ ] **A bill of materials** — every part, with enough detail to
      order it again.
- [ ] **Photographs of the actual build** — at least one overall, and
      close-ups of anything that would be hard to reproduce from the
      schematic alone.
- [ ] **Measured values** — what you predicted, what you measured, and
      under what conditions.
- [ ] **A test procedure** — the steps somebody else follows to
      confirm it works, with the readings they should get.
- [ ] **Known issues** — the honest list.

The order matters less than the completeness. Written at the bench as
you go, this takes minutes. Reconstructed afterwards, it takes an
evening and it is wrong in three places.

## The bill of materials

A bill of materials is the difference between "some resistors" and a
document somebody can hand to a supplier. Columns:

| Reference | Quantity | Description | Value or part number | Notes |
| --- | --- | --- | --- | --- |
| R1, R2 | 2 | Resistor, 1/4 W, ±5 % | 220 Ω | Sets LED current |
| C1 | 1 | Capacitor, electrolytic, 16 V | 470 µF | Polarised — check orientation |
| D1 | 1 | LED, red, 5 mm | — | Typical forward drop 2.0 V |
| U1 | 1 | Quad 2-input NAND, 14-pin DIP | 74HC00 | Pin 14 to supply, pin 7 to ground |

The references are not decoration. `R1` on the schematic, `R1` in the
table, and `R1` written on the board or in the photograph mean that
three documents describe the same physical object, and a fault report
can name it unambiguously. Without references, every conversation
about the circuit becomes pointing.

## The measurements that prove it

A build record without numbers is a claim without evidence. For each
important node or branch, record the value you expected, the value you
measured, and the conditions — supply voltage, what was running, where
the probes were. Where they disagree, say by how much and offer a
cause.

Two reasons this matters more than it seems. First, it is how anybody
including you can later tell whether the circuit still behaves as it
did when you signed it off. Second, the act of predicting and then
measuring is what catches the design error that a working prototype
cheerfully hides — plenty of circuits work while running a component
at twice its intended current, right up until the day they stop.

## Known issues, honestly

Every build has some. A list of them is a sign of a careful engineer,
not a careless one, and an empty list on a first version is not
believed by anybody who has built anything.

Write each one as a symptom, a condition, and what you know about the
cause:

> The display flickers when the motor starts. Reproducible every time.
> Probably a supply dip; not measured yet. Does not occur when the
> motor is powered from a separate supply.

That is useful. "Sometimes it glitches" is not, because nobody can
act on it. And there is a limit to what an honest note buys you — see
[[When Good Enough Is Not Safe]] for where documenting a flaw stops
being sufficient and fixing it becomes the only acceptable answer.

## Where it lives

Bench notes and sketches go in your [[Tech Journal]] as they happen.
The tidy version — schematic, bill of materials, photographs, test
procedure, known issues — is the deliverable attached to each task,
and every task's criteria table has a row that depends on it; see
[[How Marks Work]]. Write it in the language
[[Writing About Technology]] describes: specific, quantified, and
addressed to the next technician, who might well be you.

%%curriculum-start%%
## Curriculum connection

![[D3.4]]

![[B1.4]]
%%curriculum-end%%
