---
title: Decisions Practice
publish: true
codeRunner: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Making Decisions]]. A decision in code is a
question with exactly one answer acted on — and most of the trouble
comes from the values sitting right on the boundary between two
branches.

## Reading

1. **Predict the output** for `mark = 70`, then for `mark = 69`, then
   for `mark = 80`.
   ```python
   if mark >= 80:
       print("Excellent")
   elif mark >= 70:
       print("Good")
   elif mark >= 50:
       print("Pass")
   else:
       print("Not yet")
   ```
2. What does this print when `temperature` is exactly `30`?
   ```python run
   temperature = 30
   if temperature > 30:
       print("Open the windows.")
   print("done")
   ```
3. **Find the fault** and say which of the three kinds of error it is.
   ```python
   days_late = 3
   if days_late > 0:
   print("Overdue")
   ```
4. **Trace it.** What prints when `minutes` is `0`?
   ```python
   if minutes > 0:
       if minutes < 30:
           print("Short session")
       else:
           print("Full session")
   else:
       print("Day off")
   ```

## Writing

5. Write the three-tier version of an overdue message: `0` or fewer
   days is on time, up to 7 days gets a reminder, anything more gets a
   letter home. Test it with `0`, `7`, and `8`.
6. A club meets only if at least five members are present *and* the
   room is booked. Write it with nested `if` statements, and print a
   different message for each of the three outcomes.
7. Somebody writes `if mark = 80:` and Python refuses to run the file
   at all. Why, and what did they mean?
8. **Challenge.** For the code in question 1, which four values of
   `mark` would you test to be confident every branch works, and why
   those four?

## Answers

> [!success]- Answer 1
> `70` prints `Good`, `69` prints `Pass`, `80` prints `Excellent`.
> Python tries each condition in order and stops at the first `True`.
> `>=` includes the boundary value itself, which is why 70 is `Good`
> and not `Pass`.

> [!success]- Answer 2
> Only `done`. `30 > 30` is `False`, so the indented line is skipped
> entirely. The unindented `print` is not part of the `if` and always
> runs. If 30 should count as hot, the condition needs `>=`.

> [!success]- Answer 3
> The `print` is not indented, so Python never sees a body for the
> `if`:
> ```
> IndentationError: expected an indented block after 'if' statement on line 2
> ```
> It is a **syntax error** — the file never runs at all. Indent the
> `print` by four spaces and it works.

> [!success]- Answer 4
> `Day off`. `0 > 0` is `False`, so Python jumps straight to the
> matching `else` and never looks at the inner `if` at all. Indentation
> is what pairs that `else` with the outer question rather than the
> inner one.

> [!success]- Answer 5
> Type a number of days in the input box — `0`, `7` or `8` — then
> press Run.
> ```python run
> answer = input("Days late: ")
> days_late = int(answer)
>
> if days_late <= 0:
>     print("On time.")
> elif days_late <= 7:
>     print("Just remind them.")
> else:
>     print("Send the letter home.")
> ```
> `0` gives `On time.`, `7` gives `Just remind them.`, and `8` gives
> `Send the letter home.` The middle branch needs no lower limit: it is
> only reached when the first condition already failed.

> [!success]- Answer 6
> ```python
> if members_present >= 5:
>     if room_booked:
>         print("Meeting goes ahead.")
>     else:
>         print("Enough people, but no room.")
> else:
>     print("Not enough people.")
> ```
> With `members_present = 4` this prints `Not enough people.`
> whether or not the room is booked — the inner question is never
> reached. That is the nesting working correctly.

> [!success]- Answer 7
> `=` assigns a value; `==` compares two values. `if mark = 80:` asks
> Python to store something in the middle of a question, and Python
> refuses:
> ```
> SyntaxError: invalid syntax. Maybe you meant '==' or ':=' instead of '='?
> ```
> They meant `if mark == 80:`. Being caught by the compiler is the best
> outcome available for this mistake.

> [!success]- Answer 8
> One value per branch, chosen *at* the boundaries — `80`, `70`, `50`,
> and `49`. The first three land exactly on a cutoff and prove that
> `>=` includes it; the `49` proves the `else` is reachable. Testing
> `80` matters far more than testing `83`: bugs live at the edges,
> where `>` and `>=` disagree, and a value in the middle of a range
> cannot tell the two apart.
