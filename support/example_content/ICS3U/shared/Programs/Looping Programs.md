---
title: Looping Programs
publish: true
codeRunner: true
created: __CREATED__
tags:
  - programs
---
Ms. Nakamura advises the environment club, and once a month she has to
report one number: how much paper the club collected. She was doing it
with a calculator and a whiteboard, and the whiteboard got wiped once.
This program asks for the day's weights one at a time and gives back
the four numbers she actually reports.

## The program

To run it, press Run, and when it asks, type the number of days and
then one weight each time — `4`, `6.5`, `3`, `11.2` and `7`, as in the
run below.

```python run readonly
# Paper-recycling tally for Ms. Nakamura, who reports one number a
# month and was adding kilograms on a whiteboard.

days = 0
while days < 1:
    answer = input("How many collection days are you entering? ")
    if answer.isdigit():
        days = int(answer)
    if days < 1:
        print("Please type a whole number of days, like 5.")

total_kilograms = 0.0
heaviest = 0.0
heaviest_day = 0

for day in range(1, days + 1):
    kilograms = float(input(f"Day {day} — kilograms collected: "))
    total_kilograms = total_kilograms + kilograms
    if kilograms > heaviest:
        heaviest = kilograms
        heaviest_day = day

average = total_kilograms / days

print()
print(f"Collection days: {days}")
print(f"Total collected: {total_kilograms:.1f} kg")
print(f"Average per day: {average:.1f} kg")
print(f"Heaviest day:    day {heaviest_day}, {heaviest:.1f} kg")
```

```
How many collection days are you entering? 4
Day 1 — kilograms collected: 6.5
Day 2 — kilograms collected: 3
Day 3 — kilograms collected: 11.2
Day 4 — kilograms collected: 7

Collection days: 4
Total collected: 27.7 kg
Average per day: 6.9 kg
Heaviest day:    day 3, 11.2 kg
```

## How it works

There are two loops, and they are two different kinds on purpose.

The `while` loop guards the input. Nobody knows how many times somebody
will mistype a number, so the condition is "keep asking while we still
do not have a sensible answer". `answer.isdigit()` is `True` only when
every character typed is a digit, which quietly rejects `five`, `3.5`,
and an empty line without ever raising an error.

The `for` loop knows its lap count before it starts — `days` of them —
and does two jobs at once on each pass:

- **accumulating**: `total_kilograms` starts at zero and grows by one
  day's weight per pass;
- **remembering the best so far**: `heaviest` and `heaviest_day` update
  together, only when the current day beats the record.

Both patterns depend on their variables being created *before* the
loop. Move `total_kilograms = 0.0` inside the loop and the total resets
every pass, which is the bug traced by hand in
[[Testing and Debugging]].

The last four lines are the whole point of the program. A pile of
numbers went in and one report came out — input, process, output, with
the process finally doing something worth the trip.

> [!example]- What the guard loop accepts and rejects
> ```
> How many collection days are you entering? five
> Please type a whole number of days, like 5.
> How many collection days are you entering? 0
> Please type a whole number of days, like 5.
> How many collection days are you entering? 3.5
> Please type a whole number of days, like 5.
> How many collection days are you entering? 4
> Day 1 — kilograms collected:
> ```
> `0` is rejected on purpose: with zero days, the last calculation
> would be `total_kilograms / 0`, and Python would end the program with
> `ZeroDivisionError: division by zero`. The loop is not politeness —
> it is the thing standing between the user and a crash.

## Change it

1. **One line.** Change `if kilograms > heaviest:` to `>=`. Now, when
   two days tie for heaviest, the program reports the *later* one.
   Neither version is wrong; you just chose, and somebody using this
   report might care which.
2. **A few lines.** Track the lightest day as well, using a second pair
   of variables that start from the first day's weight rather than from
   zero. Starting the lightest at `0.0` would mean nothing ever beats
   it — a bug worth making once, on purpose.
3. **A real change.** Ms. Nakamura wants to know how many days were
   above average. You cannot do it as the program stands, because each
   weight is forgotten as soon as it is added — so `append` every
   weight to a list, then loop a second time over that list counting
   the ones above `average`. With the run shown above the answer is
   `2`. That is exactly the moment [[Lists]] stops being an idea and
   becomes a tool.

Practise the loop patterns in [[Loops Practice]], and see them stated
cleanly in [[Repetition]].

%%curriculum-start%%
## Curriculum connection

![[A2.2]]

![[A2.3]]

![[B1.3]]
%%curriculum-end%%
