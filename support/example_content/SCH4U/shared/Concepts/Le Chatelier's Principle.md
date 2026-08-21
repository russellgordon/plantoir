---
title: Le Châtelier's Principle
aliases:
  - "Le Châtelier's Principle"
publish: true
created: __CREATED__
enableToc: true
tags:
  - concepts
  - equilibrium
---
In [[Disturbing an Equilibrium]] you took systems that had settled and
poked them. You added a reactant to one, chilled another, squeezed a
third. Every time, the colour moved — and then stopped moving, at a new
place, and stayed there.

[[Dynamic Equilibrium]] explained why a system settles at all. This page
explains what happens when you refuse to leave it alone.

## The principle, and the word that carries it

> When a system at equilibrium is disturbed, it shifts in the direction
> that **partially** counteracts the disturbance, and reaches a new
> equilibrium.

*Partially* is doing all the work in that sentence. A system that could
fully counteract a disturbance would return to exactly where it started,
and none of your observations did that. Add reactant and the system
consumes some of it — not all. The new equilibrium always has more of
the added substance than the old one did, just less than you put in.

Notice also what the principle does not claim. It does not say the
system "wants" anything, or "tries" to restore itself. Molecules have no
preferences. The shift happens because the rates of the forward and
reverse reactions are no longer equal, and it stops when they are equal
again.

## What each disturbance does

| Disturbance | The system shifts | New value of $K$? |
| --- | --- | --- |
| Add a reactant | towards the products | unchanged |
| Remove a product | towards the products | unchanged |
| Add a product | towards the reactants | unchanged |
| Decrease the volume of a gaseous system | towards the side with **fewer moles of gas** | unchanged |
| Increase the volume | towards the side with more moles of gas | unchanged |
| Heat an exothermic reaction | towards the reactants | **changes** |
| Heat an endothermic reaction | towards the products | **changes** |

Read the right-hand column before anything else. Concentration and
volume changes move the system to a new *position* on the same curve —
the ratio $K$ is untouched, and the system slides along until the
expression evaluates to $K$ again.

**Temperature is the only entry that changes $K$ itself**, and that is
because temperature is the only disturbance that changes the energies
involved rather than the amounts. The trick for getting the direction
right is to write the energy into the equation as though it were a
substance:

$$\ce{N2(g) + 3H2(g) <=> 2NH3(g)} + \text{energy}$$

Now heating is "adding energy", which the table already covers: add
something on the right and the system shifts left. Cooling removes it
and the system shifts right. The same trick works for an endothermic
reaction with the energy term written on the left.

**Volume changes need the mole count**, not the mass count. Squeezing
the mixture above raises every concentration at once, and the system
relieves that by moving towards the side with fewer gas particles — four
moles of gas on the left, two on the right, so it shifts right. If both
sides had the same number of moles of gas, squeezing would change
nothing at all, because both the top and the bottom of the expression
would be multiplied by the same factor.

## $Q$ against $K$ is the statement that actually decides

Le Châtelier's principle is a summary of behaviour. The **reaction
quotient** is the calculation that produces the answer, and it is the
tool to reach for when the principle feels ambiguous.

$Q$ has exactly the same form as the equilibrium constant, built from
whatever concentrations the system happens to have right now — not
necessarily equilibrium ones:

$$Q = \frac{[\ce{C}]^c[\ce{D}]^d}{[\ce{A}]^a[\ce{B}]^b}$$

| Comparison | What it means | Net direction |
| --- | --- | --- |
| $Q < K$ | too few products relative to reactants | forward, to the right |
| $Q = K$ | the system is at equilibrium | no net change |
| $Q > K$ | too many products relative to reactants | reverse, to the left |

That is not a rule of thumb; it is a comparison of two numbers. Dumping
extra reactant into a settled system makes the bottom of the fraction
larger, so $Q$ drops below $K$, so the system runs forward until the
fraction climbs back to $K$. Le Châtelier's principle predicted that
too — but $Q$ told you *why*, and it will still work in situations where
the principle is hard to apply.

> [!warning] Le Châtelier is a heuristic, not a mechanism
> It is a nineteenth-century generalisation about how systems respond,
> and it is right in every case this course will put in front of you.
> It is not, however, derived from anything, and it can be led astray.
>
> The clean example: adding an inert gas at constant *volume* changes
> nothing, as the next section explains — but adding an inert gas at
> constant *pressure* forces the container to expand, which lowers every
> partial pressure, which shifts the system towards the side with **more**
> moles of gas. A system responding to an addition by moving in the
> direction of *more* particles is not what "counteracts the
> disturbance" leads you to expect.
>
> Where the principle and the arithmetic seem to disagree, the
> arithmetic is right. Work out what happened to $Q$.

## Two disturbances that do nothing, and one compromise

**A catalyst does not shift an equilibrium.** It lowers the activation
energy of the forward and reverse reactions by the same amount, so both
rates rise together and the ratio between them at equilibrium is
untouched. The system arrives at exactly the same place, sooner. This
follows directly from [[Collision Theory and Catalysts]] and it is
examined every year.

**An inert gas added at constant volume does not shift an equilibrium.**
Pumping argon into a rigid vessel raises the total pressure, and changes
no concentration of anything in the expression. Every term in $Q$ is
unchanged, so $Q$ still equals $K$, so nothing moves. The total pressure
gauge reads higher and the chemistry does not care.

Both of those catch students who have learned "pressure up means shift"
and "catalyst means change" as slogans rather than as consequences.

The compromise is what happens when the principle meets a factory.
Making ammonia from nitrogen and hydrogen is exothermic and reduces the
number of gas molecules. Le Châtelier therefore recommends **high
pressure** and **low temperature** for the best yield.

Only one of those recommendations is followed. High pressure is used,
because it helps both the yield and the rate. Low temperature is not —
because a cold reaction with a high activation energy has an excellent
equilibrium position it will not reach in any useful time. The plant
runs at a compromise temperature, high enough to be fast, low enough
that the yield is not ruined, with a catalyst to recover some of what
the compromise cost and continuous removal of the ammonia to keep $Q$
below $K$.

That is thermodynamics and kinetics arguing, and an engineer settling
it. Bring the argument to [[Energy Choices]].

Practise predicting shifts, and calculating $Q$ when the prediction is
not obvious, in [[Equilibrium Practice]]. Then
[[Acids and Bases]] applies every idea on this page to the one
equilibrium that runs in every glass of water in the building.

%%curriculum-start%%
## Curriculum connection

![[E2.2]]

![[E3.1]]

![[E3.3]]
%%curriculum-end%%
