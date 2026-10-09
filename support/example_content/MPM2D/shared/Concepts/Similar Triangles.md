---
title: Similar Triangles
publish: true
created: __CREATED__
tags:
  - concepts
---
Two triangles are *similar* when they are the same shape — not
necessarily the same size. One is a photocopy of the other at some
zoom setting: all three pairs of corresponding angles are equal, and
all three pairs of corresponding sides are in the same ratio, called
the scale factor.

Congruent triangles are the special case where the zoom is 100% —
same shape *and* same size, scale factor exactly 1. So every pair of
congruent triangles is similar, but similar triangles are congruent
only sometimes — a distinction built for [[Always, Sometimes, Never]].

## Using similarity to find a missing side

Sketch the pair first, with the corresponding sides in the same
positions, and label what you know:

```tikz
% alt: Triangle ABC with AB = 6 and BC = 8, beside the larger similar triangle DEF with DE = 9 and EF unknown.
\begin{document}
\begin{tikzpicture}
  \draw[thick] (0,0) node[below left]{$A$} -- (3,0) node[below right]{$B$} -- (1,2) node[above]{$C$} -- cycle;
  \node[below] at (1.5,0) {$6$};
  \node[above right] at (2,1) {$8$};
  \draw[thick] (5,0) node[below left]{$D$} -- (9.5,0) node[below right]{$E$} -- (6.5,3) node[above]{$F$} -- cycle;
  \node[below] at (7.25,0) {$9$};
  \node[above right] at (8,1.5) {$?$};
\end{tikzpicture}
\end{document}
```

If $\triangle ABC \sim \triangle DEF$ with $AB = 6$, $DE = 9$, and
$BC = 8$, the scale factor from the first triangle to the second is
$\frac{9}{6} = 1.5$, so

$$
\frac{EF}{BC} = \frac{DE}{AB} \implies EF = 8 \times 1.5 = 12
$$

Every length in the second triangle is $1.5$ times its partner in
the first. One known pair of corresponding sides unlocks all the
others.

> [!warning] The order of the letters is a promise
> Writing $\triangle ABC \sim \triangle DEF$ asserts that $A$ pairs
> with $D$, $B$ with $E$, and $C$ with $F$ — so side $AB$
> corresponds to side $DE$, not to whichever side looks about right.
> When one triangle is rotated or reflected on the page, trust the
> letters over your eyes. Marking equal angles with matching arcs
> *before* writing any ratios catches most mismatches.

The power of similarity is that one triangle can be measured while
its twin cannot. A metre stick and a tree cast shadows at the same
moment; the sunlight makes the two triangles similar; the reachable
one measures the unreachable one. That is the whole strategy of
[[How Tall Is the Flagpole]] — and it is also the seed of
trigonometry, because [[The Primary Trigonometric Ratios]] exist
precisely because similar right triangles keep their ratios.
[[Similar Triangles Practice]] builds the correspondence-tracking
that makes all of it reliable.

%%curriculum-start%%
## Curriculum connection

![[C1.1]]

![[C1.2]]

![[C1.3]]
%%curriculum-end%%
