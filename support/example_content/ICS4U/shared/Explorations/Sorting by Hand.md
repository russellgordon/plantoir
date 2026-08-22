---
title: Sorting by Hand
publish: true
created: __CREATED__
tags:
  - explorations
enableToc: true
---
Every group gets twelve cards, face down, each with a number on it. You
are going to put them in order. So is everybody else. Nobody is going
to touch a keyboard for the first half of this class.

The cards come from a deck the room makes first:

```python
import random

values = []
for number in range(1, 100):
    values.append(number)

random.shuffle(values)

for position in range(12):
    print(values[position])
```

Print one set per group, write the numbers on index cards, shuffle, and
put them face down in a row on the desk.

## The rules

These are not suggestions. The whole measurement depends on them.

```text
1. Only two cards may be face up at any moment.
2. To compare two cards, turn them both up, then turn them both
   back down. That counts as ONE comparison.
3. You may swap two cards, or move a card to a new position, at any
   time. Movement is free; looking is not.
4. One person in the group is the Counter. The Counter touches no
   cards and keeps a running tally of comparisons on paper.
5. The group must agree on a rule BEFORE it starts, say it out loud,
   and follow it exactly — even when a shortcut is obvious.
```

Rule five is the one groups break. It is also the one that makes this
an algorithm rather than a knack.

## The task

**Round one — invent a method.** Agree a rule, say it out loud, sort
the twelve cards, and record the comparison count. Then write your rule
down in numbered steps precise enough that another group could follow
it without asking you anything.

**Round two — swap rules.** Trade written rules with another group,
reshuffle to a *new* twelve, and sort using their rule, not yours.
Record the count. Then tell them, honestly, the first place their
instructions were ambiguous.

**Round three — the same deck, every rule.** The whole room now sorts
one identical set of twelve, each group using its own rule. Put every
count on the board in one column.

**Round four — the cruel deck.** Everyone sorts a deck that is already
in order, then a deck that is exactly backwards. Add both columns to
the board. Some rules barely notice. Some rules fall apart.

## The count

1. Which rule won on the shuffled deck? Which won on the sorted deck?
   Are they the same rule?
2. Did any group's count change when a *different* group ran their
   written rule? What does that tell you about the writing, not the
   sorting?
3. Roughly how many comparisons would your rule need for 24 cards?
   Guess first, then test it if there is time. Most guesses are far too
   low.
4. Is there a rule that never needs more than about a dozen comparisons
   on twelve cards? Under what conditions?

> [!note]- Facilitation notes
> **Physical cards, genuinely.** Index cards, not slips of paper, not a
> screen. The two-cards-face-up rule is what converts "sorting" from
> something the eye does instantly into a sequence of decisions that
> can be counted. On a screen the whole point evaporates.
>
> **Timing in a 70-minute period.** Ten minutes to build decks and read
> the rules. Fifteen on round one. Ten on round two. Ten on round three
> with the board column. Ten on round four. Fifteen on the count and on
> naming what they built.
>
> **The Counter is not a spare student.** Rotate the role between
> rounds and make it visible; the tally is the data for the whole day.
> If a group has four people, the fourth reads their own written rule
> aloud, step by step, while the others obey it literally.
>
> **What the room will invent.** Almost every class produces, without
> being told: repeatedly find the smallest remaining card and place it
> (selection sort); take cards one at a time and slide each into an
> already-sorted left-hand section (insertion sort); and repeatedly
> compare neighbours and swap (bubble sort). Occasionally a group
> splits the row in half, sorts each half, and interleaves — write that
> group's names on the board, because they have invented merge sort and
> they will be very smug about it in Unit 3, Day 6.
>
> **Do not correct a working rule for being inefficient.** Let the
> board's numbers say it. A rule that took 70 comparisons next to one
> that took 34 is an argument nobody has to win with authority.
>
> **The cruel deck is the pay-off.** Insertion-style rules take almost
> no comparisons on an already-sorted deck and the room gasps.
> Selection-style rules take exactly the same number as always. That
> contrast is the entire reason "which sort is best?" has no answer,
> and you get it for free from cardboard.
>
> **Save the board.** Photograph the three columns. They come back on
> Unit 3, Day 7 next to the machine timings, and again on Unit 3,
> Day 8 when the counts get a name.

## What tends to surface

Groups discover that their rule was not one rule. It was a rule plus
three unwritten habits their hands were performing — starting from the
left, remembering roughly where the big ones were, noticing a pair that
happened to be adjacent. Round two exposes all of it, because another
group's hands do not have your habits. Writing an algorithm is mostly
the work of finding the steps you did not know you were taking.

The second surface is that "best" is a question with a missing half.
Best for what deck? A rule that is superb on nearly-sorted data and
mediocre on shuffled data is not worse than one that is uniform; it is
*different*, and choosing between them requires knowing something about
the data you will actually be given.

The third is that counting comparisons was a better measure than
timing yourselves with a phone. The count is a property of the method.
The stopwatch measures how fast your group's hands are.

## Where this goes next

The rules the room invented already have names, and they get them in
[[Sorting]] — usually to some indignation that the room was not first
by about sixty years. You will implement one and prove it works with
[[Writing Tests]], then race them on real data in
[[Sorting and Timing It]] and drill the mechanics in [[Sorting Practice]].

The comparison counts on your board join the timings from [[The Race]]
and finally get a shared vocabulary in [[Efficiency and Big-O]]. The
question of what a ranking does to the people being ranked is
[[When Code Hurts]].

> [!note] The answer is not on this page
> No sorting algorithm is written out here, in cards or in code, and
> the names are deliberately withheld. Your room's numbered rules, in
> your room's handwriting, are the first draft of every algorithm in
> the next three classes. Keep them. Comparing your version to the
> textbook's is far more interesting than being handed the textbook's.

%%curriculum-start%%
## Curriculum connection

![[A3.4]]

![[C2.3]]
%%curriculum-end%%
