---
title: Curve Sketching Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Motion on a Line]] and [[Curve Sketching]]
— full sketches from equations, reading functions from their
derivatives, and motion analysed with the same sign charts. Run the
checklist; let the chart do the remembering.

## From equation to sketch

1. Analyse and sketch $f(x) = x^3 - 6x^2 + 9x$: intercepts,
   intervals of increase and decrease, local extremes, concavity,
   and any point of inflection. Verify with technology afterward.
2. For $f(x) = x^4 - 4x^3$, determine all critical numbers and
   classify each, then find any points of inflection.

> [!success]- Answer 1
> Intercepts: $f(x) = x(x - 3)^2$, roots at $x = 0$ and $x = 3$
> (double). First derivative:
> $f'(x) = 3x^2 - 12x + 9 = 3(x - 1)(x - 3)$, zero at 1 and 3.
> Sign chart: $+$, $-$, $+$ — increasing, decreasing, increasing.
> Local maximum $(1, 4)$; local minimum $(3, 0)$. Second
> derivative: $f''(x) = 6x - 12$, zero at $x = 2$: concave down
> before, up after — inflection point $(2, 2)$. Note the
> corroboration: the double root at 3 and the minimum at $(3, 0)$
> are the same fact — the graph touches the axis without crossing.

> [!success]- Answer 2
> $f'(x) = 4x^3 - 12x^2 = 4x^2(x - 3)$: critical numbers 0 and 3.
> Sign of $f'$: negative for $x < 0$, *still negative* for
> $0 < x < 3$, positive after 3. No sign change at 0 — not an
> extreme, just a flat pause mid-descent; sign change $-$ to $+$ at
> 3 — local (indeed global) minimum $(3, -27)$.
> $f''(x) = 12x^2 - 24x = 12x(x - 2)$: zero at 0 and 2 with genuine
> sign changes, so inflection points $(0, 0)$ and $(2, -16)$. The
> critical number that was not an extreme turns out to be an
> inflection point with a horizontal tangent.

## Reading derivatives

3. Determine $f''(x)$ for the simple rational function
   $f(x) = \dfrac{1}{x}$, and state what it says about concavity.
4. The derivative of $f(x)$ is $g(x) = (x - 1)(x - 3)$, and
   $f(0) = 0$. Describe the key features of $f$, determine its
   equation, and explain what changes if instead $f(0) = 2$.
5. You are told only that $f'(x) > 0$ for $x < 2$, $f'(2) = 0$, and
   $f'(x) < 0$ for $x > 2$. What must the graph of $f$ look like —
   and why are infinitely many different graphs consistent with
   this information?

> [!success]- Answer 3
> $f(x) = x^{-1}$, so $f'(x) = -x^{-2}$ and
> $f''(x) = 2x^{-3} = \frac{2}{x^3}$. For $x > 0$, $f'' > 0$:
> concave up (the right branch holds water). For $x < 0$,
> $f'' < 0$: concave down. The two branches bend opposite ways,
> which the graph confirms at a glance.

> [!success]- Answer 4
> $f' = g$ is an upward parabola, positive–negative–positive around
> its roots: $f$ increases to a local maximum at $x = 1$, decreases
> to a local minimum at $x = 3$, then increases. Undoing
> $g(x) = x^2 - 4x + 3$ term by term (each power steps back up):
> $f(x) = \frac{x^3}{3} - 2x^2 + 3x + C$, and $f(0) = 0$ forces
> $C = 0$. Features: maximum $\left(1, \frac{4}{3}\right)$, minimum
> $(3, 0)$, inflection at $x = 2$ where $f''(x) = 2x - 4$ changes
> sign. If $f(0) = 2$, only $C$ changes: the whole graph rides up
> two units — same shape, same $x$-locations for every feature.

> [!success]- Answer 5
> $f$ climbs, flattens exactly once at $x = 2$, then falls: one
> local maximum at $x = 2$ and no other features are forced. But
> the information is all about *slopes*, and slopes are blind to
> height — any vertical translation of a consistent graph is
> another consistent graph. Infinitely many answers, one shape.
> Knowing $f'$ everywhere pins down everything about $f$ except
> where it sits.

## Motion as sketching

6. A particle moves along a line with position
   $s(t) = t^3 - 9t^2 + 24t$ metres after $t$ seconds, $t \geq 0$.
   When is the particle at rest? When is it moving in the positive
   direction? On which intervals is it speeding up?

> [!success]- Answer 6
> Velocity: $v(t) = 3t^2 - 18t + 24 = 3(t - 2)(t - 4)$ — at rest at
> $t = 2$ and $t = 4$. Sign chart: positive on $0 \leq t < 2$,
> negative on $2 < t < 4$, positive for $t > 4$ — moving forward,
> backing up, moving forward again. Acceleration:
> $a(t) = 6t - 18$, negative before $t = 3$, positive after.
> Speeding up where $v$ and $a$ agree in sign: on $2 < t < 3$
> (both negative) and $t > 4$ (both positive). Slowing down on
> $0 \leq t < 2$ and $3 < t < 4$. The sign chart from
> [[Curve Sketching]] and the agreement table from
> [[Motion on a Line]] are the same tool wearing different labels.

%%curriculum-start%%
## Curriculum connection

![[B1.1]]

![[B1.2]]

![[B1.3]]

![[B1.4]]

![[B1.5]]

![[B2.1]]

![[B2.2]]
%%curriculum-end%%
