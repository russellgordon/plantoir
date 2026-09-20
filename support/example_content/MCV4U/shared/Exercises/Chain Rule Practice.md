---
title: Chain Rule Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[The Chain Rule]] — brackets to a power,
then the rational and radical disguises, then chains in the
abstract. Before each derivative, say the inside and the outside out
loud; the sorting is most of the skill.

## The rule itself

1. Differentiate $f(x) = (x^2 + 1)^2$ twice: once with the chain
   rule, once by expanding first. Confirm the answers agree.
2. Differentiate $f(x) = (2x^3 - 5)^4$.
3. Differentiate $f(x) = (5x^3)^{1/3}$ with the chain rule, then
   simplify the original function first and differentiate again.
   Confirm the answers agree.

> [!success]- Answer 1
> Chain rule: outside is a square, inside is $x^2 + 1$, so
> $f'(x) = 2(x^2 + 1) \cdot 2x = 4x(x^2 + 1) = 4x^3 + 4x$.
> Expanding first: $f(x) = x^4 + 2x^2 + 1$, so
> $f'(x) = 4x^3 + 4x$. ✓ Same answer, and the expanded road will
> stop being available the moment the exponent is $\frac{1}{2}$.

> [!success]- Answer 2
> Outside: fourth power. Inside: $2x^3 - 5$, whose derivative is
> $6x^2$.
> $$f'(x) = 4(2x^3 - 5)^3 \cdot 6x^2 = 24x^2(2x^3 - 5)^3$$
> No expansion required — that is the whole point.

> [!success]- Answer 3
> Chain rule:
> $f'(x) = \frac{1}{3}(5x^3)^{-2/3} \cdot 15x^2 = 5x^2(5x^3)^{-2/3}$,
> which simplifies to $5^{1/3}$ (the $x^2$ cancels against
> $x^{-2}$). Simplifying first: $f(x) = 5^{1/3}x$, a line, so
> $f'(x) = 5^{1/3}$ immediately. Both roads give the constant
> $5^{1/3}$ — the function was a straight line in disguise, and the
> chain rule saw through it.

## Rational and radical disguises

4. Differentiate $f(x) = \sqrt{x^2 + 5}$, and evaluate $f'(2)$.
5. Express $f(x) = \dfrac{x^2 + 1}{x - 1}$ as a product, and
   differentiate it. Write the answer as a single fraction.
6. Differentiate $f(x) = \dfrac{1}{\sqrt{3x + 1}}$, and evaluate
   $f'(1)$.

> [!success]- Answer 4
> As a power: $f(x) = (x^2 + 5)^{1/2}$, so
> $$\begin{aligned} f'(x) &= \frac{1}{2}(x^2 + 5)^{-1/2} \cdot 2x \\ &= \frac{x}{\sqrt{x^2 + 5}} \end{aligned}$$
> At $x = 2$: $f'(2) = \frac{2}{\sqrt{9}} = \frac{2}{3}$.

> [!success]- Answer 5
> $f(x) = (x^2 + 1)(x - 1)^{-1}$. Product rule, with the chain rule
> on the second factor:
> $$f'(x) = 2x(x - 1)^{-1} + (x^2 + 1)(-1)(x - 1)^{-2}$$
> Common denominator $(x - 1)^2$:
> $$\begin{aligned} f'(x) &= \frac{2x(x - 1) - (x^2 + 1)}{(x - 1)^2} \\ &= \frac{x^2 - 2x - 1}{(x - 1)^2} \end{aligned}$$
> Audit at $x = 0$: $f'(0) = \frac{-1}{1} = -1$, and nearby values
> of $f$ confirm a slope near $-1$ there.

> [!success]- Answer 6
> As a power: $f(x) = (3x + 1)^{-1/2}$, so
> $$\begin{aligned} f'(x) &= -\frac{1}{2}(3x + 1)^{-3/2} \cdot 3 \\ &= \frac{-3}{2(3x + 1)^{3/2}} \end{aligned}$$
> At $x = 1$: $(4)^{3/2} = 8$, so $f'(1) = -\frac{3}{16}$. Negative
> is right — the function shrinks as its denominator grows.

## Chains in the abstract

7. Suppose $h(x) = f(g(x))$, with $g(2) = 3$, $g'(2) = 4$, and
   $f'(3) = 5$. Determine $h'(2)$, and explain the answer in terms
   of rates.

> [!success]- Answer 7
> $h'(2) = f'(g(2)) \cdot g'(2) = f'(3) \times 4 = 5 \times 4 =
> 20$. In words: near $x = 2$ the inner machine runs at 4 output
> units per input unit, and near the value 3 the outer machine
> amplifies whatever it receives 5 times over. Rates through a
> chain multiply: $20$. Note which numbers went *unused* — $f'(2)$
> never appeared, because the outer machine is evaluated where the
> inner one *delivers*, not where you started.

%%curriculum-start%%
## Curriculum connection

![[A3.4]]

![[A3.5]]
%%curriculum-end%%
