---
title: Operators Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Data in Programs]]. Operators are the verbs
of a program — and Python applies them in a strict order, not yours.

## Questions

1. Evaluate `2 + 3 * 4` — and explain why the answer is not `20`.
2. **Predict the output** of `print(7 // 2, 7 % 2)`.
3. **Predict the output** of `print("na" * 4 + " Batman!")`.
4. Trace `x`, then predict what prints — and what *type* of value it is.
   ```python
   x = 10
   x = x + 2 * 3
   print(x > 15)
   ```
5. With `age = 16`, evaluate each: (a) `age >= 13 and age <= 19`,
   (b) `not (age == 16)`, (c) `age == 16 or age == 61`.
6. **Find the bug.** `if answer == "yes" or "y":` runs its branch no
   matter what the user typed. Why — and what should it say?
7. **Challenge.** Add one pair of brackets to `2 + 3 * 4 - 1` so it
   equals `19` — then a different pair so it equals `11`.

## Answers

> [!success]- Answer 1
> `14`. Multiplication happens before addition — the order of
> operations from maths class survives intact in Python.

> [!success]- Answer 2
> `3 1` — `//` is division that keeps only the whole part, and `%`
> hands back the remainder. Seven is two twos with one left over.

> [!success]- Answer 3
> `nananana Batman!` — `*` repeats the string four times first, then
> `+` glues on the ending. Text has operators too.

> [!success]- Answer 4
> Multiply first: `x` becomes `10 + 6`, so `16`. Then `16 > 15` is
> `True` — a Boolean (`bool`), the yes/no type conditionals live on.

> [!success]- Answer 5
> (a) `True` — both sides hold. (b) `False` — `not` flips a truth.
> (c) `True` — `or` needs only one side, and the first delivers.

> [!success]- Answer 6
> Python reads it as `(answer == "yes") or ("y")` — and a non-empty
> string like `"y"` counts as true on its own, every single time.
> It should say `answer == "yes" or answer == "y"`.

> [!success]- Answer 7
> `(2 + 3) * 4 - 1` gives `19`; `2 + 3 * (4 - 1)` gives `11`.
> Brackets outrank everything — same symbols, three different answers.

%%curriculum-start%%
## Curriculum connection

![[C1.3]]

![[C1.4]]

![[C2.5]]
%%curriculum-end%%
