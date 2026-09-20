---
title: Functions, Parameter Scope, and Pure Decomposition
publish: true
created: __CREATED__
tags:
  - concept
enableToc: true
---
As programs grow, writing all your code in one long block becomes unmanageable. We manage complexity by wrapping specific tasks into **functions**. A well-designed function acts like a black box: you hand it inputs (arguments), and it hands you back a result, without you needing to know how it did the math inside.

## Pure vs. Impure Functions

The safest and most reliable functions are **pure functions**. 

A pure function follows two rules:
1. It always returns the exact same output for the same input.
2. It has zero observable side effects (it doesn't change global variables, write to files, or print to the screen).

| Type | Example | Characteristics |
| :--- | :--- | :--- |
| **Pure** | `def calc_tax(price: float) -> float:` | Deterministic, easy to test, no side effects. |
| **Impure** | `def log_error(msg: str) -> None:` | Writes to a file (side effect). Harder to test. |
| **Impure** | `def get_current_time() -> str:` | Result changes every second (non-deterministic). |

## The Rules of Scope (LEGB)

When you create a variable inside a function, it is temporary. It exists only while the function is running. This is called **Local Scope**.

Python resolves variable names using the **LEGB rule**, searching in this order:
1. **L**ocal: Inside the current function.
2. **E**nclosing: Inside any wrapping functions.
3. **G**lobal: Defined at the top level of the file.
4. **B**uilt-in: Python's pre-defined names (like `print` or `len`).

```python
# Global Scope
MINIMUM_WAGE = 16.75  # BC minimum wage

def calculate_pay(hours_worked: float) -> float:
    # Local Scope
    # 'hours_worked' and 'total_pay' only exist inside this block
    total_pay = hours_worked * MINIMUM_WAGE
    return total_pay

print(calculate_pay(15))

# This will crash! 'total_pay' is invisible out here.
# print(total_pay) 
```

> [!warning] The Danger of Global State
> You can read global variables inside a function, but you should avoid modifying them using the `global` keyword. When multiple functions change shared global variables, bugs become nearly impossible to track down. Pass data in as arguments, and pass data out using `return`.

## Refactoring with Functions

When you spot the exact same logic written twice, that is a signal to refactor by extracting the logic into a function.

> [!example]- Refactoring a Salary Calculator
> 
> **Before (Repetitive):**
> ```python
> alice_base = 50000
> alice_bonus = 50000 * 0.05
> alice_total = alice_base + alice_bonus
> 
> bob_base = 60000
> bob_bonus = 60000 * 0.05
> bob_total = bob_base + bob_bonus
> ```
> 
> **After (Clean and modular):**
> ```python
> def calculate_total_comp(base_salary: float, bonus_rate: float = 0.05) -> float:
>     """Calculates total compensation given a base and a rate."""
>     return base_salary + (base_salary * bonus_rate)
> 
> alice_total = calculate_total_comp(50000)
> bob_total = calculate_total_comp(60000)
> ```

By decomposing the problem into a pure function, we guarantee that Alice and Bob are subject to the exact same mathematical rules, and if the bonus formula changes, we only have to update it in one place.

%%curriculum-start%%
## Curriculum connection

![[K1.3]]
%%curriculum-end%%
