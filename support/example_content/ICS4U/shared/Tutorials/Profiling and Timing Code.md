---
title: Profiling and Timing Code
publish: true
created: __CREATED__
tags:
  - tutorials
enableToc: true
---
"This one feels faster" is not an argument, and neither is "binary
search is $O(\log n)$ so obviously". One is a guess and the other is
a claim about how the cost *grows*, which is not the same as a claim
about how long your program takes this afternoon. Measuring is how
you find out. It takes about six lines.

## `time.perf_counter()` — timing one thing

Read the clock, do the work, read the clock again. `perf_counter()`
returns a number of seconds whose starting point is meaningless; only
the difference between two readings means anything, which is exactly
what you want.

```python
import time

from search_lib import linear_search, binary_search

names = []
for number in range(200000):
    names.append("member-" + str(number).zfill(6))

target = names[-1]

start = time.perf_counter()
linear_search(names, target)
elapsed = time.perf_counter() - start
print(f"linear search: {elapsed:.6f} seconds")

start = time.perf_counter()
binary_search(names, target)
elapsed = time.perf_counter() - start
print(f"binary search: {elapsed:.6f} seconds")
```

On the machine this was written on:

```text
linear search: 0.003578 seconds
binary search: 0.000005 seconds
```

Do not write those numbers in a report. Write what they mean.

> [!warning] One measurement is noise
> Running that same program three times in a row gave
> `0.003578`, `0.003273`, and `0.003243` seconds for the linear
> search. Nothing changed between the runs; the machine was simply
> busy with other things. Any conclusion that depends on the third
> decimal place is a conclusion about what else your computer was
> doing.
>
> What survives repetition is the *relative* result: the linear
> search took hundreds of times as long, every single run, on every
> machine in the room. That is the finding.

## `timeit` — timing something small, properly

For anything fast, one reading is useless: the work finishes before
the clock has meaningfully moved. `timeit` runs the code many times
and reports the total, and it does the fiddly parts for you.

```python
import timeit

setup = """
from search_lib import linear_search, binary_search
names = []
for number in range(200000):
    names.append("member-" + str(number).zfill(6))
target = names[-1]
"""

linear = timeit.timeit("linear_search(names, target)", setup=setup, number=100)
binary = timeit.timeit("binary_search(names, target)", setup=setup, number=100)

print(f"linear search, 100 runs: {linear:.4f} seconds")
print(f"binary search, 100 runs: {binary:.4f} seconds")
print(f"linear took {linear / binary:.0f} times as long")
```

```text
linear search, 100 runs: 0.3656 seconds
binary search, 100 runs: 0.0001 seconds
linear took 3468 times as long
```

Two things to understand about that code. The `setup` string runs
**once**, before timing starts, so building the list of 200 000 names
does not count against either result. And `number=100` is the number
of repetitions — raise it until the total is at least a few tenths of
a second, or you are measuring the clock rather than the code.

The ratio moved on a second run, from 3468 to 3608. Report it as
"roughly three thousand times", not as 3468. Precision you cannot
reproduce is not precision.

## Measure the growth, not the moment

A single pair of numbers tells you which is faster *today, on this
input*. The question [[Efficiency and Big-O]] actually asks is what
happens when the input gets bigger. So run it at several sizes and
put the results in a table:

| List length | Linear search | Binary search |
| --- | --- | --- |
| 1 000 | fast | fast |
| 10 000 | about ten times the 1 000 case | barely moved |
| 100 000 | about a hundred times | barely moved |

Fill that table with your own measured numbers and the shape appears
without anybody having to define a logarithm: doubling the list
roughly doubles the linear search and adds *one step* to the binary
search. Big-O is the vocabulary for the pattern in your own table,
which is the right order to meet it in.

## Three ways to measure the wrong thing

- **Timing with the cache warm.** Searching for the same item twice
  in a row can be much faster the second time, for reasons that have
  nothing to do with your algorithm. Vary what you search for.
- **Timing the setup.** If your timed region builds the list, you are
  mostly measuring list-building. Keep the clock around the work you
  are asking about and nothing else.
- **Timing the easy case.** Linear search looks wonderful if the
  target is always first. Search for something at the end, and for
  something absent — the honest worst case is the one worth
  reporting, and it is the one your partner's real data will
  eventually hand you.

> [!important] Measure before you optimise
> The slow part of a program is almost never where people guess it
> is. Before you rewrite anything for speed, time it and find out
> where the time actually goes. Then ask the harder question: is it
> slow enough to matter to the person using it? A tenth of a second
> saved in code nobody waits on is a tenth of a second you spent
> making the program harder to read — a trade
> [[Writing Code Others Can Read]] will make you defend.

Bring a measured comparison to [[The Race]], and expect to defend
your algorithm choice with numbers in [[The Structure Study]]. "It
felt faster" is not going to survive the question "compared to
what?"

%%curriculum-start%%
## Curriculum connection

![[C2.2]]

![[C2.3]]
%%curriculum-end%%
