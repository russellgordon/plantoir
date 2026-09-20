---
title: The Flying Pig
publish: true
created: __CREATED__
enableToc: true
tags:
  - investigations
  - unit-1
---
> [!abstract] At a glance
> **Time:** one class, with the full report written in class the next
> period and handed in at the bell — it is the first of the marked
> [[Investigation Write-Ups]]. **Groups of three at the bench, write-up
> yours alone. The point:** measure the net force on something in uniform
> circular motion two independent ways, and see whether they agree.

A battery-powered toy pig hangs from a pivot on the ceiling and flies in a
horizontal circle. Its string sweeps out a cone — a **conical pendulum** —
and that geometry lets you calculate the speed it must have, from nothing
but an angle and a radius. Then you measure the speed directly and find
out whether the physics was right.

## Safety

> [!warning] A circle of clear floor
> The pig flies at head height at a few metres per second. Clear the full
> circle plus a metre before switching on, and everyone stands outside it.
> Check the pivot with me before power goes on — a pig that comes off its
> string is a projectile.

Wings click into their fixed position; they are delicate and they are not
what you are measuring.

## Before you switch anything on

Draw the free-body diagram. There are exactly **two** forces on the pig:
gravity, $mg$, straight down, and the string tension $T$ along the string.
There is no outward force. If your diagram has one, read
[[Centripetal Force]] again before continuing.

Now resolve $T$ into components, with $\theta$ measured from the
vertical:

- **Vertically** the pig does not accelerate, so $T\cos\theta = mg$.
- **Horizontally** the net force IS the centripetal force, so
  $T\sin\theta = \dfrac{mv^2}{r}$.

Divide the second by the first and the tension — which you never
measured — disappears:

$$\tan\theta = \frac{v^2}{rg} \qquad \Rightarrow \qquad v = \sqrt{rg\tan\theta}$$

The mass has vanished too. Predict, before you measure: does a heavier pig
fly faster?

## Method

1. Launch the pig with a gentle push, tangent to the circle it should
   fly. Too hard is worse than too soft. Give it ten seconds to settle
   into a circle of constant radius.
2. **Radius.** Measure the radius of the circle it traces, as accurately
   as you can manage. Decide as a group HOW before you start — a metre
   stick held at the pig's height, a chalk circle on the floor beneath it,
   or a photograph from directly above.
3. **Angle.** Find $\theta$, the angle of the string from the vertical.
   A protractor is the obvious method and rarely the best. Two better
   ones: measure the string length $L$ and use $\sin\theta = r/L$, or
   photograph the cone from the side and measure the angle on the image.
   Say which you used and why.
4. **Period.** Time **ten** revolutions and divide by ten. This is the
   single most important precision decision in the investigation — see
   [[Uncertainty and Error]].

## What to record

| Quantity | Symbol | Value | Uncertainty |
| --- | --- | --- | --- |
| Radius of the circle | $r$ | | |
| String length | $L$ | | |
| Angle from vertical | $\theta$ | | |
| Time for ten revolutions | $10T$ | | |
| Mass of the pig | $m$ | | |

Three independent runs, relaunched each time — not three timings of one
flight. The write-up is a full report — see [[Writing a Lab Report]].

## The two routes

**Predicted, from the geometry:**

$$v_{predicted} = \sqrt{rg\tan\theta}$$

**Measured, from the motion:**

$$v_{measured} = \frac{2\pi r}{T}$$

Then the percent difference, using the predicted value as the reference.

## Analysis

1. How close were your two speeds? Is the difference within the
   uncertainty you estimated, or larger?
2. The mass cancelled in the derivation. Test it: swap pigs with another
   group, or add a small mass, and see whether the angle at a given radius
   changes. Report what you predicted first.
3. Compute the tension in the string two ways — from $T\cos\theta = mg$
   and from $T\sin\theta = mv^2/r$ — and compare.
4. Air resistance is doing something the derivation ignored. Which
   direction does it push your measured speed, and can you see that in
   your numbers?
5. If the pig flew in a bigger circle, would the angle be larger or
   smaller? Predict from the equation, then check against another group's
   data.

> [!note] For teachers
> Any toy that flies in a circle from a pivot works — a pig, a plane, a
> cow. The pivot is what makes the radius constant, and it must be
> attached firmly; a rod-and-clamp arrangement works when the ceiling does
> not. Measuring $\theta$ is deliberately left open, and it is where the
> genuine experimental thinking happens: the groups who photograph the
> cone against a plumb line get the best data. This investigation follows
> the version Paul Robinson published for his own classes.[^1]

[^1]: Robinson, P. *The Flying Pig* (laserpablo.com). The two-route
    comparison — predicted from geometry, measured from period — is his.

%%curriculum-start%%
## Curriculum connection

![[B2.6]]

![[B2.7]]

![[B3.3]]

![[A1.8]]
%%curriculum-end%%
