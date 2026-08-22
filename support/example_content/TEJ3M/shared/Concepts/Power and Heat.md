---
title: Power and Heat
publish: true
created: __CREATED__
tags:
  - concepts
---
Someone's board in [[Solder a Board]] came back with a resistor that had
gone brown and smelled wrong. Nothing was miswired. The circuit did
exactly what the schematic said — and the schematic asked that resistor
to dissipate more heat than its body could shed. Power is the quantity
that decides whether a working design is also a *surviving* one.

## Three forms of one equation

Power is the rate at which electrical energy is converted into something
else — usually heat, sometimes light or motion. Its unit is the watt, W.

$$P = VI$$

Substitute Ohm's law into that and two more useful forms fall out. If you
know the current through a component and its resistance, use

$$P = I^2 R$$

and if you know the voltage across it and its resistance, use

$$P = \frac{V^2}{R}$$

All three are the same statement. Which one you reach for depends only on
which two quantities you already have, so you never need to find a third
value first.

A worked case, the one you meet most: a 25 mA current through a 470 Ω
resistor dissipates

$$P = I^2 R = (0.025\ \text{A})^2 \times 470\ \Omega = 0.294\ \text{W}$$

That number matters because the ordinary resistors in the parts drawer
are rated at one quarter of a watt.[^rating] Asking a quarter-watt part
to shed 0.294 W is asking for 118 % of its rating, continuously. It will
not fail on the bench in front of you. It will fail in the display case
in March.

[^rating]: Physically small resistors are typically sold as 1/8 W, 1/4 W,
    1/2 W, 1 W and upward, and the rating describes how much heat the
    body can shed into still air at room temperature before its own
    temperature climbs out of specification. Crowded boards, enclosures,
    and hot rooms all make the real limit lower than the printed one,
    which is why professional practice is to design to roughly half the
    rated power and leave the margin unspent.

## Reading the same circuit as an energy budget

Take a red LED on a 5 V rail through a 220 Ω resistor, with the LED
dropping about 2.0 V. The resistor gets the leftover 3.0 V, so

$$I = \frac{3.0\ \text{V}}{220\ \Omega} \approx 13.6\ \text{mA}$$

Now account for the energy. The resistor turns
$I^2R = (0.0136)^2 \times 220 \approx 0.041\ \text{W}$, about 41 mW,
straight into heat. The LED converts
$2.0\ \text{V} \times 13.6\ \text{mA} \approx 27\ \text{mW}$ into light
and heat. Together that is 68 mW, and the supply delivers
$5\ \text{V} \times 13.6\ \text{mA} \approx 68\ \text{mW}$. The books
balance, as they must.

The interesting part is the ratio: more than half the energy in that
circuit is spent by the resistor doing nothing but not being a short
circuit. That is the honest price of the simplest current-limiting scheme
there is, and it is why battery-powered designs eventually reach for
switching regulators and PWM instead — see [[Driving Outputs Safely]].

## Why components die

- **Overheating.** Every failure above is really this one. Heat degrades
  materials, and degraded materials change value or open up.
- **Exceeding a current rating.** A microcontroller pin can typically
  source or sink only a few tens of milliamps. A small DC motor wants
  hundreds. Connect them directly and the pin, not the motor, is what
  fails.
- **Reverse voltage and inductive kick.** Switching off a motor or relay
  coil makes the coil fight back with a voltage spike far above the
  supply. A flyback diode across the coil gives that energy somewhere
  harmless to go.
- **Being right on the edge.** A part run at 98 % of its rating is a part
  that fails the first warm afternoon.

> [!tip] Design to half
> Compute the power, then choose a part rated at roughly twice it. A
> 0.245 W dissipation on a quarter-watt resistor is arithmetically
> "fine" and professionally not fine; fit a half-watt part and stop
> thinking about it. Doing this is why [[The Working Circuit]] asks for a
> power figure beside every component in your parts list.

Heat is also the whole story of why chips got small — see
[[Inside a Microcontroller]] for where that story lands. A vacuum tube
needed a heater drawing watts to do the switching
job that a transistor does with a fraction of a milliwatt, and an
integrated circuit does millions of times over on a fingernail. Every
generation of that story was won by getting the heat per switch down;
when the heat stopped falling, clock speeds stopped rising and
manufacturers started selling more cores instead.

Practise the arithmetic in [[Power Calculations Practice]], and bring the
thermal instinct to [[Spot the Hazard]] — a part you cannot comfortably
keep a finger on is a part telling you something.

%%curriculum-start%%
## Curriculum connection

![[A3.1]]

![[A3.3]]

![[A3.4]]
%%curriculum-end%%
