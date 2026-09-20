---
title: Lines and Planes Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Equations of Lines]],
[[Equations of Planes]], and [[Intersections of Lines and Planes]] —
building the equations, converting between forms, and settling where
things meet. Audit every equation you build by substituting a point
you know is on it.

## Lines

1. Determine vector and parametric equations of the line through
   $(3, 2, -1)$ and $(0, 2, 1)$, and represent the same line as the
   intersection of two planes.
2. Consider the system $2x + y = 5$ and $4x + 2y = 7$ in two-space.
   How many solution points are there, and what does the answer
   look like geometrically?
3. Show that the lines $\vec{r} = (1, 2, 0) + t(1, 1, 1)$ and
   $\vec{r} = (2, 4, 6) + s(1, -1, 2)$ are skew.

> [!success]- Answer 1
> Direction: $(0, 2, 1) - (3, 2, -1) = (-3, 0, 2)$. Vector
> equation: $\vec{r} = (3, 2, -1) + t(-3, 0, 2)$. Parametric:
> $x = 3 - 3t$, $y = 2$, $z = -1 + 2t$. For the two planes: $y = 2$
> is one of them already ($y$ never moves). Eliminate $t$ between
> $x$ and $z$: $t = \frac{3 - x}{3} = \frac{z + 1}{2}$, so
> $2(3 - x) = 3(z + 1)$, which tidies to $2x + 3z - 3 = 0$. The
> line is the crease where $y - 2 = 0$ meets $2x + 3z - 3 = 0$.
> Audit with $(3, 2, -1)$: $6 - 3 - 3 = 0$. ✓

> [!success]- Answer 2
> Doubling the first equation gives $4x + 2y = 10$, but the second
> insists $4x + 2y = 7$. No pair $(x, y)$ can satisfy both — no
> solutions. Geometrically: two parallel, distinct lines (same
> slope, different intercepts) that never meet. A system's algebra
> and its picture always tell the same story.

> [!success]- Answer 3
> The directions $(1, 1, 1)$ and $(1, -1, 2)$ are not scalar
> multiples — not parallel. Do they intersect? Match components:
> $x$: $1 + t = 2 + s$ and $y$: $2 + t = 4 - s$. Adding the two
> conditions ($t - s = 1$ and $t + s = 2$) gives $t = \frac{3}{2}$,
> $s = \frac{1}{2}$. Now the $z$ test: $t = \frac{3}{2}$ versus
> $6 + 2s = 7$. Since $\frac{3}{2} \neq 7$, no common point exists.
> Not parallel and not intersecting: skew — the highways at
> different heights.

## Planes

4. Determine the scalar equation of the plane through $(3, 2, 5)$,
   $(0, -2, 2)$, and $(1, 3, 1)$.
5. Represent the plane
   $\vec{r} = (2, 1, 0) + s(1, -1, 3) + t(2, 0, -5)$ with a scalar
   equation.

> [!success]- Answer 4
> Two vectors in the plane, first point to the others:
> $\vec{u} = (-3, -4, -3)$ and $\vec{v} = (-2, 1, -4)$. Normal:
> $$\vec{n} = \vec{u} \times \vec{v} = ((-4)(-4) - (-3)(1),\; (-3)(-2) - (-3)(-4),\; (-3)(1) - (-4)(-2)) = (19, -6, -11)$$
> Using $(3, 2, 5)$: $19(3) - 6(2) - 11(5) = 57 - 12 - 55 = -10$,
> so the plane is $19x - 6y - 11z + 10 = 0$. Audit with the other
> two points: $0 + 12 - 22 + 10 = 0$ ✓ and $19 - 18 - 11 + 10 = 0$
> ✓. Three points, one plane, fully checked.

> [!success]- Answer 5
> The normal is the cross product of the two direction vectors:
> $$(1, -1, 3) \times (2, 0, -5) = ((-1)(-5) - 3(0),\; 3(2) - 1(-5),\; 1(0) - (-1)(2)) = (5, 11, 2)$$
> Through $(2, 1, 0)$: $5(2) + 11(1) + 2(0) = 21$, so
> $5x + 11y + 2z - 21 = 0$. Audit: the normal dotted with each
> direction vector gives $5 - 11 + 6 = 0$ and $10 + 0 - 10 = 0$ —
> perpendicular to both, as a normal must be.

## Where they meet

6. Determine the point where the line
   $\vec{r} = (1, 0, 2) + t(2, 1, -1)$ meets the plane
   $x - y + 2z = 9$.
7. Determine the intersection of the planes $x + y + z = 6$,
   $x - y + z = 2$, and $2x + y - z = 1$, and describe the
   configuration.
8. Determine the distance from the point $(3, 1, 2)$ to the plane
   $2x - y + 2z - 5 = 0$.

> [!success]- Answer 6
> Substitute the parametric coordinates $x = 1 + 2t$, $y = t$,
> $z = 2 - t$ into the plane:
> $$(1 + 2t) - t + 2(2 - t) = 5 - t = 9 \quad\Rightarrow\quad t = -4$$
> The point: $(1 - 8, -4, 2 + 4) = (-7, -4, 6)$. Audit in the
> plane: $-7 + 4 + 12 = 9$. ✓ One value of $t$, one crossing — the
> line pierces the plane.

> [!success]- Answer 7
> Subtract the second equation from the first: $2y = 4$, so
> $y = 2$. Then $x + z = 4$ (first equation) and, from the third,
> $2x - z = -1$. Adding: $3x = 3$, so $x = 1$ and $z = 3$. Unique
> solution $(1, 2, 3)$ — audit in all three: $1 + 2 + 3 = 6$ ✓,
> $1 - 2 + 3 = 2$ ✓, $2 + 2 - 3 = 1$ ✓. Three planes meeting in a
> single point, like the corner of a room.

> [!success]- Answer 8
> The distance is measured along the normal:
> $$\begin{aligned} d &= \frac{|2(3) - 1(1) + 2(2) - 5|}{\sqrt{2^2 + (-1)^2 + 2^2}} \\ &= \frac{|6 - 1 + 4 - 5|}{3} = \frac{4}{3} \end{aligned}$$
> The numerator is the plane's equation *evaluated at the point* —
> zero would mean the point lies on the plane, and the farther from
> zero, the farther from the plane. Dividing by $|\vec{n}| = 3$
> converts that raw imbalance into metres of perpendicular
> clearance: the certification step of [[The Flight Path]].

%%curriculum-start%%
## Curriculum connection

![[C3.1]]

![[C3.2]]

![[C3.3]]

![[C4.1]]

![[C4.2]]

![[C4.3]]

![[C4.4]]

![[C4.5]]

![[C4.6]]
%%curriculum-end%%
