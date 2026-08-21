---
title: Factor Theorem Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[The Factor Theorem]] — remainders by
substitution, factoring cubics and quartics, and problems where the
unknown is a coefficient. Expand your factored answers to check them;
that audit is part of the question.

## Remainders and factors

1. Find the remainder when $f(x) = x^3 - 4x^2 + x + 6$ is divided by
   $x - 2$. What does the result tell you?
2. Find the remainder when $f(x) = 2x^3 - 3x^2 + 8x - 12$ is divided
   by $x - 1$.
3. Is $x - 1$ a factor of $x^4 - 6x^3 + 4x^2 + 6x - 5$? Decide
   without dividing.

> [!success]- Answer 1
> $f(2) = 8 - 16 + 2 + 6 = 0$. The remainder is 0, so by the factor
> theorem $x - 2$ is a factor of $f(x)$ — one substitution did the
> work of a whole long division.

> [!success]- Answer 2
> $f(1) = 2 - 3 + 8 - 12 = -5$. The remainder is $-5$, so $x - 1$ is
> not a factor — but you now know the point $(1, -5)$ is on the
> graph, because the remainder theorem and evaluation are the same
> act.

> [!success]- Answer 3
> $f(1) = 1 - 6 + 4 + 6 - 5 = 0$, so yes — $x - 1$ is a factor.
> (Keep this one in hand; question 8 finishes the job.)

## Factoring completely

4. Factor $x^3 + 2x^2 - x - 2$ by grouping.
5. Factor $x^3 - 4x^2 + x + 6$ completely.
6. Factor $x^4 - 13x^2 + 36$ completely, and solve
   $x^4 - 13x^2 + 36 = 0$.

> [!success]- Answer 4
> Group in pairs: $x^2(x + 2) - 1(x + 2) = (x + 2)(x^2 - 1)$, and
> the difference of squares finishes it:
> $(x + 2)(x + 1)(x - 1)$. No factor theorem needed — grouping got
> there first, which is why it stays on the strategy list.

> [!success]- Answer 5
> Candidates are the divisors of 6: $\pm 1, \pm 2, \pm 3, \pm 6$.
> $f(-1) = -1 - 4 - 1 + 6 = 0$, so $x + 1$ is a factor. Dividing
> gives $x^2 - 5x + 6 = (x - 2)(x - 3)$. So
> $f(x) = (x + 1)(x - 2)(x - 3)$. Check by expanding:
> $(x + 1)(x^2 - 5x + 6) = x^3 - 4x^2 + x + 6$. ✓

> [!success]- Answer 6
> Treat it as a quadratic in $x^2$:
> $(x^2 - 4)(x^2 - 9) = (x - 2)(x + 2)(x - 3)(x + 3)$. The roots of
> the equation are $x = \pm 2, \pm 3$ — and they are exactly the
> x-intercepts of the graph of $f(x) = x^4 - 13x^2 + 36$, which is
> the equation–graph connection in one example.

## Using the theorems

7. For what value of $k$ does $f(x) = x^3 + 5x^2 + kx + 2$ give the
   same remainder when divided by $x - 1$ as when divided by
   $x + 3$?
8. Factor $x^4 - 6x^3 + 4x^2 + 6x - 5$ completely, starting from
   what you learned in question 3.

> [!success]- Answer 7
> The two remainders are $f(1) = 1 + 5 + k + 2 = 8 + k$ and
> $f(-3) = -27 + 45 - 3k + 2 = 20 - 3k$. Setting them equal:
> $8 + k = 20 - 3k$, so $4k = 12$ and $k = 3$. Check: with $k = 3$,
> $f(1) = 11$ and $f(-3) = 20 - 9 = 11$. ✓

> [!success]- Answer 8
> From question 3, $x - 1$ is a factor. Dividing gives
> $x^3 - 5x^2 - x + 5$, which groups:
> $x^2(x - 5) - 1(x - 5) = (x - 5)(x^2 - 1)$. So
> $f(x) = (x - 1)^2(x + 1)(x - 5)$ — the factor $x - 1$ was hiding
> twice. Audit with fresh substitutions: $f(-1) = 1 + 6 + 4 - 6 - 5
> = 0$ ✓ and $f(5) = 625 - 750 + 100 + 30 - 5 = 0$. ✓

%%curriculum-start%%
## Curriculum connection

![[C3.1]]

![[C3.2]]

![[C3.3]]

![[C3.4]]

![[C3.7]]
%%curriculum-end%%
