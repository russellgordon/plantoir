---
title: Sorting and Timing It
publish: true
created: __CREATED__
tags:
  - programs
---
In [[Sorting by Hand]] the room sorted a stack of lap-time cards
without a computer, and every group invented roughly the same method:
pick up the next card, slide it back until it is in the right place,
drop it in. That is insertion sort. Nobody was taught it; it is what
hands do.

This program writes it down. It also does the thing that makes Grade
12 different from Grade 11: it measures the method, on data big enough
to hurt, and puts it beside the sort Python already ships — because
the point of writing a sort by hand is to understand one, not to use
one.

## The program

```python
# Sorting the coach's list of lap times, by hand and then by machine.
# The hand-written sort is here to be understood, not to be used: the
# last section shows what the built-in sort does with the same data.

import random
import time


def insertion_sort(values):
    """Sort a list in place, smallest first, and return the list.

    Precondition: every pair of items in values can be compared with <.
    Postcondition: values holds the same items in ascending order.
    """
    for position in range(1, len(values)):
        held = values[position]
        gap = position - 1
        while gap >= 0 and values[gap] > held:
            values[gap + 1] = values[gap]
            gap = gap - 1
        values[gap + 1] = held
    return values


def insertion_comparisons(values):
    """Sort a copy and return how many comparisons it took."""
    working = list(values)
    comparisons = 0
    for position in range(1, len(working)):
        held = working[position]
        gap = position - 1
        while gap >= 0:
            comparisons = comparisons + 1
            if working[gap] <= held:
                break
            working[gap + 1] = working[gap]
            gap = gap - 1
        working[gap + 1] = held
    return comparisons


def time_sort(sort, values):
    """Return the seconds one sort takes on a fresh copy of values."""
    working = list(values)
    start = time.perf_counter()
    sort(working)
    finished = time.perf_counter()
    return finished - start


def builtin_sort(values):
    """Sort using Python's own sort, so the two can be timed the same way."""
    values.sort()
    return values


lap_times = [64.2, 58.9, 71.0, 60.4, 58.9, 66.7, 55.3, 69.1]
print(f"Lap times as recorded: {lap_times}")
print(f"Sorted:                {insertion_sort(list(lap_times))}")

swimmers = ["Rowan", "bea", "Ali", "Nadia", "Sam"]
print(f"Names as recorded:     {swimmers}")
print(f"Sorted:                {insertion_sort(list(swimmers))}")
print()

random.seed(4)
print("Comparisons made by insertion sort:")
print(f"{'items':>8}  {'already sorted':>16}  {'shuffled':>10}  {'reversed':>10}")
for size in [500, 1000, 2000, 4000]:
    ordered = list(range(size))
    shuffled = list(range(size))
    random.shuffle(shuffled)
    backwards = list(range(size - 1, -1, -1))
    print(f"{size:>8}  {insertion_comparisons(ordered):>16}  "
          f"{insertion_comparisons(shuffled):>10}  "
          f"{insertion_comparisons(backwards):>10}")
print()

print("Seconds to sort one shuffled list:")
print(f"{'items':>8}  {'insertion sort':>16}  {'built-in sort':>15}")
for size in [500, 1000, 2000, 4000]:
    shuffled = list(range(size))
    random.shuffle(shuffled)
    ours = time_sort(insertion_sort, shuffled)
    theirs = time_sort(builtin_sort, shuffled)
    print(f"{size:>8}  {ours:>16.6f}  {theirs:>15.6f}")
```

```text nowrap
Lap times as recorded: [64.2, 58.9, 71.0, 60.4, 58.9, 66.7, 55.3, 69.1]
Sorted:                [55.3, 58.9, 58.9, 60.4, 64.2, 66.7, 69.1, 71.0]
Names as recorded:     ['Rowan', 'bea', 'Ali', 'Nadia', 'Sam']
Sorted:                ['Ali', 'Nadia', 'Rowan', 'Sam', 'bea']

Comparisons made by insertion sort:
   items    already sorted    shuffled    reversed
     500               499       65999      124750
    1000               999      250784      499500
    2000              1999      990399     1999000
    4000              3999     4043007     7998000

Seconds to sort one shuffled list:
   items    insertion sort    built-in sort
     500          0.001304         0.000026
    1000          0.005469         0.000051
    2000          0.022081         0.000112
    4000          0.087833         0.000251
```

## How it works

`insertion_sort` keeps the front of the list sorted and grows that
sorted region by one item per pass. `held` is the card in your hand.
The `while` loop slides bigger items one place to the right, opening a
gap, and `values[gap + 1] = held` drops the card into it.

> [!example]- One pass at a time, on the first five lap times
> ```text nowrap
> start    [64.2, 58.9, 71.0, 60.4, 58.9]
> pass 1: hold  58.9 -> [58.9, 64.2, 71.0, 60.4, 58.9]
> pass 2: hold  71.0 -> [58.9, 64.2, 71.0, 60.4, 58.9]
> pass 3: hold  60.4 -> [58.9, 60.4, 64.2, 71.0, 58.9]
> pass 4: hold  58.9 -> [58.9, 58.9, 60.4, 64.2, 71.0]
> ```
> Pass 2 changes nothing: 71.0 is already bigger than everything to
> its left, the `while` condition fails immediately, and the item is
> written back where it started. Pass 4 does the most work, sliding
> three items to make room for a time that ties one already placed.

**Sorting names is sorting.** `insertion_sort(swimmers)` needed no
changes at all, because `>` compares strings as happily as floats. It
also exposes something worth knowing: `'bea'` sorts *after* `'Sam'`.
Python compares text by character codes, and every capital letter
comes before every lowercase one. That is not a bug in the sort — it
is what "less than" means for strings, and if the coach wants
human alphabetical order, the fix belongs in the data or in a
`.lower()` comparison, not in the algorithm.

**Read the comparison table, not the clock.** The counts are exact and
identical on every machine:

- **Already sorted:** 499, 999, 1999, 3999 — one comparison per item,
  and no sliding at all. This is insertion sort's best case, and it is
  genuinely good.
- **Reversed:** 124 750, 499 500, 1 999 000, 7 998 000 — double the
  items and the work goes up **four** times. That is the signature of
  $O(n^2)$: every item is compared with every item before it.
- **Shuffled:** about half the reversed figure, growing the same way.

Now compare that with the times. From 500 items to 4 000 — eight times
as many — insertion sort went from 0.0013 s to 0.0878 s, about
**sixty-seven times** longer, while the built-in sort went from
0.000026 s to 0.000251 s, about ten times longer. The counted
comparisons predicted this before the stopwatch confirmed it.

> [!warning] Whose seconds are these?
> One laptop, one afternoon. Your absolute numbers will be different
> and that is fine — what must reproduce is the *shape*: doubling the
> list roughly quadruples insertion sort's time, and barely more than
> doubles the built-in's. Report ratios; treat any single measurement
> as noise. [[Profiling and Timing Code]] is the honest method.

**Use the built-in one.** Python's `sort` is a carefully engineered
merge-sort variant, $O(n \log n)$, written and tested by many people
over many years. In real work you call it. You wrote insertion sort so
that when a program is slow you can recognise the shape of the
problem, and so that the phrase "n squared" means something you have
watched happen.

## Change it

1. **One line.** Add `8000` to the size lists. Insertion sort's
   reversed count becomes `31 996 000` and one shuffled sort takes
   about 0.36 s — four times the 4 000 figure, exactly as the pattern
   predicts. The built-in sort is still under a millisecond.
2. **A few lines.** Write `selection_sort`, which repeatedly finds the
   smallest remaining item and swaps it into place, and count its
   comparisons the same way. You will find it makes **the same number
   every time** — 124 750 at 500 items, 7 998 000 at 4 000 —
   regardless of whether the data is sorted, shuffled, or reversed.
   Insertion sort adapts to nearly-sorted data; selection sort cannot.
   Both are $O(n^2)$, and that is the difference the notation hides.
3. **A real change.** Sort a list of objects. Take the `Volunteer`
   class from [[Objects in a List]] and sort a roster by hours by
   changing one comparison to `volunteers[gap].hours > held.hours`.
   The roster comes out `Rowan (1.5 h)`, `Bea (2 h)`, `Nadia (4.5 h)`,
   `Ali (6 h)`. Then ask the harder question: what would you have to
   change to sort by name instead, and how would you write it so that
   the coach can choose?

The ideas live in [[Sorting]] and [[Efficiency and Big-O]]; the drill
is in [[Sorting Practice]]. The room's version of this program is
[[Sorting by Hand]].

%%curriculum-start%%
## Curriculum connection

![[A1.3]]

![[A3.4]]

![[C2.3]]
%%curriculum-end%%
