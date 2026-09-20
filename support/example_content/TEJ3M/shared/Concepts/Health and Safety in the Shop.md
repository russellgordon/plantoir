---
title: Health and Safety in the Shop
publish: true
created: __CREATED__
tags:
  - concepts
---
[[Spot the Hazard]] puts a photograph of a bench on the screen and gives
you sixty seconds. The photographs get harder through the semester, and
the reason is that the obvious hazards — a hot iron left face up, a
trailing cable — stop being the interesting ones. The hazards that hurt
people in this trade are usually the ones that looked fine.

Treat what follows as ==professional practice, not compliance==. Nobody
who is good at this work thinks of safety as a set of rules imposed from
outside; they think of it as the part of the method that keeps the work
repeatable and the worker employable.

## Electrical work, done the way the trade does it

The bench supplies in this room are low voltage, and low voltage is
forgiving of contact and completely unforgiving of short circuits. The
hazard here is mostly energy, not shock: a battery or supply that can
deliver several amps into a dropped screwdriver will weld it, spray metal,
and set fire to insulation before any of that feels like a decision you
were part of.

- **Power off before you rewire.** Not "off" as in the output is at zero
  — disconnected, and visibly so.
- **Watch what a capacitor is holding.** Large capacitors, especially in
  power supplies, stay charged after the mains is pulled. Equipment
  designed for it has bleeder resistors. Equipment you have opened up may
  not.
- **Nothing mains-powered gets opened in this room.** The
  ==Ontario Electrical Safety Code== governs how permanent wiring and
  equipment is installed, grounded, and enclosed, and one of the reasons
  those standards exist is precisely so nobody has to make a judgement
  call at a bench. Grounding and enclosure are not paperwork; the ground
  is what carries a fault to the breaker instead of through a person.
- **Fuse and rate everything.** A supply set to its current limit is a
  supply that announces your mistakes quietly instead of expensively.

> [!danger] Meter first, hands second
> Before probing anything you did not build in the last ten minutes:
> confirm the meter's dial and lead positions, confirm the range, and
> confirm which two points you intend to bridge. Leaving a meter in
> current mode and probing across a supply puts a near short across the
> rail. The full ritual is in [[Using a Multimeter]] and it takes four
> seconds.

## Chemicals, fumes, and hot metal

WHMIS — the ==Workplace Hazardous Materials Information System== — is the
national scheme for telling you what is in a container and what it can do
to you. Its three parts are worth knowing by name because you will meet
them in every workplace: standardised **pictograms** and **supplier
labels** on the original container, **workplace labels** on anything
decanted into a second container, and a **safety data sheet** for every
product, which spells out the hazards, the protective equipment, and the
first-aid response. Solder, flux, cleaning solvents, and isopropyl
alcohol all have them.

Soldering deserves its own paragraph because it is where most of the
exposure in this room happens. The visible smoke coming off a joint is
mostly ==flux fumes==, and flux fumes are a respiratory irritant and a
known cause of occupational asthma. Work with the extraction on, or in
moving air, and never with your face directly over the joint. Wash your
hands before eating, particularly if the shop stocks leaded solder; lead
is absorbed by ingestion, not through intact skin, so hand-washing is the
control that matters. Tips reach several hundred degrees, so the iron
lives in its stand every single time it leaves your hand, and hot work
happens over a heatproof surface. [[Soldering Safely]] has the full
procedure.

Static is a hazard to the equipment rather than to you, but it is
professional practice all the same. A charge you cannot feel is many
times what a modern chip can survive, and the damage is often partial —
a component that works today and fails in three weeks, which is far worse
than one that fails immediately. Wrist strap on before the bag opens,
boards on the mat, sensitive parts stored in their antistatic packaging.
The strap connects you to ground *through a resistor* by design, so that
grounding you is not itself a shock hazard. [[Anti-Static Habits]] makes
it routine.

## The injuries that arrive slowly

The dramatic hazards get the posters. The ones that actually end careers
in computer technology accumulate quietly.

| Hazard | What it looks like | The control |
| --- | --- | --- |
| Lifting equipment | Back injury from a heavy chassis or CRT | Assess the weight first, lift with the legs, get a second person, use a cart |
| Repetitive strain | Wrist, forearm, and shoulder pain from keyboard and mouse work | Neutral wrists, supported forearms, varied tasks, real breaks |
| Eye strain | Headaches and blurred focus after screen sessions | Screen at arm's length and slightly below eye level, deliberate distance-focus breaks |
| Poor workstation setup | Neck and shoulder pain that follows you home | Feet flat, thighs level, monitor top near eye height, chair adjusted for you and not for the last person |
| Noise and clutter | Slips, trips, and things falling off benches | Cables dressed, walkways clear, bench cleared before the next job starts |

None of those is dramatic and all of them are ordinary in this industry.
Ergonomics is a real engineering problem: the workstation is a system
with a human component, and designing it badly has measurable outputs.

Finally, the part that is not on any list. ==Say something.== A hazard
you noticed and did not report is a hazard you have taken responsibility
for. In this shop and in every workplace you will ever join, raising a
concern is a normal professional act, not an accusation — and in Ontario
it is a right protected by law. [[Safety in the Lab]] sets out how that
works here, and [[When Good Enough Is Not Safe]] is where we argue about
the harder cases.

%%curriculum-start%%
## Curriculum connection

![[B1.2]]

![[D1.1]]

![[D1.2]]
%%curriculum-end%%
