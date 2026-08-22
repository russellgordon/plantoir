---
title: Loop Invariants and Boundary Edge Cases
publish: true
created: __CREATED__
tags:
  - exploration
  - algorithms
  - loops
  - testing
---

When designing loops, it's easy to get the logic right for normal lists, but completely fail on weird edge cases. 

A **loop invariant** is a condition or truth that holds before the loop starts, at the end of each iteration, and after the loop terminates. Establishing an invariant helps us prove that our loop works.

**Boundary edge cases** are inputs that test the extreme limits of your algorithm: empty lists, lists with one item, lists where everything is the same, or negative numbers.

### Analyze the Loops

For each loop below, identify the goal, state a loop invariant, and predict what happens on the provided edge cases.

#### Loop 1: Find the Maximum

```python
def find_max(numbers):
    highest = numbers[0]
    for num in numbers:
        if num > highest:
            highest = num
    return highest
```

- **Invariant:** `highest` always holds the maximum value seen *so far* in the list.
- **Test 1:** `numbers = [4, 7, 2]`
- **Edge Case 1:** `numbers = [5, 5, 5]`
- **Edge Case 2:** `numbers = []`

> [!success]- Analysis 1
> - **Test 1:** Returns 7.
> - **Edge Case 1:** Returns 5. Works fine with duplicates.
> - **Edge Case 2 (Empty):** Crashes! `numbers[0]` causes an `IndexError` because an empty list has no index 0. 
> **Fix:** Check `if not numbers: return None` before the loop.

#### Loop 2: Are All Elements Positive?

```python
def all_positive(numbers):
    for num in numbers:
        if num <= 0:
            return False
    return True
```

- **Invariant:** If the loop is currently on iteration `i`, all elements before index `i` are guaranteed to be strictly greater than 0.
- **Test 1:** `numbers = [10, 20, -5, 30]`
- **Edge Case 1:** `numbers = [0, 1, 2]`
- **Edge Case 2:** `numbers = []`

> [!success]- Analysis 2
> - **Test 1:** Returns `False` when it hits `-5`.
> - **Edge Case 1:** Returns `False` when it hits `0`. Correct, 0 is not positive.
> - **Edge Case 2 (Empty):** The loop never runs, so it skips directly to `return True`. Is an empty list considered "all positive"? In formal logic, yes (vacuous truth), but depending on the application, you might want to return `False`.

### Exploration Task

Write a loop that counts how many times the substring `"bc"` appears in a string `text`. 
Test it against these edge cases:
- `text = ""` (empty)
- `text = "bc"` (exact match)
- `text = "bcbcbc"` (contiguous)
- `text = "b"` (too short)

Does your logic hold up?

%%curriculum-start%%
## Curriculum connection

![[K1.6]]

![[K1.15]]
%%curriculum-end%%
