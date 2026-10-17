---
title: Check Your Curve Sketching
publishForSection1: true
tags:
  - exercises
---
Three quick questions on [[Curve Sketching]]. Answer each one, press
**Check**, and read why. Your score is at the bottom of the page.

> [!quiz] The graph shows $f(x) = x^3 - 3x + 1$. Estimate the root between 0 and 1 from the graph: $x \approx$ `____`
> ```functionplot
> ---
> bounds: [-1.5, 1.5, -1.5, 3.5]
> alt: The cubic y = x^3 - 3x + 1, falling from a local maximum at (-1, 3) through a root between 0 and 1 to a local minimum at (1, -1)
> ---
> y = x^3 - 3x + 1
> ```
> > [!answer]-
> > 0.35 ± 0.06
>
> > [!explain]- Why
> > The curve crosses the axis between the grid lines at 0.2 and 0.4, a
> > little past halfway, so any estimate from 0.3 to 0.4 is right. Checking
> > signs pins it down: $f(0.34) \approx 0.019 > 0$ and
> > $f(0.35) \approx -0.007 < 0$, so the root is $x \approx 0.347$.

> [!quiz|shuffle] Which graph is $f'(x)$ for $f(x) = x^3 - 3x + 1$?
> - [x] Graph A
>   ```functionplot
>   ---
>   bounds: [-2.5, 2.5, -4, 6]
>   alt: An upward parabola crossing the x-axis at -1 and 1, with y-intercept -3
>   ---
>   y = 3x^2 - 3
>   ```
> - [ ] Graph B
>   ```functionplot
>   ---
>   bounds: [-2.5, 2.5, -4, 6]
>   alt: An upward parabola with its vertex at the origin
>   ---
>   y = 3x^2
>   ```
> - [ ] Graph C
>   ```functionplot
>   ---
>   bounds: [-2.5, 2.5, -4, 6]
>   alt: A downward parabola crossing the x-axis at -1 and 1, with y-intercept 3
>   ---
>   y = 3 - 3x^2
>   ```
>
> > [!explain]- Why
> > The derivative of a cubic is a parabola. $f'(x) = 3x^2 - 3$ is zero at
> > $x = \pm 1$, where $f$ has its local maximum and minimum, and negative
> > between them, where $f$ falls.

> [!quiz] What is the slope of the tangent to $f(x) = x^3 - 3x + 1$ at $x = 2$?
> > [!answer]-
> > 9
>
> > [!explain]- Why
> > $f'(x) = 3x^2 - 3$, so $f'(2) = 12 - 3 = 9$.
