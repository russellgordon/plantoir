---
title: Trace It
publish: true
created: __CREATED__
tags:
  - warm-ups
---
Python does not read a program the way you read a paragraph. It reads
one line, does exactly that, and moves on — carrying the values of
every variable with it. Tracing is doing that job by hand, on paper,
with a table. It is slow, it is unglamorous, and it is the single most
reliable way to find out what a loop is actually doing.

## The program

```python
total = 0
for number in range(1, 6):
    if number % 2 == 0:
        total = total + number
print(total)
```

## The trace table

One row per pass through the loop. Fill it in before you run anything.

| Pass | `number` | `number % 2 == 0` | `total` after the pass |
| --- | --- | --- | --- |
| 1 | 1 | False | 0 |
| 2 | 2 | True | 2 |
| 3 | 3 | False | 2 |
| 4 | 4 | True | 6 |
| 5 | 5 | False | 6 |

The program prints `6`. Notice what the table exposes that reading
never does: `range(1, 6)` produced 1 through 5 and stopped *before* 6,
and `total` only changed on two of the five passes.

## How to run it

1. Draw the columns: one per variable, plus any condition being tested.
2. Walk the program line by line, writing every change down. If you
   find yourself skipping ahead, you have stopped tracing.
3. Compare tables with a neighbour before running the code.
4. Run it. A disagreement between your table and Python's answer is
   worth more than a page of correct tracing.

Tracing by hand is what a debugger automates, as
[[Using the Debugger]] shows — but doing it on paper first is how you
learn to read [[Repetition|a loop]] without one.

%%curriculum-start%%
## Curriculum connection

![[A1.5]]

![[B4.5]]
%%curriculum-end%%

