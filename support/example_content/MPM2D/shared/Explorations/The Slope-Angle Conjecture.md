---
title: The Slope-Angle Conjecture
publish: true
created: __CREATED__
tags:
  - explorations
enableToc: true
---
In grade 9 you met slope: rise over run, a number that says how steep a
line is. Today that old idea gets a question it has never been asked.
Draw a right triangle, mark one of its acute angles, and look at the
slope of the side that leans. Now make the triangle bigger, or smaller,
or turn the angle up a little. What does the slope do — and what does it
*refuse* to do?

## Warm-up

```tikz
% alt: Right triangle ABC with the right angle at C, a 31 degree angle at B, BC = 5 along the bottom and CA = 3 up the right side.
\begin{document}
\begin{tikzpicture}
  \draw[thick] (0,0) node[below left]{$B$} -- (5,0) node[below right]{$C$} -- (5,3) node[above right]{$A$} -- cycle;
  \draw (4.7,0) -- (4.7,0.3) -- (5,0.3);
  \draw (1.2,0) arc[start angle=0, end angle=31, radius=1.2];
  \node at (1.75,0.4) {$31^\circ$};
  \node[below] at (2.5,0) {$5$};
  \node[right] at (5,1.5) {$3$};
\end{tikzpicture}
\end{document}
```

How do you find the slope of side $AB$? What is it, as a fraction and
as a decimal?

## Three triangles, one angle

In each triangle below, $\angle A = 31^\circ$. Count the squares.

```tikz
% alt: Three right triangles on grid paper, each with its right angle at the bottom left and the 31 degree angle A at the bottom right. The first is 6 squares tall and 10 wide, the second 3 tall and 5 wide, the third 9 tall and 15 wide.
\begin{document}
\begin{tikzpicture}[scale=0.32]
  \draw[step=1, very thin, gray!50] (0,0) grid (10,9);
  \draw[step=1, very thin, gray!50] (12,0) grid (17,9);
  \draw[step=1, very thin, gray!50] (19,0) grid (34,9);
  \draw[thick, fill=blue!15] (0,0) -- (10,0) node[below right]{$A$} -- (0,6) -- cycle;
  \draw[thick, fill=blue!15] (12,0) -- (17,0) node[below right]{$A$} -- (12,3) -- cycle;
  \draw[thick, fill=blue!15] (19,0) -- (34,0) node[below right]{$A$} -- (19,9) -- cycle;
\end{tikzpicture}
\end{document}
```

Read the slope of each sloped side from left to right — it falls, so
its rise is negative — and fill in the table.

| Angle | Rise | Run | Slope (to three decimal places) |
| --- | --- | --- | --- |
| $31^\circ$ | | | |
| $31^\circ$ | | | |
| $31^\circ$ | | | |

Then: are the three triangles similar? How do you know? And what do you
notice about their slopes?

## The sketch

Three right triangles again, this time ones you can move. Drag $B$, $E$
or $H$ to resize a triangle; move the **angle** slider to change the
marked angle in all three at once.

```geogebra
file: Slope Angle Conjecture.ggb
alt: Three right triangles of different sizes, ABC, DEF and GHI, that share one marked angle set by a slider. Points B, E and H resize them, and each triangle shows its two shorter sides and the ratio of one to the other.
```

## Questions for your group

1. Are these triangles congruent? Are they similar? How do you know?
2. Drag $B$, $E$ or $H$ to change the size of each triangle. Does that
   change the slope of the triangle?
3. Move the angle slider. What do you notice about the triangles? What
   do you notice about the slope?
4. Make a conjecture — an educated guess — about how the marked angle,
   the slope and the size of a triangle are related.

> [!question]- A sentence to finish (click to expand)
> Given a certain angle, say $47^\circ$, …
>
> Finish it as a group, then test it: does the sketch ever make your
> sentence false?

## What mathematics tends to surface

Equal angles force proportional sides — that is
[[Similar Triangles]] — so every right triangle with the same marked
angle has the same rise-to-run ratio, however large it is drawn. The
slope belongs to the *angle*, not to the triangle. Groups who see that
have found the tangent ratio before anyone has named it: the ratio of
the side opposite an angle to the side beside it, the idea at the heart
of [[The Primary Trigonometric Ratios]]. A table of angles and their
slopes is exactly what the tan button on a calculator remembers for
you.

## An extension

Draw three right triangles of your own, with different angles. For
each, measure the angle with a protractor and calculate the slope of
its sloped side to three decimal places. Then trade slopes, not
angles, with a neighbouring group: can they tell you each of your
angles from the sketch alone? The same idea measures what cannot be
climbed in [[How Tall Is the Flagpole]].

> [!note] Your group's sentence
> The section above says where this exploration tends to lead, not what
> to write. The sentence, and the evidence for it, are your group's.

%%curriculum-start%%
## Curriculum connection

![[C1.1]]

![[C1.2]]

![[C2.1]]
%%curriculum-end%%
