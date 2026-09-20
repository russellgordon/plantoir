---
title: Efficiency Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Efficiency and Big-O]]. Counting is exact and
portable; timing is neither. Every question below asks you to count
first and measure second — and to say what your measurement is
actually evidence of.

## Counting and classifying

1. Give the Big-O of each, in terms of the length of `values`, and say
   what you counted:
   ```python
   def first_item(values):
       return values[0]

   def total(values):
       running = 0
       for value in values:
           running = running + value
       return running

   def every_pair(values):
       pairs = []
       for first in values:
           for second in values:
               pairs.append((first, second))
       return pairs
   ```
2. `count_steps(n)` runs a loop inside a loop, each `range(n)`. It
   returns 100 for `n = 10` and 400 for `n = 20`. Predict `n = 40`
   without running it, then say what rule you used.
3. Simplify each to Big-O and say which term you kept and why:
   $3n + 12$, $\frac{1}{2}n^2 - \frac{1}{2}n$, $n + n\log n$,
   $2^n + n^{100}$.
4. Write `halvings(n)`, which counts how many times `n` can be halved
   with `//` before it reaches 1. Report it for 8, 1 000, and
   1 000 000, and name the Big-O it is measuring.

## Measuring

5. Write `comparisons_to_find(values, target)`, counting the
   comparisons a linear search makes. Report the count for the first
   item, the last item, and an absent item in a list of 1 000, and
   label each as best, worst, or average case.
6. **Predict, then measure.** Which of these finds duplicates faster,
   and by how much at 4 000 items? Time both at 1 000, 2 000, and
   4 000 and describe the two growth patterns.
   ```python
   def has_duplicate_slow(values):
       """True when any value appears twice. Compares every pair."""
       for first in range(len(values)):
           for second in range(first + 1, len(values)):
               if values[first] == values[second]:
                   return True
       return False


   def has_duplicate_fast(values):
       """True when any value appears twice. Remembers what it has seen."""
       seen = {}
       for value in values:
           if value in seen:
               return True
           seen[value] = True
       return False
   ```
7. A classmate reports that their sort "takes 0.4 seconds, so it is
   $O(n)$". Name two things wrong with that sentence, and describe the
   smallest experiment that would settle the question.

## Judgement

8. Your team's program takes eleven seconds to produce the community
   centre's monthly report. One member wants to replace the sort with
   a faster one. What would you measure first, and what are the two
   most likely outcomes of that measurement?
9. A pull request replaces a linear search with a binary search and
   makes the report four times faster. All existing tests pass. Write
   the review comment you would leave, and say what would have to be
   true before you approve it.
10. **Theoretical bounds.** Why is it impossible for any
    comparison-based sorting algorithm to achieve a worst-case time
    better than $O(n \log n)$? Model comparison sorting as a binary
    decision tree and prove that the tree's height must be $\Omega(n \log n)$.

## Answers

> [!success]- Answer 1
> `first_item` is $O(1)$: one indexing operation, whatever the length.
> `total` is $O(n)$: the loop body runs once per item, so the count of
> additions equals the length. `every_pair` is $O(n^2)$: a loop inside
> a loop over the same list, so the append runs $n \times n$ times —
> and note it also *stores* $n^2$ pairs, so its memory is $O(n^2)$
> too. What was counted in each case: the operation that repeats most
> often.

> [!success]- Answer 2
> 1 600. The count is $n^2$, so doubling $n$ multiplies the steps by
> four: 100 at 10, 400 at 20, 1 600 at 40. The rule is the one worth
> memorising — in $O(n^2)$, doubling the input quadruples the work,
> and you can predict the next row of any such table without running
> anything.

> [!success]- Answer 3
> $3n + 12 \rightarrow O(n)$; the constant 12 stops mattering
> immediately and the 3 is a fixed factor, not a shape.
> $\frac{1}{2}n^2 - \frac{1}{2}n \rightarrow O(n^2)$; at $n = 1000$
> the squared term is a thousand times larger than the linear one.
> $n + n\log n \rightarrow O(n \log n)$; $n\log n$ dominates $n$.
> $2^n + n^{100} \rightarrow O(2^n)$; this is the surprising one —
> exponential growth eventually overtakes *any* polynomial, however
> huge its exponent.

> [!success]- Answer 4
> ```python
> def halvings(n):
>     """How many times can n be halved before reaching 1?"""
>     count = 0
>     while n > 1:
>         n = n // 2
>         count = count + 1
>     return count
>
>
> for n in [8, 1000, 1000000]:
>     print(n, halvings(n))
> ```
> ```text
> 8 3
> 1000 9
> 1000000 19
> ```
> This is $\log_2 n$, and it is the reason $O(\log n)$ algorithms feel
> like magic: a thousand times more data costs ten more steps. It is
> exactly the count binary search makes in [[Searching]].

> [!success]- Answer 5
> ```python
> def comparisons_to_find(values, target):
>     """Count comparisons a linear search makes before finishing."""
>     comparisons = 0
>     for value in values:
>         comparisons = comparisons + 1
>         if value == target:
>             return comparisons
>     return comparisons
>
>
> data = list(range(1000))
> print(comparisons_to_find(data, 0),
>       comparisons_to_find(data, 999),
>       comparisons_to_find(data, -1))
> ```
> ```text
> 1 1000 1000
> ```
> First item: 1, the best case. Last item and absent item: 1 000, the
> worst case — and note they are the *same* worst case, which is why
> "does this exist?" is as expensive as "where is the last one?". The
> average over all present targets is about $n/2$, which is still
> $O(n)$: halving a linear cost does not change its shape.

> [!success]- Answer 6
> Measured on one laptop, seconds for one call:
> ```text
>  items       slow       fast
>   1000   0.006302   0.000027
>   2000   0.025519   0.000061
>   4000   0.097346   0.000097
> ```
> The slow column **quadruples** each time the input doubles — the
> $O(n^2)$ signature of comparing every pair. The fast column roughly
> doubles: it is $O(n)$, because each value is checked against a
> dictionary in about constant time. At 4 000 items the difference is
> about a factor of a thousand, and it grows with every doubling.
>
> Your absolute numbers will differ. The ratios between the rows will
> not, and it is the ratios you should quote.

> [!success]- Answer 7
> First, a single time is not a growth rate: $O$ describes what
> happens as $n$ grows, and one measurement at one size cannot show
> that. Second, one run is noise — machine, other programs, and the
> state of the interpreter all move the number.
>
> The smallest experiment that settles it: run the same sort on
> several sizes — say 1 000, 2 000, 4 000, 8 000 — repeat each a few
> times, and look at the ratio between consecutive rows. Roughly 2×
> means linear, roughly 4× means quadratic. Better still, count
> comparisons instead: exact, reproducible, and unaffected by the
> laptop.

> [!success]- Answer 8
> Measure **where the eleven seconds actually go**, before changing
> anything — the technique is in [[Profiling and Timing Code]]. The
> two likely outcomes: (a) the sort is a small fraction of the total,
> in which case replacing it would make the program harder to read
> for no perceptible gain, and the real cost is somewhere nobody
> guessed, usually reading files or rebuilding the same list
> repeatedly; or (b) the sort really is most of it, in which case the
> first thing to try is Python's built-in `sorted`, which is
> $O(n \log n)$, tested by thousands of people, and one line.

> [!success]- Answer 9
> A review that names the condition, not the author:
>
> *"Nice speed-up, and the binary search itself looks correct
> including the `low <= high` boundary. It introduces a precondition
> the old code did not have: the list must be sorted. Where is it
> sorted, and is that guaranteed for every caller — including the
> import path that builds the list in arrival order? Please add the
> precondition to the docstring and a test that fails on an unsorted
> list, then I am happy to approve."*
>
> All tests passing is not evidence here: the old tests were written
> for a function with no preconditions, so none of them tries unsorted
> data. A change that is faster and correct *given a new assumption*
> is only safe once somebody has checked the assumption holds — the
> argument in [[Testing and Regression]] and the whole point of
> [[Read the Diff]].

> [!success]- Answer 10
> A comparison sort determines the permutation of $n$ distinct elements
> by making binary comparisons ($a_i \le a_j$).
>
> 1. **Decision tree model**: Any comparison sort can be represented
>    as a binary tree where each internal node is a comparison and each
>    leaf is one permutation of the input.
> 2. **Number of leaves**: There are $n!$ possible permutations of $n$
>    items. To sort correctly, the tree must have at least $n!$ leaves
>    ($L \ge n!$).
> 3. **Tree height and comparisons**: A binary tree of height $h$ has
>    at most $2^h$ leaves ($2^h \ge L \ge n!$). Taking the base-2
>    logarithm of both sides:
>    $$h \ge \log_2(n!)$$
> 4. **Stirling's approximation**:
>    $$\log_2(n!) = \sum_{i=1}^n \log_2 i \ge \sum_{i=n/2}^n \log_2(n/2) = \frac{n}{2}(\log_2 n - 1) = \Omega(n \log n)$$
>
> The height $h$ represents the worst-case number of comparisons.
> Therefore, no comparison-based sort can have a worst-case time better
> than $\Omega(n \log n)$. This is a **problem lower bound** (a limit
> on *any* comparison sort) rather than an upper bound on one algorithm.

%%curriculum-start%%
## Curriculum connection

![[C2.1]]

![[C2.2]]

![[C2.3]]

![[C2.4]]

![[D4.2]]
%%curriculum-end%%

