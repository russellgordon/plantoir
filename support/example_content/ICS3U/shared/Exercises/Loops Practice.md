---
title: Loops Practice
publish: true
codeRunner: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Repetition]]. A loop is a bargain: describe
one pass precisely and the computer does all of them. The two things
worth getting exactly right are how many passes happen, and which lines
are inside.

## Reading

1. How many lines does this print, and what is the last one?
   ```python run
   for day in range(1, 8):
       print(f"Day {day}")
   ```
2. **Trace it.** Give the value of `total` after each pass, then say
   what prints.
   ```python run
   weights = [6, 11, 7]
   total = 0
   for weight in weights:
       total = total + weight
   print(total)
   ```
3. **Find the fault.** This prints `7` when it should print `24`.
   ```python run
   weights = [6, 11, 7]
   for weight in weights:
       total = 0
       total = total + weight
   print(total)
   ```
4. How many lines does this print in total?
   ```python run
   for week in range(2):
       for day in range(3):
           print(f"Week {week}, day {day}")
   ```

## Writing

5. Write a `while` loop that keeps asking `How many bins? ` until the
   answer is made only of digits, then prints
   `Recording 6 bins.` Use `.isdigit()`.
6. Add up every even number from 2 to 20 and print the total. Do it
   twice — once with a `range` that steps by 2, and once with a `range`
   over every number and an `if` inside.
7. Why does `range(1, 8)` give you a week, and `range(1, 7)` give you
   only six days? State the rule in your own words.
8. **Challenge.** Keep asking for weights until the user types `done`,
   then report the heaviest — without storing anything in a list.

## Answers

> [!success]- Answer 1
> Seven lines, ending with `Day 7`. `range(1, 8)` starts at 1 and stops
> *before* 8.

> [!success]- Answer 2
> `total` is 6, then 17, then 24, and `24` prints. The `print` is
> outside the loop, so it runs once, after every pass is done. Move it
> inside and you get three lines instead of one.

> [!success]- Answer 3
> `total = 0` is inside the loop, so every pass throws away the running
> total and starts again — the printed value is only the last weight.
> Move that line above the `for`:
> ```python run
> weights = [6, 11, 7]
> total = 0
> for weight in weights:
>     total = total + weight
> print(total)
> ```
> An accumulator has to be created before the loop and used after it.

> [!success]- Answer 4
> Six. The inner loop runs completely — three passes — for each of the
> outer loop's two passes, so the count multiplies: 2 × 3. Nested loops
> are how you cover a table, a grid, or every day of every week.

> [!success]- Answer 5
> When it asks, type `four`, then `4`: the loop keeps asking until it
> gets digits.
> ```python run
> answer = ""
>
> while not answer.isdigit():
>     answer = input("How many bins? ")
>
> bins = int(answer)
> print(f"Recording {bins} bins.")
> ```
> Starting `answer` at `""` matters: the condition is checked *before*
> the first pass, and an empty string is not made of digits, so the
> question gets asked at least once.

> [!success]- Answer 6
> ```python run
> total = 0
> for number in range(2, 21, 2):
>     total = total + number
> print(total)
> ```
> ```python run
> total = 0
> for number in range(1, 21):
>     if number % 2 == 0:
>         total = total + number
> print(total)
> ```
> Both print `110`. The first says what you want; the second checks
> every number and throws half of them away. Prefer the first, but the
> second is the pattern you need the moment the test is more
> interesting than "is it even".

> [!success]- Answer 7
> `range(a, b)` includes `a` and stops before `b`, so the count is
> `b - a`. `range(1, 8)` is seven numbers, 1 through 7. Say it as "up
> to but not including", out loud, until it sticks — this is the most
> common off-by-one error in the language.

> [!success]- Answer 8
> When it asks, type one weight at a time — `6`, `11`, `7` — and
> `done` to finish.
> ```python run
> highest = 0
> entry = ""
>
> while entry != "done":
>     entry = input("Weight in kg (or 'done'): ")
>     if entry.isdigit():
>         weight = int(entry)
>         if weight > highest:
>             highest = weight
>
> print(f"Heaviest: {highest} kg")
> ```
> Entering 6, 11, 7, then `done` prints `Heaviest: 11 kg`. The
> `.isdigit()` check is what lets `done` pass through the loop without
> `int()` raising a `ValueError`. Notice the weakness of starting at
> `0`: if every weight could be negative, nothing would ever beat the
> start value — the fix is to record the first value seen instead.
