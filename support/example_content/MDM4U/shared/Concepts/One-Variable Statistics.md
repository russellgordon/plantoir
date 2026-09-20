---
title: One-Variable Statistics
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
Eleven numbers went up on the board — minutes spent commuting to
school — and the class was asked for "the average". Three answers came
back: $23.2$, $20$, and $15$. All three were correct. They were the
mean, the median, and the mode of the same eleven numbers, and the
gap between them was one value, a $52$, sitting far from everybody
else. Choosing which average to report is a choice about what you want
your reader to believe, and this page is about making that choice
honestly.

## Centre

The **mean** $\bar{x} = \frac{\sum x}{n}$ balances the data like a
seesaw, which is why a single distant value can drag it. The
**median** is the middle value in order, which is why it barely
notices. The **mode** is the most frequent value, and it is the only
one that works on categorical data — you cannot average "biology,
chemistry, biology".

For $12, 15, 15, 17, 18, 20, 22, 25, 28, 31, 52$: mean $\approx 23.2$,
median $20$, mode $15$. Drop the $52$ and the mean falls to $20.3$
while the median moves only to $19$. That difference in stubbornness
has a name — the median is **resistant** — and it is why incomes and
house prices are reported as medians by anyone being careful.

The relationship runs both ways, and it is diagnostic. Mean well above
median means a right skew, a long tail of large values. Mean below
median means a left skew. Mean and median close together suggests
rough symmetry. You can infer the shape from two numbers, and
[[Graph Talks]] trains exactly that reflex.

## Spread

Centre without spread is half a description. **Range** is
$\max - \min$, easy and fragile. **Interquartile range** is
$Q_3 - Q_1$, the width of the middle half, and it is resistant for the
same reason the median is.

**Standard deviation** measures typical distance from the mean:

$$\sigma = \sqrt{\frac{\sum (x - \mu)^2}{n}} \qquad s = \sqrt{\frac{\sum (x - \bar{x})^2}{n - 1}}$$

Use $\sigma$ when your numbers *are* the whole population; use $s$
when they are a sample standing in for something larger, which is
almost always. Work one by hand exactly once, on $2, 4, 4, 4, 5, 5,
7, 9$: the mean is $5$, the squared deviations sum to $32$, and
$\sigma = \sqrt{32/8} = 2$. After that, let
[[Using a Spreadsheet for Statistics]] do the arithmetic and spend
your attention on what the number means.

## Position

Where does one value sit inside the whole set? Three answers, three
uses.

**Quartiles** split the ordered data into four parts. For the commute
data $Q_1 = 15$ and $Q_3 = 28$, so $\text{IQR} = 13$ and the usual
outlier fences sit at $Q_1 - 1.5(\text{IQR}) = -4.5$ and
$Q_3 + 1.5(\text{IQR}) = 47.5$. The $52$ clears the upper fence, so it
is flagged as an outlier — flagged, not deleted. An outlier is a
question, not a mistake.

**Percentiles** say what fraction of the data falls below a value.
**Z-scores** say how many standard deviations from the mean it sits,
and they are the only one of the three that lets you compare a
commute to a chemistry mark. That is the doorway into
[[The Normal Distribution]], where position becomes probability.

## Choosing the graph, and reporting honestly

- [ ] Categorical data → bar graph, or a circle graph only when the
      categories genuinely make a whole.
- [ ] Numerical data, shape wanted → histogram; check more than one
      interval width before you believe the shape.
- [ ] Small data set, values worth keeping → stem-and-leaf.
- [ ] Comparing two or more groups → boxplots side by side.
- [ ] Every graph: axes labelled, units stated, vertical scale
      starting at zero unless you say plainly that it does not.
- [ ] Every summary: report a centre **and** a spread **and** $n$.

That last line is the whole page in one instruction. "The average
score was 76" is not a finding. "The average score was 76, the median
75, the standard deviation 13, from 84 students" is a finding, and a
reader can argue with it — which is the point.

Once a second variable arrives, the questions change completely, and
[[Two-Variable Statistics]] takes over. Practise the calculations, and
the judgement calls, in [[One- and Two-Variable Data Practice]].

%%curriculum-start%%
## Curriculum connection

![[C1.2]]

![[D1.1]]

![[D1.2]]

![[D1.3]]

![[D1.5]]
%%curriculum-end%%
