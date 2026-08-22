---
title: The Mole
publish: true
created: __CREATED__
tags:
  - concepts
  - quantities
---
Last class you were asked how many atoms were in a paperclip, and the
room stalled in an interesting way. Nobody doubted the number existed.
The problem was that atoms cannot be counted the way marbles can, and
the balance in front of you reports grams, which is the wrong quantity
entirely. The mole is how chemists get from the quantity they can
measure to the quantity the reaction actually cares about.

## The reaction counts, your balance weighs

A balanced equation is a statement about **numbers of particles**. When
you write

$$\ce{Zn + 2HCl -> ZnCl2 + H2}$$

the 2 does not mean two grams of hydrochloric acid or two millilitres of
it. It means that for every one zinc atom, two molecules of $\ce{HCl}$
are consumed. The equation is a recipe written in particles.

Your equipment cannot count particles. So you need a bridge — a way of
saying "this mass corresponds to that many particles" — and the bridge
has to be built once, carefully, and then used everywhere.

## A counting unit, chosen to be convenient

You already accept counting units. A dozen is twelve of anything; a
ream is five hundred sheets. A **mole** is the same idea, sized for
atoms:

$$1 \text{ mol} = 6.022 \times 10^{23} \text{ particles}$$

That number — Avogadro's number — looks arbitrary and is not. It was
chosen so that one mole of an element has a mass in grams equal to the
number printed under its symbol on the periodic table. One mole of
carbon atoms is 12.01 g. One mole of zinc atoms is 65.38 g. The whole
point of the number is to make the periodic table double as a
conversion chart.[^1]

[^1]: Since 2019 the mole is *defined* as exactly
    $6.02214076 \times 10^{23}$ elementary entities, rather than being
    derived from a mass of carbon-12 as it was before. The number stayed
    the same to more decimal places than any school measurement could
    detect; what changed is which quantity is treated as fixed and which
    is measured. It is a good example of a definition being tidied up
    long after everyone had agreed on the value.

> [!warning] "Mole" names a number, not a substance
> A mole of water and a mole of lead are the same *count* and wildly
> different masses. A mole of $\ce{H2O}$ is 18.02 g; a mole of
> lead is 207.2 g. If a sentence you have written would still make sense
> with "mole" replaced by "gram", something has gone wrong.

## Moving between mass, moles, and particles

Two relationships do all the work. With $n$ for amount in moles, $m$ for
mass in grams, $M$ for molar mass in grams per mole, and $N$ for the
number of particles:

$$n = \frac{m}{M} \qquad N = n \times 6.022 \times 10^{23}$$

Which means every problem of this kind is the same problem wearing
different clothes:

| You are given | You want | Route |
| --- | --- | --- |
| Mass | Moles | Divide by molar mass |
| Moles | Mass | Multiply by molar mass |
| Moles | Particles | Multiply by Avogadro's number |
| Mass | Particles | Both steps, in that order |

There is no fourth trick. If a question looks unfamiliar, find where it
sits in that table before you write anything down.

> [!example]- Worked: the paperclip
> A steel paperclip has a mass of about 1.0 g and is mostly iron, so
> treat it as iron. The molar mass of iron is 55.85 g/mol.
>
> $n = \frac{1.0 \text{ g}}{55.85 \text{ g/mol}} = 0.018 \text{ mol}$
>
> $N = 0.018 \times 6.022 \times 10^{23} = 1.1 \times 10^{22}$ atoms
>
> Eleven thousand billion billion atoms, from a measurement you took in
> four seconds. Note the answer carries **two** significant figures,
> because the mass did — see [[Significant Figures and Units]]. Writing
> $1.078 \times 10^{22}$ would be claiming a precision the balance never
> gave you.

## Why this is the hinge of the course

Everything quantitative from here runs through the mole. Percentage
composition, empirical formulas, the amount of precipitate you should
have recovered, the volume of gas a reaction will produce, the
concentration of a solution — each one is a mass or a volume converted
into a count, put through a balanced equation, and converted back.

Get comfortable with the conversions in [[Mole Conversions Practice]]
until they stop being a procedure you look up. Then
[[Molar Mass and Composition]] handles compounds rather than elements,
and [[Stoichiometry]] puts the
count through the equation, which is where this is all going.

%%curriculum-start%%
## Curriculum connection

![[D2.1]]

![[D3.1]]

![[D3.2]]
%%curriculum-end%%
