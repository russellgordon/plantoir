---
title: Sinusoid Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Sinusoids in Radians]] and
[[Reciprocal Trigonometric Functions]] — the parent graphs in radians,
the four parameters read both ways, and one model built from real
numbers. Degrees appear nowhere. Sketch first, every time; a
transformation you cannot draw is a transformation you cannot check.

## The parent graphs

1. Sketch $y = \sin x$ and $y = \cos x$ over $0 \le x \le 2\pi$. For
   each, state the period, the amplitude, the domain, the range, and
   every $x$ at which the curve crosses its axis.
2. State the period and domain of $y = \tan x$, say where its
   asymptotes fall and why they fall there, and explain why the
   question "what is its amplitude?" has no answer.
3. State the domain, range and period of $y = \csc x$, and explain why
   its asymptotes sit exactly where $\sin x$ has its zeros. Then say
   why $\csc x$ and $\sin^{-1} x$ are not the same object.

> [!success]- Answer 1
> Both have period $2\pi$, amplitude $1$, domain all real numbers and
> range $-1 \le y \le 1$ — the two graphs are the same curve, shifted.
> $y = \sin x$ crosses its axis at $x = 0$, $\pi$ and $2\pi$;
> $y = \cos x$ crosses at $x = \frac{\pi}{2}$ and $\frac{3\pi}{2}$,
> and starts at its maximum instead. In radians the shape has not
> changed at all — only the numbers written under the axis have,
> which is the whole content of the change of unit.

> [!success]- Answer 2
> Period $\pi$, not $2\pi$: $\tan x = \frac{\sin x}{\cos x}$, and
> both parts change sign together every half turn, so the ratio
> repeats twice as often. The domain excludes
> $x = \frac{\pi}{2} + n\pi$, which is exactly where $\cos x = 0$ and
> the ratio has a zero denominator — so the asymptotes stand there.
> Amplitude means half the distance between a maximum and a minimum,
> and $\tan x$ has neither: it runs to infinity on both sides of every
> asymptote. A function with no maximum cannot have an amplitude.

> [!success]- Answer 3
> $\csc x = \frac{1}{\sin x}$, so its domain excludes $x = n\pi$ where
> $\sin x = 0$, and those are its asymptotes — a reciprocal blows up
> exactly where the original crosses zero, which is Unit 2's
> reciprocal thinking with a new function underneath it. Its period is
> still $2\pi$, inherited from sine. Its range is
> $y \le -1$ or $y \ge 1$: sine never exceeds $1$ in size, so its
> reciprocal never falls below $1$ in size. And $\sin^{-1} x$ is the
> *inverse function*, the angle whose sine is $x$ — a different
> machine that answers a different question. The notation collision is
> the reason the curriculum names $\csc x$ and $\frac{1}{\sin x}$ as
> the acceptable ways to write it.

## Reading and building sinusoids

4. For $y = 3\cos(2x) - 1$: state the amplitude, period, phase shift,
   equation of the axis, maximum and minimum. Then sketch one full
   period.
5. Sketch $y = -2\sin\!\left(\frac{1}{2}\left(x - \frac{\pi}{3}\right)\right) + 1$
   over one full period, marking the five key points. State the period
   and the phase shift.
6. A sinusoidal function has amplitude $2$, period $\pi$, and a maximum
   at $(0, 3)$. Write an equation for it in two different ways.
7. A curve oscillates about the line $y = 4$, reaches a minimum value
   of $1$, has period $\frac{2\pi}{3}$, and has its first maximum at
   $x = \frac{\pi}{6}$. Write an equation.

> [!success]- Answer 4
> Amplitude $3$; period $\frac{2\pi}{2} = \pi$; phase shift $0$; axis
> $y = -1$; maximum $-1 + 3 = 2$ at $x = 0$; minimum $-1 - 3 = -4$ at
> $x = \frac{\pi}{2}$. Sketch the axis first, then the amplitude
> band, then mark the five points a quarter-period apart —
> $\frac{\pi}{4}$ each — and the curve draws itself.

> [!success]- Answer 5
> $k = \frac{1}{2}$, so the period is
> $\frac{2\pi}{1/2} = 4\pi$ — stretched, not compressed. Phase shift
> $\frac{\pi}{3}$ to the right; axis $y = 1$; amplitude $2$, and the
> negative sign flips the sine, so the curve leaves the axis
> *downwards*. Quarter-period is $\pi$, so the five points are
> $\left(\frac{\pi}{3}, 1\right)$,
> $\left(\frac{4\pi}{3}, -1\right)$ — the minimum, because of the
> flip — $\left(\frac{7\pi}{3}, 1\right)$,
> $\left(\frac{10\pi}{3}, 3\right)$ and
> $\left(\frac{13\pi}{3}, 1\right)$.

> [!success]- Answer 6
> Amplitude $2$ and a maximum of $3$ put the axis at $c = 1$. Period
> $\pi$ gives $k = \frac{2\pi}{\pi} = 2$. A cosine starts at its
> maximum, and the maximum is at $x = 0$, so no shift is needed:
> $y = 2\cos(2x) + 1$. A sine starts on its axis climbing, and must be
> moved a quarter-period — $\frac{\pi}{4}$ — to the left:
> $y = 2\sin\!\left(2\left(x + \frac{\pi}{4}\right)\right) + 1$. Check
> both at $x = 0$: $2(1) + 1 = 3$ and
> $2\sin\frac{\pi}{2} + 1 = 3$. ✓ Two equations, one curve — which is
> the ordinary state of affairs, not a coincidence.

> [!success]- Answer 7
> The axis is $y = 4$ and the minimum is $1$, so the amplitude is
> $4 - 1 = 3$ and the maximum is $7$. Period $\frac{2\pi}{3}$ gives
> $k = \frac{2\pi}{2\pi/3} = 3$. Cosine peaks at the start of its
> cycle, and the first peak is at $x = \frac{\pi}{6}$, so
> $d = \frac{\pi}{6}$:
> $y = 3\cos\!\left(3\left(x - \frac{\pi}{6}\right)\right) + 4$. Test
> it at $x = \frac{\pi}{6}$: $3\cos 0 + 4 = 7$. ✓

## One model, in radians

8. A city's daylight runs from about $8.7$ hours on its shortest day to
   about $15.9$ hours on its longest, and the longest falls on about
   day $172$ of the year. Let $t$ be the day number. Build a sinusoidal
   model $h(t)$ for hours of daylight, then use it twice: predict the
   daylight on day $1$, and find the stretch of the year with at least
   $14$ hours of daylight.

> [!success]- Answer 8
> Axis: $\frac{15.9 + 8.7}{2} = 12.3$. Amplitude:
> $\frac{15.9 - 8.7}{2} = 3.6$. Period $365$ days, so
> $k = \frac{2\pi}{365}$. The maximum is at $t = 172$, and cosine peaks
> at the start of its cycle, so
> $$h(t) = 3.6\cos\!\left(\frac{2\pi}{365}(t - 172)\right) + 12.3$$
> **Day 1.** The angle is $\frac{2\pi}{365}(1 - 172) \approx -2.944$
> radians, and $\cos(-2.944) \approx -0.980$, so
> $h(1) \approx 3.6(-0.980) + 12.3 \approx 8.8$ hours. Close to the
> shortest day, which is what early January ought to give — the model
> passing a test it was not built from.
>
> **At least fourteen hours.** Solve
> $3.6\cos\theta + 12.3 \ge 14$, so
> $\cos\theta \ge \frac{1.7}{3.6} \approx 0.472$, so
> $|\theta| \le \arccos(0.472) \approx 1.079$ radians. Since
> $\theta = \frac{2\pi}{365}(t - 172)$, that is
> $|t - 172| \le 1.079 \times \frac{365}{2\pi} \approx 62.7$ — roughly
> day $109$ to day $235$, about four months centred on the longest day.
> Notice which step did the work: the inequality was solved on the
> angle first and translated back into days afterwards, because
> $\arccos$ answers in radians and the days were never the variable
> the cosine could see.

%%curriculum-start%%
## Curriculum connection

![[B2.1]]

![[B2.2]]

![[B2.3]]

![[B2.5]]

![[B2.6]]

![[B2.7]]
%%curriculum-end%%
