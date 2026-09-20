---
title: Probability Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These follow [[Probability Basics]]. Start every question by naming
the sample space out loud — how many outcomes, and are they equally
likely? Half of what goes wrong in probability goes wrong before any
arithmetic happens, in an unexamined assumption about what the
outcomes are.

## Sample spaces and simple events

1. Two number cubes are rolled and the sum is recorded. (a) How many
   outcomes are in the sample space? (b) Find $P(\text{sum} = 7)$,
   (c) $P(\text{sum} = 11)$, and (d) $P(\text{sum} \geq 10)$.
2. Classify each sample space as discrete or continuous, and say why:
   (a) the number of text messages you receive tomorrow; (b) the time
   it takes you to run 100 m; (c) the suit of a card drawn from a
   deck; (d) the mass of an apple picked at random from a crate.
3. A spinner has 8 equal sectors numbered 1 to 8. Find
   (a) $P(\text{prime})$, (b) $P(\text{multiple of }3)$, and
   (c) $P(\text{prime or multiple of }3)$. Confirm (c) two ways.

> [!success]- Answer 1
> (a) Each cube is distinguishable, so the sample space is the $36$
> ordered pairs — *not* the 11 possible sums, which are not equally
> likely. Getting this wrong here poisons every later part.
> (b) Six pairs give 7 (1-6, 2-5, 3-4, 4-3, 5-2, 6-1), so
> $\frac{6}{36} = \frac{1}{6}$.
> (c) Two pairs give 11 (5-6 and 6-5), so
> $\frac{2}{36} = \frac{1}{18}$.
> (d) Sums of 10, 11, or 12 come from $3 + 2 + 1 = 6$ pairs, so
> $\frac{6}{36} = \frac{1}{6}$ — the same as rolling a 7, which
> surprises most people.

> [!success]- Answer 2
> (a) **Discrete.** You can count messages; there is no such thing as
> 4.3 of them.
> (b) **Continuous.** Time is measured, and between any two times
> there is another. Your stopwatch's two decimal places are a
> limitation of the instrument, not of the sample space.
> (c) **Discrete**, and also categorical — four outcomes with no
> numerical order.
> (d) **Continuous.** Mass is measured. Note the pattern: counted
> things are discrete, measured things are continuous, and it is the
> measured ones that will need [[The Normal Distribution]].

> [!success]- Answer 3
> The primes in 1 to 8 are $\{2, 3, 5, 7\}$; the multiples of 3 are
> $\{3, 6\}$.
> (a) $\frac{4}{8} = \frac{1}{2}$.
> (b) $\frac{2}{8} = \frac{1}{4}$.
> (c) By listing: the union is $\{2, 3, 5, 6, 7\}$, five sectors, so
> $\frac{5}{8}$. By formula, noting that 3 is in both sets so the
> overlap has probability $\frac{1}{8}$:
> $$P(A \text{ or } B) = \frac{1}{2} + \frac{1}{4} - \frac{1}{8} = \frac{5}{8}$$
> Adding without subtracting would have given $\frac{6}{8}$ —
> counting sector 3 twice.

## Complements, unions, and overlaps

4. Four fair coins are tossed. Find the probability of getting at
   least one head, and explain why the complement is the efficient
   route.
5. One card is drawn from a standard deck. Find (a) $P(\text{heart
   or face card})$ and (b) $P(\text{heart or spade})$. (c) Why did
   only one of them require a subtraction?
6. A bag holds 12 green marbles and 16 red. Two marbles are drawn.
   Find the probability that both are green (a) if the first is
   replaced, (b) if it is not. (c) Which is smaller, and why should
   that have been obvious?

> [!success]- Answer 4
> "At least one head" covers four separate cases — one, two, three,
> or four heads. Its complement is a single case: no heads at all,
> which is TTTT.
> $$P(\text{no heads}) = \left(\tfrac{1}{2}\right)^4 = \frac{1}{16}$$
> So $P(\text{at least one head}) = 1 - \frac{1}{16} =
> \frac{15}{16} = 0.9375$. Whenever a question says "at least",
> check the complement before you start listing cases.

> [!success]- Answer 5
> (a) There are 13 hearts and 12 face cards, but three cards — the
> jack, queen, and king of hearts — are in both groups.
> $\frac{13}{52} + \frac{12}{52} - \frac{3}{52} = \frac{22}{52} =
> \frac{11}{26} \approx 0.423$.
> (b) A card cannot be both a heart and a spade, so the events are
> mutually exclusive and you simply add:
> $\frac{13}{52} + \frac{13}{52} = \frac{26}{52} = \frac{1}{2}$.
> (c) Only (a) had an overlap. Adding alone would have counted those
> three royal hearts twice, inflating the answer to
> $\frac{25}{52}$. A quick Venn diagram makes the difference visible
> in seconds.

> [!success]- Answer 6
> There are $12 + 16 = 28$ marbles in total.
> (a) With replacement the second draw faces the same bag:
> $\frac{12}{28} \times \frac{12}{28} = \frac{3}{7} \times
> \frac{3}{7} = \frac{9}{49} \approx 0.1837$.
> (b) Without replacement, one green is gone and only 27 marbles
> remain: $\frac{12}{28} \times \frac{11}{27} = \frac{3}{7} \times
> \frac{11}{27} = \frac{11}{63} \approx 0.1746$.
> (c) Without replacement is smaller. Removing a green marble makes
> the bag *less* green for the second draw, so the second factor
> drops from $\frac{12}{28} \approx 0.429$ to
> $\frac{11}{27} \approx 0.407$. The second factor in (b) is a
> conditional probability, which is the whole subject of
> [[Conditional Probability]].

## Probability by counting

7. A student rolls a number cube 60 times and records 14 sixes. The
   theoretical probability of a six is $\frac{1}{6}$. Is the cube
   loaded? What would you do next?
8. A 5-card hand is dealt from a standard deck. What is the
   probability that all five cards are hearts? Express it as
   "about 1 in $n$".
9. Three people are chosen at random. Assuming 365 equally likely
   birthdays and no twins, find the probability that at least two
   share a birthday. Why does the answer for 23 people feel so
   different?

> [!success]- Answer 7
> The expected number of sixes is $60 \times \frac{1}{6} = 10$, and
> the student got 14. That is 4 above expectation, and it is well
> within ordinary variation for 60 rolls — an experimental
> probability of $\frac{14}{60} \approx 0.233$ against a theoretical
> $0.167$. So: no verdict. One run of 60 cannot distinguish a loaded
> cube from a lucky one.
> What to do next is the real answer: roll it a great many more
> times. Experimental probability tends toward theoretical as trials
> increase, so 6000 rolls would settle it while 60 never can. That
> tendency is exactly what [[The Simulation]] was demonstrating, and
> it is why sample size is the first thing to ask about any claim.

> [!success]- Answer 8
> Every 5-card hand is equally likely, so count favourable hands over
> total hands. All five hearts means choosing 5 from the 13 hearts:
> $$P = \frac{\binom{13}{5}}{\binom{52}{5}} = \frac{1287}{2\,598\,960} \approx 0.000495$$
> Since $\frac{2\,598\,960}{1287} \approx 2019$, that is about
> **1 in 2000** hands. Multiply by 4 if you want any single suit
> rather than hearts specifically — about 1 in 505.

> [!success]- Answer 9
> Work with the complement: all three birthdays different. The first
> person may have any birthday, the second must avoid one day, the
> third must avoid two.
> $$P(\text{all different}) = \frac{365}{365} \times \frac{364}{365} \times \frac{363}{365} \approx 0.9918$$
> So $P(\text{at least two share}) \approx 1 - 0.9918 = 0.0082$,
> under one percent.
> The reason 23 people feels so different is that the number of
> *pairs* grows far faster than the number of people:
> 3 people make $\binom{3}{2} = 3$ pairs, while 23 people make
> $\binom{23}{2} = 253$. Your intuition tracks the people; the
> mathematics tracks the pairs. That mismatch is the entire trick of
> [[The Birthday Problem]].

%%curriculum-start%%
## Curriculum connection

![[A1.1]]

![[A1.2]]

![[A1.3]]

![[A1.4]]

![[A1.5]]

![[A1.6]]

![[A2.5]]
%%curriculum-end%%
