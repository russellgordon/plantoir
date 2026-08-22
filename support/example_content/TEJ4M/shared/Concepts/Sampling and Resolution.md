---
title: Sampling and Resolution
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
In [[Sample a Signal]] one group set their board to capture a 1300 Hz
tone, sampled it a thousand times a second, and plotted a beautiful clean
300 Hz wave. Nothing was broken. The equipment did exactly what it was
told, and told them a lie they could not detect from the data. Getting an
analog quantity into a computer honestly is two separate promises — how
finely you can tell values apart, and how often you look — and this page
is about both.

## Resolution: what one count is worth

A converter with $n$ bits divides its reference into $2^n$ steps. The
size of one step, the **least significant bit**, is

$$\text{LSB} = \frac{V_{\text{ref}}}{2^n}$$

For a 10-bit converter on a 3.3 V reference:

$$\text{LSB} = \frac{3.3\ \text{V}}{1024} \approx 3.223\ \text{mV}$$

Everything inside one step reads as the same number, so the unavoidable
**quantization error** is up to half a step either way — about
$\pm 1.61\ \text{mV}$ here. A 12-bit converter on the same reference
gives $3.3 / 4096 \approx 0.806\ \text{mV}$ per step: four times finer,
because two more bits means four times as many steps.

Resolution is not accuracy. A converter can resolve microvolts and still
be wrong by tens of millivolts if its reference drifts, its input is
loaded, or its offset was never calibrated. Resolution says how small a
*change* you can see; accuracy says how close the value is to the truth.
Never claim the second when you have measured the first.

## Matching the converter to the sensor

Resolution only means something once you convert it into the units you
care about. A sensor giving 10 mV per degree Celsius, read by that 10-bit
converter:

$$\frac{3.223\ \text{mV per count}}{10\ \text{mV}/^\circ\text{C}} \approx 0.322\ ^\circ\text{C per count}$$

If your specification promised readings to 0.1 °C, you have already
failed it, and no amount of code will fix that. Three real options, all
of which belong in a design review:

1. **Amplify.** A gain of 4 makes each count worth
   $0.322 / 4 \approx 0.081\ ^\circ\text{C}$ and meets the requirement —
   at the cost of a quarter of the temperature range, and of amplifying
   the noise too.
2. **Use a better converter.** Twelve bits gets each count to about
   0.081 °C without touching the range.
3. **Average.** Averaging $N$ samples reduces *random* noise by
   $\sqrt{N}$, so sixteen samples improve the effective resolution by
   about two bits — but only if there is enough noise to dither between
   codes, and it costs you sixteen sample times. It does nothing at all
   about a systematic offset.

## Sampling rate, and the rule with no exceptions

The other promise is how often you look. To reconstruct a signal you must
sample at **more than twice** the highest frequency present in it — the
Nyquist criterion. A signal containing components up to 400 Hz needs a
sampling rate above 800 Hz, and "above" is doing real work in that
sentence: sampling at exactly twice can land every sample on a zero
crossing and hand you a flat line.

Read it as a budget. A converter capable of 100 000 samples per second,
shared round-robin between four channels, gives each channel 25 000
samples per second, which honestly covers signals up to about 12.5 kHz —
less, once you leave room for a real anti-alias filter to roll off.

Storage is a budget too. Two bytes per sample at 5 kHz for two seconds is
$2 \times 5000 \times 2 = 20\,000$ bytes, which will not fit in the free
memory of a small board. Store 8-bit samples, sample slower, or stream
the data out as it arrives — decide before the capture, not during it.

> [!warning] Aliasing cannot be undone in software
> A frequency above half the sampling rate does not disappear. It comes
> back disguised as a lower frequency, at $|f - n f_s|$ for whichever
> multiple $n$ lands nearest. That 1300 Hz tone sampled at 1000 Hz
> appears at $|1300 - 1000| = 300$ Hz, and a 900 Hz tone sampled at
> 1000 Hz appears at 100 Hz.
>
> Once the samples exist, the fake and the real are the same numbers.
> There is no filter, no averaging, and no clever algorithm that
> separates them afterwards, because the information was destroyed at the
> moment of sampling.
>
> The only defence is analog and comes first: a low-pass filter ahead of
> the converter, with its cutoff well below half the sampling rate, so
> that nothing capable of aliasing ever arrives. That is the whole reason
> [[Filters and Noise]] sits before this page.

## Going back the other way

Digital to analog runs the same argument in reverse, and the workhorse in
this room is **pulse-width modulation**: a fixed-frequency square wave
whose on-time proportion sets the average. An 8-bit duty setting gives
256 levels, so a request for 30% becomes $0.30 \times 255 = 76.5$, which
must be rounded — 76 counts is an actual duty of
$76/255 \approx 29.8\%$. PWM only behaves like an analog level once the
load averages it: a motor's inertia and a filter both do, and an
oscilloscope emphatically does not, which is why PWM looks like a square
wave on a scope and behaves like a voltage to the motor.

## Why this got cheap

Neither of these promises is new. The mathematics was settled before
anybody in this room was born, and the reason a phone in your pocket now
captures fifty megapixels and records twenty-four bit audio is not that
the theory improved — it is that the *other* parts of a computer caught
up with it.

Follow one of them through. A 12-megapixel image at 12 bits per colour
per pixel is about 54 MB before compression. Capturing it means moving
that off the sensor faster than the shutter interval, holding it while
the processor works on it, and then storing it somewhere it survives
losing power. In 1995 each of those three was the binding constraint:
the bus could not carry it, the memory could not hold it, and the disk
could not take it quickly enough or often enough. None of them is
binding now, and the sensor design that was uneconomic then is ordinary.

That is the pattern worth taking out of this course, because it repeats.
Advances in processors, memory and storage do not stay in the computer —
they arrive as capability in whatever the computer is attached to. Cheap
flash storage is why a handheld device can record video at all. Falling
memory prices are why a camera can hold a burst instead of one frame.
Processors fast enough to run the arithmetic in real time are why a
phone can correct a lens's distortion between the shutter and the
preview. The enabling advance is usually one layer down from the product
that gets the attention, and it is almost never the part named in the
advertisement.

Two consequences for the way you specify things. **The constraint moves,
so date your assumptions** — "too much data to store" is a claim with a
year attached to it, and a design that was right in 2015 may be
needlessly cramped now. And **the constraint is somewhere**, so find out
where before you optimise: the storage question in
[[Storage Systems and Arrays]] and the measurement discipline in
[[Firmware and System Optimisation]] both exist because guessing which
layer is the bottleneck is reliably wrong.

Do the arithmetic in [[Sampling and Resolution Practice]], capture real
signals in [[Sample a Signal]], and write the sample rate, the reference
voltage, and the filter cutoff into your build notes. A stored dataset
whose sampling conditions were never recorded is not data — it is a
picture of some numbers.

%%curriculum-start%%
## Curriculum connection

![[A1.3]]

![[A5.5]]

![[A5.6]]

![[B5.2]]
%%curriculum-end%%
