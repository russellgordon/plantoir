---
title: Two-Dimensional Data
publish: true
created: __CREATED__
tags:
  - concepts
---
A list holds a line of things. A great deal of real data is not a line:
a seating chart, a spreadsheet, a chessboard, an image, a distance table
between cities. For those you need a grid, and a grid is a list whose
elements are themselves lists.

## Building and reaching in

```python
grid = [
    [3, 1, 4],
    [1, 5, 9],
    [2, 6, 5],
]

print(grid[1][2])      # 9 — row 1, column 2
grid[0][0] = 7         # top-left becomes 7
```

Row first, then column. That order is a convention, not a law of
nature, and half of all grid bugs are the two indexes swapped. Say it
out loud every time: *row, then column.*

Building an empty grid needs care:

```python
rows = 3
columns = 4
grid = []
for row_number in range(rows):
    row = []
    for column_number in range(columns):
        row.append(0)
    grid.append(row)
```

The long way is the safe way. The tempting short version,
`[[0] * columns] * rows`, produces three references to *the same row* —
change one and all three change. It is the single most common
two-dimensional trap in Python, and it fails silently.

## Processing every element

The pattern is a loop inside a loop, and the outer one is the rows:

```python
total = 0
for row in grid:
    for value in row:
        total = total + value
```

When you need the positions as well as the values, loop over the
indexes instead:

```python
for row_number in range(len(grid)):
    for column_number in range(len(grid[row_number])):
        if grid[row_number][column_number] == 0:
            print(f"empty seat at row {row_number}, column {column_number}")
```

## The four traversals worth knowing

| You need | The shape |
| --- | --- |
| Every element | Loop rows, loop columns |
| One row | `grid[row_number]` — it is just a list |
| One column | Loop the rows, take the same index from each |
| A neighbour | `row ± 1`, `column ± 1` — and check the edges before you look |

That last one is where grids get interesting and where they crash. A
cell on the top row has no neighbour above it, so every neighbour check
needs a bounds test first:

```python
if row_number > 0 and grid[row_number - 1][column_number] == 1:
```

Games of life, flood fills, image blurs, and maze solvers are all the
same shape: visit each cell, look at its neighbours, decide something.

> [!question]- When should a grid be something else?
> When the rows mean different things, use a list of objects rather than
> a grid of numbers — [[Objects and Classes]] exists for exactly that.
> When most cells are empty, a dictionary keyed by `(row, column)` costs
> far less memory than a grid full of zeros, which is a judgement call
> [[Choosing a Data Structure]] walks through.

%%curriculum-start%%
## Curriculum connection

![[A3.5]]

![[A3.1]]
%%curriculum-end%%
