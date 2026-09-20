---
title: The Logic Machine
publish: true
created: __CREATED__
tags:
  - tasks
enableToc: true
---
> [!abstract] At a glance
> Pairs · two design periods and two bench periods · a working gate
> circuit, its truth table, its simplified expression, and a test log ·
> demonstrated at the end of Unit 2

## What you are making

A circuit built from logic gates that does one job requiring it to
*remember* something. A two-floor lift indicator that holds the last
floor called. A three-judge vote that latches the result until reset. A
door that stays unlocked once the right combination is entered. A machine
that will not start until two separate people have each pressed a button.

Combinational logic decides; sequential logic remembers. Your machine has
to do both, which means at least one latch, built from gates you can
point at — [[Sequential Logic and Memory]] is the reference, and
[[Gates on the Bench]] gave you the chips.

## Milestones

- [ ] **One sentence.** What the machine does, and what it remembers.
- [ ] **Truth table**, complete — every combination of inputs, no gaps,
      including the ones you think cannot happen.
- [ ] **Boolean expression** derived from the table, then **simplified**
      with the working shown, per [[Boolean Algebra]].
- [ ] **Gate count, before and after** simplification. The saving is
      part of the deliverable.
- [ ] **Schematic** with chips, pin numbers, and decoupling capacitors
      drawn — not implied.
- [ ] **Built and tested**, every row of the table, in
      [[Build the Logic Machine]].
- [ ] **Test log** listing every fault found, the hypothesis you formed,
      and the test that confirmed it.

## How it is assessed

Assessment follows the criteria below and the framework in
[[How Marks Work]]. The design periods count as much as the bench
periods: a machine that was simplified on paper before it was wired uses
fewer chips, fails in fewer places, and finishes earlier, and that is not
a coincidence. Your [[Tech Journal]] carries the reasoning.

The machine is built by a pair; the mark is not. Yours comes from your
own algebra — the derivation and the simplification, in your own
handwriting, with the gate count you arrived at — your own share of the
test log, and the conference where you account for a row. Two people can
hand in one machine and leave with two different marks, and often do.

Partway through you will stop and judge your own work against the table
below, before it goes anywhere near a mark: [[Judging Your Own Work]]
sets out how, and the point of doing it early is that there is still a
period left to act on what you find.

## Success criteria

| Quality | What it looks like at your bench |
| --- | --- |
| A machine that remembers | The stored state survives the input going away |
| A complete truth table | Every input combination present, including the awkward ones |
| Simplification that paid | Gate count before and after, with the algebra shown |
| A schematic that matches | Pin numbers, supply pins, and decoupling all drawn and all present |
| Tested, not demonstrated | Every row checked and recorded, not the four that work |
| Faults chased, not guessed | Each fault has a hypothesis and the test that confirmed it |
| Careful handling | Strap on, orientation checked, power off before rewiring |

## Reflect

In your [[Tech Journal]]: your machine has a state it can be in at
power-up that your truth table never described. Find it, describe it, and
say what you would add to make the machine start in a known state every
time. Real products get this wrong regularly, and users experience it as
"you have to unplug it and plug it back in".

> [!warning]- If your simplified circuit behaves differently from the original
> Then one of the two is not what you think it is. Do not adjust wires
> until it agrees — go back to the truth table and evaluate both
> expressions row by row on paper. Either the algebra has a slip in it,
> or the circuit does not match the expression you believe you built.
> Both are found faster on paper than at the bench.

%%curriculum-start%%
## Curriculum connection

![[A5.3]]

![[B3.1]]

![[B3.2]]

![[B3.3]]

![[A5.1]]

![[A5.2]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

OBSERVE — Unit 2, Day 13, the build-and-test period
  Watch for: what moves first when a row of the table fails — the logic
  probe, or a wire. The test log will tell you about the faults the pair
  recognised as faults; only the period tells you about the ones they
  rewired past without ever forming a hypothesis, and those are the ones
  that matter, because that pair will meet the same fault again in Unit
  3 with no method to bring to it.
  Going well: a probe lands on an intermediate node before anything is
  unplugged, and one of them says out loud which half they are ruling
  out.
  Stuck: wires come out in handfuls and go back differently, and the
  table is retested from row one each time with nothing written down.
  Record: bench list on your day plan, one letter each — P for probe
  first, W for wire first. That letter is B3.2 in five seconds.

TALK — Unit 2, Day 11, the conference already on that agenda
  Ask: "Point at a row where your output is 1. In gates, what has to be
  true for that row to come out that way?"
  Then: "Write that row as an expression, right now, on the corner of
  the page — and say which gate each term is."
  And: "Which row is only there because the machine remembers? Cover it
  up — is what is left still your machine?"
  A strong answer travels between all three of A5.3's representations
  without redrawing anything: the table it is looking at, the expression
  it can write on demand, and the gates each term becomes. That is the
  whole of the expectation rather than a truth table being read aloud,
  and a machine that works tells you nothing about whether its builder
  can make that trip or copied a wiring diagram that happened to be
  right.
  Record: one line per pair; note whether they answered from the table
  in front of them or had to rebuild it on paper first.

The product evidence is the built machine, its schematic, its simplified
expression and its test log, handed in on Day 14.
%%
