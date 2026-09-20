---
title: Boolean Truth Tables and Compound Conditions
publish: true
created: __CREATED__
tags:
  - warmup
  - python
  - booleans
  - conditionals
---

Compound boolean expressions combine `and`, `or`, and `not` with comparison operators like `==`, `<`, and `>=`. Python always evaluates them to exactly `True` or `False` — but stacking several together can trip up even careful readers.

Below are five expressions. For each one, predict whether it evaluates to `True` or `False` **before** you run anything.

```python
temperature = 18
is_raining = False
has_umbrella = True

# Expression 1
print(temperature > 15 and not is_raining)

# Expression 2
print(temperature < 10 or is_raining)

# Expression 3
print(not (temperature > 15 and is_raining))

# Expression 4
print(has_umbrella or temperature < 0 and is_raining)

# Expression 5
print(temperature == 18 and has_umbrella and not is_raining)
```

Write down `True` or `False` for each of the five before checking your answers.

> [!success]- Answer 1
> `True`
>
> `temperature > 15` is `True` (18 > 15), and `not is_raining` is `True` (since `is_raining` is `False`). `True and True` is `True`.

> [!success]- Answer 2
> `False`
>
> `temperature < 10` is `False` (18 is not less than 10), and `is_raining` is `False`. `False or False` is `False`.

> [!success]- Answer 3
> `True`
>
> Inside the brackets, `temperature > 15` is `True` but `is_raining` is `False`, so `True and False` is `False`. The outer `not` flips that `False` to `True`.

> [!success]- Answer 4
> `True`
>
> This one is the trap: Python evaluates `and` before `or`, so this is really `has_umbrella or (temperature < 0 and is_raining)`. `has_umbrella` is `True`, so the whole expression is `True` no matter what the right-hand side works out to — Python does not even need to check it.

> [!success]- Answer 5
> `True`
>
> All three parts hold: `temperature == 18` is `True`, `has_umbrella` is `True`, and `not is_raining` is `True`. `True and True and True` is `True`.

If you predicted all five correctly, you already have a solid mental model of operator precedence. If Expression 4 caught you out, you are in good company — mixing `and` and `or` without brackets is one of the most common sources of logic bugs in real programs, which is exactly why experienced programmers add brackets even when they are not strictly required.

%%curriculum-start%%
## Curriculum connection

![[K1.8]]
%%curriculum-end%%
