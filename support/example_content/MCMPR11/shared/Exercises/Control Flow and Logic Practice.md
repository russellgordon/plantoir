---
title: Control Flow and Logic Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions let you practice logic and control flow. A decision in code is a
question with exactly one answer acted on — and most of the trouble comes from
the values sitting right on the boundary between two branches.[^1]

[^1]: This is why testing boundary values is so important in real software,
      like the systems managing BC Ferries reservations.

## Reading

1. **Predict the output** for `risk = 4`, then for `risk = 5`, then for `risk = 2`.
   ```python
   if risk >= 5:
       print("Extreme wildfire danger")
   elif risk >= 4:
       print("High danger")
   elif risk >= 2:
       print("Moderate danger")
   else:
       print("Low danger")
   ```
2. What does this print when `wind_speed` is exactly `60`?
   ```python
   wind_speed = 60
   if wind_speed > 60:
       print("Cancel ferry sailings.")
   print("Update posted")
   ```
3. **Find the fault** and say which of the three kinds of error it is.
   ```python
   minutes_to_sailing = 15
   if minutes_to_sailing < 30:
   print("Boarding soon")
   ```
4. **Trace it.** What prints when `passengers` is `0`?
   ```python
   if passengers > 0:
       if passengers < 100:
           print("Standard sailing")
       else:
           print("Busy sailing")
   else:
       print("Empty vessel")
   ```

## Writing

5. Write a three-tier version of a ferry message: `10` or fewer minutes until departure means "Boarding now", up to 30 minutes means "Standby", and anything more is "On time". Test it with `10`, `30`, and `45`.
6. An evacuation alert only sounds if the `fire_distance` is less than 5 kilometres *and* the `wind_direction` is `"towards_town"`. Write it with nested `if` statements, and print a different message for each of the three outcomes.
7. Somebody writes `if level = 5:` and Python refuses to run the file at all. Why, and what did they mean?
8. **Challenge.** For the code in question 1, which four values of `risk` would you test to be confident every branch works, and why those four?

## Answers

> [!success]- Answer 1
> `4` prints `High danger`, `5` prints `Extreme wildfire danger`, `2` prints `Moderate danger`.
> Python tries each condition in order and stops at the first `True`. `>=` includes the boundary value itself, which is why 5 is `Extreme` and not `High`.

> [!success]- Answer 2
> Only `Update posted`. `60 > 60` is `False`, so the indented line is skipped entirely. The unindented `print` is not part of the `if` and always runs. If 60 should trigger a cancellation, the condition needs `>=`.

> [!success]- Answer 3
> The `print` is not indented, so Python never sees a body for the `if`. It is a **syntax error** — the file never runs at all. Indent the `print` by four spaces and it works.

> [!success]- Answer 4
> `Empty vessel`. `0 > 0` is `False`, so Python jumps straight to the matching `else` and never looks at the inner `if` at all. Indentation is what pairs that `else` with the outer question rather than the inner one.

> [!success]- Answer 5
> ```python
> minutes = int(input("Minutes to departure: "))
> if minutes <= 10:
>     print("Boarding now")
> elif minutes <= 30:
>     print("Standby")
> else:
>     print("On time")
> ```
> `10` gives `Boarding now`, `30` gives `Standby`, and `45` gives `On time`. The middle branch needs no lower limit because it is only reached when the first condition fails.

> [!success]- Answer 6
> ```python
> if fire_distance < 5:
>     if wind_direction == "towards_town":
>         print("Sound evacuation alert!")
>     else:
>         print("Monitor fire closely.")
> else:
>     print("Fire is distant.")
> ```
> With `fire_distance = 6`, this prints `Fire is distant.` whether or not the wind is blowing towards town — the inner question is never reached.

> [!success]- Answer 7
> `=` assigns a value; `==` compares two values. `if level = 5:` asks Python to store something in the middle of a question, which is a syntax error. They meant `if level == 5:`.

> [!success]- Answer 8
> One value per branch, chosen *at* the boundaries — `5`, `4`, `2`, and `1`. The first three land exactly on a cutoff and prove that `>=` includes it; the `1` proves the `else` is reachable. Testing boundaries catches off-by-one errors.

%%curriculum-start%%
## Curriculum connection

![[K1.8]]
%%curriculum-end%%
