---
title: Population Growth
publish: true
created: __CREATED__
enableToc: true
tags:
  - concepts
  - unit-5
---
Two models, and knowing when each applies is most of the unit.

## Exponential

$$\frac{dN}{dt} = rN$$

Unlimited resources, constant per-capita growth rate. Bacteria in fresh
medium, an introduced species with no predators. It always ends, because
nothing is unlimited.

## Logistic

$$\frac{dN}{dt} = rN\left(\frac{K - N}{K}\right)$$

Growth slows as the population approaches carrying capacity $K$. The
S-shaped curve is the classic result: slow, then fast, then levelling.

## What sets carrying capacity

Food, water, space, nesting sites, disease, and predation. Density-DEPENDENT
factors intensify per-capita mortality or depress fecundity (birth rate) as
population density rises; density-INDEPENDENT factors — a hard frost, a
drought, a flood — eliminate individuals regardless of density.

In [[Modelling Population Growth]], you simulate how variations in intrinsic
fecundity, lag times, and resource limitations create damped oscillations or
chaotic boom-and-bust cycles around $K$.

## r-selected and K-selected

Many small offspring, high fecundity, little parental care, early maturity
(dandelions, fruit flies) versus few offspring, heavy energetic investment,
late maturity (whales, humans). Neither strategy is superior; each represents
an evolutionary trade-off across varying ecological disturbance regimes.

%%curriculum-start%%
## Curriculum connection

![[F2.1]]

![[F2.3]]

![[F3.1]]

![[F3.3]]
%%curriculum-end%%
