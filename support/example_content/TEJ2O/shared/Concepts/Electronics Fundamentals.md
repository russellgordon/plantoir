---
title: Electronics Fundamentals
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
The first LED you lit in [[Breadboard a Circuit]] involved three
quantities you could not see, arguing invisibly the whole time. This
page gives them names and one law.

## Pressure, flow, and squeeze

Voltage, measured in volts (V), is electrical pressure — how hard the
supply pushes charge around the circuit. Current, measured in amperes
(A) — usually milliamps (mA) at our bench — is the flow itself, how
much charge actually moves. Resistance, measured in ohms (Ω), is the
squeeze that opposes the flow. The water analogy is honest as far as
it goes: pressure in the pipes, litres per second, and how far the
tap is closed. It only misleads if you forget that a circuit must be
a complete loop — no loop, no flow, anywhere.

## One law rules the bench

The three are locked together by Ohm's law:

$$
V = IR
$$

Fix any two and the third has no choice. It rearranges to whichever
question you are asking: $I = V/R$ for "how much will flow?", and
$R = V/I$ for "what resistor do I need?" — the question every LED
circuit asks, since an LED does not limit its own current and will
cheerfully burn itself out. A multimeter lets you check the law's
answers against reality, and the two should agree embarrassingly
well.

> [!success]- Self-check: pick the resistor (click to expand)
> A 5 V supply drives an LED that drops 2 V and wants 20 mA. The
> resistor takes what is left: $R = \frac{5 - 2}{0.020} = 150\ \Omega$.
> The nearest standard value at or above is exactly 150 Ω — the same
> maths behind the resistor handed to you at the bench.

## The parts on the bench

Resistors limit current; their value is painted on in colour bands —
two digits, a multiplier, and a tolerance band. Capacitors store
charge and release it, smoothing bumps in a supply. Diodes allow
current one way only, and an LED is a diode that spends the energy as
light. Transistors act as switches or amplifiers — a small current
controlling a large one, the trick that computers are millions of.
[[Electronics Calculations Practice]] drills the numbers, and
[[Predict the Circuit]] asks what happens before you power anything.

## Measuring voltage, current, and resistance safely

A digital multimeter is the technician's eyes on the bench. Each
measurement requires a specific procedure:

- **Measuring resistance ($\Omega$):** Power must be completely
  disconnected from the circuit. The meter sends its own tiny test
  current through the component to calculate resistance; measuring an
  energized component produces false readings and can damage the meter.
- **Measuring voltage ($\text{V}$):** Connected in **parallel** across
  the two points of interest while the circuit is powered. The black
  probe connects to ground ($\text{COM}$) and the red probe to the
  positive measurement point.
- **Measuring current ($\text{A}$ or $\text{mA}$):** Connected in
  **series** by breaking the circuit loop and inserting the meter so
  all current passes through it. The internal shunt fuse protects the
  meter from overcurrent.

Observing proper probe placement and range selection prevents blown
meter fuses and ensures reliable circuit diagnostics.

%%curriculum-start%%
## Curriculum connection

![[B2.1]]

![[B2.5]]

![[D1.1]]
%%curriculum-end%%
