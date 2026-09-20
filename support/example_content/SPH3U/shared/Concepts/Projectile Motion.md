---
title: Projectile Motion
publish: true
created: __CREATED__
enableToc: true
tags:
  - concepts
  - unit-1
---
A projectile is anything moving through the air with only gravity acting
on it — a thrown ball, a struck puck, a jet of water. The whole topic
rests on one idea, and it is a strange one the first time you meet it.

## The two directions do not talk to each other

Horizontal motion and vertical motion are **independent**. Gravity pulls
down, so it changes the vertical velocity and leaves the horizontal
velocity alone.

| Direction | Acceleration | What the motion looks like |
| --- | --- | --- |
| Horizontal | $0$ | Constant velocity: $d_x = v_x t$ |
| Vertical | $9.8\ \mathrm{m/s^2}$ down | Everything from [[The Kinematic Equations]] |

That is the entire method. Split the problem in two, solve each part with
the tools you already have, and let **time** be the one quantity the two
halves share.

> [!question] The demonstration worth remembering
> Two identical balls, one dropped and one fired horizontally from the
> same height at the same instant. They land together — every time, at
> any launch speed. If the horizontal motion affected the vertical, they
> could not.

## The recipe

1. Choose a positive direction for each axis and write it down.
2. Split the initial velocity: $v_x = v\cos\theta$, $v_y = v\sin\theta$.
   (For a horizontal launch, $v_y = 0$ and you are already done.)
3. Work in the **vertical** to find the time of flight — it is the only
   direction with an acceleration to bite on.
4. Take that time into the **horizontal** to find the range.

## Two facts students find surprising

- **At the top of the arc the projectile is still accelerating.** The
  vertical velocity is zero for an instant; the acceleration is
  $9.8\ \mathrm{m/s^2}$ down the entire time, including at that instant.
- **Launch angle and range**: on level ground, $45°$ gives the greatest
  range, and any two angles that add to $90°$ give the same range. A shot
  put coach knows this; so does anyone who has played a golf hole into
  the wind.

## What this model ignores

Air resistance, which for a light ball or a long flight is not small. A
struck baseball actually travels about 40% less far than this model
predicts. The model is still the right place to start — but say so in
your conclusions, because "the theory was wrong" is almost never the
reason your numbers disagreed.

%%curriculum-start%%
## Curriculum connection

![[B2.7]]

![[B2.8]]

![[B2.9]]
%%curriculum-end%%
