---
title: Starting from a Skeleton
publish: true
created: __CREATED__
tags:
  - tutorials
---
A blank file is the hardest part of a lot of programs. A **skeleton**
removes it: a file that already has the shape of the solution, with the
thinking left for you to do.

## What a skeleton looks like

```python
"""Ticket pricing — Unit 1.

Reads the customer's age, decides the price, prints it.
"""

# --- Input ---------------------------------------------------------
age = 0          # TODO: ask the customer's age and convert it

# --- Process -------------------------------------------------------
price = 0.0      # TODO: choose the price from the age

# --- Output --------------------------------------------------------
print()          # TODO: print the price, to two decimals
```

Nothing there solves the problem. What it gives you is the
input–process–output shape from [[Decomposition and Design]], the names
worth using, and three places to stand. You fill the `TODO` lines in
order and run it after each one — a program that runs at every step is
a program whose failures stay small.

## Where skeletons come from

- **Given to you.** Several tasks in this course start from one.
- **The language's own documentation.** The examples in Python's docs
  are skeletons: a working shape you adapt rather than copy blindly.
- **Your editor's snippets.** Type `for` and take the offered
  structure, then rename its variables to mean something.
- **Your own previous work.** By the end of the course you will have a file that
  reads a data file, loops over it, and prints a summary. That file is
  your best skeleton, because you already understand every line of it.

## Using one honestly

1. Read the whole thing before typing. A skeleton you have not read is
   a maze.
2. Rename the placeholders to your problem's words. `value` and
   `result` are what the author called them because they did not know
   your problem.
3. Delete what you do not need. An unused section is a lie about your
   program.
4. Run it after each `TODO` you close.
5. Be able to explain every line that remains. This is the line between
   using a skeleton and copying an answer — and it is the line
   [[Our Classroom Norms]] holds you to.

> [!tip] Make your own, deliberately
> When you finish a program you are pleased with, save a copy with the
> specifics stripped out and the structure left behind. That file, in a
> folder called `Skeletons`, will save you a whole period in Unit 4.

%%curriculum-start%%
## Curriculum connection

![[B2.1]]

![[C3.2]]
%%curriculum-end%%
