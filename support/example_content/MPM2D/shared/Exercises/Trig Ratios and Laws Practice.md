---
title: Trig Ratios and Laws Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[The Primary Trigonometric Ratios]], then
[[The Sine Law]] and [[The Cosine Law]] — the toolkit your group
carried outside for [[Inaccessible Heights]]. Half the skill is the
calculation; the other half is choosing the tool. Round to one decimal.

## Questions

1. In a right triangle, the hypotenuse is $12$ cm and one acute angle
   is $35°$. Find the side opposite that angle.
2. From a point $18$ m from the base of a climbing wall, the angle of
   elevation to the top is $32°$. How tall is the wall?
3. In acute $\triangle ABC$, $\angle A = 40°$, $\angle B = 75°$, and
   $a = 10$ cm. Find $b$.
4. In acute $\triangle DEF$, $d = 7$ cm, $e = 9$ cm, and
   $\angle F = 52°$. Find $f$.
5. **Which tool, and why.** For each triangle, name the method —
   primary ratios, sine law, or cosine law — and say what decides it:
   (a) right triangle, one acute angle and the hypotenuse known;
   (b) acute, two angles and one side; (c) acute, two sides and the
   contained angle; (d) acute, all three sides.
6. **Challenge.** A triangular park has sides $5$ m, $7$ m, and
   $8$ m. Find its largest angle, and explain how you knew where to
   hunt before calculating anything.
7. **Explore the development.** In acute $\triangle ABC$, drop an
   altitude $h$ from vertex $C$ to side $c$ (meeting $c$ at $D$). Let
   $AD = x$, so $DB = c - x$. (a) In right $\triangle ACD$, express $x$
   and $h^2$ in terms of side $b$ and angle $A$. (b) Apply the
   Pythagorean theorem in right $\triangle BCD$: $a^2 = h^2 + (c - x)^2$.
   (c) Substitute your expressions from (a) into (b), expand, and
   simplify to produce the cosine law $a^2 = b^2 + c^2 - 2bc\cos A$.

## Answers

> [!success]- Answer 1
> Opposite over hypotenuse is sine: $x = 12 \sin 35° \approx 6.9$ cm.
> Size check: shorter than the hypotenuse, as it must be. ✓

> [!success]- Answer 2
> $h = 18 \tan 32° \approx 11.2$ m. The right angle at the wall's
> base is what makes a primary ratio legal here.

> [!success]- Answer 3
> A known side faces a known angle — sine law:
> $\frac{b}{\sin 75°} = \frac{10}{\sin 40°}$, so $b \approx 15.0$ cm.
> Check: the bigger angle faces the bigger side. ✓

> [!success]- Answer 4
> No known side faces a known angle — cosine law:
> $f^2 = 7^2 + 9^2 - 2(7)(9)\cos 52° \approx 52.4$, so
> $f \approx 7.2$ cm.

> [!success]- Answer 5
> (a) Primary ratios — a right angle is present. (b) Sine law — the
> third angle comes free, so a known side faces a known angle.
> (c) Cosine law — the known angle sits *between* the sides.
> (d) Cosine law, rearranged for an angle — the sine law cannot start
> without one. The decider: does a known side face a known angle?

> [!success]- Answer 6
> The largest angle faces the longest side, so hunt opposite the $8$ m
> side: $\cos\theta = \frac{5^2 + 7^2 - 8^2}{2(5)(7)} = \frac{1}{7}$,
> so $\theta \approx 81.8°$ — under $90°$: the triangle is truly acute.

> [!success]- Answer 7
> (a) In $\triangle ACD$, $\cos A = \frac{x}{b} \implies x = b\cos A$,
> and $h^2 = b^2 - x^2$.
> (b) In $\triangle BCD$,
> $a^2 = h^2 + (c - x)^2 = h^2 + c^2 - 2cx + x^2$.
> (c) Substitute $h^2 + x^2 = b^2$ and $x = b\cos A$:
> $a^2 = (h^2 + x^2) + c^2 - 2cx = b^2 + c^2 - 2c(b\cos A) = b^2 + c^2 - 2bc\cos A$.
> The cosine law is the Pythagorean theorem with the $-2bc\cos A$
> correction accounting for non-right angles — the development
> [[The Cosine Law]] establishes.

%%curriculum-start%%
## Curriculum connection

![[C2.1]]

![[C2.2]]

![[C3.1]]

![[C3.2]]

![[C3.3]]

![[C3.4]]
%%curriculum-end%%
