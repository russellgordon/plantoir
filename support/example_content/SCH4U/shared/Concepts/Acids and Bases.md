---
title: Acids and Bases
publish: true
created: __CREATED__
enableToc: true
tags:
  - concepts
  - equilibrium
---
The very first measurement of this unit was a neutralisation, back in
[[Calorimetry of a Neutralisation]], and you treated it then as a
reaction that ran to completion and released heat. That was the Grade 11
account, and it was good enough to get a number out of a thermometer.

It is not good enough any more. Everything in
[[Dynamic Equilibrium]] and [[Le Chatelier's Principle|Le Châtelier's Principle]]
applies to acid solutions, and once it is applied, the two-line
definition you learned last year turns out to be describing a special
case.

## What changed since Grade 11

Grade 11 used **Arrhenius's** definition: an acid produces
$\ce{H+}$ in water, a base produces $\ce{OH-}$. It works, in
water, for the substances that contain the relevant ion to begin with.
Its limits were flagged at the time — ammonia is unmistakably basic and
contains no hydroxide.

The repair is the **Brønsted–Lowry** definition, and it is shorter:

> An **acid** is a proton donor. A **base** is a proton acceptor.

Three things change immediately.

- **Water leaves the definition.** Acid–base behaviour is now a transfer
  between two substances, and no solvent is mentioned. Hydrogen chloride
  gas and ammonia gas react on contact to make solid ammonium chloride,
  with nothing dissolved in anything, and Brønsted–Lowry calls that an
  acid–base reaction because a proton moved.
- **Ammonia is a base with no explaining away.** It accepts a proton
  from water. That is the definition, applied directly.
- **Acidity becomes a relationship, not a property.** A substance is an
  acid *with respect to* something that will take its proton. Water
  accepts a proton from hydrogen chloride and donates one to ammonia; it
  is not confused, it is **amphiprotic**, and so are
  $\ce{HCO3-}$ and $\ce{H2PO4-}$.

One notational point carried over from Grade 11. A bare proton does not
drift about in solution — it attaches to water, giving the **hydronium
ion**, $\ce{H3O+}$. This course writes
$[\ce{H3O+}]$ throughout, because the whole picture is about
where the proton went.

## Conjugate pairs

Every Brønsted–Lowry reaction has two acids and two bases in it, and
they come in linked pairs.

$$\ce{CH3COOH(aq) + H2O(l) <=> CH3COO-(aq) + H3O+(aq)}$$

Ethanoic acid donated a proton, so it is the acid; what is left,
$\ce{CH3COO-}$, is its **conjugate base**. Water accepted the
proton, so it is the base; $\ce{H3O+}$ is its **conjugate
acid**.

A conjugate pair differs by **exactly one proton** — one $\ce{H}$, and
one unit of charge. That is the whole test, and it is worth applying
mechanically until it is automatic, because the whole of
[[Buffers and Titration Curves]] is built out of conjugate pairs.

There is a relationship between the two halves of a pair that explains a
great deal:

> The stronger an acid, the weaker its conjugate base.

If a substance holds its proton loosely, whatever is left behind has
little appetite to take one back. Hydrochloric acid is strong and the
chloride ion is so feeble a base that it does nothing measurable in
water. Ethanoic acid is weak and the ethanoate ion is a base you can
detect: dissolve sodium ethanoate in pure water and the solution comes
out **basic**, which under Arrhenius's definition makes no sense at all.

## Strong and weak is a statement about equilibrium

A **strong** acid ionises essentially completely. Put hydrogen chloride
in water and, for practical purposes, no $\ce{HCl}$ molecules remain.
Its ionisation is written with a single arrow, not because there is no
equilibrium but because it lies so far right that the reverse reaction
is negligible.

A **weak** acid ionises only slightly, and its equilibrium is the point:

$$K_a = \frac{[\ce{H3O+}][\ce{A-}]}{[\ce{HA}]}$$

A large $K_a$ means the products are favoured, so the acid is stronger.
Values span many orders of magnitude, so they are usually quoted as
$\text{p}K_a = -\log K_a$, where a **smaller** $\text{p}K_a$ means a
stronger acid. Reading those tables properly is what
[[Reading an Equilibrium Table]] is for.

Now the comparison that makes it concrete. Take two solutions of the
same concentration, 0.10 mol/L:

| Solution | What is present | $[\ce{H3O+}]$ | pH |
| --- | --- | --- | --- |
| Hydrochloric acid | ions only, no intact $\ce{HCl}$ | 0.10 mol/L | 1.00 |
| Ethanoic acid | mostly intact molecules | about $1.3 \times 10^{-3}$ mol/L | about 2.87 |

Both bottles say 0.10 mol/L. One is nearly two pH units more acidic than
the other, because in the ethanoic acid only about **1.3 per cent** of
the molecules have given up a proton at any moment. The rest are sitting
there intact. Using the $K_a$ your booklet gives for ethanoic acid you
can calculate that figure yourself, and doing so once is worth more than
reading it here.

> [!important] Strong is not concentrated, and weak is not safe
> **Strong or weak** describes what fraction of the substance ionises.
> It is a property of the substance and you cannot change it.
> **Concentrated or dilute** describes how much is dissolved in a given
> volume. It is a property of the mixture and you change it with water.
> A dilute solution of a strong acid and a concentrated solution of a
> weak acid are both perfectly ordinary things, and the two words are
> answering different questions.
>
> Neither word describes hazard. Glacial ethanoic acid is a weak acid
> and will burn you. Read the label, not the category.

## Water ionises too

Even pure water conducts electricity a little, which it could not do if
it contained no ions. A tiny fraction of water molecules transfer a
proton to each other:

$$\ce{2H2O(l) <=> H3O+(aq) + OH-(aq)}$$

The equilibrium constant for that, the **ion product of water**, is

$$K_w = [\ce{H3O+}][\ce{OH-}] = 1.0 \times 10^{-14}$$

That value holds **at 25 °C**. The temperature is not decoration, and it
belongs in the sentence every time you quote the number. $K_w$ is an
equilibrium constant, and by
[[Le Chatelier's Principle|Le Châtelier's Principle]] the only thing that
changes an equilibrium constant is temperature — so $K_w$ at 50 °C is a different number.

Because the product is fixed, the two concentrations are locked
together: push one up and the other must come down. There is hydroxide
in every acid and hydronium in every base, always, in whatever amount
$K_w$ permits.

The pH scale is just a convenient way of writing those numbers:

$$\text{pH} = -\log[\ce{H3O+}] \qquad \text{pOH} = -\log[\ce{OH-}] \qquad \text{pH} + \text{pOH} = 14.00$$

That last identity holds **at 25 °C**, because it is $K_w$ in
logarithmic clothing. And here is the consequence people find
surprising: warm water is neutral at a pH below 7. Neutral means
$[\ce{H3O+}] = [\ce{OH-}]$, not "pH is 7" — and as $K_w$
rises with temperature, both concentrations rise together and the
neutral pH falls. Pure water at body temperature is neutral and its pH
is not 7.00. If you have been treating 7 as a law of nature, that is the
sentence to keep.

The mechanics of logarithms — including how many decimal places a pH is
allowed to have — are in
[[Working with Logarithms in Chemistry]].

> [!danger] The two hazards in this unit
> Student work here uses **dilute** solutions at the concentrations the
> procedure states, and there is never a reason to reach for a stronger
> bottle than the one you were given.
>
> **Sodium hydroxide does not hurt at first.** An alkali burn is
> painless for long enough that people carry on working, and it
> penetrates deeper than a dilute acid burn because it dissolves the
> fats and proteins your skin and the surface of your eye are made from.
> Rinse for far longer than seems necessary and report it, however
> minor it looks.
>
> When any acid has to be diluted, **acid goes into water, never water
> into acid.** Dilution releases heat, and pouring water onto a
> concentrated acid releases it all at the surface, which can boil and
> spit acid back out of the container. Eye protection stays on. Full
> rules in [[Lab Safety and WHMIS]].

Practise the calculations in [[Acids and Bases Practice]], and then meet
the case where all of this becomes a design problem rather than a
measurement: [[Buffers and Titration Curves]].

%%curriculum-start%%
## Curriculum connection

![[E3.6]]

![[E3.7]]
%%curriculum-end%%
