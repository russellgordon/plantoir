---
title: Dot and Cross Product Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[What Vectors Are]],
[[Adding and Scaling Vectors]], [[The Dot Product]], and
[[The Cross Product]] — a warm-up on vectors themselves, then each
product in turn. Sketch first wherever a sketch is possible; the
picture audits the arithmetic.

## Vector warm-up

1. Determine the magnitude and direction of the vector $(8, 6)$.
2. Represent the vector with magnitude 8 and direction $30°$
   anticlockwise from the positive $x$-axis in Cartesian form.
3. A plane on a heading of N 27° E has an airspeed of 375 km/h. The
   wind is blowing from the south at 62 km/h. Determine the plane's
   actual direction of travel and its ground speed.

> [!success]- Answer 1
> Magnitude: $\sqrt{8^2 + 6^2} = \sqrt{100} = 10$. Direction:
> $\tan^{-1}\left(\frac{6}{8}\right) \approx 36.9°$ above the
> positive $x$-axis. A 3–4–5 triangle scaled by 2 — worth
> recognising on sight.

> [!success]- Answer 2
> $(8\cos 30°, 8\sin 30°) = (4\sqrt{3}, 4) \approx (6.93, 4)$.
> Audit: $\sqrt{48 + 16} = \sqrt{64} = 8$. ✓

> [!success]- Answer 3
> Components, taking east as $x$ and north as $y$. The heading
> N 27° E leans $27°$ east of north:
> $(375\sin 27°, 375\cos 27°) \approx (170.3, 334.1)$. Wind *from*
> the south blows *toward* the north: $(0, 62)$. Sum:
> $(170.3, 396.1)$. Ground speed:
> $\sqrt{170.3^2 + 396.1^2} \approx 431$ km/h. Direction:
> $\tan^{-1}\left(\frac{170.3}{396.1}\right) \approx 23.3°$ east of
> north — about N 23° E. The tailwind adds speed and swings the
> travel direction closer to north than the heading; both changes
> should feel right before the arithmetic confirms them.

## The dot product

4. For $\vec{a} = (3, -1, 2)$ and $\vec{b} = (1, 4, -2)$, compute
   $\vec{a} \cdot \vec{b}$ and determine the angle between the
   vectors.
5. Determine $k$ so that $(2, k, 1)$ and $(3, -2, 4)$ are
   orthogonal.
6. Determine the projection of $\vec{a} = (6, 2)$ onto
   $\vec{b} = (3, 4)$ — the scalar amount and the vector.

> [!success]- Answer 4
> Dot product: $3(1) + (-1)(4) + 2(-2) = 3 - 4 - 4 = -5$.
> Magnitudes: $|\vec{a}| = \sqrt{14}$, $|\vec{b}| = \sqrt{21}$. So
> $$\cos\theta = \frac{-5}{\sqrt{14}\sqrt{21}} = \frac{-5}{7\sqrt{6}} \approx -0.292, \qquad \theta \approx 107°$$
> The negative dot product promised an obtuse angle before the
> inverse cosine said which one.

> [!success]- Answer 5
> Orthogonal means dot product zero:
> $2(3) + k(-2) + 1(4) = 10 - 2k = 0$, so $k = 5$. Check:
> $(2, 5, 1) \cdot (3, -2, 4) = 6 - 10 + 4 = 0$. ✓

> [!success]- Answer 6
> $\vec{a} \cdot \vec{b} = 18 + 8 = 26$ and $|\vec{b}| = 5$. Scalar
> projection: $\frac{26}{5} = 5.2$ — how much of $\vec{a}$ points
> along $\vec{b}$. Vector projection: that amount in $\vec{b}$'s
> unit direction,
> $\frac{26}{25}(3, 4) = (3.12, 4.16)$. This is the wagon-handle
> computation: only the along-the-road part of the pull does work.

## The cross product

7. For $\vec{a} = (1, 0, 1)$ and $\vec{b} = (0, 1, -1)$, compute
   $\vec{a} \times \vec{b}$, and verify the result is orthogonal to
   both original vectors.
8. Determine the area of the parallelogram with sides
   $\vec{a} = (2, 1, 0)$ and $\vec{b} = (1, 3, 0)$.
9. You are loosening a stubborn bolt with a wrench. Using
   $|\vec{r} \times \vec{F}| = |\vec{r}||\vec{F}|\sin\theta$,
   explain how to maximise the torque — and why a longer handle
   helps as much as a stronger pull.

> [!success]- Answer 7
> $$\vec{a} \times \vec{b} = (0(-1) - 1(1),\; 1(0) - 1(-1),\; 1(1) - 0(0)) = (-1, 1, 1)$$
> Verification by dot product: $(1, 0, 1) \cdot (-1, 1, 1) =
> -1 + 0 + 1 = 0$ and $(0, 1, -1) \cdot (-1, 1, 1) = 0 + 1 - 1 =
> 0$. Both zero — the answer stands. Run this check every time; it
> is free.

> [!success]- Answer 8
> $$\vec{a} \times \vec{b} = (1(0) - 0(3),\; 0(1) - 2(0),\; 2(3) - 1(1)) = (0, 0, 5)$$
> Area $= |(0, 0, 5)| = 5$ square units. Both sides lie in the
> $xy$-plane, so the cross product points straight up the $z$-axis
> — perpendicular to the plane containing the parallelogram,
> exactly as it must.

> [!success]- Answer 9
> Torque is largest when every factor is as large as possible:
> maximise $|\vec{r}|$ by gripping at the end of the handle,
> maximise $|\vec{F}|$ by pulling hard, and maximise $\sin\theta$
> by pulling at $90°$ to the handle, where $\sin\theta = 1$. The
> three factors multiply, so doubling the handle length doubles the
> torque exactly as doubling the force does — which is why a length
> of pipe slipped over a wrench handle is the mechanic's cheat, and
> why pushing along the handle ($\theta = 0$) turns nothing at all.

%%curriculum-start%%
## Curriculum connection

![[C1.1]]

![[C1.2]]

![[C1.3]]

![[C1.4]]

![[C2.1]]

![[C2.2]]

![[C2.3]]

![[C2.4]]

![[C2.5]]

![[C2.6]]

![[C2.7]]
%%curriculum-end%%
