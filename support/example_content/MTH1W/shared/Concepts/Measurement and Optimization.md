---
title: Measurement and Optimization
publish: true
created: __CREATED__
tags:
  - concepts
---
Building [[The Best Box]] from identical sheets of card, your class
found that equal amounts of material hold very different amounts of
popcorn — measurement is full of trade-offs like that, and this page
collects the machinery for reasoning about them.

## Units are ratios in disguise

Converting units is proportional reasoning from
[[Ratios, Rates, and Proportions]] wearing a lab coat: $1$ m $= 100$
cm is a rate, and converting just means scaling by it. The same logic
crosses between systems — metric to imperial, or the many measurement
systems developed by cultures worldwide, from hand spans to
paces — as long as you know one honest linking rate. Keep the units
visible in your work and they check the work for you: if the answer
comes out in cm² when you wanted cm³, the units caught the error
before you did.

## Where a unit comes from

The sentence above passes over something worth stopping on. Every
measurement system in that list was *invented*, by particular people
solving a particular problem, and the choices they made are still
sitting inside the numbers you write down.

The older units are almost all bodies and work. A **cubit** is a
forearm; a **foot** is a foot; a **hand**, still the unit horses are
measured in, is a hand. A **fathom** is the span of two outstretched
arms, because that is how you haul a rope in and count it as it comes.
An **acre** was the area one person with one ox could plough in a day,
which is why an acre is a strange number of square metres — it was never
a length at all, it was a day's work. These units are wonderfully
convenient, because the measuring instrument is attached to you, and
hopeless for trade, because your forearm is not mine.

**That is the problem the metric system was built to solve**, in
revolutionary France in the 1790s, and the design goal was explicitly
political as much as scientific: a unit belonging to nobody, so that no
landowner's forearm and no region's custom could be the standard. The
metre was defined from the size of the Earth, the other units were
derived from it by tens, and the awkward local units that different
towns used for the same goods were legislated away. It took decades and
was widely resented — but the reason the conversions on this page are
easy is that somebody decided they should be.

Two things follow that are still live. **The definitions kept moving.**
A metre was a fraction of a meridian, then a metal bar in a vault near
Paris, and is now defined by the speed of light, because each definition
was replaced when somebody needed to measure more finely than it could
be reproduced. And **the old systems did not go away.** Canada buys
lumber in feet and milk in litres; aviation measures altitude in feet
worldwide; a recipe hands you cups. So the conversion skill above is not
a historical curiosity — it is what a Canadian trades worker, nurse, or
pilot does several times a day, and it is where real mistakes with real
costs happen when it is done carelessly.

When [[The Math Fair]] asks you to research a measurement system or a
geometric idea, this is the shape of a good story: who needed it, what
their instrument was, what broke when the community got bigger than the
instrument, and where the idea earns a living now.

## What doubling a dimension really does

Stretch, and the measurements do *not* all stretch together:

| Measure | Dimensions involved | Double one length… | Double all |
| --- | --- | --- | --- |
| Perimeter | one | part grows $\times 2$ | $\times 2$ |
| Area | two | grows $\times 2$ | $\times 4$ |
| Volume | three | grows $\times 2$ | $\times 8$ |

Area answers to *two* dimensions, so doubling both lengths quadruples
it; volume answers to three, so doubling everything multiplies it by
eight. This is why a pizza twice the diameter is four times the pizza,
and why guesses at [[Estimation Duels]] about big objects go wrong in
predictable ways. It is also why optimisation is interesting at all:
perimeter and area grow at different speeds, so among all rectangles
with the same perimeter, the square encloses the most area — spending
the same fence differently buys different amounts of yard.

One more relationship worth owning: a pyramid holds exactly one third
of the prism it fits inside, and a cone one third of its cylinder —
fill one with water and pour three times to see it. Between scaling
effects and these thirds, most volume problems in
[[Design Under Constraints]] reduce to shapes you already know.

%%curriculum-start%%
## Curriculum connection

![[E1.1]]

![[E1.3]]

![[E1.4]]

![[E1.6]]
%%curriculum-end%%
