---
title: Logic Gates
publish: true
created: __CREATED__
tags:
  - concepts
---
In [[Gates on the Bench]] you did not look up a truth table — you built
one. Two switches, a chip, an LED, and a meter, and you filled in four
rows by measuring the output for every combination of inputs. That table
came out of the hardware. Everything on this page is bookkeeping for what
the hardware already told you.

## The six gates, completely described

A logic gate looks at its inputs, each of which is a voltage the chip
reads as either 0 or 1, and drives its output by a fixed rule. Two inputs
means four possible input combinations, so four rows says everything
there is to say.

| A | B | AND | OR | NAND | NOR | XOR |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | 0 | 0 | 0 | 1 | 1 | 0 |
| 0 | 1 | 0 | 1 | 1 | 0 | 1 |
| 1 | 0 | 0 | 1 | 1 | 0 | 1 |
| 1 | 1 | 1 | 1 | 0 | 0 | 0 |

NOT takes one input and flips it: 0 becomes 1, 1 becomes 0.

Read the columns as sentences rather than memorising them. AND is "both".
OR is "at least one". XOR is "exactly one of two" — a difference
detector, true when the inputs disagree. NAND and NOR are AND and OR with
a NOT bolted on the output, which is why their columns are the AND and OR
columns upside down. On a schematic that inversion is drawn as a small
bubble on the output, and the bubble is the only difference between the
AND symbol and the NAND symbol.

In algebra the same six are written $Y = A \cdot B$ for AND,
$Y = A + B$ for OR, $Y = \overline{A}$ for NOT, and the inverted pair get
a bar over the whole expression: $Y = \overline{A \cdot B}$ for NAND.
[[Boolean Algebra]] takes that notation somewhere useful.

> [!example] NAND can build anything
> Tie both inputs of a NAND together and feed them the same signal: the
> only rows that can happen are 0,0 and 1,1, so the output is 1 then 0 —
> you have made a NOT gate. Follow a NAND with one of those inverters and
> you have AND. Invert both *inputs* of a NAND instead and you have OR,
> which is De Morgan's law wearing a hardware costume. That is why NAND
> is called a universal gate, and why a chip with four NAND gates on it
> is the most useful thing in the drawer.

## What a 1 and a 0 physically are

A gate does not receive numbers. It receives a voltage, and it decides.
Every logic family publishes two thresholds: any input below the lower
one is guaranteed to be read as 0, any input above the upper one is
guaranteed to be read as 1, and the band between them is undefined
territory where the chip may do anything at all — including oscillate.

Two consequences you will meet at the bench within the hour:

- **A floating input is not a 0.** An unconnected input has no defined
  voltage and will happily pick up interference from your hand. Every
  unused input gets tied to the supply or to ground through a resistor.
  A circuit that behaves differently when you touch it has a floating
  input somewhere.
- **Families are not interchangeable.** Older TTL parts and modern CMOS
  parts have different thresholds and different appetites for input
  current, and a design that mixes them without checking is a design
  that works on the bench and fails in the case. The datasheet for the
  exact part is the authority — see [[Reading a Datasheet]].

## Testing a gate honestly

A logic probe reports high, low, or floating on one pin at a time, and it
is the fastest tool for the job. A multimeter tells you the actual
voltage, which is what you want when a signal is sitting stubbornly in
the middle band. An oscilloscope shows you what a static reading cannot:
a gate whose output is oscillating, or a signal that is briefly wrong
during the transition. [[Using an Oscilloscope]] is worth the setup time
the first time a circuit is "right" and still misbehaves.

The bench procedure that catches nearly everything:

1. Confirm supply and ground on the chip's power pins before testing any
   signal pin. A chip with no power reads as floating everywhere and
   looks like a broken gate.
2. Drive the inputs deliberately — actual connections to the rail or to
   ground, not a dangling wire.
3. Record all four rows even when the first two look right. Half a truth
   table is not evidence.
4. Compare against the table above. A disagreement is either the wrong
   chip, a wrong pin, or a floating input, in that order of likelihood.

Practise reading and combining gates in [[Logic Gates Practice]], then
put several of them together into something that makes a decision worth
making in [[The Logic Machine]].

%%curriculum-start%%
## Curriculum connection

![[A5.3]]

![[B3.1]]

![[B3.2]]
%%curriculum-end%%
