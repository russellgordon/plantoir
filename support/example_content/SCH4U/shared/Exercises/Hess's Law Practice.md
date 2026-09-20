---
title: Hess's Law Practice
publish: true
created: __CREATED__
enableToc: false
tags:
  - chemistry
  - exercises
---
Every question on this page is the same question in a different costume:
**how do I build the equation I want out of the equations I have?**

Two operations are allowed, and they are the only two:

| Operation | What happens to the equation | What happens to $\Delta H$ |
| --- | --- | --- |
| **Reverse it** | Reactants and products swap | Sign flips |
| **Multiply by $n$** | Every coefficient is multiplied by $n$ | $\Delta H$ is multiplied by $n$ |

Then add the equations up and cancel anything that appears identically
on both sides. Whatever survives is your target, and the sum of the
adjusted $\Delta H$ values is your answer.

The working method that prevents almost every error: **write the target
equation at the top of the page first**, then look at each given
equation and ask "where does this substance need to end up, and how many
of it?" Decide the operation before you touch the numbers. People who
manipulate the numbers first and check the equations afterwards get the
right magnitude with the wrong sign roughly half the time.

Values given inside a question are given so that everyone works from the
same ones. Anything else comes from the data booklet.

**1.** State Hess's law, and explain why it is true. Then: given that
$\ce{H2O(l) -> H2O(g)}$ has
$\Delta H = +44.0$ kJ, what is $\Delta H$ for
$\ce{2H2O(g) -> 2H2O(l)}$?

> [!success]- Answer 1
> **Hess's law:** the enthalpy change for a reaction is the same
> whatever route is taken from reactants to products, provided the
> starting and finishing conditions are the same.
>
> **Why it is true:** enthalpy is a **state function**. Its value
> depends only on the state a system is in, not on how the system got
> there. So the difference between a starting state and a finishing
> state is fixed by those two states alone, and any route that connects
> them must show the same difference.
>
> The everyday version: the difference in altitude between the bottom
> and the top of a hill does not depend on which path you walked. The
> *effort* does — a steep path is harder — but the altitude change does
> not. Enthalpy is the altitude. It is not the effort.
>
> **For the water:** two operations, applied in either order.
>
> $\begin{aligned} \text{Reverse:}\quad \ce{H2O(g)} &\ce{-> H2O(l)} & \Delta H &= -44.0\ \text{kJ} \\ \text{Multiply by 2:}\quad \ce{2H2O(g)} &\ce{-> 2H2O(l)} & \Delta H &= -88.0\ \text{kJ} \end{aligned}$
>
> **$\Delta H = -88.0$ kJ.**
>
> Both changes make sense before you check the arithmetic. Condensing is
> the reverse of evaporating, so it must release energy where
> evaporating absorbed it, hence the negative sign. And twice as much
> water releases twice as much energy, because enthalpy is
> **extensive** — it scales with amount.
>
> Hold on to that last property. It is true of $\Delta H$, and in Unit 5
> you will meet a quantity that looks similar and is **not** extensive,
> where multiplying the equation must not multiply the number. Knowing
> which is which is worth several marks a year.

**2.** Find $\Delta H$ for
$\ce{C(s)} + \tfrac{1}{2}\ce{O2(g) -> CO(g)}$
from:

$\text{(1)}\ \ce{C(s) + O2(g) -> CO2(g)} \qquad \Delta H_1 = -393.5\ \text{kJ}$

$\text{(2)}\ \ce{CO(g)} + \tfrac{1}{2}\ce{O2(g) -> CO2(g)} \qquad \Delta H_2 = -283.0\ \text{kJ}$

> [!success]- Answer 2
> Target: carbon on the left, carbon monoxide on the right.
>
> Equation (1) already has carbon on the left, so keep it as it is.
> Equation (2) has carbon monoxide on the **left** and the target needs
> it on the right, so **reverse** (2) and flip its sign.
>
> $\begin{aligned} \ce{C(s) + O2(g)} &\ce{-> CO2(g)} & \Delta H &= -393.5\ \text{kJ} \\ \ce{CO2(g)} &\ce{-> CO(g)} + \tfrac{1}{2}\ce{O2(g)} & \Delta H &= +283.0\ \text{kJ} \end{aligned}$
>
> Add them. $\ce{CO2}$ appears on the right of the first and the left
> of the second, so it cancels completely. On the oxygen: one whole
> $\ce{O2}$ goes in on the left and half comes back out on the right,
> leaving $\tfrac{1}{2}\ce{O2}$ on the left.
>
> $$\ce{C(s)} + \tfrac{1}{2}\ce{O2(g) -> CO(g)}$$
>
> $\Delta H = -393.5 + 283.0 = -110.5\ \text{kJ}$
>
> **$\Delta H = -110.5$ kJ.**
>
> **Why this question exists at all.** You cannot measure this one
> directly. Burn carbon in a limited supply of oxygen and you get a
> mixture of carbon monoxide and carbon dioxide in proportions you
> cannot control, so there is no experiment that produces pure carbon
> monoxide and nothing else. Hess's law gets you a number for a reaction
> that cannot be run cleanly, from two that can — and that, rather than
> exam questions, is what the law is for.
>
> **The sanity check:** $-110.5$ kJ is less negative than $-393.5$ kJ,
> which it must be, because going all the way to carbon dioxide has to
> release more energy than stopping halfway.

**3.** Find $\Delta H$ for
$\ce{2NO(g) + O2(g) -> 2NO2(g)}$
from:

$\text{(1)}\ \tfrac{1}{2}\ce{N2(g)} + \tfrac{1}{2}\ce{O2(g) -> NO(g)} \qquad \Delta H_1 = +90.3\ \text{kJ}$

$\text{(2)}\ \tfrac{1}{2}\ce{N2(g) + O2(g) -> NO2(g)} \qquad \Delta H_2 = +33.2\ \text{kJ}$

> [!success]- Answer 3
> The target has **two** $\ce{NO2}$ on the right, so (2) is
> multiplied by 2. It has **two** $\ce{NO}$ on the left, and (1) makes
> $\ce{NO}$ on the right, so (1) is reversed **and** multiplied by 2.
>
> $\begin{aligned} 2 \times \text{(2)}:\quad \ce{N2(g) + 2O2(g)} &\ce{-> 2NO2(g)} & \Delta H &= 2(+33.2) = +66.4\ \text{kJ} \\ 2 \times \text{reverse (1)}:\quad \ce{2NO(g)} &\ce{-> N2(g) + O2(g)} & \Delta H &= 2(-90.3) = -180.6\ \text{kJ} \end{aligned}$
>
> Add. $\ce{N2}$ cancels completely. Oxygen: $\ce{2O2}$ in on the
> left, $\ce{O2}$ out on the right, leaving one $\ce{O2}$ on the
> left.
>
> $$\ce{2NO(g) + O2(g) -> 2NO2(g)}$$
>
> $\Delta H = +66.4 - 180.6 = -114.2\ \text{kJ}$
>
> **$\Delta H = -114.2$ kJ.**
>
> **The order of operations matters and the sign is where it shows.**
> Reverse first, then multiply, or multiply first, then reverse —
> either gives $-180.6$ kJ. What does not work is multiplying by 2 and
> then forgetting the reversal, which gives $+180.6$ and an answer of
> $-114.2$ turned into $+247.0$. Write both steps as separate lines, as
> above, and the error becomes visible instead of invisible.
>
> Notice that both given reactions are **endothermic** and the target is
> **exothermic**. There is nothing strange about that. You have not
> combined two uphill journeys into a downhill one; you have gone up one
> hill and back down a taller one.

**4.** Using the standard enthalpies of formation below, calculate
$\Delta H$ for the complete combustion of methane:
$\ce{CH4(g) + 2O2(g) -> CO2(g) + 2H2O(l)}$

| Substance | $\Delta H_f$ (kJ/mol) |
| --- | --- |
| $\ce{CH4(g)}$ | $-74.6$ |
| $\ce{CO2(g)}$ | $-393.5$ |
| $\ce{H2O(l)}$ | $-285.8$ |
| $\ce{O2(g)}$ | $0$ |

> [!success]- Answer 4
> The shortcut form of Hess's law, which is what a formation table is
> for:
>
> $$\Delta H = \sum \Delta H_f(\text{products}) - \sum \Delta H_f(\text{reactants})$$
>
> **Multiply each value by its coefficient** — this is the step people
> skip, and here the water has a coefficient of 2.
>
> $\begin{aligned} \Delta H &= \left[ (-393.5) + 2(-285.8) \right] - \left[ (-74.6) + 2(0) \right] \\ &= \left[ -393.5 - 571.6 \right] - \left[ -74.6 \right] \\ &= -965.1 + 74.6 \\ &= -890.5\ \text{kJ} \end{aligned}$
>
> **$\Delta H = -890.5$ kJ per mole of methane.**
>
> **Oxygen is zero, and it is zero for a reason rather than by
> convention-for-convenience.** The enthalpy of formation of an element
> in its standard state is defined as zero, because "forming
> $\ce{O2}$ from $\ce{O2}$" involves no change at all. So elements
> in their standard states drop out of every calculation — but only in
> their standard states. $\ce{O3}$ is not zero, and neither is
> monatomic oxygen.
>
> **Products minus reactants, in that order.** Reversing it gives
> $+890.5$ kJ, which claims that burning methane absorbs energy. A
> two-second check against the world — a gas flame heats things —
> catches it.

**5.** Define *formation reaction*, and write the formation equation for
liquid ethanol. Then, given
$\Delta H_f[\ce{C2H5OH(l)}] = -277.6$ kJ/mol along
with the values in question 4, find the enthalpy of combustion of
ethanol.

> [!success]- Answer 5
> **A formation reaction** produces exactly **one mole** of a substance
> from its constituent **elements in their standard states**. The "one
> mole" is not optional, which is why fractional coefficients are
> normal and correct in these equations.
>
> For liquid ethanol, the elements are carbon as graphite, hydrogen as
> $\ce{H2}$ gas, and oxygen as $\ce{O2}$ gas:
>
> $$\ce{2C(s) + 3H2(g)} + \tfrac{1}{2}\ce{O2(g) -> C2H5OH(l)}$$
>
> Balance-check it: 2 carbons, 6 hydrogens, 1 oxygen on each side.
>
> **The combustion:**
> $\ce{C2H5OH(l) + 3O2(g) -> 2CO2(g) + 3H2O(l)}$
>
> $\begin{aligned} \Delta H &= \left[ 2(-393.5) + 3(-285.8) \right] - \left[ (-277.6) + 3(0) \right] \\ &= \left[ -787.0 - 857.4 \right] + 277.6 \\ &= -1644.4 + 277.6 \\ &= -1366.8\ \text{kJ} \end{aligned}$
>
> **$\Delta H = -1366.8$ kJ per mole of ethanol.**
>
> **Now put that beside the school measurement.** Burning ethanol under
> a can of water in question 3 of [[Enthalpy Practice]] gave about
> $-1.02 \times 10^{3}$ kJ/mol. The two numbers differ by about a
> quarter, and the whole of that gap is in the same direction that heat
> loss, evaporation, and incomplete combustion predict.
>
> That comparison is the point of doing both calculations. **This one is
> not a better measurement of the same thing — it is not a measurement
> at all.** It is arithmetic on values somebody else measured under
> controlled conditions, and it inherits their accuracy rather than
> your apparatus's.

**6.** Find $\Delta H$ for
$\ce{C2H4(g) + H2(g) -> C2H6(g)}$
from these combustion data:

$\text{(1)}\ \ce{C2H4(g) + 3O2(g) -> 2CO2(g) + 2H2O(l)} \qquad \Delta H = -1411\ \text{kJ}$

$\text{(2)}\ \ce{C2H6(g)} + \tfrac{7}{2}\ce{O2(g) -> 2CO2(g) + 3H2O(l)} \qquad \Delta H = -1560\ \text{kJ}$

$\text{(3)}\ \ce{H2(g)} + \tfrac{1}{2}\ce{O2(g) -> H2O(l)} \qquad \Delta H = -285.8\ \text{kJ}$

> [!success]- Answer 6
> Work from the target, substance by substance.
>
> - $\ce{C2H4}$ is needed on the **left**, and (1) has it on
>   the left. **Keep (1).**
> - $\ce{H2}$ is needed on the **left**, and (3) has it on the left.
>   **Keep (3).**
> - $\ce{C2H6}$ is needed on the **right**, and (2) has it on
>   the left. **Reverse (2).**
>
> $\begin{aligned} \ce{C2H4 + 3O2} &\ce{-> 2CO2 + 2H2O} & \Delta H &= -1411\ \text{kJ} \\ \ce{H2} + \tfrac{1}{2}\ce{O2} &\ce{-> H2O} & \Delta H &= -285.8\ \text{kJ} \\ \ce{2CO2 + 3H2O} &\ce{-> C2H6} + \tfrac{7}{2}\ce{O2} & \Delta H &= +1560\ \text{kJ} \end{aligned}$
>
> Cancel across the sum. $\ce{2CO2}$ appears on the right of the
> first and the left of the third — gone. Water: 2 plus 1 is 3 on the
> right, and 3 on the left — gone. Oxygen: on the left
> $3 + \tfrac{1}{2} = \tfrac{7}{2}$, and $\tfrac{7}{2}$ on the right —
> gone.
>
> $$\ce{C2H4(g) + H2(g) -> C2H6(g)}$$
>
> $\Delta H = -1411 - 285.8 + 1560 = -136.8\ \text{kJ}$
>
> **$\Delta H = -137$ kJ**, to three significant figures — two of the
> given values carry four figures and $-1560$ carries only four as
> written, but the subtraction of numbers near 1500 leaves the answer
> good to about a kilojoule, so three figures is the honest report.
>
> **That everything cancelled is the check.** If your oxygen had not
> come out even, you would know a coefficient was wrong before you
> reached the arithmetic — which is why cancelling the equations
> explicitly is worth the thirty seconds rather than trusting the
> pattern.
>
> This value is the **enthalpy of hydrogenation** of ethene, and it is
> measured this way in practice for the same reason as question 2:
> combustions are easy to run cleanly in a bomb calorimeter, and the
> hydrogenation is not.

**7.** Four claims from a study group. Correct each.
*(a) "For question 2, I added the two given values:
$-393.5 + (-283.0) = -676.5$ kJ."*
*(b) "I reversed equation (1) and doubled it, so $\Delta H$ went from
$+90.3$ to $+180.6$ kJ."*
*(c) "We added a catalyst, so $\Delta H$ for the reaction got smaller."*
*(d) "The combustion of ethanol has $\Delta H = -1366.8$ kJ, so a bottle
of ethanol in a cupboard is dangerous — it will release that much
energy."*

> [!success]- Answer 7
> **(a) The second equation had to be reversed, and reversing flips the
> sign.** Carbon monoxide is on the left of (2) and on the right of the
> target, so (2) runs backwards, and $-283.0$ becomes $+283.0$. The
> correct answer is $-393.5 + 283.0 = -110.5$ kJ.
>
> The student's $-676.5$ kJ is checkable in five seconds without doing
> the problem again. It claims that making carbon monoxide from carbon
> releases **more** energy than making carbon dioxide does — that
> stopping halfway is more exothermic than going all the way. That
> cannot be right, and noticing it is a better skill than getting the
> sign right first time.
>
> **(b) Right operations, one sign missed.** Reversing takes $+90.3$ to
> $-90.3$. Doubling then takes it to $-180.6$, not $+180.6$. The student
> doubled the original value instead of the reversed one.
>
> The fix is procedural rather than conceptual: **write the reversed
> equation out on its own line with its new sign before you multiply
> anything.** Doing both operations in your head, in one step, is where
> this error lives, and it is worth roughly one question per test.
>
> **(c) A catalyst changes neither $\Delta H$ nor anything else about
> the two ends.** $\Delta H$ is the difference in enthalpy between
> reactants and products, and a catalyst does not alter what the
> reactants are or what the products are. It offers a different route
> between them, with a lower activation energy, so the reaction gets
> there **sooner**.
>
> On a potential energy diagram: the hump gets lower, the two ends stay
> exactly where they were. Hess's law says the enthalpy change cannot
> depend on the route — and a catalyst is a route. If a catalyst could
> change $\Delta H$, you could build a machine that made energy by
> cycling a reaction forwards with a catalyst and backwards without one.
>
> **(d) Two words missing again: "per mole".** The value is $-1366.8$ kJ
> for **each mole** of ethanol burned, and a bottle holds a great many
> moles — so the total energy available is far larger than the number
> quoted, not equal to it.
>
> And the energy is only released **if the reaction happens**. A closed
> bottle in a cool cupboard is thermodynamically downhill and kinetically
> stuck, exactly as in question 6 of [[Enthalpy Practice]]: there is no
> route over the activation barrier at room temperature. The hazard is
> real and it is a hazard about **ignition sources and vapour**, not
> about the size of $\Delta H$. That distinction is why the safety rule
> in the labs is "no flames" rather than "no flammable liquids".

Reference: [[Hess's Law]] and [[Enthalpy]]. Testing the law with your own
hands: [[Testing Hess's Law]]. The measurement side:
[[Calorimetry]] and [[Enthalpy Practice]].

%%curriculum-start%%
## Curriculum connection

![[D2.5]]

![[D2.7]]
%%curriculum-end%%
