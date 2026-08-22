---
title: Linear Systems Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Linear Systems]] and
[[Solving Systems Algebraically]] — reasoning built at the boards in
[[Crossing Paths]]. Every solution ends checked in *both* equations:
a point that satisfies only one line is just a resident.

## Questions

1. Solve by graphing: $y = 2x - 1$ and $y = -x + 5$.
2. Solve by substitution: $y = 3x - 4$ and $2x + y = 11$. Check your
   point in both equations.
3. Solve by elimination: $3x + 2y = 19$ and $5x - 2y = 5$.
4. Try to solve $2x + 3y = 12$ and $4x + 6y = 30$. What happens
   algebraically — and what must the graphs be doing?
5. **Create, then solve.** A school play sells 250 tickets. Adult
   tickets cost \$12, student tickets \$8, and the total is
   \$2540. How many of each sold? This is [[Break-Even]] mathematics.
6. **Find the error.** Substituting $y = 2x - 5$ into $3x - 2y = 8$,
   Noah writes $3x - 4x - 10 = 8$ and gets $x = -18$. Find the slip,
   fix it, and check the corrected point in both equations.
7. **Challenge.** Create a system whose solution is $(-1, 4)$, where
   neither equation starts with $y$ isolated. Prove it works.
8. **Slope formula and line equation.** A line passes through $A(-2, 7)$
   and $B(4, -5)$. (a) Develop and apply the slope formula
   $m = \frac{y_2 - y_1}{x_2 - x_1}$ to find its slope. (b) Use the slope
   and one point to determine the equation of the line in slope-intercept
   form $y = mx + b$.
9. **Translating between linear forms.** (a) Convert the equation
   $y = \frac{3}{4}x - 5$ to standard form $Ax + By + C = 0$, where
   $A, B, C$ are integers and $A \ge 0$. (b) Convert $2x - 5y = 15$ to
   slope-intercept form $y = mx + b$ and identify its slope and
   $y$-intercept.

## Answers

> [!success]- Answer 1
> The lines cross at $(2, 3)$: $2x - 1 = -x + 5$ gives $3x = 6$, so
> $x = 2$, $y = 3$. Check: $2(2) - 1 = 3$ ✓ and $-2 + 5 = 3$ ✓.

> [!success]- Answer 2
> $2x + (3x - 4) = 11$, so $5x = 15$: $x = 3$, $y = 5$. Check both:
> $5 = 9 - 4$ ✓ and $6 + 5 = 11$ ✓.

> [!success]- Answer 3
> Adding eliminates $y$: $8x = 24$, so $x = 3$, and $9 + 2y = 19$
> gives $y = 5$. Check the equation you did *not* use: $15 - 10 = 5$ ✓.

> [!success]- Answer 4
> Doubling the first gives $4x + 6y = 24$; the second insists on $30$.
> No point can do both — no solution: same slope, different intercepts.

> [!success]- Answer 5
> With $a + s = 250$ and $12a + 8s = 2540$, substituting
> $a = 250 - s$ gives $3000 - 4s = 2540$, so $s = 115$, $a = 135$.
> Check the story: $135 + 115 = 250$ ✓ and $1620 + 920 = 2540$ ✓.

> [!success]- Answer 6
> The $-2$ must multiply *all* of $y$ — brackets first. Correctly,
> $3x - 2(2x - 5) = 3x - 4x + 10$, so $-x + 10 = 8$: $x = 2$,
> $y = -1$. Check: $-1 = 4 - 5$ ✓ and $6 + 2 = 8$ ✓ — dropped
> brackets earn a wing in the museum of [[Mistakes Are Data]].

> [!success]- Answer 7
> Answers vary. Build outward from $(-1, 4)$: since $-1 + 4 = 3$ and
> $2(-1) - 4 = -6$, one system is $x + y = 3$ with $2x - y = -6$ —
> checks pass by construction. Creating a system is solving, reversed.

> [!success]- Answer 8
> (a) The slope formula measures vertical rise over horizontal run:
> $m = \frac{-5 - 7}{4 - (-2)} = \frac{-12}{6} = -2$.
> (b) Substitute $m = -2$ and $(4, -5)$ into $y = mx + b$:
> $-5 = -2(4) + b \implies b = 3$. Equation: $y = -2x + 3$. Verify with
> $A(-2, 7)$: $-2(-2) + 3 = 7$ ✓.

> [!success]- Answer 9
> (a) Multiply all terms by 4 to clear fractions: $4y = 3x - 20$.
> Rearrange to $3x - 4y - 20 = 0$. (Check at $x = 0$: $y = -5$ gives
> $-4(-5) - 20 = 0$ ✓).
> (b) Isolate $y$: $-5y = -2x + 15 \implies y = \frac{2}{5}x - 3$.
> Slope $m = \frac{2}{5}$, $y$-intercept $(0, -3)$.

%%curriculum-start%%
## Curriculum connection

![[B1.1]]

![[B1.2]]

![[B1.4]]

![[B1.5]]
%%curriculum-end%%
