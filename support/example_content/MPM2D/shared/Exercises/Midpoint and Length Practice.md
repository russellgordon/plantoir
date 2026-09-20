---
title: Midpoint and Length Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Midpoint and Length]] — formulas invented at
the boards, one right-triangle sketch at a time, in the grid work that
opens [[The Quadrilateral Case File]]. The midpoint is an average; the
length is Pythagoras wearing coordinates.

## Questions

1. Find the midpoint of the segment joining $A(2, 6)$ and $B(8, 10)$.
2. Find the length of the segment joining $C(-3, 1)$ and $D(5, 7)$.
3. $M(1, 2)$ is the midpoint of a segment with one endpoint at
   $P(-4, 7)$. Find the other endpoint, and verify.
4. In $\triangle ABC$ with $A(0, 0)$, $B(8, 0)$, and $C(4, 6)$, find
   the midpoints of $AC$ and $BC$, then the length between them.
   Compare that length with $AB$. Noticing anything?
5. **Which formula, and why.** A trail runs straight from $(1, 3)$ to
   $(9, 9)$, units in kilometres. Decide which formula answers each
   part and what it actually *measures*, then answer: (a) where does
   the halfway rest stop go? (b) how long is the trail?
6. Show that the triangle with vertices $A(-2, 1)$, $B(4, 1)$, and
   $C(1, 5)$ is isosceles.
7. **Challenge.** Find the point on the $y$-axis that is the same
   distance from $(2, 1)$ as from $(6, 3)$. Verify your answer.
8. **Medians and right bisectors.** For $\triangle ABC$ with vertices
   $A(-2, 0)$, $B(4, 0)$, and $C(2, 6)$: (a) find the equation of the
   median from $C$ to side $AB$; (b) determine the equation of the
   perpendicular bisector of $AB$ in standard form $Ax + By + C = 0$.

## Answers

> [!success]- Answer 1
> Average each coordinate: $\left(\frac{2+8}{2}, \frac{6+10}{2}\right) = (5, 8)$. It
> should land between $A$ and $B$ — it does.

> [!success]- Answer 2
> Run $8$, rise $6$: $\sqrt{8^2 + 6^2} = 10$ — a 6–8–10 triangle on the grid.

> [!success]- Answer 3
> Work the averages backwards: $\frac{-4+x}{2} = 1$ gives $x = 6$ and
> $\frac{7+y}{2} = 2$ gives $y = -3$. Verify: the midpoint of
> $(-4, 7)$ and $(6, -3)$ is indeed $(1, 2)$. ✓

> [!success]- Answer 4
> Midpoints: $(2, 3)$ and $(6, 3)$ — a horizontal segment of length
> $4$: exactly half of $AB = 8$, and parallel to it. No coincidence,
> as [[The Quadrilateral Case File]] will demand you prove.

> [!success]- Answer 5
> (a) Midpoint — it averages coordinates to locate a *position*:
> $(5, 6)$. (b) Length — Pythagoras on rise and run measures a
> *distance*: $\sqrt{8^2 + 6^2} = 10$ km. A point, then a number.

> [!success]- Answer 6
> $AC = \sqrt{3^2 + 4^2} = 5$ and $BC = \sqrt{3^2 + 4^2} = 5$, while
> $AB = 6$. Two equal sides — isosceles. ✓

> [!success]- Answer 7
> On the $y$-axis, $x = 0$; setting squared distances equal gives
> $4 + (y-1)^2 = 36 + (y-3)^2$, so $4y = 40$ and the point is
> $(0, 10)$. Verify: both distances are $\sqrt{85}$. ✓

> [!success]- Answer 8
> (a) The midpoint of $AB$ is
> $M = \left(\frac{-2+4}{2}, \frac{0+0}{2}\right) = (1, 0)$.
> The median joins $C(2, 6)$ to $M(1, 0)$, with slope
> $m = \frac{6-0}{2-1} = 6$. Equation through $(1, 0)$:
> $y = 6(x - 1) = 6x - 6$.
> (b) $AB$ lies on the $x$-axis (horizontal, slope $0$), so its
> perpendicular bisector is the vertical line through $M(1, 0)$:
> $x = 1$, or in standard form $x - 1 = 0$.

%%curriculum-start%%
## Curriculum connection

![[B1.4]]

![[B1.5]]

![[B2.1]]

![[B2.2]]

![[B2.5]]

![[B3.1]]

![[B3.2]]
%%curriculum-end%%
