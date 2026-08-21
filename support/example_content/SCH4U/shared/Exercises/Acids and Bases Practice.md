---
title: Acids and Bases Practice
publish: true
created: __CREATED__
enableToc: false
tags:
  - chemistry
  - equilibrium
  - exercises
---
Everything on this page rests on one equilibrium, and it is the
equilibrium of water with itself:

$$\ce{2H2O(l) <=> H3O+(aq) + OH-(aq)}$$

$$K_w = [\ce{H3O+}][\ce{OH-}] = 1.0 \times 10^{-14}\ \text{at 25}\ ^\circ\text{C}$$

**The temperature matters and is not a formality.** $K_w$ is an
equilibrium constant like any other, so it changes with temperature —
above 25 °C it is larger, and neutral water then has a pH below 7. Every
question here is at 25 °C, and every question you meet elsewhere should
tell you.

The four relationships you will use constantly:

$$\text{pH} = -\log[\ce{H3O+}] \qquad \text{pOH} = -\log[\ce{OH-}] \qquad \text{pH} + \text{pOH} = 14.00 \qquad [\ce{H3O+}] = 10^{-\text{pH}}$$

**Significant figures in a logarithm work differently, and this catches
everybody once.** Only the digits **after** the decimal point in a pH
are significant. A concentration known to two significant figures gives
a pH quoted to two decimal places; three figures gives three decimals.
The "2" in pH 2.60 is not a significant figure at all — it is telling
you the power of ten. See
[[Working with Logarithms in Chemistry]].

**1.** A solution has $[\ce{H3O+}] = 2.5 \times 10^{-3}$
mol/L at 25 °C. Find its pH, its pOH, and $[\ce{OH-}]$.

> [!success]- Answer 1
> $\text{pH} = -\log(2.5 \times 10^{-3}) = 2.60$
>
> $\text{pOH} = 14.00 - 2.60 = 11.40$
>
> $[\ce{OH-}] = \frac{K_w}{[\ce{H3O+}]} = \frac{1.0 \times 10^{-14}}{2.5 \times 10^{-3}} = 4.0 \times 10^{-12}\ \text{mol/L}$
>
> **pH 2.60, pOH 11.40, $[\ce{OH-}] = 4.0 \times 10^{-12}$ mol/L.**
>
> **Two decimal places on the pH**, because $2.5 \times 10^{-3}$ has two
> significant figures. Writing 2.60206 would claim a precision the data
> does not support, and writing 2.6 would throw away a figure you had.
>
> **Check it by going backwards**, which takes five seconds:
> $10^{-2.60} = 2.5 \times 10^{-3}$ ✓
>
> **Hydroxide is present even in an acidic solution**, and that is the
> point of the last line. There is no such thing as a solution with no
> hydroxide in it. The water equilibrium guarantees that both ions are
> always present; what changes is the ratio, and $K_w$ fixes the product
> at every moment.

**2.** Find the pH of 0.0250 mol/L sodium hydroxide solution at 25 °C,
and the concentration of hydronium ion in it.

> [!success]- Answer 2
> Sodium hydroxide is a **strong base** — it dissociates completely, so
> there is no equilibrium to solve and no ICE table needed:
>
> $[\ce{OH-}] = 0.0250\ \text{mol/L}$
>
> $\text{pOH} = -\log(0.0250) = 1.602$
>
> $\text{pH} = 14.000 - 1.602 = 12.398$
>
> $[\ce{H3O+}] = \frac{1.0 \times 10^{-14}}{0.0250} = 4.0 \times 10^{-13}\ \text{mol/L}$
>
> **pH 12.398**, three decimals for three significant figures in the
> concentration.
>
> **Route check.** Two routes exist — via pOH as above, or via
> $[\ce{H3O+}]$ and then straight to pH. They must agree:
> $-\log(4.0 \times 10^{-13}) = 12.40$, which matches to the precision
> that a two-figure $K_w$ allows. Getting the same answer two ways is
> worth more than getting it once carefully.
>
> **The word "strong" is doing specific work here.** It means fully
> ionised, and nothing else. It does not mean concentrated. This
> solution is dilute and strongly basic at the same time, and question 5
> is where that distinction earns its keep.

**3.** A 0.100 mol/L solution of a weak monoprotic acid HA has a pH of
2.88 at 25 °C. Calculate $K_a$ and the percentage ionisation.

> [!success]- Answer 3
> $$\ce{HA(aq) + H2O(l) <=> A-(aq) + H3O+(aq)}$$
>
> From the pH:
> $[\ce{H3O+}] = 10^{-2.88} = 1.32 \times 10^{-3}\ \text{mol/L}$
>
> **The ICE table**, with $x$ the amount that ionised:
>
> | | $\ce{HA}$ | $\ce{A-}$ | $\ce{H3O+}$ |
> | --- | --- | --- | --- |
> | Initial | 0.100 | 0 | ~0 |
> | Change | $-x$ | $+x$ | $+x$ |
> | Equilibrium | $0.100 - x$ | $x$ | $x$ |
>
> The measured hydronium concentration **is** $x$, so
> $x = 1.32 \times 10^{-3}$ mol/L, and every other equilibrium
> concentration follows:
>
> $\begin{aligned} [\ce{A-}] &= 1.32 \times 10^{-3}\ \text{mol/L} \\ [\ce{HA}] &= 0.100 - 0.00132 = 0.0987\ \text{mol/L} \end{aligned}$
>
> $K_a = \frac{[\ce{A-}][\ce{H3O+}]}{[\ce{HA}]} = \frac{(1.32 \times 10^{-3})^2}{0.0987} = \frac{1.74 \times 10^{-6}}{0.0987} = 1.8 \times 10^{-5}$
>
> **$K_a = 1.8 \times 10^{-5}$**, two significant figures, because the
> pH was given to two decimal places.
>
> **Percentage ionisation:**
> $\frac{1.32 \times 10^{-3}}{0.100} \times 100 = 1.3\%$
>
> **What those two numbers are telling you.** Only about one molecule in
> seventy-five has given up its proton at any instant. The other
> seventy-four are sitting there intact — which is the whole meaning of
> "weak", stated as a measurement rather than as a label.
>
> Compare with your data booklet. A $K_a$ near $1.8 \times 10^{-5}$ is
> consistent with ethanoic acid, and this measurement on its own cannot
> distinguish it from any other acid with a similar constant. The route
> here is exactly the one used at the bench in
> [[Disturbing an Equilibrium]].

**4.** A weak acid has $K_a = 1.8 \times 10^{-5}$. Find the pH of a
0.250 mol/L solution of it at 25 °C.

> [!success]- Answer 4
> This is question 3 run backwards, and it needs the small-$x$
> approximation and the check that goes with it.
>
> | | $\ce{HA}$ | $\ce{A-}$ | $\ce{H3O+}$ |
> | --- | --- | --- | --- |
> | Initial | 0.250 | 0 | ~0 |
> | Change | $-x$ | $+x$ | $+x$ |
> | Equilibrium | $0.250 - x$ | $x$ | $x$ |
>
> $K_a = \frac{x^2}{0.250 - x} = 1.8 \times 10^{-5}$
>
> $K_a$ is small, so assume $x \ll 0.250$ and therefore
> $0.250 - x \approx 0.250$:
>
> $x^2 = (1.8 \times 10^{-5})(0.250) = 4.5 \times 10^{-6}$
>
> $x = 2.1 \times 10^{-3}\ \text{mol/L}$
>
> **Apply the 5% test before going any further:**
>
> $\frac{2.1 \times 10^{-3}}{0.250} \times 100 = 0.85\%$
>
> Comfortably under 5%, so the approximation stands and the quadratic is
> not needed.
>
> $\text{pH} = -\log(2.1 \times 10^{-3}) = 2.67$
>
> **pH 2.67.**
>
> **Do the test every time, and report it.** In question 5 of
> [[Equilibrium Practice]] the same approximation failed on a system
> that looked just as safe, and it failed by an amount small enough that
> nobody would have noticed. The check is one division.
>
> **Sanity check on the size:** a strong acid at 0.250 mol/L would have
> pH 0.60. This weak acid comes in two whole pH units higher, which is a
> factor of about a hundred in hydronium concentration, and that is what
> "weak" buys you.

**5.** Compare 0.100 mol/L hydrochloric acid with 0.100 mol/L ethanoic
acid ($K_a = 1.8 \times 10^{-5}$) at 25 °C. Which has the lower pH?
Which needs more sodium hydroxide to neutralise a 25.00 mL sample? Use
dynamic equilibrium to explain why those two answers are not the same.

> [!success]- Answer 5
> **Hydrochloric acid** is strong, so it ionises completely:
>
> $[\ce{H3O+}] = 0.100\ \text{mol/L} \quad \Rightarrow \quad \text{pH} = 1.000$
>
> **Ethanoic acid** is weak. With the approximation, tested as in
> question 4:
>
> $x = \sqrt{(1.8 \times 10^{-5})(0.100)} = 1.3 \times 10^{-3}\ \text{mol/L}$
>
> $\frac{1.3 \times 10^{-3}}{0.100} \times 100 = 1.3\%$, under 5% ✓
>
> $\text{pH} = -\log(1.3 \times 10^{-3}) = 2.87$
>
> **The hydrochloric acid has by far the lower pH** — 1.000 against
> 2.87, which is a factor of about 75 in hydronium concentration.
>
> **Both need exactly the same amount of sodium hydroxide.** Each 25.00
> mL sample contains
> $(0.100\ \text{mol/L})(0.02500\ \text{L}) = 2.50 \times 10^{-3}$ mol
> of acid, each reacts one-to-one with hydroxide, so each needs
> $2.50 \times 10^{-3}$ mol of base — **25.00 mL of 0.100 mol/L sodium
> hydroxide** in both cases.
>
> **Why the two answers differ, in terms of equilibrium.** pH measures
> the hydronium ion **present right now**. Neutralisation consumes every
> proton the acid can **eventually supply**. In the ethanoic acid, 98.7%
> of the protons are still attached to their molecules at any instant —
> but as hydroxide removes the free hydronium, the equilibrium
>
> $$\ce{CH3COOH(aq) + H2O(l) <=> CH3COO-(aq) + H3O+(aq)}$$
>
> responds by shifting right and releasing more. The reservoir empties
> completely, one small portion at a time.
>
> **This is the distinction between *strong* and *concentrated*, and it
> is the one worth being able to explain in a sentence.** Strong is
> about the **fraction** ionised; concentrated is about the **amount**
> present. A dilute strong acid can have a higher pH than a
> concentrated weak one, and the weak one can still neutralise far more
> base.

**6.** 25.00 mL of 0.100 mol/L ethanoic acid is titrated with 0.100
mol/L sodium hydroxide. Find the volume needed to reach the equivalence
point, and calculate the pH there. Which indicator is appropriate, and
why is methyl orange not?

> [!success]- Answer 6
> **Volume at equivalence.** Moles of acid:
> $(0.100)(0.02500) = 2.50 \times 10^{-3}$ mol. One-to-one, so
> $2.50 \times 10^{-3}$ mol of base is needed:
>
> $V = \frac{2.50 \times 10^{-3}\ \text{mol}}{0.100\ \text{mol/L}} = 0.02500\ \text{L} = 25.00\ \text{mL}$
>
> **The pH at the equivalence point is not 7.** At equivalence, all the
> ethanoic acid has been converted to ethanoate ion, and ethanoate is
> the **conjugate base of a weak acid**, so it reacts with water:
>
> $$\ce{CH3COO-(aq) + H2O(l) <=> CH3COOH(aq) + OH-(aq)}$$
>
> Concentration of ethanoate: $2.50 \times 10^{-3}$ mol in a total
> volume of $25.00 + 25.00 = 50.00$ mL:
>
> $[\ce{CH3COO-}] = \frac{2.50 \times 10^{-3}\ \text{mol}}{0.05000\ \text{L}} = 0.0500\ \text{mol/L}$
>
> $K_b = \frac{K_w}{K_a} = \frac{1.0 \times 10^{-14}}{1.8 \times 10^{-5}} = 5.6 \times 10^{-10}$
>
> $x = \sqrt{K_b \times 0.0500} = \sqrt{(5.6 \times 10^{-10})(0.0500)} = 5.3 \times 10^{-6}\ \text{mol/L}$
>
> $\text{pOH} = -\log(5.3 \times 10^{-6}) = 5.28 \quad \Rightarrow \quad \text{pH} = 14.00 - 5.28 = 8.72$
>
> **pH 8.72 at the equivalence point — basic.**
>
> **Do not forget the dilution.** The acid was diluted from 25.00 mL to
> 50.00 mL by the base added, so the ethanoate concentration is 0.0500
> mol/L and not 0.100. Skipping that halves nothing dramatic here, but
> it is the standard way this calculation goes wrong.
>
> **Indicator choice follows from the pH.** Phenolphthalein changes over
> roughly pH 8.3 to 10, which brackets 8.72 nicely. **Methyl orange
> changes over roughly pH 3.1 to 4.4**, which is far below the
> equivalence point — it would turn while a substantial amount of acid
> was still unreacted, and the titre would come out badly low.
>
> **The general rule, worth carrying:** the equivalence point of a weak
> acid against a strong base is **above** pH 7; a strong acid against a
> strong base is at 7; a strong acid against a weak base is **below** 7.
> Choose the indicator to match the equivalence pH, not the other way
> round.

**7.** In the same titration, what is the pH after exactly 12.50 mL of
sodium hydroxide has been added, and what is special about that point?

> [!success]- Answer 7
> 12.50 mL is **half** the volume needed to reach equivalence, so half
> the ethanoic acid has been converted to ethanoate.
>
> $\begin{aligned} \text{acid remaining} &= 1.25 \times 10^{-3}\ \text{mol} \\ \text{ethanoate formed} &= 1.25 \times 10^{-3}\ \text{mol} \end{aligned}$
>
> Both are in the same solution, so whatever the total volume is, their
> **concentrations are equal**.
>
> $K_a = \frac{[\ce{A-}][\ce{H3O+}]}{[\ce{HA}]}$, and
> with $[\ce{A-}] = [\ce{HA}]$ those two cancel, leaving
> $[\ce{H3O+}] = K_a$ exactly.
>
> $\text{pH} = -\log(1.8 \times 10^{-5}) = 4.74$
>
> **pH 4.74 — and it equals $\text{p}K_a$.**
>
> **Why this point is worth knowing.** It gives you a way to measure
> $K_a$ from a titration curve with no calculation at all: find the
> volume at the equivalence point, halve it, and read the pH. That
> reading is $\text{p}K_a$.
>
> **And it is where the buffering is strongest.** With substantial
> amounts of both the weak acid and its conjugate base present, added
> acid is absorbed by the ethanoate and added base is absorbed by the
> ethanoic acid. The titration curve is at its flattest here — you can
> see it on the graph as the long shallow stretch before the sharp rise.
>
> The same idea, written as the Henderson–Hasselbalch equation:
>
> $$\text{pH} = \text{p}K_a + \log\frac{[\ce{A-}]}{[\ce{HA}]}$$
>
> When the ratio is 1 the logarithm is 0 and the pH is $\text{p}K_a$,
> which is the result above. This equation is the design tool for
> [[The Buffer Design]], and question 7 is where it comes from.

**8.** Four claims from a study group. Correct each.
*(a) "A solution of pH 3 is twice as acidic as one of pH 6."*
*(b) "This acid is concentrated, so it is a strong acid."*
*(c) "The equivalence point of a titration is where the pH is 7."*
*(d) "Diluting a weak acid makes it weaker, because a smaller fraction
of it ionises."*

> [!success]- Answer 8
> **(a) The scale is logarithmic, so the factor is a thousand.**
>
> $\begin{aligned} \text{pH } 3: \quad [\ce{H3O+}] &= 1 \times 10^{-3}\ \text{mol/L} \\ \text{pH } 6: \quad [\ce{H3O+}] &= 1 \times 10^{-6}\ \text{mol/L} \end{aligned}$
>
> The ratio is $10^{3}$, so the pH 3 solution has **one thousand
> times** the hydronium concentration, not twice it. Each whole pH unit
> is a factor of ten, which is exactly what the logarithm in the
> definition is doing.
>
> The scale exists because concentrations in this field span more than
> fourteen orders of magnitude, and a linear axis cannot show that. The
> price of the convenience is that differences on the scale are
> **ratios** in reality, and forgetting it makes everything look far
> closer together than it is.
>
> **(b) Two different words for two different things.** **Strong**
> describes the **fraction** that ionises — complete, for a strong acid.
> **Concentrated** describes **how much** is dissolved per litre.
>
> All four combinations exist. Question 5 has a dilute strong acid and a
> dilute weak one at the same concentration, and their pH values differ
> by nearly two units. A concentrated weak acid can be a great deal less
> corrosive than a dilute strong one, and confusing these two words is
> a laboratory safety problem before it is a marking problem.
>
> **(c) Only for a strong acid with a strong base.** The equivalence
> point is where **stoichiometrically equivalent** amounts have been
> added — not where the pH is 7. What sits in the flask at that moment
> decides the pH.
>
> | Titration | What is in the flask at equivalence | pH there |
> | --- | --- | --- |
> | Strong acid + strong base | A neutral salt | 7 |
> | Weak acid + strong base | The conjugate **base** of the weak acid | **Above 7** |
> | Strong acid + weak base | The conjugate **acid** of the weak base | **Below 7** |
>
> Question 6 worked one out at 8.72. Assuming 7 there would have led to
> methyl orange and a titre several millilitres short.
>
> **(d) The conclusion is wrong and, awkwardly, the observation is
> right.** Diluting a weak acid **does** increase the percentage that
> ionises — the equilibrium shifts toward the side with more particles
> as the solution becomes more dilute. So the student's stated fact is
> backwards as well as their conclusion.
>
> More importantly, **"weak" is not a property you can change by adding
> water.** It is a statement about $K_a$, and $K_a$ depends only on what
> the acid is and on the temperature. Dilution changes concentrations,
> raises the pH toward 7, and increases percentage ionisation. It does
> not touch $K_a$, and an acid does not become a different acid because
> you diluted it.
>
> This is the same rule as in [[Equilibrium Practice]], applied to a
> different constant: **an equilibrium constant depends on temperature
> and on nothing else.**

Reference: [[Acids and Bases]] and
[[Buffers and Titration Curves]]. The logarithm mechanics:
[[Working with Logarithms in Chemistry]]. Measuring a $K_a$ at the
bench: [[Disturbing an Equilibrium]]. Where question 7 is going:
[[The Buffer Design]].

%%curriculum-start%%
## Curriculum connection

![[E2.5]]

![[E3.5]]

![[E3.6]]

![[E3.7]]
%%curriculum-end%%
