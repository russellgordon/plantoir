---
title: Repair or Replace
publish: true
created: __CREATED__
tags:
  - discussions
---
You had this argument in Grade 10 and lost it to a fact: most of you
could not fix the thing anyway. That excuse is gone. You can read a
schematic, drive a meter, and put a soldering iron on a board without
setting anything on fire — which means "unrepairable" now has to mean
something more specific than "beyond me". Sometimes it does. A part
with no published datasheet, a board with no schematic, a chip paired
by serial number to one particular device: those are barriers built on
purpose, and they are not the same barrier as difficulty.

The trade has a word for what changed between last year and this one:
**board-level repair**. The shop that replaces the whole main board is
not lying about the fault — it is telling you where its economics
stop. The fault is usually much smaller than the module that gets
replaced.

| What the customer reports | What gets replaced | What is often actually faulty |
| --- | --- | --- |
| Laptop will not charge | The whole main board | One charging controller, or a blown fuse worth pennies |
| Monitor is dead, no picture | The whole monitor | Bulged electrolytic capacitors in its power supply |
| Cordless drill "won't hold a charge" | The battery pack | One weak cell out of ten, or the pack's protection board |

Every row of that table is a real repair a technician can do in under
an hour with a meter, an iron, and the right part. Every row is also a
repair almost nobody is offered, because the labour costs more than
the replacement and the parts are not sold separately.

Questions worth arguing about:

1. A shop quotes \$180 to diagnose and replace a main board on a
   device worth \$500. The actual fault is a \$4 part. Who arranged
   the economics that make replacement rational — and is anyone in
   that chain behaving badly, or is everyone behaving sensibly inside
   a system that produces a bad result?
2. Manufacturers argue that board-level repair by untrained people is
   genuinely unsafe — a badly reworked charging circuit is a fire in
   somebody's bedroom. That is a real argument. What evidence would
   separate the honest version of it from the convenient one?
3. Serialised parts mean a replacement screen or battery, genuine and
   correctly fitted, can still be rejected by the device. Defend that
   design decision as its engineers would. Then say what it costs the
   owner.
4. You can now diagnose to the component. Does being *able* to fix
   something create any obligation to try — for yourself, for family,
   for a neighbour? Where is the line between a favour and taking
   responsibility for someone's fire safety?
5. If repair became easy and normal again, who wins, who loses, and
   what happens to the price of new hardware? Argue the
   manufacturer's side first, honestly, before you argue your own.

> [!important] Skill changes the argument, and it also changes your exposure
> Once you can open it, you own the outcome. A repair you did badly is
> not a neutral event — it is a device someone else will plug in and
> trust. Hold that thought all the way into
> [[When Good Enough Is Not Safe]], which is the same conversation
> pointed at your own workbench instead of at a corporation's.

The argument gets a practical test. Every build you hand in this
semester carries a known-issues list, because
[[Documenting Your Build]] insists on one. Decide here what you think
"repairable" obliges a maker to provide — and then provide it.

%%curriculum-start%%
## Curriculum connection

![[A1.3]]

![[C1.1]]

![[C1.2]]

![[C2.2]]
%%curriculum-end%%
