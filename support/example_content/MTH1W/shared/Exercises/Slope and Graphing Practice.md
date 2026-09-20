---
title: Slope and Graphing Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Slope and Rate of Change]] — the "how much
more per one more" instinct was built in class during [[Bungee Drop]].
Sketch by hand first; [[Using Desmos]] is for checking, not guessing.

## Questions

1. Find the slope of the line through $(1, 2)$ and $(4, 11)$.
2. A table of values: $(0, 8)$, $(1, 11)$, $(2, 14)$, $(3, 17)$.
   Find the rate of change and initial value; write $y = mx + b$.
3. Graph $y = 3$ and $x = -2$ on the same axes. State the slope of
   each — and explain why one of them has no slope at all.
4. Graph $x + y = 10$. Find both intercepts and the slope.
5. **Find the error.** For $(2, 3)$ and $(5, 9)$, Nadia computes
   slope $= \frac{5 - 2}{9 - 3} = \frac{3}{6} = \frac{1}{2}$.
   What went wrong, and what is the correct slope?
6. A repair shop's data: a 2-hour job costs \$130; a 5-hour job
   costs \$250. Find the hourly rate and the flat call-out fee.
7. **Challenge.** Find the equation of the line through $(2, 5)$
   that is parallel to $x + y = 7$.
8. Two gyms: Iron Works charges \$30 a month plus \$4 a visit; Rec
   Centre charges \$10 a month plus \$8 a visit. Write both as
   $y = ax + b$, graph them on the same axes, and find where they
   cross. Say in a sentence what that point means to somebody
   choosing between the two, and which gym is cheaper on either side
   of it.
9. Solve $2x + 3 = -x + 9$ two ways — algebraically, and by graphing
   $y = 2x + 3$ and $y = -x + 9$ and reading the intersection. Say
   what the two methods have in common, and one thing each shows that
   the other does not.
10. Two lines cross at $(4, 7)$. One has slope $2$. Give a possible
    equation for each line, then say how many *different* pairs of
    lines could have produced that same crossing point.
11. Start with $y = 2x$. Sketch it, then sketch each of these on the
    same axes and give the equation of the result: (a) translated
    $3$ units up; (b) reflected in the $x$-axis; (c) rotated $90°$
    about the origin. For each, say what changed in the equation and
    what stayed the same.
12. **Find the error.** Sam says "reflecting $y = 2x$ in the $x$-axis
    and rotating it $90°$ about the origin give the same line, because
    both of them tip it the other way." Test the claim by taking the
    point $(1, 2)$ through each transformation, and say what is
    actually true about the two results.

## Answers

> [!success]- Answer 1
> $m = \frac{11 - 2}{4 - 1} = \frac{9}{3} = 3$. Three up for every
> one across.

> [!success]- Answer 2
> Each step right adds 3, so $m = 3$; the value at zero is 8, so
> $b = 8$: $y = 3x + 8$. Rate of change and initial value are the
> table's two secrets, and the equation wears both openly.

> [!success]- Answer 3
> $y = 3$ is horizontal: every height is 3, slope 0 — no change.
> $x = -2$ is vertical: the run between any two of its points is 0,
> and dividing by 0 is meaningless — *undefined* slope, not zero.

> [!success]- Answer 4
> Intercepts where the other variable is 0: $(10, 0)$ and $(0, 10)$.
> Slope $-1$: every extra unit of $x$ costs one unit of $y$, because
> the two must always total 10.

> [!success]- Answer 5
> Nadia put the $x$-changes on top. Slope is rise over run:
> $\frac{9 - 3}{5 - 2} = 2$. Her $\frac{1}{2}$ is the reciprocal — a
> quick sketch shows a line steeper than 1, catching the slip.

> [!success]- Answer 6
> Rate $= \frac{250 - 130}{5 - 2} = \textdollar 40$/hour. Work backwards from
> the 2-hour job: $130 - 2(40) = \textdollar 50$ call-out fee. Check with the
> other point: $50 + 5(40) = 250$. ✓

> [!success]- Answer 7
> $x + y = 7$ is $y = -x + 7$: slope $-1$. Try $y = -x + b$ through
> $(2, 5)$: $b = 7$ — the *same* line. Since $2 + 5 = 7$, the point
> already sat on the line; the only parallel line through it is itself.

> [!success]- Answer 8
> **Iron Works:** $y = 4x + 30$. **Rec Centre:** $y = 8x + 10$.
>
> Setting them equal: $4x + 30 = 8x + 10 \Rightarrow 20 = 4x \Rightarrow x = 5$, and $y = 4(5) + 30 = 50$. They cross at $(5, 50)$.
>
> **What the point means:** at exactly five visits a month, both gyms cost \$50 — the choice is a coin toss. It is the *break-even* point, and it is the only place the two plans agree.
>
> **Either side of it:** below five visits the Rec Centre is cheaper (its per-visit charge is higher, but you pay it less often, and its monthly fee is \$20 lower). Above five visits Iron Works is cheaper, and the gap grows by \$4 for every extra visit. So the honest advice is not "which gym is cheaper" — it is "how often do you actually go?", which is a question about the person, not about the graph. Both slopes and both intercepts matter, and neither one alone decides it.

> [!success]- Answer 9
> **Algebraically:** $2x + 3 = -x + 9 \Rightarrow 3x = 6 \Rightarrow x = 2$, and substituting back, $y = 2(2) + 3 = 7$.
>
> **Graphically:** the lines cross at $(2, 7)$ — the same answer, read off rather than computed.
>
> **In common:** both are answering the identical question, *for what $x$ do these two expressions produce the same value?* Solving an equation and finding an intersection are the same act in two costumes.
>
> **What each shows that the other does not.** The algebra gives an exact answer, and would still work if the crossing were at $x = \frac{7}{13}$, where a graph would only let you say "about a half". The graph shows the whole story either side of the crossing: which line is above before it, which after, and whether they cross at all — two parallel lines produce an equation with no solution, and the graph makes that *obvious* where the algebra makes it merely true.

> [!success]- Answer 10
> One line has slope $2$ through $(4, 7)$: $y = 2x - 1$. The other can be almost anything through the same point — $y = -x + 11$, or $y = 7$, or $y = \frac{1}{2}x + 5$.
>
> **How many pairs?** Infinitely many. Every line through $(4, 7)$ except one with slope $2$ will do, and there are infinitely many of those. This is the point of the question: the intersection tells you where two relations agree and *nothing whatever* about what they are. A break-even point of five visits is consistent with a great many pairs of gym plans, so quoting the crossing point alone — without both equations — is not enough information for anybody to act on.

> [!success]- Answer 11
> **(a) Translated 3 up:** $y = 2x + 3$. The slope is unchanged, so the new line is parallel to the original — translating a line never changes how steep it is. What changed is $b$, from $0$ to $3$; the line no longer passes through the origin.
>
> **(b) Reflected in the $x$-axis:** $y = -2x$. Every point $(x, y)$ becomes $(x, -y)$, so a line that rose $2$ for every $1$ across now falls $2$. The sign of $a$ flips; its size does not. Still through the origin.
>
> **(c) Rotated $90°$ about the origin:** $y = -\frac{1}{2}x$. The point $(1, 2)$ goes to $(-2, 1)$, so the new slope is $\frac{1}{-2} = -\frac{1}{2}$. Still through the origin, because the origin is the centre of the rotation and does not move.
>
> **The pattern worth keeping:** translation moves $b$ and leaves $a$ alone; reflection in an axis flips the sign of $a$; rotation about the origin turns $a$ into $-\frac{1}{a}$. And any line $y = ax$ passes through the origin, so any transformation *centred* there leaves it there — which is why only the translation moved it.

> [!success]- Answer 12
> The claim is false, and one point settles it.
>
> Take $(1, 2)$, which is on $y = 2x$.
>
> **Reflected in the $x$-axis:** $(1, -2)$, which lies on $y = -2x$.
>
> **Rotated $90°$ about the origin:** $(-2, 1)$, which lies on $y = -\frac{1}{2}x$.
>
> Different points, different lines. Both results do "tip it the other way" in the loose sense that both slopes are now negative — which is why the claim sounds reasonable — but $-2$ and $-\frac{1}{2}$ are not the same steepness, and the two lines are not the same line.
>
> **What *is* true:** the rotated line is perpendicular to the original, because rotating by $90°$ is exactly what perpendicular means. The reflected line is not. "Both go downhill" is a description of the sign only, and the sign is one of the two things a slope carries.

%%curriculum-start%%
## Curriculum connection

![[C3.3]]

![[C4.3]]

![[C4.4]]

![[C4.2]]
%%curriculum-end%%
