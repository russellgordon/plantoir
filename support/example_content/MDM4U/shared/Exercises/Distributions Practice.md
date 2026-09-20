---
title: Distributions Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These follow [[Random Variables and Distributions]],
[[Expected Value]], [[The Binomial Distribution]], and
[[The Hypergeometric Distribution]]. Use technology for the
arithmetic — [[Using a Spreadsheet for Statistics]] handles all of it
— and spend your effort on two decisions: what is the random
variable, and which model applies. Every distribution you write must
have probabilities summing to $1$; check that before you go any
further.

## Random variables and expected value

1. Two fair coins are tossed and $X$ is the number of heads.
   (a) Write the probability distribution as a table. (b) Verify the
   probabilities sum to 1. (c) Find $E(X)$ and interpret it.
2. Of six sealed cases, three each hold \$1, two each hold \$1000,
   and one holds \$100 000. (a) Find the expected value. (b) Predict
   what happens to it if \$10 000 is added to every case, then
   verify. (c) Predict and verify what happens if every amount is
   multiplied by 10.
3. A carnival booth charges \$1 to play and pays \$5 with probability
   $0.1$, nothing otherwise. (a) Find the expected gain per play for
   the player. (b) What prize would make the game fair? (c) What is
   the booth's expected profit over 500 plays?
4. Two number cubes are rolled and $X$ is the sum. (a) Generate the
   related probability distribution table. (b) Describe the probability
   histogram for $X$ (with bars of width 1 centred on each integer sum),
   determine the total area of the bars, and explain your result.
   (c) Find $E(X)$ using the full distribution, then explain the answer
   in one sentence without summing anything. (d) How does this
   theoretical probability histogram compare with a frequency histogram
   from 100 actual rolls?

> [!success]- Answer 1
> (a) The sample space is HH, HT, TH, TT, all equally likely.
>
> | $x$ | 0 | 1 | 2 |
> | --- | --- | --- | --- |
> | $P(X = x)$ | $\frac{1}{4}$ | $\frac{1}{2}$ | $\frac{1}{4}$ |
>
> (b) $\frac{1}{4} + \frac{1}{2} + \frac{1}{4} = 1$. ✓
> (c) $E(X) = 0\left(\frac{1}{4}\right) + 1\left(\frac{1}{2}\right)
> + 2\left(\frac{1}{4}\right) = 1$. Over many pairs of tosses you
> average one head per pair — and here the expected value is also a
> possible outcome, which is a coincidence of this symmetric case,
> not a rule.

> [!success]- Answer 2
> (a) Weight each amount by its probability:
> $$E(X) = \frac{3}{6}(1) + \frac{2}{6}(1000) + \frac{1}{6}(100\,000) = \frac{102\,003}{6} = 17\,000.5$$
> So \$17 000.50 — a number that is in none of the cases, and far
> above what five of the six players would actually receive.
> (b) Adding a constant to every value shifts the expected value by
> that constant: \$27 000.50. Verify:
> $\frac{3}{6}(10\,001) + \frac{2}{6}(11\,000) +
> \frac{1}{6}(110\,000) = 27\,000.5$. ✓
> (c) Multiplying every value by 10 multiplies the expected value by
> 10: \$170 005.00. Both properties fall straight out of the
> formula, and both are worth trusting because you checked them.

> [!success]- Answer 3
> (a) Work in net dollars. Winning nets $5 - 1 = 4$; losing nets
> $-1$.
> $$E(\text{gain}) = 0.1(4) + 0.9(-1) = 0.4 - 0.9 = -0.50$$
> The player loses 50 cents per play on average.
> (b) Let the prize be $p$ dollars. Fairness needs
> $0.1(p - 1) + 0.9(-1) = 0$, so $0.1p = 1$ and $p = 10$. A \$10
> prize makes the game fair — double the current one.
> (c) The booth gains what the player loses:
> $500 \times 0.50 = 250$, so \$250 expected profit over 500 plays.
> Note how reliable that is for the booth and how invisible it is to
> any single player, who wins \$4 or loses \$1 and never loses 50
> cents.

> [!success]- Answer 4
> (a) The distribution is $\frac{1}{36}, \frac{2}{36}, \ldots,
> \frac{6}{36}, \ldots, \frac{2}{36}, \frac{1}{36}$ for sums 2
> through 12.
> (b) Each rectangle has a base of width 1 centred on the integer sum
> $x$ (from $x = 2$ to $x = 12$) and height equal to $P(X = x)$. The area
> of each bar is $\text{base} \times \text{height} = 1 \times P(X = x) = P(X = x)$.
> Total area $= \sum P(X = x) = \frac{36}{36} = 1$. The total area
> equals 1 because the histogram represents a complete probability
> distribution accounting for all outcomes in the sample space.
> (c) $$E(X) = \sum x\,P(X = x) = \frac{1(2) + 2(3) + \cdots + 2(11) + 1(12)}{36} = \frac{252}{36} = 7$$
> The one-sentence version: each cube has expected value $3.5$, and
> the expected value of a sum is the sum of the expected values, so
> $3.5 + 3.5 = 7$. The distribution is also symmetric about 7, so
> the mean has to sit there.
> (d) A frequency histogram has raw counts on the vertical axis and
> will show sample variability with 100 rolls. Dividing each count by
> 100 converts frequencies into relative frequencies, which approximate
> the symmetric tent shape of the theoretical probability histogram and
> converge to it as the number of trials increases.

## Binomial

5. A manufacturer estimates that $0.5\%$ of its bulbs are defective.
   You buy 4. (a) Explain why this is binomial. (b) Give the
   probability distribution for the number of defective bulbs.
   (c) Find the probability of at least one defective bulb.
6. A player makes 70% of her free throws, and shots are independent.
   In 8 attempts, find (a) $P(\text{exactly } 6)$, (b)
   $P(\text{at least } 6)$, and (c) the expected number of makes.
7. The probability that a business traveller cancels a hotel
   reservation is estimated at 8%. With 10 reservations, find the
   probability that at least 4 are cancelled, and comment on whether
   the hotel should worry.

> [!success]- Answer 5
> (a) Four checks: a fixed number of trials ($n = 4$); two outcomes
> per bulb (defective or not); the same probability each time
> ($p = 0.005$, because the production run is enormous compared with
> your four bulbs); and independence between bulbs.
> (b) $P(X = x) = \binom{4}{x}(0.005)^x (0.995)^{4-x}$:
>
> | $x$ | 0 | 1 | 2 | 3 | 4 |
> | --- | --- | --- | --- | --- | --- |
> | $P(X = x)$ | $0.980150$ | $0.019701$ | $0.000149$ | $0.0000005$ | $0.0000000006$ |
>
> The column sums to $1$. ✓
> (c) Complement: $1 - (0.995)^4 = 1 - 0.980150 = 0.019850$, about
> $2.0\%$. Notice the shape — violently skewed, nothing like a bell.
> Binomial distributions are symmetric only when $p = 0.5$.

> [!success]- Answer 6
> With $n = 8$ and $p = 0.7$:
> (a) $P(X = 6) = \binom{8}{6}(0.7)^6 (0.3)^2 = 28 \times 0.117649
> \times 0.09 \approx 0.2965$.
> (b) Add the top three cases.
> $P(X = 7) = 8(0.7)^7(0.3) \approx 0.19765$ and
> $P(X = 8) = (0.7)^8 \approx 0.05765$.
> $$P(X \geq 6) \approx 0.29648 + 0.19765 + 0.05765 = 0.5518$$
> Just over half the time she makes at least 6 of 8.
> (c) $\mu = np = 8 \times 0.7 = 5.6$ makes. Consistent with (b):
> the expected value sits between 5 and 6, so "at least 6" landing
> near a coin flip is exactly what it should be.

> [!success]- Answer 7
> $n = 10$, $p = 0.08$, and $X$ is the number of cancellations.
> $P(X \geq 4) = 1 - P(X \leq 3)$, and summing
> $\binom{10}{x}(0.08)^x(0.92)^{10-x}$ for $x = 0, 1, 2, 3$ gives
> $0.43439 + 0.37773 + 0.14781 + 0.03427 \approx 0.99420$.
> $$P(X \geq 4) \approx 1 - 0.99420 = 0.0058$$
> About $0.58\%$ — roughly one night in 170. The expected number of
> cancellations is $np = 0.8$, so four is well out in the tail. The
> honest comment is that the hotel should not worry about *this*,
> but the model assumes cancellations are independent, and a
> snowstorm or a cancelled conference makes them anything but. When
> the independence assumption fails, the real risk is far larger
> than $0.58\%$.

## Hypergeometric, and choosing a model

8. A 5-card hand is dealt from a standard deck and $X$ is the number
   of hearts. Find $P(X = 2)$ and explain why this is not binomial.
9. A committee of 4 is chosen at random from 7 women and 5 men.
   (a) Find the probability of exactly 2 women. (b) Find the mean
   number of women on such a committee.
10. Three cards are drawn from a deck and you want exactly one face
    card. Compute the probability (a) if each card is replaced before
    the next draw, and (b) if it is not. Which model is which, and
    why do the answers differ in the direction they do?

> [!success]- Answer 8
> Choose 2 of the 13 hearts and 3 of the 39 non-hearts, out of all
> 5-card hands:
> $$P(X = 2) = \frac{\binom{13}{2}\binom{39}{3}}{\binom{52}{5}} = \frac{78 \times 9139}{2\,598\,960} \approx 0.2743$$
> It is not binomial because the cards are dealt without
> replacement. After the first heart is dealt, only 12 hearts remain
> among 51 cards, so the probability of a heart changes from
> $\frac{13}{52} = 0.25$ to $\frac{12}{51} \approx 0.235$. Both the
> constant-$p$ condition and the independence condition fail, which
> is precisely what makes this hypergeometric.

> [!success]- Answer 9
> Population $n = 12$, successes $a = 7$ (women), sample $r = 4$.
> (a) $$P(X = 2) = \frac{\binom{7}{2}\binom{5}{2}}{\binom{12}{4}} = \frac{21 \times 10}{495} = \frac{14}{33} \approx 0.424$$
> (b) $\mu = r \cdot \frac{a}{n} = 4 \times \frac{7}{12} =
> \frac{7}{3} \approx 2.33$ women. That is the sample size times the
> population's proportion of women — which is what "representative
> on average" means, written as one line of arithmetic.

> [!success]- Answer 10
> There are 12 face cards among 52.
> (a) **With replacement is binomial**, with $n = 3$ and
> $p = \frac{12}{52} = \frac{3}{13}$:
> $$P(X = 1) = \binom{3}{1}\left(\frac{3}{13}\right)\left(\frac{10}{13}\right)^2 = \frac{900}{2197} \approx 0.4096$$
> (b) **Without replacement is hypergeometric**:
> $$P(X = 1) = \frac{\binom{12}{1}\binom{40}{2}}{\binom{52}{3}} = \frac{12 \times 780}{22\,100} = \frac{36}{85} \approx 0.4235$$
> The without-replacement answer is slightly larger. Removing a
> non-face card makes the remaining deck a little richer in face
> cards, and removing a face card makes a second one less likely —
> together these pull probability toward the middle of the
> distribution and away from the extremes of 0 and 3 face cards.
> The gap here is about $0.014$, small because 3 cards is a small
> fraction of 52. Draw 26 cards and the two models would disagree
> wildly.

%%curriculum-start%%
## Curriculum connection

![[A1.2]]

![[B1.1]]

![[B1.2]]

![[B1.3]]

![[B1.4]]

![[B1.5]]

![[B1.6]]

![[B1.7]]

![[B2.1]]
%%curriculum-end%%
