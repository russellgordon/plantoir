---
title: Counting Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These follow [[The Fundamental Counting Principle]] and
[[Pascal's Triangle]]. Every question here is answerable by
multiplying, adding, or subtracting — no factorial notation required
yet. Before you compute, say out loud whether the situation is stages
of one task (multiply) or alternatives to it (add). Getting that
sentence right is the whole skill.

## Multiplying and adding

1. A cafeteria offers 4 main dishes, 3 sides, and 5 drinks.
   (a) How many meals consist of one of each? (b) How many ways are
   there to buy a single item as a snack?
2. A licence plate has 4 letters followed by 3 digits, and any
   character may repeat. How many plates are possible?
3. A binary string of length 8 is a sequence of eight 0s and 1s.
   (a) How many are there? (b) How many begin with 1? (c) How many
   begin with 1 and end with 0?

> [!success]- Answer 1
> (a) Three stages of one meal, so multiply:
> $4 \times 3 \times 5 = 60$ meals.
> (b) One item, chosen from three separate menus that cannot both
> apply, so add: $4 + 3 + 5 = 12$ snacks. Same three numbers, two
> different questions, two very different answers — which is why the
> *and* / *or* reading has to come first.

> [!success]- Answer 2
> Seven stages, each independent: four letter slots with 26 choices
> each, then three digit slots with 10 each.
> $$26^4 \times 10^3 = 456\,976 \times 1000 = 456\,976\,000$$
> Roughly 457 million plates. Worth a sanity check: this is about
> twelve times the population of Canada, which is the sort of margin
> a plate system is designed to have.

> [!success]- Answer 3
> (a) Eight slots, two choices each: $2^8 = 256$.
> (b) The first slot is now fixed at 1 and the other seven are free:
> $1 \times 2^7 = 128$ — exactly half, as symmetry demands.
> (c) Two slots fixed, six free: $2^6 = 64$, half of (b) again.

## Restrictions and complements

4. Using the plate format from question 2, how many plates have no
   repeated letter and no repeated digit? What percentage of all
   plates is that?
5. A password is exactly 5 characters, each a lowercase letter or a
   digit (36 possibilities). (a) How many passwords are there?
   (b) How many contain at least one digit?
6. A local phone number has 7 digits and cannot begin with 0 or 1.
   (a) How many are possible? (b) How many end in an even digit?

> [!success]- Answer 4
> Handle the restricted stages in order, each slot having one fewer
> choice than the last.
> Letters: $26 \times 25 \times 24 \times 23 = 358\,800$.
> Digits: $10 \times 9 \times 8 = 720$.
> Together: $358\,800 \times 720 = 258\,336\,000$.
> As a fraction of all plates,
> $\frac{258\,336\,000}{456\,976\,000} \approx 0.565$, so about
> $56.5\%$. Forbidding repeats costs you more than four plates in
> ten, which is more than most people guess.

> [!success]- Answer 5
> (a) $36^5 = 60\,466\,176$.
> (b) "At least one digit" has five overlapping cases; its
> complement has exactly one. Passwords with **no** digit use only
> the 26 letters: $26^5 = 11\,881\,376$. Subtract:
> $$60\,466\,176 - 11\,881\,376 = 48\,584\,800$$
> That is about $80.4\%$ of all passwords — so the "must contain a
> digit" rule rules out only about a fifth of the possibilities, and
> is far weaker protection than it sounds.

> [!success]- Answer 6
> (a) The first digit has 8 choices (2 through 9) and the remaining
> six are free: $8 \times 10^6 = 8\,000\,000$.
> (b) Now the last digit is restricted to $\{0, 2, 4, 6, 8\}$, so 5
> choices, and only the middle five digits are free:
> $8 \times 10^5 \times 5 = 4\,000\,000$ — exactly half, which is
> the check that tells you the restriction was applied to the right
> slot.

## Grids and triangles

7. Your school is 5 blocks west and 3 blocks south of your home. At
   every corner you may go west or south. How many different routes
   are there? Verify your answer a second way.
8. A club has 6 members. (a) How many different subsets of members
   could form a group, counting the empty group and the whole club?
   (b) How many of those subsets have exactly 2 members? (c) How do
   your two answers relate to a row of Pascal's triangle?
9. Show that $\binom{10}{3} = \binom{9}{2} + \binom{9}{3}$ by
   computing all three, then explain what the identity says about
   choosing a committee.

> [!success]- Answer 7
> Every route is a sequence of 8 moves, of which exactly 3 are south
> (the other 5 are west). Choose which moves are the southward ones:
> $\binom{8}{3} = \frac{8 \times 7 \times 6}{3 \times 2 \times 1} =
> 56$ routes.
> Second way: write the number of routes to each corner on a grid.
> Every corner is the sum of the corner above it and the corner to
> its right, the edges are all 1s, and the school's corner comes out
> $56$ — you have written Pascal's triangle onto the streets.
> Choosing the 5 westward moves instead gives $\binom{8}{5} = 56$
> too, which is the symmetry check.

> [!success]- Answer 8
> (a) Each of the 6 members is either in or out, independently:
> $2^6 = 64$ subsets.
> (b) $\binom{6}{2} = 15$.
> (c) Row 6 of the triangle reads $1, 6, 15, 20, 15, 6, 1$ — the
> number of subsets of each size from 0 to 6 — and those entries sum
> to $64$. Part (b) is the third entry of that row, and part (a) is
> the row total. Two questions, one row.

> [!success]- Answer 9
> $\binom{10}{3} = \frac{10 \times 9 \times 8}{6} = 120$.
> $\binom{9}{2} = \frac{9 \times 8}{2} = 36$ and
> $\binom{9}{3} = \frac{9 \times 8 \times 7}{6} = 84$, and
> $36 + 84 = 120$. ✓
> What it says: single out one club member — call her Priya. Every
> 3-person committee from the 10 either includes Priya, in which case
> the other two come from the remaining 9 ($\binom{9}{2}$ ways), or
> excludes her, in which case all three come from the remaining 9
> ($\binom{9}{3}$ ways). The two cases cannot overlap and cover
> everything, so add them. That argument is the addition rule of
> Pascal's triangle, and it is a proof about people rather than
> algebra.

%%curriculum-start%%
## Curriculum connection

![[A2.1]]

![[A2.2]]

![[A2.3]]

![[A2.4]]
%%curriculum-end%%
