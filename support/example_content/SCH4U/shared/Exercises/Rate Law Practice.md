---
title: Rate Law Practice
publish: true
created: __CREATED__
enableToc: false
tags:
  - chemistry
  - exercises
---
One warning before you start, because it is the source of most of the
wrong answers on this topic:

> [!warning] You cannot read a rate law off a balanced equation
> The exponents in a rate law are found **by experiment** and nowhere
> else. They are not the coefficients, they are frequently not whole
> numbers you would have guessed, and a substance in the balanced
> equation can be entirely absent from the rate law.
>
> There is exactly one exception, and it is narrow: for an **elementary
> step** — a single collision event, written as it actually happens —
> the coefficients *are* the exponents. Overall equations are almost
> never elementary, which is why the rule fails almost everywhere it is
> applied.

Rate is a **change in concentration per unit time**, so its units are
usually mol/(L·s). The rate constant $k$ has whatever units make the
right-hand side of the rate law come out in mol/(L·s), which means its
units change with the overall order. Work them out; do not memorise
them.

**1.** The concentration of a reactant falls from 0.500 mol/L to
0.380 mol/L over 30.0 s. Calculate the average rate of consumption. Why
is this not the same as the rate at $t = 0$?

> [!success]- Answer 1
> $\text{rate} = -\frac{\Delta[\ce{A}]}{\Delta t} = \frac{0.500 - 0.380\ \text{mol/L}}{30.0\ \text{s}} = \frac{0.120\ \text{mol/L}}{30.0\ \text{s}}$
>
> $\text{rate} = 4.00 \times 10^{-3}\ \text{mol/(L}\cdot\text{s)}$
>
> The minus sign in the definition is there because $[\ce{A}]$ is
> falling, and a rate is reported as a positive quantity. Put the sign
> in the definition, not in the answer.
>
> **Why this is not the initial rate.** Almost every reaction slows down
> as it proceeds, because the reactants are being used up and collisions
> between them become less frequent. So the rate at the start is higher
> than $4.00 \times 10^{-3}$ mol/(L·s), the rate at 30.0 s is lower, and
> your answer is an **average** that belongs to neither moment.
>
> On a graph of concentration against time this is the difference
> between the slope of the **chord** joining two points and the slope of
> the **tangent** at one point. The average rate is the chord; the
> instantaneous rate is the tangent.
>
> **This is why every rate law is determined from initial rates.** At
> $t = 0$ you know all the concentrations exactly, because they are the
> ones you mixed. A moment later you do not, and any rate you measure
> then belongs to a mixture whose composition you would have to work out
> before you could use it.

**2.** For $\ce{2N2O5(g) -> 4NO2(g) + O2(g)}$,
oxygen is being formed at $2.5 \times 10^{-3}$ mol/(L·s). At what rate
is $\ce{N2O5}$ being consumed, and $\ce{NO2}$ formed?

> [!success]- Answer 2
> The coefficients do not give you the rate *law*, but they absolutely
> do give you the ratios between the rates of the different species —
> those come straight from the stoichiometry, which has to hold moment
> by moment.
>
> For every 1 mole of $\ce{O2}$ formed, 2 moles of
> $\ce{N2O5}$ are consumed and 4 moles of $\ce{NO2}$ are
> formed.
>
> $\begin{aligned} \text{rate of } \ce{N2O5} \text{ consumption} &= 2 \times (2.5 \times 10^{-3}) = 5.0 \times 10^{-3}\ \text{mol/(L}\cdot\text{s)} \\ \text{rate of } \ce{NO2} \text{ formation} &= 4 \times (2.5 \times 10^{-3}) = 1.0 \times 10^{-2}\ \text{mol/(L}\cdot\text{s)} \end{aligned}$
>
> **This is why "the rate of the reaction" is ambiguous** unless you say
> which substance you mean. Three perfectly correct numbers describe the
> same reaction at the same instant and they differ by a factor of four.
>
> Chemists get round it by dividing each rate by its coefficient, which
> gives one number for the whole reaction:
>
> $\text{rate} = -\tfrac{1}{2}\frac{\Delta[\ce{N2O5}]}{\Delta t} = \tfrac{1}{4}\frac{\Delta[\ce{NO2}]}{\Delta t} = \frac{\Delta[\ce{O2}]}{\Delta t}$
>
> When you report a rate, say what it is a rate **of**.

**3.** For $\ce{A + B -> products}$, initial
rates were measured at 25 °C:

| Trial | $[\ce{A}]_0$ (mol/L) | $[\ce{B}]_0$ (mol/L) | Initial rate (mol/(L·s)) |
| --- | --- | --- | --- |
| 1 | 0.100 | 0.100 | $2.00 \times 10^{-3}$ |
| 2 | 0.200 | 0.100 | $8.00 \times 10^{-3}$ |
| 3 | 0.100 | 0.200 | $4.00 \times 10^{-3}$ |

Determine the rate law, the overall order, and the value of $k$ with its
units.

> [!success]- Answer 3
> **Order in A.** Compare trials 1 and 2, which differ only in
> $[\ce{A}]$. It doubled; the rate went from
> $2.00 \times 10^{-3}$ to $8.00 \times 10^{-3}$, a factor of **4**.
>
> $2^m = 4$, so $m = 2$. **Second order in A.**
>
> **Order in B.** Compare trials 1 and 3, which differ only in
> $[\ce{B}]$. It doubled; the rate doubled, a factor of **2**.
>
> $2^n = 2$, so $n = 1$. **First order in B.**
>
> $$\text{rate} = k[\ce{A}]^2[\ce{B}]$$
>
> **Overall order** $= 2 + 1 = 3$.
>
> **Finding $k$**, using trial 1 — and you should then check it against
> the other two, because a $k$ that only fits one row is not a rate
> constant:
>
> $k = \frac{\text{rate}}{[\ce{A}]^2[\ce{B}]} = \frac{2.00 \times 10^{-3}}{(0.100)^2(0.100)} = \frac{2.00 \times 10^{-3}}{1.00 \times 10^{-3}} = 2.00$
>
> **The units, derived rather than recalled:**
>
> $\frac{\text{mol/(L}\cdot\text{s)}}{(\text{mol/L})^2(\text{mol/L})} = \frac{\text{mol/(L}\cdot\text{s)}}{\text{mol}^3/\text{L}^3} = \frac{\text{L}^2}{\text{mol}^2 \cdot \text{s}}$
>
> **$k = 2.00\ \text{L}^2\text{mol}^{-2}\text{s}^{-1}$ at 25 °C.**
>
> Two things that must always be attached to a rate constant. The
> **units**, because they encode the overall order and a bare "2.00" is
> meaningless. And the **temperature**, because $k$ changes with
> temperature — that is the whole mechanism by which heating speeds a
> reaction up.
>
> **Why this design works.** Each pair of trials changes exactly one
> concentration and holds the other fixed, so each comparison isolates
> one exponent. It is the same controlled-variable logic as
> [[Factors That Change a Rate]], applied to a table instead of a bench.

**4.** Using the rate law from question 3, predict the initial rate when
$[\ce{A}]_0 = 0.150$ mol/L and $[\ce{B}]_0 = 0.250$ mol/L.

> [!success]- Answer 4
> $\begin{aligned} \text{rate} &= k[\ce{A}]^2[\ce{B}] = (2.00)(0.150)^2(0.250) \\ &= (2.00)(0.0225)(0.250) \\ &= 1.125 \times 10^{-2}\ \text{mol/(L}\cdot\text{s)} \end{aligned}$
>
> **$1.13 \times 10^{-2}$ mol/(L·s)**, to three significant figures.
>
> **Check the size before you accept it.** Against trial 1, $[\ce{A}]$
> is 1.5 times larger, which multiplies the rate by $1.5^2 = 2.25$, and
> $[\ce{B}]$ is 2.5 times larger, which multiplies it by 2.5.
> Together: $2.25 \times 2.5 = 5.625$, and
> $(2.00 \times 10^{-3})(5.625) = 1.125 \times 10^{-2}$. Same answer by
> a different route, which is what a check should be.
>
> **The units survived because you carried them.** Substituting numbers
> without units into a rate law is how people end up quoting a rate in
> mol/L, and a rate that is not per unit time is not a rate.

**5.** This mechanism is proposed for
$\ce{NO2(g) + CO(g) -> NO(g) + CO2(g)}$:

$\text{Step 1 (slow)}\quad \ce{NO2(g) + NO2(g) -> NO3(g) + NO(g)}$

$\text{Step 2 (fast)}\quad \ce{NO3(g) + CO(g) -> NO2(g) + CO2(g)}$

Show that the steps add to the overall equation, identify any
intermediate, and predict the rate law. What would it mean for this
mechanism if the measured rate law turned out to be
$\text{rate} = k[\ce{NO2}][\ce{CO}]$?

> [!success]- Answer 5
> **Adding the steps:**
>
> $\ce{2NO2 + NO3 + CO -> NO3 + NO + NO2 + CO2}$
>
> $\ce{NO3}$ appears once on each side and cancels. One
> $\ce{NO2}$ appears on each side and cancels, leaving one on the
> left:
>
> $$\ce{NO2(g) + CO(g) -> NO(g) + CO2(g)}$$
>
> which is the overall equation, so the mechanism is at least
> **consistent** with it.
>
> **The intermediate is $\ce{NO3}$** — produced in one step and
> consumed in a later one, so it never appears in the overall equation
> and would not be found in the bottle at the start or at the end. That
> is what makes intermediates hard to detect and mechanisms hard to
> prove.
>
> **The predicted rate law.** The slowest step controls the overall
> rate, in the same way that the narrowest doorway controls how fast a
> crowd leaves a room. Step 1 is elementary — it is written as an actual
> collision — so for **this step alone** the coefficients are the
> exponents:
>
> $$\text{rate} = k[\ce{NO2}]^2$$
>
> **Carbon monoxide does not appear**, even though it is a reactant in
> the overall equation. It is consumed in a fast step that happens
> after the bottleneck, so how much of it is present makes no
> difference to how quickly the crowd gets through the door. Doubling
> $[\ce{CO}]$ would not change the rate at all.
>
> **If the measured rate law were $k[\ce{NO2}][\ce{CO}]$**, this
> mechanism would be **disproved**. A mechanism has to reproduce the
> experimental rate law, and this one predicts no dependence on
> $[\ce{CO}]$ whatsoever. You would have to propose a different
> mechanism — most simply, one in which the rate-determining step is a
> single collision between one $\ce{NO2}$ and one $\ce{CO}$.
>
> **What can and cannot be concluded, and this is the whole point of
> mechanisms.** Agreement between a proposed mechanism and a measured
> rate law does **not** prove the mechanism. Other mechanisms can
> predict the same rate law, and rate data alone cannot separate them.
> Disagreement, on the other hand, is decisive. A mechanism is a
> hypothesis that experiments can kill and cannot confirm.

**6.** Using collision theory, explain why raising the temperature
increases the rate of a reaction far more than the increase in collision
frequency alone would suggest. Then say what a catalyst does and, just
as importantly, what it does not do.

> [!success]- Answer 6
> **Collision theory** says a reaction happens when particles collide
> with at least the **activation energy** and in a suitable
> **orientation**. So the rate depends on three things: how often they
> collide, what fraction of those collisions is energetic enough, and
> what fraction is aimed properly.
>
> **Why temperature matters so much.** Raising the temperature does
> increase collision frequency, because the particles move faster — but
> that effect is modest, roughly with the square root of the absolute
> temperature. A rise from 300 K to 310 K raises average speeds by under
> two per cent.
>
> The large effect is on the **energy distribution**. At any
> temperature, molecular energies are spread over a wide range, and only
> the molecules out in the high-energy tail have enough to react.
> Warming the sample shifts and broadens that distribution, and because
> the reacting molecules are in the **tail**, a small shift can multiply
> the number of them several times over. A rule of thumb often quoted
> for reactions near room temperature is that a 10 °C rise roughly
> doubles the rate — which no two-per-cent change in speed could
> possibly produce.
>
> **What a catalyst does:** provides an alternative route with a
> **lower activation energy**. A larger fraction of collisions now
> clears the barrier, so the rate rises, at the same temperature and
> without any energy being added.
>
> **What a catalyst does not do**, and every item here has been an exam
> question:
>
> | Claim | True? | Why |
> | --- | --- | --- |
> | Changes $\Delta H$ | **No** | It changes the route, and $\Delta H$ depends only on the two ends |
> | Is consumed | **No** | It is regenerated; it appears in a step and reappears in a later one |
> | Changes the equilibrium position | **No** | It speeds the forward and reverse reactions equally |
> | Increases the yield | **No** | It gets you to the same finish sooner |
> | Lowers the activation energy | **Yes** | That is its whole definition |
>
> **Where collision theory stops being true.** It treats molecules as
> hard spheres with an energy and a direction, which is enough to
> explain concentration, temperature, surface area, and catalysts —
> everything you measured in [[Factors That Change a Rate]]. It does not
> explain why the orientation requirement is severe for some reactions
> and mild for others, it says nothing about what happens during the
> collision, and it does not predict activation energies. A model that
> covers four factors and admits it cannot do the fifth thing is worth
> having; a model whose limits you cannot state is not.

**7.** Four claims from a study group. Correct each.
*(a) "The equation is $\ce{2NO + O2 -> 2NO2}$,
so the rate law is $k[\ce{NO}]^2[\ce{O2}]$."*
*(b) "Increasing the concentration speeds a reaction up because the
particles have more energy."*
*(c) "The catalyst made the reaction faster, so we got more product."*
*(d) "$k$ is a constant, so it is the same for a reaction whatever the
conditions."*

> [!success]- Answer 7
> **(a) Coefficients are not exponents unless the step is elementary.**
> The rate law might turn out to be $k[\ce{NO}]^2[\ce{O2}]$, and
> the only way to find out is to measure initial rates while varying one
> concentration at a time. Writing it down from the equation is a guess
> dressed as a derivation.
>
> Look at question 5 for the counterexample living in the same family of
> chemistry: the overall equation contains $\ce{CO}$ and the rate law
> does not contain it at all. No amount of staring at a balanced
> equation would have revealed that.
>
> **(b) Right conclusion, wrong mechanism, and the mechanism is what is
> being marked.** Raising the concentration does not give any particle
> more energy. The energy distribution is set by the **temperature**
> and nothing else. What a higher concentration does is pack more
> particles into the same volume, so collisions happen **more often** —
> the same fraction of them clears the activation barrier, but there are
> more of them per second.
>
> Keep the two levers separate: **concentration and surface area change
> how often; temperature and catalysts change what fraction succeeds.**
> Nearly every conceptual question in this unit is testing whether you
> have those in the right columns.
>
> **(c) Faster is not further, and this is the misconception of the
> unit.** A catalyst lowers the barrier; it does not move the finish
> line. The amount of product is fixed by how much limiting reactant you
> started with — and, once you reach Unit 4, by where the equilibrium
> lies. Neither of those is touched by a catalyst.
>
> The reason a catalyst cannot shift an equilibrium is worth carrying
> forward: it lowers the barrier for the **forward and reverse
> reactions by the same amount**, because both directions cross the same
> hump. Both rates rise, they still become equal at the same place, and
> the system arrives at the same destination sooner.
>
> In industry this is enormously valuable anyway — arriving in an hour
> instead of a week, at a lower temperature, is the difference between a
> viable process and a laboratory curiosity. The benefit is real; it is
> just not the benefit the student named.
>
> **(d) $k$ is constant with respect to *concentration*, and with
> respect to nothing else.** It does not change when you use more
> reactant — which is exactly what makes the rate law useful, because
> the concentration dependence is captured by the exponents instead.
>
> It **does** change with temperature, and steeply. It **does** change
> when a catalyst is added, because the catalyst has created a different
> route with a different barrier. So a rate constant must always be
> quoted with its temperature and its conditions, in the same way that
> an equilibrium constant must — a bare number with no conditions is not
> a physical quantity.

Reference: [[Rates of Reaction]] and
[[Collision Theory and Catalysts]]. Measuring these effects yourself:
[[Factors That Change a Rate]], and the task built on it,
[[The Rate Investigation]].

%%curriculum-start%%
## Curriculum connection

![[D3.7]]

![[D3.5]]
%%curriculum-end%%
