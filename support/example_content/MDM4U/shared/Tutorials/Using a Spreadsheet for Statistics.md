---
title: Using a Spreadsheet for Statistics
publish: true
created: __CREATED__
tags:
  - tutorials
enableToc: true
---
A spreadsheet is where a dataset stops being a picture and becomes
something you can ask questions of. Any of them will do — the
functions below have the same names and the same behaviour in every
spreadsheet program you are likely to meet, which is why this page
names functions rather than menus. Menus move; `AVERAGE` does not.

One rule before anything else: **keep the raw data untouched.** Put
it on its own sheet, never type over a cell in it, and do all your
work on a second sheet that refers to the first. The moment you
"just fix" a value in the original, you have created a dataset that
no longer matches its source and cannot be checked by anyone,
including you.

## Summarizing one column

Every one-variable statistic in this course has a function waiting
for it. Point each at a range of cells — a whole column, or the part
of it you mean.

| Function | What it gives you | What to watch for |
| --- | --- | --- |
| `AVERAGE` | The mean $\bar{x}$ | Silently dragged by outliers; report the median beside it for skewed data |
| `MEDIAN` | The middle value | Resistant to outliers, which is the reason to use it |
| `MODE` | The most frequent value | Undefined or unhelpful when nothing repeats |
| `MIN`, `MAX` | The extremes | Their difference is the range — the crudest measure of spread |
| `STDEV.S` | The standard deviation of a **sample** | The one you almost always want; it divides by $n - 1$ |
| `STDEV.P` | The standard deviation of a whole **population** | Only when your rows genuinely are everyone |
| `COUNT` | How many *numbers* are in the range | Ignores blanks and text — compare it to `COUNTA` |
| `COUNTA` | How many *non-empty* cells | If these two disagree, something in your column is not a number |

That last pair is the cheapest data-quality check there is. If
`COUNT` says 480 and `COUNTA` says 500, then twenty of your values
are text — often a stray space, a comma, or the word "n/a" — and
every statistic above just quietly ignored them.

## Counting subgroups

Most interesting questions are about a *part* of the data, and two
functions cover almost all of them:

- `COUNTIF(range, criterion)` counts the rows matching one condition
  — `COUNTIF(C2:C500, "yes")`, or `COUNTIF(D2:D500, ">65")`.
- `COUNTIFS(range1, criterion1, range2, criterion2)` counts rows
  matching several at once, which is how you build a two-way table
  by hand.

A two-way table built from `COUNTIFS` is the raw material of
[[Conditional Probability]]: the row totals, the column totals, and
the four counts in the middle are exactly what $P(A \mid B)$ needs.
Building one from real data, rather than being handed one, is the
moment the formula stops feeling arbitrary.

## Two columns, and the relationship between them

- `CORREL(rangeX, rangeY)` returns the correlation coefficient $r$.
- `SLOPE(rangeY, rangeX)` and `INTERCEPT(rangeY, rangeX)` give the
  least-squares line — note that both take the $y$ values *first*,
  which is the most common source of a nonsense answer here.
- A scatter chart of the two columns, with a trend line added.

Do those in the opposite order to the one you want to. **Plot
first.** A correlation coefficient is a single number summarizing a
whole cloud of points, and a single number can be produced by clouds
that look nothing alike: a tidy line, a curve that happens to drift
upward, a shapeless blob with one distant point dragging the whole
statistic. If you compute $r$ before you look at the scatter plot,
you have accepted a summary of a picture you never saw — the exact
error [[Two-Variable Statistics]] spends a class dismantling.

## Before you trust a single number of it

> [!warning] Missing values are not zeros
> Real datasets encode "no answer" as something, and that something
> is often a number: `0`, `-99`, `999`, or a blank that a careless
> import turned into `0`. `AVERAGE` cannot tell the difference
> between someone who reported zero hours and someone who declined
> to answer. Open the data dictionary before you open the
> statistics — [[Reading a Data Dictionary]] exists for exactly this
> — and if there is no data dictionary, treat every suspicious
> value as a question you must answer before you publish anything.

Three more habits, in rough order of how often they save someone:

- [ ] Sort each column and look at the top and bottom ten rows. Ages
      of 0 and 214, dates in the future, and duplicated rows all
      confess themselves in about thirty seconds.
- [ ] Never type a summary number into a cell. Write the formula, so
      that when you fix a data error every statistic updates and
      none of them is left stale.
- [ ] Write down, somewhere permanent, how many rows you started
      with and how many you removed. "We dropped 14 of 500 rows with
      missing income" is a sentence your report needs and your memory
      will not supply — see [[Cleaning Messy Data]].

Spreadsheets are excellent at arithmetic on thousands of rows and
completely indifferent to whether the arithmetic means anything. The
function will always return a number. Deciding whether that number
deserves to be in your conclusion is the part that is yours.

%%curriculum-start%%
## Curriculum connection

![[D1.1]]

![[D2.1]]

![[D2.4]]
%%curriculum-end%%
