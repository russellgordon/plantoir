---
title: From Sketch to Cut File
publish: true
created: __CREATED__
tags:
  - tutorials
enableToc: true
---
A laser cutter cannot read your sketch. It reads a file of lines, and
it does exactly what each line tells it — including the line you drew
by accident. This page is how a pencil sketch becomes a file the laser
can cut safely on the first try, and it takes about one period the
first time.

## Vector, not raster

The laser follows **vector** lines — paths with exact start and end
points, the same kind of drawing that makes a masthead sharp at any
size ([[The Software You Will Meet]]). A photo or a screenshot is
**raster**, a grid of pixels; the laser can only engrave it, slowly,
never cut it. So the sign is drawn in a vector program — Inkscape is
free, and whatever your school uses will do the same jobs.

## Three kinds of line, three colours

Every laser shop agrees a colour code, so a file says what each line is
for. Ours is on the settings sheet by the machine; a common one is:

| Line colour | The laser will… | Use it for |
| --- | --- | --- |
| Red, thinnest stroke | Cut right through | The outline of the sign; holes for hanging it |
| Blue, thinnest stroke | Score a shallow line | Lettering drawn as outlines; borders |
| Black fill | Engrave the area, line by line | A small logo only — engraving is slow |

The stroke is set to the thinnest width your laser's software asks for,
because a thick stroke may be read as a shape to engrave instead of a
line to follow.

## Text becomes shapes

A font is a set of instructions on *your* computer. Send a file with
live text to another machine and it may swap your typeface for a
different one without asking. So when the lettering is final, convert
the text to paths (in Inkscape, *Object to Path*). Then it is a drawing
of letters, and it will cut exactly as you see it. Keep a copy with the
live text, in case you need to edit the words.

## The test card, and the settings sheet

Before any real work, each material gets **one test card**, run by me in
front of the class: a small grid of squares cut and scored at different
powers and speeds, and a row of slots that shows the kerf. We read the
cards together — which square cut cleanly, which scored without
burning, how wide the slots came out — and the winning settings go on
the **settings sheet** by the machine.

That sheet is a working document, the same kind a real shop keeps: one
row per material, with the power, speed, and passes that worked, who
tested it, and when. You cut from it rather than from a guess, and if
your cut surprises you, you add a note to the row so the next person
does not have to learn it again.

## Nesting: many parts, one sheet

Loading and focusing a sheet takes minutes, and material costs money,
so parts share sheets. Arrange several people's outlines on one sheet,
edges a few millimetres apart, and the laser cuts them all in one job.
Nested prototypes are how a whole class gets its cardboard trials cut
in one period; see the time budget in [[The Sign Shop]].

## Before you send a file

Read down this list with the file open — the same way a newsroom reads
a filing checklist before a story goes to the editor.

- [ ] Sized in millimetres, at the real size of the finished piece
- [ ] Every line is the right colour, at the thinnest stroke
- [ ] Every piece of text converted to paths
- [ ] No stray points, doubled lines, or hidden layers
- [ ] The material you will cut is on the approved list and matches
      the settings-sheet row you chose
- [ ] Your name and the job's estimated time are on the job sheet, and
      your place in the queue is booked

%%curriculum-start%%
## Curriculum connection

![[A1.4]]

![[A2.5]]

![[A2.4]]
%%curriculum-end%%
