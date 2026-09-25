---
title: 3D Printing
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
You met this page's ideas as failures first: the tangle of plastic
spaghetti, the part whose corners curled off the bed, the hair-fine
strings between two towers. Every one of those prints was the machine
telling you something about how it works. This page names what it was
saying.

## One layer at a time

The printer in our room melts a thin plastic thread — **filament** —
in a hot **nozzle** and draws with it, one flat layer at a time, on a
**bed**. When a layer is done the nozzle rises a fraction of a
millimetre and draws the next layer on top. Industry calls this
material extrusion, and it is only one of several kinds of 3D printing;
others harden liquid resin with light or fuse powder with a laser.

A **slicer** program turns your model into the thousands of moves the
printer makes, and it asks you three questions that decide how the part
turns out:

| Setting | What it is | The trade |
| --- | --- | --- |
| **Layer height** | How thick each layer is | Thinner layers look smoother and take longer |
| **Infill** | How solid the inside is, as a percentage and a pattern | More infill is stronger, heavier, and slower |
| **Supports** | Scaffolding printed under overhangs, snapped off afterwards | Needed for steep overhangs; they waste plastic and leave marks |

The slicer also tells you, before anything prints, how long the print
will take and how many grams it will use. In this room those two
numbers are criteria, not trivia: one printer serves the whole class.

## Why prints fail

| What you see | What usually caused it |
| --- | --- |
| Corners lifting off the bed (**warping**) | The plastic shrinks as it cools and pulls up; a dirty or cold bed lets it |
| Fine hairs between parts (**stringing**) | Plastic oozing from the nozzle as it travels |
| A nest of loose strands (**spaghetti**) | The part came loose from the bed and the printer kept drawing in mid-air |
| A hole too small for its peg | Printed holes tend to come out slightly smaller than drawn |

Treat a failed print as data. Say what you saw, find the likely cause,
change **one** thing, and print the smallest test that will show
whether it worked — then write it in the log so the next crew does not
repeat it. [[Getting Unstuck]] has the same move for stuck stories.

## Why it matters beyond this room

Judge a printed part by the same short list as anything made — its
function, its aesthetics, its material, how it was fabricated — and
the printer's strengths and weaknesses show at once. One part costs
almost the same as the tenth, and a shape no mould could make is no
harder to print; but every part is slow, and layers make it weaker in
one direction than the others. That is why printing turns up in so
many technology areas: prototypes in product design, custom fixtures on
factory lines, replacement parts nobody stocks any more, medical and
dental models, and gear like the rig your crew is about to make.

Printers were not always in classrooms. The idea behind our kind of
printer was patented in 1989, and when that patent expired in 2009, an
open project called RepRap had already published, free, how to build a
printer from ordinary parts. Cheap printers followed within a few
years. The good that came of it — anyone can make a part — pushed the
technology into schools and homes; the harm that came with it — piles
of failed prints, in plastic that does not break down in a landfill —
is now pushing
it again, towards recycled filament and machines that waste less.

%%curriculum-start%%
## Curriculum connection

![[A1.1]]

![[A1.2]]

![[A3.1]]

![[B2.3]]
%%curriculum-end%%
