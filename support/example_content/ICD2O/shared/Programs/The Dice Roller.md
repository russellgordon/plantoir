---
title: The Dice Roller
publish: true
created: __CREATED__
tags:
  - programs
---
Roll as many dice as you like; the program tallies every result and
draws a little bar chart out of `#` marks. A [[Loops|loop]], the
`random` module, and a first honest taste of
[[Data in Programs|data]] — generated, counted, and displayed.

## The program

```python
import random

count = int(input("How many dice should I roll? "))
tally = [0, 0, 0, 0, 0, 0]

for roll in range(count):
    result = random.randint(1, 6)
    tally[result - 1] = tally[result - 1] + 1

print()
print("Results of", count, "rolls:")

for face in range(1, 7):
    times = tally[face - 1]
    print(face, ":", "#" * times, "-", times)
```

## Read it before you run it

Predict in writing first — then run the program and grade yourself.

- `tally` is a list of six counters. Why does the program say
  `result - 1` — what goes wrong without the `- 1`?
- Predict the exact output for `0` dice. (Yes, zero. Trace it.)
- Now imagine `600` dice. Roughly what should the six bars look like —
  and what would a wildly uneven chart suggest about the dice?

## Make it yours

1. **One line.** Change the `#` bar into a character you like better.
2. **A few lines.** After the chart, announce which face came up most
   often — a loop over the tally will find it.
3. **A real change.** Roll *two* dice each round and tally the sums
   from 2 to 12. Run it big, look at the shape of the chart, and
   explain why 7 turns out to be the celebrity.

%%curriculum-start%%
## Curriculum connection

![[C1.4]]

![[C2.2]]

![[C3.1]]

![[C3.4]]
%%curriculum-end%%
