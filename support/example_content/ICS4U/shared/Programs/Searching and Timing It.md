---
title: Searching and Timing It
publish: true
created: __CREATED__
tags:
  - programs
---
In [[The Race]] two groups wrote a lookup for the community centre's
membership card numbers. Both worked. On the ten test cards they were
indistinguishable. On the real file — a hundred thousand numbers — one
answered before your finger left the key and the other took a
noticeable, awkward moment, every single time.

This program is that race, run properly: same data, same question,
both answers checked against each other first, and then measured two
ways — by counting comparisons, which is exact and the same on every
machine, and by the clock, which is not.

## The program

```python
# Two ways to look up a membership number, measured against each other.
# The numbers are made up, and they are only numbers: the community
# centre's card numbers are stored here without the names attached.

import random
import time

REPEATS = 100


def linear_search(values, target):
    """Return the index of target in values, or -1 if it is absent.

    Precondition: none. Any list at all will do.
    """
    for index in range(len(values)):
        if values[index] == target:
            return index
    return -1


def binary_search(values, target):
    """Return the index of target in values, or -1 if it is absent.

    Precondition: values is sorted in ascending order. On an unsorted
    list this function returns wrong answers instead of crashing.
    """
    low = 0
    high = len(values) - 1
    while low <= high:
        middle = (low + high) // 2
        if values[middle] == target:
            return middle
        elif values[middle] < target:
            low = middle + 1
        else:
            high = middle - 1
    return -1


def linear_comparisons(values, target):
    """Count the comparisons a linear search would make."""
    comparisons = 0
    for index in range(len(values)):
        comparisons = comparisons + 1
        if values[index] == target:
            return comparisons
    return comparisons


def binary_comparisons(values, target):
    """Count the comparisons a binary search would make."""
    comparisons = 0
    low = 0
    high = len(values) - 1
    while low <= high:
        middle = (low + high) // 2
        comparisons = comparisons + 1
        if values[middle] == target:
            return comparisons
        elif values[middle] < target:
            low = middle + 1
        else:
            high = middle - 1
    return comparisons


def time_search(search, values, target):
    """Return the average seconds per search over REPEATS runs."""
    start = time.perf_counter()
    for run in range(REPEATS):
        search(values, target)
    finished = time.perf_counter()
    return (finished - start) / REPEATS


def make_card_numbers(count):
    """Return a sorted list of count card numbers, starting at 100000."""
    numbers = []
    for offset in range(count):
        numbers.append(100000 + offset * 2)
    return numbers


# Both searches must agree before either is worth timing.
cards = make_card_numbers(1000)
random_checks = 0
for check in range(1000):
    wanted = random.choice(cards)
    if linear_search(cards, wanted) == binary_search(cards, wanted):
        random_checks = random_checks + 1
print(f"Agreed on {random_checks} of 1000 random lookups.")
print(f"Missing card: linear {linear_search(cards, 7)}, "
      f"binary {binary_search(cards, 7)}")
print()

print("Comparisons for a card that is not there (the worst case):")
print(f"{'cards':>10}  {'linear':>10}  {'binary':>10}")
for size in [1000, 10000, 100000]:
    cards = make_card_numbers(size)
    print(f"{size:>10}  {linear_comparisons(cards, 7):>10}  "
          f"{binary_comparisons(cards, 7):>10}")
print()

print(f"Seconds per search, averaged over {REPEATS} runs:")
print(f"{'cards':>10}  {'linear':>12}  {'binary':>12}")
for size in [1000, 10000, 100000]:
    cards = make_card_numbers(size)
    linear_time = time_search(linear_search, cards, 7)
    binary_time = time_search(binary_search, cards, 7)
    print(f"{size:>10}  {linear_time:>12.8f}  {binary_time:>12.8f}")
```

```text wrap
Agreed on 1000 of 1000 random lookups.
Missing card: linear -1, binary -1

Comparisons for a card that is not there (the worst case):
     cards      linear      binary
      1000        1000           9
     10000       10000          13
    100000      100000          16

Seconds per search, averaged over 100 runs:
     cards        linear        binary
      1000    0.00000979    0.00000037
     10000    0.00010155    0.00000050
    100000    0.00100818    0.00000062
```

## How it works

**Correctness first.** The program does not time anything until the
two searches have agreed on a thousand random lookups and on one card
that is not there. A fast wrong answer is not a result, and the first
thing a reviewer will ask you is how you know the new version still
works — see [[Read the Diff]] for that conversation happening in
public.

**Linear search** starts at the front and keeps going. To prove a card
is absent it must look at every single one, so the worst case is
exactly as many comparisons as there are cards: 1 000 cards, 1 000
comparisons; 100 000 cards, 100 000 comparisons. The table says so
precisely because the count is arithmetic, not measurement.

**Binary search** throws away half the remaining cards with every
comparison. `middle = (low + high) // 2` uses integer division so the
midpoint is always a whole index, and then exactly one of three things
happens: found, too small (search the right half), too big (search the
left half). Ten times as many cards costs only three or four more
comparisons, because the question is not "how many cards" but "how
many times can you halve them" — $\log_2 100000 \approx 16.6$, and the
measured count is 16.

**The clock agrees, roughly.** Linear search's time multiplies by
about ten when the list does. Binary search's barely moves. That
*shape* is the result. The digits are not:

> [!warning] What these timings are and are not
> These numbers came off one laptop, on one afternoon, with other
> programs running. Yours will differ, possibly by a factor of five,
> and a single run of a fast function measures the machine's mood as
> much as the code. What survives the change of machine is the
> **relative** behaviour: linear grows in proportion to the list,
> binary hardly grows at all. Quote ratios, never milliseconds, when
> you defend an algorithm choice — the technique is in
> [[Profiling and Timing Code]].

`time.perf_counter()` is the right clock for this: it is designed for
measuring intervals and has the finest resolution Python can offer.
The average over `REPEATS` runs exists because one binary search takes
under a millionth of a second — far too little for any clock to
measure honestly on its own.

**The precondition is the whole story.** `binary_search` works only on
a sorted list, and its docstring says so, because a broken
precondition here does not raise an exception. It returns `-1` for
cards that are sitting in the list, and tells a real member they are
not registered.

## Change it

1. **One line.** Change `REPEATS` to `1000`. The times settle down —
   the fourth decimal place stops jumping between runs — and the
   program takes ten times as long to finish. That trade is what
   timing work is: precision costs patience.
2. **A few lines.** Add `1000000` to both size lists. Linear search
   makes a million comparisons and takes about ten times its
   hundred-thousand time; binary search makes **19**. The gap between
   the two columns is now a factor of tens of thousands, and it is
   still growing.
3. **A real change.** Break the precondition on purpose. Shuffle the
   card list with `random.shuffle(cards)` and then ask
   `binary_search` for every card that is definitely in it. When we
   ran that on a shuffled list of 1 000 cards, binary search failed to
   find **991 of them** — the exact count depends on the shuffle, but
   it is always most of them. Linear search misses none. No exception,
   no warning, no crash: the fast algorithm just lies. Write the test
   that would have caught this before your team shipped it —
   [[Testing and Regression]] shows how.

The ideas are in [[Searching]] and [[Efficiency and Big-O]]; the drill
is in [[Searching Practice]] and [[Efficiency Practice]].

%%curriculum-start%%
## Curriculum connection

![[A1.1]]

![[A3.2]]

![[C2.2]]
%%curriculum-end%%
