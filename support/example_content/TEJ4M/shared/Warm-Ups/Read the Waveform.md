---
title: Read the Waveform
publish: true
created: __CREATED__
tags:
  - warm-ups
enableToc: true
---
New this year, and overdue. An oscilloscope trace goes up on the board
— a real capture from a real bench, with the scale settings visible in
the corner — and the task is to get five honest numbers off it and one
sentence about what could have produced it.

This is the same routine as [[Read the Schematic]], pointed at a
different document. A schematic is what somebody intended. A waveform
is what the circuit is actually doing, which is not always the same
thing and is never less interesting.

## How to run it

1. Reveal the trace. One quiet minute. Everyone writes the five
   readings below — no calling out, no calculators shared.
2. Before anything else, the class states the **scale settings** and
   the **probe attenuation** out loud. A trace whose settings are not
   known is a drawing, not a measurement, and any number read off it
   is fiction.
3. Cold-call the five readings, then the one-sentence guess about the
   circuit.
4. Close with the question that matters most: *what would you measure
   next to be sure?* On most traces there is exactly one follow-up
   that would settle it.

## The five readings

| Reading | How you get it | What it is worth |
| --- | --- | --- |
| Period, then frequency | Count horizontal divisions for one full cycle, multiply by the timebase, take the reciprocal | Tells you which circuit you are looking at |
| Amplitude, peak to peak | Count vertical divisions, multiply by volts per division, then apply probe attenuation | Tells you whether the levels are legal for the logic downstream |
| DC offset | Where the trace sits relative to the zero marker | A signal centred where it should not be is a clue on its own |
| Duty cycle | High time divided by period | The whole of PWM lives here |
| Rise time | The 10 % to 90 % transition on one edge | Decides whether the edge is fast enough — or too fast |

The sixth thing is not a number. It is a description: **what does the
noise look like?** Broadband fuzz on every part of the trace, a
periodic wobble at one particular frequency, a burst that appears only
on edges, or ringing that decays after each transition. Those four
have four different causes and this year you are expected to tell them
apart. [[Filters and Noise]] is where they get their names.

## Doing the arithmetic

The grid is the measurement. Suppose one complete cycle spans four
divisions with the timebase set to 200 µs per division.

$$T = 4 \times 200\ \mu\text{s} = 800\ \mu\text{s} \qquad f = \frac{1}{T} = \frac{1}{800 \times 10^{-6}\ \text{s}} = 1250\ \text{Hz}$$

If the high portion occupies 1.2 of those four divisions, the duty
cycle is $1.2 / 4 = 0.30$, so 30 %. If the trace spans 3.4 vertical
divisions at 1 V per division with the scope correctly told it is
using a ×10 probe, the signal is 3.4 V peak to peak — a plausible
3.3 V logic signal with a little overshoot, or a badly loaded 5 V one,
and the offset reading tells you which.

Rise time is the reading that catches people out, because part of what
you measure belongs to the instrument rather than the circuit. A
scope's own rise time is roughly

$$t_{\text{scope}} \approx \frac{0.35}{\text{bandwidth}}$$

for the gently rolling-off response most bench scopes have, and the
measured rise time is approximately the two combined in quadrature:

$$t_{\text{measured}} \approx \sqrt{t_{\text{signal}}^2 + t_{\text{scope}}^2}$$

So a 12 ns edge measured on a 100 MHz scope, whose own rise time is
about 3.5 ns, corresponds to a real edge of about 11.5 ns. At that
ratio the correction barely matters. Measure a 4 ns edge on the same
scope and the instrument is contributing most of what you see, and the
honest answer is "faster than this scope can tell me".

## What the trace does not tell you

- **Current.** A scope measures voltage against ground, full stop.
  Current is inferred, usually across a small known resistance, and
  the inference is only as good as your knowledge of that resistance.
- **What is happening at a node you did not probe.** One channel is
  one story. Most interesting faults are relationships between two
  signals.
- **Whether the ringing is real.** A long ground lead adds inductance
  and manufactures ringing that the circuit does not have. If ringing
  changes when you shorten the ground connection, it was yours.
- **Whether you are seeing the whole signal.** A digital scope samples.
  Too few samples per cycle and a fast signal can appear as a slow one
  that was never there — the trap [[Sampling and Resolution]] is
  entirely about.

> [!example]- A worked round
> On screen: a trace sitting mostly near the bottom of the grid,
> jumping up briefly and regularly. Settings: 200 µs per division,
> 1 V per division, ×10 probe, DC coupled.
>
> Period is four divisions, so 800 µs, so 1.25 kHz. Amplitude is 3.3
> divisions, so about 3.3 V peak to peak. The low level sits on the
> zero marker, so there is no meaningful offset. The high portion is
> just over one division, so the duty cycle is a little under 30 %.
> The rising edges are too fast to measure at this timebase — a
> vertical line — so any rise-time claim here would be invented.
>
> One sentence: a 3.3 V microcontroller output running PWM at about
> 1.25 kHz, roughly 30 % duty — an LED dimmed to about a third, or a
> motor drive at low speed. To be sure: change the commanded duty in
> firmware and confirm the trace follows it. If it does not, the
> signal you are looking at is not the one you think it is.

## One variation

Two channels. Put a clock and a data line up together, or a control
signal and the rail it disturbs, and ask for the *relationship*: which
edge comes first, by how many nanoseconds or microseconds, and does
the second signal ever change while the first is still moving. That is
the question every bus in [[Communication Buses]] turns on, and it is
the natural handoff from this routine to
[[Using a Logic Analyzer]], which answers it across sixteen lines at
once but cannot tell you the shape of any of them.

> [!tip] Write the settings beside every trace you keep
> A waveform sketched into your [[Tech Journal]] with no
> volts-per-division and no time-per-division beside it is a doodle.
> Two extra numbers turn it into evidence you can still use a year from now.
