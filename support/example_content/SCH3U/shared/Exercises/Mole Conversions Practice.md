---
title: Mole Conversions Practice
publish: true
created: __CREATED__
tags:
  - chemistry
  - exercises
---
Two relationships do all the work on this page, and there is no third
one hiding anywhere:

$$n = \frac{m}{M} \qquad N = n \times 6.022 \times 10^{23}$$

with $n$ the amount in moles, $m$ the mass in grams, $M$ the molar mass
in grams per mole, and $N$ the number of particles.

Molar masses to **two decimal places** from the periodic table. Carry
full precision through the working and round **once**, at the end, to
the number of significant figures the data allow. Every line of working
carries units.

**1.** How many moles are there in 25.0 g of sodium chloride?

> [!success]- Answer 1
> Molar mass first, because every one of these starts there.
>
> $M(\ce{NaCl}) = 22.99 + 35.45 = 58.44 \text{ g/mol}$
>
> $n = \frac{m}{M} = \frac{25.0 \text{ g}}{58.44 \text{ g/mol}} = 0.4278 \text{ mol}$
>
> **0.428 mol**, to three significant figures, because the mass was
> given to three and the molar mass to four. The weakest measurement
> sets the ceiling.
>
> Check the units did what they should: grams divided by grams per mole
> leaves moles. If your units had come out as grams squared per mole,
> you divided the wrong way round, and the units told you before the
> answer did.

**2.** What is the mass of 2.50 mol of carbon dioxide?

> [!success]- Answer 2
> $M(\ce{CO2}) = 12.01 + 2(16.00) = 44.01 \text{ g/mol}$
>
> Rearranging $n = \frac{m}{M}$ gives $m = nM$:
>
> $m = (2.50 \text{ mol})(44.01 \text{ g/mol}) = 110.025 \text{ g}$
>
> **$1.10 \times 10^2$ g**, to three significant figures.
>
> That form is worth using rather than "110 g", which is ambiguous
> about whether the trailing zero counts. Scientific notation makes the
> claim explicit: three figures, no more.

**3.** How many molecules are there in 4.00 g of water? How many
**atoms**?

> [!success]- Answer 3
> $M(\ce{H2O}) = 2(1.01) + 16.00 = 18.02 \text{ g/mol}$
>
> $\begin{aligned} n &= \frac{4.00 \text{ g}}{18.02 \text{ g/mol}} = 0.22198 \text{ mol} \\ N &= (0.22198)(6.022 \times 10^{23}) = 1.3367 \times 10^{23} \end{aligned}$
>
> **$1.34 \times 10^{23}$ molecules**, to three significant figures.
>
> For the atoms, notice what the formula says: each molecule contains
> **three** atoms, two hydrogens and one oxygen. So
>
> $3 \times 1.3367 \times 10^{23} = 4.01 \times 10^{23}$ atoms.
>
> Keep those two numbers apart in your head. "How many particles" is
> never a complete question until somebody says *particles of what*, and
> a great many marks are lost in the gap between molecules and atoms.

**4.** A sample of calcium nitrate, $\ce{Ca}(\ce{NO3})_2$, has a
mass of 50.0 g.
(a) How many moles is that?
(b) How many nitrate ions does it contain?

> [!success]- Answer 4
> **(a)** Build the molar mass carefully — the subscript outside the
> bracket multiplies **everything** inside it.
>
> $M = 40.08 + 2[14.01 + 3(16.00)] = 40.08 + 2(62.01) = 164.10 \text{ g/mol}$
>
> $n = \frac{50.0 \text{ g}}{164.10 \text{ g/mol}} = 0.30469 \text{ mol}$
>
> **0.305 mol**, to three significant figures.
>
> **(b)** One formula unit contains **two** nitrate ions, so
>
> $\begin{aligned} n(\ce{NO3-}) &= 2 \times 0.30469 = 0.60938 \text{ mol} \\ N &= (0.60938)(6.022 \times 10^{23}) = 3.6697 \times 10^{23} \end{aligned}$
>
> **$3.67 \times 10^{23}$ nitrate ions.**
>
> Sanity check: the answer should be a bit more than half of Avogadro's
> number times one, and it is. If you had got $1.8 \times 10^{23}$ you
> would have forgotten the 2 — and multiplying by 2 at the end is
> easier to remember if you write $n(\ce{NO3-}) = 2n(\text{compound})$
> as its own line rather than doing it in your head.

**5.** A copper sample contains $1.505 \times 10^{22}$ atoms. What is
its mass?

> [!success]- Answer 5
> This one runs the chain backwards: particles to moles to mass.
>
> $n = \frac{N}{6.022 \times 10^{23}} = \frac{1.505 \times 10^{22}}{6.022 \times 10^{23}} = 0.024992 \text{ mol}$
>
> $m = nM = (0.024992 \text{ mol})(63.55 \text{ g/mol}) = 1.5882 \text{ g}$
>
> **1.588 g**, to four significant figures, because the particle count
> was given to four.
>
> Worth a moment: fifteen thousand million million million atoms weigh
> about as much as a paperclip. The mole exists precisely so that you
> never have to hold that sentence in your head while doing arithmetic.

**6.** Which contains more atoms — 10.0 g of carbon or 10.0 g of lead?
By what factor?

> [!success]- Answer 6
> Same mass, different atoms, so the comparison is entirely about molar
> mass.
>
> **Carbon:**
> $n = \frac{10.0}{12.01} = 0.83264 \text{ mol}$, so
> $N = (0.83264)(6.022 \times 10^{23}) = 5.01 \times 10^{23}$ atoms.
>
> **Lead:**
> $n = \frac{10.0}{207.2} = 0.048263 \text{ mol}$, so
> $N = (0.048263)(6.022 \times 10^{23}) = 2.91 \times 10^{22}$ atoms.
>
> **The carbon contains more, by a factor of about 17.**
>
> And here is the shortcut, which is worth more than the arithmetic. You
> never needed Avogadro's number at all. For equal masses, the ratio of
> the counts is just the inverse ratio of the molar masses:
>
> $$\frac{N_{\ce{C}}}{N_{\ce{Pb}}} = \frac{M_{\ce{Pb}}}{M_{\ce{C}}} = \frac{207.2}{12.01} = 17.3$$
>
> Divide the two rounded counts above instead and you get 17.2, not
> 17.3. Neither is a mistake — it is what rounding twice does to you,
> and it is the reason the rule is to round **once**, at the end.
>
> A lead atom is about seventeen times heavier than a carbon atom, so
> ten grams of lead buys you about a seventeenth as many of them. If you
> can see that before reaching for the calculator, you understand what
> molar mass is.

**7.** A tablet contains 325 mg of acetylsalicylic acid,
$\ce{C9H8O4}$.
(a) How many moles is that?
(b) How many molecules?

> [!success]- Answer 7
> Convert the mass to grams before anything else — the molar mass is in
> grams per mole and mixing milligrams into it is the commonest slip on
> a question that looks easy.
>
> $325 \text{ mg} = 0.325 \text{ g}$
>
> $M = 9(12.01) + 8(1.01) + 4(16.00) = 108.09 + 8.08 + 64.00 = 180.17 \text{ g/mol}$
>
> **(a)** $n = \frac{0.325 \text{ g}}{180.17 \text{ g/mol}} = 1.8039 \times 10^{-3} \text{ mol}$
>
> **$1.80 \times 10^{-3}$ mol**, to three significant figures.
>
> **(b)** $N = (1.8039 \times 10^{-3})(6.022 \times 10^{23}) = 1.0863 \times 10^{21}$
>
> **$1.09 \times 10^{21}$ molecules.**
>
> A dose small enough to swallow without noticing contains around a
> thousand million million million molecules. This is the arithmetic
> behind why dosage matters and why "a tiny amount" is not a chemical
> argument — see [[Chemicals We Live With]].

**8.** Four statements from a study group. Each is wrong or incomplete.
Fix each one.
*(a) "There are $6.022 \times 10^{23}$ atoms in one mole of water."*
*(b) "0.5 mol of oxygen has a mass of 8 g."*
*(c) "To find moles you multiply the mass by the molar mass."*
*(d) "A mole of lead weighs more than a mole of carbon, so a mole of
lead contains more atoms."*

> [!success]- Answer 8
> **(a) Molecules, not atoms.** One mole of water contains
> $6.022 \times 10^{23}$ **molecules**, and each molecule holds three
> atoms, so the atom count is
> $3 \times 6.022 \times 10^{23} = 1.81 \times 10^{24}$ atoms. The mole
> counts whatever entity you name, and the sentence is only complete
> once you have named it.
>
> **(b) It depends on what "oxygen" means, and the usual meaning makes
> this wrong.** If the student meant oxygen **atoms**, then
> $M = 16.00$ g/mol and $0.5 \times 16.00 = 8.0$ g, which is what they
> wrote. But "oxygen" in a chemical context ordinarily means the
> substance $\ce{O2}$, for which $M = 32.00$ g/mol, giving
> $0.5 \times 32.00 = 16.0$ g. The safe habit is to write the formula
> rather than the element's name whenever there is any doubt — and there
> is doubt for every diatomic element.
>
> **(c) Divide, do not multiply.** $n = \frac{m}{M}$. The units settle
> it without any memory being involved: grams divided by grams per mole
> gives moles, whereas grams multiplied by grams per mole gives grams
> squared per mole, which is not a quantity that exists. Check the
> magnitude too — 25.0 g of sodium chloride is a spoonful, so a fraction
> of a mole is plausible and 1461 mol is not.
>
> **(d) The first half is right and the conclusion does not follow.** A
> mole of lead does have a greater mass — 207.2 g against 12.01 g. But
> a mole is a **count**, and both samples contain exactly
> $6.022 \times 10^{23}$ atoms, by definition. That is the whole point
> of the unit: it fixes the number and lets the mass vary. If "mole"
> could be replaced by "gram" in a sentence you have written and the
> sentence still seemed to make sense, something has gone wrong.

Reference: [[The Mole]] and [[Molar Mass and Composition]]. How many
figures you are entitled to: [[Significant Figures and Units]].

%%curriculum-start%%
## Curriculum connection

![[D2.1]]

![[D2.3]]

![[D3.1]]
%%curriculum-end%%
