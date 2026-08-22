---
title: Corrosion and Electrolysis
publish: true
created: __CREATED__
enableToc: true
tags:
  - concepts
  - electrochemistry
---
The cell you built in [[Building a Galvanic Cell]] took some setting up:
two beakers, two electrodes, a salt bridge, a careful choice of metals.

A rusting car does none of that and is a galvanic cell anyway. So is a
bridge, a buried pipeline, and a nail left in a damp shed. Nobody
assembled them. The components were already present, and this page is
about what happens when electrochemistry runs whether you asked it to or
not — and about the industry built on running it deliberately in the
other direction.

## Rust is a cell you did not build

Corrosion is not iron "reacting with air". It is an **electrochemical**
process with two separate half-reactions happening at two different
places on the same piece of metal.

At an **anodic region** — often a scratch, a stressed bend, or a spot
where the surface is slightly different — iron is oxidised:

$$\ce{Fe(s) -> Fe^2+(aq) + 2e-}$$

The electrons travel through the metal itself, which is an excellent
conductor and needs no wire, to a **cathodic region** where oxygen is
reduced in the film of water sitting on the surface:

$$\ce{O2(g) + 2H2O(l) + 4e- -> 4OH-(aq)}$$

The iron(II) ions then meet more oxygen, are oxidised further to
iron(III), and precipitate as a hydrated oxide — which is rust. Its
formula is written $\ce{Fe2O3} \cdot x\ce{H2O}$
with a variable $x$, because rust genuinely does not have a fixed water
content.

Three things follow immediately, and each one you have seen.

- **Rust needs iron, water, and oxygen — all three.** Remove any one and
  it stops. Iron does not rust in dry air, and it does not rust in water
  that has had the oxygen removed.
- **An electrolyte speeds it up enormously**, because a solution
  carrying ions completes the circuit far better than pure water does.
  That is road salt in a Canadian winter, and sea spray on a coast, and
  it is why the underside of a car goes first.
- **Rust does not protect the metal underneath.** It is porous, it
  occupies more volume than the iron it came from, and it flakes away —
  exposing fresh metal to start again. Corrosion of iron is
  self-perpetuating rather than self-limiting.

> [!question] Why does aluminium not disappear, then?
> Aluminium is *more* easily oxidised than iron. By the reduction
> potentials in [[Reading a Reduction Potential Table]] it ought to
> corrode faster, and every aluminium object you own should have crumbled
> long ago.
>
> It does oxidise — immediately, on every fresh surface. The difference
> is in the **oxide**. Aluminium oxide is thin, dense, and sticks
> tightly to the metal beneath, so it seals the surface and nothing
> further can reach it. Iron oxide flakes off and seals nothing.
>
> The thermodynamics predicted the wrong outcome because it was
> answering a different question, and the physical structure of the
> product settled it. That is [[Collision Theory and Catalysts]] all
> over again in a different costume: what a reaction *would* do and what
> it *does* are not the same question.

## Stopping it

Every method below either keeps the reactants apart or makes sure the
iron is the **cathode** — because a cathode is where reduction happens,
and a metal being reduced is a metal not dissolving.

| Method | How it works | Where it fails |
| --- | --- | --- |
| Paint, grease, or plastic coating | a barrier excluding water and oxygen | one scratch and corrosion starts underneath |
| Galvanising — a zinc coating | barrier **and** sacrificial protection | the zinc is gradually consumed |
| Sacrificial anode | a block of a more easily oxidised metal is bolted on | the block must be inspected and replaced |
| Impressed current | a power supply forces the structure negative | needs permanent electricity |
| Alloying — stainless steel | chromium forms a sealing oxide, as aluminium does | costly, and can still pit in salty conditions |

**Galvanising deserves the second look.** A zinc coat is not simply
paint that happens to be metal. Scratch through paint and the iron
beneath rusts; scratch through zinc and the iron **still does not**,
because zinc is more readily oxidised than iron. The zinc becomes the
anode of the little cell and corrodes in the iron's place. A galvanised
surface protects the metal it is no longer covering, which no ordinary
barrier can do.

That is **cathodic protection** by a **sacrificial anode**, and the same
idea at larger scale is a magnesium or zinc block bolted to a ship's
hull, a buried pipeline, or the inside of a domestic water heater.
Choosing to corrode something cheap on purpose is a great deal less
expensive than replacing the thing it is attached to.

## Running the reaction uphill

An **electrolytic** cell, from
[[Galvanic and Electrolytic Cells]], forces a non-spontaneous redox
reaction with an external supply. Industry runs a great deal of chemistry
that way, because some substances cannot be obtained any other way.

- **Aluminium.** Aluminium is bound so tightly to oxygen that no
  ordinary reducing agent will release it. Purified aluminium oxide is
  dissolved in a molten salt bath and electrolysed, with the metal
  collecting at the cathode and oxygen released at carbon anodes that
  are steadily consumed in the process. Aluminium was a precious metal
  until this became practical.
- **Zinc.** Zinc is recovered by electrolysing a solution of its
  sulfate, depositing the metal on a cathode — which is why the
  galvanising in the table above exists at all.
- **Refining copper.** Impure copper is made the anode and pure copper
  the cathode. Copper dissolves and re-plates in purer form, while the
  more valuable impurities fall to the bottom of the cell as a sludge
  that is worth collecting on its own account.
- **Electroplating.** Make the object the cathode, put the plating metal
  in solution, and it deposits on the surface. Chrome trim and gold
  contacts are this reaction.
- **Chlorine, sodium hydroxide, and hydrogen** come together from the
  electrolysis of brine, three industrially important products from one
  cell.
- **Hydrogen from water** is electrolysis in its simplest form, hydrogen
  at the cathode and oxygen at the anode in a two-to-one ratio by
  volume. Whether that is a clean fuel depends entirely on where the
  electricity came from — an argument for [[Energy Choices]] rather than
  for this page.

> [!danger] Electrolysis makes gases
> Any electrolysis of an aqueous solution is likely to be producing
> **hydrogen** at one electrode, and hydrogen forms an explosive mixture
> with air over a wide range of concentrations.
>
> No flames anywhere in the room. The cell is **never sealed** — gas has
> to escape, and a sealed cell builds pressure until something gives.
> Electrolysis of a chloride solution also produces **chlorine**, which
> is toxic, and that is done in a fume hood or not at all. Disconnect
> the supply before touching anything in the cell, and keep the
> electrical supply away from spilled electrolyte. The rest is in
> [[Lab Safety and WHMIS]].

## What it costs

Electrolysis is expensive in one specific way: it consumes electricity
in direct proportion to the number of moles of electrons pushed through
the cell. That is not an engineering inefficiency to be designed away —
it is the enthalpy of the reaction being paid for, in advance, at the
meter.

The consequence shows up on maps. Aluminium smelters are built where
electricity is abundant and cheap, which in Canada has meant beside
hydroelectric generation rather than beside the ore. The chemistry
decided the geography.

It also decides the arithmetic of recycling. Remelting aluminium
requires only enough energy to melt it, while producing it from ore
requires the electrolysis as well — which is why aluminium is among the
most worthwhile things to recycle and why the case for doing so is
chemical rather than merely virtuous.

Take that argument to [[Batteries and Corrosion]], where the same
chemistry is examined as a product with a lifetime and a disposal
problem, and then bring the year together in
[[The Chemistry Showcase]].

%%curriculum-start%%
## Curriculum connection

![[F2.5]]

![[F2.6]]

![[F3.5]]

![[F3.6]]
%%curriculum-end%%
