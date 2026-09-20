---
title: Tracing Variable State and Memory
publish: true
created: __CREATED__
tags:
  - exploration
  - tracing
  - memory
  - python
---

When code isn't doing what you expect, the most powerful debugging tool isn't a complex IDE — it's a piece of paper. Tracing code line by line forces you to slow down and act like the computer.

In this exploration, you will trace the state of variables as they change over time.

### Instructions

For each program below, fill out the trace table. Record the value of each variable *after* the corresponding line has finished executing. If a variable hasn't been created yet, write `-`.

### Program A: The Accumulator

```python
# Line numbers for reference
1 | total = 0
2 | limit = 3
3 | i = 1
4 | while i <= limit:
5 |     total = total + i
6 |     i = i + 1
7 | print(total)
```

**Your Trace Table:**

| Line Executed | `total` | `limit` | `i` | Output |
|---------------|---------|---------|-----|--------|
| 1             |         |         |     |        |
| 2             |         |         |     |        |
| 3             |         |         |     |        |
| 5             |         |         |     |        |
| 6             |         |         |     |        |
| ...           |         |         |     |        |

> [!success]- Completed Table A
> | Line Executed | `total` | `limit` | `i` | Output |
> |---------------|---------|---------|-----|--------|
> | 1             | 0       | -       | -   |        |
> | 2             | 0       | 3       | -   |        |
> | 3             | 0       | 3       | 1   |        |
> | 4 (eval True) |         |         |     |        |
> | 5             | 1       | 3       | 1   |        |
> | 6             | 1       | 3       | 2   |        |
> | 4 (eval True) |         |         |     |        |
> | 5             | 3       | 3       | 2   |        |
> | 6             | 3       | 3       | 3   |        |
> | 4 (eval True) |         |         |     |        |
> | 5             | 6       | 3       | 3   |        |
> | 6             | 6       | 3       | 4   |        |
> | 4 (eval False)|         |         |     |        |
> | 7             | 6       | 3       | 4   | 6      |

### Program B: List Mutation

Trace how the list changes in memory.

```python
1 | data = [10, 20]
2 | data.append(30)
3 | copy = data
4 | copy[0] = 99
5 | print(data[0])
```

> [!success]- Completed Table B
> | Line Executed | `data` (memory contents) | `copy` (memory contents) | Output |
> |---------------|--------------------------|--------------------------|--------|
> | 1             | `[10, 20]`               | -                        |        |
> | 2             | `[10, 20, 30]`           | -                        |        |
> | 3             | `[10, 20, 30]`           | Points to `data`         |        |
> | 4             | `[99, 20, 30]`           | Points to `data`         |        |
> | 5             | `[99, 20, 30]`           | Points to `data`         | 99     |
> 
> *Notice that changing `copy[0]` mutated the original `data` list because they are aliases pointing to the same memory address!*

%%curriculum-start%%
## Curriculum connection

![[K1.15]]
%%curriculum-end%%
