---
title: Continuous Data and Its Intervals
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
Counting how many students chose each of four options is easy: four
categories, four totals. Recording how long each of forty students slept
is not, because no two answers are the same and a table with forty rows
of one is not a summary of anything.

Continuous data is the hard case, and how you handle it changes what
your graph says.

## Why you cannot just count

A **continuous random variable** can take any value in a range —
height, time, mass, temperature. Three consequences follow immediately:

- **No value repeats**, so a frequency table of exact values is useless.
- **Precision is a choice you made**, not a property of the world.
  Sleep measured to the nearest half hour looks tidy; to the nearest
  minute it looks like noise. Neither is more true.
- **The probability of any exact value is effectively zero.** Nobody
  slept exactly 7.000000 hours. Questions have to be asked about
  *intervals* instead: between 7 and 8 hours.

## Intervals, and the judgement in choosing them

Group the values into intervals of equal width, count how many fall in
each, and graph the counts as a **histogram** — bars touching, because
the variable is continuous and there are no gaps between intervals.

| Sleep (hours) | Frequency |
| --- | --- |
| $5 \le t < 6$ | 3 |
| $6 \le t < 7$ | 9 |
| $7 \le t < 8$ | 14 |
| $8 \le t < 9$ | 11 |
| $9 \le t < 10$ | 3 |

Two decisions were made there, and both are arguable: the width of the
interval, and where the first one starts. Redraw the same forty values
with half-hour intervals and the shape gets spikier; with two-hour
intervals it becomes almost featureless. **The distribution you show is
partly a distribution of your own choices**, which is why a histogram
without its interval width stated is not evidence.

A useful discipline: try three widths before choosing one, and say in
your report which you chose and why.

> [!warning] A histogram is not a bar graph
> Bar graphs show categories and their bars have gaps. Histograms show
> intervals of a continuous variable and their bars touch. Drawing one
> when you mean the other tells a reader the wrong thing about your data
> before they read a single number.

## Spread, and standard deviation

The mean tells you where a distribution sits; it says nothing about how
tightly the values cluster. Two classes can average the same mark with
completely different stories underneath.

**Standard deviation** measures that spread: roughly, the typical
distance of a value from the mean.

$$\sigma = \sqrt{\frac{\sum (x - \mu)^2}{n}}$$

Work through it once by hand on five values so the formula stops being
decoration: find the mean, subtract it from each value, square the
results — squaring is what stops the positives and negatives from
cancelling — average them, then take the root to return to the original
units.

After that, use technology. [[Using a Spreadsheet for Statistics]] has
the functions, and the difference between the population and sample
versions, which matters when your data is a sample rather than the whole
group.

What the number means in practice: in a roughly bell-shaped
distribution, about 68% of values lie within one standard deviation of
the mean and about 95% within two. That is the bridge to
[[The Normal Distribution]], and it is why standard deviation is the
measure of spread that keeps appearing rather than the range.

%%curriculum-start%%
## Curriculum connection

![[B2.1]]

![[B2.2]]

![[B2.3]]

![[B2.4]]

![[B2.5]]
%%curriculum-end%%
