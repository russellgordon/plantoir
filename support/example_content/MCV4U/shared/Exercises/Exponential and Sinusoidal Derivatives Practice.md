---
title: Exponential and Sinusoidal Derivatives Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Derivatives of Exponential Functions]] and
[[Derivatives of Sinusoidal Functions]] — the two families that model
growth and repetition, alone and in combination. Radians throughout,
always.

## Exponential derivatives

1. Differentiate $f(x) = e^x$ and $g(x) = 2^x$.
2. Differentiate $f(x) = e^{3x}$.
3. Evaluate $\dfrac{2^h - 1}{h}$ for $h = 0.1$, $0.01$, and
   $0.001$. What is the march approaching, and what does it verify?
4. A population is modelled by $N(t) = 500e^{0.2t}$, with $t$ in
   years. Determine the rate of growth at $t = 5$.

> [!success]- Answer 1
> $f'(x) = e^x$ — the function that is its own derivative.
> $g'(x) = 2^x \ln 2$ — same shape, stretched by the constant
> $\ln 2 \approx 0.693$. Only base $e$ escapes the stretch factor.

> [!success]- Answer 2
> Chain rule: the inside $3x$ reports its rate 3, so
> $f'(x) = 3e^{3x}$. At every point this function grows at three
> times its own height.

> [!success]- Answer 3
> $h = 0.1$: $\frac{2^{0.1} - 1}{0.1} \approx 0.718$. $h = 0.01$:
> $\approx 0.696$. $h = 0.001$: $\approx 0.6934$. The march settles
> toward $\ln 2 \approx 0.693$ — and this limit is exactly the
> stretch factor in $\frac{d}{dx}2^x = 2^x \ln 2$, verified with
> nothing but a calculator.

> [!success]- Answer 4
> $N'(t) = 500 \times 0.2\,e^{0.2t} = 100e^{0.2t}$. At $t = 5$:
> $N'(5) = 100e^{1} \approx 272$ individuals per year. Note the
> signature of exponential growth: $N'(t) = 0.2\,N(t)$ — the rate
> is always 20% of the size.

## Sinusoidal derivatives

5. Determine the slope of $f(x) = \sin x$ at
   $x = \dfrac{\pi}{3}$.
6. Determine the equation of the tangent line to $f(x) = \cos x$ at
   $x = \dfrac{\pi}{2}$.
7. Differentiate $f(x) = x \sin x$.
8. Express $\tan x$ as $\dfrac{\sin x}{\cos x}$ and differentiate it
   using the product and chain rules. Simplify.

> [!success]- Answer 5
> $f'(x) = \cos x$, so the slope is
> $\cos\frac{\pi}{3} = \frac{1}{2}$. Check against the graph: at
> $\frac{\pi}{3}$ sine is still climbing toward its crest at
> $\frac{\pi}{2}$, but flattening — a modest positive slope fits.

> [!success]- Answer 6
> Point: $f\left(\frac{\pi}{2}\right) = 0$. Slope:
> $f'(x) = -\sin x$, so
> $f'\left(\frac{\pi}{2}\right) = -1$. Tangent:
> $y = -\left(x - \frac{\pi}{2}\right)$. Cosine crosses its axis
> at full steepness, heading down — slope exactly $-1$.

> [!success]- Answer 7
> Product rule: $f'(x) = 1 \cdot \sin x + x \cos x =
> \sin x + x \cos x$. Both factors take their turn; neither $x$ nor
> $\sin x$ gets to hold still for free.

> [!success]- Answer 8
> Write $f(x) = \sin x\,(\cos x)^{-1}$. Then
> $$f'(x) = \cos x\,(\cos x)^{-1} + \sin x \cdot (-1)(\cos x)^{-2}(-\sin x) = 1 + \frac{\sin^2 x}{\cos^2 x}$$
> Over a common denominator:
> $\frac{\cos^2 x + \sin^2 x}{\cos^2 x} = \frac{1}{\cos^2 x}$ — the
> Pythagorean identity collapsing the sum. The derivative of
> $\tan x$ is $\frac{1}{\cos^2 x}$, always positive: tangent only
> ever climbs.

## Rates in the wild

9. The height of a tide is modelled by
   $h(t) = 3\sin\left(\dfrac{\pi t}{6}\right) + 5$ metres, with $t$
   in hours. Determine the rate of change of the height at $t = 3$,
   and interpret the answer.

> [!success]- Answer 9
> Chain rule:
> $h'(t) = 3\cos\left(\frac{\pi t}{6}\right) \cdot \frac{\pi}{6}
> = \frac{\pi}{2}\cos\left(\frac{\pi t}{6}\right)$. At $t = 3$:
> $h'(3) = \frac{\pi}{2}\cos\frac{\pi}{2} = 0$ metres per hour.
> Interpret before moving on: $h(3) = 3\sin\frac{\pi}{2} + 5 = 8$,
> the model's maximum — this is high tide, and the water is
> momentarily still. A rate of zero at the crest is the model
> agreeing with the ocean.

%%curriculum-start%%
## Curriculum connection

![[A2.4]]

![[A2.5]]

![[A2.6]]

![[A2.7]]

![[A2.8]]

![[B2.2]]

![[B2.3]]
%%curriculum-end%%
