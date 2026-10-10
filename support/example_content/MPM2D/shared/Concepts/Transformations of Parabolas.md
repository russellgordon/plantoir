---
title: Transformations of Parabolas
publish: true
created: __CREATED__
tags:
  - concepts
---
In a [[Which One Doesn't Belong]] round with four parabolas, every
choice was defensible: one opened down, one was skinnier, one had
slid away from the origin. That set was secretly a map of this whole
topic — every parabola in this course is $y = x^2$ after some
combination of three moves.

Start from the parent, $y = x^2$: vertex at the origin, and the
1-4-9 climb — from the vertex, across 1 and up 1, across 2 and up
4, across 3 and up 9.

## The three moves

**Flips and stretches — the $a$.** In $y = ax^2$, every height is
multiplied by $a$. If $a = 2$, the climb becomes 2-8-18 and the
parabola narrows; if $a = \frac{1}{2}$, it widens. A negative $a$
flips every height below the axis, so the parabola opens down.

**Slides — the $h$ and the $k$.** In $y = (x - h)^2$ the graph
slides horizontally so the vertex lands at $x = h$; in
$y = x^2 + k$ it slides vertically by $k$. Neither slide changes
the shape — the whole curve moves rigidly, like a stamp lifted and
pressed down somewhere else.

Put together, $y = a(x - h)^2 + k$ is the parent after a flip or
stretch, then a slide that parks the vertex at $(h, k)$ — which is
exactly why [[The Vertex Form]] can be read straight off a graph,
and read back into one.

## Sketching by transformation

To sketch $y = -2(x - 1)^2 + 3$ by hand:

- [ ] Read the vertex: $(1, 3)$. Plot it.
- [ ] Read $a = -2$: opens down, narrowed — the 1-4-9 climb
      becomes a *descent* of 2-8-18.
- [ ] From the vertex, step across 1 and down 2, on both sides.
- [ ] Step across 2 and down 8, on both sides.
- [ ] Join with a smooth symmetric curve, then confirm one point in
      the equation — or the whole curve in [[Using Desmos]].

Here is the parent and the finished sketch on the same axes. Check
yours against it: the vertex sits at $(1, 3)$, and the curve falls away
twice as steeply as the parent does.

```functionplot
---
bounds: [-4, 5, -6, 10]
alt: The parent parabola y = x^2 and y = -2(x - 1)^2 + 3, which opens down, is narrower, and has its vertex at (1, 3).
---
y = x^2
y = -2(x - 1)^2 + 3
```

The order matters: stretch and flip first, slide second. Sliding
first and stretching afterward drags the vertex out of position,
and the graph betrays it immediately — a worthwhile thing to watch
happen once, on purpose. [[Quadratic Graphing Practice]] turns the
whole sequence from a procedure into a reflex.

%%curriculum-start%%
## Curriculum connection

![[A2.1]]

![[A2.2]]

![[A2.3]]
%%curriculum-end%%
