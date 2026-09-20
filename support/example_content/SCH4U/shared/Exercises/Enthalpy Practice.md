---
title: Enthalpy Practice
publish: true
created: __CREATED__
enableToc: false
tags:
  - chemistry
  - exercises
---
One relationship does most of the work on this page:

$$Q = mc\Delta T$$

and one sign convention decides whether your answer is right or exactly
backwards.

**$Q$ describes the surroundings. $\Delta H$ describes the system.** If
the water got hotter, $Q$ is positive and the reaction released energy,
so $\Delta H$ is negative. The sign flips exactly once, at the moment
you stop talking about the water and start talking about the reaction.
Write that flip down as a separate line in your working every time and
you will stop losing marks to it.

Take $c = 4.18\ \text{J/(g}\cdot^\circ\text{C)}$ for water and for
dilute aqueous solutions, and check the booklet for anything else.

> [!warning] Where your significant figures go to die
> Every calorimetry question on this page gives temperatures to three or
> four figures and then asks you to subtract them. A subtraction of two
> similar numbers keeps the **decimal places** and destroys the
> **significant figures**: $21.6 - 15.2 = 6.4$ starts with three figures
> each and ends with two.
>
> That subtraction is almost always the bottleneck in the whole
> calculation, and quoting a final answer to four figures because the
> molar mass had four is the most common error in this unit.

**1.** How much heat is absorbed when 150.0 g of water is warmed from
21.5 °C to 32.7 °C?

> [!success]- Answer 1
> $\Delta T = 32.7 - 21.5 = 11.2\ ^\circ\text{C}$
>
> $Q = mc\Delta T = (150.0\ \text{g})(4.18\ \text{J/(g}\cdot^\circ\text{C)})(11.2\ ^\circ\text{C}) = 7022\ \text{J}$
>
> **$7.02 \times 10^3$ J, which is 7.02 kJ.**
>
> Three significant figures. $\Delta T$ came out as 11.2, which has
> three, and that matches the mass and the specific heat capacity, so
> nothing here is the bottleneck.
>
> Check the units by cancelling them rather than by trusting the
> formula: grams times joules per gram per degree times degrees leaves
> joules. If your units do not cancel to joules, the arithmetic is
> wrong and the units have told you before the answer did.

**2.** 8.00 g of ammonium nitrate is dissolved in 100.0 g of water in a
polystyrene cup. The temperature falls from 21.6 °C to 15.2 °C.
Calculate the molar enthalpy of solution and write the thermochemical
equation.

> [!success]- Answer 2
> $\Delta T = 15.2 - 21.6 = -6.4\ ^\circ\text{C}$ — the solution got
> **colder**, so it lost energy.
>
> **The mass is the mass of the whole solution**, not just the water.
> The dissolved ammonium nitrate is part of what cooled down:
> $m = 100.0 + 8.00 = 108.0\ \text{g}$
>
> $Q = mc\Delta T = (108.0\ \text{g})(4.18\ \text{J/(g}\cdot^\circ\text{C)})(6.4\ ^\circ\text{C}) = 2889\ \text{J} = 2.889\ \text{kJ}$
>
> The solution **lost** 2.889 kJ, so the dissolving process **absorbed**
> it. This is the sign flip, and here it makes $\Delta H$ positive.
>
> Molar mass of $\ce{NH4NO3}$:
> $2(14.01) + 4(1.01) + 3(16.00) = 80.06\ \text{g/mol}$
>
> $n = \frac{8.00\ \text{g}}{80.06\ \text{g/mol}} = 0.09993\ \text{mol}$
>
> $\Delta H = \frac{+2.889\ \text{kJ}}{0.09993\ \text{mol}} = +28.9\ \text{kJ/mol}$
>
> **$\Delta H = +29\ \text{kJ/mol}$**, to two significant figures,
> because $\Delta T = 6.4\ ^\circ$C had two.
>
> $$\ce{NH4NO3(s) -> NH4+(aq) + NO3-(aq)} \qquad \Delta H = +29\ \text{kJ/mol}$$
>
> **Sanity check on the sign, which takes two seconds.** The cup got
> colder. Energy went *into* the dissolving process to make that happen.
> Into the system means positive. An endothermic process that cools its
> surroundings is exactly how an instant cold pack works, and if your
> answer came out negative you have skipped the flip rather than made an
> arithmetic error.
>
> Compare your value with the booklet's. If yours is smaller in
> magnitude, ask what the cup absorbed that you did not count.

**3.** In a demonstration, 0.500 g of ethanol is burned under a metal
can holding 200.0 g of water. The water warms from 20.1 °C to 33.4 °C.
Calculate the molar enthalpy of combustion, and say how it will compare
with the value in the data booklet and why.

> [!success]- Answer 3
> *This is a demonstration and not a student procedure — an open flame,
> a hot metal surface, and a flammable liquid within centimetres of each
> other is not a combination for twelve benches at once.*
>
> $\Delta T = 33.4 - 20.1 = 13.3\ ^\circ\text{C}$
>
> $Q = mc\Delta T = (200.0\ \text{g})(4.18\ \text{J/(g}\cdot^\circ\text{C)})(13.3\ ^\circ\text{C}) = 11119\ \text{J} = 11.12\ \text{kJ}$
>
> Molar mass of ethanol, $\ce{C2H5OH}$:
> $2(12.01) + 6(1.01) + 16.00 = 46.08\ \text{g/mol}$
>
> $n = \frac{0.500\ \text{g}}{46.08\ \text{g/mol}} = 0.010851\ \text{mol}$
>
> $\Delta H = -\frac{11.12\ \text{kJ}}{0.010851\ \text{mol}} = -1025\ \text{kJ/mol}$
>
> **$\Delta H = -1.02 \times 10^{3}\ \text{kJ/mol}$**, three significant
> figures.
>
> **How it compares, and why.** Your result will be substantially
> **less negative** than the booklet's value — commonly by a quarter or
> more. Every one of the reasons pushes the same way:
>
> - Most of the flame's energy warms the **air** around the can rather
>   than the water in it.
> - The **can itself** warms up, and that energy never entered the water
>   you counted.
> - Some ethanol **evaporates** without burning, so the mass that
>   disappeared is larger than the mass that reacted — which makes $n$
>   too large and $|\Delta H|$ too small.
> - Incomplete combustion produces soot, and a carbon atom that ends up
>   as soot has released less energy than one that reached carbon
>   dioxide.
>
> There is no mechanism here that pushes the other way. **A simple can
> calorimeter systematically underestimates the magnitude of every heat
> of combustion**, which is why bomb calorimeters exist and why the
> booklet's numbers were not measured this way.

**4.** A reaction releases 45.0 kJ when 0.250 mol of the reactant is
consumed. Write the thermochemical equation in both accepted forms, for
a reaction $\ce{A -> B}$. Then say how much energy is
released when 1.75 mol reacts.

> [!success]- Answer 4
> Per mole:
> $\frac{45.0\ \text{kJ}}{0.250\ \text{mol}} = 180.\ \text{kJ/mol}$,
> released, so $\Delta H$ is negative.
>
> **Form 1 — energy as a separate $\Delta H$ term:**
>
> $$\ce{A -> B} \qquad \Delta H = -180.\ \text{kJ/mol}$$
>
> **Form 2 — energy written into the equation as a product:**
>
> $$\ce{A -> B} + 180.\ \text{kJ}$$
>
> Both say the same thing. In the second form an exothermic reaction
> puts the energy on the **product** side, because energy comes out
> alongside the products; an endothermic reaction puts it on the
> reactant side, because energy has to be supplied along with the
> reactants. If you can never remember which, derive it in three
> seconds from that sentence rather than memorising it.
>
> **For 1.75 mol:**
> $(1.75\ \text{mol})(180.\ \text{kJ/mol}) = 315\ \text{kJ}$ released.
>
> Written as "180." with a decimal point on purpose: that says three
> significant figures rather than two, matching the data.
>
> **The scaling is the part worth noticing.** Enthalpy is
> **extensive** — twice as much reaction releases twice as much energy —
> which is why $\Delta H$ is always quoted *per mole of reaction as
> written*, and why changing the coefficients in an equation changes the
> number beside it. That property is what makes the next page possible.

**5.** A 55.0 g piece of metal is heated to 98.0 °C and dropped into
100.0 g of water at 20.0 °C in an insulated cup. The final temperature
of both is 23.6 °C. Find the specific heat capacity of the metal.

> [!success]- Answer 5
> The assumption doing all the work: **the energy the water gained is
> the energy the metal lost.** That is only true if the cup is perfectly
> insulating, which it is not, and the question says to assume it.
>
> Energy gained by the water:
>
> $Q = (100.0\ \text{g})(4.18\ \text{J/(g}\cdot^\circ\text{C)})(23.6 - 20.0) = (100.0)(4.18)(3.6) = 1505\ \text{J}$
>
> The metal fell from 98.0 °C to 23.6 °C, a change of 74.4 °C:
>
> $c = \frac{Q}{m\Delta T} = \frac{1505\ \text{J}}{(55.0\ \text{g})(74.4\ ^\circ\text{C})} = 0.368\ \text{J/(g}\cdot^\circ\text{C)}$
>
> **0.37 J/(g·°C)**, to two significant figures — the water's
> temperature change was 3.6 °C, which has two, and everything else is
> better than that.
>
> **Two things worth taking from this.** The metal's specific heat
> capacity is roughly a tenth of water's, which is why a metal spoon in
> hot soup burns your mouth and the soup does not: the same energy per
> gram raises the metal's temperature about eleven times as far. And
> water's unusually large value is the reason it is used as the
> measuring fluid in every calorimeter on this page — a large $c$ means
> the temperature rise stays small and manageable for a large amount of
> energy.
>
> Compare with the booklet. A value near 0.37 J/(g·°C) is consistent
> with several metals, and this measurement alone cannot tell you which.

**6.** Explain, using the terms *enthalpy*, *activation energy*,
*exothermic*, and *potential energy*, why the combustion of a hydrocarbon
can be strongly exothermic and still not happen at all in a room full of
air.

> [!success]- Answer 6
> **Enthalpy** is the energy stored in the chemical bonds and
> arrangement of a substance. A reaction's $\Delta H$ compares the
> **potential energy** of the products with that of the reactants. When
> the products sit lower, energy is released to the surroundings and the
> reaction is **exothermic**, so $\Delta H$ is negative.
>
> Combustion of a hydrocarbon is strongly exothermic: the products are a
> long way downhill from the reactants.
>
> **But every reaction has to go uphill before it can go downhill.** The
> existing bonds must be stretched and broken before new ones form, and
> the height of that hump is the **activation energy**. A mixture of
> petrol vapour and air at room temperature has almost no molecules
> colliding hard enough to get over it, so the reaction proceeds at a
> rate indistinguishable from zero — and the mixture sits there, stable,
> for years.
>
> **The two quantities answer two different questions and neither
> answers the other:**
>
> | Quantity | Question it answers | What it says about the other |
> | --- | --- | --- |
> | $\Delta H$ | How far downhill? Which way is energetically favoured? | Nothing about speed |
> | Activation energy | How high is the barrier? How fast at this temperature? | Nothing about direction |
>
> This is why a match matters. The match does not supply the energy of
> combustion — that comes from the fuel, and it is enormously more than
> the match provides. The match supplies the **activation energy** for
> the first few molecules, whose released energy then pushes their
> neighbours over the barrier, and so on.
>
> **Downhill is not the same as fast.** Diamond converting to graphite
> is downhill and takes geological time. This distinction is the whole
> reason Unit 3 has two halves, and half the difficult questions in this
> course are difficult only because somebody blurred it.

**7.** Four claims from a study group. Correct each.
*(a) "The temperature went down, so the reaction was exothermic — it
gave its heat away."*
*(b) "$\Delta H = +29\ \text{kJ/mol}$, so this reaction absorbs 29 kJ."*
*(c) "We only used the mass of the water, because the specific heat
capacity we used was water's."*
*(d) "Our value came out below the booklet's, so we made a mistake
somewhere."*

> [!success]- Answer 7
> **(a) Backwards, and it is the most common error in the unit.** A
> falling temperature means the surroundings **lost** energy. That
> energy went into the chemical system, so the process **absorbed**
> energy and is **endothermic**, with a positive $\Delta H$.
>
> The phrase "gave its heat away" is the source of the confusion: the
> *solution* gave energy away, to the *reaction*. Fix it by naming which
> thing you are talking about in every sentence. "The solution cooled"
> and "the reaction absorbed energy" are the same event described from
> the two sides, and $\Delta H$ always describes the system's side.
>
> **(b) Missing three words: "per mole of reaction as written".** The
> units are kJ **per mole**, so 29 kJ is absorbed for every mole that
> reacts, not once. Dissolve 0.100 mol and about 2.9 kJ is absorbed;
> dissolve 5.00 mol and about 145 kJ is.
>
> This is the same extensive property as in question 4 and it is why the
> equation the value belongs to must always be quoted with it. A
> $\Delta H$ with no equation attached is not a usable number.
>
> **(c) A real error with a known direction.** The dissolved solute is
> part of the solution and it cooled down along with the water, so its
> mass belongs in $m$. Using 100.0 g instead of 108.0 g makes $Q$ too
> small by about 7%, and $|\Delta H|$ too small by the same 7%.
>
> The student's stated reason is worth addressing separately, because it
> is half right: using water's $c$ for a salt solution **is** an
> approximation, and a 1 mol/L solution's specific heat capacity is a
> little below water's. The correct response to that is to state it as
> an assumption, not to compensate for it by leaving mass out. Two
> approximations that happen to point opposite ways do not add up to a
> measurement.
>
> **(d) Not a mistake — an expected bias, and you should say so.** Every
> heat-loss mechanism in a school calorimeter pushes the same way. The
> cup, the lid, the thermometer, and the air all absorb energy you never
> counted, so the measured $\Delta T$ is low, so $|\Delta H|$ is low.
>
> A **mistake** is something you did wrong that a careful repeat would
> fix — a misread balance, a spilled portion. A **limitation** is
> something about the method that survives doing everything perfectly,
> and it belongs in the analysis with its direction named. "Our value is
> 18% below the booklet's, in the direction that heat loss to the
> calorimeter predicts" is a strong sentence. "We made a mistake
> somewhere" is not a sentence about chemistry at all.

Reference: [[Enthalpy]] and [[Calorimetry]]. The measurement behind all
of this: [[Calorimetry of a Neutralisation]]. Adding reactions together
rather than measuring them: [[Hess's Law]] and
[[Hess's Law Practice]]. On how many figures your data has earned you:
[[Significant Figures and Units]].

%%curriculum-start%%
## Curriculum connection

![[D2.1]]

![[D2.2]]

![[D2.3]]

![[D2.4]]
%%curriculum-end%%
