---
title: Parallel, Perpendicular, and the Bisector
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
Two lines on a grid have a relationship you can read off their slopes
alone, without drawing anything. That fact does more work in this course
than almost any other, because it turns geometry questions into
arithmetic.

## The two rules

**Parallel lines have equal slopes.** They rise at the same rate, so
they never meet.

$$m_1 = m_2$$

**Perpendicular lines have slopes that are negative reciprocals.**

$$m_1 \times m_2 = -1 \qquad\text{equivalently}\qquad m_2 = -\frac{1}{m_1}$$

So a line of slope $\tfrac{2}{3}$ is perpendicular to one of slope
$-\tfrac{3}{2}$: flip it over, change the sign. Both steps, every time —
flipping without the sign change is the error that survives longest,
because the answer still looks plausible.

| First slope | Parallel to it | Perpendicular to it |
| --- | --- | --- |
| $3$ | $3$ | $-\tfrac{1}{3}$ |
| $-\tfrac{2}{5}$ | $-\tfrac{2}{5}$ | $\tfrac{5}{2}$ |
| $1$ | $1$ | $-1$ |
| $0$ (horizontal) | $0$ | undefined (vertical) |

That last row is the case the rule cannot express: a horizontal line has
slope 0 and its perpendicular is vertical, whose slope is undefined
rather than $-\tfrac{1}{0}$. Say it in words instead, and the trap
disappears.

## Building the right bisector

The **right bisector** of a segment is the line that cuts it in half at
a right angle. It needs exactly two things, and you already have both
tools:

1. **The midpoint** of the segment — the point it must pass through.
2. **The negative reciprocal** of the segment's slope — the direction it
   must run.

For the segment from $A(1, 2)$ to $B(7, 6)$:

- Midpoint: $\left(\frac{1+7}{2}, \frac{2+6}{2}\right) = (4, 4)$
- Slope of $AB$: $m = \frac{y_2 - y_1}{x_2 - x_1} = \frac{6-2}{7-1} = \frac{4}{6} = \frac{2}{3}$
- Perpendicular slope: $-\frac{3}{2}$
- Equation in point-slope form through $(4,4)$: $y - 4 = -\frac{3}{2}(x - 4)$
- In slope-intercept form: $y = -\frac{3}{2}x + 10$
- In standard form: $3x + 2y - 20 = 0$

Every right-bisector question is those steps in that order. Translating
between forms — $y = mx + b$ for graphing, $Ax + By + C = 0$ for
general alignment — lets you match the form to the job.

## What the bisector is for

A point on the right bisector is **equidistant from both endpoints** —
that is what "half way, at right angles" means geometrically. So these
questions are really about fairness and distance:

- Where should a bus stop go so that two houses are equally far from it?
- Which points are closer to the school than to the arena?
- Where do two circles of the same radius meet?

## Proving things on the grid

Combined with length and midpoint, the two slope rules let you *prove*
claims rather than measure them:

- **A right angle**: show the two slopes multiply to $-1$.
- **A parallelogram**: show both pairs of opposite sides have equal
  slopes.
- **A rectangle**: a parallelogram with one right angle.
- **A rhombus**: a parallelogram with two adjacent sides of equal length,
  using the distance formula from [[Midpoint and Length]].
- **An isosceles triangle**: two sides of equal length.

A measured diagram is evidence; a slope calculation is a proof. That
distinction is what [[What Makes a Proof Convincing]] argues about, and
it is exactly what [[The Quadrilateral Case File]] asks you to produce.

%%curriculum-start%%
## Curriculum connection

![[B1.3]]

![[B1.4]]

![[B1.5]]

![[B2.5]]
%%curriculum-end%%
