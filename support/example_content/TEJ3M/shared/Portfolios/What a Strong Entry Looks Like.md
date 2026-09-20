---
title: What a Strong Entry Looks Like
publish: true
created: __CREATED__
tags:
  - portfolio
---
Once the journal habit exists, the only remaining question is quality,
and quality in a technician's log comes down to one property:
**reproducibility**. A strong entry contains enough that somebody
else — including you in four months, with no memory of the day —
could rebuild the situation and get the same result. A weak entry
could have been written about any circuit, in any lab, from the
hallway.

## Side by side

| Weak | Strong |
| --- | --- |
| "It wouldn't work." | "LED lit very dimly. Measured 4.1 V across the 220 Ω resistor — about 19 mA — so current was fine; the LED itself dropped only 0.9 V, which is far too low for a red one. Wrong part, or in backwards." |
| "I fixed it." | "Reflowed the joint on pin 3; it had been dull and lumpy. Continuity beeps now, and the input reads low when the button is pressed." |
| "The reading was weird." | "Meter read 0.00 on the 200 mA range with the leads still in the V jack. Moved them to the mA jack and got 13.6 mA, which matches my prediction of 13.9 mA." |
| "Electronics is hard." | "I can do the arithmetic fine, but I lose track of which node is which once a circuit has more than one branch. Tracing on the schematic first helped; tracing on the breadboard did not." |
| "Group work went fine." | "Priya wired the divider; I checked every value against the schematic and caught a 1 kΩ where a 10 kΩ should be. Next lab I want the wiring and she can check me." |

Read the weak column again: nothing happened in it. The strong column
is the same bench day, remembered properly — a voltage, a resistance,
a pin number, a range setting. Notice that the strong versions are
barely longer. Specific is not the same as long. It is the difference
between "it broke" and a fault the next technician could reproduce,
which is exactly what the "what fought back" prompt in
[[Tech Journal]] is asking for.

## A measurement without conditions is half a measurement

This is the Grade 11 upgrade, and it is the thing most often missing
from otherwise good entries. "3.2 V" is not a measurement. "3.2 V
across the motor terminals, supply at 6.0 V, motor stalled" is a
measurement, because it says what was true at the time. The same
motor, spinning freely, gives a completely different number, and an
entry that does not say which one you had is an entry that cannot be
checked.

Three conditions worth recording almost every time: what the supply
was actually set to, which two points the probes were on, and what
else in the circuit was running. It costs one extra clause.

## Feelings are welcome, anchored to a moment and a part

The journal is not a lab report. Frustrated, proud, embarrassed, and
delighted all belong in it. The rule is that a feeling arrives
attached to the moment that caused it and the hardware involved. "I
felt useless" floats free and teaches you nothing later. "I felt
useless when my third joint failed the continuity test — then I
cleaned the tip, let the iron come back up to temperature, and the
fourth one took in two seconds" is a feeling with an address and an
exit. The feeling is real data about you; the fault is the handle you
can actually turn. That pairing is the whole method in
[[Getting Unstuck]].

%%curriculum-start%%
## Curriculum connection

![[D3.4]]

![[D3.6]]
%%curriculum-end%%
