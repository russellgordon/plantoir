---
title: Refactor This Branching Maze
publish: true
created: __CREATED__
tags:
  - warmup
  - python
  - refactoring
  - conditionals
---

Deeply nested `if/elif/else` statements make code incredibly difficult to read, maintain, and test. 

Look at the following function that determines BC Ferries ticket pricing. It works, but it's a structural mess.

```python
def get_ferry_fare(age, is_resident):
    if is_resident == True:
        if age < 5:
            return 0
        else:
            if age >= 65:
                return 0
            else:
                if age >= 12:
                    return 18.00
                else:
                    return 9.00
    else:
        if age < 5:
            return 0
        else:
            if age >= 12:
                return 18.00
            else:
                return 9.00
```

Your challenge: **Refactor** this code into a readable version with minimal nesting. You can use early returns, logical operators like `and` / `or`, or simplify the logic entirely.

> [!success]- Answer 1
> There are many ways to simplify this. Notice that children under 5 always travel free, and non-residents never get the senior discount. Here is a much cleaner version using early returns and flat logic:
> 
> ```python
> def get_ferry_fare(age, is_resident):
>     # Everyone under 5 is free
>     if age < 5:
>         return 0
>         
>     # BC Residents 65+ are free
>     if is_resident and age >= 65:
>         return 0
>         
>     # Kids 5-11 pay half fare
>     if age < 12:
>         return 9.00
>         
>     # Everyone else pays full fare
>     return 18.00
> ```
> 
> This version is shorter, easier to read, and avoids unnecessary `else` blocks!

%%curriculum-start%%
## Curriculum connection

![[K1.5]]
%%curriculum-end%%
