---
title: Recursion
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
The question on the board was innocent: count every file on this
drive. Then somebody opened a folder and found a folder, which
contained a folder. A loop can walk one folder. A loop cannot walk a
structure that is a copy of itself, however deep, because you do not
know how many loops to write.

A recursive function is one that calls itself on a smaller piece of
the same problem. It is not a trick, and it is not always the right
answer — but for problems shaped like that drive, it is the only
description that is honest about the shape.

## Base case first, always

```python
def factorial(n):
    """Return n! for n >= 0. Base case: 0! is 1."""
    if n == 0:
        return 1
    return n * factorial(n - 1)
```

```text nowrap
factorial(5)  ->  120
factorial(0)  ->  1
factorial(20) ->  2432902008176640000
```

Two rules, and both are visible in four lines:

1. **A base case** that returns without calling itself. Here, `n == 0`.
2. **Progress** towards that base case on every call. Here, `n - 1`.

Write the base case first, physically, at the top of the function.
Every recursive function that has ever run forever was missing one or
the other.

`factorial(5)` does not loop. It builds a stack of unfinished
multiplications — `5 * (4 * (3 * (2 * (1 * 1))))` — and finishes them
on the way back up. That is the same call stack from
[[Stacks and Queues]], doing what it always does, but now you can
watch it grow.

The drive from the opening paragraph, in seven lines:

```python
def count_files(folder):
    """Count every file in a folder and all folders inside it."""
    total = 0
    for item in folder:
        if isinstance(item, list):
            total = total + count_files(item)
        else:
            total = total + 1
    return total
```

```python
drive = ["notes.txt",
         ["essay.docx", "draft.docx", ["photo1.jpg", "photo2.jpg"]],
         "budget.csv"]
print(count_files(drive))
```

```text wrap
6
```

The base case here is quiet but real: a folder with no folders inside
it never recurses, so the loop just counts. This is the shape that
makes recursion worth learning — the function does not know or care
how deep the nesting goes.

## What happens when you forget

```python
def countdown(n):
    print(n)
    countdown(n - 1)

countdown(3)
```

> [!bug] The traceback for a missing base case
> ```text nowrap
> 3
> 2
> 1
> 0
> -1
> ...
> Traceback (most recent call last):
>   File "countdown.py", line 5, in <module>
>     countdown(3)
>     ~~~~~~~~~^^^
>   File "countdown.py", line 3, in countdown
>     countdown(n - 1)
>     ~~~~~~~~~^^^^^^^
>   File "countdown.py", line 3, in countdown
>     countdown(n - 1)
>     ~~~~~~~~~^^^^^^^
>   [Previous line repeated 996 more times]
> RecursionError: maximum recursion depth exceeded
> ```
> The function is perfectly correct Python. It counts down past zero
> for ever, because nothing tells it to stop, and each call adds a
> frame to the call stack until Python's limit — 1 000 frames by
> default — runs out. `[Previous line repeated 996 more times]` is
> the interpreter being kind; the exact count varies with how deep
> your program already was.

Read that error as a *design* message, not a memory problem. Raising
the limit is almost never the fix. The fix is a base case, or a loop.

## The pitfall that does not crash

```python
def fib(n):
    """Return the nth Fibonacci number, counting from fib(0) = 0."""
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)
```

This is correct. It has a base case, it makes progress, it returns the
right answers. It is also close to unusable, because each call makes
two more:

| `n` | calls made | answer |
| --- | --- | --- |
| 10 | 177 | 55 |
| 20 | 21 891 | 6 765 |
| 30 | 2 692 537 | 832 040 |

Ten more on `n` costs roughly a hundred times the work. `fib(50)` on
this definition would still be running at the end of the period,
because the same subproblems are recomputed millions of times.
[[C2.4|the recursion pitfalls expectation]] names both traps: infinite
recursion, which announces itself loudly, and exponential growth,
which does not.

The loop version is boring, linear, and finishes instantly:

```python
def fib_loop(n):
    """The same numbers, with a loop instead of recursion."""
    previous = 0
    current = 1
    if n == 0:
        return 0
    for step in range(n - 1):
        previous, current = current, previous + current
    return current
```

## Recursion or a loop — honestly

Use recursion when the **data** is recursive: folders inside folders,
a comment with replies that have replies, a merge sort that sorts two
halves the same way it sorts the whole. In those cases the recursive
version is shorter, matches the problem, and is easier to defend in a
review.

Use a loop when the problem is a straight sequence. Counting, totalling,
and walking a list are loops. Writing them recursively is a party trick
that costs stack frames and readability.

> [!tip] Trust the recursive call
> The hardest part of writing recursion is psychological: you must
> assume the call on the smaller piece already works, and only get the
> combining step right. Tracing every level by hand is how you *check*
> a recursive function, not how you write one. [[Trace It]] has the
> method for when you do need to follow it down.

Practise in [[Recursion Practice]], where the base case is the marked
part. If you meet a `RecursionError` in code you did not write,
[[Reading a Traceback in Someone Else's Code]] shows how to find the
missing base case in somebody else's function.

%%curriculum-start%%
## Curriculum connection

![[A3.6]]

![[C2.4]]

![[C1.3]]
%%curriculum-end%%
