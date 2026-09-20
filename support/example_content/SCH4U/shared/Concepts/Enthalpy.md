---
title: Enthalpy
publish: true
created: __CREATED__
enableToc: true
tags:
  - concepts
  - energy
---
In [[Calorimetry of a Neutralisation]] you mixed two clear solutions and
the thermometer climbed. Nothing was heated. No burner was lit. The
energy that warmed that liquid came out of the chemistry, and this unit
begins with the obvious follow-up question: **where was it before?**

Grade 11 treated energy as something a reaction sometimes happened to
give off. This year it is the thing that decides which way a reaction
goes at all.

## The thermometer is measuring the surroundings

Split the world in two. The **system** is the reaction — the particles
whose bonds are changing. The **surroundings** are everything else: the
water, the beaker, the air, the thermometer bulb.

Your thermometer has never once measured the system. It measures the
surroundings, and infers.

**Enthalpy**, $H$, is the heat content of a system at constant pressure.
You cannot measure the enthalpy of anything, and it does not matter,
because chemistry only ever needs the **change**:

$$\Delta H = H_\text{products} - H_\text{reactants}$$

- If the products hold **less** enthalpy than the reactants, the
  difference has gone into the surroundings. The surroundings warm up,
  the thermometer rises, and $\Delta H$ is **negative**. The reaction is
  **exothermic**.
- If the products hold **more**, the difference had to come from the
  surroundings. The surroundings cool, the thermometer falls, and
  $\Delta H$ is **positive**. The reaction is **endothermic**.

> [!important] The sign is written from the system's point of view
> A rising thermometer means a **negative** $\Delta H$. That inversion
> is the single most common error in this unit, and it is not a
> convention you can shrug at — it is the difference between a reaction
> that releases energy and one that consumes it.
>
> Say the sentence in full every time: *the surroundings gained heat, so
> the system lost it, so $\Delta H$ is negative.* Three clauses, and the
> sign falls out of the third.

## Bond breaking costs, bond forming pays

Here is the mechanism, and it is short.

**Breaking a bond always absorbs energy.** Always. A bond is an
attraction; pulling two attracted things apart takes work, every time,
with no exceptions.

**Forming a bond always releases energy.** Also always, for the same
reason read backwards.

A reaction does both. Reactant bonds break and product bonds form, and
$\Delta H$ is the **net balance**:

$$\Delta H \approx (\text{energy in, to break bonds}) - (\text{energy out, from forming bonds})$$

If the new bonds are stronger than the old ones, more comes out than
went in, and the reaction is exothermic. If they are weaker, it is
endothermic. That is all "exothermic" means at the level of the
particles.

> [!warning] Energy is not stored in bonds and released by breaking them
> This phrase appears in newspapers, in biology textbooks, and
> occasionally in chemistry ones, and it is backwards. Breaking a bond
> **costs** energy. Nothing is released by breaking anything.
>
> Burning methane is exothermic not because the C–H bonds "contained"
> energy, but because the $\ce{C=O}$ and $\ce{O-H}$ bonds in the
> products are stronger than the bonds that were broken to make them. If
> you find yourself explaining an exothermic reaction by saying bonds
> broke, stop and count both sides.

## Writing it down

A **thermochemical equation** is a balanced equation with its energy
change attached. There are two accepted forms and you should be able to
convert between them.

With $\Delta H$ written beside the equation:

$$\ce{CH4(g) + 2O2(g) -> CO2(g) + 2H2O(l)} \qquad \Delta H = -890 \text{ kJ}$$

Or with the energy as a term in the equation itself, on the side it
comes out of:

$$\ce{CH4(g) + 2O2(g) -> CO2(g) + 2H2O(l)} + 890 \text{ kJ}$$

Both say the same thing. Note that the sign disappears in the second
form, because the *position* of the term is carrying the information —
an endothermic reaction would have the energy term on the left.

Three rules govern the number:

| If you do this to the equation | Do this to $\Delta H$ |
| --- | --- |
| Multiply all coefficients by $n$ | multiply $\Delta H$ by $n$ |
| Reverse the equation | change the sign of $\Delta H$ |
| Change a state symbol | look up a different value — it is a different reaction |

That last row is not a technicality. Producing water as a liquid and
producing it as a vapour release measurably different amounts of energy,
because condensing the vapour releases more. A thermochemical equation
without state symbols is incomplete.

Two related quantities get confused, so separate them now. The
**enthalpy of reaction** is the change for the equation as written, in
kilojoules. A **molar enthalpy** is the change per mole of one named
substance, in kilojoules per mole — of combustion, of neutralisation, of
solution. The **enthalpy of formation** is a special molar enthalpy:
forming exactly one mole of a compound from its elements in their
standard states. [[Hess's Law]] is where that specialisation earns its
keep.

## Physical, chemical, nuclear

Energy changes accompany all three kinds of change, and they are not the
same size.

| Kind of change | What is rearranged | Rough scale, per mole |
| --- | --- | --- |
| Physical — melting, boiling, dissolving | attractions *between* particles | small |
| Chemical — burning, neutralising, rusting | bonds *within* particles | tens to hundreds of kilojoules |
| Nuclear — fission, fusion | the nucleus itself | around a million times larger again |

The middle row is the whole of this unit. The first row is why boiling a
kettle takes real energy without changing what is in it — the
$\ce{O-H}$ bonds survive, and only the hydrogen bonding between
molecules is overcome. The third is why a nuclear plant and a coal plant
of the same output consume such wildly different masses of fuel.

Note that every row can go either way. Melting absorbs and freezing
releases. Burning releases and photosynthesis absorbs. Fission and
fusion both release. "Endothermic" is not a property of a kind of
change; it is a property of a particular change in a particular
direction.

Next comes the measurement that produced the number in the first place —
[[Calorimetry]] — and then the trick that lets you find $\Delta H$ for
reactions nobody can measure, in [[Hess's Law]]. Practise the signs and
the scaling rules in [[Enthalpy Practice]] before either.

%%curriculum-start%%
## Curriculum connection

![[D2.1]]

![[D2.2]]

![[D3.1]]

![[D3.2]]
%%curriculum-end%%
