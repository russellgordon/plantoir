---
title: The Binomial Distribution
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
Eight free throws, a shooter who makes 70% of them, and the question
on the board: what is the chance of exactly six? Your group got there
the honest way — one path, HHHHHHMM, has probability
$(0.7)^6(0.3)^2$, and then you started listing the other orders and
ran out of board. Somebody said "that is just choosing which two she
misses", wrote $\binom{8}{2}$, and the room exhaled. That move — one
path's probability, times the number of paths — is the binomial
distribution entire.

## The four conditions

A random variable is binomial when all four of these hold. Check them
in order; the fourth is the one people skip.

> [!tip] Spotting a binomial situation
> 1. A **fixed** number of trials, $n$, decided before you start.
> 2. Each trial has exactly **two** outcomes — success or failure,
>    however you choose to label them.
> 3. The probability of success, $p$, is the **same** on every trial.
> 4. The trials are **independent**: no result affects any other.
>
> Drawing cards *with* replacement is binomial. Drawing them
> *without* replacement is not, because condition 3 and condition 4
> both break the moment the deck changes. That situation has its own
> page — [[The Hypergeometric Distribution]].

## The formula, and where it comes from

$$P(X = x) = \binom{n}{x} p^{x} (1-p)^{n-x}$$

Read it in three pieces. $p^x$ is the probability of the successes.
$(1-p)^{n-x}$ is the probability of the failures. $\binom{n}{x}$
counts how many different orders those successes could arrive in — and
it is exactly the entry from row $n$ of [[Pascal's Triangle]], which
is why the triangle you built in Unit 1 turns up in Unit 2 without
being invited.

The free throws: $P(X = 6) = \binom{8}{6}(0.7)^6(0.3)^2 =
28 \times 0.117649 \times 0.09 \approx 0.296$. Close to a coin flip
for a shooter who is far better than a coin flip — because "exactly
six" excludes seven and eight, and exactness is expensive.

A manufacturer's example runs the other way. If $0.5\%$ of bulbs are
defective and you buy $4$:

| $x$ defective | $P(X = x)$ |
| --- | --- |
| 0 | $0.9801$ |
| 1 | $0.0197$ |
| 2 | $0.000149$ |
| 3 | $0.0000005$ |
| 4 | $0.0000000006$ |

The column sums to $1$, as every distribution must, and the shape is
violently skewed — nothing like a bell. Binomial distributions are
symmetric only when $p = 0.5$.

## The mean of a binomial

You could compute $E(X) = \sum x P(X=x)$ every time. You do not have
to, because the answer is always

$$\mu = np$$

which is what intuition guessed before the formula arrived: 8 shots at
70% should average $5.6$ makes; 4 bulbs at $0.5\%$ should average
$0.02$ defectives. When a shortcut and your intuition agree, that is
not a reason to distrust either.

## Comparing distributions

Hold $p$ fixed and let $n$ grow, and something happens that Unit 2
spends real time on: the histogram becomes more symmetric, its peak
sharper relative to its width, and it starts to look like a bell.
Simulate it — [[Simulating with Python]] does this in about six lines
— and the connection to [[The Normal Distribution]] stops being a
claim you were asked to believe and becomes a thing you watched.

That relationship is genuinely useful. For large $n$ the exact
binomial sum for "at least 60 heads in 100 tosses" is a nuisance; the
normal approximation gets you there in one $z$-score. Just remember
which one is the truth and which one is the convenience.

Work the formula until it is automatic in [[Distributions Practice]],
and take it into your investigation whenever your data is a count of
successes out of a fixed number of tries.

%%curriculum-start%%
## Curriculum connection

![[B1.4]]

![[B1.6]]

![[B1.7]]

![[B2.7]]
%%curriculum-end%%
