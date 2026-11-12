---
title: Sorting
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
In [[Sorting by Hand]] nobody was allowed a computer. Groups were
handed a shuffled stack of lap-time cards and told to put them in
order, then to write down what their hands had actually done. Three
methods came back, in different words: keep swapping neighbours that
are out of order; find the smallest and move it to the front; pick up
the next card and slide it back into the sorted part.

Those are bubble, selection, and insertion sort. You did not need to
be taught them. What you do need is to write them precisely, count
what they cost, and know when to stop using them.

## Three sorts your hands already knew

```python
def bubble_sort(values):
    """Sort a list in place by repeatedly swapping neighbours."""
    for pass_number in range(len(values) - 1):
        swapped = False
        for position in range(len(values) - 1 - pass_number):
            if values[position] > values[position + 1]:
                values[position], values[position + 1] = (
                    values[position + 1], values[position])
                swapped = True
        if not swapped:
            return values
    return values
```

```python
def selection_sort(values):
    """Sort a list in place by repeatedly finding the smallest item left."""
    for start in range(len(values)):
        smallest = start
        for position in range(start + 1, len(values)):
            if values[position] < values[smallest]:
                smallest = position
        values[start], values[smallest] = values[smallest], values[start]
    return values
```

Insertion sort — the third one, and the one most hands invent — is
written out and measured in [[Sorting and Timing It]].

All three are $O(n^2)$: a loop inside a loop, each item compared with
many others, so doubling the data roughly quadruples the work. They
differ in ways worth knowing:

| Sort | Best case | Worst case | Comparisons on sorted data |
| --- | --- | --- | --- |
| Bubble (with the `swapped` flag) | $O(n)$ | $O(n^2)$ | One pass, then it stops |
| Selection | $O(n^2)$ | $O(n^2)$ | The same every time |
| Insertion | $O(n)$ | $O(n^2)$ | One comparison per item |

The `swapped` flag is the whole difference between a bubble sort that
notices the data was already in order and one that grinds through
every pass regardless. Selection sort cannot be rescued that way: it
must scan the remaining items to know which is smallest, whatever
order they are in. Two algorithms with the same Big-O can still be
very different to live with — which is the honest footnote that
[[Efficiency and Big-O]] adds to its own notation.

## Merge sort: divide the problem, not the data

> [!note]- The one that is not $O(n^2)$
> ```python
> def merge_sort(values):
>     """Return a new sorted list, by sorting two halves and merging them."""
>     if len(values) <= 1:
>         return values
>     middle = len(values) // 2
>     left = merge_sort(values[:middle])
>     right = merge_sort(values[middle:])
>     return merge(left, right)
>
>
> def merge(left, right):
>     """Merge two sorted lists into one sorted list."""
>     merged = []
>     left_index = 0
>     right_index = 0
>     while left_index < len(left) and right_index < len(right):
>         if left[left_index] <= right[right_index]:
>             merged.append(left[left_index])
>             left_index = left_index + 1
>         else:
>             merged.append(right[right_index])
>             right_index = right_index + 1
>     while left_index < len(left):
>         merged.append(left[left_index])
>         left_index = left_index + 1
>     while right_index < len(right):
>         merged.append(right[right_index])
>         right_index = right_index + 1
>     return merged
> ```
> The base case is a list of one item, which is already sorted. Above
> it, every call splits the work in half and merges two sorted halves
> in one pass. That is $\log_2 n$ levels of splitting, each costing
> about $n$ work to merge — $O(n \log n)$, and it is why sorting a
> million records is possible at all. It is also
> [[A3.6|the recursion expectation]]'s own example, and the clearest
> case in the course of a recursive algorithm being genuinely better
> rather than merely clever.

At 4 000 shuffled items, insertion sort makes about four million
comparisons. Merge sort, counted on the same list, makes 42 817. That
gap is not a constant factor you can optimise away — it is a different
shape.

## What you sort by, and what stays put

Sorting is never really about numbers. It is about a rule for deciding
which of two records comes first, and Python will compare whatever you
give it: `>` on strings compares character codes, which is why
`'bea'` sorts after `'Sam'` — every capital letter comes before every
lowercase one. That is
[[A1.3|the non-numeric comparison expectation]] in one surprising
line, and the fix belongs in your comparison, not in the algorithm.

When two records tie, does their original order survive? A sort that
promises it does is **stable**. Sorting the sign-in sheet by hours
with insertion sort's `>` comparison:

```text wrap
[('Rowan', 2), ('Nadia', 1), ('Bea', 2), ('Ali', 1)]
->  [('Nadia', 1), ('Ali', 1), ('Rowan', 2), ('Bea', 2)]
```

Nadia signed in before Ali, and still comes first. Change that one
comparison to `>=` and the same data comes out
`[('Ali', 1), ('Nadia', 1), ('Bea', 2), ('Rowan', 2)]` — every tie
reversed. Nothing is "wrong" with either version, but only one of them
can be handed to a coach who reads ties as arrival order. Stability is
a promise you make to a person.

## Use the built-in sort

Python's `list.sort()` and `sorted()` are a carefully engineered,
stable, $O(n \log n)$ merge-sort variant, written and tested by many
people over many years. **In real work, you call it.** Nobody
hand-writes a sort in production, and a code review that finds one
will ask why.

You wrote three by hand so that you can recognise the shape of a slow
program, defend a choice with counted comparisons, and read the sort
in somebody else's inherited code without flinching. That is the
skill; the sorting is the exercise.

Measure them yourself in [[Sorting and Timing It]], practise the
mechanics in [[Sorting Practice]], and put the vocabulary on it in
[[Efficiency and Big-O]].

%%curriculum-start%%
## Curriculum connection

![[A3.4]]

![[C2.3]]

![[A1.3]]
%%curriculum-end%%
