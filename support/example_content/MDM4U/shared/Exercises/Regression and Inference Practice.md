---
title: Regression and Inference Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These follow [[Two-Variable Statistics]] and
[[Correlation and Causation]], and they carry Unit 4's work on
confidence and the reading of published claims. Technology does the
fitting — [[Using Desmos]] takes about four clicks — so every question
here is really about interpretation. Say what each number means *with
units attached*, and say what it does not mean.

Questions 1 to 4 use this data: eight students recorded hours spent
studying for a test, $x$, and the mark they earned, $y$.

| $x$ (hours) | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| $y$ (mark) | 52 | 58 | 57 | 65 | 68 | 72 | 70 | 79 |

Technology reports the line of best fit as
$\hat{y} = 3.54x + 49.2$ with $r = 0.97$.

## Fitting and predicting

1. Describe the relationship in the three required terms —
   direction, form, strength — then interpret the slope and the
   intercept in context. Which of the two is meaningful here?
2. (a) Predict the mark of a student who studies 5 hours. (b) The
   student who studied 7 hours scored 70. Find that point's
   residual and say what it means.
3. Use the model to predict the mark of a student who studies 20
   hours. What is wrong with the answer, and what is the name of the
   error?

> [!success]- Answer 1
> **Direction:** positive — more study hours go with higher marks.
> **Form:** roughly linear; the points rise steadily with no visible
> curve. **Strength:** very strong, $r = 0.97$, with the points
> hugging the line closely.
> **Slope:** $3.54$ marks per hour of study. Each additional hour is
> associated with a predicted increase of about three and a half
> marks. Note "associated with", not "causes" — that distinction is
> question 6.
> **Intercept:** $49.2$ is the predicted mark for a student who
> studies zero hours. Unlike most intercepts, this one is
> interpretable, because $x = 0$ is a real and plausible amount of
> studying and it sits just outside the observed range of 1 to 8
> hours. Even so, it is an extrapolation of one unit and should be
> quoted with that caveat.

> [!success]- Answer 2
> (a) $\hat{y} = 3.54(5) + 49.2 = 17.7 + 49.2 = 66.9$, so about
> **67**.
> (b) At $x = 7$, $\hat{y} = 3.54(7) + 49.2 = 24.78 + 49.2 = 73.98$.
> $$\text{residual} = y - \hat{y} = 70 - 73.98 = -3.98$$
> The residual is about $-4$: this student scored roughly four marks
> **below** what the model predicted for seven hours of study, so
> the point sits below the line. It is the largest residual in the
> set, which makes it worth a second look — but at $-4$ marks on a
> test it is well within ordinary variation, not an outlier
> demanding explanation.

> [!success]- Answer 3
> $\hat{y} = 3.54(20) + 49.2 = 70.8 + 49.2 = 120$.
> A mark of 120 out of 100 is impossible, and the model produced it
> without complaint — models do not know what your variables mean.
> The error is **extrapolation**: using a model far outside the
> range of the data it was built from. The data covers 1 to 8 hours;
> nothing in it says the relationship stays linear at 20. In reality
> the returns to studying flatten out, and the true relationship over
> a wider range is almost certainly curved. Predict inside your data
> (interpolation) and be very cautious just outside it.

## Correlation, causation, and residuals

4. (a) Compute $r^2$ and interpret it. (b) Suppose the residuals,
   plotted against $x$, formed a clear U shape rather than random
   scatter. What would that tell you?
5. Classify each relationship as cause-and-effect, common-cause,
   reverse cause-and-effect, accidental, or presumed, with a
   one-line justification: (a) the age of a tree and its diameter;
   (b) ice cream sales and forest fires across a year; (c) the
   consumer price index and the number of known planets; (d) the
   number of firefighters sent to a fire and the damage the fire
   causes; (e) eating breakfast and getting better marks.
6. A student's report concludes: *"Since $r = 0.97$, studying causes
   higher marks."* Write a two-sentence response, and describe a
   study design that could support a causal claim.

> [!success]- Answer 4
> (a) $r^2 = 0.97^2 \approx 0.94$. About $94\%$ of the variation in
> marks is accounted for by the linear relationship with study
> hours — leaving roughly $6\%$ to everything else: prior knowledge,
> sleep, test-day conditions, luck with which topics appeared.
> That is an unusually high figure for real educational data, and
> with only eight students you should treat it as a property of this
> small sample rather than a law about studying.
> (b) A U-shaped residual plot means the *line* is wrong, not the
> relationship. Systematic structure left over in the residuals says
> the data is curved and a linear model has been forced onto it —
> the model over-predicts in the middle and under-predicts at both
> ends. The response is to fit a non-linear model, not to reach for
> a bigger $r$. This is why you look at residuals at all: $r$ can be
> respectable while the model is plainly the wrong shape.

> [!success]- Answer 5
> (a) **Cause and effect.** Growth over time physically produces the
> extra diameter; the mechanism is direct and well understood.
> (b) **Common cause.** Hot dry summer weather drives both ice cream
> sales and fire risk. Neither variable touches the other.
> (c) **Accidental.** Two unrelated quantities that happened to
> drift upward over the same span. There is no mechanism and no
> reason to expect the pattern to continue.
> (d) **Common cause** — the severity of the fire drives both the
> number of firefighters dispatched and the damage done. Read
> carelessly it looks like firefighters cause damage, which is the
> point of the example.
> (e) **Presumed.** The story is plausible and the correlation is
> real, but students who eat breakfast differ from those who do not
> in household routine, sleep, and income, any of which could be
> doing the work. Plausible plus correlated is not evidence.

> [!success]- Answer 6
> A defensible response: *"An $r$ of 0.97 shows a very strong linear
> association in these eight students, but association is not
> causation — students who choose to study more may also differ in
> prior achievement, sleep, and motivation, any of which could
> explain the marks. The sample is also far too small, and
> self-selected, to support a general claim."*
> A design that could support causation: **randomly assign** a large
> group of comparable students to prescribed amounts of study time,
> hold the test and teaching constant, and compare mean marks across
> groups. Random assignment is what spreads the unknown confounders
> evenly, and it is the only tool that does. (Whether such a study
> would be ethical or practical in a school is a separate and
> genuine question, which is exactly why so much education research
> is observational.)

## Confidence, margin of error, and claims in the media

7. A news report says: *"45% of Ontarians support the proposal.
   Results are accurate to within 3 percentage points, 19 times out
   of 20."* (a) State the interval. (b) Explain what "19 times out
   of 20" means. (c) Give one common misinterpretation and correct
   it.
8. Poll A surveys 400 people and poll B surveys 1600, both at the
   95% confidence level with results near 50%. (a) Roughly what is
   each margin of error? (b) If you wanted to halve poll B's margin
   again, how many people would you need? (c) Why do national polls
   rarely exceed a couple of thousand respondents?
9. A company's annual report shows a bar graph of profits from 2001
   to 2007. The vertical axis begins at 17 billion dollars and ends
   at 23, and the bars rise gradually across the seven years. The
   headline reads *"Big Increase in Profits"*. Give three reasons the
   headline may be misleading, and one way it might be fair.

> [!success]- Answer 7
> (a) $45\% \pm 3\%$, so the interval runs from $42\%$ to $48\%$.
> (b) "19 times out of 20" is a $95\%$ confidence level. It
> describes the **method**: if the same polling procedure were
> repeated many times, about 19 of every 20 intervals produced would
> contain the true population value.
> (c) The common misreading is *"there is a 95% chance the true
> value is between 42% and 48%"*, which treats the unknown true
> value as random. It is not — it is a fixed number; the interval is
> what varies from poll to poll. A second, more damaging
> misreading: that support "went up" because a previous poll said
> $42\%$. If both polls carry $\pm 3$ points, those results overlap
> completely and the data shows no change at all. Newspapers make
> that error constantly.

> [!success]- Answer 8
> (a) The margin of error shrinks with the square root of the
> sample size. For a result near $50\%$ at the $95\%$ level:
> $$\text{poll A} \approx \frac{1.96 \times 0.5}{\sqrt{400}} = 0.049 \qquad \text{poll B} \approx \frac{1.96 \times 0.5}{\sqrt{1600}} = 0.0245$$
> About $\pm 4.9$ points and $\pm 2.5$ points. Four times the sample
> halved the margin — which is the relationship you investigated
> with technology, seen in two numbers.
> (b) Halving again requires quadrupling again: $6400$ respondents,
> for a margin near $\pm 1.2$ points.
> (c) Because the cost is linear in respondents while the benefit
> goes as $\sqrt{n}$. Going from 1600 to 6400 quadruples the budget
> to gain about 1.2 percentage points — and at that scale, bias from
> non-response and question wording is far larger than the
> remaining sampling error. Buying more respondents cannot fix a
> problem that is not sampling error, which is the lesson of
> [[Bias]].

> [!success]- Answer 9
> **Reason one: the axis.** Starting the vertical scale at 17
> instead of 0 exaggerates the visual difference between the bars.
> A bar for 22 looks several times taller than a bar for 18, when
> the real increase is under a quarter. Every bar's height is
> honest; the *impression* is not.
> **Reason two: "big" is undefined.** Roughly 17.5 to 22.5 billion
> over six years is real growth, but whether it is big depends on
> inflation, on company size, and on what competitors did. A
> percentage change or an inflation-adjusted series would settle it;
> the graph offers neither.
> **Reason three: the window.** Seven years were chosen by someone.
> If profits were higher in 1999, or fell sharply in 2008, a
> different window tells a different story. Ask what happened
> outside the frame.
> **How it might be fair:** if profits genuinely rose steadily by
> about $28\%$ over six years, that is a real and substantial
> increase, and the headline is defensible as a summary of the
> trend. The graph would be honest with a zero-based axis, a stated
> source, and a note on whether the figures are adjusted for
> inflation — at which point readers could judge "big" for
> themselves. That is the standard [[The Statistical Claim Report]]
> holds you to as well.

%%curriculum-start%%
## Curriculum connection

![[D2.1]]

![[D2.2]]

![[D2.3]]

![[D2.4]]

![[D2.5]]

![[D3.1]]

![[D3.2]]

![[E1.5]]
%%curriculum-end%%
