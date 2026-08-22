---
title: Identities and Equations Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Compound Angles]] and
[[Trigonometric Identities]]. Half the skill is knowing which job
each question is: an exact value, a proof, or an equation with a
finite list of answers. All domains are $0 \le x \le 2\pi$.

## Compound angles and exact values

1. Determine the exact value of $\sin\dfrac{\pi}{12}$.
2. Determine the exact value of $\cos\dfrac{7\pi}{12}$.
3. Use a compound angle formula to show that
   $\cos\!\left(x + \dfrac{\pi}{2}\right) = -\sin x$.

> [!success]- Answer 1
> $\frac{\pi}{12} = \frac{\pi}{4} - \frac{\pi}{6}$, so
> $$\sin\frac{\pi}{12} = \sin\frac{\pi}{4}\cos\frac{\pi}{6} - \cos\frac{\pi}{4}\sin\frac{\pi}{6} = \frac{\sqrt{2}}{2}\cdot\frac{\sqrt{3}}{2} - \frac{\sqrt{2}}{2}\cdot\frac{1}{2} = \frac{\sqrt{6}-\sqrt{2}}{4}$$
> Sanity check: that is about $0.259$, small and positive, as the
> sine of a small angle should be. ✓

> [!success]- Answer 2
> $\frac{7\pi}{12} = \frac{\pi}{3} + \frac{\pi}{4}$, so
> $$\cos\frac{7\pi}{12} = \cos\frac{\pi}{3}\cos\frac{\pi}{4} - \sin\frac{\pi}{3}\sin\frac{\pi}{4} = \frac{1}{2}\cdot\frac{\sqrt{2}}{2} - \frac{\sqrt{3}}{2}\cdot\frac{\sqrt{2}}{2} = \frac{\sqrt{2}-\sqrt{6}}{4}$$
> Negative, about $-0.259$ — correct for a second-quadrant angle.

> [!success]- Answer 3
> Expand:
> $\cos x \cos\frac{\pi}{2} - \sin x \sin\frac{\pi}{2} =
> \cos x \cdot 0 - \sin x \cdot 1 = -\sin x$. The formula turned a
> transformation fact (shift cosine left by $\frac{\pi}{2}$, get an
> upside-down sine) into two lines of algebra.

## Proving identities

4. Prove that $\dfrac{\sin^2 x}{1 - \cos x} = 1 + \cos x$, and state
   any values of $x$ where the identity says nothing.
5. Derive the double angle formula $\sin 2x = 2\sin x \cos x$ from a
   compound angle formula.
6. Is $\sin(x + y) = \sin x + \sin y$ an identity? Settle it.

> [!success]- Answer 4
> Work the left side only. Pythagorean identity up top:
> $$\begin{aligned} \frac{\sin^2 x}{1 - \cos x} &= \frac{1 - \cos^2 x}{1 - \cos x} \\ &= \frac{(1 - \cos x)(1 + \cos x)}{1 - \cos x} = 1 + \cos x \end{aligned}$$
> The cancellation requires $1 - \cos x \ne 0$, so the identity is
> silent where $\cos x = 1$ — at $x = 0$ and $x = 2\pi$ in this
> domain, the left side is undefined.

> [!success]- Answer 5
> Set both angles equal in $\sin(a + b)$:
> $\sin(x + x) = \sin x \cos x + \cos x \sin x = 2\sin x \cos x$.
> One substitution, one collect — which is why the double angle
> formulas are not worth memorising separately from their parent.

> [!success]- Answer 6
> No. One counter-example suffices: $x = y = \frac{\pi}{2}$ gives
> $\sin \pi = 0$ on the left and $1 + 1 = 2$ on the right. An
> identity must hold for *every* input, so a single failure is a
> complete disproof — the cheapest kind of certainty in mathematics.

## Solving equations

7. Solve $2\sin x + 1 = 0$.
8. Solve $2\sin^2 x + \sin x - 1 = 0$.
9. Solve $\cos 2x = \dfrac{1}{2}$.

> [!success]- Answer 7
> $\sin x = -\frac{1}{2}$: reference angle $\frac{\pi}{6}$, sine
> negative in the third and fourth quadrants, so
> $x = \frac{7\pi}{6}$ or $\frac{11\pi}{6}$.

> [!success]- Answer 8
> Factor as a quadratic in $\sin x$:
> $(2\sin x - 1)(\sin x + 1) = 0$. Either $\sin x = \frac{1}{2}$,
> giving $x = \frac{\pi}{6}$ or $\frac{5\pi}{6}$, or $\sin x = -1$,
> giving $x = \frac{3\pi}{2}$. Three solutions; a quick mental graph
> of the sine wave confirms the count.

> [!success]- Answer 9
> Let $u = 2x$. As $x$ runs over $[0, 2\pi]$, $u$ runs over
> $[0, 4\pi]$ — *two* laps of the circle, so expect double the
> answers. $\cos u = \frac{1}{2}$ at $u = \frac{\pi}{3},
> \frac{5\pi}{3}, \frac{7\pi}{3}, \frac{11\pi}{3}$. Halving:
> $x = \frac{\pi}{6}, \frac{5\pi}{6}, \frac{7\pi}{6},
> \frac{11\pi}{6}$. The classic error is solving only one lap and
> losing half the list.

%%curriculum-start%%
## Curriculum connection

![[B3.1]]

![[B3.2]]

![[B3.3]]

![[B3.4]]
%%curriculum-end%%
