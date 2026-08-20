---
title: Refraction
publish: true
created: __CREATED__
tags:
  - concepts
  - optics
---
In [[The Law of Reflection]] you learned to draw the normal before you drew
anything else. Keep that habit, because everything here depends on it too.

The observation this page explains is the one you can set up with a glass of
water and a straw: the straw appears broken at the surface, and the part under
water looks both bent and shallower than it is. Light did not stop travelling
in straight lines. It changed direction once, at the boundary, and this is why.

## Light bends because it changes speed

Light travels fastest in a vacuum. In any material it travels more slowly,
because the light interacts with the atoms it passes. How much slower is what
the **index of refraction** measures: $n = \frac{c}{v}$, where $c$ is the
speed of light in a vacuum and $v$ its speed in the material. A larger $n$
means slower light, and $n$ is never less than one.

| Material | Index of refraction |
| --- | --- |
| Vacuum | 1 exactly |
| Air | About 1.0003 — treat it as 1.00 |
| Water | About 1.33 |
| Ordinary glass | About 1.5 |
| Diamond | About 2.42 |

Now the mechanism, which is the part worth being able to say out loud. Picture
the ray not as a line but as a wave with a front — a row of soldiers marching
in step, if you like. When that front meets the boundary at an angle, one edge
of it enters the slower medium *before* the other edge does. That edge slows
down first, the other edge keeps going at the old speed for a moment longer,
and the front pivots. When the whole front is across, everything is marching
in step again — in a new direction.

Two things follow immediately. A ray that meets the boundary **along the
normal**, head-on, has every part of its front cross at the same instant, so
there is nothing to pivot and the ray does not bend at all — though it does
still change speed. And the amount of bending must depend on how obliquely the
ray arrives, which is exactly what the equation says.

## Which way, and how much

The direction is the thing to get right, and it is worth fixing it now rather
than guessing under pressure.

**Entering a slower medium — a higher index — the ray bends toward the
normal.** Going from air into water or glass, the angle in the second medium
is smaller than the angle in the first.

**Entering a faster medium — a lower index — the ray bends away from the
normal.** Coming out of water into air, the angle gets larger.

The relationship is **Snell's law**, $n_1 \sin\theta_1 = n_2 \sin\theta_2$,
where both angles are measured from the normal and the subscripts label the
two media. Check the direction rule against it: if $n_2$ is larger than $n_1$,
then $\sin\theta_2$ must be smaller than $\sin\theta_1$, so $\theta_2$ is the
smaller angle — closer to the normal. The equation and the rule are the same
statement.

So the factors that determine how much a ray refracts are exactly three: the
index of the medium it is leaving, the index of the medium it is entering, and
the angle of incidence. There is a quiet fourth. The index of a material is
very slightly different for different colours — larger for violet than for
red — so a beam of white light entering glass at an angle comes apart into its
colours. That separation is **dispersion**, and it is why a prism makes a
spectrum.

Refraction also explains the straw. Light from the submerged part leaves the
water and bends away from the normal at the surface, and your eye and brain
trace those rays back in straight lines to a point that is higher than where
they actually came from. The straw looks bent because you are seeing its lower
half in the wrong place. The same effect makes a pool look shallower than it
is, which is worth remembering before jumping in.

## Partial reflection, and the case where it becomes total

Light meeting a boundary rarely does only one thing. Usually **some reflects
and some refracts** at the same time — that is partial reflection and
refraction, and you have seen it every winter evening: a window at night shows
you both the street outside and a faint reflection of the room. The proportion
that reflects grows as the angle of incidence grows, which is why a lake
looks transparent when you stand at its edge looking down and mirror-like when
you look across it at a shallow angle.

There is one case where the refracted part disappears entirely.

Going from a **slower medium into a faster one** — glass to air, say — the ray
bends away from the normal, so the refracted angle is always larger than the
incident angle. Increase the incident angle far enough and the refracted angle
reaches 90°, lying flat along the surface. Push past that and there is no
refracted ray at all: **all** the light reflects back into the first medium,
obeying the ordinary law of reflection. This is **total internal reflection**.

The angle at which it begins is the **critical angle** $\theta_c$, found by
putting $\theta_2 = 90°$ into Snell's law, which gives $\sin\theta_c = \frac{n_2}{n_1}$.

Two conditions have to hold, and both are needed:

- the light must be travelling from the higher-index medium toward the lower,
  and
- the angle of incidence must be **greater than** the critical angle.

Reverse the first condition and it can never happen, however steep the angle.

This is not a curiosity. An optical fibre is a glass thread carrying light
that strikes its wall at a shallow angle, so it reflects totally, again and
again, for kilometres with almost nothing lost — which is how most long
distance data now travels. Good binoculars fold their light path with prisms
using total internal reflection rather than mirrors, because a total
reflection loses less light than any silvered surface. And a cut diamond
sparkles because its high index gives it a small critical angle, so light that
gets in bounces around inside before finding a face steep enough to escape
through.

Practise the calculations and the diagrams in [[Refraction Practice]], then
put curved surfaces on the glass and see what happens in
[[Lenses and Images]].

%%curriculum-start%%
## Curriculum connection

![[E3.4]]

![[E3.7]]

![[E3.8]]
%%curriculum-end%%
