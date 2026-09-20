---
title: Quadratic Formula Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Zeros and the Quadratic Formula]] — the tool
your group reached for when [[The Perfect Arc]] asked exactly where
the ball comes down. House rule: *try factoring first*. The formula
is for equations that will not budge, not a substitute for noticing.

## Questions

1. Solve $x^2 - 7x + 12 = 0$ by the most efficient method, and
   verify one root.
2. Solve $x^2 + 4x - 7 = 0$ exactly, then **verify one root by
   substitution** into the original equation.
3. Without solving, use the discriminant $b^2 - 4ac$ to predict how
   many $x$-intercepts each relation has: (a) $y = x^2 - 6x + 9$;
   (b) $y = 2x^2 + x + 5$.
4. A ball's height in metres is $h = -5t^2 + 14t + 3$, with $t$ in
   seconds. When does it land?
5. **Find the error.** Solving $x^2 - 2x - 8 = 0$, Ava writes
   $x = \frac{-2 \pm \sqrt{4 + 32}}{2}$ and gets $x = 2$ and $x = -4$.
   Check one of her roots, find the slip, and finish it correctly.
6. **Challenge.** For what value of $k$ does $x^2 + 6x + k = 0$
   have exactly one root? Explain using the discriminant.
7. **Explore the development.** The general quadratic equation
   $ax^2 + bx + c = 0$ is solved by completing the square in four
   steps: (1) divide by $a$ and isolate constants,
   $x^2 + \frac{b}{a}x = -\frac{c}{a}$; (2) add
   $(\frac{b}{2a})^2 = \frac{b^2}{4a^2}$ to both sides; (3) factor the
   left side as $(x + \frac{b}{2a})^2 = \frac{b^2 - 4ac}{4a^2}$;
   (4) take square roots and solve for
   $x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$.
   Match each step to the numerical equation $2x^2 + 8x - 10 = 0$.

## Answers

> [!success]- Answer 1
> It factors: $(x - 3)(x - 4) = 0$, so $x = 3$ or $x = 4$. Verify
> $x = 3$: $9 - 21 + 12 = 0$. ✓ No formula required.

> [!success]- Answer 2
> No integer pair multiplies to $-7$ and adds to $4$, so the formula:
> $x = \frac{-4 \pm \sqrt{16 + 28}}{2} = -2 \pm \sqrt{11}$. Verify
> $x = -2 + \sqrt{11}$: squaring gives $15 - 4\sqrt{11}$; adding
> $4x = -8 + 4\sqrt{11}$ and then $-7$ leaves $0$. ✓ The surds cancel
> — that cancellation *is* the verification.

> [!success]- Answer 3
> (a) $36 - 36 = 0$: one $x$-intercept — the vertex sits on the axis.
> (b) $1 - 40 = -39 < 0$: none — the parabola never reaches the axis.
> The discriminant answers "how many" without finding "where".

> [!success]- Answer 4
> Set $h = 0$: $5t^2 - 14t - 3 = 0$ factors as $(5t + 1)(t - 3) = 0$:
> $t = 3$ or $t = -\frac{1}{5}$. Negative time is before the throw —
> the ball lands at $t = 3$ s. Rejecting a root is interpreting it.

> [!success]- Answer 5
> Check $x = -4$: $16 + 8 - 8 = 16 \neq 0$ — the check fails, doing
> its job. With $b = -2$ the formula needs $-b = 2$, not $-2$: Ava
> kept the minus. Correctly $x = \frac{2 \pm 6}{2}$, so $x = 4$ or
> $x = -2$, and both survive substitution. ✓

> [!success]- Answer 6
> Exactly one root needs $b^2 - 4ac = 0$: $36 - 4k = 0$, so $k = 9$.
> Sensible, because $x^2 + 6x + 9 = (x + 3)^2$ — a perfect square,
> touching the axis once at $x = -3$.

> [!success]- Answer 7
> Step 1: Divide by 2 and isolate: $x^2 + 4x = 5$.
> Step 2: Add $(\frac{4}{2})^2 = 4$ to both sides: $x^2 + 4x + 4 = 5 + 4 = 9$.
> Step 3: Factor left side: $(x + 2)^2 = 9$.
> Step 4: Square roots: $x + 2 = \pm 3 \implies x = -2 \pm 3$, giving
> $x = 1$ or $x = -5$.
> The general formula is simply completing the square on parameters — the
> development [[Zeros and the Quadratic Formula]] demonstrates.

%%curriculum-start%%
## Curriculum connection

![[A3.4]]

![[A3.7]]

![[A3.8]]
%%curriculum-end%%
