---
title: Limits Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[The Limit]] and [[The Derivative]] —
watching limits happen numerically, taking them algebraically, and
reading what a difference quotient says about a graph. Take the
numeric road first where you can; the estimate audits the algebra.

## Watching limits happen

1. For $f(x) = x^2$, compute the average rate of change from $x = 3$
   to $x = 3 + h$ for $h = 1$, $h = 0.1$, and $h = 0.01$. What limit
   are the answers approaching?
2. Evaluate $\left(1 + \frac{1}{n}\right)^n$ for $n = 1$, $2$, $3$,
   and $10$. What number is this sequence creeping toward?
3. The Fibonacci sequence begins $1, 1, 2, 3, 5, 8, 13, \ldots$
   Compute the ratio of each term to the one before it, out to
   $\frac{13}{8}$. What value do the ratios approach?

> [!success]- Answer 1
> Each average rate is $\frac{(3+h)^2 - 9}{h}$. For $h = 1$:
> $\frac{16 - 9}{1} = 7$. For $h = 0.1$: $\frac{9.61 - 9}{0.1} =
> 6.1$. For $h = 0.01$: $\frac{9.0601 - 9}{0.01} = 6.01$. The march
> is $7$, $6.1$, $6.01$ — settling toward $6$, the slope of the
> tangent to $y = x^2$ at $x = 3$.

> [!success]- Answer 2
> $n = 1$: $2$. $n = 2$: $1.5^2 = 2.25$. $n = 3$:
> $\left(\frac{4}{3}\right)^3 = \frac{64}{27} \approx 2.370$.
> $n = 10$: $1.1^{10} \approx 2.594$. The sequence climbs toward
> $e \approx 2.718$ — slowly, but it never stops climbing and never
> passes $e$. You will meet this number properly in
> [[Derivatives of Exponential Functions]].

> [!success]- Answer 3
> $\frac{1}{1} = 1$, $\frac{2}{1} = 2$, $\frac{3}{2} = 1.5$,
> $\frac{5}{3} \approx 1.667$, $\frac{8}{5} = 1.6$,
> $\frac{13}{8} = 1.625$. The ratios bounce alternately above and
> below their destination, closing in on the golden ratio
> $\frac{1 + \sqrt{5}}{2} \approx 1.618$. A limit reached from both
> sides at once.

## Taking limits algebraically

4. Evaluate $\lim\limits_{x \to 2} \dfrac{x^2 - 4}{x - 2}$.
5. Evaluate $\lim\limits_{h \to 0} \dfrac{(3 + h)^2 - 9}{h}$ by
   simplifying first, and confirm it matches question 1.
6. Evaluate $\lim\limits_{h \to 0} \dfrac{(x + h)^3 - x^3}{h}$.
7. Evaluate $\lim\limits_{x \to 0} \dfrac{\sqrt{x + 9} - 3}{x}$.
   (Multiplying by a well-chosen form of 1 helps.)

> [!success]- Answer 4
> Substituting $x = 2$ gives $\frac{0}{0}$ — no verdict. Factor:
> $\frac{(x-2)(x+2)}{x-2} = x + 2$ everywhere except $x = 2$
> itself, and the limit only cares about the approach. As
> $x \to 2$, $x + 2 \to 4$. The limit is $4$.

> [!success]- Answer 5
> Expand: $\frac{9 + 6h + h^2 - 9}{h} = \frac{6h + h^2}{h} = 6 + h$.
> As $h \to 0$ this heads straight for $6$ — the same destination
> the numeric march in question 1 was pointing at. Two roads, one
> limit.

> [!success]- Answer 6
> Expand the cube: $(x+h)^3 = x^3 + 3x^2h + 3xh^2 + h^3$, so the
> quotient is $\frac{3x^2h + 3xh^2 + h^3}{h} = 3x^2 + 3xh + h^2$.
> As $h \to 0$, the limit is $3x^2$ — which is exactly the
> derivative of $x^3$, computed from the definition.

> [!success]- Answer 7
> Multiply numerator and denominator by $\sqrt{x + 9} + 3$:
> $$\frac{(x + 9) - 9}{x(\sqrt{x+9} + 3)} = \frac{1}{\sqrt{x+9} + 3}$$
> As $x \to 0$ this becomes $\frac{1}{3 + 3} = \frac{1}{6}$.
> Numeric audit: at $x = 0.01$, $\frac{\sqrt{9.01} - 3}{0.01}
> \approx 0.1666$. ✓

## Reading the derivative as a limit

8. You are told $\lim\limits_{h \to 0} \dfrac{f(4 + h) - f(4)}{h} = 8$
   for $f(x) = x^2$. What does this say about the graph of $f$? What
   would the same statement mean for a general function $y = f(x)$?
9. Use the definition of the derivative to determine $f'(x)$ for
   $f(x) = x^2 - 5x$.

> [!success]- Answer 8
> That limit is the definition of $f'(4)$: the slope of the tangent
> to $y = x^2$ at the point $(4, 16)$ is $8$ — equivalently, the
> instantaneous rate of change there is 8 units of $y$ per unit of
> $x$. For a general $f$, the statement says exactly the same
> thing about the point $(4, f(4))$: tangent slope 8, whatever the
> function is. The sentence is about the *point*, not the formula.

> [!success]- Answer 9
> $$\begin{aligned} \frac{(x+h)^2 - 5(x+h) - (x^2 - 5x)}{h}  \\ &= \frac{2xh + h^2 - 5h}{h} = 2x + h - 5 \end{aligned}$$
> As $h \to 0$: $f'(x) = 2x - 5$. Sanity check with the toolbox to
> come: the power rule will say the same thing in one line — but
> you just proved it, and that is better.

%%curriculum-start%%
## Curriculum connection

![[A1.1]]

![[A1.2]]

![[A1.3]]

![[A1.4]]
%%curriculum-end%%
