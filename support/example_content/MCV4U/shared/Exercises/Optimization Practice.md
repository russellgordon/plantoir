---
title: Optimization Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Optimization]] — warm-ups first, then the
boxes, then models drawn from the world. For every question: name
the variable, build the function, state the domain the story allows,
and *audit* your candidate before you crown it.

## Warming up

1. Two numbers have a sum of 30. Using calculus, determine the pair
   with the greatest product.
2. A farmer has 1200 m of fencing for a rectangular field along a
   straight river — no fence needed on the river side. What
   dimensions give the largest area?

> [!success]- Answer 1
> Let one number be $x$; the other is $30 - x$. Maximise
> $P(x) = x(30 - x) = 30x - x^2$. Then $P'(x) = 30 - 2x$, zero at
> $x = 15$; $P'$ is positive before and negative after, so this is
> a maximum. The pair is 15 and 15, with product 225. The estimate
> you made before differentiating — "probably the middle" — just
> got certified.

> [!success]- Answer 2
> Let $x$ be each side perpendicular to the river; the parallel
> side uses what remains, $1200 - 2x$. Area
> $A(x) = x(1200 - 2x) = 1200x - 2x^2$ on $0 < x < 600$.
> $A'(x) = 1200 - 4x$, zero at $x = 300$, with $A'$ changing $+$ to
> $-$: a maximum. Dimensions $300$ m by $600$ m, area
> $180\,000$ m². Not a square — the river is doing the work of one
> fence, and the optimum leans into the free side.

## Boxes and packages

3. An open-top box is made from a 24 cm by 24 cm sheet by cutting
   equal squares of side $x$ from the corners and folding up the
   sides. Determine the value of $x$ that maximises the volume, and
   the maximum volume.
4. An open-top box with a square base must hold 4000 cm³. What
   dimensions minimise the material used?

> [!success]- Answer 3
> $V(x) = x(24 - 2x)^2$ on $0 < x < 12$. Product and chain rules:
> $$\begin{aligned} V'(x) &= (24 - 2x)^2 + x \cdot 2(24 - 2x)(-2) \\ &= (24 - 2x)(24 - 6x) \end{aligned}$$
> Zero at $x = 12$ (the domain's edge — a flattened box of volume
> zero) and $x = 4$. Sign of $V'$ around 4: positive then negative
> — a maximum. $V(4) = 4(16)^2 = 1024$ cm³. This is
> [[The Box Problem]] settled in general: every group's fold was a
> point on this curve, and $x = 4$ is its summit.

> [!success]- Answer 4
> Base side $x$, height $h$, with $x^2h = 4000$, so
> $h = \frac{4000}{x^2}$. Material (base plus four sides):
> $$S(x) = x^2 + 4xh = x^2 + \frac{16000}{x}, \quad x > 0$$
> $S'(x) = 2x - \frac{16000}{x^2}$, zero when $x^3 = 8000$, so
> $x = 20$. Audit: $S''(x) = 2 + \frac{32000}{x^3} > 0$ — concave
> up, a genuine minimum. Dimensions: base 20 cm by 20 cm, height
> $h = \frac{4000}{400} = 10$ cm, using $S(20) = 400 + 800 = 1200$
> cm². The height is half the base side — a shape worth remembering
> for [[The Packaging Brief]].

## Models from the world

5. The number of daily bus riders is modelled by
   $1200(1.15)^{-x}$, where $x$ is the fare in dollars. What fare
   maximises the total revenue?
6. A foraging bird gains $E = \dfrac{3000t}{t + 4}$ joules of food
   energy by spending $t$ minutes in a berry patch, and takes 2
   minutes to fly to each new patch. How long should it stay in a
   patch to maximise its average rate of energy gain?

> [!success]- Answer 5
> Revenue is fare times riders:
> $R(x) = 1200x(1.15)^{-x}$. Product rule, with
> $\frac{d}{dx}(1.15)^{-x} = -(1.15)^{-x}\ln 1.15$:
> $$R'(x) = 1200(1.15)^{-x}\left(1 - x\ln 1.15\right)$$
> The exponential factor is never zero, so $R'(x) = 0$ exactly when
> $x = \frac{1}{\ln 1.15} \approx 7.16$. $R'$ is positive before
> and negative after: a maximum. A fare of about \$7.16 — call it
> \$7.15 at the fare box — yields revenue near
> $R(7.16) \approx \textdollar 3159$ per day. Cheaper fares carry more riders
> for too little each; dearer fares charge fewer riders too much.

> [!success]- Answer 6
> Average rate of gain = energy divided by *total* time, foraging
> plus travel:
> $$R(t) = \frac{3000t}{(t + 4)(t + 2)} = \frac{3000t}{t^2 + 6t + 8}$$
> Writing this as $3000t\,(t^2 + 6t + 8)^{-1}$ and differentiating:
> $$\begin{aligned} R'(t) &= \frac{3000(t^2 + 6t + 8) - 3000t(2t + 6)}{(t^2 + 6t + 8)^2} \\ &= \frac{3000(8 - t^2)}{(t^2 + 6t + 8)^2} \end{aligned}$$
> Zero at $t = \sqrt{8} = 2\sqrt{2} \approx 2.8$ minutes, with $R'$
> positive before and negative after: a maximum. The bird should
> stay about 2.8 minutes — leave while berries remain, because the
> hidden ones cost more time than a fresh patch does. Compare
> strategies, as [[B2.5|the curriculum asks]]: a table of $R(t)$
> and a graph both point to the same summit the algebra found.

%%curriculum-start%%
## Curriculum connection

![[B2.1]]

![[B2.2]]

![[B2.3]]

![[B2.4]]

![[B2.5]]
%%curriculum-end%%
