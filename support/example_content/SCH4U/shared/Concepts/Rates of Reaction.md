---
title: Rates of Reaction
publish: true
created: __CREATED__
enableToc: true
tags:
  - concepts
  - kinetics
---
[[Factors That Change a Rate]] gave you five things to vary and a
stopwatch. Warmer went faster. More concentrated went faster. Powder
went faster than a lump. None of that is surprising, and none of it is
an explanation.

This page does the quantitative half — turning "faster" into a number
you can predict from. [[Collision Theory and Catalysts]] does the
explaining. Take them in that order, because you cannot check an
explanation against data you have not learned to read.

## Rate is a slope

Plot the concentration of a reactant against time and you get a curve
that falls steeply at first and flattens out. The **rate** at any moment
is how fast that curve is falling:

$$\text{rate} = -\frac{\Delta[\text{reactant}]}{\Delta t} = +\frac{\Delta[\text{product}]}{\Delta t}$$

The minus sign is there because a reactant's concentration decreases and
a rate is quoted as a positive number. Units are mol/(L·s) — a
concentration per unit time.

Two distinctions matter:

- An **average rate** is the slope of the straight line between two
  points on the curve. An **instantaneous rate** is the slope of the
  tangent at a single point. Averages over a long interval can be badly
  misleading, because the curve is steepest at the start.
- The **initial rate** is the instantaneous rate at $t = 0$. It is the
  one experiments are built around, because at that moment no products
  have accumulated and nothing is running backwards yet.

One more subtlety. In a reaction such as
$\ce{2A -> 3B}$, B appears faster than A disappears —
by a factor of $\tfrac{3}{2}$. To get a single rate for the reaction
rather than a rate per species, divide each by its coefficient. Quoting
"the rate" without saying which substance you measured is incomplete.

## The rate law is measured, not read off the equation

For most reactions the rate depends on the concentrations of the
reactants in a form like this:

$$\text{rate} = k[\ce{A}]^m[\ce{B}]^n$$

$k$ is the **rate constant**, fixed for a given reaction at a given
temperature. The exponents $m$ and $n$ are the **orders** with respect
to each reactant, and their sum is the overall order.

> [!warning] The orders are not the coefficients
> This is the point at which Grade 12 kinetics departs from everything
> you have done before, and it is worth stopping on.
>
> The exponents in a rate law can only be found by **experiment**. They
> are not the coefficients of the balanced equation, they are not
> derivable from it, and they need not even be whole numbers. A reaction
> with a coefficient of 2 may turn out to be first order in that
> reactant, or zero order, or something else.
>
> The reason is that a balanced equation is **bookkeeping**. It says
> what went in and what came out. It does not claim that all those
> particles met simultaneously — and if it did, it would usually be
> claiming something that essentially never happens.

The standard way to measure the orders is the **method of initial
rates**: run the reaction several times, changing one concentration at a
time, and see what each change does to the starting rate.

Suppose a set of trials for $\ce{A + B -> products}$
came out like this.

| Trial | $[\ce{A}]$, mol/L | $[\ce{B}]$, mol/L | Initial rate, mol/(L·s) |
| --- | --- | --- | --- |
| 1 | 0.10 | 0.10 | $2.0 \times 10^{-3}$ |
| 2 | 0.20 | 0.10 | $4.0 \times 10^{-3}$ |
| 3 | 0.10 | 0.20 | $8.0 \times 10^{-3}$ |

Compare trials 1 and 2. $[\ce{A}]$ doubles, $[\ce{B}]$ is held
still, and the rate doubles. Doubling produced a factor of $2^1$, so the
reaction is **first order in A**.

Compare trials 1 and 3. $[\ce{B}]$ doubles and the rate quadruples.
Doubling produced a factor of $2^2$, so the reaction is **second order
in B**.

$$\text{rate} = k[\ce{A}][\ce{B}]^2$$

Substituting trial 1 gives the rate constant:

$$k = \frac{2.0 \times 10^{-3}}{(0.10)(0.10)^2} = 2.0 \quad \text{L}^2/(\text{mol}^2 \cdot \text{s})$$

The overall order is three. Notice that nothing in that working ever
looked at the balanced equation, and that the units of $k$ came out of
the algebra rather than being remembered — they have to, because they
change with the overall order.

## What the balanced equation is hiding

A reaction that appears to be one event is almost always a sequence of
**elementary steps**, each one a genuine encounter between particles.
The sequence is the **mechanism**, and the steps must add up to the
overall balanced equation.

Two things live in a mechanism that never appear in the overall
equation:

- An **intermediate** is produced in one step and consumed in a later
  one. It is real, sometimes detectable, and cancels out of the sum.
- A **catalyst**, if there is one, is consumed early and regenerated
  later — the mirror image of an intermediate.

Steps are rarely equally fast. The **rate-determining step** is the
slowest one, and it controls the whole sequence in the same way the
narrowest point on a road controls the traffic: widening anything else
changes nothing.

That is where the rate law comes from. For an **elementary step** — and
only for an elementary step — the orders *do* equal the coefficients,
because a step is a description of an actual collision. So the
experimentally measured rate law is a window onto the slow step, and
reading it is how chemists find out what the mechanism is.

If the measured rate law for a reaction whose overall equation contains
$\ce{2NO2}$ turns out to be second order in $\ce{NO2}$, that is
consistent with two of those molecules colliding in the slow step. If it
turned out to be first order, they could not both be in it.

## What a mechanism can and cannot prove

Kinetics has a hard limit and you should be able to state it.

A proposed mechanism must (a) have steps that add to the overall
equation and (b) predict the rate law that was actually measured. A
mechanism failing either test is **wrong** and can be discarded on the
spot.

But a mechanism passing both tests is not thereby **right**. More than
one sequence of steps can predict the same rate law, and the rate law
cannot choose between them. The most a chemist says is that a mechanism
is *consistent with* the evidence — which is the same careful phrase you
will argue about in [[What Counts as Evidence]].

Practise extracting orders from trial data and writing rate laws in
[[Rate Law Practice]], and then design a rate experiment of your own in
[[The Rate Investigation]]. The explanation of *why* concentration and
temperature do what they do is waiting in
[[Collision Theory and Catalysts]].

%%curriculum-start%%
## Curriculum connection

![[D3.7]]

![[D2.8]]
%%curriculum-end%%
