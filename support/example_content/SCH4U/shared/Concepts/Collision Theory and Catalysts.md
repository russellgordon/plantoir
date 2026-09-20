---
title: Collision Theory and Catalysts
publish: true
created: __CREATED__
enableToc: true
tags:
  - concepts
  - kinetics
---
[[Factors That Change a Rate]] produced five reliable results and no
reasons. [[Rates of Reaction]] made the results quantitative and still
offered no reasons. This page supplies the model, and it is a
deliberately crude one: treat the particles as objects that have to run
into each other, and see how far that gets you.

It gets you remarkably far, and then it stops. Both halves matter.

## Two conditions, and most collisions fail

**Collision theory** says a reaction between particles requires them to
collide, and that a collision leads to reaction only if two conditions
are met at once.

**Enough energy.** The colliding pair must bring at least a minimum
amount of kinetic energy, called the **activation energy** $E_a$. Below
that threshold they simply bounce apart unchanged. The energy is needed
because old bonds have to start breaking before new ones finish forming,
and breaking bonds costs — as [[Enthalpy]] insisted.

**The right orientation.** Even an energetic collision does nothing if
the reacting parts of the two molecules are not pointing at each other.
For two spheres this hardly matters. For a large molecule with one small
reactive site, most approaches are hopeless.

The consequence is worth stating plainly: in a typical reaction mixture,
==the overwhelming majority of collisions produce nothing at all.== Not
a slim majority — a vast one. Rate is not set by how often particles
meet. It is set by how often they meet *successfully*, and that is a
tiny fraction of a very large number.

## Reading a potential energy diagram

Put reaction progress on the horizontal axis and potential energy on the
vertical. The reactants sit at one level, the products at another, and
between them the curve rises to a peak and comes back down.

The peak is the **activated complex**, sometimes called the transition
state: the fleeting arrangement in which old bonds are partly broken and
new bonds are partly formed. It is not an intermediate and cannot be
bottled. It exists for the duration of a collision.

Three quantities are read off that one diagram:

| Quantity | Read as | What it tells you |
| --- | --- | --- |
| $E_a$ forward | peak minus the reactant level | how hard it is to get the reaction started |
| $E_a$ reverse | peak minus the product level | how hard the reverse reaction is |
| $\Delta H$ | product level minus reactant level | the net energy change, and its sign |

Which gives a relationship worth checking on any diagram you are handed:

$$\Delta H = E_{a,\text{forward}} - E_{a,\text{reverse}}$$

For an **exothermic** reaction the products sit below the reactants, so
the reverse activation energy is the larger of the two. For an
**endothermic** one it is the other way round. Draw both, once, and you
will not have to memorise which is which.

## Every factor, from the same two conditions

| Factor increased | Effect on rate | Why, in terms of collisions |
| --- | --- | --- |
| Concentration of a solution | faster | more particles per litre, so more collisions per second |
| Pressure of a gas | faster | same thing — the particles are crowded closer |
| Surface area of a solid | faster | only surface particles can be collided with; powder exposes far more |
| Temperature | much faster | see below — this one is not what most people think |
| Nature of the reactants | varies | how many bonds must break, and how strong they are |
| A catalyst | faster | a different route, with a lower $E_a$ |

**Temperature deserves its own paragraph**, because the obvious
explanation is the minor one. Yes, hotter particles move faster and
collide more often. That effect is real and it is small. The large
effect is on the **fraction of collisions that clear $E_a$**.

At any temperature, molecules do not all have the same energy; there is
a broad spread, with most near the middle and a thin tail at high
energy. Only the collisions in that tail are energetic enough to react.
Raise the temperature and the whole spread shifts right — but the tail
beyond a fixed threshold grows out of all proportion to the shift,
because it is being counted from the steep part of the curve. A modest
temperature rise can multiply the reacting fraction several times over
while barely changing how often particles meet.

That is why a fridge works. Cooling food does not stop the chemistry; it
moves most of the molecules out of the tail.

## Catalysts, and the three things they do not do

A **catalyst** increases the rate of a reaction and is not consumed
overall. It works by providing an **alternative mechanism** with a lower
activation energy — a different route over a lower pass. It does not
push particles over the original barrier.

A catalyst may be consumed in an early step of that mechanism and
regenerated in a later one, which is how it can be genuinely involved
and still be recoverable at the end. **Homogeneous** catalysts are in
the same phase as the reactants; **heterogeneous** catalysts are not,
and work at their surface — which is why they are made porous, to
maximise the area from the table above. Enzymes are the biological case,
and their specificity comes from an active site shaped to hold one
substrate in exactly the orientation the second condition demands.

Now the three things a catalyst does **not** do, all of which follow
from lowering a barrier rather than moving the levels either side of it.

1. **It does not change $\Delta H$.** The reactants and products are at
   the same energies they always were. Only the peak between them moved.
2. **It does not change the position of equilibrium.** It lowers the
   forward and reverse activation energies by the *same* amount, so both
   directions speed up equally, and the system arrives at the same place
   sooner. There is more on this in
   [[Le Chatelier's Principle|Le Châtelier's Principle]].
3. **It does not make an unfavourable reaction happen.** A catalyst can
   only accelerate a reaction that was going to happen anyway.

> [!failure] Downhill does not mean fast
> A large negative $\Delta H$ says **nothing whatsoever** about rate.
> These are two separate questions with two separate answers, and this
> is the most important sentence in Unit 3.
>
> Diamond converting to graphite releases energy. It is not happening to
> any diamond you have ever seen, because the activation energy is
> enormous. A pile of dry firewood in air is thermodynamically poised to
> burn and will sit there for a century until something supplies the
> $E_a$. A mixture of hydrogen and oxygen is stable indefinitely and
> then, given a spark, is not.
>
> Thermodynamics tells you where a system would end up. Kinetics tells
> you whether it will get there this century. A reaction can be
> strongly favoured and immeasurably slow, and that combination is
> ordinary rather than exotic.

> [!question] Where does collision theory stop being true?
> It treats molecules as hard spheres that either hit or miss, and that
> picture is best for simple gas-phase reactions. For large molecules,
> the orientation requirement has to be patched in as a correction
> factor rather than predicted. For reactions in solution the picture is
> worse still, because a solvent surrounds each particle and a pair that
> has met stays together for many attempts rather than one.
>
> The model is a good account of *why* the factors do what they do, and
> a poor tool for calculating a rate from first principles. That is a
> perfectly respectable thing for a model to be, as long as you say so.

Take this into [[The Rate Investigation]], where you will change one
factor deliberately and be asked to explain the result in exactly these
terms. Then Unit 4 asks the question kinetics cannot: not how fast, and
not how far downhill, but **how far** — starting in
[[Dynamic Equilibrium]].

%%curriculum-start%%
## Curriculum connection

![[D3.5]]

![[D3.6]]
%%curriculum-end%%
