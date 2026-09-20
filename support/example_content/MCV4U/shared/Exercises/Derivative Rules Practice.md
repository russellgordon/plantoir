---
title: Derivative Rules Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Derivative Rules]] — the power rule and its
reasonable companions, the product rule, and slopes on demand.
Fluency is the goal; speed will arrive on its own, uninvited.

## Power, sum, and constant multiple

1. Verify the power rule for $f(x) = x^4$ using the definition of
   the derivative.
2. Differentiate $f(x) = 5x^3 - 4x + 7$, and determine the
   instantaneous rate of change at $x = -1$.
3. Differentiate $f(x) = \sqrt{x}$, and determine the slope of the
   tangent at $x = 9$.

> [!success]- Answer 1
> Expand $(x + h)^4 = x^4 + 4x^3h + 6x^2h^2 + 4xh^3 + h^4$, so
> $$\frac{(x+h)^4 - x^4}{h} = 4x^3 + 6x^2h + 4xh^2 + h^3$$
> As $h \to 0$, everything carrying an $h$ vanishes:
> $f'(x) = 4x^3$. The exponent hopped down front, the power dropped
> by one — the conjectured pattern, certified.

> [!success]- Answer 2
> Term by term: $f'(x) = 15x^2 - 4 + 0$. The constant 7 contributes
> nothing — flat pieces have no rate. At $x = -1$:
> $f'(-1) = 15(1) - 4 = 11$.

> [!success]- Answer 3
> Rewrite as a power: $f(x) = x^{1/2}$, so
> $f'(x) = \frac{1}{2}x^{-1/2} = \frac{1}{2\sqrt{x}}$. At $x = 9$:
> $f'(9) = \frac{1}{2 \times 3} = \frac{1}{6}$. Reasonable? The
> square root curve is climbing but flattening at $x = 9$ — a small
> positive slope is exactly right.

## The product rule

4. Differentiate $f(x) = (3x + 2)(2x^2 - 1)$ twice: once with the
   product rule, once by expanding first. Confirm the answers agree.
5. Differentiate $f(x) = (x^2 + 1)(x^3 - 2x)$ using the product
   rule.

> [!success]- Answer 4
> Product rule:
> $f'(x) = 3(2x^2 - 1) + (3x + 2)(4x) = 6x^2 - 3 + 12x^2 + 8x$,
> which is $18x^2 + 8x - 3$. Expanding first:
> $f(x) = 6x^3 + 4x^2 - 3x - 2$, so $f'(x) = 18x^2 + 8x - 3$. The
> two roads agree — and that agreement is the reason to trust the
> product rule on functions you *cannot* expand.

> [!success]- Answer 5
> $$f'(x) = 2x(x^3 - 2x) + (x^2 + 1)(3x^2 - 2)$$
> $$= 2x^4 - 4x^2 + 3x^4 - 2x^2 + 3x^2 - 2 = 5x^4 - 3x^2 - 2$$
> Audit by expanding: $f(x) = x^5 - x^3 - 2x$ gives
> $f'(x) = 5x^4 - 3x^2 - 2$. ✓

## Slopes on demand

6. Determine the derivative of $f(x) = 2x^3 + 3x^2$, and the
   point(s) on the graph where the slope of the tangent is 36.
7. Determine the equation of the tangent line to
   $f(x) = x^3 - 3x^2 + 2$ at $x = 1$.
8. Water flows into two barrels. The volumes in litres after $t$
   minutes are $f(t)$ and $g(t)$. Explain what $f'(t)$, $g'(t)$,
   $f'(t) + g'(t)$, and $(f + g)'(t)$ each represent, and how this
   story verifies the sum rule.

> [!success]- Answer 6
> $f'(x) = 6x^2 + 6x$. Set it to 36: $6x^2 + 6x - 36 = 0$, so
> $x^2 + x - 6 = (x + 3)(x - 2) = 0$, giving $x = -3$ and $x = 2$.
> The points: $f(-3) = -54 + 27 = -27$ and $f(2) = 16 + 12 = 28$,
> so $(-3, -27)$ and $(2, 28)$. Two points — a cubic's slopes
> repeat, once on each arm.

> [!success]- Answer 7
> Point: $f(1) = 1 - 3 + 2 = 0$, so $(1, 0)$. Slope:
> $f'(x) = 3x^2 - 6x$, so $f'(1) = 3 - 6 = -3$. Line through
> $(1, 0)$ with slope $-3$: $y = -3(x - 1)$, or $y = -3x + 3$.

> [!success]- Answer 8
> $f'(t)$ and $g'(t)$ are the flow rates into each barrel, in
> litres per minute. Their sum $f'(t) + g'(t)$ is the combined
> inflow measured barrel by barrel; $(f + g)'(t)$ is the rate the
> *total* volume grows, measured on the total. Water does not care
> how you account for it — both describe the same litres arriving
> per minute, so they must be equal. That physical certainty is the
> sum rule: $(f + g)' = f' + g'$.

%%curriculum-start%%
## Curriculum connection

![[A2.1]]

![[A2.2]]

![[A2.3]]

![[A3.1]]

![[A3.2]]

![[A3.3]]
%%curriculum-end%%
