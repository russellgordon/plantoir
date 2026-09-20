---
title: Vectors and Projectiles Practice
publish: true
created: __CREATED__
tags:
  - exercises
  - unit-1
---
**1.** A ball is kicked at $18\ \text{m/s}$, $35^\circ$ above the
horizontal, from level ground. Find its time of flight and range.

> [!success]- Answer 1
> $v_y = 18\sin 35^\circ = 10.3\ \text{m/s}$, so time up is
> $10.3/9.8 = 1.05\ \text{s}$ and total flight is $2.1\ \text{s}$.
> $v_x = 18\cos 35^\circ = 14.7\ \text{m/s}$, so range
> $= 14.7 \times 2.1 = 31\ \text{m}$.

**2.** A plane flies at $220\ \text{km/h}$ heading north while the wind
blows at $60\ \text{km/h}$ from the west. Find the ground velocity.

> [!success]- Answer 2
> Components: $220$ north, $60$ east. Magnitude
> $\sqrt{220^2 + 60^2} = 228\ \text{km/h}$, direction
> $\tan^{-1}(60/220) = 15^\circ$ east of north.

**3.** A stone is thrown horizontally at $12\ \text{m/s}$ from a
$45\ \text{m}$ cliff. Where does it land, and how fast is it moving on
impact?

> [!success]- Answer 3
> Fall time: $t = \sqrt{2h/g} = 3.03\ \text{s}$; horizontal distance
> $36\ \text{m}$. Impact: $v_x = 12$, $v_y = 29.7$, so
> $v = 32\ \text{m/s}$ at $68^\circ$ below horizontal.

**4.** Why is the horizontal velocity unchanged throughout question 3?

> [!success]- Answer 4
> Because no horizontal force acts. Gravity is vertical, and the two
> directions are independent — the point of [[Projectile Motion]].

**5.** In a modified Atwood pulley system ("dumb waiter" configuration), a
$4.0\ \text{kg}$ block on a frictionless incline angled at $30^\circ$ is
connected by a light string over a frictionless pulley to a hanging
$3.0\ \text{kg}$ mass. Using free-body diagrams and algebraic equations,
predict the magnitude of the system acceleration and the tension in the
string.

> [!success]- Answer 5
> For the block on the incline (taking uphill as positive):
> $T - m_1 g \sin 30^\circ = m_1 a$. For the hanging mass (taking downward as
> positive): $m_2 g - T = m_2 a$. Adding equations eliminates tension:
> $a = \frac{m_2 g - m_1 g \sin 30^\circ}{m_1 + m_2} = \frac{(3.0)(9.8) - (4.0)(9.8)(0.50)}{4.0 + 3.0} = \frac{29.4 - 19.6}{7.0} = 1.4\ \text{m/s}^2$.
> Substituting back gives tension:
> $T = m_2 (g - a) = (3.0)(9.8 - 1.4) = 25.2\ \text{N}$.

**6.** A $5.0\ \text{kg}$ wooden crate rests on the flat bed of a pickup
truck. The coefficient of static friction is $\mu_s = 0.40$ and kinetic
friction is $\mu_k = 0.30$. (a) Determine the maximum forward acceleration
the truck can sustain without the crate sliding. (b) If the truck
accelerates forward at $5.5\ \text{m/s}^2$, determine the acceleration of
the crate relative to the ground (inertial frame) and relative to the truck
(non-inertial frame).

> [!success]- Answer 6
> (a) Static friction provides the forward force:
> $F_{s,\text{max}} = \mu_s mg = (0.40)(5.0)(9.8) = 19.6\ \text{N}$.
> Maximum acceleration: $a_{\text{max}} = \mu_s g = (0.40)(9.8) = 3.92\ \text{m/s}^2$.
> (b) At $a_{\text{truck}} = 5.5\ \text{m/s}^2$, the crate slips. Kinetic
> friction acts forward on the crate:
> $F_k = \mu_k mg = (0.30)(5.0)(9.8) = 14.7\ \text{N}$.
> In the ground (inertial) frame, $a_{\text{crate, ground}} = F_k / m = \mu_k g = 2.94\ \text{m/s}^2$ forward.
> In the truck's (non-inertial) frame, an apparent fictitious inertial force
> acts backward: $a_{\text{crate, truck}} = a_{\text{crate, ground}} - a_{\text{truck}} = 2.94 - 5.5 = -2.56\ \text{m/s}^2$
> ($2.6\ \text{m/s}^2$ backward relative to the truck bed).

%%curriculum-start%%
## Curriculum connection

![[B2.1]]

![[B2.2]]

![[B2.3]]

![[B2.4]]

![[B2.5]]

![[B3.2]]
%%curriculum-end%%

