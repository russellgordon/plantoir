---
title: Conditional Probability Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These follow [[Conditional Probability]]. For every question, write
down what the *new* sample space is once the condition is imposed —
that single line converts most of these from hard to routine. Draw the
tree or build the table; both are faster than staring at the formula.

## Conditioning on information

1. Two number cubes are rolled. (a) Given that the sum is even, find
   $P(\text{sum} = 8)$. (b) Given that at least one cube shows a 4,
   find $P(\text{sum} = 7)$.
2. Two cards are drawn from a deck without replacement. Find
   (a) $P(\text{second is an ace} \mid \text{first was an ace})$,
   (b) $P(\text{both aces})$, and (c) $P(\text{at least one ace})$.
3. A committee of 3 is chosen at random from 5 women and 4 men. Given
   that the committee contains at least one man, find the probability
   that it contains exactly one man.

> [!success]- Answer 1
> (a) Of the 36 ordered pairs, 18 have an even sum — that is the new
> sample space. Five of them sum to 8: (2,6), (3,5), (4,4), (5,3),
> (6,2). So $P = \frac{5}{18} \approx 0.278$, up from the
> unconditional $\frac{5}{36} \approx 0.139$, exactly doubled
> because the condition kept half the outcomes and all of the
> favourable ones.
> (b) Pairs containing at least one 4: six with a 4 first, six with a
> 4 second, minus (4,4) counted twice — 11 outcomes. Of those, (3,4)
> and (4,3) sum to 7. So $P = \frac{2}{11} \approx 0.182$, slightly
> above the unconditional $\frac{1}{6}$.

> [!success]- Answer 2
> (a) One ace is gone and 51 cards remain, three of them aces:
> $\frac{3}{51} = \frac{1}{17} \approx 0.0588$.
> (b) Multiplication rule:
> $\frac{4}{52} \times \frac{3}{51} = \frac{12}{2652} =
> \frac{1}{221} \approx 0.00452$.
> (c) Complement, counted with combinations. Hands of two with no
> ace: $\binom{48}{2} = 1128$ out of $\binom{52}{2} = 1326$.
> $$P(\text{at least one ace}) = 1 - \frac{1128}{1326} = \frac{198}{1326} = \frac{33}{221} \approx 0.149$$
> About one draw in seven, which is far more often than part (b) and
> a good reminder that "at least one" and "both" are wildly
> different questions.

> [!success]- Answer 3
> All committees: $\binom{9}{3} = 84$. All-women committees:
> $\binom{5}{3} = 10$. So committees with at least one man number
> $84 - 10 = 74$ — and that is the conditioned sample space.
> Committees with exactly one man: choose 1 of 4 men and 2 of 5
> women, $\binom{4}{1}\binom{5}{2} = 4 \times 10 = 40$.
> $$P = \frac{40}{74} = \frac{20}{37} \approx 0.541$$
> Note that the denominator is 74, not 84. Forgetting to shrink the
> sample space is the single most common error in this set, and it
> always makes the answer too small.

## Trees, and reversing the condition

4. Bag A contains 3 red and 2 blue marbles; bag B contains 1 red and
   4 blue. A bag is chosen at random and one marble is drawn.
   (a) Find $P(\text{red})$. (b) Given that the marble is red, find
   the probability it came from bag A.
5. A factory runs two machines. Machine 1 produces 60% of the items
   and 2% of its output is defective; machine 2 produces the other
   40% with 5% defective. (a) What proportion of all items are
   defective? (b) An item is found defective — what is the
   probability it came from machine 2?
6. A screening test detects 99% of people who have a condition and
   falsely flags 5% of people who do not. (a) If 1% of the
   population has the condition, find the probability that someone
   who tests positive actually has it. (b) Repeat for a population
   in which 10% have it. (c) What does the comparison tell you?

> [!success]- Answer 4
> (a) Two paths lead to red. Bag A then red:
> $\frac{1}{2} \times \frac{3}{5} = \frac{3}{10}$. Bag B then red:
> $\frac{1}{2} \times \frac{1}{5} = \frac{1}{10}$. Add:
> $P(\text{red}) = \frac{4}{10} = \frac{2}{5}$.
> (b) Now condition on red, so the new sample space is that
> $\frac{2}{5}$, and ask what fraction of it came through bag A:
> $$P(\text{A} \mid \text{red}) = \frac{3/10}{4/10} = \frac{3}{4}$$
> Three quarters, up from the $\frac{1}{2}$ you started with. Seeing
> a red marble is evidence about which bag you picked, and this is
> the reversal — $P(\text{red} \mid \text{A})$ was $\frac{3}{5}$,
> while $P(\text{A} \mid \text{red})$ is $\frac{3}{4}$. Two
> different numbers, and confusing them is the mistake question 6
> is built on.

> [!success]- Answer 5
> (a) Two paths to a defective item:
> $0.60 \times 0.02 = 0.012$ and $0.40 \times 0.05 = 0.020$.
> $P(\text{defective}) = 0.012 + 0.020 = 0.032$, or $3.2\%$.
> (b) $P(\text{machine 2} \mid \text{defective}) =
> \frac{0.020}{0.032} = 0.625$.
> Machine 2 makes only 40% of the items but 62.5% of the defects —
> which is precisely the kind of statement a quality manager needs
> and the raw defect rates do not directly give.

> [!success]- Answer 6
> (a) Take 10 000 people. $100$ have it, and $99$ of those test
> positive. Of the $9900$ who do not, $5\%$ — that is $495$ — test
> positive anyway. Total positives: $99 + 495 = 594$.
> $$P(\text{has it} \mid \text{positive}) = \frac{99}{594} = \frac{1}{6} \approx 16.7\%$$
> (b) Now $1000$ have it and $990$ test positive; of the $9000$ who
> do not, $450$ test positive. Total $1440$, so
> $\frac{990}{1440} = 0.6875$, about $68.8\%$.
> (c) The test did not change. Only the **base rate** did, and the
> answer moved from one-in-six to better-than-two-in-three. When a
> condition is rare, healthy people vastly outnumber sick ones, so
> even a small false-positive rate produces a flood of false alarms.
> This is why screening tests are applied to high-risk groups rather
> than to everyone, and why "the test is 99% accurate" is not an
> answer to "do I have it?".

## Independence, tested

7. Of 200 students surveyed, 30 walk to school and have a part-time
   job, 50 walk and have no job, 45 do not walk and have a job, and
   75 do neither. (a) Build the contingency table with totals.
   (b) Find $P(\text{job})$ and $P(\text{job} \mid \text{walks})$.
   (c) Are the two attributes independent? (d) Find
   $P(\text{walks} \mid \text{job})$.
8. For events with $P(A) = 0.4$, $P(B) = 0.5$, and
   $P(A \text{ and } B) = 0.2$, decide whether $A$ and $B$ are
   independent. Repeat for $P(A) = 0.6$, $P(B) = 0.3$,
   $P(A \text{ and } B) = 0.25$, and find $P(A \mid B)$ in that case.
9. Events $C$ and $D$ are mutually exclusive, with $P(C) = 0.3$ and
   $P(D) = 0.4$. Are they independent? Justify with a calculation,
   then say what the result means in plain language.

> [!success]- Answer 7
> (a) The table, with margins:
>
> | Of 200 students | Job | No job | Total |
> | --- | --- | --- | --- |
> | Walks | 30 | 50 | 80 |
> | Does not walk | 45 | 75 | 120 |
> | Total | 75 | 125 | 200 |
>
> (b) $P(\text{job}) = \frac{75}{200} = 0.375$ and
> $P(\text{job} \mid \text{walks}) = \frac{30}{80} = 0.375$.
> (c) They are equal, so in this sample the attributes are
> **independent** — knowing that a student walks tells you nothing
> about whether they have a job. Equivalently,
> $P(\text{walks}) \times P(\text{job}) = 0.4 \times 0.375 = 0.15$,
> and $\frac{30}{200} = 0.15$. ✓
> (d) $P(\text{walks} \mid \text{job}) = \frac{30}{75} = \frac{2}{5}
> = 0.4$, which equals $P(\text{walks})$ — independence read from
> the other side, as it must be.

> [!success]- Answer 8
> First pair: $P(A) \times P(B) = 0.4 \times 0.5 = 0.2$, which
> matches $P(A \text{ and } B) = 0.2$. **Independent.**
> Second pair: $P(A) \times P(B) = 0.6 \times 0.3 = 0.18$, but
> $P(A \text{ and } B) = 0.25$. Not equal, so **dependent** — and
> since the joint probability is larger than the product, the two
> events tend to occur together.
> $$P(A \mid B) = \frac{0.25}{0.30} = \frac{5}{6} \approx 0.833$$
> Compare that with $P(A) = 0.6$: knowing $B$ happened pushes the
> chance of $A$ up substantially, which is what dependence means in
> practice.

> [!success]- Answer 9
> Mutually exclusive means they cannot both happen, so
> $P(C \text{ and } D) = 0$. Independence would require
> $P(C) \times P(D) = 0.3 \times 0.4 = 0.12$. Since
> $0 \neq 0.12$, they are **not independent** — they are strongly
> dependent.
> In plain language: learning that $C$ occurred tells you an enormous
> amount about $D$, namely that it definitely did not. Mutually
> exclusive events are about as far from independent as two events
> can get, and the fact that both phrases sound like "unrelated" is
> the reason this question exists.

%%curriculum-start%%
## Curriculum connection

![[A1.5]]

![[A1.6]]

![[A2.5]]
%%curriculum-end%%
