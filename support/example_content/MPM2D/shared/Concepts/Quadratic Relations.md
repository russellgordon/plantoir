---
title: Quadratic Relations
publish: true
created: __CREATED__
tags:
  - concepts
---
Counting handshakes at the boards in [[The Handshake Problem]], your
group built a table whose first differences kept growing — 1, then
2, then 3 — and the growth itself grew steadily. The growing dot
arrangements in [[Visual Patterns]] did the same thing. Linear
relations grow by a constant amount; these relations grow by a
constantly *changing* amount, and they are called quadratic.

A quadratic relation has the form $y = ax^2 + bx + c$ with
$a \ne 0$, and its graph is a parabola — a symmetric curve with a
single turning point.

## Second differences — the fingerprint

Take $y = x^2 - 4x$ and difference the table twice:

| $x$ | $y$ | 1st difference | 2nd difference |
| --- | --- | --- | --- |
| 0 | $0$ | | |
| 1 | $-3$ | $-3$ | |
| 2 | $-4$ | $-1$ | $2$ |
| 3 | $-3$ | $1$ | $2$ |
| 4 | $0$ | $3$ | $2$ |

The first differences change, but the *second* differences are
constant — that is the fingerprint. Constant first differences mean
linear; constant second differences mean quadratic, no graph
required. (The constant turns out to be $2a$, which is a lovely
thing to verify for yourself with a few equations of your own.)

## The features of a parabola

Every parabola has the same anatomy, and naming the parts precisely
is half the work of describing one:

- the **vertex** — the turning point, where the maximum or minimum
  value lives
- the **axis of symmetry** — the vertical line through the vertex;
  for $y = x^2 - 4x$ it is $x = 2$
- the **zeros** — where the graph crosses the $x$-axis, here
  $x = 0$ and $x = 4$; the axis of symmetry is their average
- the **$y$-intercept** — the value when $x = 0$; it is always $c$

Symmetry is the parabola's great gift: every point has a mirror
twin across the axis, so half the graph comes free. Zeros at $0$
and $4$ place the vertex at $x = 2$ before any algebra happens.

Different forms of the equation surrender different features —
[[The Vertex Form]] hands you the vertex, and
[[Zeros and the Quadratic Formula]] hands you the zeros.
[[Quadratic Graphing Practice]] builds fluency with the whole
anatomy at once.

## Comparing with exponential growth

Not all non-linear curves behave the same way. In
[[Squares Against Doubling]], we race $y = x^2$ against $y = 2^x$:

| $x$ | $y = x^2$ (Quadratic) | $y = 2^x$ (Exponential) |
| --- | --- | --- |
| $-2$ | $(-2)^2 = 4$ | $2^{-2} = \frac{1}{2^2} = \frac{1}{4}$ |
| $-1$ | $(-1)^2 = 1$ | $2^{-1} = \frac{1}{2^1} = \frac{1}{2}$ |
| $0$ | $0^2 = 0$ | $2^0 = 1$ |
| $1$ | $1^2 = 1$ | $2^1 = 2$ |
| $2$ | $2^2 = 4$ | $2^2 = 4$ |
| $3$ | $3^2 = 9$ | $2^3 = 8$ |
| $4$ | $4^2 = 16$ | $2^4 = 16$ |
| $5$ | $5^2 = 25$ | $2^5 = 32$ |

Examining patterns in the table explains zero and negative exponents:
- **Zero as an exponent ($2^0 = 1$)**: moving one step left in the
  $2^x$ column divides by 2; $\frac{2^1}{2} = 2^{1-1} = 2^0 = 1$.
- **Negative exponents ($2^{-n} = \frac{1}{2^n}$)**: continuing to
  divide by 2 produces unit fractions ($2^{-1} = \frac{1}{2}$,
  $2^{-2} = \frac{1}{4}$, $2^{-3} = \frac{1}{8}$).
- **Contrasting features**: the parabola $y = x^2$ is symmetric about
  the $y$-axis with a minimum turning point at $(0, 0)$ and constant
  second differences of 2. The exponential curve $y = 2^x$ has no
  symmetry, approaches the $x$-axis as an asymptote without ever
  touching zero, and eventually overtakes polynomial growth for all
  $x > 4$.

%%curriculum-start%%
## Curriculum connection

![[A1.2]]

![[A1.3]]

![[A1.4]]
%%curriculum-end%%
