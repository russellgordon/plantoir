---
title: Trig Ratios and Laws Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Special Angles]], [[The Sine Law]], and
[[The Cosine Law]]. The first group is calculator-free; after that,
half the skill is choosing the tool before touching a button. Round
to one decimal place where rounding is needed.

## Exact values and the full circle

1. State exact values: $\sin 60°$, $\tan 45°$, $\cos 30°$.
2. Evaluate exactly: $\sin^2 45° + \cos^2 45°$.
3. Find both angles between $0°$ and $360°$ with
   $\sin\theta = \frac{1}{2}$.
4. Find both angles between $0°$ and $360°$ with $\tan\theta = 1$.

> [!success]- Answer 1
> From the two rebuildable triangles: $\sin 60° = \frac{\sqrt{3}}{2}$,
> $\tan 45° = 1$, $\cos 30° = \frac{\sqrt{3}}{2}$. If you drew the
> triangles rather than recalling digits, the answers came with
> receipts.

> [!success]- Answer 2
> $\left(\frac{\sqrt{2}}{2}\right)^2 + \left(\frac{\sqrt{2}}{2}\right)^2
> = \frac{1}{2} + \frac{1}{2} = 1$. Not a coincidence: on the unit
> circle, $\sin\theta$ and $\cos\theta$ are the legs of a right
> triangle whose hypotenuse is 1, so this sum is 1 at *every* angle.

> [!success]- Answer 3
> $\theta = 30°$ or $\theta = 150°$. The rotating arm reaches height
> $\frac{1}{2}$ once rising, once returning — the second angle is
> $180° - 30°$.

> [!success]- Answer 4
> $\theta = 45°$ or $\theta = 225°$. Tangent is positive where sine
> and cosine share a sign — first and *third* quadrants — so the
> partner angle is $180° + 45°$, not $180° - 45°$.

## Sine law — including the trap

5. In $\triangle ABC$, $\angle A = 44°$, $\angle B = 71°$, and
   $a = 12$ cm. Find $b$.
6. In $\triangle ABC$, $\angle A = 30°$, $a = 6$ cm, and $b = 10$ cm.
   Find *all* possible measures of $\angle B$.

> [!success]- Answer 5
> A known side faces a known angle, so the sine law applies:
> $b = \dfrac{12 \sin 71°}{\sin 44°} \approx 16.3$ cm. Check before
> believing: $71° > 44°$, so $b$ had to exceed 12 cm. ✓

> [!success]- Answer 6
> $\sin B = \dfrac{10 \sin 30°}{6} = \dfrac{5}{6}$, so
> $B \approx 56.4°$ — *or* its supplement, $B \approx 123.6°$. Test
> both against the angle budget: $30° + 56.4° < 180°$ and
> $30° + 123.6° < 180°$, so both triangles exist and both answers
> stand. Reporting only the acute one is the classic miss; the
> question's word "all" was the warning.

## Cosine law and mixed

7. In $\triangle ABC$, $b = 8$ cm, $c = 11$ cm, and the contained
   angle $\angle A = 52°$. Find $a$.
8. A triangle has sides 6 m, 7 m, and 10 m. Find its largest angle.
9. **Challenge.** From point $P$, the angle of elevation to the top
   of a tower is $28°$. From point $Q$, which is 50 m closer along
   flat ground, it is $40°$. Find the height of the tower.

> [!success]- Answer 7
> No known side faces a known angle — cosine law:
> $a^2 = 8^2 + 11^2 - 2(8)(11)\cos 52° \approx 76.6$, so
> $a \approx 8.8$ cm.

> [!success]- Answer 8
> The largest angle faces the 10 m side:
> $\cos\theta = \dfrac{6^2 + 7^2 - 10^2}{2(6)(7)} = -\dfrac{15}{84}$,
> so $\theta \approx 100.3°$. The negative cosine announced an obtuse
> angle before the calculator finished — that is the check.

> [!success]- Answer 9
> In $\triangle PQT$ ($T$ the tower top): the angle at $Q$ is
> $180° - 40° = 140°$, leaving $12°$ at $T$. Sine law gives the slant
> side $QT = \dfrac{50 \sin 28°}{\sin 12°} \approx 112.9$ m. Then the
> right triangle under $T$ gives height
> $h = QT \sin 40° \approx 72.6$ m. Two triangles sharing an edge —
> solve one, carry the edge to the other.

%%curriculum-start%%
## Curriculum connection

![[D1.1]]

![[D1.2]]

![[D1.3]]

![[D1.4]]

![[D1.5]]

![[D1.6]]

![[D1.7]]
%%curriculum-end%%
