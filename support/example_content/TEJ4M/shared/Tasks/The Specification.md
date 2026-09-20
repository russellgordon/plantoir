---
title: The Specification
publish: true
created: __CREATED__
tags:
  - tasks
enableToc: true
---
> [!abstract] At a glance
> Individually · launched in Unit 1 and due at the end of it · a written
> specification for a device you do **not** build · assessed on whether
> somebody else could build it and prove it works

## What you are making

A document. That is the whole task, and it is deliberately
uncomfortable: for two years the evidence of your learning has been
something on a bench, and this time it is six or seven pages that
somebody else could build from without asking you a single question.

Choose a small device — a bench tool, a monitor for something in your
house, a fix for an annoyance in this shop. Then write the specification
a manufacturer would need: what it must do, the conditions it must do it
in, the interfaces it presents to the world, the components you have
selected and why, and the acceptance tests that decide whether a built
unit passes or fails.

The rule that makes this hard: **every requirement must be testable**.
"Reliable" is not a requirement. "Operates continuously for
$72\ \text{h}$ at $40\ ^\circ\text{C}$ ambient without exceeding
$70\ ^\circ\text{C}$ on any component surface" is a requirement, and you
can already see how it would be checked.

## Milestones

- [ ] **The sentence.** One sentence naming what the device does and
      for whom. Written first, changed as often as you like, never
      skipped.
- [ ] **Block diagram**, with every arrow labelled by what travels
      along it — volts, bits, or watts.
- [ ] **Requirements list**, numbered, every entry testable, split into
      what the device must do and the conditions it must survive.
- [ ] **Interfaces**, stated precisely: supply voltage and current
      range, connector, signal levels, protocol, and what happens when
      each one is connected wrongly.
- [ ] **Component selection** for at least four parts, each with a real
      part number, a datasheet reference, and — for every part that
      carries current — the calculation that sized it, plus the
      tolerance figure wherever a tolerance is what decided it.
- [ ] **Power budget**, as a table: every block, its current, and the
      total with margin stated.
- [ ] **Acceptance tests** — a numbered procedure another person could
      run with our bench equipment, each with a pass criterion in
      numbers.
- [ ] **Peer build check**: another bench runs your acceptance tests
      exactly as written and reports, in writing, what they could not
      do. You say nothing while they work — every question you answer
      out loud is one your document failed to answer, and the point of
      the exercise is to find out how many there are.

## How it is assessed

The criteria table below, weighted as [[How Marks Work]] sets out. Two
things worth saying plainly.

First, this is assessed as growth, not as a first attempt. The version
that counts is the one after your peer check, and the evidence of your
thinking between those two versions belongs in your [[Tech Journal]] —
what somebody could not do with your document, what you had assumed, and
what you rewrote. A specification that improved for stated reasons
outscores one that was tidy from the beginning.

Second, false precision costs you marks. A number you cannot source is
worse than an honest range: if a datasheet gives a figure, cite it; if
your figure came from a calculation, show it; if you are estimating,
label the estimate and say what you would measure to replace it. That
habit is the whole of [[Reading a Datasheet Like an Engineer]].

## Success criteria

| Quality | What it looks like in your document |
| --- | --- |
| One clear job | The opening sentence names a device, a person, and a difficulty |
| Testable requirements | Every requirement has a number, a unit, and a condition |
| Honest interfaces | Voltages, connectors, and protocols stated, including failure cases |
| Justified components | Real part numbers, with the calculation that sized each one and the tolerance where that decided it |
| A power budget that adds up | Every block accounted for, margin stated as a figure |
| Runnable acceptance tests | The test another bench ran went through as written, and what stopped them is written down |
| Sourced numbers | Datasheet figures cited, calculations shown, estimates labelled |
| Evidence of revision | The journal shows what changed after the peer check, and why |

> [!warning]- If you cannot decide what to specify
> Pick the smallest annoyance you have personally experienced this
> month, and specify the device that removes it. A cable that keeps
> falling off a bench, a plant nobody remembers to water, a door that
> gets left open. Small and real beats large and imagined every time,
> because a real annoyance comes with real conditions attached —
> temperature, duty cycle, who has to use it — and those conditions are
> most of what a specification is made of. If you are still stuck after
> ten minutes, that is a [[Getting Unstuck]] situation, and the
> procedure there applies to writing as much as to circuits.

%%curriculum-start%%
## Curriculum connection

![[A3.1]]

![[A3.3]]

![[A3.5]]

![[B2.1]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

OBSERVE — Unit 1, Day 16, while the benches trade documents
  The agenda already tells authors to stay quiet, so silence is not the
  thing to watch. Watch what they WRITE while silent. An author noting
  "clause 4.2 — they read it twice and then asked which supply" has
  located a defect; an author noting "they got confused" has recorded a
  mood and will change nothing on Day 17. The handed-in document shows
  the fixed version and cannot tell you which of those two notes
  produced it.
  Going well: a numbered list of clauses, growing, with the tester's
  actual words beside each.
  Stuck: nothing on the page, or one line at the end.
  Record: a tick against each name for clause-level notes, a dot for
  the rest. One pass of the room, and the dots are the students to
  stand beside on Day 17.

TALK — Unit 1, Day 15, at the feedback checkpoint already on that agenda
  Ask: "Read me requirement four. Now describe a device that meets
  every word of it and would still be useless to the person you wrote
  it for."
  Then: "Which of your chosen parts would you change first if the
  supplier discontinued it, and what else in the document moves when
  you do?"
  A strong first answer finds the loophole in their own wording and can
  say what clause would close it — A3.1 under load, terminology precise
  enough that a reader does not have to come and ask. A strong second
  answer reaches for the parameter that drove the choice — dropout,
  tolerance, package, temperature range — rather than for another part
  number, which is A3.5 asked backwards and much harder to fake than a
  citation.
  Record: one word beside each name — loophole, or none — and the
  parameter they named. Thirty seconds each.

The product evidence is the specification itself, handed in at the end
of Day 17. That one arrives on its own.
%%
