---
title: Testing Hess's Law
publish: true
created: __CREATED__
enableToc: true
tags:
  - chemistry
  - investigation
---
Last week you measured the energy released when an acid and a base meet
in a cup. Today you are going to reach the **same destination by two
different routes** and find out whether the energy bill depends on which
way you went.

If it does not — if a long way round and a short way round cost exactly
the same — then energy change is a property of where you started and
where you ended, and nothing else. That is a very large claim, and you
can test it in a polystyrene cup in one period.

## What you are trying to find out

Start with solid sodium hydroxide and dilute hydrochloric acid. End with
sodium chloride solution and water. There are two ways to get there.

| Route | What you do | What you measure |
| --- | --- | --- |
| **A — direct** | Drop the solid straight into the acid | $\Delta H_2$, in one experiment |
| **B — two steps** | Dissolve the solid in water first, then add that solution to the acid | $\Delta H_1$ and $\Delta H_3$, in two experiments |

Written as equations, with states, because the states are the entire
point:

$$\ce{NaOH(s) -> Na+(aq) + OH-(aq)} \qquad \Delta H_1$$

$$\ce{NaOH(s) + HCl(aq) -> NaCl(aq) + H2O(l)} \qquad \Delta H_2$$

$$\ce{NaOH(aq) + HCl(aq) -> NaCl(aq) + H2O(l)} \qquad \Delta H_3$$

The question is whether $\Delta H_1 + \Delta H_3$ comes out equal to
$\Delta H_2$, within the uncertainty of three cup experiments.

> [!abstract] Why those three equations add up
> Equations can be added like algebra, and anything appearing on both
> sides cancels. Notice first that "$\ce{NaOH(aq)}$" and
> "$\ce{Na+(aq) + OH-(aq)}$" are two names for
> the same thing — a sodium hydroxide solution *is* those ions in
> water.
>
> $\begin{aligned} \ce{NaOH(s)} &\ce{-> Na+(aq) + OH-(aq)} \\ \ce{Na+(aq) + OH-(aq) + HCl(aq)} &\ce{-> NaCl(aq) + H2O(l)} \\ \hline \ce{NaOH(s) + HCl(aq)} &\ce{-> NaCl(aq) + H2O(l)} \end{aligned}$
>
> The ions appear on the right of the first line and the left of the
> second, so they cancel, and what survives is exactly the direct route.
> **If the equations add, the claim being tested is that the enthalpies
> add too.** That is the whole of what you are checking.

## What you have to work with

- **Solid sodium hydroxide**, in pellets, in a closed container.
- **Hydrochloric acid, 1.0 mol/L**, and **sodium hydroxide solution,
  1.0 mol/L**, both as supplied.
- **Distilled water.**
- Nested polystyrene cups with a lid, a thermometer or temperature
  probe, a balance reading to at least 0.01 g, graduated cylinders, a
  spatula, a small dry beaker or weighing boat.

Your design decisions, written and justified before the lab:

- **How much solid you will use**, calculated so that the acid is in
  excess in Route A. If the solid is in excess, some of it dissolves
  without reacting, and you are then measuring a mixture of two
  different processes at once. Show the calculation.
- **The same amount of substance in every run.** All three experiments
  have to be scaled to the same number of moles of sodium hydroxide,
  because you are going to add and subtract the results. Show how you
  worked out the volumes and masses that make that true.
- **How you will mass a hygroscopic solid quickly.** Sodium hydroxide
  pellets pull water out of the air continuously while they sit on a
  balance pan. Say what you will do about it and how long you will
  allow yourself.
- **Your mass for $m$ in $Q = mc\Delta T$**, for each of the three
  runs, and your reason. It is not the same choice in all three, and
  noticing that is most of the analysis.
- **Your reading interval for the maximum temperature.** The same
  interval in all three runs, or the comparison is not a comparison.
- **How many trials of each**, and what agreement you will accept.

> [!danger] Solid sodium hydroxide is the most hazardous thing here
> Read this one twice. Pellets are not the same as the dilute solution
> you have used before, and they are not treated the same way.
>
> - **Sodium hydroxide does not warn you.** Dilute acid stings, so you
>   notice a splash and rinse it. Sodium hydroxide feels soapy or
>   slippery — that sensation is the solid or the solution attacking the
>   fats in your skin — and it keeps working while it does not hurt. A
>   base burn of the same strength penetrates **deeper** than an acid
>   burn, exactly because nothing made you pull away. **Rinse any
>   suspected contact for at least 15 minutes under running water**,
>   whether or not it hurts, and tell me. In an eye it is an emergency:
>   eyewash at once, hold the lid open, and somebody else comes for me
>   while you stay at the eyewash.
> - **Pellets are handled with a spatula, never with fingers**, and
>   never with damp fingers. A pellet held in a moist hand starts
>   dissolving into your skin within seconds.
> - **Add the solid to the liquid, slowly, with stirring — never liquid
>   onto a heap of solid.** This is the same rule as *acid into water*
>   and it exists for the same reason. Dissolving sodium hydroxide
>   releases a great deal of heat very quickly; with the liquid already
>   there, the heat spreads through the whole volume, and the other way
>   round it concentrates where the liquid lands and can spit caustic
>   solution back at you.
> - **A dropped pellet is picked up with a spatula and told to me**, not
>   with a bare hand and not with a paper towel you then put in the bin.
>   Pellets on a bench absorb water and become invisible caustic
>   puddles.
> - **The container is closed the moment you have what you need.**
>   Sodium hydroxide absorbs both water and carbon dioxide from the air,
>   which is a safety point, a housekeeping point, and — as you will see
>   in the analysis — a data point.
> - **Eye protection on from the first move to the last of the
>   cleanup.** Hair tied back, sleeves secured, closed-toe shoes.
> - **The acid is dilute and stays dilute.** Use it as supplied. Nothing
>   is concentrated today, nothing is heated, and no flame comes near
>   this bench.
> - **The thermometer is not a stirring rod**, and nothing goes back into
>   a stock bottle.
> - **Check the pH of every mixture before disposal** and follow the
>   route I give you. A mixture you assumed was neutral usually is not.
> - **Report every incident immediately**, however small.

## The prediction you write first

Before you mass anything:

1. **The sign of all three $\Delta H$ values.** All three, committed.
2. **Which of $\Delta H_1$ and $\Delta H_3$ you expect to be larger in
   magnitude**, and one sentence of reason.
3. **Your prediction for $\Delta H_2$**, calculated from your predicted
   $\Delta H_1$ and $\Delta H_3$ — or, better, run the two Route B
   experiments first, add them, and **write down what Route A must give
   before you run it.** That is a genuine prediction with a number
   attached, and it is the strongest form this lab takes.
4. **The agreement you would accept.** Before you see any data, decide
   what percentage difference between the two routes you would call a
   confirmation and what you would call a failure. Deciding this
   afterwards is how everybody's data confirms everything.

## What to collect

| Run | Reaction | Mass of NaOH (g) | Mass warmed, $m$ (g) | Initial temp (°C) | Maximum temp (°C) | $\Delta T$ (°C) |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Solid into water | | | | | |
| 2 | Solid into acid | | | | | |
| 3 | Solution into acid | | | | | |

For each run, work through the same three steps, carrying units:

$$Q = mc\Delta T \qquad n = \frac{m_{\ce{NaOH}}}{M_{\ce{NaOH}}} \qquad \Delta H = -\frac{Q}{n}$$

with $c = 4.18\ \text{J/(g}\cdot^\circ\text{C)}$ for these dilute
solutions. The minus sign is not decoration: $Q$ is the energy the
**solution gained**, and $\Delta H$ describes the **system**, so the
sign flips exactly once and it flips there.

Then the comparison, which is the actual result:

| Quantity | Value (kJ/mol) |
| --- | --- |
| $\Delta H_1$ (solid into water) | |
| $\Delta H_3$ (solution into acid) | |
| $\Delta H_1 + \Delta H_3$ — Route B | |
| $\Delta H_2$ (solid into acid) — Route A | |
| Difference | |
| Difference as a percentage of $\Delta H_2$ | |

**Significant figures matter more here than anywhere else this term**,
because you are subtracting two numbers of similar size at the end. Keep
full precision in the calculator through every intermediate step and
round once, at the very end, to the number of figures your worst
measurement allows — which will be $\Delta T$, and which will probably
be two. A "difference" quoted to four figures from data good to two is
not a result. See [[Significant Figures and Units]].

## What to bring to the consolidation

- Your prediction, dated before the data, including the agreement
  threshold you set in advance.
- All three runs, every trial, including any you excluded and why.
- **The comparison table above, completed**, with the difference stated
  both as a value and as a percentage.
- **Your verdict against your own threshold.** Did the routes agree by
  the standard you set before you started? Answer that question, in
  those words.
- **Both routes compared with the data booklet.** Look up the accepted
  values and state how far each of your three measurements sits from
  them. You may find that both routes are wrong in the same direction
  and still agree with each other, which is the most interesting outcome
  available today.
- **The class data.** Every group's Route A and Route B on one plot,
  Route B on one axis and Route A on the other. If the law holds and the
  errors are random, the points scatter around a line of slope 1
  through the origin. Systematic error moves the whole cloud off that
  line, and it moves it in a direction you should be able to explain.

## What you should not claim

- **Agreement does not prove Hess's law and disagreement does not refute
  it.** You ran three cup experiments in one period. What you can
  defend is that your measurements were, or were not, consistent with
  the law at the precision you could achieve — and stating the precision
  is what turns that into a real sentence.
- **Heat loss makes every magnitude too small.** In each run, some
  energy warmed the cups, the lid, the thermometer, and the air, and
  none of it reached the water you counted. Every measured $\Delta T$ is
  therefore low and every $|\Delta H|$ is therefore low. Your three
  numbers are all underestimates, before you compare anything.
- **The two routes do not lose heat equally, and the direction depends
  on something you can test.** Route B is two experiments and Route A is
  one. If each run loses a similar *fraction* of its energy, the two
  routes are biased by similar percentages and the comparison partly
  survives. If each run loses a similar *absolute* amount — which is
  closer to true when the losses come from the apparatus warming up —
  then Route B loses roughly twice as much, and its sum comes out
  **less negative** than Route A. Look at your own numbers and say which
  picture they support. This is a better paragraph than anything you can
  write about "human error".
- **Sodium hydroxide pellets are not pure sodium hydroxide by the time
  you weigh them, and the error has a direction.** They absorb water and
  carbon dioxide from the air. So the mass on your balance includes
  material that is not going to react, which means your calculated $n$
  is **too large**, which means $|\Delta H| = Q/n$ comes out **too
  small**. This pushes the same way as the heat loss, and the two
  together are why school values for this experiment sit below the
  booklet's.
- **You cannot claim the acid was in excess unless you calculated it.**
  If the solid ran out of acid to react with, part of what you measured
  in Route A was dissolution rather than neutralisation — which is
  Route B's first step contaminating Route A's only step, and it would
  make the routes agree for entirely the wrong reason.
- **A percentage difference is not an uncertainty.** Saying "the routes
  agreed to within 6%" says nothing until you also say what spread your
  repeats showed. If your own repeats differ by 10%, then a 6%
  difference between routes is not a detection of anything.

Where this goes next: [[Hess's Law]] states the law properly and shows
what it lets you calculate that you could never measure, and
[[Hess's Law Practice]] is where you do the equation arithmetic until
the sign errors stop. The measurement technique came from
[[Calorimetry of a Neutralisation]], and the account of $Q = mc\Delta T$
is in [[Calorimetry]].

%%curriculum-start%%
## Curriculum connection

![[A1.1]]

![[A1.4]]

![[A1.13]]

![[D2.6]]

![[D3.4]]
%%curriculum-end%%
