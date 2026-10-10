---
title: Similar Triangles Practice
description: Show your work. Before trusting an answer, check that its size makes sense against its triangle.
printable: true
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Similar Triangles]] — the proportional
reasoning your group used outdoors in [[How Tall Is the Flagpole]].
One habit runs through the set: before trusting an answer, ask whether
its *size* makes sense against the triangle it lives in.

### Question 1

$\triangle ABC \sim \triangle DEF$, with $AB = 4$, $DE = 10$, and
$BC = 6$. Find $EF$.

```tikz
% alt: Triangle ABC with AB = 4 and BC = 6, beside the larger similar triangle DEF with DE = 10 and EF unknown.
\begin{document}
\begin{tikzpicture}
  \draw[thick] (0,0) node[below left]{$A$} -- (2.4,0) node[below right]{$B$} -- (0.8,1.6) node[above]{$C$} -- cycle;
  \node[below] at (1.2,0) {$4$};
  \node[above right] at (1.6,0.8) {$6$};
  \draw[thick] (4,0) node[below left]{$D$} -- (10,0) node[below right]{$E$} -- (6,4) node[above]{$F$} -- cycle;
  \node[below] at (7,0) {$10$};
  \node[above right] at (8,2) {$?$};
\end{tikzpicture}
\end{document}
```

> [!answer]-
>
> $EF = 15$. The scale factor is $\frac{10}{4} = 2.5$, so
> $EF = 6 \times 2.5 = 15$.

### Question 2

**Explain why.** Every pair of congruent triangles is similar, but not
every pair of similar triangles is congruent. Explain both halves using
scale factors.

> [!answer]-
>
> Congruent triangles are similar with scale factor exactly $1$.
> Similar triangles allow *any* scale factor: a $2:1$ enlargement
> keeps every angle but matches no side.

### Question 3

One triangle has sides $6$, $8$, $10$; another has sides $9$, $12$,
$15$. Are they similar? Justify with ratios, and state what that means
about their angles.

> [!answer]-
>
> Similar: $\frac{9}{6} = \frac{12}{8} = \frac{15}{10} = 1.5$, so
> corresponding angles are equal.

### Question 4

A metre stick casts a shadow $1.6$ m long while a tree's shadow
measures $12.8$ m. How tall is the tree — and why are the two
triangles similar in the first place?

> [!answer]-
>
> $8$ m, from $\frac{h}{12.8} = \frac{1}{1.6}$. The sun's rays meet
> stick and tree at the same angle, and both stand at right angles to
> the ground, so two pairs of angles match.

### Question 5

**Find the error.** For question 1's triangles, Sam finds $BC$ from
$EF = 15$ via $\frac{4}{10} = \frac{15}{BC}$, getting $BC = 37.5$.
Catch the slip with a size check, then fix it.

> [!answer]-
>
> $BC$ belongs to the smaller triangle, so it must be under $15$. Sam
> flipped one ratio: $\frac{BC}{15} = \frac{4}{10}$, so $BC = 6$.

### Question 6

**Challenge.** A ramp runs $7.5$ m along the ground to a wall. A
vertical post $1.2$ m tall, standing $3$ m from the ramp's foot, just
touches the ramp. How high does the ramp meet the wall?

> [!answer]-
>
> $3$ m, from $\frac{h}{1.2} = \frac{7.5}{3}$.

### Question 7

**From similar right triangles to trig ratios.** Right triangle
$\triangle ABC$ has $\angle A = 30°$, adjacent side
$AC = \sqrt{3} \approx 1.73$, opposite side $BC = 1$, and hypotenuse
$AB = 2$. A larger right triangle $\triangle DEF$ has $\angle D = 30°$
and hypotenuse $DE = 10$.

1. Verify $\triangle ABC \sim \triangle DEF$ and find $EF$ and $DF$.
   > [!answer]-
   >
   > Both have angles $30°$, $60°$ and $90°$; the scale factor is
   > $5$, so $EF = 5$ and $DF = 5\sqrt{3} \approx 8.66$.
2. Compute $\frac{\text{opposite}}{\text{hypotenuse}}$ in both
   triangles. What constant ratio does this define for $30°$?
   > [!answer]-
   >
   > $\frac{1}{2} = \frac{5}{10} = 0.5$ in both: this is
   > $\sin 30°$.

Trigonometric ratios exist because similar right triangles keep their
side ratios — the idea behind [[The Primary Trigonometric Ratios]].

%%curriculum-start%%
## Curriculum connection

![[C1.1]]

![[C1.2]]

![[C1.3]]

![[C2.1]]
%%curriculum-end%%
