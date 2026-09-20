---
title: Components and Their Markings
publish: true
created: __CREATED__
tags:
  - concepts
---
[[Name That Part]] runs for four minutes at the start of class and it is
never really about naming. A part on the bench has its identity printed
on it in a code, and being able to read that code — bands, three-digit
numbers, a stripe, a flat edge — is what turns a drawer of anonymous
beads into a stock of known quantities.

## Resistors: the band code

Four bands: two digits, a multiplier, and a tolerance.

| Colour | Digit | Multiplier |
| --- | --- | --- |
| Black | 0 | ×1 |
| Brown | 1 | ×10 |
| Red | 2 | ×100 |
| Orange | 3 | ×1 000 |
| Yellow | 4 | ×10 000 |
| Green | 5 | ×100 000 |
| Blue | 6 | ×1 000 000 |
| Violet | 7 | ×10 000 000 |
| Grey | 8 | not used in practice |
| White | 9 | not used in practice |

Gold and silver appear as multipliers too (×0.1 and ×0.01) but you will
almost always meet them in the fourth position, where gold means ±5 %
tolerance and silver means ±10 %. Precision parts use five bands — three
digits, a multiplier, and a tighter tolerance such as brown for ±1 %.

Three you should be able to read without looking anything up, because
they are in every drawer in this room:

- Brown, black, red, gold → 1, 0, ×100 = **1 kΩ ±5 %**
- Yellow, violet, brown, gold → 4, 7, ×10 = **470 Ω ±5 %**
- Red, red, orange, gold → 2, 2, ×1 000 = **22 kΩ ±5 %**

> [!note] Why the drawer has 470 Ω but not 500 Ω
> Standard values follow the **E-series**. The E12 series — the ±10 %
> family — runs 10, 12, 15, 18, 22, 27, 33, 39, 47, 56, 68, 82 and then
> repeats a decade up. E24 fills the gaps with 11, 13, 16, 20, 24, 30,
> 36, 43, 51, 62, 75, 91. The spacing is roughly geometric, so
> neighbouring values are separated by about as much as the tolerance
> band is wide. There is no point stocking 500 Ω when a 470 Ω part with
> ±5 % might measure anywhere from 446.5 Ω to 493.5 Ω anyway. When a
> calculation gives you 213 Ω, you do not go looking for 213 — you take
> the next standard value that keeps you safe, which here is 220 Ω.

## Everything else on the bench

**Capacitors.** Small ceramics carry a three-digit code in picofarads:
two digits and a number of zeros. `104` means 10 followed by four zeros,
so 100 000 pF — which is 100 nF, or 0.1 µF, the decoupling capacitor you
will fit beside every chip. `103` is 10 nF. Electrolytics print their
value and a voltage rating plainly, and they have a stripe marking the
negative lead. Fit one backwards and it can vent; that is not a figure of
speech.

**Diodes.** A band at one end marks the cathode, the end current flows
*out* of in normal conduction. An ordinary silicon diode drops roughly
0.6 to 0.7 V when conducting; a Schottky drops less, around 0.2 to 0.4 V.
Those drops are nearly independent of current, which is what makes a
diode useless as a resistor and perfect as a one-way valve.

**LEDs.** The longer lead is the anode, and the flat spot on the rim
marks the cathode. Forward voltage depends on the colour, because the
colour depends on the semiconductor:

| Colour | Typical forward drop |
| --- | --- |
| Red | 1.8 – 2.2 V |
| Amber / yellow | 2.0 – 2.2 V |
| Green | 2.0 – 3.4 V, depending on the type |
| Blue / white | 2.8 – 3.6 V |

Those are ranges on purpose. Two green LEDs from different reels can
genuinely differ by more than a volt, which is exactly why the datasheet
for the part you are holding beats any table, including this one.

**Devices that move or sense.** DC motors, stepper motors, and servos
turn current into motion; switches, optical sensors, thermistors, and
accelerometers turn something physical into an electrical quantity.
[[Sensors and Actuators]] is where these get their own treatment, but the
marking discipline is identical — a motor prints its rated voltage and
stall current, and both numbers decide what has to sit between it and
your microcontroller.

## The identification routine

Run this on any unfamiliar part before it goes anywhere near power:

- [ ] Read every marking on the body, including the tiny ones, and write
      them down verbatim
- [ ] Decide what family it belongs to from its package and lead count
- [ ] Find the datasheet by searching the exact printed part number
- [ ] Note the three numbers that constrain your design: maximum voltage,
      maximum current, and power or thermal rating
- [ ] Note which lead is which, and mark it on your schematic
- [ ] Confirm the value with a meter where you can — a resistor should
      measure within its tolerance band, and if it does not, the part or
      your reading is wrong

That is not busywork. Reading text closely, using documents, and putting
numbers to what you read are the Essential Skills the trade actually
runs on, and a datasheet is the most honest document you will meet this
year — see [[Reading a Datasheet]] for how to attack a forty-page one
without reading forty pages. Then prove the values in
[[Ohm's Law Practice]] and put the parts to work in
[[The Working Circuit]].

%%curriculum-start%%
## Curriculum connection

![[A3.1]]

![[A3.2]]

![[D3.4]]
%%curriculum-end%%
