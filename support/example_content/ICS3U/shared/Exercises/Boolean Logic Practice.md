---
title: Boolean Logic Practice
publish: true
codeRunner: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Boolean Logic]]. Every one of them can be
settled by typing it into Python — but predict first, because the
whole point is to make your prediction match the machine.

## Working it out

1. Give the value of each: `True and False`, `True or False`,
   `not True`, `(5 > 3) and (2 > 4)`.
2. With `on_roster = True` and `form_returned = False`, what does each
   of these produce?
   ```python
   on_roster and form_returned
   on_roster or form_returned
   not (on_roster and form_returned)
   ```
3. Complete the row: if `A` is `False` and `B` is `True`, then
   `A and B` is ___, `A or B` is ___, and `not A` is ___.
4. Are `not (A and B)` and `(not A) or (not B)` the same for all four
   combinations of `A` and `B`? Show your reasoning.

## Using it

5. **Find the fault.** It is Monday, and this prints `Weekend!`
   ```python run
   day = "Mon"
   if day == "Sat" or "Sun":
       print("Weekend!")
   ```
6. Why does this print `False` rather than crashing, when `sessions`
   is `0`?
   ```python
   print(sessions > 0 and minutes / sessions > 30)
   ```
7. Write one condition for: the book is overdue **and** it has not been
   renewed. Then give the two variables names that make the line read
   like the sentence.
8. **Challenge.** A student can go on the trip if they are 18 or older,
   or if a guardian has given permission. Write the condition, then
   explain why `or` is right here and `and` would be cruel.

## Answers

> [!success]- Answer 1
> `False`, `True`, `False`, `False`. The last one needs both sides to
> be `True`; `2 > 4` is `False`, so the whole expression is `False`
> regardless of the first part.

> [!success]- Answer 2
> `False`, `True`, `True` in that order. The second line is `True`
> because `or` needs only one side. The third is `True` because the
> thing inside the brackets is `False`, and `not` flips it — "it is not
> the case that both are true".

> [!success]- Answer 3
> `A and B` is `False`, `A or B` is `True`, `not A` is `True`. That is
> row three of the table in [[Boolean Logic]], and it is the row that
> catches people: an `or` written where `and` was meant lets this case
> through.

> [!success]- Answer 4
> Yes — identical in all four combinations. Try it:
> ```python run
> print(not (True and False))
> print((not True) or (not False))
> ```
> Both print `True`. In words, "not both" and "at least one is missing"
> say the same thing. Write whichever version a person can say out
> loud.

> [!success]- Answer 5
> Python reads it as `(day == "Sat") or ("Sun")`. A non-empty string
> counts as `True` on its own, so the second half is always `True`, so
> the whole condition is always `True`. Every comparison needs both
> sides:
> ```python
> if day == "Sat" or day == "Sun":
> ```
> Check it with `print(bool("Sun"))`, which prints `True`.

> [!success]- Answer 6
> `and` stops as soon as it meets a `False`. `sessions > 0` is `False`,
> so Python already knows the whole expression is `False` and never
> evaluates the division — which is the only reason there is no
> `ZeroDivisionError`. Swapping the two halves around would crash, so
> the order of an `and` can matter.

> [!success]- Answer 7
> ```python
> if is_overdue and not renewed_recently:
>     print("Send the reminder.")
> ```
> With `is_overdue = True` and `renewed_recently = False`, that prints
> `Send the reminder.` Both variables get their values earlier —
> `is_overdue = days_late > 0` — and naming them is the whole point:
> the librarian can read that condition aloud and tell you whether your
> rule matches her rule.

> [!success]- Answer 8
> ```python
> if age >= 18 or has_permission:
>     print("Cleared for the trip.")
> ```
> With `age = 16` and `has_permission = True` this is `True`. `and`
> would require both — an 18-year-old would still need a guardian's
> note, and a 16-year-old with permission would be refused. The
> operator is not a technicality here; it is the policy.
