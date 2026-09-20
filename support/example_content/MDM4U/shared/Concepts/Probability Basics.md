---
title: Probability Basics
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
On the first day of this course [[The Birthday Problem]] took a room
of confident people and made them wrong together. Twenty-three
students, better-than-even odds of a shared birthday — nobody's
intuition survived the reveal. That was the point. Probability is the
tool you build precisely because intuition is unreliable here, and the
tool starts with three plain words: outcome, sample space, event.

## Sample spaces, events, and the numbers between 0 and 1

An **outcome** is one result of an experiment. The **sample space** is
the set of all of them. An **event** is a subset of the sample space —
a collection of outcomes you happen to care about.

Roll two number cubes and record the sum. The sample space is the $36$
ordered pairs; "the sum is 7" is an event containing $6$ of them; its
probability is $\frac{6}{36} = \frac{1}{6}$.

A sample space is **discrete** when its outcomes can be counted —
cards drawn, coins tossed, sums rolled. It is **continuous** when its
outcomes are measured — the time a task takes, the distance a ball is
thrown. Unit 1 lives entirely in discrete spaces; the continuous ones
wait for [[The Normal Distribution]], where "how likely is exactly
this value?" stops making sense.

Every outcome carries a probability $P_i$ between $0$ and $1$, and
across a whole sample space those probabilities sum to exactly $1$:

$$P_1 + P_2 + P_3 + \cdots + P_n = 1$$

That sum is your cheapest error check. If your probabilities do not
total $1$, you have either missed an outcome or double-counted one,
and no amount of further work will fix it.

## Complements, unions, and the overlap

The **complement** of $A$, written $\sim\!A$, is everything in the
sample space that is not $A$, so $P(\sim\!A) = 1 - P(A)$. Whenever a
question says "at least one", check the complement first: the chance
of at least one head in four coin tosses is
$1 - \frac{1}{16} = \frac{15}{16}$, and the alternative is summing
four separate cases for no reason.

Two events are **mutually exclusive** when they cannot both occur. For
those, $P(A \text{ or } B) = P(A) + P(B)$. For events that *can*
overlap, adding alone counts the overlap twice, so subtract it once:

$$P(A \text{ or } B) = P(A) + P(B) - P(A \text{ and } B)$$

Draw one card: $P(\text{heart or face card}) = \frac{13}{52} +
\frac{12}{52} - \frac{3}{52} = \frac{11}{26}$, where the $3$ is the
jack, queen, and king of hearts, who are in both sets and get one
seat, not two. A Venn diagram makes this obvious and is never a waste
of thirty seconds.

## Theoretical, experimental, and the long run

A **theoretical** probability is calculated from the structure of the
sample space. An **experimental** probability is the fraction of times
the event actually happened in trials you ran. In [[The Simulation]]
your group watched the second creep toward the first: ten trials
wandered wildly, a hundred settled, a thousand hugged the theoretical
value closely. More trials, closer agreement — that tendency is the
bridge between the mathematics and the world.

> [!warning] The long run has no memory
> "Closer agreement over many trials" does **not** mean a coin that
> has landed heads six times is now due for tails. The coin cannot
> remember. What actually happens is that six heads become a smaller
> and smaller fraction of a growing pile of tosses — the early
> imbalance is diluted, never corrected. Every casino, every lottery
> advertisement, and a surprising number of sports commentators live
> in the gap between those two sentences.

Everything above assumes the outcomes are simply there to be counted.
The moment one event changes the odds of another, you need the next
page — [[Conditional Probability]] — and the moment you want to attach
a *number* to each outcome rather than a name, you need
[[Random Variables and Distributions]]. Consolidate this page in
[[Probability Practice]].

%%curriculum-start%%
## Curriculum connection

![[A1.1]]

![[A1.2]]

![[A1.3]]

![[A1.4]]

![[A1.5]]
%%curriculum-end%%
