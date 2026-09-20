---
title: Searching Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Searching]]. Use this sorted list of
community centre card numbers throughout, and count comparisons by
hand before you count them in code:

```python
cards = [102, 118, 134, 155, 167, 189, 203, 221, 240]
```

## By hand

1. Trace a binary search for `203`. Write down `low`, `high`,
   `middle`, and the value examined at each step, and say how many
   comparisons it took.
2. Trace a binary search for `130`, which is not there. How does the
   loop end, and how many comparisons were made?
3. A linear search for `240` in this list takes how many comparisons?
   For `102`? For a number that is absent? Which of the three is the
   worst case, and does the same answer hold for binary search?

## In code

4. Write `linear_search(values, target)` returning the index or `-1`,
   with a docstring that states its precondition.
5. Write `binary_search(values, target)` with the same signature.
   State the precondition in the docstring, and explain in one
   sentence why `low <= high` and `middle + 1` matter.
6. **Find the fault.** This binary search never terminates for some
   inputs. Why?
   ```python
   while low <= high:
       middle = (low + high) // 2
       if values[middle] == target:
           return middle
       elif values[middle] < target:
           low = middle
       else:
           high = middle
   ```
7. Write `find_by_card(members, card)` that searches a list of
   `Member` objects (each with `name` and `card`) and returns the
   object or `None`. Why does this one have to be a linear search, as
   written?
8. Write `all_positions(values, target)`, returning **every** index
   where the target appears. Test it on `[2, 5, 2, 9, 2]`.
9. **Judgement.** Run `binary_search` on the same numbers shuffled
   into arrival order and search for `240`. Report what happens, and
   write the sentence you would put in a code review.

## Answers

> [!success]- Answer 1
> ```text
> step 1: low=0 high=8 middle=4 value=167
> step 2: low=5 high=8 middle=6 value=203
> ```
> Two comparisons. 167 is smaller than 203, so the whole left half —
> five of the nine cards — is discarded in one step, and `low` becomes
> `middle + 1`. The second look lands on it exactly. Nine cards, at
> most four comparisons, because $2^4 > 9$.

> [!success]- Answer 2
> ```text
> step 1: low=0 high=8 middle=4 value=167
> step 2: low=0 high=3 middle=1 value=118
> step 3: low=2 high=3 middle=2 value=134
> ```
> Three comparisons, then `high` becomes `1` while `low` is `2`, so
> `low <= high` is false and the loop ends with `-1`. The region to
> search became empty, which is how binary search proves a value is
> absent — without ever looking at most of the list.

> [!success]- Answer 3
> Linear search takes nine comparisons for `240` (the last item), one
> for `102` (the first), and nine for anything absent. The worst case
> is "absent, or last" — both force a look at every item.
>
> For binary search the pattern is different: the worst case is about
> $\log_2 9 \approx 3.2$, so four comparisons, whether the value is
> present or absent. Being first or last in the list makes almost no
> difference. That is what "the shape of the growth is different"
> means in practice.

> [!success]- Answer 4
> ```python
> def linear_search(values, target):
>     """Return the index of target in values, or -1 if it is absent.
>
>     Precondition: none. Any list at all will do.
>     """
>     for index in range(len(values)):
>         if values[index] == target:
>             return index
>     return -1
>
>
> print(linear_search(cards, 102), linear_search(cards, 240),
>       linear_search(cards, 1))
> ```
> ```text
> 0 8 -1
> ```
> "Precondition: none" is worth writing down. It is the reason this
> function is still the right answer for unsorted data.

> [!success]- Answer 5
> ```python
> def binary_search(values, target):
>     """Return the index of target in values, or -1 if it is absent.
>
>     Precondition: values is sorted in ascending order. On an unsorted
>     list this function returns wrong answers instead of crashing.
>     """
>     low = 0
>     high = len(values) - 1
>     while low <= high:
>         middle = (low + high) // 2
>         if values[middle] == target:
>             return middle
>         elif values[middle] < target:
>             low = middle + 1
>         else:
>             high = middle - 1
>     return -1
> ```
> ```text
> 0 8 -1
> ```
> `low <= high` rather than `<` because a region of exactly one item
> still has to be examined — with the strict version, items at the
> edges are never found. `middle + 1` and `middle - 1` because the
> middle has just been compared and must leave the region; leaving it
> in is how the loop in question 6 gets stuck.

> [!success]- Answer 6
> When the region shrinks to two items, `middle` is the lower of them.
> If the target is the upper one, `low = middle` leaves `low` and
> `high` exactly where they were, and the loop repeats the same
> comparison for ever. The program does not crash; it hangs, which is
> harder to diagnose. `low = middle + 1` and `high = middle - 1`
> guarantee the region gets strictly smaller every pass, which is the
> loop's version of a base case.

> [!success]- Answer 7
> ```python
> def find_by_card(members, card):
>     """Return the Member with this card number, or None if absent."""
>     for member in members:
>         if member.card == card:
>             return member
>     return None
>
>
> print(find_by_card(members, 118))
> print(find_by_card(members, 999))
> ```
> ```text
> Rowan (118)
> None
> ```
> It must be linear because nothing guarantees the list is sorted by
> card number — members are added in joining order. To binary search
> it you would first have to sort by `card` and keep it sorted on
> every insertion, which is a real cost. If lookups by card are
> frequent, the better answer is a dictionary from card number to
> member, as [[Choosing a Data Structure]] argues.

> [!success]- Answer 8
> ```python
> def all_positions(values, target):
>     """Return every index where target appears."""
>     found = []
>     for index in range(len(values)):
>         if values[index] == target:
>             found.append(index)
>     return found
>
>
> print(all_positions([2, 5, 2, 9, 2], 2))
> ```
> ```text
> [0, 2, 4]
> ```
> Note that this cannot return early: proving there are no more
> matches requires looking at everything, so it is $O(n)$ even in the
> best case. Binary search cannot help here either — it finds *a*
> match, with no promise about which.

> [!success]- Answer 9
> ```python
> shuffled = [155, 102, 240, 118, 203, 134, 189, 167, 221]
> print(binary_search(shuffled, 240), linear_search(shuffled, 240))
> ```
> ```text
> -1 2
> ```
> The card is at index 2. Binary search reports that it does not
> exist — no exception, no warning, just a wrong answer delivered
> quickly. A review comment that would have caught it:
>
> *"`binary_search` requires a sorted list, and `shuffled` is in
> arrival order, so this returns -1 for members who are registered.
> Either sort the list where it is built and say so in the docstring,
> or use `linear_search` here. Please add a test with an unsorted
> list."*
>
> Naming the condition, the consequence, and the smallest fix is what
> [[Read the Diff]] is practice for.

%%curriculum-start%%
## Curriculum connection

![[A1.1]]

![[A3.2]]

![[C2.1]]

![[C2.2]]
%%curriculum-end%%

