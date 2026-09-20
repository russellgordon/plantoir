---
title: Where a Line Meets a Parabola
publish: true
created: __CREATED__
tags:
  - concepts
---
Two graphs on the same axes, and the question is where they cross. It
comes up whenever two situations are being compared — a cost that grows
steadily against one that accelerates, a projectile against a slope, a
revenue line against a cost curve.

The crossing points are the values of $x$ where the two functions agree,
so setting them equal is not a trick. It is the definition.

$$\text{Solve } f(x) = g(x) \quad\text{where}\quad f(x) = x^2 - 2x - 3, \; g(x) = x + 1$$

Bring everything to one side, and a familiar object appears:

$$x^2 - 2x - 3 = x + 1 \;\Longrightarrow\; x^2 - 3x - 4 = 0 \;\Longrightarrow\; (x-4)(x+1) = 0$$

So $x = 4$ or $x = -1$. Substitute back into the *simpler* function —
the line, always — to get the points: $(4, 5)$ and $(-1, 0)$.

## The three cases, and what they mean

| Discriminant of the combined equation | Graph | The situation |
| --- | --- | --- |
| $b^2 - 4ac > 0$ | Two intersection points | The line cuts the parabola |
| $b^2 - 4ac = 0$ | One point | The line is tangent — it touches and leaves |
| $b^2 - 4ac < 0$ | No points | They never meet; no real solution |

This is the same discriminant from [[Quadratic Functions Revisited]],
doing a new job. When a question asks for the value of $k$ that makes a
line tangent to a curve, it is asking you to set the discriminant to
zero and solve — a question that looks impossible until you notice that.

## Graphically, and why you should do both

Plot both in [[Using Desmos]] before solving. The graph tells you how
many solutions to expect and roughly where, which catches the two most
common errors instantly: a sign slip that produces two answers where the
picture shows none, and an arithmetic slip that puts a crossing point in
the wrong quadrant.

The graph is not the answer, though. Reading "about 3.9" off a screen is
not solving; the algebra gives $x = 4$ exactly, and exact is what a
later calculation needs.

> [!tip] Substitute into the easier one
> Once you have the $x$ values, put them into whichever function is
> simpler — usually the line. Students routinely substitute into the
> quadratic, do more arithmetic than necessary, and make a mistake in
> it. Both functions must give the same $y$; that is what "intersection"
> means, and checking one against the other is a free verification.

%%curriculum-start%%
## Curriculum connection

![[A2.1]]

![[A2.2]]

![[A2.4]]

![[A2.5]]
%%curriculum-end%%
