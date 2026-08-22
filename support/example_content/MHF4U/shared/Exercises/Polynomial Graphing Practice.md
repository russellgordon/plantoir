---
title: Polynomial Graphing Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Polynomial Functions]],
[[Zeros and Multiplicity]], and [[Even and Odd Functions]] — reading
graphs from equations, building equations from graphs, and putting
symmetry to work. Sketch on paper first; [[Using Desmos]] is for
checking, not producing.

## Reading equations

1. For $f(x) = -2x^4 + 5x^3 - x + 7$: state the degree, the leading
   coefficient, the end behaviour, and the y-intercept.
2. Without graphing, explain why $f(x) = x^3 - 4x$ must have at least
   one x-intercept — and why *every* odd-degree polynomial must.
3. Determine whether each function is even, odd, or neither, using
   algebra alone: (a) $f(x) = x^4 - 3x^2$ (b) $g(x) = x^3 - 4x$
   (c) $h(x) = x^3 + x^2$.

> [!success]- Answer 1
> Degree 4, leading coefficient $-2$. Even degree with a negative
> leading coefficient sends both ends down. The y-intercept is
> $f(0) = 7$. Everything came from two terms — the first and the
> last; the middle terms only matter close to the origin.

> [!success]- Answer 2
> An odd-degree polynomial has ends pointing in *opposite* vertical
> directions — here, down on the left and up on the right. A
> polynomial is continuous, so to get from below the axis to above
> it, the graph must cross it somewhere. Even-degree polynomials get
> no such guarantee: $x^2 + 1$ never crosses.

> [!success]- Answer 3
> (a) $f(-x) = (-x)^4 - 3(-x)^2 = x^4 - 3x^2 = f(x)$ — even.
> (b) $g(-x) = -x^3 + 4x = -(x^3 - 4x) = -g(x)$ — odd.
> (c) $h(-x) = -x^3 + x^2$, which is neither $h(x)$ nor $-h(x)$ —
> neither. The mixed exponent parities (3 and 2) gave it away before
> the algebra confirmed it.

## Sketching from factored form

4. Sketch $f(x) = (x + 2)(x - 1)^2$: give the zeros, the behaviour
   at each zero, the end behaviour, and the y-intercept.
5. Sketch $f(x) = -(x - 3)(x + 1)^3$: same four features.
6. Solve $x^4 - 10x^2 + 9 < 0$, and give the solution algebraically.

> [!success]- Answer 4
> Zeros: $x = -2$ (multiplicity 1 — the graph cuts through) and
> $x = 1$ (multiplicity 2 — the graph touches and turns back).
> Degree 3 with a positive leading coefficient: down-left, up-right.
> y-intercept: $f(0) = (2)(-1)^2 = 2$. So the graph rises through
> $-2$, passes $(0, 2)$, bounces off the axis at $1$, and leaves
> upward.

> [!success]- Answer 5
> Zeros: $x = 3$ (multiplicity 1 — cuts through) and $x = -1$
> (multiplicity 3 — crosses, but flattens as it does, like $x^3$).
> Total degree 4 with leading coefficient $-1$: both ends down.
> y-intercept: $f(0) = -(-3)(1)^3 = 3$.

> [!success]- Answer 6
> Factor as a quadratic in $x^2$:
> $x^4 - 10x^2 + 9 = (x^2 - 1)(x^2 - 9)$, so the zeros are
> $\pm 1, \pm 3$. The product is negative when exactly one factor
> is — that is, when $1 < x^2 < 9$. Solution: $-3 < x < -1$ or
> $1 < x < 3$. Test $x = 2$: $(4-1)(4-9) = -15 < 0$. ✓

## Building equations

7. A cubic has zeros $2$, $-1$, and $-4$, and passes through
   $(1, 20)$. Determine its equation.
8. A quartic touches the x-axis at $-2$ and at $3$ (nowhere else)
   and passes through $(0, -36)$. Determine its equation.

> [!success]- Answer 7
> The family is $f(x) = k(x - 2)(x + 1)(x + 4)$. Substituting
> $(1, 20)$: $k(-1)(2)(5) = -10k = 20$, so $k = -2$ and
> $f(x) = -2(x - 2)(x + 1)(x + 4)$. Check: $f(1) = -2(-1)(2)(5) =
> 20$. ✓ Without the point, any $k$ would do — three zeros pick a
> family, not a function.

> [!success]- Answer 8
> "Touches" means even multiplicity, and a quartic budget forces
> multiplicity 2 at each: $f(x) = k(x + 2)^2(x - 3)^2$. Substituting
> $(0, -36)$: $k(4)(9) = 36k = -36$, so $k = -1$ and
> $f(x) = -(x + 2)^2(x - 3)^2$. A negative $k$ makes sense: the
> graph opens downward, touching the axis from below.

## One last audit

9. Which of these define polynomial functions, and which do not?
   $f(x) = 4$; $g(x) = 3x - 7$; $h(x) = x^2 - 5x$;
   $p(x) = 2x^3 - \sqrt{x}$; $q(x) = \dfrac{5}{x} + 1$;
   $r(x) = x^4 - 2x^{-1}$. For each one that does, say why the
   equation defines a *function* at all — and say where the linear and
   quadratic functions you met in Grade 10 sit in this family.

> [!success]- Answer 9
> Polynomials: $f$, $g$ and $h$. A polynomial expression is a sum of
> terms, each a constant times a power of $x$ with a whole-number
> exponent — so $\sqrt{x} = x^{1/2}$ disqualifies $p$, and the
> negative exponents hiding inside $\frac{5}{x}$ and $2x^{-1}$
> disqualify $q$ and $r$. Every one of them is a *function*, though,
> and for the same reason: substituting a number for $x$ triggers a
> chain of additions and multiplications with no choices in it, so one
> input can only ever produce one output.
>
> And the family is older than it looks. $f(x) = 4$ is a polynomial of
> degree zero, $g$ is degree one, $h$ is degree two — the lines and
> parabolas of Grade 10 are simply the first two rungs of the ladder
> this whole unit climbs. Nothing new was invented at the start of the course; the
> degree just went up.

%%curriculum-start%%
## Curriculum connection

![[C1.1]]

![[C1.3]]

![[C1.5]]

![[C1.7]]

![[C1.8]]

![[C1.9]]

![[C4.3]]
%%curriculum-end%%
