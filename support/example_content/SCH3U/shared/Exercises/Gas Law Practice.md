---
title: Gas Law Practice
publish: true
created: __CREATED__
tags:
  - chemistry
  - exercises
---
One rule governs this whole page and there are no exceptions to it:
**every temperature is in kelvins**, converted the moment you write it
down. $T(\text{K}) = T(^\circ\text{C}) + 273.15$. The gas laws are
proportionalities, and a proportionality needs a scale whose zero means
none of the quantity. Celsius zero is the freezing point of water, which
is a fact about water and not about gases.

The relationships you need:

$$\frac{P_1V_1}{T_1} = \frac{P_2V_2}{T_2} \qquad PV = nRT$$

with $R = 8.314 \text{ kPa} \cdot \text{L} / (\text{mol} \cdot \text{K})$
when pressure is in kilopascals and volume in litres.

**Conditions used on this page**, because a molar volume quoted without
its conditions is not a number:

| Name | Temperature | Pressure | Molar volume of an ideal gas |
| --- | --- | --- | --- |
| STP | 0 °C, which is 273.15 K | 101.325 kPa | 22.4 L/mol |
| SATP | 25 °C, which is 298.15 K | 100 kPa | 24.8 L/mol |

Some textbooks define STP with a pressure of 100 kPa instead, where the
molar volume works out to 22.7 L/mol. Check which convention a question
is using before you take a molar volume from memory.

**1.** A gas occupies 250.0 mL at 101.3 kPa. What volume does it occupy
at 152.0 kPa, at constant temperature?

> [!success]- Answer 1
> Temperature is constant, so it cancels from both sides of the combined
> law and what is left is Boyle's law, $P_1V_1 = P_2V_2$.
>
> $V_2 = \frac{P_1V_1}{P_2} = \frac{(101.3 \text{ kPa})(250.0 \text{ mL})}{152.0 \text{ kPa}} = 166.6 \text{ mL}$
>
> **166.6 mL.**
>
> The volumes may stay in millilitres because they appear on both sides
> and cancel. Temperature never gets that privilege, because it appears
> as a ratio of absolute values.
>
> Sanity check first, every time: the pressure went **up**, so the
> volume must come **down**. If your answer had been larger than
> 250.0 mL you inverted the fraction, and the check takes two seconds
> against the several minutes of a redone question.

**2.** A balloon has a volume of 2.00 L at 20.0 °C. What is its volume
at 80.0 °C, at constant pressure? What answer would you get by using
degrees Celsius directly, and why is it wrong?

> [!success]- Answer 2
> Convert both temperatures before anything else:
>
> $T_1 = 20.0 + 273.15 = 293.15 \text{ K} \qquad T_2 = 80.0 + 273.15 = 353.15 \text{ K}$
>
> Pressure is constant, so $\frac{V_1}{T_1} = \frac{V_2}{T_2}$:
>
> $V_2 = V_1 \times \frac{T_2}{T_1} = (2.00 \text{ L}) \times \frac{353.15}{293.15} = 2.409 \text{ L}$
>
> **2.41 L.**
>
> **Using Celsius** you would compute
> $2.00 \times \frac{80.0}{20.0} = 8.00$ L — four times the original
> volume rather than a twenty per cent increase. The answer is wrong by
> a factor of more than three, and nothing about 8.00 L looks obviously
> absurd, which is what makes this error dangerous.
>
> The reason it fails: the ratio $\frac{80.0}{20.0}$ claims that 80 °C
> is "four times as hot" as 20 °C. It is not four times anything. On the
> absolute scale the two temperatures differ by only twenty per cent,
> and twenty per cent is what the balloon does. Had the first
> temperature been 0 °C, the Celsius method would have asked you to
> divide by zero, which is the scale telling you rather loudly that it
> is not the right one for ratios.

**3.** A gas occupies 500.0 mL at 25.0 °C and 98.0 kPa. What volume
would it occupy at STP?

> [!success]- Answer 3
> Both pressure and temperature change, so this is the combined law.
> Rearranged for $V_2$:
>
> $$V_2 = V_1 \times \frac{P_1}{P_2} \times \frac{T_2}{T_1}$$
>
> $T_1 = 298.15 \text{ K}$, and STP is $T_2 = 273.15$ K and
> $P_2 = 101.325$ kPa.
>
> $\begin{aligned} V_2 &= (500.0 \text{ mL}) \times \frac{98.0}{101.325} \times \frac{273.15}{298.15} \\ &= (500.0)(0.96718)(0.91615) = 443.0 \text{ mL} \end{aligned}$
>
> **443 mL**, to three significant figures — the pressure was given to
> three, and that is the ceiling.
>
> Both changes push the same way here, which is a useful check. Raising
> the pressure squeezes the gas smaller, and lowering the temperature
> shrinks it further, so the answer had to come out below 500.0 mL. If
> only one factor had gone that way you would want to look at which
> effect was larger before trusting the sign of the change.

**4.** What mass of oxygen is contained in a 5.00 L cylinder at 25.0 °C
and 850. kPa?

> [!success]- Answer 4
> This one needs the amount of gas, not just a before and after, so it
> is the ideal gas law.
>
> $T = 25.0 + 273.15 = 298.15 \text{ K}$
>
> $n = \frac{PV}{RT} = \frac{(850. \text{ kPa})(5.00 \text{ L})}{(8.314)(298.15)} = \frac{4250}{2478.8} = 1.7146 \text{ mol}$
>
> Oxygen as a gas is $\ce{O2}$, so $M = 32.00$ g/mol:
>
> $m = nM = (1.7146 \text{ mol})(32.00 \text{ g/mol}) = 54.87 \text{ g}$
>
> **54.9 g of oxygen.**
>
> The units are the whole reason this works. Kilopascals times litres
> divided by kilopascal-litres per mole-kelvin, times kelvins, leaves
> moles. Use a pressure in atmospheres with this value of $R$ and the
> answer is out by a factor of about a hundred — so check that your
> pressure unit matches your gas constant before you press equals.
>
> Writing the pressure as "850." with the decimal point is deliberate:
> it says three significant figures rather than two.

**5.** What volume of hydrogen, measured at STP, is produced when
0.500 g of magnesium reacts with excess dilute hydrochloric acid?

> [!success]- Answer 5
> $$\ce{Mg + 2HCl -> MgCl2 + H2}$$
>
> $n(\ce{Mg}) = \frac{0.500 \text{ g}}{24.31 \text{ g/mol}} = 0.020568 \text{ mol}$
>
> The mole ratio of magnesium to hydrogen is 1 to 1, so
> $n(\ce{H2}) = 0.020568$ mol. At STP the molar volume is 22.4 L/mol:
>
> $V = (0.020568 \text{ mol})(22.4 \text{ L/mol}) = 0.4607 \text{ L}$
>
> **0.461 L, which is 461 mL.**
>
> Half a gram of ribbon produces the better part of half a litre of gas.
> That is the reason gas volumes are a convenient thing to measure in a
> school lab — the quantity is large and easy to read, where the
> corresponding **mass** of hydrogen is only about 0.0415 g and sits
> right at the edge of a school balance's resolution. This calculation
> is exactly what you are doing in [[Measuring a Gas Law]], run
> backwards.
>
> And note the phrase "measured at STP" doing real work. Without it the
> question has no answer, because the same amount of gas occupies
> different volumes under different conditions.

**6.** Propane burns:
$\ce{C3H8 + 5O2 -> 3CO2 + 4H2O}$.
At SATP, what volume of oxygen is needed to burn 10.0 L of propane, and
what volume of carbon dioxide is produced? What about the water?

> [!success]- Answer 6
> No molar masses and no moles are needed, and seeing why is the point
> of the question.
>
> At a fixed temperature and pressure, equal volumes of any gas contain
> equal numbers of particles — that falls straight out of $PV = nRT$,
> since $V$ and $n$ are proportional when $P$, $T$, and $R$ are all
> fixed. So for gases at the same conditions, **the coefficient ratio is
> a volume ratio directly**.
>
> $\begin{aligned} V(\ce{O2}) &= 10.0 \text{ L} \times \frac{5}{1} = 50.0 \text{ L} \\ V(\ce{CO2}) &= 10.0 \text{ L} \times \frac{3}{1} = 30.0 \text{ L} \end{aligned}$
>
> **50.0 L of oxygen, producing 30.0 L of carbon dioxide.**
>
> **The water is the trap.** The shortcut only works for **gases**, and
> at SATP — 25 °C — water is a **liquid**. So the answer is not 40.0 L.
> The 4 moles of water per mole of propane would occupy about 40 L as a
> vapour at these conditions and instead occupy roughly 40 **millilitres**
> as a liquid, a thousandfold difference.
>
> This is not a technicality invented for exams. It is why a cold car
> exhaust drips water on a driveway and a hot one does not, and it is
> why the volume of exhaust gas leaving an engine depends on how hot the
> pipe is.

**7.** A 0.250 L flask holds 0.349 g of an unknown gas at 100.0 °C and
98.5 kPa. Find its molar mass, and suggest what the gas might be.

> [!success]- Answer 7
> $T = 100.0 + 273.15 = 373.15 \text{ K}$
>
> $n = \frac{PV}{RT} = \frac{(98.5)(0.250)}{(8.314)(373.15)} = \frac{24.625}{3102.4} = 7.9375 \times 10^{-3} \text{ mol}$
>
> $M = \frac{m}{n} = \frac{0.349 \text{ g}}{7.9375 \times 10^{-3} \text{ mol}} = 43.97 \text{ g/mol}$
>
> **44.0 g/mol**, to three significant figures.
>
> **What it might be.** Carbon dioxide has a molar mass of 44.01 g/mol,
> which is an excellent match. But be careful how you say it: dinitrogen
> monoxide is 44.02 g/mol and propane is 44.11 g/mol, and this
> measurement cannot separate any of the three. The honest conclusion is
> **"a molar mass of 44.0 g/mol, consistent with carbon dioxide among
> others"**, and identifying it would take a chemical test rather than a
> better balance.
>
> This is how molar masses of gases were determined before instruments,
> and it is what you are doing from the other end in
> [[Measuring a Gas Law]] — there you know the substance and measure the
> molar volume; here you assume the molar volume behaviour and measure
> the substance.

**8.** Three claims from a study group. Correct each.
*(a) "Going from 25 °C to 50 °C doubles the Celsius temperature, so at
constant pressure the volume doubles."*
*(b) "Pressure and volume are directly proportional — squeezing a gas
raises its pressure, so they go up together."*
*(c) "One mole of any substance occupies 22.4 L at STP, so one mole of
water occupies 22.4 L."*

> [!success]- Answer 8
> **(a) Celsius ratios are meaningless.** In kelvins the change is from
> 298.15 K to 323.15 K:
>
> $\frac{323.15}{298.15} = 1.0839$
>
> so the volume increases by about **8.4%**, not by 100%. The student's
> method overstates the change by more than a factor of ten.
>
> The reason is that the Celsius scale has an offset zero. A ratio only
> means something on a scale where zero corresponds to none of the
> quantity, and the only such scale for temperature is the absolute one.
>
> **(b) Inversely proportional, and the student's own evidence says
> so.** Squeezing a gas means **reducing** its volume, and the pressure
> **rises** — so one goes up while the other goes down, which is the
> definition of inverse. Boyle's law is $P_1V_1 = P_2V_2$, meaning the
> product stays constant, not the ratio.
>
> A quick test whenever you are unsure which way a relationship runs:
> plot it in your head. A directly proportional relationship gives a
> straight line through the origin; an inverse one gives a curve
> approaching both axes. A gas squeezed to half its volume doubles its
> pressure, and squeezed to a tenth it goes to ten times — that curve,
> not that line.
>
> **(c) The molar volume applies to gases, and only to gases.** At STP,
> 0 °C, water is a **liquid** — indeed it is at or below its freezing
> point. One mole of water is 18.02 g, and as a liquid that occupies
> about 18 mL, which is roughly a thousand times smaller than 22.4 L.
>
> The reason 22.4 L/mol works for *any* gas is that the volume of a gas
> is overwhelmingly empty space, so the size of the individual particles
> barely matters. In a liquid or a solid the particles are in contact,
> so the volume depends entirely on what the substance is, and there is
> no universal molar volume to quote.
>
> The general lesson: check the **state** of every substance before
> applying a gas law to it. Half of the difficult questions in this unit
> are difficult only because one of the substances is not a gas.

Reference: [[The Gas Laws]] and [[Gases and the Atmosphere]]. Measuring
these relationships yourself: [[Measuring a Gas Law]].

%%curriculum-start%%
## Curriculum connection

![[F2.1]]

![[F2.3]]

![[F2.4]]

![[F3.3]]
%%curriculum-end%%
