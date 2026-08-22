---
title: The Normal Distribution
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
Three groups measured three unrelated things at the boards — reaction
times, the heights in a class list, the total when ten dice are rolled
a hundred times. Three different questions, three different units, and
when the histograms went up on the wall they were the same shape. That
was not a coincidence you were meant to admire and move past. It is
the most useful fact in this course.

## The shape, and what fixes it

A normal distribution is symmetric, single-peaked, and asymptotic —
the tails approach the axis without ever touching it. Exactly two
numbers fix a particular one: the mean $\mu$, which says where the
peak sits, and the standard deviation $\sigma$, which says how spread
out it is. Change $\mu$ and the whole curve slides; change $\sigma$
and it stretches or narrows around the same centre.

The area under the whole curve is $1$ — because it accounts for every
possible outcome — and that is why *area* answers every question you
will ask of it. "What fraction of the class is under 160 cm?" is
"how much area lies to the left of 160?"

## The 68–95–99.7 rule

| Within | Of the data |
| --- | --- |
| $\mu \pm 1\sigma$ | about 68% |
| $\mu \pm 2\sigma$ | about 95% |
| $\mu \pm 3\sigma$ | about 99.7% |

That table is worth knowing by heart, not because it replaces
calculation, but because it makes bad answers obvious. If a
calculation says 40% of values lie within one standard deviation of
the mean, the calculation is wrong.

## Standardizing: the z-score

Every normal distribution can be re-expressed as one — the standard
normal, with $\mu = 0$ and $\sigma = 1$ — by asking each value the
same question: *how many standard deviations from the mean are you?*

$$z = \frac{x - \mu}{\sigma}$$

A $z$-score of $1.5$ means "one and a half standard deviations above
the mean", whatever was being measured, in whatever units. That is
what makes two unlike things comparable: a $z$ of $2.1$ on a chemistry
test and a $z$ of $0.4$ on a swim time are now on speaking terms.

> [!question]- Self-check: a test has $\mu = 72$ and $\sigma = 8$. Is a
> score of 88 unusual? (click to expand)
> $z = \frac{88 - 72}{8} = 2$, so the score sits two standard
> deviations above the mean. By the rule above, about 95% of scores
> lie within two standard deviations, leaving about 5% split between
> the two tails — so roughly 2.5% of students scored 88 or higher.
> Unusual, yes; astonishing, no.

## Why it keeps appearing

Because sums and averages of many small independent effects tend to
this shape, no matter what shape the individual effects had. Height is
the sum of many genetic and environmental contributions; the dice
total is the sum of ten rolls. That is why the normal curve turns up
in places nobody designed it into — and why it earns a permanent place
in [[Regression and Inference Practice]] and in the analysis stage of
[[The Culminating Investigation]].

One honest caution: *keeps appearing* is not *always appears*.
Incomes, waiting times, and city populations are famously not normal,
and treating them as though they were is a classic way to be
confidently wrong. Look at the histogram before you reach for the
curve — a habit [[Normal Distribution Practice]] drills deliberately.

## Reading "plus or minus three points, 19 times out of 20"

Every published poll carries a sentence like that, and it is a normal
distribution talking. Unpacked, it says two things:

- **The margin of error** — the poll's figure is an estimate, and the
  true value is probably within three percentage points either side of
  it.
- **The confidence level** — "19 times out of 20" is 95%, which is two
  standard deviations. If the same poll were run twenty times, about
  nineteen of those intervals would contain the true value and about one
  would not.

Three consequences worth knowing before you argue about a poll:

1. **A lead inside the margin is not a lead.** 46% against 44% with a
   margin of three means the two are not distinguishable. Reporting it
   as "ahead" is the single most common misuse of this sentence.
2. **The margin covers sampling error only.** It says nothing about a
   badly worded question, a sample that missed a group, or people who
   did not answer honestly — the failures in [[Bias]], none of which
   shrink when the sample grows.
3. **Halving the margin costs four times the sample**, because the
   margin depends on the square root of the sample size. That is why
   national polls stop at about a thousand people rather than ten
   thousand.

%%curriculum-start%%
## Curriculum connection

![[B2.3]]

![[B2.5]]

![[B2.6]]

![[B2.7]]

![[B2.8]]

![[D1.4]]
%%curriculum-end%%
