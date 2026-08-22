---
title: The Gas Laws
publish: true
created: __CREATED__
enableToc: true
tags:
  - concepts
  - gases
---
In [[Measuring a Gas Law]] you took a sealed syringe, changed one thing
about it, and recorded what happened to the rest. Somebody pushed the
plunger and watched the pressure gauge. Somebody warmed a flask and
watched the volume. The graphs came out clean enough that the
relationships were obvious before anybody named them, which is how it
happened historically as well — every one of these laws is somebody's
measurements before it is anybody's equation.

This page names them, states the conditions each one holds under, and is
honest about the point at which they stop working.

## Kelvin, first, and always

Before any of it: **every temperature in every gas law calculation is in
kelvins.** This is not a preference. Using Celsius gives a wrong answer,
not an approximate one.

$$T(\text{K}) = t(^\circ\text{C}) + 273.15$$

The reason is that these are *proportionalities*, and a
proportionality needs a scale whose zero means none of the quantity.
Zero degrees Celsius does not mean a gas has no thermal energy; it means
water freezes, which is a fact about water and has nothing to do with
the gas in your syringe. Zero kelvin does mean none — it is the
temperature at which molecular motion is at its minimum, and nothing is
colder.

Test it. Warm a gas from 10 °C to 20 °C at constant pressure. The
Celsius number doubled, so does the volume double? In kelvins the change
is 283.15 K to 293.15 K, a rise of about 3.5%, so the volume increases
by about 3.5%. A gas that doubled in volume for a 10-degree rise would
be an alarming thing to have in a laboratory.

For school work 273 is usually close enough, but write down which you
used.

## The four relationships

Each law holds **two** variables fixed and describes how the other two
trade off. The amount of gas, $n$, is constant throughout all four —
the container is sealed.

| Law | Held constant | In words | Equation |
| --- | --- | --- | --- |
| Boyle's | temperature | volume is inversely proportional to pressure | $P_1V_1 = P_2V_2$ |
| Charles's | pressure | volume is directly proportional to absolute temperature | $\frac{V_1}{T_1} = \frac{V_2}{T_2}$ |
| Gay-Lussac's | volume | pressure is directly proportional to absolute temperature | $\frac{P_1}{T_1} = \frac{P_2}{T_2}$ |
| Combined | nothing but the amount | all three together | $\frac{P_1V_1}{T_1} = \frac{P_2V_2}{T_2}$ |

The combined law is not a fifth thing to memorise. Cover up the variable
that is held constant in any row and you have recovered that row's law
from the combined one — hold $T$ constant and the temperatures cancel,
leaving Boyle's. Learn the combined law and you own all four.

Boyle's is the one that is inverse rather than direct, and it is the one
students get backwards. Squeeze a gas into half the volume and the
molecules hit the walls twice as often, so the pressure doubles. Plotted
as $P$ against $V$ it is a curve; plotted as $P$ against
$\frac{1}{V}$ it is a straight line, which is the more convincing graph
to hand in.

## Avogadro, and why equal volumes matter

The four laws above never change the amount of gas. Avogadro's
contribution was to say what happens when you do.

**Avogadro's hypothesis: equal volumes of any gases, at the same
temperature and pressure, contain equal numbers of particles.** It
follows that volume is directly proportional to the number of moles, and
— this is the surprising half — it does not matter which gas. A litre of
hydrogen and a litre of carbon dioxide at the same conditions hold the
same number of molecules, despite carbon dioxide molecules being
twenty-two times heavier.

That was a genuinely bold claim in 1811, and it resolved a puzzle nobody
else could. Gases had been observed to combine in simple whole-number
volume ratios — two volumes of hydrogen with one volume of oxygen giving
two volumes of water vapour — and the accepted picture of atoms could
not explain how two volumes of product came from three volumes of
reactant. Avogadro's answer was that hydrogen and oxygen exist as
*diatomic* molecules that split during the reaction. He was right, and
he was largely ignored for about fifty years.

The practical consequence is the **molar volume**: one mole of any gas
occupies the same volume under the same conditions. That volume must
always be quoted with its conditions attached, because the number is
meaningless without them.

| Conditions | Definition | Molar volume |
| --- | --- | --- |
| STP | 0 °C and 100 kPa | 22.7 L/mol |
| STP, older definition | 0 °C and 101.325 kPa | 22.4 L/mol |
| SATP | 25 °C and 100 kPa | 24.8 L/mol |

Both STP rows are in circulation — IUPAC changed the standard pressure
from 101.325 kPa to 100 kPa in 1982 and textbooks did not all follow at
once. Use whichever your data booklet defines, and **write the
conditions beside the number** so that a reader can tell which you
meant. An answer of "22.4 L" with no conditions is not wrong so much as
unfinished.

## The ideal gas law

Combine everything above — the three variables and the amount — into one
equation:

$$PV = nRT$$

$R$ is the universal gas constant, and its value depends only on the
units you are working in:

- $R = 8.314$ L·kPa/(mol·K), which is the usual choice in this course
- $R = 0.08206$ L·atm/(mol·K), if pressure is in atmospheres

The units of $R$ are the specification for every other quantity in the
equation. Using the first value means volume in litres, pressure in
kilopascals, and temperature in kelvins — no exceptions, no substitutes.

A worked example: what volume does 0.500 mol of oxygen occupy at
25.0 °C and 98.5 kPa?

$$V = \frac{nRT}{P} = \frac{(0.500)(8.314)(298.15)}{98.5} = 12.6 \text{ L}$$

Unlike the combined law, this one describes a single state rather than a
change between two. That makes it the door from a gas measurement into
[[Stoichiometry]] — rearrange for $n$, and a pressure, a volume, and a
temperature have given you an amount in moles.

**Dalton's law of partial pressures** finishes the set: in a mixture,
each gas exerts the pressure it would exert if it were alone, and the
total is the sum.

$$P_\text{total} = P_1 + P_2 + P_3 + \dots$$

This is not an abstraction — it is what you have to apply whenever a gas
is collected over water. The gas in the tube is mixed with water vapour,
so the pressure you read includes the vapour's contribution, and the
pressure of the gas you actually made is the total minus the vapour
pressure of water at that temperature, which you look up.

## Where the model breaks, and why

Everything on this page is the behaviour of an **ideal gas** — a gas
whose particles have no volume of their own and no attraction for one
another. Those are the assumptions of the kinetic molecular theory in
[[Gases and the Atmosphere]], and they are both false. They are false by
so little, at ordinary conditions, that the equations work beautifully.
Two situations make them false enough to matter:

- **High pressure.** Squeeze a gas hard and the particles themselves
  take up a noticeable fraction of the container. The space available
  for movement is less than the measured volume, so a real gas resists
  further compression more than the ideal gas law predicts.
- **Low temperature.** Cool a gas and the particles slow down enough for
  the attractions between them to have an effect, pulling them together
  and reducing the pressure below the ideal prediction. Keep cooling and
  the attractions win completely: the gas condenses to a liquid, at
  which point the model has not merely become inaccurate but has stopped
  describing the substance at all.

The general statement is that gases behave most ideally at **low
pressure and high temperature**, when the particles are far apart and
moving fast enough to ignore one another. A model that tells you where
it fails is more useful than one that claims to work everywhere.

Practise the calculations in [[Gas Law Practice]], and then
[[Gases and the Atmosphere]] applies all of it to the several kilograms
of air pressing on you at this moment.

%%curriculum-start%%
## Curriculum connection

![[F2.1]]

![[F2.2]]

![[F3.4]]

![[F3.5]]

![[F3.6]]
%%curriculum-end%%
