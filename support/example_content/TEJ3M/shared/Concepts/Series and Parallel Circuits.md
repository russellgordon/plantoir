---
title: Series and Parallel Circuits
publish: true
created: __CREATED__
tags:
  - concepts
---
[[The Prediction Contest]] put two circuits side by side with identical
parts in them, and asked which would draw more current. Half the room got
it backwards. The parts were the same; only the *arrangement* differed,
and arrangement turns out to decide almost everything.

## Series: one path, shared current

Components in series sit end to end on a single path. Charge that leaves
the supply has nowhere else to go, so the current is identical at every
point in the loop — the same number through the first resistor as the
last. What gets divided instead is voltage: each component takes a share
of the supply, and the shares add back up to the supply exactly.

$$R_{\text{total}} = R_1 + R_2 + R_3 + \dots$$

Three resistors of 330 Ω, 470 Ω, and 220 Ω in series total 1020 Ω. On a
9 V supply that gives

$$I = \frac{9\ \text{V}}{1020\ \Omega} \approx 0.00882\ \text{A} = 8.82\ \text{mA}$$

and that one current then produces each drop: $8.82\ \text{mA}$ through
330 Ω is 2.91 V, through 470 Ω is 4.15 V, through 220 Ω is 1.94 V. Add
them: 9.00 V. That is not a coincidence you should be pleased about — it
is Kirchhoff's voltage law, and it is your free check on every series
calculation you will ever do. If your drops do not sum to the supply, you
have made an arithmetic error, full stop.

## Parallel: shared voltage, divided current

Components in parallel are connected across the same two points, so they
all see the same voltage — the full supply, if they sit straight across
it. The current splits between them, and the branch currents add up to
the total flowing out of the supply. That is Kirchhoff's current law:
whatever arrives at a junction leaves it.

$$\frac{1}{R_{\text{total}}} = \frac{1}{R_1} + \frac{1}{R_2} + \frac{1}{R_3} + \dots$$

Two 1 kΩ resistors in parallel come to 500 Ω. A 470 Ω beside a 220 Ω come
to about 150 Ω. Notice what those have in common: the parallel total is
always *smaller than the smallest* resistor in the group. Students find
that shocking until they think about it as plumbing — adding another pipe
between the same two points cannot make it harder for water to get
across.

> [!question]- Self-check: predict before you read on (click to expand)
> A 100 Ω resistor is in series with a pair of 220 Ω and 330 Ω resistors
> that are in parallel with each other, all on a 12 V supply. What is the
> total current?
>
> Work inward. The parallel pair is $\frac{220 \times 330}{220 + 330} = 132\ \Omega$, so the whole network is $100 + 132 = 232\ \Omega$ and $I = \frac{12\ \text{V}}{232\ \Omega} \approx 51.7\ \text{mA}$.
>
> Now the check. The 100 Ω drops $51.7\ \text{mA} \times 100\ \Omega = 5.17\ \text{V}$, leaving 6.83 V across the parallel block. That 6.83 V pushes $\frac{6.83}{220} = 31.0\ \text{mA}$ down one branch and $\frac{6.83}{330} = 20.7\ \text{mA}$ down the other. The branches sum to 51.7 mA and the drops sum to 12 V. Both laws agree, so the answer stands.

## The voltage divider, and why you will use it constantly

Two resistors in series across a supply produce a predictable voltage at
the point between them. That point is a *divider*, and it is how sensors
report themselves to a microcontroller.

$$V_{\text{out}} = V_{\text{in}} \times \frac{R_2}{R_1 + R_2}$$

With 5 V in, $R_1 = 10\ \text{k}\Omega$ and $R_2 = 4.7\ \text{k}\Omega$,
the output is $5 \times \frac{4700}{14700} \approx 1.60\ \text{V}$. Swap
$R_2$ for a light-dependent resistor and that voltage now reports on the
room — the idea [[Sensors and Actuators]] builds on and
[[Digital and Analog Signals]] turns into a number.

> [!important] Work from the inside out
> Real circuits are neither purely series nor purely parallel. Find the
> smallest group that is clearly one or the other, replace it with a
> single equivalent resistance, redraw, and repeat until one resistor is
> left. Redrawing is not a waste of time — the redraw is where the
> mistake usually surfaces, which is why [[Reading Schematics]] insists
> you be able to trace a path with a fingertip.

Drill the whole business in [[Series and Parallel Practice]], then take
the predictions to the bench in [[Measure a Circuit]] where the meter
gets a vote.

%%curriculum-start%%
## Curriculum connection

![[A3.3]]

![[B3.1]]

![[B3.3]]
%%curriculum-end%%
