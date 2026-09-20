---
title: Permutations and Combinations Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These follow [[Permutations]], [[Combinations]], and
[[Pascal's Triangle]]. Write down, for every question, whether order
carries meaning **before** you choose a formula — most errors in this
set are not arithmetic. If a question resists you, shrink it to three
or four objects and list them by hand; the small case always tells you
which tool applies.

## Arrangements

1. Evaluate (a) $P(9,3)$ and (b) $\binom{9}{3}$. (c) One answer is
   six times the other. Explain why, without using the formulas.
2. Eight different books are placed on a shelf. (a) How many
   arrangements are there? (b) How many have three particular books
   sitting together, in any order, as a block?
3. How many distinct arrangements are there of the letters of the
   word STATISTICS?

> [!success]- Answer 1
> (a) $P(9,3) = 9 \times 8 \times 7 = 504$.
> (b) $\binom{9}{3} = \frac{9 \times 8 \times 7}{3 \times 2 \times 1}
> = \frac{504}{6} = 84$.
> (c) Both questions choose the same three people from nine. The
> permutation then hands those three distinct roles, and there are
> $3! = 6$ ways to hand out three roles to three people. So every
> single selection is counted six times in $504$ and once in $84$.
> The relationship $P(9,3) = \binom{9}{3} \times 3!$ is just that
> sentence written down.

> [!success]- Answer 2
> (a) Eight distinct objects in eight slots:
> $8! = 40\,320$ arrangements.
> (b) Glue the three books into one block. You now have six things
> to arrange — five loose books and the block — giving $6! = 720$
> arrangements. The block's own three books can be ordered $3! = 6$
> ways inside it. Multiply:
> $$6! \times 3! = 720 \times 6 = 4\,320$$
> That is about $10.7\%$ of all arrangements, which is a reasonable
> figure for a fairly demanding restriction.

> [!success]- Answer 3
> Ten letters, but not ten *distinguishable* letters: there are three
> S's, three T's, and two I's, plus one A and one C. Count as though
> all ten were distinct, then divide out the arrangements you cannot
> tell apart:
> $$\frac{10!}{3!\,3!\,2!} = \frac{3\,628\,800}{6 \times 6 \times 2} = \frac{3\,628\,800}{72} = 50\,400$$
> Check the letter count before you divide — $3 + 3 + 2 + 1 + 1 = 10$
> — because a miscounted repeat is the usual failure here.

## Selections

4. A club has 10 members. (a) In how many ways can it choose a
   president, vice-president, secretary, and treasurer? (b) In how
   many ways can it choose a four-person steering committee whose
   members are all equal? (c) Explain the relationship between your
   two answers.
5. Seven people gather and each shakes hands with every other person
   exactly once. How many handshakes occur? Verify with a second
   method.
6. A committee of 5 is chosen from 6 girls and 7 boys. How many
   committees have (a) exactly 2 girls, (b) at least 1 girl?

> [!success]- Answer 4
> (a) Four distinct offices, so order matters:
> $P(10,4) = 10 \times 9 \times 8 \times 7 = 5040$.
> (b) Equal standing, so order does not matter:
> $\binom{10}{4} = \frac{5040}{24} = 210$.
> (c) $5040 = 210 \times 24 = \binom{10}{4} \times 4!$. Choosing the
> executive is a two-stage task: pick the four people (210 ways),
> then assign the four titles among them ($4! = 24$ ways). An
> arrangement is a selection followed by an ordering, and that is the
> single most useful sentence in this unit.

> [!success]- Answer 5
> A handshake is a selection of 2 people from 7, with order
> irrelevant — shaking hands is symmetric.
> $\binom{7}{2} = \frac{7 \times 6}{2} = 21$.
> Second method: the first person shakes 6 hands, the second shakes
> 5 *new* ones, then 4, 3, 2, 1, and the last person has already
> shaken everyone's. $6+5+4+3+2+1 = 21$. ✓ Two independent routes to
> the same number is how you know a counting argument is sound.

> [!success]- Answer 6
> (a) Two stages, so multiply: choose 2 of the 6 girls, then 3 of
> the 7 boys.
> $$\binom{6}{2} \times \binom{7}{3} = 15 \times 35 = 525$$
> (b) "At least 1" is the complement of "none". All committees:
> $\binom{13}{5} = 1287$. All-boy committees: $\binom{7}{5} = 21$.
> So $1287 - 21 = 1266$ committees contain at least one girl —
> about $98.4\%$, which makes sense when girls are nearly half the
> pool and the committee is five strong.

## Both at once

7. From a standard deck of 52 cards, a hand of 5 is dealt. How many
   hands (a) are there altogether, (b) consist entirely of hearts,
   (c) contain exactly 2 aces?
8. A lottery draws 6 numbers from 49, order irrelevant. How many
   possible draws are there, and what is the probability that one
   ticket matches all six?
9. The number of handshakes among $n$ people is $\binom{n}{2}$.
   Compute it for $n = 4, 5, 6, 7$ and find those four numbers inside
   Pascal's triangle. What is the pattern called?

> [!success]- Answer 7
> (a) $\binom{52}{5} = 2\,598\,960$.
> (b) All five from the 13 hearts: $\binom{13}{5} = 1287$.
> (c) Two stages: choose 2 of the 4 aces, then 3 of the 48 non-aces.
> $$\binom{4}{2} \times \binom{48}{3} = 6 \times 17\,296 = 103\,776$$
> As a probability that is
> $\frac{103\,776}{2\,598\,960} \approx 0.0399$, so roughly 4% of
> hands — about one deal in 25.

> [!success]- Answer 8
> Order does not matter and numbers are not repeated, so it is a
> straight combination:
> $$\binom{49}{6} = 13\,983\,816$$
> One ticket is one of those equally likely draws, so the
> probability is $\frac{1}{13\,983\,816} \approx 7.15 \times
> 10^{-8}$. Put in units you can feel: buying one ticket a week, you
> would expect to wait roughly 269 000 years. The counting is easy;
> the interpretation is the part worth carrying around.

> [!success]- Answer 9
> $\binom{4}{2} = 6$, $\binom{5}{2} = 10$, $\binom{6}{2} = 15$,
> $\binom{7}{2} = 21$.
> Those appear in successive rows of Pascal's triangle, always the
> third entry along, forming the diagonal $1, 3, 6, 10, 15, 21,
> \ldots$ — the **triangular numbers**. Both sequences count pairs:
> the triangular numbers count dots stacked in a triangle, and
> $\binom{n}{2}$ counts handshakes. Same arithmetic, two stories,
> which is exactly what [[Pascal's Triangle]] claims about every
> diagonal it has.

%%curriculum-start%%
## Curriculum connection

![[A2.1]]

![[A2.2]]

![[A2.3]]

![[A2.4]]

![[A2.5]]
%%curriculum-end%%
