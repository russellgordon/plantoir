---
title: Sorting Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Sorting]]. Use this list of lap times in
seconds throughout, and do the first two questions on paper before
touching a keyboard:

```python
times = [64, 25, 12, 22, 11]
```

## By hand

1. Write out the list after **each comparison** of the first pass of a
   bubble sort. Where does the largest value end up, and why is that
   guaranteed?
2. Write out the list after each **pass** of an insertion sort. Which
   pass does the most work, and why?
3. **Find the fault.** This bubble sort crashes. Say exactly why, name
   the error, and give the two corrections it needs.
   ```python
   def bubble_sort(values):
       for pass_number in range(len(values)):
           for position in range(len(values)):
               if values[position] > values[position + 1]:
                   values[position], values[position + 1] = (
                       values[position + 1], values[position])
       return values
   ```

## In code

4. Write `insertion_sort(values)`. Test it on the lap times, on an
   empty list, and on a list of one item.
5. Write `selection_sort(values)`. Say what it does that insertion
   sort does not, and which of the two you would rather run on
   nearly-sorted data.
6. Sort `["Rowan", "bea", "Ali", "nadia", "Sam"]` with your insertion
   sort. Explain the result, then make it sort the way a person would
   expect.
7. Sort a list of `Volunteer` objects (each with `name` and `hours`)
   by hours, fewest first, by changing exactly one line of your
   insertion sort.
8. **Stability.** Sort
   `[("Rowan", 2), ("Nadia", 1), ("Bea", 2), ("Ali", 1)]` by the
   second value using `>` in the comparison, then again using `>=`.
   Report both results and say which one you would hand to a coach
   who reads ties as arrival order.
9. **Counting.** Count the comparisons your insertion sort makes on
   sorted, shuffled, and reversed lists of 100, 200, and 400 items.
   What happens to each column when the size doubles?

## Answers

> [!success]- Answer 1
> ```text
> compare 0,1: [25, 64, 12, 22, 11]
> compare 1,2: [25, 12, 64, 22, 11]
> compare 2,3: [25, 12, 22, 64, 11]
> compare 3,4: [25, 12, 22, 11, 64]
> ```
> The largest value, 64, ends up at the end — guaranteed, because
> once the pass reaches it, every remaining comparison finds it larger
> and keeps swapping it along. That is why a bubble sort can shorten
> each pass by one: after $k$ passes, the last $k$ items are already
> in their final places.

> [!success]- Answer 2
> ```text
> pass 1: [25, 64, 12, 22, 11]
> pass 2: [12, 25, 64, 22, 11]
> pass 3: [12, 22, 25, 64, 11]
> pass 4: [11, 12, 22, 25, 64]
> ```
> Pass 4 does the most work: 11 is smaller than everything already
> placed, so it slides past all four items. Insertion sort's cost
> depends on how far each item has to travel — which is why a
> nearly-sorted list is nearly free and a reversed list is the worst
> case.

> [!success]- Answer 3
> The inner loop runs to `len(values) - 1`, so `values[position + 1]`
> reads one past the end:
> ```text
> IndexError: list index out of range
> ```
> Two corrections: the inner range must be
> `range(len(values) - 1 - pass_number)` — the `-1` stops the overrun
> and the `- pass_number` skips the tail that is already sorted — and
> the outer range only needs `len(values) - 1` passes, because when
> every other item is placed the last one has nowhere else to be.

> [!success]- Answer 4
> ```python
> def insertion_sort(values):
>     """Sort a list in place, smallest first, and return it."""
>     for position in range(1, len(values)):
>         held = values[position]
>         gap = position - 1
>         while gap >= 0 and values[gap] > held:
>             values[gap + 1] = values[gap]
>             gap = gap - 1
>         values[gap + 1] = held
>     return values
>
>
> print(insertion_sort([64, 25, 12, 22, 11]))
> print(insertion_sort([]))
> print(insertion_sort([7]))
> ```
> ```text
> [11, 12, 22, 25, 64]
> []
> [7]
> ```
> The empty list and the single item work without any special case,
> because `range(1, 0)` and `range(1, 1)` are both empty. Those two
> tests take four seconds to write and catch the most common class of
> boundary bug there is.

> [!success]- Answer 5
> ```python
> def selection_sort(values):
>     """Sort a list in place by repeatedly finding the smallest item left."""
>     for start in range(len(values)):
>         smallest = start
>         for position in range(start + 1, len(values)):
>             if values[position] < values[smallest]:
>                 smallest = position
>         values[start], values[smallest] = values[smallest], values[start]
>     return values
>
>
> print(selection_sort([64, 25, 12, 22, 11]))
> ```
> ```text
> [11, 12, 22, 25, 64]
> ```
> Selection sort makes far fewer *swaps* — at most one per position —
> which mattered enormously when writing to storage was expensive. But
> it must scan every remaining item to find the smallest, so its
> comparison count is identical whatever the data. On nearly-sorted
> data insertion sort wins easily; that is the difference two
> algorithms with the same $O(n^2)$ can still have.

> [!success]- Answer 6
> ```text
> ['Ali', 'Rowan', 'Sam', 'bea', 'nadia']
> ```
> Every capital letter sorts before every lowercase one, because `>`
> on strings compares character codes. Nothing is broken — that is
> what "less than" means for text. To sort the way a person expects,
> change the comparison, not the algorithm:
> ```python
> while gap >= 0 and values[gap].lower() > held.lower():
> ```
> ```text
> ['Ali', 'bea', 'nadia', 'Rowan', 'Sam']
> ```
> Real name sorting is harder still — accents, prefixes such as "de",
> and names that do not split into first and last. Knowing that your
> simple rule is a simplification is the professional part.

> [!success]- Answer 7
> ```python
>         while gap >= 0 and volunteers[gap].hours > held.hours:
> ```
> ```text
> Rowan (1.5 h)
> Bea (2 h)
> Nadia (4.5 h)
> Ali (6 h)
> ```
> One line, because the algorithm never cared what the items were —
> only how to compare two of them. That is the same reusability that
> lets a `Queue` hold names one day and objects the next.

> [!success]- Answer 8
> ```text
> with >   [('Nadia', 1), ('Ali', 1), ('Rowan', 2), ('Bea', 2)]
> with >=  [('Ali', 1), ('Nadia', 1), ('Bea', 2), ('Rowan', 2)]
> ```
> The `>` version is **stable**: Nadia signed in before Ali and still
> comes first. The `>=` version reverses every tie, because equal
> items keep sliding past one another. Hand the coach the stable one —
> and notice that nothing about the sorted-ness differs between them.
> The difference is only visible if you know what the ties meant to a
> person.

> [!success]- Answer 9
> ```text
>  items    sorted   shuffled   reversed
>    100        99       2988       4950
>    200       199       9446      19900
>    400       399      39817      79800
> ```
> The sorted column **doubles** — one comparison per item, $O(n)$, the
> best case. The shuffled and reversed columns **quadruple**, which is
> the $O(n^2)$ signature: reversed is exactly $n(n-1)/2$, and shuffled
> lands at about half of that. Your shuffled numbers will differ
> slightly because the shuffle differs; the quadrupling will not.

%%curriculum-start%%
## Curriculum connection

![[A1.3]]

![[A3.4]]

![[C2.1]]

![[C2.3]]
%%curriculum-end%%

