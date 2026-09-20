---
title: Spot the Off-by-One Bug
publish: true
created: __CREATED__
tags:
  - warmup
  - python
  - debugging
  - loops
---

Off-by-one errors happen when a loop runs one time too many or one time too few, or when a boundary index is calculated incorrectly. They are among the most common logical errors in programming.

Below are three snippets. Each contains a subtle off-by-one bug. Find and fix them.

### Snippet A: Building a Fence

```python
# We want to place a post every meter for 10 meters.
# 10 meters requires 11 posts (0, 1, 2... 10).
posts = []
for i in range(10):
    posts.append(f"Post at {i}m")
```

> [!success]- Answer 1
> `range(10)` generates numbers from 0 to 9, which is only 10 posts, ending at 9m.
> **Fix:** Use `range(11)` to include the 10th meter.

### Snippet B: Reversing a List Manually

```python
recent_earthquakes = ["Tofino", "Port Alberni", "Victoria", "Richmond"]
reversed_quakes = []

# Iterate backwards from the last element to the first
for i in range(len(recent_earthquakes), 0, -1):
    reversed_quakes.append(recent_earthquakes[i])
```

> [!success]- Answer 2
> List indices start at 0. `len(recent_earthquakes)` is 4, but the valid indices are 0 to 3. Trying to access `recent_earthquakes[4]` raises an `IndexError`. Also, the loop stops before reaching index 0.
> **Fix:** Use `range(len(recent_earthquakes) - 1, -1, -1)`.

### Snippet C: The First Three

```python
# We want to print exactly the first 3 items in the list
top_cities = ["Vancouver", "Surrey", "Burnaby", "Richmond", "Abbotsford"]
i = 0
while i <= 3:
    print(top_cities[i])
    i += 1
```

> [!success]- Answer 3
> The condition `i <= 3` will run for `i = 0, 1, 2, 3`. This prints 4 cities, not 3.
> **Fix:** Use `i < 3` to print exactly indices 0, 1, and 2.

%%curriculum-start%%
## Curriculum connection

![[K1.6]]

![[K1.15]]
%%curriculum-end%%
