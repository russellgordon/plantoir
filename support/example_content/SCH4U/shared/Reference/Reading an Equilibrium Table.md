---
title: Reading an Equilibrium Table
publish: true
created: __CREATED__
enableToc: true
tags:
  - reference
  - equilibrium
---
This page contains no data. The numbers you will use come from **the
data booklet you are handed**, which is the authority, and one of the
few genuinely useful skills in Unit 4 is being able to open it and know
exactly what you are entitled to conclude.

What follows is how those tables are built, what each column is a
statement about, and the three conclusions people draw from them that
do not follow. The chemistry behind it is [[Dynamic Equilibrium]] and
[[Acids and Bases]].

## What a $K$ value is a statement about

An equilibrium constant is a statement about **where a system settles**,
at **one temperature**, expressed as a ratio of products over reactants.

- **Large $K$** — the system settles with mostly products. The reaction
  looks, from outside, as though it went to completion.
- **$K$ near 1** — meaningful amounts of everything are present.
- **Small $K$** — the system settles with mostly reactants. The reaction
  looks as though it failed, and it did not; it arrived somewhere close
  to where it started.

Three habits to build:

1. **Read the temperature at the top of the table.** Almost every table
   is compiled at 25 °C. A constant is only a constant at a fixed
   temperature, and temperature is the one disturbance that changes it —
   see [[Le Chatelier's Principle|Le Châtelier's Principle]].
2. **Note the significant figures.** Booklet values are usually given to
   two, which caps your answer at two however many digits the calculator
   offers.
3. **Expect no units.** Equilibrium constants are conventionally written
   as bare numbers. The convention has a real justification — the
   expression is strictly built from ratios rather than raw
   concentrations — and at this level you simply do not attach units.

## The four tables you will meet

| Table | Symbol | The equilibrium it describes | Sorted so that |
| --- | --- | --- | --- |
| Acid ionisation constants | $K_a$ | a weak acid donating a proton to water | the strongest acid is usually at the top |
| Base ionisation constants | $K_b$ | a weak base accepting a proton from water | the strongest base is usually at the top |
| Solubility products | $K_{sp}$ | a sparingly soluble salt dissolving into its ions | often alphabetical, not by size |
| Ion product of water | $K_w$ | water transferring a proton to itself | a single value, $1.0 \times 10^{-14}$ at 25 °C |

Several things about that first table are worth knowing before you open
it.

**The conjugate base is usually printed beside the acid**, in its own
column, because half the questions are about the base rather than the
acid. Reading across a row gives you a conjugate pair.

**The strong acids may not have numbers at all**, or may be marked "very
large". That is not an omission. In water, a strong acid ionises
completely, so all that survives is hydronium — and every strong acid
therefore produces the same acidity at the same concentration. Water
cannot tell them apart, so the table stops trying.

**Values may be given as $K_a$ or as $\text{p}K_a$ or both**, and the
conversion goes both ways:

$$\text{p}K_a = -\log K_a \qquad K_a = 10^{-\text{p}K_a}$$

A **smaller** $\text{p}K_a$ means a **stronger** acid, which is the
opposite direction from $K_a$ and catches people every year.

## Relationships between entries

Two shortcuts save a great deal of table-hunting.

**A conjugate pair's constants multiply to $K_w$:**

$$K_a \times K_b = K_w$$

So a booklet that prints $K_a$ values does not need to print $K_b$ for
their conjugate bases — you divide. This is also the arithmetic behind
"the stronger the acid, the weaker its conjugate base": if the product
is fixed, one going up forces the other down.

**In logarithmic form**, at 25 °C:

$$\text{p}K_a + \text{p}K_b = 14.00$$

**Solubility products need more care than they look.** A $K_{sp}$ is the
product of the ion concentrations at saturation, each raised to its
coefficient — so its numerical value depends on how many ions the
formula produces.

> [!warning] Comparing two $K_{sp}$ values is only valid within a formula type
> A salt of type $\ce{AB}$ and a salt of type $\ce{AB2}$ relate
> their $K_{sp}$ to their actual solubility through different powers.
> The smaller $K_{sp}$ of the two is **not** reliably the less soluble
> salt.
>
> Comparing silver chloride with silver bromide — both $\ce{AB}$ — is
> legitimate, and the smaller $K_{sp}$ is the less soluble. Comparing
> silver chloride with calcium fluoride is not, and to answer that
> question you must convert each $K_{sp}$ into a molar solubility first
> and compare those.

## Setting up an ICE table

An ICE table is the standard way of getting from a booklet value to an
answer. It is a plain table with three rows, and its whole purpose is to
stop you losing track of what changed.

For a weak acid $\ce{HA}$ at initial concentration $c$:

| | $\ce{HA}$ | $\ce{H3O+}$ | $\ce{A-}$ |
| --- | --- | --- | --- |
| **I**nitial | $c$ | about 0 | 0 |
| **C**hange | $-x$ | $+x$ | $+x$ |
| **E**quilibrium | $c - x$ | $x$ | $x$ |

Substituting the bottom row into the $K_a$ expression gives

$$K_a = \frac{x^2}{c - x}$$

and the equation is solved for $x$, which is the hydronium
concentration you wanted.

Four rules for filling one in:

- The **Change** row always follows the coefficients of the balanced
  equation. A coefficient of 2 gives $-2x$ or $+2x$.
- Pure **solids and pure liquids** are left out entirely, exactly as
  they are left out of the $K$ expression.
- The initial hydronium concentration is written as "about 0" rather
  than 0, because water's own ionisation supplies a trace. It is
  negligible next to what a weak acid produces, and it is not zero.
- Every entry is a **concentration**, in mol/L. Not moles. If the
  question gave you moles and a volume, divide before the table, not
  after.

> [!tip] When you are allowed to say "$x$ is small"
> If $c - x \approx c$, the algebra collapses from a quadratic to a
> square root and the problem becomes a one-line calculation. That
> approximation is legitimate when $x$ really is negligible — and the
> usual test is whether $x$ comes out below **five per cent** of $c$.
>
> As a rule of thumb, it is safe when the initial concentration is at
> least about a thousand times $K_a$. When it is not — a very weak
> solution, or a comparatively strong weak acid — solve the quadratic.
> The honest move is to make the approximation, then **check** it, and
> to say in your working that you checked.

## Three things the table does not say

**It says nothing about rate.** A reaction with an enormous $K$ may take
a century. Equilibrium constants and kinetics are separate subjects that
share a chapter, and the argument is in
[[Collision Theory and Catalysts]].

**It says nothing at any other temperature.** A table compiled at 25 °C
tells you about systems at 25 °C. This includes $K_w$ — pure water at
body temperature is still neutral, and its pH is not 7.00.

**It says nothing about how much you have.** $K$ fixes a *ratio*, not an
amount. A tiny sample and a large one at the same temperature satisfy
the same constant. Whether the amounts you have are enough to do
anything with is a separate question, and it is the question
[[Buffers and Titration Curves]] turns out to be about.

Practise pulling values and using them in [[Equilibrium Practice]] and
[[Acids and Bases Practice]].
