---
title: Galvanic and Electrolytic Cells
publish: true
created: __CREATED__
enableToc: true
tags:
  - concepts
  - electrochemistry
---
Drop a strip of zinc into copper(II) sulfate solution and copper plates
out onto it while the blue fades. Electrons went from the zinc to the
copper ions, directly, at the point of contact, and all you got for it
was a warm beaker.

In [[Building a Galvanic Cell]] you separated the two halves and made
the electrons take the long way round — through a wire, through a
voltmeter, through anything you cared to put in their path. The
chemistry is identical. What changed is that the electron transfer now
happens somewhere you can use it.

## The parts, and what each one is for

```mermaid
graph LR
    AN["Anode: oxidation happens here"] -->|"electrons leave through the wire"| V["External circuit"]
    V -->|"electrons arrive"| CA["Cathode: reduction happens here"]
    SB["Salt bridge"] -->|"anions travel towards"| AN
    SB -->|"cations travel towards"| CA
```

- **Two half-cells**, each holding one of the half-reactions from
  [[Redox Bookkeeping]] — typically a metal electrode standing in a
  solution of its own ion.
- **Two electrodes**, the solid conductors where electrons enter or
  leave the solution. If neither half-reaction involves a solid metal,
  an inert electrode of platinum or graphite is used simply as a
  surface.
- **The external circuit** — the wire, and whatever the cell is
  powering. Electrons travel through it from the anode to the cathode,
  and this is the only place electrons move as electrons.
- **The salt bridge**, a tube of inert electrolyte joining the two
  solutions.

The salt bridge is the component students omit from diagrams and it is
the one without which nothing works at all. Oxidation at the anode
leaves positive ions behind in that solution; reduction at the cathode
removes positive ions from the other. Within moments one compartment
would be strongly positive and the other strongly negative, and the
build-up of charge would stop the reaction dead. The salt bridge lets
ions move to cancel it: **anions towards the anode**, where positive
charge is accumulating, and **cations towards the cathode**, where it is
being depleted.

The whole cell is abbreviated in **cell notation**, anode on the left:

$$\ce{Zn(s)} \mid \ce{Zn^2+(aq)} \parallel \ce{Cu^2+(aq)} \mid \ce{Cu(s)}$$

A single bar is a boundary between phases; the double bar is the salt
bridge.

## Both cells, one rule and one difference

There are two kinds of cell and they are opposites in purpose.

| | Galvanic (voltaic) cell | Electrolytic cell |
| --- | --- | --- |
| The reaction | spontaneous | non-spontaneous |
| Energy | chemical to electrical | electrical to chemical |
| $E^\circ_\text{cell}$ | positive | negative |
| Needs a power supply? | no — it *is* one | yes |
| Anode | **oxidation** | **oxidation** |
| Cathode | **reduction** | **reduction** |
| Sign of the anode | negative | **positive** |
| Sign of the cathode | positive | **negative** |

Read the last four rows carefully, because this is where the topic
loses people.

**Oxidation happens at the anode and reduction at the cathode in both
kinds of cell.** That never changes, and it is definitional — the words
*anode* and *cathode* name the half-reaction, not the terminal. The
mnemonic that survives everything is **An Ox** and **Red Cat**.

What flips is the **sign**, and the reason is worth working out rather
than memorising.

- In a **galvanic** cell, the anode is where electrons are being
  produced. They pile up and push out into the circuit, so the anode is
  the **negative** terminal.
- In an **electrolytic** cell, an external supply is in charge. Its
  negative terminal forces electrons onto one electrode, so that
  electrode is **negative** — and electrons arriving is reduction, so
  that electrode is the cathode. The supply's positive terminal pulls
  electrons out of the other, which is oxidation, so that one is the
  positive anode.

In both cases electrons still travel through the external wire from
anode to cathode. Trace the electrons and the signs follow; memorise the
signs and you will swap them under pressure.

## Every potential is a difference

You cannot measure the potential of a single half-cell. Not because the
instruments are not good enough — because a voltmeter needs two
connections, so any reading it gives you is a **difference between two
half-cells**. There is no such thing as an absolute half-cell voltage to
measure.

The solution is a reference point, agreed on by convention: the
**standard hydrogen electrode**. Hydrogen gas at standard pressure
bubbles over an inert platinum surface immersed in a 1 mol/L solution of
hydrogen ions, at 25 °C, and

$$\ce{2H+(aq) + 2e- <=> H2(g)} \qquad E^\circ = 0.00 \text{ V}$$

That zero is **assigned**, not measured. It is a choice of origin, in
exactly the sense that the enthalpy of formation of an element is zero
in [[Hess's Law]] — and for exactly the same reason, since neither
quantity has a meaningful absolute value.

Every other half-cell is then connected to the hydrogen electrode, the
difference is read off, and that difference is tabulated as the
half-cell's **standard reduction potential**. A positive value means the
half-reaction pulls electrons harder than hydrogen does; a negative
value means it pulls less hard. That is the whole meaning of the sign,
and [[Reading a Reduction Potential Table]] is about getting it out of
the booklet without error.

## Adding potentials, and the multiplication you must not do

Both entries in the table are written as reductions. In a real cell one
of them is running backwards, and the cell potential is the difference:

$$E^\circ_\text{cell} = E^\circ_\text{cathode} - E^\circ_\text{anode}$$

where both values are taken straight from the table as reductions, with
their printed signs. A **positive** result means the reaction as written
is spontaneous — you have a galvanic cell. A **negative** result means
it is not, and driving it anyway requires a power supply of at least
that magnitude, which is an electrolytic cell.

> [!warning] Never multiply a standard potential
> When you balance a redox equation you multiply half-equations so the
> electrons cancel — five times, in the worked example on
> [[Redox Bookkeeping]]. It is extremely tempting to multiply the
> potential by the same factor. **Do not.**
>
> A potential is energy **per unit of charge** — a volt is a joule per
> coulomb. Doubling a half-equation doubles the energy released *and*
> doubles the charge moved, so the ratio between them is unchanged. The
> potential is an **intensive** property, like density or temperature:
> two litres of water at 20 °C are not at 40 °C.
>
> Contrast that with $\Delta H$ in [[Enthalpy]], which is **extensive**
> and *is* multiplied when the equation is scaled. Two quantities, two
> opposite rules, and telling them apart is the difference between an
> answer and a plausible-looking wrong answer.

Electrolytic cells are not a curiosity. Every aluminium can, every
electroplated fitting, and the industrial production of chlorine and of
hydrogen all depend on paying an electricity bill to run a reaction
uphill — which is [[Corrosion and Electrolysis]], and where the
electrochemistry finally leaves the beaker.

Draw and label both kinds of cell until it is automatic, in
[[Redox and Cells Practice]].

%%curriculum-start%%
## Curriculum connection

![[F2.1]]

![[F2.5]]

![[F3.2]]

![[F3.3]]

![[F3.4]]
%%curriculum-end%%
