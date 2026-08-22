---
title: Domain and Range Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Domain and Range]]. For each function, give
both sets and — more importantly — the *reason* each restriction
exists. A stated reason is worth more than a memorised answer.

## From equations

1. $f(x) = x^2 - 3$
2. $f(x) = \sqrt{x - 4}$
3. $f(x) = \dfrac{1}{x + 2}$
4. $f(x) = 2\sqrt{x} + 1$

> [!success]- Answer 1
> Domain: all real numbers — squaring accepts anything. Range:
> $y \ge -3$, because $x^2 \ge 0$ always, and the whole graph is the
> parent parabola slid down 3.

> [!success]- Answer 2
> Domain: $x \ge 4$ — the root refuses negative input, so
> $x - 4 \ge 0$. Range: $y \ge 0$, since a square root never returns
> a negative. The parent's sets slid right 4 along with the graph.

> [!success]- Answer 3
> Domain: $x \ne -2$ — division by zero at exactly one input.
> Range: $y \ne 0$ — a fraction with numerator 1 can shrink toward
> zero forever but never arrive. Both restrictions are the parent
> $\frac{1}{x}$'s, with the vertical one slid left 2.

> [!success]- Answer 4
> Domain: $x \ge 0$. Range: $y \ge 1$ — the parent's outputs
> ($y \ge 0$) are stretched by 2 (still $\ge 0$) and then lifted
> by 1.

## From contexts

5. A ball's height is $h(t) = -5t^2 + 20t$ metres after $t$ seconds.
   State the domain and range *of the model*, not of the algebra.
6. Movie tickets cost \$14 each, so a group's cost is
   $C(n) = 14n$. What are the domain and range, and what makes this
   function different in kind from the ones above?

> [!success]- Answer 5
> The zeros of $h$ are $t = 0$ and $t = 4$ (factor:
> $-5t(t - 4)$), so the flight lasts from $t = 0$ to $t = 4$:
> domain $0 \le t \le 4$. The peak is midway, at $t = 2$, where
> $h(2) = 20$: range $0 \le h \le 20$. Algebra offered all real
> numbers; the physics declined.

> [!success]- Answer 6
> Domain: $n \in \{0, 1, 2, 3, \ldots\}$ — you cannot buy 2.7
> tickets. Range: $\{0, 14, 28, 42, \ldots\}$. This is a *discrete*
> function: its graph is separated dots, a kind you will meet again
> in [[Sequences and Their Rules]].

## Stretch

7. State the domain and range of $g(x) = -\sqrt{x}$, and explain how
   they differ from those of $\sqrt{x}$.
8. State the domain and range of $f(x) = \dfrac{3}{x - 1} + 2$.

> [!success]- Answer 7
> Domain: $x \ge 0$ — the reflection is vertical, so allowed inputs
> do not change. Range: $y \le 0$ — every output of $\sqrt{x}$ got
> its sign flipped. Reflections in the $x$-axis rewrite the range and
> leave the domain alone.

> [!success]- Answer 8
> The parent $\frac{1}{x}$ slid right 1 and up 2 (the 3 stretches
> but forbids nothing new). Domain: $x \ne 1$; range: $y \ne 2$.
> The excluded values are exactly the new asymptotes — sketch it or
> confirm in [[Using Desmos]], and the two gaps stare back at you.

%%curriculum-start%%
## Curriculum connection

![[A1.3]]
%%curriculum-end%%
