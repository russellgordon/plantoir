---
title: Repetition
publish: true
codeRunner: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
[[The Hundred-Line Problem]] was not a trick. Everybody genuinely
started copying and pasting the same `print` line, and everybody
stopped somewhere around the twelfth copy, because by then the mistake
was obvious: the program does not contain a hundred ideas. It contains
one idea, a hundred times. A loop is how you say that.

## Counting laps in advance

```python run readonly
for day in range(1, 8):
    print(f"Day {day}: warm-up, drills, scrimmage")
```

```
Day 1: warm-up, drills, scrimmage
Day 2: warm-up, drills, scrimmage
Day 3: warm-up, drills, scrimmage
Day 4: warm-up, drills, scrimmage
Day 5: warm-up, drills, scrimmage
Day 6: warm-up, drills, scrimmage
Day 7: warm-up, drills, scrimmage
```

`range(1, 8)` produces 1 up to *but not including* 8 — seven numbers.
That exclusive ending is deliberate (it makes `range(len(items))` line
up with list positions) and it is also the most reliable source of
off-by-one bugs in the language. When a loop runs one time too few,
suspect `range` before you suspect anything else.

Use `for` when the number of repetitions is knowable before the loop
starts: every day of a week, every mark in a list, every line in a
file.

## Repeating until something changes

```python
answer = ""
while answer != "yes":
    answer = input("Is the form in yet? ")
```

`while` re-checks its condition before every pass and keeps going while
it is `True`. You cannot know in advance how many times somebody will
mistype a number, so validating input is `while` territory — that is
exactly how [[Looping Programs]] refuses to start until it has a
sensible number of days.

> [!warning] The loop that never ends
> A `while` loop whose condition can never become `False` will run
> until you stop it. The usual cause is forgetting to change the
> variable the condition depends on:
> ```python run
> count = 3
> while count > 0:
>     print(count)
> ```
> `count` is never reduced, so this prints `3` forever. Run it: within
> a second the page stops it for printing too much. A stuck loop that
> prints nothing runs until you press **Stop**. Either way, look for
> what the loop was supposed to be changing, fix it, and run it again.

## The accumulator pattern

Most useful loops are not printing; they are building up an answer in a
variable that lives *outside* the loop.

```python run readonly
minutes = [45, 0, 60, 30, 0, 90, 25]

total = 0
for session in minutes:
    total = total + session

print(f"Total: {total} minutes over {len(minutes)} days")
```

```
Total: 250 minutes over 7 days
```

Three lines carry the whole pattern: start the accumulator at a value
that means "nothing yet", update it once per pass, and use it after the
loop. Change the starting value and the update, and the same skeleton
finds a highest value, counts how many items match a condition, or
builds a sentence. It is the reason a pile of numbers can become
something a person can act on.

## Loops inside loops

Once you have met [[Lists]], loops start containing loops — one pass
per week on the outside, one pass per day on the inside:

```python run readonly
weeks = []
weeks.append([45, 0, 60, 30, 0, 90, 25])
weeks.append([30, 30, 60, 0, 45, 60, 0])

for week_number in range(len(weeks)):
    total = 0
    for minutes in weeks[week_number]:
        total = total + minutes
    print(f"Week {week_number + 1}: {total} minutes")
```

```
Week 1: 250 minutes
Week 2: 225 minutes
```

Notice where `total = 0` sits. Inside the outer loop, it resets each
week, which is what you want. Move it above the outer loop and you get
a running total across all weeks — also a legitimate program, just not
this one. Indentation is the whole difference, and tracing it by hand
is faster than guessing; see [[Trace It]].

Get the reps in [[Loops Practice]], then read a complete loop-driven
program in [[Looping Programs]].

%%curriculum-start%%
## Curriculum connection

![[A2.2]]

![[A2.3]]

![[B3.1]]
%%curriculum-end%%
