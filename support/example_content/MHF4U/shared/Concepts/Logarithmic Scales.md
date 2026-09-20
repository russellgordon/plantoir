---
title: Logarithmic Scales
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
The estimation duel asked how much stronger a magnitude $7$ earthquake
is than a magnitude $5$, and the room split between "a bit worse" and
"twice as bad". Both are wrong by an order of magnitude, and that is the
whole point of this page: a scale built on logarithms turns *factors*
into *steps*, so a gap of two on the dial is a gap of a hundred in the
world.

## Why anyone builds a scale this way

Some quantities arrive over a range no ruler can hold. Ground motion in
an earthquake spans a factor of millions; sound intensity from a
whisper to a jet engine spans a factor of a trillion; the concentration
of hydrogen ions in a solution runs from about $1$ down to
$0.000\,000\,000\,000\,01$ mol/L. Plot any of those directly and every
value you care about is squashed against one end of the axis.

A logarithm is the tool for exactly this, because it is the exponent —
[[The Logarithm]] made that its whole definition. Take the logarithm of
the quantity and the trillion becomes a $12$, the range collapses onto a
line you can draw, and equal *steps* on the new scale mean equal
*factors* in the old one.

| Scale | The quantity underneath | One step on the dial means |
| --- | --- | --- |
| Richter magnitude | Amplitude of ground motion | $\times 10$ in the shaking |
| Decibel, $L = 10\log_{10}\!\frac{I}{I_0}$ | Sound intensity $I$ | $\times 10$ needs ten decibels |
| pH, $\text{pH} = -\log_{10} C$ | Concentration $C$ of $\ce{H+}$ ions | $\times \frac{1}{10}$ in concentration |

Notice the pH row runs backwards. The minus sign is there so that the
numbers come out positive and readable for the solutions chemists
actually handle — which means acidic solutions get the *small* numbers,
and a solution ten times more acidic sits one pH unit *lower*.

## Reading the scale, both directions

Magnitude $7$ against magnitude $5$: the difference is $2$, and because
Richter magnitude is a base-ten logarithm of amplitude, the ground moves
$10^2 = 100$ times as far. (Energy release climbs faster still — roughly
$10^{1.5}$ per unit of magnitude, so about $1000$ times the energy — which
is why the two scales get confused so often.)

Sound is the same arithmetic with a factor of ten stapled on the front,
because a decibel is a *tenth* of a unit: a $70$ dB conversation against a
$40$ dB library is $30$ decibels, so three factors of ten, so
$10^3 = 1000$ times the intensity. And going the other way is a
logarithmic equation like any other: if $L = 85$, then
$\frac{I}{I_0} = 10^{8.5} \approx 3.2 \times 10^8$.

The pH questions are the ones worth practising, because the answer is
never the number you first reach for. Diluting a solution from
$0.1$ mol/L to $0.01$ mol/L changes the concentration by a factor of ten
and the pH by exactly $1$ — and it will do that again from $0.001$ to
$0.0001$, because the scale does not care where you started. Asked the
harder version — a solution at pH $1.7$ that must be raised to pH
$3.1$ — do the algebra rather than guessing:

$$C = 10^{-\text{pH}}, \qquad \frac{C_{\text{old}}}{C_{\text{new}}} = \frac{10^{-1.7}}{10^{-3.1}} = 10^{1.4} \approx 25$$

so the solution must be diluted to about a twenty-fifth of its
concentration. The pH went up by less than one and a half; the water
bill went up twenty-five-fold.

## The other half of the unit: how long until it doubles?

The same equations turn up wherever growth is by a percentage rather
than an amount. An investment of $300(1.05)^n$ dollars doubles when

$$300(1.05)^n = 600 \implies 1.05^n = 2 \implies n = \frac{\log 2}{\log 1.05} \approx 14.2$$

— just over fourteen years, and notice the $300$ vanished. Doubling time
depends on the *rate*, never on the starting amount, which is a fact
about exponentials that surprises almost everybody the first time.
[[Laws of Logarithms]] is where the move that pulled $n$ down out of the
exponent comes from, and [[Logarithm Practice]] has more of both kinds.

> [!tip] Estimate before you compute, always
> Every scale on this page is base ten, so you can bracket the answer in
> your head: a magnitude gap of $2.3$ is somewhere between $100$ and
> $1000$. If the algebra hands you $4.6$, the algebra is wrong. That is
> the reflex [[Estimation Duels]] trains and
> [[Checking Your Own Work]] insists on, and logarithms punish its
> absence harder than anything else in this course.

## Posing your own

Every scale above is a ready-made source of questions, and posing one is
half the skill: pick a scale, find two real readings, and ask something a
person would actually want to know. *Two earthquakes were recorded last
year at magnitude $6.2$ and $4.9$ — how much more did the ground move?*
*A phone reports $88$ dB at a concert and $52$ dB in the kitchen: how many
times more intense is the concert?* Bring one to class with the numbers
sourced, and it becomes a question for the room. That habit is exactly
what [[The Signature Function]] will ask of you at a larger scale.

%%curriculum-start%%
## Curriculum connection

![[A2.4]]

![[A3.2]]

![[A3.4]]
%%curriculum-end%%
