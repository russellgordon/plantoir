---
title: Empirical Formula Practice
publish: true
created: __CREATED__
tags:
  - chemistry
  - exercises
---
Every question on this page is the same question. You are given masses
or percentages, which is what a balance can tell you, and you are asked
for a **ratio of counts**, which is what a formula is. The mole is the
only bridge between those two things, and the route never changes:

1. Assume 100 g if you were given percentages, so percentages become
   grams.
2. Divide each mass by that element's molar mass, to get moles.
3. Divide every result by the **smallest** of them.
4. If what comes out is not close to whole numbers, multiply all of them
   by a small integer until it is.

Molar masses to two decimal places. Keep full precision through steps 2
and 3 — rounding early is what turns a genuine 1.50 into a fake 1.5 you
cannot interpret.

**1.** A compound is found to be 40.0% carbon, 6.7% hydrogen, and 53.3%
oxygen by mass. Find its empirical formula.

> [!success]- Answer 1
> Take 100.0 g of the compound, so the percentages become grams
> directly. That assumption costs nothing, because a ratio does not care
> how much you started with.
>
> $\begin{aligned} n(\ce{C}) &= \frac{40.0}{12.01} = 3.3306 \text{ mol} \\ n(\ce{H}) &= \frac{6.7}{1.01} = 6.6337 \text{ mol} \\ n(\ce{O}) &= \frac{53.3}{16.00} = 3.3313 \text{ mol} \end{aligned}$
>
> Divide each by the smallest, which is 3.3306:
>
> $\begin{aligned} \ce{C} &: \frac{3.3306}{3.3306} = 1.000 \\ \ce{H} &: \frac{6.6337}{3.3306} = 1.992 \\ \ce{O} &: \frac{3.3313}{3.3306} = 1.000 \end{aligned}$
>
> **The empirical formula is $\ce{CH2O}$.**
>
> The hydrogen came out at 1.992 rather than exactly 2. That is a
> rounding of the input percentages, not a chemical fact — 6.7% is given
> to two significant figures, and two figures cannot produce a ratio
> good to four. A value within about a percent of a whole number is a
> whole number.

**2.** The compound in question 1 has a molar mass of 180.2 g/mol. Find
its molecular formula.

> [!success]- Answer 2
> The empirical formula gives the **ratio**; the molar mass gives the
> **size**. You need both, and neither one alone is enough.
>
> $M(\ce{CH2O}) = 12.01 + 2(1.01) + 16.00 = 30.03 \text{ g/mol}$
>
> $$\frac{180.2}{30.03} = 6.001$$
>
> So the molecule is six empirical units:
>
> **$\ce{C6H12O6}$**
>
> That is glucose. Notice that the empirical formula
> $\ce{CH2O}$ is also the empirical formula of formaldehyde,
> of acetic acid, and of ribose — all of which have the same carbon,
> hydrogen, and oxygen ratio and none of which is remotely the same
> substance. The ratio was never going to be enough on its own, which
> is exactly the point of [[Empirical and Molecular Formulas]].

**3.** A strip of magnesium of mass 0.486 g is heated in a crucible
until it will react no further. The product has a mass of 0.806 g. Find
the empirical formula of the product.

> [!success]- Answer 3
> The oxygen was never weighed directly. It is the difference, and
> saying so out loud is the whole trick of this style of question.
>
> $m(\ce{O}) = 0.806 \text{ g} - 0.486 \text{ g} = 0.320 \text{ g}$
>
> $\begin{aligned} n(\ce{Mg}) &= \frac{0.486}{24.31} = 0.019992 \text{ mol} \\ n(\ce{O}) &= \frac{0.320}{16.00} = 0.020000 \text{ mol} \end{aligned}$
>
> Divide both by the smaller, 0.019992:
>
> $\ce{Mg} : 1.000 \qquad \ce{O} : 1.000$
>
> **The empirical formula is $\ce{MgO}$.**
>
> Two things worth noticing. The oxygen mass, 0.320 g, is a difference
> of two measured masses, so its uncertainty is **larger** than either
> of theirs — differences of similar numbers always lose precision. And
> the answer is only trustworthy because the magnesium was heated until
> the mass stopped changing; a strip taken off the flame early would
> leave unreacted magnesium in the crucible, the oxygen difference would
> come out too small, and the formula would come out wrong in a
> predictable direction.

**4.** A sample of hydrated copper(II) sulfate has a mass of 4.99 g.
After heating to constant mass, 3.19 g of the anhydrous solid remains.
Find $x$ in $\ce{CuSO4} \cdot x\ce{H2O}$.

> [!success]- Answer 4
> $M(\ce{CuSO4}) = 63.55 + 32.07 + 4(16.00) = 159.62 \text{ g/mol}$
>
> $M(\ce{H2O}) = 18.02 \text{ g/mol}$
>
> The water lost is the difference in mass:
>
> $m(\ce{H2O}) = 4.99 - 3.19 = 1.80 \text{ g}$
>
> $\begin{aligned} n(\ce{CuSO4}) &= \frac{3.19}{159.62} = 0.019985 \text{ mol} \\ n(\ce{H2O}) &= \frac{1.80}{18.02} = 0.099889 \text{ mol} \end{aligned}$
>
> $$x = \frac{n(\ce{H2O})}{n(\ce{CuSO4})} = \frac{0.099889}{0.019985} = 4.998$$
>
> **$x = 5$, so the formula is $\ce{CuSO4 * 5H2O}$.**
>
> This is the calculation behind [[Finding an Empirical Formula]], and
> the reason $x$ must be a whole number is that the water sits at
> definite positions in the crystal. A result of 4.6 does not mean a
> compound with 4.6 waters exists; it means some of the water never
> left.

**5.** Ammonium nitrate, $\ce{NH4NO3}$, is used as a
fertiliser and its value depends on how much nitrogen it delivers.
Calculate its percentage composition.

> [!success]- Answer 5
> Build the molar mass, keeping track of **both** nitrogens — one in the
> ammonium, one in the nitrate.
>
> $M = 2(14.01) + 4(1.01) + 3(16.00) = 28.02 + 4.04 + 48.00 = 80.06 \text{ g/mol}$
>
> $\begin{aligned} \%\ce{N} &= \frac{28.02}{80.06} \times 100\% = 35.00\% \\ \%\ce{H} &= \frac{4.04}{80.06} \times 100\% = 5.046\% \\ \%\ce{O} &= \frac{48.00}{80.06} \times 100\% = 59.96\% \end{aligned}$
>
> Add them up as a check: $35.00 + 5.046 + 59.96 = 100.01\%$. The extra
> hundredth is rounding, not an error — the unrounded values sum to
> exactly 100%. If your total had come to 96% or 104%, you would have
> dropped or double-counted an atom, and the check would have caught it
> for free.
>
> **35.00% of the mass is nitrogen**, which is the number a farmer
> actually buys. Two fertilisers at the same price per kilogram are not
> the same purchase if their nitrogen percentages differ, and that
> comparison is exactly what percentage composition is for.

**6.** A 1.000 g sample of a compound of iron and chlorine contains
0.3444 g of iron. Find its empirical formula.

> [!success]- Answer 6
> $m(\ce{Cl}) = 1.000 - 0.3444 = 0.6556 \text{ g}$
>
> $\begin{aligned} n(\ce{Fe}) &= \frac{0.3444}{55.85} = 6.1665 \times 10^{-3} \text{ mol} \\ n(\ce{Cl}) &= \frac{0.6556}{35.45} = 1.8494 \times 10^{-2} \text{ mol} \end{aligned}$
>
> Divide both by the smaller:
>
> $\ce{Fe} : 1.000 \qquad \ce{Cl} : \frac{1.8494 \times 10^{-2}}{6.1665 \times 10^{-3}} = 2.999$
>
> **The empirical formula is $\ce{FeCl3}$**, iron(III) chloride.
>
> Sanity check with the chemistry you already have: iron(III) is
> $\ce{Fe^3+}$ and chloride is $\ce{Cl-}$, so a one-to-three
> ratio is exactly what charge balance predicts. When a formula from
> data agrees with a formula from charges, both are probably right, and
> when they disagree it is worth finding out which one to trust before
> writing anything down.

**7.** Ethyne and benzene both have the empirical formula
$\ce{CH}$.
(a) Explain why the empirical formula alone cannot distinguish them.
(b) Their molar masses are 26.04 g/mol and 78.12 g/mol. Find both
molecular formulas.
(c) What single measurement would you need to tell them apart?

> [!success]- Answer 7
> **(a)** An empirical formula is a **ratio**, and a ratio is
> deliberately blind to size. One carbon per hydrogen describes a
> molecule with two atoms of each, one with six of each, and one with a
> hundred of each, equally well. Everything the empirical formula knows
> is preserved when you scale the molecule up, so nothing it knows can
> tell you the scale.
>
> **(b)** $M(\ce{CH}) = 12.01 + 1.01 = 13.02 \text{ g/mol}$
>
> $\begin{aligned} \frac{26.04}{13.02} &= 2.000 \implies \ce{C2H2} \\ \frac{78.12}{13.02} &= 6.000 \implies \ce{C6H6} \end{aligned}$
>
> **(c)** The **molar mass**, and nothing else is needed. That is the
> whole content of the relationship between empirical and molecular
> formulas: the ratio comes from composition, the multiplier comes from
> the molar mass, and neither measurement can be substituted for the
> other.
>
> Worth being honest about the limits, though. Molar mass gives you the
> molecular formula and stops there. Two substances can share a
> molecular formula and be different compounds because the atoms are
> connected differently, and no mass measurement of any kind will
> separate those.

**8.** Three pieces of student work. Say what is wrong with each and
give the correct result.
*(a) "My percentages were 48.63% C, 8.18% H, 43.19% O. I divided by the
smallest and got C 1.50, H 3.00, O 1.00. I rounded the 1.50 up, so the
empirical formula is $\ce{C2H3O}$."*
*(b) "My ratio came out Fe 1.00 : O 1.33, so I rounded to
$\ce{FeO}$."*
*(c) "I found the empirical formula was $\ce{CH2}$, so the molecular
formula is $\ce{CH2}$."*

> [!success]- Answer 8
> **(a) 1.50 is not a rounding error — it is a signal.** A value that
> sits almost exactly halfway between two whole numbers is telling you
> that your unit is twice as big as it should be. Multiply **every**
> ratio by 2:
>
> $\ce{C} : 1.50 \times 2 = 3 \qquad \ce{H} : 3.00 \times 2 = 6 \qquad \ce{O} : 1.00 \times 2 = 2$
>
> **The empirical formula is $\ce{C3H6O2}$.**
>
> Two things went wrong at once. Rounding 1.50 to 2 changes the ratio by
> a third, which is far outside any experimental uncertainty. And the
> student multiplied only one of the three numbers, which changes the
> ratio rather than rescaling it — whatever you do, you do to all of
> them.
>
> **(b) Same signal, different fraction.** 1.33 is close to
> $\frac{4}{3}$, so multiply both by 3:
>
> $\ce{Fe} : 3 \qquad \ce{O} : 4$
>
> **The empirical formula is $\ce{Fe3O4}$**, which is a real
> and common iron oxide — so rounding 1.33 down to 1 did not just lose
> precision, it named a different substance that was also sitting right
> there on the shelf.
> The fractions worth recognising on sight are 0.50 (multiply by 2),
> 0.33 and 0.67 (by 3), and 0.25 and 0.75 (by 4). Anything else — 1.15,
> say — is not a fraction to be cleared and is usually a sign that a
> mass or a molar mass went in wrong.
>
> **(c) The conclusion has no support.** $\ce{CH2}$ is the empirical
> formula, and the molecular formula is $\ce{(CH2)_{n}}$ for some whole
> number $n$ that the composition data cannot determine. It could be
> $\ce{C2H4}$, $\ce{C3H6}$,
> $\ce{C4H8}$, and so on. To settle it you need the molar
> mass, exactly as in question 7. Assuming $n = 1$ because no other
> information was given is not a conservative choice — it is an
> unsupported claim wearing the clothes of one.

Reference: [[Empirical and Molecular Formulas]] and
[[Molar Mass and Composition]]. Doing it with a balance rather than with
given data: [[Finding an Empirical Formula]].

%%curriculum-start%%
## Curriculum connection

![[D2.4]]

![[D3.3]]
%%curriculum-end%%
