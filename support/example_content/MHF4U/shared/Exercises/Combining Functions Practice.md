---
title: Combining Functions Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Combining Functions]] — arithmetic on whole
functions, composition in both orders, domains, and the combined
models your [[The Signature Function|Signature Function]] may need.

## Sums, differences, products, quotients

1. Let $f(x) = x^2 - 4$ and $g(x) = x + 2$. Find $(f + g)(x)$,
   $(f - g)(3)$, and $\left(\dfrac{f}{g}\right)(x)$ with its domain.
2. Let $h(x) = x^2 + 2^x$. Describe the end behaviour of $h$ in both
   directions, and explain why $h$ has no zeros.
3. Two odd functions are multiplied. Prove that the product is even.

> [!success]- Answer 1
> $(f + g)(x) = x^2 + x - 2$. $(f - g)(3) = f(3) - g(3) = 5 - 5 =
> 0$. For the quotient:
> $\left(\frac{f}{g}\right)(x) = \frac{(x-2)(x+2)}{x+2} = x - 2$,
> but the domain excludes $x = -2$, where the original denominator
> is zero — so the graph is the line $y = x - 2$ with a hole at
> $(-2, -4)$. Dividing functions is how rational functions, holes
> and all, were born.

> [!success]- Answer 2
> As $x \to \infty$, both terms explode upward, with $2^x$
> eventually dwarfing $x^2$. As $x \to -\infty$, the exponential
> fades to 0 and the parabola takes over, so $h$ climbs like $x^2$,
> hugging it from just above. No zeros: $x^2 \ge 0$ and $2^x > 0$
> always, so their sum is strictly positive — the parts can vouch
> for the whole.

> [!success]- Answer 3
> Let $f$ and $g$ be odd, and let $p(x) = f(x)g(x)$. Then
> $p(-x) = f(-x)g(-x) = \big(-f(x)\big)\big(-g(x)\big) = f(x)g(x)
> = p(x)$ — even, for every $x$. The two negatives cancel, exactly
> as they do for the odd integers the functions are named after.

## Composition

4. Let $f(x) = x + 1$ and $g(x) = 2x$. Compute $f(g(x))$ and
   $g(f(x))$. Are they equal?
5. Using this table, evaluate $f(g(1))$, $g(f(3))$, and $f(f(2))$.

   | $x$ | $f(x)$ | $g(x)$ |
   | --- | ------ | ------ |
   | 1   | 3      | 2      |
   | 2   | 1      | 4      |
   | 3   | 4      | 1      |
   | 4   | 2      | 3      |

6. Let $f(x) = \sqrt{x}$ and $g(x) = x - 3$. State $f(g(x))$ and
   $g(f(x))$, each with its domain.
7. A car travels $d(t) = 90t$ kilometres in $t$ hours, and fuel for
   a trip of $d$ kilometres costs $C(d) = 0.08d$ dollars. Evaluate
   $C(d(4))$ and interpret it. What relationship does $C(d(t))$
   represent?
8. Let $f(x) = 3x - 2$. Find $f^{-1}(x)$, then verify both
   $f(f^{-1}(x)) = x$ and $f^{-1}(f(x)) = x$.

> [!success]- Answer 4
> $f(g(x)) = f(2x) = 2x + 1$, but $g(f(x)) = g(x + 1) = 2x + 2$.
> Not equal — doubling then adding one is a different recipe from
> adding one then doubling, and composition remembers the order.

> [!success]- Answer 5
> Work inside out. $f(g(1)) = f(2) = 1$. $g(f(3)) = g(4) = 3$.
> $f(f(2)) = f(1) = 3$. No formulas anywhere — composition is about
> plumbing outputs into inputs, and a table exposes that more
> honestly than an equation does.

> [!success]- Answer 6
> $f(g(x)) = \sqrt{x - 3}$: we need $g$'s output to be acceptable
> to $f$, so $x - 3 \ge 0$, giving domain $x \ge 3$.
> $g(f(x)) = \sqrt{x} - 3$: only $f$'s own requirement applies, so
> domain $x \ge 0$. Same two machines, different order, different
> domains — the plumbing decides.

> [!success]- Answer 7
> $d(4) = 360$ km, so $C(d(4)) = 0.08 \times 360 = \textdollar 28.80$ — the
> fuel cost of a four-hour trip. In general
> $C(d(t)) = 0.08(90t) = 7.2t$: cost as a function of *time*, the
> middle variable composed away. Chained dependencies collapse into
> one function — that is composition's whole job.

> [!success]- Answer 8
> Swap and solve: $x = 3y - 2$ gives $f^{-1}(x) = \frac{x + 2}{3}$.
> Forward: $f(f^{-1}(x)) = 3 \cdot \frac{x+2}{3} - 2 = x$. ✓
> Backward: $f^{-1}(f(x)) = \frac{(3x - 2) + 2}{3} = x$. ✓
> Each machine run through the other returns every input untouched —
> the defining handshake of a function and its inverse, and exactly
> how [[The Logarithm|the logarithm]] and the exponential treat each
> other.

## When algebra runs out

9. Explain why $\cos x = x$ cannot be solved by algebraic
   rearrangement, then find its solution to two decimal places
   anyway.

> [!success]- Answer 9
> No sequence of algebraic moves isolates an $x$ that appears both
> inside a cosine and outside it — the two sides are different
> species of function. But a graph settles everything: $y = \cos x$
> and $y = x$ cross exactly once (the line leaves the strip
> $-1 \le y \le 1$ almost immediately). Trapping the crossing:
> $\cos 0.7 \approx 0.765 > 0.7$ and $\cos 0.8 \approx 0.697 <
> 0.8$, so the solution is between; tightening the bracket gives
> $x \approx 0.74$. Numerical answers to unalgebraic questions are
> not a concession — they are the method.

%%curriculum-start%%
## Curriculum connection

![[D2.1]]

![[D2.3]]

![[D2.4]]

![[D2.5]]

![[D2.6]]

![[D2.7]]

![[D3.2]]
%%curriculum-end%%
