---
title: Midpoint and Length
publish: true
created: __CREATED__
tags:
  - concepts
---
In a [[Graph Talks]] warm-up you estimated the middle of a segment
by eye before anyone wrote a formula — halfway over, halfway up.
Two formulas run through all of analytic geometry, and neither needs
to be memorised, because each one is something you already know,
wearing coordinates.

## The midpoint is an average

Where is the middle of the segment from $A(2, 3)$ to $B(8, 11)$?
Halfway across and halfway up. Halfway across means averaging the
$x$-coordinates; halfway up means averaging the $y$-coordinates:

$$
M = \left( \frac{x_1 + x_2}{2}, \; \frac{y_1 + y_2}{2} \right)
= \left( \frac{2 + 8}{2}, \; \frac{3 + 11}{2} \right) = (5, 7)
$$

That is the whole formula: the average of the ends.[^1] If you can
average two test scores, you can find a midpoint — and if the
formula ever deserts you, a quick sketch rebuilds it, because the
middle of a segment is visibly halfway over and halfway up.

## The length is Pythagoras in disguise

How far is it from $A(2, 3)$ to $B(8, 11)$? Draw the segment, then
the horizontal run and the vertical rise. You have just built a
right triangle whose hypotenuse is the distance you want:

$$
d = \sqrt{(x_2 - x_1)^2 + (y_2 - y_1)^2}
= \sqrt{6^2 + 8^2} = \sqrt{100} = 10
$$

The formula *is* the Pythagorean theorem — $(x_2 - x_1)$ is one
leg, $(y_2 - y_1)$ is the other, and the square root undoes the
squaring on the hypotenuse. Squaring also makes the sign question
vanish: a run of $-6$ contributes the same $36$ as a run of $6$, so
the order you subtract in cannot hurt you.

A sketch is not decoration here — it is the method. Groups that
draw the right triangle first almost never confuse the two formulas,
because an average looks nothing like a hypotenuse. The same right
triangle also yields the line's slope as rise over run:
$m = \frac{y_2 - y_1}{x_2 - x_1}$.

These coordinate tools do heavy lifting elsewhere: length powers
[[The Equation of a Circle]], and slope, length, and midpoint together
let you verify real geometric claims in [[Properties on the Grid]].
[[Midpoint and Length Practice]] has the reps, including segments
whose length is an ugly root — leave it exact as $\sqrt{45}$, or
clean it to $3\sqrt{5}$, but resist rounding too early.

[^1]: Averages hide everywhere in this course — the axis of
    symmetry of a parabola is the average of its zeros, for the
    same halfway reason.

%%curriculum-start%%
## Curriculum connection

![[B1.4]]

![[B2.1]]

![[B2.2]]
%%curriculum-end%%
