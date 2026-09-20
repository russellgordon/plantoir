---
title: Refraction Practice
publish: true
created: __CREATED__
tags:
  - optics
  - exercises
---
Use $n_{\text{air}} = 1.00$, $n_{\text{water}} = 1.33$, and
$c = 3.00 \times 10^8$ m/s throughout. Every angle is measured from the
normal. Show the formula, then the substitution, then the answer with
units — and round only at the end.

**1.** A ray passes from air into a glass block. Does it bend toward
the normal or away from it? Explain using what happens to the speed of
the light.

> [!success]- Answer 1
> **Toward the normal.**
>
> Glass has a higher index of refraction than air, and the index is a
> statement about speed: $n = \frac{c}{v}$, so a higher index means
> light travels more slowly in that medium. When the ray meets the
> boundary at an angle, the part of the wavefront that arrives first
> slows down first, and the wavefront pivots — the same way a trolley
> veers if one wheel hits gravel before the other. The result is a ray
> that leans in closer to the normal.
>
> Going the other way — glass into air — the light speeds up and the
> ray bends **away** from the normal. The rule to hold on to is
> **slower means closer to the normal**, and it follows directly from
> $n_1 \sin\theta_1 = n_2 \sin\theta_2$: if $n_2$ is bigger then
> $\sin\theta_2$ must be smaller.

**2.** A ray travels from air into water with an angle of incidence of
40°. Find the angle of refraction.

> [!success]- Answer 2
> $$n_1 \sin\theta_1 = n_2 \sin\theta_2$$
>
> $\begin{aligned} \sin\theta_2 &= \frac{n_1 \sin\theta_1}{n_2} = \frac{(1.00)(\sin 40^\circ)}{1.33} = \frac{0.6428}{1.33} = 0.4833 \\ \theta_2 &= \sin^{-1}(0.4833) = 28.9^\circ \end{aligned}$
>
> **The angle of refraction is 28.9°.**
>
> Sanity check before you move on: 28.9° is smaller than 40°, so the
> ray bent **toward** the normal — which is what entering a
> higher-index medium should do. An answer larger than 40° here would
> mean an arithmetic slip, and the check costs you five seconds.

**3.** A ray enters an unknown transparent block from air. The angle of
incidence is 50° and the angle of refraction is 30°. Find the index of
refraction of the block.

> [!success]- Answer 3
> $$n_2 = \frac{n_1 \sin\theta_1}{\sin\theta_2} = \frac{(1.00)(\sin 50^\circ)}{\sin 30^\circ} = \frac{0.7660}{0.5000} = 1.53$$
>
> **The index of refraction is 1.53**, with no units — it is a ratio of
> two speeds, so the units cancel.
>
> Three significant figures is as far as this goes. The angles were
> given to two figures, and reporting 1.5321 would be claiming a
> precision the protractor never had.

**4.** Find the speed of light in water, and in the block from question
3.

> [!success]- Answer 4
> $$v = \frac{c}{n}$$
>
> **In water:**
> $v = \frac{3.00 \times 10^8\ \text{m/s}}{1.33} = 2.26 \times 10^8\ \text{m/s}$
>
> **In the block:**
> $v = \frac{3.00 \times 10^8\ \text{m/s}}{1.53} = 1.96 \times 10^8\ \text{m/s}$
>
> Both are slower than in vacuum, which they have to be — a refractive
> index below 1 would mean light travelling faster than $c$ in ordinary
> transparent matter, and nobody has seen that.
>
> Notice how large these still are. Light crosses a classroom in
> roughly a hundred-millionth of a second whether the room is full of
> air or full of water. The slowdown is small in everyday terms and
> completely decisive for the geometry.

**5.** A ray inside water meets the water–air surface at an angle of
incidence of 50°. Find the angle of refraction in air, and interpret
your result.

> [!success]- Answer 5
> $$\sin\theta_2 = \frac{n_1 \sin\theta_1}{n_2} = \frac{(1.33)(\sin 50^\circ)}{1.00} = (1.33)(0.7660) = 1.019$$
>
> There is **no angle whose sine is greater than 1**, so the equation
> has no solution — and that is not a mistake, it is the answer. No ray
> emerges into the air at all. All of the light is reflected back into
> the water, obeying the law of reflection at the surface. This is
> **total internal reflection**.
>
> The boundary case is the **critical angle**, where the refracted ray
> would just graze along the surface at 90°:
>
> $$\sin\theta_c = \frac{n_2}{n_1} = \frac{1.00}{1.33} = 0.7519 \qquad \theta_c = 48.8^\circ$$
>
> Our 50° is past that, which is why nothing got out. Total internal
> reflection happens only going from higher index to lower — you can
> never get it entering water from air — and it is what carries a
> signal down an optical fibre for kilometres with the light never
> once leaving the glass.

**6.** Explain, in terms of rays and where your brain assumes light
comes from, why a straw in a glass of water looks broken at the
surface, and why a pool looks shallower than it is.

> [!success]- Answer 6
> **The straw.** Light from the submerged part of the straw travels up
> through the water, and bends **away** from the normal as it leaves
> for the air. Your eye receives that bent ray but has no way of
> knowing it was bent — the visual system assumes light travels in
> straight lines, so it traces the ray straight back and places the
> submerged part somewhere it is not. The part above the water sends
> unbent light, so the two halves are located by two different rules
> and the straw appears to snap at exactly the surface.
>
> **The pool.** Same mechanism, applied to the bottom. Rays from the
> floor of the pool bend away from the normal on leaving the water,
> and traced straight back they meet **higher up** than the real floor.
> So the apparent depth is less than the real depth.
>
> This one is worth taking seriously outside a physics class. The
> bottom of any body of water is deeper than it looks, and looking
> shallow is not a reason to step in.

**7.** List the factors that determine how much a ray bends when it
crosses a boundary. Say which are qualitative and which you can put a
number on.

> [!success]- Answer 7
> **The angle of incidence.** Larger angles of incidence give larger
> angles of refraction — but not proportionally. It is the *sines* that
> stay in a fixed ratio, which is why a graph of $\sin\theta_1$ against
> $\sin\theta_2$ is straight and a graph of the raw angles is not
> quite. A ray arriving along the normal at 0° does not bend at all,
> however different the two media are.
>
> **The two indices of refraction**, meaning the speeds of light in
> the two media. Only the **ratio** matters, which is why
> $n_1 \sin\theta_1 = n_2 \sin\theta_2$ has both of them in it and why
> two media with the same index show no bending at their boundary at
> all.
>
> **The wavelength**, slightly. The index of a material is a little
> different for different colours, so violet bends marginally more than
> red. In a single flat boundary the effect is small; through a prism
> it separates into a spectrum, and in raindrops it makes a rainbow.
>
> All three can be quantified. In practice you will measure the first
> two and observe the third.

**8.** Two claims from a class discussion. *(a) "The frequency of the
light changes when it enters the water — that's what makes it bend."*
*(b) "Light always bends toward the normal when it enters a new
medium."* Correct both.

> [!success]- Answer 8
> **(a)** The frequency does **not** change. It is set by whatever
> produced the light, and crossing a boundary does not alter how many
> waves arrive per second — if it did, waves would have to pile up or
> disappear at the surface, which nothing does.
>
> What changes is the **speed**, and therefore the **wavelength**.
> Since $v = f\lambda$ with $f$ fixed, a smaller $v$ means a
> proportionally smaller $\lambda$. The bending follows from the speed
> change, not from a frequency change.
>
> There is a nice consequence: colour is tied to frequency, not
> wavelength, which is why a red object seen underwater is still red
> even though the light's wavelength in the water is shorter.
>
> **(b)** Only when entering a medium of **higher** index. Going the
> other way — glass to air, water to air — the light speeds up and
> bends **away** from the normal, which is exactly the case in question
> 5 and the case that makes total internal reflection possible.
>
> And one exception that swallows both: a ray arriving **along the
> normal**, at an angle of incidence of 0°, does not bend at all in
> either direction. Its speed still changes. Bending needs the boundary
> to be met at an angle, and "always" was doing far too much work in
> that sentence.

Reference: [[Refraction]]. Your own measurements of the index of
refraction: [[Finding the Focal Length]].

%%curriculum-start%%
## Curriculum connection

![[E2.6]]

![[E3.4]]

![[E3.7]]
%%curriculum-end%%
