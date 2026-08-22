---
title: Sinusoidal Functions Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Sinusoidal Functions]] — reading equations,
building them from properties, and running models like the one your
group built for [[The Ferris Wheel]]. Angles are in degrees
throughout.

## Reading equations

1. For $y = 4\sin x$: state the amplitude, period, maximum, and
   minimum.
2. For $y = 3\sin(2x) - 1$: state the amplitude, period, equation of
   the axis, maximum, minimum, and range.
3. For $y = 2\cos(x - 60°) + 5$: state the amplitude, phase shift,
   equation of the axis, and range.

> [!success]- Answer 1
> Amplitude 4; period $360°$ (no $k$, no change); maximum 4 and
> minimum $-4$, since the axis is still $y = 0$.

> [!success]- Answer 2
> Amplitude 3; period $\frac{360°}{2} = 180°$; axis $y = -1$.
> Maximum $-1 + 3 = 2$, minimum $-1 - 3 = -4$; range
> $-4 \le y \le 2$. Every answer hangs off two numbers: the axis and
> the amplitude.

> [!success]- Answer 3
> Amplitude 2; phase shift $60°$ right; axis $y = 5$; range
> $3 \le y \le 7$. The period is untouched at $360°$ — no $k$ inside
> the bracket.

## Building equations

4. A sinusoidal function has amplitude 2, period $180°$, and a
   maximum point at $(0, 3)$. Represent it with an equation in two
   different ways.
5. (a) What is the period of $y = \sin(3x)$? (b) What value of $k$
   gives a sinusoid a period of $720°$?

> [!success]- Answer 4
> Period $180°$ forces $k = 2$; a maximum of 3 with amplitude 2 puts
> the axis at $y = 1$. A cosine starts at its peak, so
> $y = 2\cos(2x) + 1$ works immediately. For a sine version, shift
> so the peak lands at $x = 0$: $y = 2\sin(2(x + 45°)) + 1$ — check:
> at $x = 0$ the argument is $90°$, where sine peaks. ✓ Same graph,
> two names.

> [!success]- Answer 5
> (a) $\frac{360°}{3} = 120°$. (b) Solve $\frac{360°}{k} = 720°$:
> $k = \frac{1}{2}$. A $k$ below 1 *stretches* the wave — inside
> letters act backwards, here as everywhere.

## Models in motion

6. A Ferris wheel rider's height is
   $h(t) = 25\sin(3(t - 30)) + 27$, with $h$ in metres and $t$ in
   seconds. Find the maximum and minimum heights, the height at
   $t = 30$, and the time for one full revolution.
7. A tide follows $h(t) = 5\sin(30(t + 3))$, with $h$ in metres and
   $t$ in hours after midnight. Find the period, verify that high
   tide is at midnight, and find the first low tide after midnight.
8. For the wheel in question 6: what changes in the equation if the
   wheel turns twice as fast, and what if the boarding platform is
   raised by 1 m?

> [!success]- Answer 6
> Axis 27, amplitude 25: maximum $52$ m, minimum $2$ m. At $t = 30$
> the sine's argument is $0°$, so $h(30) = 27$ m — the rider crosses
> the axis. One revolution is the period:
> $\frac{360°}{3} = 120$ seconds.

> [!success]- Answer 7
> Period: $\frac{360°}{30} = 12$ hours. High tide: sine peaks when
> its argument is $90°$, and $30(t + 3) = 90$ gives $t = 0$ —
> midnight. ✓ Low tide: argument $270°$ gives
> $30(t + 3) = 270$, so $t = 6$ — 6 a.m., half a cycle later, as it
> must be.

> [!success]- Answer 8
> Twice as fast doubles $k$ from 3 to 6, halving the period to 60 s —
> amplitude and axis untouched, since the wheel itself did not
> change size. Raising the platform 1 m lifts everything: $c$ goes
> from 27 to 28. Each physical change edits exactly one letter; that
> one-to-one mapping is the whole point of the form.

%%curriculum-start%%
## Curriculum connection

![[D2.1]]

![[D2.2]]

![[D2.3]]

![[D2.4]]

![[D2.5]]

![[D2.6]]

![[D2.7]]

![[D2.8]]

![[D3.1]]

![[D3.2]]

![[D3.3]]

![[D3.4]]

![[D3.5]]
%%curriculum-end%%
