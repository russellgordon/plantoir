---
title: Efficiency and Big-O
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
You have been doing this all unit without the words for it. In
[[The Race]] you noticed that one lookup got slower with the file and
the other did not. In [[Sorting by Hand]] you noticed that doubling
the pile of cards more than doubled the work. Big-O is not a new idea;
it is the vocabulary for the thing you already saw.

It answers one question, and refuses to answer any other: **as the
input grows, how does the work grow?**

## Count, do not time

Timings depend on your laptop, the weather in the room, and what the
browser is doing. Counts do not. Count the operation that happens most
often — comparisons, usually — and the pattern appears immediately:

```python
def count_pairs(values):
    """Count how many times the inner line runs."""
    steps = 0
    for first in range(len(values)):
        for second in range(first + 1, len(values)):
            steps = steps + 1
    return steps
```

| Items | Steps |
| --- | --- |
| 10 | 45 |
| 20 | 190 |
| 40 | 780 |
| 80 | 3 160 |

Doubling the items roughly ==quadruples== the steps. That is the
signature you are learning to recognise, and it costs nothing to
measure — no stopwatch, no assumptions, identical on every machine.
Exactly, the count is $n(n-1)/2$, which is $\frac{1}{2}n^2 - \frac{1}{2}n$.

## The notation, and what it deliberately throws away

Big-O keeps only the term that dominates as $n$ grows, and drops
constants. $\frac{1}{2}n^2 - \frac{1}{2}n$ becomes ==$O(n^2)$== —
because at $n = 1000$ the $n^2$ term is a thousand times bigger than
the $n$ term, and the $\frac{1}{2}$ does not change the shape at all.

| Big-O | Called | Doubling $n$ does what | Where you have seen it |
| --- | --- | --- | --- |
| $O(1)$ | constant | nothing | dictionary lookup (average) |
| $O(\log n)$ | logarithmic | adds one step | [[Searching]], binary search |
| $O(n)$ | linear | doubles the work | linear search, one loop |
| $O(n \log n)$ | linearithmic | slightly more than doubles | merge sort, `sorted()` |
| $O(n^2)$ | quadratic | quadruples the work | bubble, insertion, selection |
| $O(2^n)$ | exponential | squares the work | naive Fibonacci |

Read the table as a ladder. One step down it is not a small
inconvenience: at a million items, $O(\log n)$ is about 20 operations
and $O(n^2)$ is a trillion. No faster laptop closes that gap, which is
why "just buy a better computer" is not an engineering answer.

## What Big-O hides, and why you still measure

Big-O is a statement about *growth*, not about speed today. Four
honest caveats, all of which you have already met:

- **Constants are real.** Two $O(n)$ algorithms can differ by a factor
  of fifty. Big-O says they will stay a factor of fifty apart.
- **Small inputs do not care.** For thirty volunteers, every algorithm
  on this page is instant. Choosing the clever one anyway, and making
  the code harder to read, is a bad trade — and
  [[Reading Somebody Else's Code]] is the bill that arrives later.
- **Best, average, worst are different questions.** Insertion sort is
  $O(n)$ on already-sorted data and $O(n^2)$ on reversed data. Quoting
  one number without saying which case is how people mislead
  themselves.
- **Memory counts too.** Merge sort is faster than insertion sort and
  uses extra space to do it. "Efficient" always means efficient in
  *something*.

> [!important] What a defensible claim sounds like
> Not "binary search is faster". Instead: *"Linear search is $O(n)$,
> binary search is $O(\log n)$ but requires sorted data. Our card file
> is sorted and read far more often than it is written, so we sort
> once and binary search after. Counted comparisons on 100 000 cards:
> 100 000 against 16. Measured on one laptop, the search went from
> about 1 ms to under 1 µs — your machine will differ, the ratio will
> not."* That paragraph is what
> [[C2.2|the search analysis expectation]] is asking for, and it is
> worth marks in [[The Structure Study]] and
> [[The Software Project]].

## Theoretical limits and complexity classes
 
Big-O is part of a larger mathematical field: **theoretical computer science**
and computational complexity theory. Computer scientists classify problems by
their intrinsic difficulty, independent of hardware:
 
- **Lower bounds on problems**: While an algorithm like insertion sort is
  $O(n^2)$ and merge sort is $O(n \log n)$, theoretical proofs establish
  that *any* comparison-based sorting algorithm requires at least $\Omega(n \log n)$
  comparisons in the worst case. Using a **decision tree model**, sorting $n$ items
  corresponds to identifying one of $n!$ possible permutations. A binary decision
  tree with $n!$ leaves must have a minimum height of $\log_2(n!) \approx n \log_2 n - n \log_2 e = \Omega(n \log n)$.
- **Complexity classes ($P$ vs $NP$)**: Problems solvable in polynomial time
  (like searching, sorting, and shortest-path graph algorithms) belong to class $P$.
  Problems whose solutions can be *verified* in polynomial time belong to $NP$.
  Whether $P = NP$ remains the central open question of theoretical computer science.
- **Computability and undecidability**: Alan Turing proved that certain problems
  (like the Halting Problem — determining whether an arbitrary program will
  eventually stop running) cannot be decided by *any* algorithm.
 
Understanding theoretical bounds helps engineers recognize when a problem is
provably hard and when an optimal algorithm has already been found.
 
Timing still matters — it is how you find out *which* part of a real
program is slow, which is almost never the part you guessed.
[[Profiling and Timing Code]] has the method; the rule is to measure
before you optimise, and to keep the correct version until the fast
one passes the same tests.
 
Do the counting yourself in [[Efficiency Practice]], watch the shapes
appear in [[Searching and Timing It]] and [[Sorting and Timing It]],
and see the exponential case bite in [[Recursion]].
 
%%curriculum-start%%
## Curriculum connection
 
![[C2.2]]
 
![[C2.3]]
 
![[C2.4]]
 
![[D4.2]]
%%curriculum-end%%
