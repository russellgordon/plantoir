---
title: Writing Documentation Somebody Can Build From
publish: true
created: __CREATED__
tags:
  - tutorials
enableToc: true
---
Here is the standard every task in this course is marked against, and
it has never been "does it work". It is this: **could a competent
stranger, holding only your documentation and a budget, build it, test
it, repair it, and know what is wrong with it?**

A circuit that works and has no record is a one-off. A circuit with a
proper record is a design, and the difference is entirely paperwork.
That is not a school invention. Nobody buys a prototype; they buy the
ability to make more of them and to fix the ones already out there.

## The package

Nine parts. None of them is long, and every one of them is written *as
you go* — reconstructed at the end it takes an evening and it is wrong
in three places.

- [ ] **The specification.** What it must do, as requirements with
      numbers and acceptance criteria. A requirement nobody can test is
      not a requirement — see [[Writing a Specification]].
- [ ] **A block diagram.** The system's shape on one page, before any
      component appears.
- [ ] **The schematic.** Drawn, not photographed. Every component with
      a reference designator and a value, every rail named, ground
      shown, a title block with a revision.
- [ ] **The bill of materials.** Every part, with enough detail that
      somebody could order it again without asking you a question.
- [ ] **Assembly notes.** What is polarised, what orientation, what
      wire gauge, what must be fitted last, and photographs of anything
      that would be hard to reproduce from the schematic alone.
- [ ] **The firmware.** Source, the toolchain version it was built
      with, how to flash it, and the tag it came from — the discipline
      in [[Version Control for Firmware]].
- [ ] **A test procedure.** Numbered steps somebody else follows, with
      the expected readings and explicit pass and fail thresholds.
- [ ] **Design decisions.** Each significant choice, the alternative
      rejected, the number that decided it, and the margin left.
- [ ] **Known issues and maintenance.** The honest list, plus what
      wears out, what to check, and how to take it apart safely.

## The bill of materials, at Grade 12

Last year's bill of materials answered "what parts?". This one has to
answer "what parts, and what happens when this one is unavailable?" —
because in a real project that is the question that arrives first.

| Ref | Qty | Description | Manufacturer part | Key rating | Alternate | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| R1 | 1 | Resistor, thick film, ±1 % | *exact part number* | 0.25 W, 0805 | Any ±1 % 0805 | Sets sense-amp gain; tolerance matters here |
| C1 | 1 | Capacitor, aluminium electrolytic | *exact part number* | 470 µF, 25 V, 105 °C | Higher voltage OK | Bulk on 12 V input; polarised |
| C2 | 1 | Capacitor, ceramic, X7R | *exact part number* | 10 µF, 25 V, 0805 | Do not substitute Y5V | See derating: value falls under DC bias |
| Q1 | 1 | N-channel MOSFET, logic level | *exact part number* | 30 V, 5 A, gate specified at 4.5 V | Must be logic level | Driven directly from a 3.3 V pin |
| D1 | 1 | Schottky diode | *exact part number* | 40 V, 2 A | — | Flyback across the motor; do not omit |
| U1 | 1 | Microcontroller board | *board name* | — | — | Pin assignments in the firmware README |

Three columns are new and each earns its place. **Key rating** is what
the part must be, as opposed to what you happened to buy — it is the
line somebody substituting a part has to satisfy. **Alternate** says
what may be swapped and what may not. **Notes** carries the reason,
which is the part that stops a future maintainer from "improving" your
design back into a fault.

Reference designators are not decoration. `R1` on the schematic, `R1`
in this table, and `R1` in the photograph mean three documents describe
the same physical object, and a fault report can name it without
pointing.

## The test procedure is the deliverable people forget

A test procedure written properly is worth more than the schematic,
because it is the only thing that proves the device works *now* rather
than on the day you finished it.

Write it as numbered imperative steps with expected values, in a form
somebody could follow without you:

> 1. With no load connected, set the supply to 12.0 V, current limit
>    300 mA. Output on.
> 2. Measure at TP1 (5 V rail). **Pass:** 4.90 V to 5.10 V.
> 3. Measure at TP2 (sensor supply). **Pass:** 3.25 V to 3.35 V.
> 4. Connect the load. Measure at TP1 again with the fan running.
>    **Pass:** not below 4.75 V at any point; use a scope, DC coupled,
>    20 ms per division, and watch for at least ten start cycles.
> 5. Command 30 % duty from the console. **Pass:** scope on TP3 shows
>    a 1.2 kHz to 1.3 kHz square wave, 28 % to 32 % duty.

Thresholds written before the test is run cannot be argued with
afterwards, which is the entire point. A pass criterion invented while
looking at the result is not a test; it is a description.

## Known issues, honestly

Every build has some. A list of them is a sign of a careful engineer,
not a careless one, and an empty list on a first version is not
believed by anybody who has ever built anything.

Write each as a symptom, a condition, a cause if you know it, and a
severity you are willing to defend:

> **Display flickers when the motor starts.** Reproducible on every
> start. Rail dips to 4.62 V for about 3 ms, measured at TP1 with the
> scope, DC coupled. Cause is inrush through the shared 12 V feed;
> confirmed by running the motor from a second supply, which removes
> the symptom entirely. Severity: cosmetic, but it is the same dip
> that would reset the controller if it went 200 mV further, so it is
> on the list to fix with a separate feed rather than a bigger
> capacitor.

That is useful. "Sometimes it glitches" is not, because nobody can act
on it. And there is a limit to what an honest note buys you —
[[When Good Enough Is Not Safe]] is where documenting a flaw stops
being sufficient and fixing it becomes the only acceptable answer.

## The stranger test

The exercise that finds every defect in your document, and it takes
fifteen minutes.

Hand your documentation to another bench. Watch them try to follow it.
**Say nothing.** Not one word, not even when they go wrong — especially
not then.

Every question they ask out loud is a defect in your document. Every
pause is an ambiguity. Every wrong turn is a step you knew and did not
write. Write them all down without defending anything, then fix the
document rather than explaining yourself. Then swap and do the same for
them.

That is exactly what a design review is, which is why
[[The Engineering Review]] will feel familiar rather than frightening
by the time you get there.

## Where it lives

Bench notes, sketches, and the reasons behind decisions go into your
[[Tech Journal]] as they happen — that is what the decision prompt is
for, and writing this document is much faster when the reasons are
already recorded. The tidy version is the deliverable attached to each
task, and it is where a large share of the criteria on every task page
are actually won — see [[How Marks Work]].

Write it in the language [[Writing About Technology]] describes:
specific, quantified, imperative in procedures, and addressed to the
next technician, who might very well be you.

%%curriculum-start%%
## Curriculum connection

![[D3.3]]

![[D3.4]]
%%curriculum-end%%
