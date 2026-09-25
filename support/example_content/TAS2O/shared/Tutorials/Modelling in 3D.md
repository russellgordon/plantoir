---
title: Modelling in 3D
publish: true
created: __CREATED__
tags:
  - tutorials
enableToc: true
---
A printer prints exactly what the model says, to a fraction of a
millimetre — including the mistake you made when you guessed a
measurement. This page takes a rig from a pencil sketch to a file the
printer can use, in a free browser-based program such as Tinkercad. Any
3D modelling program does the same jobs with different buttons.

## Sketch first, with numbers on it

Before the program opens, draw the part on paper from two or three
sides, and write a measurement on every edge that matters — measured
with calipers from the real phone, clamp, or tripod it has to fit, in
millimetres. That sketch is a **dimensioned drawing**, the document a
machinist or a print shop works from, and it is the first thing I will
ask to see at your desk. A model built from a drawing takes one period;
a model built by eye takes three and still does not fit.

## Solids and holes

Most beginner models are built the same way: stack simple solid shapes
— boxes, cylinders, wedges — and cut into them with **hole** shapes.

1. Set the grid to millimetres before you place anything.
2. Build the outside from solids, typing each size into its box rather
   than dragging. Dragged sizes are guesses.
3. Place hole shapes where material must go: the slot for the phone,
   the pocket for the nut.
4. Select everything and **group** it. The holes now cut the solids.
5. Check every measurement against your drawing with the ruler tool.

## Designing for the printer

The printer has opinions, and a good model respects them:

- **Add the tolerance.** Printed holes come out slightly small, so
  anything that must fit is drawn bigger by the clearance the class
  coupon found — see [[The Tolerance Coupon]]. A 71.5 mm phone does
  not go in a 71.5 mm clamp.
- **Lie it flat.** Put the biggest flat face on the bed. Overhangs
  steeper than about 45° need supports, which waste plastic and time.
- **Walls you can trust.** Very thin walls print weak or not at all;
  two or three millimetres is a sensible starting point for a clamp.
- **Let metal do the metal's job.** A camera tripod's screw is ¼″-20.
  Plastic threads of that size rarely hold a phone safely, so a rig
  that screws onto a tripod has a hexagonal pocket for a steel ¼″-20
  nut instead. The nut measures 7/16″ across its flats — about
  11.1 mm — so the pocket is drawn at that plus your clearance.

## From model to print

Export the model as an **STL** or **3MF** file — the formats a slicer
reads — and name it with your crew, the part, and the version:
`crew3-clamp-v1.stl`. Open it in the slicer, choose the settings from
[[3D Printing]], and write down the two numbers the slicer gives you,
the time and the grams, before you book a slot in the print queue.

> [!tip] Version numbers are a promise
> Never save over v1 when you start v2. The difference between the two
> files is the evidence that your test changed your design — which is
> exactly what [[The Rig]] asks you to show.

%%curriculum-start%%
## Curriculum connection

![[A1.4]]

![[A2.7]]

![[A2.5]]
%%curriculum-end%%
