---
title: One- and Two-Variable Data Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These follow [[Sampling Techniques]], [[Bias]],
[[One-Variable Statistics]], and [[Two-Variable Statistics]]. Several
questions ask for a judgement rather than a value; those answers
explain the reasoning and say where a different defensible choice
exists. Use technology for the arithmetic once you have done question
3 by hand — [[Using a Spreadsheet for Statistics]] will do the rest.

Throughout, this is the commute data (one-way minutes, from 11
students):

$$12, \; 15, \; 15, \; 17, \; 18, \; 20, \; 22, \; 25, \; 28, \; 31, \; 52$$

## Summarizing one variable

1. Find the mean, median, mode, and range of the commute data. Which
   measure of centre would you report to a school board, and why?
2. Remove the value 52 and recompute the mean and the median. What
   does the comparison demonstrate?
3. By hand, treating the set as a whole population, find the standard
   deviation of $2, 4, 4, 4, 5, 5, 7, 9$. Then state what changes if
   these eight values are a sample from a larger group.

> [!success]- Answer 1
> The values are already in order and sum to $255$, so
> $\bar{x} = \frac{255}{11} \approx 23.2$ minutes.
> With 11 values the median is the 6th: $20$ minutes.
> The mode is $15$, the only repeated value.
> The range is $52 - 12 = 40$ minutes.
> Which to report: the **median**, and say so explicitly. The mean
> sits more than three minutes above the median because one long
> commute drags it, so "the average commute is 23 minutes" would
> describe nobody in the set — six of the eleven students commute
> 20 minutes or less. The mode is useless here; with one repeat it is
> an accident of rounding, not a feature of the data. Best practice
> is to report the median *and* the mean and let the gap between
> them tell the reader about the skew.

> [!success]- Answer 2
> Without the 52, the ten remaining values sum to $203$, so the mean
> becomes $20.3$ minutes. The median becomes the average of the 5th
> and 6th values, $\frac{18 + 20}{2} = 19$ minutes.
> The mean fell by $2.9$ minutes; the median fell by $1$. One value
> out of eleven moved the mean almost three times as far as it moved
> the median. That is **resistance**, and it is the whole reason
> incomes, house prices, and commute times are reported as medians
> by anyone being careful.

> [!success]- Answer 3
> The eight values sum to $40$, so $\mu = 5$. Squared deviations:
> $9, 1, 1, 1, 0, 0, 4, 16$, which sum to $32$.
> $$\sigma = \sqrt{\frac{32}{8}} = \sqrt{4} = 2$$
> A typical value sits about 2 units from the mean, which matches
> the eye: most of the data is between 4 and 7.
> If the eight values are a **sample**, divide by $n - 1 = 7$
> instead: $s = \sqrt{\frac{32}{7}} \approx 2.14$. The sample
> version is slightly larger because a sample tends to be a bit less
> spread out than the population it came from, and dividing by a
> smaller number corrects for that. In practice you will almost
> always want $s$ — data you collect is nearly always a sample.

## Position, spread, and outliers

4. For the commute data, find $Q_1$, $Q_3$, and the interquartile
   range. Apply the $1.5 \times \text{IQR}$ test and state which
   values, if any, are flagged. What should you do about them?
5. The standard deviation of the commute data, treated as a sample,
   is about $11.2$ minutes. Find the $z$-score of the 52-minute
   commute, and explain why you should be careful converting it to a
   percentile.
6. Two classes wrote the same test. Class A: mean 75, median 75,
   range 14, $s \approx 4.9$. Class B: mean 76.5, median 76, range
   43, $s \approx 14.3$. Which class did better? What else would you
   want to know?

> [!success]- Answer 4
> With 11 values, the median is the 6th ($20$) and is excluded from
> both halves.
> Lower half: $12, 15, 15, 17, 18$, so $Q_1 = 15$.
> Upper half: $22, 25, 28, 31, 52$, so $Q_3 = 28$.
> $\text{IQR} = 28 - 15 = 13$ minutes — the middle half of students
> commute between 15 and 28 minutes.
> Fences: $Q_1 - 1.5(13) = 15 - 19.5 = -4.5$ and
> $Q_3 + 1.5(13) = 28 + 19.5 = 47.5$.
> Only $52$ clears a fence, so it is flagged as an outlier.
> What to do: investigate, not delete. A 52-minute commute is
> entirely plausible for a student who is bused in from outside
> town. Unless you can show it is a recording error, keep it, report
> it, and mention it — an outlier is a question, not a mistake.

> [!success]- Answer 5
> $$z = \frac{52 - 23.2}{11.2} \approx 2.57$$
> So the long commute sits about two and a half sample standard
> deviations above the mean.
> The caution: converting a $z$-score into a percentile requires the
> **normal** model, and this data is not normal. It is right-skewed
> — mean well above median, one long tail — with only 11 values.
> Quoting "the 99.5th percentile" from a normal table here would be
> using a curve the data does not follow. The $z$-score is still a
> perfectly good statement of relative position; it is the
> probability claim on top of it that is not earned.

> [!success]- Answer 6
> The centres are nearly identical — Class B is ahead by 1.5 marks
> on the mean and 1 on the median, which is well inside the noise
> for a single test. The spreads are not close at all: Class B's
> standard deviation is roughly three times Class A's, and its range
> is three times as wide.
> So "which did better" has no single answer, and saying so is the
> correct response. Class A is far more consistent; Class B contains
> both the strongest and the weakest performances. If you care about
> the typical student, they are equivalent. If you care about who is
> struggling, Class B has students far below anything in Class A.
> What else you would want: the class sizes, the two distributions
> as side-by-side boxplots, and whether the classes were comparable
> to begin with. A mean with no $n$ attached is not yet a finding.

## Two variables, and the sample behind them

7. Choose the most appropriate graph for each, and justify in one
   line: (a) the proportion of students in each of four transport
   categories; (b) the shape of the commute-time distribution;
   (c) comparing commute times across four grades; (d) whether
   commute time is related to hours of sleep.
8. A school posts a poll on its social media account: *"Should the
   school day start later? Most students say the current start is
   too early."* It receives 240 responses, 78% of them yes. Name the
   sampling technique, identify at least two sources of bias, and
   say what you would do instead.
9. In a class data set, handspan and height have a correlation
   coefficient of $r = 0.72$. (a) Describe the relationship.
   (b) What does $r^2$ tell you? (c) Does a large handspan cause
   height?

> [!success]- Answer 7
> (a) **Bar graph**, or a circle graph if the four categories are
> exhaustive and non-overlapping so they genuinely form a whole.
> Categorical data, and the comparison is between category sizes.
> (b) **Histogram**, and try more than one interval width before you
> trust the shape — a stem-and-leaf plot also works at $n = 11$ and
> keeps the actual values visible.
> (c) **Side-by-side boxplots.** They put four five-number summaries
> on one axis and make differences in both centre and spread visible
> at once.
> (d) **Scatter plot.** Two numerical variables measured on the same
> individuals; nothing else will show direction, form, and strength.

> [!success]- Answer 8
> The technique is **voluntary response** — nobody was selected;
> people opted in. That alone disqualifies the result from
> representing the school.
> Sources of bias, at least four available:
> **Voluntary-response bias** — students who feel strongly about
> start times are far more likely to answer than students who do
> not care.
> **Sampling bias** — only students who follow the school's account
> could see it, which is not the student body.
> **Response bias from the wording** — the second sentence tells the
> respondent what most students supposedly think before asking the
> question. That is a leading prompt inside a measuring instrument.
> **Non-response bias** — 240 responses out of a school of, say,
> 900 tells you about the 27% who answered, not the other 73%.
> What to do instead: a **stratified random sample** by grade, drawn
> from the school's enrolment list, with a neutral question such as
> *"What time should the school day begin? 8:00 · 8:30 · 9:00 ·
> 9:30 · No preference"*, distributed so that non-responders can be
> followed up and counted. Then report the response rate, because a
> response rate is a finding.

> [!success]- Answer 9
> (a) A **moderate-to-strong positive linear** relationship: people
> with larger handspans tend to be taller, and the points cluster
> reasonably tightly around an upward line — but with visible
> scatter. At $r = 0.72$ you could not predict one person's height
> from their handspan with much confidence.
> (b) $r^2 = 0.72^2 \approx 0.52$, so the linear model accounts for
> about $52\%$ of the variation in height. Just under half is
> explained by something else, which is a more sobering statement
> than "$r = 0.72$" sounds.
> (c) No. Both are consequences of overall body size, growth, and
> genetics — a textbook **common-cause** relationship. Nothing about
> stretching your hand makes you taller. This is exactly the
> distinction [[Correlation and Causation]] exists to protect, and a
> strong $r$ never settles it.

%%curriculum-start%%
## Curriculum connection

![[B2.4]]

![[C1.2]]

![[C2.1]]

![[C2.2]]

![[C2.3]]

![[C2.4]]

![[D1.1]]

![[D1.2]]

![[D1.3]]

![[D1.5]]

![[D2.1]]

![[D2.2]]

![[D2.5]]

![[D3.1]]
%%curriculum-end%%
