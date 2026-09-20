---
title: Relativity and Quanta Practice
publish: true
created: __CREATED__
tags:
  - exercises
  - unit-5
---
**1.** A spacecraft passes at $0.80c$. How long does its $1.00\ \text{s}$
clock tick appear to an observer at rest?

> [!success]- Answer 1
> $\gamma = 1/\sqrt{1 - 0.64} = 1.67$, so $1.67\ \text{s}$.

**2.** That spacecraft is $120\ \text{m}$ long in its own frame. How long
does the observer measure it?

> [!success]- Answer 2
> $L = 120/1.67 = 72\ \text{m}$, contracted along its motion only.

**3.** A metal has a work function of $2.3\ \text{eV}$. What is the
longest wavelength of light that will eject electrons?

> [!success]- Answer 3
> $W = 3.7\times10^{-19}\ \text{J}$; $f = W/h = 5.6\times10^{14}\ \text{Hz}$;
> $\lambda = c/f = 5.4 \times 10^{-7}\ \text{m}$, about 540 nm. Redder
> light does nothing, however bright.

**4.** Find the de Broglie wavelength of an electron moving at
$1.5 \times 10^6\ \text{m/s}$.

> [!success]- Answer 4
> $\lambda = h/(mv) = (6.63\times10^{-34})/((9.11\times10^{-31})(1.5\times10^6)) = 4.9 \times 10^{-10}\ \text{m}$
> — comparable to atomic spacing, which is why crystals diffract
> electrons.

**5.** In a photoelectric effect inquiry simulating a potassium photocathode,
a student measures the stopping potential $V_{\text{stop}}$ required to halt
photoelectrons across four incident frequencies:

| Frequency $f$ ($10^{14}\ \text{Hz}$) | $6.0$ | $7.0$ | $8.0$ | $9.0$ |
| --- | --- | --- | --- | --- |
| Stopping potential $V_{\text{stop}}$ ($\text{V}$) | $0.22$ | $0.63$ | $1.04$ | $1.46$ |

(a) Using Einstein's photoelectric equation $e V_{\text{stop}} = hf - W$,
determine the experimental value of Planck's constant $h$ from the slope of
the $V_{\text{stop}}$ vs $f$ graph. (b) Determine the work function $W$ in
$\text{eV}$ and the threshold frequency $f_0$.

> [!success]- Answer 5
> (a) Slope $m = \frac{\Delta V_{\text{stop}}}{\Delta f} = \frac{1.46 - 0.22}{(9.0 - 6.0)\times 10^{14}} = \frac{1.24}{3.0 \times 10^{14}} = 4.13 \times 10^{-15}\ \text{V}\cdot\text{s}$.
> Since $e V_{\text{stop}} = hf - W \implies V_{\text{stop}} = \frac{h}{e}f - \frac{W}{e}$,
> $h = e \times m = (1.602 \times 10^{-19}\ \text{C})(4.13 \times 10^{-15}\ \text{V}\cdot\text{s}) = 6.62 \times 10^{-34}\ \text{J}\cdot\text{s}$.
> (b) Threshold frequency $f_0$ occurs where $V_{\text{stop}} = 0$:
> $0 = (4.13 \times 10^{-15})f_0 - \frac{W}{e} \implies f_0 = 6.0 \times 10^{14} - \frac{0.22}{4.13 \times 10^{-15}} = 5.47 \times 10^{14}\ \text{Hz}$.
> Work function $W = h f_0 = (4.13 \times 10^{-15}\ \text{eV}\cdot\text{s})(5.47 \times 10^{14}\ \text{Hz}) = 2.26\ \text{eV}$
> ($3.62 \times 10^{-19}\ \text{J}$).

**6.** At the TRIUMF cyclotron facility in Vancouver, protons ($m_0 = 1.67 \times 10^{-27}\ \text{kg}$)
are accelerated to a relativistic speed of $v = 0.75c$. (a) Calculate the
classical momentum $p_{\text{classical}} = m_0 v$ and the relativistic
momentum $p_{\text{rel}} = \gamma m_0 v$. (b) Explain how the measured
deflection curvature of the proton beam in the facility's dipole steering
magnets ($r = p / (qB)$) proves the validity of relativistic dynamics and
refutes classical Newtonian mechanics at high velocities.

> [!success]- Answer 6
> (a) Lorentz factor $\gamma = 1/\sqrt{1 - (0.75)^2} = 1/\sqrt{0.4375} = 1.512$.
> Classical: $p_{\text{classical}} = (1.67 \times 10^{-27})(0.75 \times 3.00 \times 10^8) = 3.76 \times 10^{-19}\ \text{kg}\cdot\text{m/s}$.
> Relativistic: $p_{\text{rel}} = \gamma p_{\text{classical}} = (1.512)(3.76 \times 10^{-19}) = 5.68 \times 10^{-19}\ \text{kg}\cdot\text{m/s}$.
> (b) In a uniform magnetic field $B$, a charged particle follows a circular
> arc of radius $r = p / (qB)$. If Newtonian mechanics were valid, the beam
> would bend along a radius corresponding to $p_{\text{classical}}$, requiring
> a smaller magnetic field to steer. In actual accelerator experiments, the
> observed beam radius requires the magnetic force to bend the $51\%$ larger
> relativistic momentum $p_{\text{rel}}$, conclusively proving relativistic
> momentum conservation.

%%curriculum-start%%
## Curriculum connection

![[F2.2]]

![[F2.3]]

![[F2.4]]

![[F3.1]]

![[F3.2]]

![[F3.3]]
%%curriculum-end%%

