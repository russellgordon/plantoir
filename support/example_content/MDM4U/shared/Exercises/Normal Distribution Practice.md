---
title: Normal Distribution Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These follow [[The Normal Distribution]]. Sketch the curve for every
question, shade the region you want, and estimate the answer from the
68–95–99.7 rule *before* you compute. The sketch catches the sign
errors and the table misreadings, which between them account for
nearly every wrong answer in this topic. Table values below are quoted
to four decimal places for $z$ rounded to two.

## Reading the curve

1. A test is normally distributed with $\mu = 72$ and $\sigma = 8$.
   Find the $z$-score of (a) 88 and (b) 60. (c) What percentage of
   students scored between 60 and 88?
2. Heights in a population are normal with $\mu = 170$ cm and
   $\sigma = 8$ cm. Using only the 68–95–99.7 rule, find the
   percentage of people (a) between 162 cm and 178 cm, (b) taller
   than 186 cm, (c) shorter than 146 cm.
3. Priya scored 86 on a chemistry test where $\mu = 74$ and
   $\sigma = 6$. In the pool she swam 58.2 s where the club mean is
   60.0 s with $\sigma = 1.2$ s, and lower times are better. In which
   event was her performance more exceptional?

> [!success]- Answer 1
> (a) $z = \frac{88 - 72}{8} = 2$.
> (b) $z = \frac{60 - 72}{8} = -1.5$. The negative sign is
> information, not an error — it says "below the mean".
> (c) Area to the left of $z = 2$ is $0.9772$; area to the left of
> $z = -1.5$ is $0.0668$. Subtract:
> $$0.9772 - 0.0668 = 0.9104$$
> About $91.0\%$ of students. Sanity check against the rule: the
> region runs from 1.5 standard deviations below to 2 above, so it
> should be a bit more than 95% minus a bit — and 91% is
> comfortably plausible.

> [!success]- Answer 2
> (a) $162 = \mu - \sigma$ and $178 = \mu + \sigma$, so this is
> exactly $\mu \pm 1\sigma$: about $68\%$.
> (b) $186 = \mu + 2\sigma$. About $95\%$ lies within two standard
> deviations, leaving $5\%$ split evenly between the two tails, so
> about $2.5\%$ are taller.
> (c) $146 = \mu - 3\sigma$. About $99.7\%$ lies within three, so
> $0.3\%$ is split between the tails and about $0.15\%$ are shorter.
> One person in roughly 667 — which is why "three sigma" is
> shorthand for genuinely rare.

> [!success]- Answer 3
> Chemistry: $z = \frac{86 - 74}{6} = 2.0$, so she is two standard
> deviations **above** the mean, at about the $97.7$th percentile.
> Swimming: $z = \frac{58.2 - 60.0}{1.2} = -1.5$. Here below the
> mean is good, so she is 1.5 standard deviations into the fast side
> — faster than about $93.3\%$ of the club.
> The chemistry result is more exceptional, because $2.0$ standard
> deviations in the favourable direction beats $1.5$. Standardizing
> is what let you compare a mark to a swim time at all: the raw
> numbers 86 and 58.2 have nothing to say to each other, but two
> $z$-scores do.

## Areas and z-scores

4. The heights of 16-month-old maple seedlings are normal with
   $\mu = 32$ cm and $\sigma = 10.2$ cm. Find the probability that a
   randomly chosen seedling is between 24.0 cm and 38.0 cm.
5. For the test in question 1, what score marks the 90th percentile?
6. A bulb's life is normal with $\mu = 1200$ hours and
   $\sigma = 100$ hours. The manufacturer wants at most 1% of bulbs
   to fail before the guarantee expires. How long should the
   guarantee be?
7. What proportion of a normal distribution lies more than 1.75
   standard deviations above the mean?

> [!success]- Answer 4
> $$z_1 = \frac{24 - 32}{10.2} \approx -0.78 \qquad z_2 = \frac{38 - 32}{10.2} \approx 0.59$$
> Areas to the left: $0.2177$ and $0.7224$. Subtract:
> $0.7224 - 0.2177 = 0.5047$, so about $50.5\%$.
> Rounding the $z$-scores to two decimals costs a little accuracy —
> unrounded the answer is $0.5054$ — which is a difference of under
> a tenth of a percentage point and never matters at this level.
> What does matter: about half the seedlings fall in a 14 cm window
> around the mean, which tells you immediately that $\sigma = 10.2$
> is a lot of spread for a 32 cm plant.

> [!success]- Answer 5
> The 90th percentile is the score with $0.9000$ of the area to its
> left. Reading the table backwards, the closest entry is
> $z = 1.28$ (area $0.8997$). Then undo the standardizing:
> $$x = \mu + z\sigma = 72 + 1.28(8) = 82.24$$
> About $82$. Check the direction: the 90th percentile must be above
> the mean, and $82 > 72$. ✓ Going backwards from area to score is
> the most common exam variant of this topic and the one most people
> practise least.

> [!success]- Answer 6
> You want the time $x$ with only $1\%$ of the area to its **left**.
> Reading the table backwards for an area of $0.0100$ gives
> $z = -2.33$ (area $0.0099$).
> $$x = 1200 + (-2.33)(100) = 967$$
> So a guarantee of about **967 hours** — call it 960 to be safe.
> Note the trade-off the manufacturer is making: a 1000-hour
> guarantee would correspond to $z = -2.0$ and a failure rate of
> about $2.3\%$, more than double the returns for 33 extra hours of
> advertising.

> [!success]- Answer 7
> Area to the left of $z = 1.75$ is $0.9599$, so the area to the
> right is $1 - 0.9599 = 0.0401$, about $4.0\%$.
> Sanity check with the rule: more than $1\sigma$ above the mean is
> about $16\%$, and more than $2\sigma$ above is about $2.5\%$. A
> $z$ of $1.75$ sits between those, so an answer of $4\%$ is in the
> right neighbourhood. If you had computed $40\%$ or $0.4\%$, the
> rule would have caught it instantly.

## Approximation, and knowing when not to

8. A fair coin is tossed 100 times. Use a normal approximation to
   estimate the probability of getting at least 60 heads. The exact
   binomial answer is $0.0284$ — how close do you get?
9. Which of these would you model with a normal distribution, and
   which would you refuse to? (a) Heights of 17-year-olds. (b)
   Household incomes in a city. (c) Repeated careful measurements of
   one fixed length. (d) Time customers spend waiting on hold.

10. A continuous random variable $X$ models the battery life of a laptop
    (in hours) as normal with $\mu = 8.0$ and $\sigma = 1.2$.
    (a) What is the theoretical probability that a randomly tested
    laptop runs for *exactly* 8.000000 hours, $P(X = 8.0)$? Explain why.
    (b) Find the probability that a laptop runs between 7.0 and 9.0
    hours. (c) Explain why probabilities for continuous random variables
    must be defined over intervals rather than single points.

> [!success]- Answer 8
> The count of heads is binomial with $n = 100$ and $p = 0.5$, so
> $\mu = np = 50$ and $\sigma = \sqrt{np(1-p)} = \sqrt{25} = 5$.
> Because a discrete count is being approximated by a continuous
> curve, use the continuity correction and treat "at least 60" as
> "above 59.5":
> $$z = \frac{59.5 - 50}{5} = 1.90$$
> Area to the left is $0.9713$, so $P(X \geq 60) \approx 1 - 0.9713
> = 0.0287$. Against the exact $0.0284$, that is an error of
> $0.0003$ — excellent.
> Skipping the continuity correction gives $z = 2.00$ and $0.0228$,
> which is off by about 20% of the answer. The correction is worth
> the half-unit of care.

> [!success]- Answer 9
> **(a) Yes.** Height is the sum of many small independent genetic
> and environmental contributions, which is the classic recipe for a
> normal shape. Within a single age and sex group it fits well.
> **(b) No.** Incomes are strongly right-skewed: bounded below by
> zero, unbounded above, with a long thin tail of very high earners
> that drags the mean well above the median. Treating them as normal
> would predict as many people far below the mean as far above, and
> there is no such thing as an income of negative \$60 000.
> **(c) Yes.** Measurement error around a true value is close to the
> textbook case — small independent errors in both directions.
> **(d) No.** Waiting times are right-skewed and bounded below by
> zero. Many short waits, a few very long ones, no negative waits.
> The habit worth taking away: look at the histogram before you
> reach for the curve. "Keeps appearing" is not "always appears",
> and confidently applying a normal model to skewed data is one of
> the tidiest ways to be wrong in [[The Culminating Investigation]].

> [!success]- Answer 10
> (a) $P(X = 8.0) = 0$. For any continuous random variable, the sample
> space contains infinitely many outcomes. The area of a vertical line
> segment with width 0 under a continuous density curve is 0.
> (b) Standardize both bounds:
> $$z_1 = \frac{7.0 - 8.0}{1.2} \approx -0.83 \qquad z_2 = \frac{9.0 - 8.0}{1.2} \approx 0.83$$
> Areas to the left: $0.2033$ and $0.7967$. Subtract:
> $0.7967 - 0.2033 = 0.5934$, so about $59.3\%$.
> (c) Because probability corresponds to the area under the continuous
> probability density curve. An interval $[a, b]$ has non-zero width
> $\Delta x > 0$ and thus positive area, whereas a single point has zero
> width. Continuous probability distributions assign probabilities to
> ranges of values, forming a continuous model.

%%curriculum-start%%
## Curriculum connection

![[B2.1]]

![[B2.3]]

![[B2.5]]

![[B2.6]]

![[B2.7]]

![[B2.8]]

![[D1.4]]
%%curriculum-end%%
