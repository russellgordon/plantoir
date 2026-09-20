---
title: Atomic Structure and Orbitals
publish: true
created: __CREATED__
enableToc: true
tags:
  - concepts
  - structure
---
Unit 1 opened with a question about boiling points in
[[Boiling Points and Structure]] and has been answering it downwards
ever since — shape, then polarity, then the forces between molecules.
Each answer leaned on a word that was never defined.
==Electronegative== means an atom pulls electrons. ==Polarisable== means
its electron cloud squashes easily. Both are claims about where the
electrons are, and until now you have been taking them on trust.

This page pays that debt. It is the bottom of Unit 1, and it is also the
oldest argument in the course: how do you find out about something you
cannot see, cannot weigh, and cannot hold still?

## Two experiments, two models

**Ernest Rutherford** fired alpha particles at a sheet of gold foil only
a few thousand atoms thick. Almost all of them went straight through as
if the foil were not there. A very small fraction came back at large
angles — some nearly straight back at the source.

Both observations matter, and students usually remember only the second.
Passing straight through says the atom is mostly **empty space**. Coming
back says that somewhere in that emptiness sits something **tiny, dense,
and positively charged**: a nucleus. The plum-pudding model, in which
positive charge was smeared through the whole atom, cannot deflect
anything sharply, because there is nothing concentrated to hit.

Rutherford's picture — electrons circling a nucleus — has a fatal
problem, and he knew it. Classical physics says an accelerating charge
radiates energy, and an electron going in a circle is accelerating
continuously. It should spiral into the nucleus almost instantly. Every
atom in the universe should have collapsed. They have not.

**Niels Bohr** repaired it with a claim that had no justification at the
time and turned out to be right: the electron may occupy only certain
**allowed energy levels**, and while it sits in one it does not radiate.
Energy is emitted only when the electron drops from a higher level to a
lower one, and the light carries away exactly the difference.

The evidence was already on the bench. Pass electricity through hydrogen
gas and the light it gives off, spread out by a prism, is not a rainbow.
It is a handful of sharp coloured lines, in the same places every time,
for every sample of hydrogen anywhere.[^1] A continuous range of allowed
energies would give a continuous spectrum. Discrete lines mean discrete
levels, and Bohr's model calculates the hydrogen lines correctly.

Then it stops. Bohr's model fails for **every atom with more than one
electron**, because it has no way to handle electrons repelling each
other, and its neat circular orbits turn out not to exist. It is a
model that was spectacularly right about one atom and wrong about the
rest — which is a more useful thing to have been than vaguely right
about everything.

## An orbital is a probability, not a path

The replacement gives up on knowing where the electron *is*. An
**orbital** is a region around the nucleus within which an electron is
very likely to be found — conventionally drawn to enclose about nine
tenths of the probability. The boundary on the diagram is a choice, not
a wall.

The structure goes in three nested layers:

- **Shells**, numbered $n = 1, 2, 3, \ldots$ — roughly, how far out.
- **Subshells** within each shell, labelled $s$, $p$, $d$, $f$ — the
  shape of the region. Shell $n$ contains $n$ kinds of subshell.
- **Orbitals** within each subshell: one $s$ orbital, three $p$, five
  $d$, seven $f$. Every orbital, of every kind, holds a maximum of two
  electrons.

So the capacities are $s = 2$, $p = 6$, $d = 10$, $f = 14$, and the $s$
orbital is a sphere while each $p$ orbital is a two-lobed shape pointing
along one axis. The three $p$ orbitals are identical except in
direction, and that "identical except in direction" is what makes
Hund's rule below say anything at all.

## Three rules write every configuration

**The aufbau principle** — fill the lowest-energy orbital available
first. *Aufbau* is German for building up, and the name describes the
procedure rather than a law of nature.

**The Pauli exclusion principle** — no two electrons in one atom may
have the same set of four quantum numbers. The consequence you use: an
orbital holds at most two electrons, and those two must have **opposite
spins**.

**Hund's rule** — within a set of orbitals of equal energy, put one
electron into each before pairing any of them up, and keep those single
electrons' spins parallel. Electrons repel; given three identical rooms,
they take one each before doubling up.

Nitrogen is the clean illustration. Its configuration is
$1s^2\,2s^2\,2p^3$, and Hund's rule says those three $p$ electrons sit
one to an orbital, all unpaired. Oxygen's fourth $p$ electron has no
empty room left and must pair, which costs energy — and that cost is
exactly the reason oxygen's first ionisation energy is *lower* than
nitrogen's, breaking the tidy left-to-right trend you met last year.

The filling order that follows from the aufbau principle is:

$$1s \;\; 2s \;\; 2p \;\; 3s \;\; 3p \;\; 4s \;\; 3d \;\; 4p \;\; 5s \;\; 4d \;\; 5p \;\; 6s \;\; 4f \;\; 5d \;\; 6p$$

You do not have to memorise that. It is written on the periodic table
itself, read left to right across the rows — which is the entire point
of [[The Blocks of the Periodic Table]].

## Where the rules bend

**The $4s$ and $3d$ problem.** The list above puts $4s$ before $3d$, and
for potassium and calcium that is right: potassium is
$[\ce{Ar}]\,4s^1$, not $[\ce{Ar}]\,3d^1$.

But the moment the $3d$ orbitals begin to fill, they drop **below** $4s$
in energy. In a neutral iron atom, the $3d$ orbitals are the lower ones.
This has a consequence you can check against data: when a transition
metal is ionised, the electrons that leave are the $4s$ electrons, not
the $3d$ ones. Iron is $[\ce{Ar}]\,3d^6\,4s^2$ and the iron(II) ion is
$[\ce{Ar}]\,3d^6$ — not $[\ce{Ar}]\,3d^4\,4s^2$.

Read that twice, because it sounds like a contradiction and is not.
**$4s$ fills first and $4s$ empties first.** Filling order and removal
order are not reverses of each other, because orbital energies are not
fixed — they depend on the nuclear charge and on how many other
electrons are present, so the ordering shifts as you move along the row.
The diagonal filling rule is a mnemonic for building neutral ground
states, and nothing more.

**Chromium and copper.** Two elements in the first transition row do not
follow the rule at all:

| Element | Rule predicts | Actually observed |
| --- | --- | --- |
| Chromium | $[\ce{Ar}]\,3d^4\,4s^2$ | $[\ce{Ar}]\,3d^5\,4s^1$ |
| Copper | $[\ce{Ar}]\,3d^9\,4s^2$ | $[\ce{Ar}]\,3d^{10}\,4s^1$ |

An electron has moved from $4s$ into $3d$ to give a half-filled or a
completely filled $d$ subshell. Learn those two — they are the ones you
will be asked for.

> [!question] Is "half-filled shells are stable" an explanation?
> Not really, and it is worth being honest about that. It is a
> **mnemonic** for two observations, dressed up as a cause. The real
> accounting involves how much energy is saved by keeping electrons
> unpaired and spread out, balanced against the cost of moving one
> between subshells, and it comes out close either way — which is
> precisely why these two elements can be tipped over the line at all.
>
> The giveaway is that the rule does not generalise. Palladium's ground
> state is $[\ce{Kr}]\,4d^{10}$ with *no* outer $s$ electron
> whatsoever, and several other heavy $d$-block elements break the
> pattern in ways "half-filled is stable" does not predict. Take
> chromium and copper as measured facts about two elements, not as a
> principle.

> [!info] Canadian work on where electrons are
> Three names your curriculum points at, all working on this exact
> question. **Ronald J. Gillespie** at McMaster University developed the
> VSEPR model behind [[Molecular Shapes]]. **Richard F. W. Bader**, also
> at McMaster, worked out how to divide a molecule into atoms using the
> electron *density* itself rather than an arbitrary boundary.
> **Robert J. LeRoy** at the University of Waterloo gave his name to the
> LeRoy radius, a mathematical treatment of where a molecule effectively
> ends. Every one of them was answering the question this page opened
> with.

[^1]: This is not only a laboratory result. The same fixed pattern of
    lines, seen in light from a star, identifies which elements the star
    contains — which is how we know what the sun is made of without
    going there. Reading structure out of a pattern in data is the move
    the whole of [[Reading a Data Table]] is about.

%%curriculum-start%%
## Curriculum connection

![[C2.2]]

![[C3.1]]

![[C3.2]]

![[C3.3]]

![[C3.5]]
%%curriculum-end%%
