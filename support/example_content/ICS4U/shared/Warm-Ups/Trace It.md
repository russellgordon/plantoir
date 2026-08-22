---
title: Trace It
publish: true
created: __CREATED__
tags:
  - warm-ups
---
Last year you traced a loop: one row per pass, variables changing in
place. A recursive function needs a different table, because nothing
changes in place. Each call gets its own private copy of the
parameters, and the calls pile up — every one of them frozen
mid-sentence, waiting for the call it just made to hand something
back. Tracing that pile is how recursion stops being magic.

## The program

```python
def power(base, exponent):
    if exponent == 0:
        return 1
    return base * power(base, exponent - 1)


print(power(2, 4))
```

## The trace table

One row per **call**, not per pass. Fill the "going down" column
first, top to bottom, then come back up filling the last column from
the bottom.

| Call | `exponent` | Base case reached? | Waiting for | Hands back |
| --- | --- | --- | --- | --- |
| `power(2, 4)` | 4 | no | `power(2, 3)` | 2 × 8 = 16 |
| `power(2, 3)` | 3 | no | `power(2, 2)` | 2 × 4 = 8 |
| `power(2, 2)` | 2 | no | `power(2, 1)` | 2 × 2 = 4 |
| `power(2, 1)` | 1 | no | `power(2, 0)` | 2 × 1 = 2 |
| `power(2, 0)` | 0 | **yes** | nothing | 1 |

The program prints `16`. Two things the table exposes that reading
never does. First, the multiplication happens on the way *back up* —
by the time the base case returns, four calls are sitting there
holding a `base * ...` they have not finished. Second, `exponent`
never changes; there are five different `exponent` variables, one per
call, and they simply never meet.

## How to run it

1. Draw the columns before you read the code. Deciding what to record
   is half the work.
2. Go down until you hit the base case. If you never hit it, stop —
   you have found the bug, and it is the interesting kind.
3. Come back up, filling in what each call hands to the one above it.
4. Compare tables with a neighbour, then run the program.

> [!example]- What happens with no base case in reach
> Change the last line to `print(power(2, -1))` and the exponent
> counts downward past zero forever. Python stops it, and the report
> is the most literal thing it ever prints — the same frame, over and
> over. It begins:
>
> ```text
> Traceback (most recent call last):
>   File "/home/student/power.py", line 7, in <module>
>     print(power(2, -1))
>           ^^^^^^^^^^^^
>   File "/home/student/power.py", line 4, in power
>     return base * power(base, exponent - 1)
>                   ^^^^^^^^^^^^^^^^^^^^^^^^^
>   File "/home/student/power.py", line 4, in power
>     return base * power(base, exponent - 1)
>                   ^^^^^^^^^^^^^^^^^^^^^^^^^
> ```
>
> Roughly a thousand identical frames follow, and Python has the
> decency to summarise them rather than print every one:
>
> ```text
>   [Previous line repeated 996 more times]
> RecursionError: maximum recursion depth exceeded
> ```
>
> A `RecursionError` almost never means "the problem was too big". It
> means the base case was never reachable from the argument you
> passed. Read the table: which column would have stayed the same
> forever?

Tracing on paper is slow, and that is the feature. See
[[Recursion]] for the clean statement of the idea, and try the same
technique on the program you have inherited in
[[The Inherited Program]] — a call stack you draw yourself is worth
more than an hour of scrolling.

%%curriculum-start%%
## Curriculum connection

![[A1.5]]

![[A3.5]]

![[C2.1]]
%%curriculum-end%%
