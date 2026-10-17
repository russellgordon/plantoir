---
title: Functions Practice
publish: true
codeRunner: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Functions]] and
[[Parameters, Returns, and Scope]]. A function is a named piece of
thinking: information goes in through parameters, an answer comes back
through `return`, and everything else stays inside.

## Reading

1. In `def letter_grade(mark):`, called as `letter_grade(78)`, name
   these four things: the definition, the parameter, the argument, and
   what `return "B"` does.
2. **Predict the output.**
   ```python run
   def double(number):
       print(number * 2)

   result = double(5)
   print(result)
   ```
3. **Find the fault.** This is supposed to give `69.5`.
   ```python run
   def average(values):
       total = 0
       for value in values:
           total = total + value
       total / len(values)

   print(average([78, 91, 46, 63]))
   ```
4. Why does this fail, and what should the last line be instead?
   ```python run
   def total_of(values):
       total = 0
       for value in values:
           total = total + value
       return total

   total_of([1, 2])
   print(total)
   ```

## Writing

5. Write `kilograms_to_pounds(kilograms)`, which returns the mass in
   pounds (multiply by 2.2). Print the result for `6.5` kg to one
   decimal place.
6. Write `is_overdue(days_late)`, which returns `True` or `False`. Show
   it being used directly inside an `if`.
7. Write `greet(name, greeting="Hello")` so that `greet("Priya")` and
   `greet("Priya", "Welcome back")` both work.
8. **Challenge.** These two lines appear in four places in a program:
   ```python
   hours = minutes // 60
   rest = minutes % 60
   ```
   Turn them into a function, then write a second function that uses
   the first to produce `Priya: 3 h 5 min`.

## Answers

> [!success]- Answer 1
> `def letter_grade(mark):` is the definition; `mark` is the parameter,
> a name that only exists inside the function; `78` is the argument,
> the value supplied at the call; and `return "B"` hands `"B"` back to
> whoever called and ends the function immediately. Leave the argument
> out and Python is precise about it:
> ```
> TypeError: letter_grade() missing 1 required positional argument: 'mark'
> ```

> [!success]- Answer 2
> `10`, then `None`. The function prints but never returns, so
> `result` receives Python's "no value at all". A function that prints
> can only ever do that one thing; a function that returns can be
> stored, compared, or passed on.

> [!success]- Answer 3
> The last line of the function computes the average and throws it
> away — there is no `return`, so the call produces `None`. Add it:
> ```python run
> def average(values):
>     total = 0
>     for value in values:
>         total = total + value
>     return total / len(values)
>
> print(average([78, 91, 46, 63]))
> ```
> ```
> 69.5
> ```

> [!success]- Answer 4
> `total` is local to `total_of` — created when the function starts and
> gone when it ends:
> ```
> NameError: name 'total' is not defined
> ```
> The caller has to catch the returned value:
> `print(total_of([1, 2]))`, which prints `3`. That restriction is a
> feature: nothing outside the function can be damaged by what happens
> inside it.

> [!success]- Answer 5
> ```python run
> def kilograms_to_pounds(kilograms):
>     return kilograms * 2.2
>
> print(f"{kilograms_to_pounds(6.5):.1f}")
> ```
> ```
> 14.3
> ```
> The function returns the full-precision number; the rounding belongs
> at the point of display, not inside the calculation.

> [!success]- Answer 6
> ```python run
> def is_overdue(days_late):
>     return days_late > 0
>
> if is_overdue(3):
>     print("Send the reminder.")
> ```
> `days_late > 0` is already `True` or `False`, so there is no need to
> write `if days_late > 0: return True`. Naming a condition like this
> is the cheapest readability win in the language.

> [!success]- Answer 7
> ```python run
> def greet(name, greeting="Hello"):
>     return f"{greeting}, {name}."
>
> print(greet("Priya"))
> print(greet("Priya", "Welcome back"))
> ```
> ```
> Hello, Priya.
> Welcome back, Priya.
> ```
> A default value makes the second parameter optional. Defaults must
> come after the parameters that have none.

> [!success]- Answer 8
> ```python run
> def as_hours_and_minutes(minutes):
>     return f"{minutes // 60} h {minutes % 60} min"
>
> def summary(name, minutes):
>     return f"{name}: {as_hours_and_minutes(minutes)}"
>
> print(summary("Priya", 185))
> ```
> ```
> Priya: 3 h 5 min
> ```
> The awkward arithmetic now exists once. When the coach asks for
> `3h05` instead, one function changes and every line of output follows
> — which is the entire argument for writing functions in the first
> place.
