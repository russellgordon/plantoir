---
title: Digital and Analog Signals
publish: true
created: __CREATED__
tags:
  - concepts
---
On the analog day of [[Blink, Read, React]] you turned a potentiometer
and watched a number on screen sweep smoothly from nearly zero to
something over sixty-five thousand. On the digital day, the same board
reading a button gave you exactly two answers, ever. Same pins, same
chip, completely different contract — and knowing which contract you are
working under is most of the job.

## Two states versus a continuum

A **digital** signal is one that the receiving circuit is required to
round. Anything below the low threshold means 0, anything above the high
threshold means 1, and the design's whole purpose is to keep signals out
of the middle. That rounding is why digital systems are robust: a bit of
noise on a 3.3 V line still reads as a 1, and the noise is erased at
every stage rather than accumulating.

An **analog** signal carries its meaning in the exact value. The voltage
from a thermistor divider, a microphone, or a light sensor is a
continuous quantity, and every millivolt of interference is now part of
the reading. Analog signals carry more information and lose it more
easily. That is the whole trade.

Most real sensors are analog at heart — a switch is the obvious exception,
and even a switch is analog while it is bouncing. Your microcontroller,
being digital, therefore needs a translator on the way in and a different
one on the way out.

## Analog in: the ADC and what its numbers mean

An analog-to-digital converter compares an input voltage against a
reference and reports where it falls, as an integer. Two numbers describe
it completely: the **reference voltage**, which sets the top of the
range, and the **resolution in bits**, which sets how finely that range is
sliced.

A 10-bit converter produces $2^{10} = 1024$ distinct codes, numbered 0 to
1023. With a 3.3 V reference, a reading of 683 corresponds to

$$V = \frac{683}{1023} \times 3.3\ \text{V} \approx 2.20\ \text{V}$$

and one step of the converter is worth about
$3.3\ \text{V} / 1024 \approx 3.2\ \text{mV}$. That step is the honest
limit on your precision: no averaging, no smoothing, and no decimal
places in your print statement change the fact that the hardware cannot
distinguish two voltages closer together than that.

MicroPython smooths over the differences between chips by offering
`read_u16()`, which rescales whatever the hardware produces into a
0 – 65535 range. A reading of 32768 on a 3.3 V reference is therefore

$$V = \frac{32768}{65535} \times 3.3\ \text{V} \approx 1.65\ \text{V}$$

Convenient — but be clear-eyed about it. If the underlying converter is
10-bit, `read_u16()` still only produces 1024 genuinely different values,
spread across a 16-bit range. The extra digits are presentation, not
precision, and [[Reading a Datasheet]] is where you find out which you
have.

> [!warning] Two things that quietly ruin analog readings
> **Exceeding the input range.** Feeding a pin more than the chip's
> supply voltage does not give you a bigger number; it gives you a
> damaged pin. Anything above the reference must be brought down with a
> divider first — the arithmetic is in
> [[Series and Parallel Circuits]].
>
> **No shared ground.** A voltage is a difference between two points, so
> a sensor and a microcontroller that do not share a ground are not
> measuring the same thing. Readings that drift, jump, or depend on what
> else is plugged in are usually this.

## Analog out, sort of: PWM

Most microcontroller pins cannot produce an arbitrary voltage. They can
only be fully on or fully off — so they cheat, extremely quickly.
**Pulse-width modulation** switches a pin on and off at a fixed frequency
and varies the fraction of each cycle it spends on. That fraction is the
duty cycle, and for a load that cannot respond fast enough to follow the
switching — an LED and your eye, a motor and its own inertia — the effect
is the same as a steady voltage of

$$V_{\text{average}} = \text{duty} \times V_{\text{supply}}$$

A 25 % duty cycle on a 3.3 V rail behaves like about 0.825 V to a motor.
It is emphatically *not* 0.825 V on an oscilloscope: put a probe on it
and you will see the full square wave, which is the clearest possible
demonstration of why [[Using an Oscilloscope]] tells you things a
multimeter cannot. A meter shows the average and hides the mechanism.

If you genuinely need a smooth voltage, filter it — a resistor and
capacitor together average the pulses out, with the smoothing set by the
time constant $\tau = RC$. A 10 kΩ resistor and a 100 nF capacitor give
$\tau = 1\ \text{ms}$, and the output settles to within a couple of
percent of its final value after about five time constants. Choose $\tau$
much longer than the PWM period and much shorter than the speed you want
to respond, and you have a usable analog output.

The pattern to carry forward: digital when you need reliability, analog
when you need detail, and a converter of some kind wherever the two meet.
[[Sensors and Actuators]] puts real parts on both ends of that sentence,
[[Reading Sensors]] writes the code, and
[[Microcontroller Code Practice]] drills the converter arithmetic until
you can do it in your head at the bench.

%%curriculum-start%%
## Curriculum connection

![[A3.2]]

![[A5.2]]

![[B3.2]]
%%curriculum-end%%
