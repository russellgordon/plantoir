---
title: Voltage, Current, and Resistance
publish: true
created: __CREATED__
tags:
  - concepts
---
In [[Measure a Circuit]] you took the same simple loop and measured it
three different ways, and the meter had to be connected differently each
time. That was not fussiness. Those three readings are three genuinely
different quantities, and the way you attach the meter tells you which
one you are asking about.

## Three quantities, not three names for one thing

**Voltage** is a difference in electrical pressure between two points.
That is why a voltage reading always has two probes on two places and why
"the voltage at the resistor" is a sloppy phrase — you mean the voltage
*across* it, between one end and the other. Unit: the volt, V.

**Current** is the flow of charge past a point, and it is the same
everywhere along an unbranched loop. Unit: the ampere, A, though at this
bench you will nearly always be working in milliamps. One milliamp is a
thousandth of an amp.

**Resistance** is how much a component opposes that flow. Unit: the ohm,
Ω. It is a property of the part itself, which is why you measure it with
the part disconnected and the circuit unpowered — a meter measuring
resistance is putting its own tiny current through the component, and a
live circuit ruins that.

| Quantity | Symbol | Unit | How the meter connects |
| --- | --- | --- | --- |
| Voltage | $V$ | volt (V) | In **parallel**, across the part |
| Current | $I$ | ampere (A) | In **series**, circuit broken open |
| Resistance | $R$ | ohm (Ω) | Across the part, **power off** |

That third column is the whole practical skill. To measure current you
must open the circuit and make the meter part of the loop, because the
current has to flow *through* the meter to be counted. To measure voltage
you leave the circuit intact and touch two points, because you are asking
about a difference between them.

> [!warning] The classic destroyed-fuse mistake
> Leave the meter set to current — leads still in the A jack — and then
> probe across a supply as if you were measuring voltage, and you have
> just connected a near-short across the rail. On a good meter the fuse
> dies. On a bad one, more than the fuse. Check the dial and the jack
> before every single probe; [[Using a Multimeter]] makes a ritual of it
> for exactly this reason.

## Why the water analogy is useful and where it fails

Pressure in a pipe, litres per second, and a partly closed tap: the
analogy is honest about proportion, and it correctly predicts that
nothing flows unless the loop is complete. It fails in two ways worth
knowing now. Water leaks out of a broken pipe; charge does not pour out
of a cut wire, it simply stops. And water has mass and momentum in a way
that ordinary bench current does not — a circuit reaches its new state
faster than you can watch.

The analogy also tempts you into saying a supply "gives" a fixed current.
It does not. A bench supply holds a voltage steady and the circuit decides
the current, which is precisely the relationship [[Ohm's Law]] pins down
with a number.

## Getting the reading you actually asked for

- [ ] Meter dial and lead position checked before the probes touch
      anything
- [ ] Range set so the reading is not pinned at the top or lost in the
      last digit
- [ ] Black lead on the point you are calling zero, so the sign of the
      reading means something
- [ ] Reading written down with its unit, in your [[Tech Journal]], next
      to the value you predicted

That last one is the difference between measuring and collecting. A
number with no prediction beside it teaches you nothing, which is why
[[Predict the Circuit]] runs before the supply comes on and why
[[The Prediction Contest]] makes a competition of it. When measurement
and prediction disagree, one of them is wrong and finding out which is
the actual work — start with [[Ohm's Law Practice]] if the arithmetic is
where you are shaky.

%%curriculum-start%%
## Curriculum connection

![[A3.1]]

![[A3.3]]

![[B3.2]]
%%curriculum-end%%
