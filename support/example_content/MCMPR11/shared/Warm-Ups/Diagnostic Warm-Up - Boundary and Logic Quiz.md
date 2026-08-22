---
title: Diagnostic Warm-Up - Boundary and Logic Quiz
publish: true
created: __CREATED__
tags:
  - warmup
  - python
  - conditionals
  - diagnostic
---

This is a quick temperature check, not a graded test. Six short questions, no code to write — just read, decide, and check yourself. It is worth revisiting this same page again later in the course; if a question that felt easy at the start of the course suddenly feels shaky before a bigger milestone, that is exactly the kind of thing worth reviewing before it costs you marks on something bigger.

**Question 1.** A test case checks that a function correctly handles the smallest and largest values it is meant to accept. What is the general name for those extreme, edge-of-range input values?

> [!success]- Answer 1
> **Boundary values** (or edge cases). Bugs cluster at boundaries far more often than in the comfortable middle of a range, which is exactly why good test cases always include them on purpose rather than by accident.

**Question 2.** A discount applies to ages `13` through `18` inclusive. Which condition correctly tests for that range?

```python
# Option A
if age > 13 and age < 18:

# Option B
if age >= 13 and age <= 18:

# Option C
if age >= 13 or age <= 18:
```

> [!success]- Answer 2
> **Option B.** "Inclusive" means both endpoints count, so the comparisons need `>=` and `<=`, not the strict `>` and `<` in Option A — those would silently exclude ages 13 and 18 themselves. Option C uses `or` instead of `and`, which is actually `True` for *every* age (any age is either ≥ 13 or ≤ 18, or both), so it applies the discount to everyone.

**Question 3.** `for i in range(5):` — what is the last value `i` takes on inside the loop?

> [!success]- Answer 3
> `4`. `range(5)` produces `0, 1, 2, 3, 4` — five values starting at 0, stopping *before* 5. Forgetting that `range` excludes its stop value is one of the most common sources of off-by-one bugs.

**Question 4.** A test suite for a "pass/fail" function checks scores of `49`, `50`, and `51`, where `50` is the passing mark. Why did the person writing the tests deliberately pick those three numbers instead of, say, `10`, `50`, and `90`?

> [!success]- Answer 4
> Because `49`, `50`, and `51` sit right on and around the actual boundary where behaviour is supposed to change — from fail to pass. A test at `10` or `90` only proves the obvious cases work; testing right at the boundary is what actually catches a `>` written where `>=` was needed, or the reverse.

**Question 5.** What does this print?

```python
mark = 50
if mark >= 50:
    print("Pass")
elif mark >= 80:
    print("Honours")
else:
    print("Fail")
```

> [!success]- Answer 5
> `Pass`. Python checks `elif`/`else` branches in order and stops at the **first** condition that is `True` — it never even looks at the later branches once one has matched. Since `mark >= 50` is already `True` for a mark of 50, "Honours" never gets checked, even though `80` would also satisfy it. This is a semantic bug hiding in the branch order, not a syntax error, so Python never warns you about it.

**Question 6.** True or false: if a function passes every test case you gave it, that proves the function has no bugs.

> [!success]- Answer 6
> **False.** Passing tests only proves the function is correct for the specific inputs you actually tested — it says nothing about inputs you never tried. This is exactly why boundary values, not just "typical" values, matter so much when choosing test cases: they give you the best chance of catching a bug with the fewest tests.

How did that feel? If most of these were quick, you are in good shape. If a couple made you pause, that is useful information — flag them for yourself and come back to this page again before the next milestone.

%%curriculum-start%%
## Curriculum connection

![[K1.15]]
%%curriculum-end%%
