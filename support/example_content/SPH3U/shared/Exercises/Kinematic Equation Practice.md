---
title: Kinematic Equation Practice
publish: true
created: __CREATED__
tags:
  - exercises
  - unit-1
---
For each: list what you know, name the quantity that is neither known nor
wanted, and let that choose your equation — as on
[[The Kinematic Equations]].

**1.** A car accelerates uniformly from rest to $25\ \text{m/s}$ in
$8.0\ \text{s}$. How far does it travel?

> [!success]- Answer 1
> Neither known nor wanted: $a$. So use
> $\Delta d = \left(\frac{v_1+v_2}{2}\right)\Delta t = \left(\frac{0+25}{2}\right)(8.0) = 100\ \text{m}$.

**2.** A ball is thrown straight up at $14\ \text{m/s}$. How high does it
go? (Take up as positive, $a = -9.8\ \text{m/s}^2$.)

> [!success]- Answer 2
> At the top $v_2 = 0$, and $\Delta t$ is not wanted, so
> $v_2^2 = v_1^2 + 2a\Delta d$ gives
> $\Delta d = -14^2 / (2 \times -9.8) = 10\ \text{m}$.

**3.** A train braking at $0.50\ \text{m/s}^2$ takes $600\ \text{m}$ to
stop. How fast was it going?

> [!success]- Answer 3
> $v_1 = \sqrt{2 \times 0.50 \times 600} = 24\ \text{m/s}$, or about
> 88 km/h.

**4.** A stone is dropped from a bridge and hits the water
$2.4\ \text{s}$ later. How high is the bridge, and how fast was the stone
moving on impact?

> [!success]- Answer 4
> $\Delta d = \tfrac{1}{2}(9.8)(2.4)^2 = 28\ \text{m}$;
> $v_2 = 9.8 \times 2.4 = 24\ \text{m/s}$ downward.

**5.** An automated speed-enforcement camera monitors a $50\ \text{km/h}$ ($13.9\ \text{m/s}$) community safety zone. A vehicle travelling at $70\ \text{km/h}$ ($19.4\ \text{m/s}$) detects a pedestrian and brakes with a deceleration of $6.5\ \text{m/s}^2$ after a $1.2\ \text{s}$ driver reaction time.
- (a) Compute the total stopping distance from $70\ \text{km/h}$ versus the posted $50\ \text{km/h}$.
- (b) Assess how speed enforcement technologies reduce both collision severity and excessive fuel consumption.

> [!success]- Answer 5
> (a) At $70\ \text{km/h}$: Reaction distance $d_{react} = (19.4)(1.2) = 23.3\ \text{m}$. Braking distance $d_{brake} = v_1^2 / (2a) = (19.4)^2 / (2 \times 6.5) = 29.0\ \text{m}$. Total stopping distance $= 23.3 + 29.0 = 52.3\ \text{m}$.  
> At $50\ \text{km/h}$: Reaction distance $= (13.9)(1.2) = 16.7\ \text{m}$. Braking distance $= (13.9)^2 / (2 \times 6.5) = 14.9\ \text{m}$. Total stopping distance $= 16.7 + 14.9 = 31.6\ \text{m}$. A $40\%$ speed reduction yields a $40\%$ shorter stopping distance, preventing fatal impacts.  
> (b) Photo radar discourages high-speed driving and rapid acceleration cycles; lower steady speeds dramatically reduce aerodynamic drag (which scales with $v^2$), cutting vehicular carbon emissions and fuel consumption.

**6.** A drone flies $120\ \text{m}\ [\text{N}]$ in $15\ \text{s}$, hovers for $10\ \text{s}$, and flies $80\ \text{m}\ [\text{S}]$ in $10\ \text{s}$.
- (a) Calculate the drone's average speed (a scalar) and average velocity (a vector).
- (b) Explain why average speed can never be less than the magnitude of average velocity.

> [!success]- Answer 6
> (a) Total distance (scalar) $= 120 + 80 = 200\ \text{m}$. Total time $= 15 + 10 + 10 = 35\ \text{s}$.  
> Average speed $= 200 / 35 = 5.7\ \text{m/s}$.  
> Total displacement (vector) $= (+120) + (-80) = +40\ \text{m}\ [\text{N}]$.  
> Average velocity $= \vec{d}_{total} / \Delta t = (+40) / 35 = +1.1\ \text{m/s}\ [\text{N}]$.  
> (b) Distance accumulates along the entire actual path traversed regardless of reversals, whereas displacement measures only the net straight-line vector from the initial to final position. Thus $d \ge |\Delta \vec{d}|$, so average speed $\ge |\vec{v}_{avg}|$.

%%curriculum-start%%
## Curriculum connection

![[B1.2]]

![[B2.3]]

![[B2.7]]

![[B3.2]]
%%curriculum-end%%
