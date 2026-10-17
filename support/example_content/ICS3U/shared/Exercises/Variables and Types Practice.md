---
title: Variables and Types Practice
publish: true
codeRunner: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Variables and Data Types]] and
[[Input and Output]]. A variable is a name for a value; a type is what
that value is allowed to do. Almost every early bug in this course is
one of those two sentences being ignored.

## Questions

1. Give the type — `int`, `float`, `str`, or `bool` — for each: the
   number of chairs in a room; the mass of a recycling bin in
   kilograms; a book title; whether a permission form is in.
2. **Predict the output.**
   ```python run
   rows = 8
   rows = rows + 4
   print(rows)
   ```
3. **Predict the output.** Explain the quotation marks.
   ```python run
   print(type("14"))
   ```
4. **Find the fault.** The club advisor types `6.5` and this crashes.
   ```python
   answer = input("Kilograms collected: ")
   total = answer + 2.5
   ```
5. **Predict the output.**
   ```python run
   minutes = 185
   print(f"{minutes / 60:.1f}")
   ```
6. Rename these so the next reader does not have to guess:
   `x = 12`, `n = "Priya"`, `flag = True`.
7. Write a program that asks for a name and a number of days, then
   prints `Priya, the trip is in 14 days.`
8. **Challenge.** A coach has `total_minutes = 250`. Print it as
   `4 h 10 min`, without using a decimal point anywhere.

## Answers

> [!success]- Answer 1
> `int` for chairs (you count them, and half a chair is not a thing),
> `float` for kilograms (measurements have decimals), `str` for a
> title, `bool` for whether the form is in. If you were tempted by
> `str` for the mass, remember that text cannot be added up.

> [!success]- Answer 2
> `12`. The second line is not a contradiction — `=` means "work out
> the right-hand side and store it in the name on the left". Python
> computes `8 + 4` first, then puts `12` back into `rows`.

> [!success]- Answer 3
> `<class 'str'>`. The quotation marks make it text, not a number.
> `"14"` and `14` look identical when printed and behave completely
> differently: one can be added to `1` and one cannot.

> [!success]- Answer 4
> `input()` always returns text, so `answer` is the string `"6.5"`, and
> Python refuses to add a number to text:
> ```
> TypeError: can only concatenate str (not "float") to str
> ```
> Convert first, on its own line:
> ```python
> answer = input("Kilograms collected: ")
> kilograms = float(answer)
> total = kilograms + 2.5
> ```
> `float`, not `int` — `int("6.5")` raises `ValueError`, because `int`
> only accepts text that spells a whole number.

> [!success]- Answer 5
> `3.1`. The division gives `3.0833333333333335`; `:.1f` rounds the
> *display* to one decimal place. The value stored is unchanged —
> formatting is about the reader, not the arithmetic.

> [!success]- Answer 6
> Something like `chairs_per_row = 12`, `player_name = "Priya"`,
> `form_returned = True`. Boolean names read best as a claim that is
> either true or false, so `form_returned` beats `flag` and beats
> `is_form` too.

> [!success]- Answer 7
> When it asks, type a name and then a number of days.
> ```python run
> name = input("Name: ")
> days = int(input("Days until the trip: "))
> print(f"{name}, the trip is in {days} days.")
> ```
> ```
> Name: Priya
> Days until the trip: 14
> Priya, the trip is in 14 days.
> ```
> The `int()` is not strictly needed to print the number — but the
> moment anybody wants to subtract from it, text will not do.

> [!success]- Answer 8
> ```python run
> total_minutes = 250
> print(f"{total_minutes // 60} h {total_minutes % 60} min")
> ```
> ```
> 4 h 10 min
> ```
> `//` divides and discards the remainder; `%` keeps only the
> remainder. Ordinary `/` would give `4.1666...` hours, which is a
> different and less useful sentence.
