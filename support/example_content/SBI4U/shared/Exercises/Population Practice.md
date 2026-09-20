---
title: Population Practice
publish: true
created: __CREATED__
tags:
  - exercises
  - unit-5
---
**1.** A population of 200 grows at $r = 0.15$ per year with unlimited
resources. Find its size after 3 years.

> [!success]- Answer 1
> $N(t) = N_0(1 + r)^t = 200 \times 1.15^3 \approx 304$ individuals.

**2.** With $K = 1000$ and $N = 900$, what fraction of the maximum growth
rate remains?

> [!success]- Answer 2
> $(K - N)/K = (1000 - 900)/1000 = 0.10$ — one tenth. The environmental
> resistance term $(1 - N/K)$ heavily throttles the intrinsic rate of
> increase ($dN/dt = rN(1 - N/K)$), even though the population remains
> below carrying capacity.

**3.** Mark and recapture: 60 marked, later 80 caught of which 12 are
marked. Estimate the population.

> [!success]- Answer 3
> Using the Lincoln–Petersen index:
> $$N = \frac{M \times C}{R} = \frac{60 \times 80}{12} = 400\text{ individuals}$$

**4.** Which assumption of that method is most likely violated if marking
makes an animal more visible to predators, and which way is your estimate
wrong?

> [!success]- Answer 4
> The assumption that marked and unmarked individuals experience equal
> mortality. If predators selectively prey on marked animals, fewer marked
> individuals survive to the recapture phase ($R$ decreases), causing the
> calculated population size $N$ to be an overestimate (too high).

**5.** Distinguish density-dependent from density-independent limiting
factors, with an example of each.

> [!success]- Answer 5
> Density-dependent factors intensify their proportional effect on per-capita
> mortality or fecundity as population density increases (e.g., intraspecific
> competition for nest sites, communicable disease transmission, predation).
> Density-independent factors exert mortality irrespective of population size
> (e.g., severe unseasonal frost, forest fires, volcanic eruptions).

**6.** In a computer simulation of predator–prey dynamics (Lotka–Volterra model),
why does the predator population curve consistently lag behind the prey curve?

> [!success]- Answer 6
> Predator reproduction depends on prey consumption (conversion efficiency
> and gestation lag). As prey numbers expand, predator fecundity increases
> with a time delay; as predators over-consume prey, prey numbers drop first,
> which later causes predator starvation and population decline.

**7.** Apply the second law of thermodynamics and the 10% trophic efficiency
rule to human food energy flow. If $10^6\text{ kJ}$ of net primary productivity
is available in cereal grain:
a. Calculate the food energy available to humans consuming the grain directly
(trophic level 2).
b. Calculate the food energy available if the grain is fed to cattle and humans
consume the beef (trophic level 3).
c. State one consequence for global agricultural land use.

> [!success]- Answer 7
> a. Trophic level 2 (herbivores/humans eating grain):
>    $10^6\text{ kJ} \times 0.10 = 10^5\text{ kJ}$.
> b. Trophic level 3 (humans eating beef):
>    $10^5\text{ kJ} \times 0.10 = 10^4\text{ kJ}$ (a 90% loss of usable food
>    energy across the intermediate livestock trophic level).
> c. Plant-centred diets require significantly less arable land, freshwater, and
>    fertiliser per capita, effectively expanding human carrying capacity and
>    reducing ecological footprint.

**8.** Compare a population age-structure diagram with a wide triangular base
(high proportion of pre-reproductive individuals) to an urn-shaped diagram.
What does each predict about future population momentum?

> [!success]- Answer 8
> A triangular base indicates strong positive population momentum — rapid
> future growth as the large youth cohort reaches reproductive maturity, even
> if fertility rates decline. An urn-shaped profile (narrow base) indicates an
> aging population with negative momentum (impending natural decrease).

%%curriculum-start%%
## Curriculum connection

![[F1.1]]

![[F1.2]]

![[F2.1]]

![[F2.2]]

![[F2.3]]

![[F3.1]]

![[F3.2]]

![[F3.3]]

![[F3.4]]
%%curriculum-end%%
