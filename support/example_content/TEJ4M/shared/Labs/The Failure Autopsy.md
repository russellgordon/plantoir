---
title: The Failure Autopsy
publish: true
created: __CREATED__
tags:
  - labs
enableToc: true
---
On the bench in front of you is something that used to work. Somebody
bought it, used it, and threw it away — and between those two facts is
an engineering decision that turned out to be wrong. Your job today is
not to repair it. Your job is to find out what killed it, prove it with
evidence rather than with a story, and then say what the designer would
have had to do differently.

This is the first bench period of Grade 12 and it sets the standard for
every one after it. You will commit to a verdict before you open the
case, and you will be graded on the quality of your reasoning, not on
whether the verdict was right. A wrong prediction with a named cause is
worth more here than a lucky guess.

> [!danger] Safety notes
> **Only devices fed from an external low-voltage adapter** — the wall
> adapter itself stays sealed and stays out of this. Anything that
> plugs straight into a wall outlet is opened by your teacher, on the
> demonstration bench, or not at all: the primary side of a mains
> supply holds hundreds of volts on capacitors that do not care that
> the plug is out. **Unplug, and keep the adapter on your side of the
> bench** where you can see it is unplugged. **Discharge every
> electrolytic capacitor through a resistor** — a $1\ \text{k}\Omega$
> resistor across the terminals for five seconds, then confirm with
> the meter that the voltage really is near zero. Never short a
> capacitor with a screwdriver; the spark pits the terminals, and on a
> larger capacitor it can throw metal. **Remove any battery first**,
> and treat a swollen lithium cell as a fire waiting for a reason —
> hand it to your teacher, do not puncture it, do not bin it.
> **Anti-static strap on** before you touch a board you intend to
> probe. **Broken displays, snapped plastic, and cut sheet metal are
> sharp**: gloves for the disassembly, glasses on throughout.

## What you need

- [ ] One dead device, externally powered, rated no more than
      $24\ \text{V}$ DC
- [ ] Screwdriver set, spudger or plastic opening tool, small pliers
- [ ] Multimeter, anti-static strap and mat, magnifier
- [ ] A $1\ \text{k}\Omega$ resistor, half-watt or larger, for
      discharging
- [ ] Safety glasses, gloves for disassembly, and your journal

## Predict before you open it

1. **Handle it and describe it.** Weight, smell, rattles, scorching,
   corrosion around a connector, a case that no longer sits flat. Write
   down everything you notice while you still have to guess.
2. **Write your verdict.** One sentence: *what failed, and why*. Be
   specific enough to be wrong — "a component failed" is not a verdict,
   "the reservoir capacitor dried out and the supply rail collapsed" is.
3. **Write the evidence you expect to find.** A bulged capacitor top? A
   resistor discoloured brown? A cracked solder joint under a heavy
   connector? A fuse open? Name at least two observations that would
   confirm your verdict and one that would disprove it.
4. **Predict what you will measure**, in numbers: the resistance across
   the supply input, whether the fuse reads near $0\ \Omega$ or open,
   and whether any semiconductor reads as a dead short.

## The autopsy

5. **Outside first, and photograph everything.** Vents blocked with
   dust, a case with no ventilation at all, a device that lived beside
   a heat source — this is the environment the designer had to survive
   and often the reason they did not.
6. **Open it without breaking it.** Fasteners into a labelled tray,
   ribbon cables released rather than pulled. Photograph each layer
   before you lift it.
7. **Discharge, then verify.** Bleed every electrolytic through the
   resistor, then measure across it and record the reading. Only now
   does an unprotected finger come near the board.
8. **Survey with the magnifier, no meter yet.** Look for: bulged or
   vented capacitor tops, brown haloes in the board around a resistor,
   green corrosion, cracked or dull solder joints, cold joints around
   heavy parts, and any component whose printing has been cooked off.
9. **Now measure.** Resistance across the DC input, in both meter
   polarities. Continuity of the fuse. Diode-test across any regulator
   or transistor you can identify. Compare against the same part
   elsewhere on the board where you can.
10. **Find the heat map.** Discolouration on the board is a permanent
    record of where the power went. Trace the hottest region back to
    the component that made it and read that component's markings.
11. **Write the finding as a chain**, not a name: *this got hot,
    because it carried this, because that had failed, because…* Stop
    when you reach a design decision rather than another component.

## Results

| Observation | Predicted | Found |
| --- | --- | --- |
| Failed component (name and marking) | | |
| Evidence of heat (where, how visible) | | |
| Resistance across DC input (Ω) | | |
| Fuse: short or open | | |
| Any part reading as a dead short | | |
| Capacitor voltage after discharge (V) | | |
| Ventilation the enclosure actually provided | | |

## Predicted against measured

Take each row where you were wrong and name the cause of the gap. There
are only a few honest kinds: you did not have the evidence yet, you had
it and misread it, or you reasoned from a device that was not this one.
Say which. "I assumed it was the capacitor because it usually is" is a
real and respectable answer once you have written it down.

Then chase the disagreements between benches. Two groups looking at the
same class of device often reach different verdicts, and comparing the
evidence each one leaned on is the fastest way to learn what evidence
is actually worth.

## The question that matters

Somebody designed this device, and it met its specification on the day
it shipped. Name the decision that made it die anyway.

Then the design-margin question, and this one comes back all semester: what
would you have changed so it survived a hot day in a closed cabinet, a
year of being switched on and off, or being plugged in backwards once?
Give a specific change — a different rating, a different package, a
vent, a diode — and say what it would have cost. If your answer is "use
better parts", you have not answered yet.

%%curriculum-start%%
## Curriculum connection

![[B2.3]]

![[B3.4]]

![[D1.1]]

![[B2.1]]

![[A3.5]]
%%curriculum-end%%
