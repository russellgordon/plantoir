---
title: Quadratic Graphing Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[The Vertex Form]] and
[[Transformations of Parabolas]] — ideas your group built in
[[Maximum Enclosure]]. The skill trained here is fluent movement
between forms: each hands you a different feature for free, and a good
sketch needs only a vertex, a direction, and one honest point. Check
any sketch in seconds with [[Using Desmos]].

## Questions

1. For $y = (x - 2)^2 - 5$: state the vertex, the axis of symmetry,
   and the direction of opening, then sketch.
2. A parabola has vertex $(3, -4)$ and passes through $(5, 4)$.
   Determine its equation in vertex form.
3. For $y = (x - 1)(x - 5)$: state the zeros, the axis of symmetry,
   and the vertex, then sketch.
4. For $y = x^2 + 6x + 5$: find the $y$-intercept, the zeros, and the
   vertex, then sketch.
5. **Same parabola, three outfits.** $y = 2(x-1)^2 - 8$,
   $y = 2(x+1)(x-3)$, and $y = 2x^2 - 4x - 6$ describe one parabola.
   Say which feature each form hands you for free, then verify they
   agree by evaluating all three at $x = 0$.
6. **Challenge.** Describe the transformations that carry $y = x^2$
   onto $y = -\frac{1}{2}(x - 3)^2 + 4$, then sketch the image.
7. **Curve of best fit from data.** A physics experiment rolls a can
   down a ramp, recording distance $d$ (cm) reached at time $t$ (s):

| Time $t$ (s) | 0.0 | 0.5 | 1.0 | 1.5 | 2.0 |
| --- | --- | --- | --- | --- | --- |
| Distance $d$ (cm) | 0 | 12 | 50 | 113 | 200 |

   Plot the data points, draw a smooth curve of best fit, and determine
   a quadratic equation $d = at^2$ modelling the motion.
8. **Quadratic versus exponential.** Build a table of values for
   $y = x^2$ and $y = 2^x$ for integer values $x \in [-2, 4]$. Use the table
   to explain: (a) why $2^0 = 1$; (b) the meaning of $2^{-1}$ and $2^{-2}$;
   (c) two ways the graph of $y = x^2$ differs from $y = 2^x$.
9. **Completing the square (no fractions).** Convert each quadratic from
   standard form $y = ax^2 + bx + c$ to vertex form $y = a(x - h)^2 + k$
   by completing the square, and state the vertex:
   (a) $y = x^2 - 10x + 21$;
   (b) $y = 3x^2 + 12x + 5$.

## Answers

> [!success]- Answer 1
> Vertex $(2, -5)$, axis $x = 2$, opens up. Sketch from the vertex,
> then one honest point: $x = 3$ gives $y = -4$, and symmetry gives
> its mirror at $x = 1$.

> [!success]- Answer 2
> Start from $y = a(x - 3)^2 - 4$ and feed it the known point:
> $4 = a(2)^2 - 4$, so $a = 2$ and $y = 2(x - 3)^2 - 4$. Verify:
> $2(5-3)^2 - 4 = 4$. ✓

> [!success]- Answer 3
> Zeros $x = 1$ and $x = 5$; the axis splits them at $x = 3$, and the
> vertex sits there at $y = (2)(-2) = -4$. The zeros come free — the
> vertex costs one substitution.

> [!success]- Answer 4
> $y$-intercept $5$, read off the constant. Factoring
> $(x + 1)(x + 5)$ gives zeros $-1$ and $-5$; the axis is $x = -3$
> and the vertex is $(-3, -4)$. Three features, three sources.

> [!success]- Answer 5
> Vertex form: vertex $(1, -8)$. Factored: zeros $-1$ and $3$.
> Standard: $y$-intercept $-6$. At $x = 0$ all three give $-6$ ✓ —
> loyalty to one form is the only losing strategy.

> [!success]- Answer 6
> Reflect in the $x$-axis, compress vertically by factor
> $\frac{1}{2}$, translate right $3$ and up $4$: opens down, wide,
> vertex $(3, 4)$ — the sketch behind [[The Perfect Arc]].

> [!success]- Answer 7
> The points $(0, 0)$, $(0.5, 12)$, $(1.0, 50)$, $(1.5, 113)$, $(2.0, 200)$
> form a parabolic curve passing through the origin. Testing $d = at^2$
> with $(1.0, 50)$ gives $50 = a(1.0)^2$, so $a = 50$: $d = 50t^2$.
> Check other points: at $t = 2.0$, $d = 50(4) = 200$ cm ✓; at $t = 0.5$,
> $d = 50(0.25) = 12.5 \approx 12$ cm ✓. The quadratic model fits the
> experimental data closely.

> [!success]- Answer 8
> Values: for $y = x^2$: $(-2, 4), (-1, 1), (0, 0), (1, 1), (2, 4), (3, 9), (4, 16)$.
> For $y = 2^x$: $(-2, 0.25), (-1, 0.5), (0, 1), (1, 2), (2, 4), (3, 8), (4, 16)$.
> (a) Each step left in $2^x$ divides by 2; $\frac{2^1}{2} = 2^0 = 1$.
> (b) Negative exponents indicate repeated division:
> $2^{-1} = \frac{1}{2^1} = \frac{1}{2}$,
> $2^{-2} = \frac{1}{2^2} = \frac{1}{4}$.
> (c) $y = x^2$ is symmetric about $x = 0$ with a minimum turning point
> at $(0, 0)$ and two zeros; $y = 2^x$ has no vertical symmetry line,
> never reaches zero ($y > 0$), and overtakes $y = x^2$ for all $x > 4$.

> [!success]- Answer 9
> (a) Half of $-10$ is $-5$, squared is $25$:
> $y = (x^2 - 10x + 25) + 21 - 25 = (x - 5)^2 - 4$.
> Vertex: $(5, -4)$. (Check zeros: $(x - 5)^2 = 4 \implies x = 7$ or $3$,
> which factors $x^2 - 10x + 21 = (x - 7)(x - 3)$ ✓).
> (b) Factor $3$ from the $x$-terms: $y = 3(x^2 + 4x) + 5$. Half of $4$ is
> $2$, squared is $4$:
> $y = 3(x^2 + 4x + 4 - 4) + 5 = 3((x + 2)^2 - 4) + 5 = 3(x + 2)^2 - 12 + 5 = 3(x + 2)^2 - 7$.
> Vertex: $(-2, -7)$.

%%curriculum-start%%
## Curriculum connection

![[A1.1]]

![[A1.4]]

![[A2.3]]

![[A2.4]]

![[A3.3]]

![[A3.5]]
%%curriculum-end%%
