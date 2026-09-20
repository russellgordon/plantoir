---
title: Power Calculations Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These follow [[Power and Heat]]. Three forms of one equation —
$P = VI$, $P = I^2R$, and $P = \frac{V^2}{R}$ — and the whole skill is
picking the one that uses the two quantities you already have. Answers
in watts and milliwatts, and every one of them ends with a judgement
about whether the part survives.

## Finding the watts

1. A device draws 0.5 A from a 12 V supply. What power does it consume?
2. A current of 25 mA flows through a 470 Ω resistor. Find the power
   dissipated, and say whether a quarter-watt resistor is adequate.
3. A 330 Ω resistor has 9 V across it. Find the power dissipated, and
   again judge a quarter-watt part.
4. A red LED with a 2.0 V forward drop runs from a 5 V supply through a
   220 Ω series resistor. Find the current, the power dissipated by the
   resistor, the power converted by the LED, and the total power drawn
   from the supply. Show that the three numbers are consistent.

## Judging a design by its heat

5. A small DC motor runs at 6 V drawing 800 mA. Find its power. A
   microcontroller pin on this board is rated to source about 20 mA —
   express the mismatch as a factor and say what has to go between them.
6. A device left permanently on draws 3 W. Find the energy it uses in a
   day and in a thirty-day month, in kilowatt-hours, and estimate the
   cost at 13 cents per kilowatt-hour.
7. What is the maximum current a quarter-watt 1 kΩ resistor can safely
   carry, and the maximum voltage that can appear across it?
8. **Find the error.** Asked for the resistor's dissipation in question
   4, a classmate writes
   $P = \frac{V^2}{R} = \frac{(5\ \text{V})^2}{220\ \Omega} = 0.114\ \text{W}$.
   The formula is real and the arithmetic is right. What is wrong, and
   why does it matter even though this particular error is on the safe
   side?

## Answers

> [!success]- Answer 1
> $P = VI = 12\ \text{V} \times 0.5\ \text{A} = 6\ \text{W}$. Volts times amperes is watts, directly — no conversion needed.

> [!success]- Answer 2
> You have current and resistance, so use $P = I^2R = (0.025\ \text{A})^2 \times 470\ \Omega = 0.000625 \times 470 = 0.294\ \text{W}$.
>
> **Judgement:** a quarter-watt part is rated for 0.25 W, and 0.294 W is
> $\frac{0.294}{0.25} = 118\ \%$ of that. Not adequate. It will get hot,
> drift in value, discolour, and eventually fail — probably not while you
> are watching. Fit a half-watt part, which runs at 59 % of its rating
> and can be forgotten about.

> [!success]- Answer 3
> You have voltage and resistance, so use $P = \frac{V^2}{R} = \frac{(9\ \text{V})^2}{330\ \Omega} = \frac{81}{330} \approx 0.245\ \text{W}$.
>
> **Judgement:** that is 98 % of a quarter-watt rating. Arithmetically
> inside the limit; professionally not acceptable. Ratings assume still
> air at room temperature, and your circuit will live in a case, in
> summer, next to other warm parts. Fit a half-watt resistor and design to
> roughly half of any rating as a habit.

> [!success]- Answer 4
> **Current.** The LED takes 2.0 V, so the resistor has $5.0 - 2.0 = 3.0\ \text{V}$ across it and $I = \frac{3.0\ \text{V}}{220\ \Omega} \approx 0.01364\ \text{A} = 13.6\ \text{mA}$. That current is the same everywhere in a series loop.
>
> **Resistor.** $P = I^2R = (0.01364\ \text{A})^2 \times 220\ \Omega \approx 0.0409\ \text{W} = 40.9\ \text{mW}$. Comfortably inside a quarter-watt part.
>
> **LED.** $P = VI = 2.0\ \text{V} \times 0.01364\ \text{A} \approx 0.0273\ \text{W} = 27.3\ \text{mW}$.
>
> **Supply.** $P = VI = 5.0\ \text{V} \times 0.01364\ \text{A} \approx 0.0682\ \text{W} = 68.2\ \text{mW}$.
>
> **Consistency:** $40.9 + 27.3 = 68.2\ \text{mW}$. The energy the supply
> delivers is exactly the energy the two components spend, which is the
> check that proves the whole calculation. Worth noticing that 60 % of it
> goes into the resistor, whose entire job is to not be a short circuit.

> [!success]- Answer 5
> $P = VI = 6\ \text{V} \times 0.8\ \text{A} = 4.8\ \text{W}$.
>
> The current mismatch is $\frac{800\ \text{mA}}{20\ \text{mA}} = 40$ — the motor wants forty times what the pin can supply, and that is its *running* current, not its far larger stall or start-up current.
>
> What goes between them: a transistor or driver chip rated well above
> the motor's stall current, switched by the pin; a flyback diode across
> the motor, because it is inductive; and a supply for the motor separate
> from the one feeding the board, with the grounds tied together. All
> three, not two of three. See [[Driving Outputs Safely]].

> [!success]- Answer 6
> **Per day:** $3\ \text{W} \times 24\ \text{h} = 72\ \text{Wh} = 0.072\ \text{kWh}$.
>
> **Per thirty days:** $0.072 \times 30 = 2.16\ \text{kWh}$.
>
> **Cost:** 2.16 kWh at 13 cents is about 28 cents a month, or roughly
> \$3.40 a year.
>
> The individual number is trivially small, which is exactly the point.
> Multiply it by every device in a school, or a city, and standby power
> stops being trivial — the arithmetic that makes [[Tech Headlines]]
> stories about idle consumption believable.

> [!success]- Answer 7
> Rearrange each form for the quantity you want.
>
> **Current:** $P = I^2R$ gives $I = \sqrt{\frac{P}{R}} = \sqrt{\frac{0.25\ \text{W}}{1000\ \Omega}} = \sqrt{0.00025} \approx 0.0158\ \text{A} = 15.8\ \text{mA}$.
>
> **Voltage:** $P = \frac{V^2}{R}$ gives $V = \sqrt{PR} = \sqrt{0.25 \times 1000} = \sqrt{250} \approx 15.8\ \text{V}$.
>
> Cross-check the pair with Ohm's law: $15.8\ \text{V} \div 1000\ \Omega = 15.8\ \text{mA}$. They agree, as they must — and remember these are absolute limits, so a real design should stay well under them.

> [!success]- Answer 8
> **What is wrong:** in $P = \frac{V^2}{R}$, the $V$ must be the voltage
> across *that resistor*, not the supply voltage. The resistor only has
> 3.0 V across it, because the LED took 2.0 V first. The correct figure
> is $\frac{(3.0\ \text{V})^2}{220\ \Omega} \approx 0.0409\ \text{W}$, matching answer 4.
>
> **Why it matters anyway:** here the error inflates the answer, 0.114 W
> against a true 0.041 W, so the part chosen would be oversized rather
> than undersized. But the *habit* — grabbing the supply voltage because
> it is the number on the page — is the same habit that underestimates
> in other circuits, and it is why every power calculation should start
> by naming which two points the voltage is measured between.

Bring the thermal instinct to [[Spot the Hazard]], and apply it for real
when you cost out the parts list for [[The Working Circuit]].

%%curriculum-start%%
## Curriculum connection

![[A3.3]]

![[A3.4]]
%%curriculum-end%%
