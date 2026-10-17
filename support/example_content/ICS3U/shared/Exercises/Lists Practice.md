---
title: Lists Practice
publish: true
codeRunner: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Lists]]. Every one of them uses the same
starting list, so keep it in a file and edit as you go:

```python
marks = [78, 91, 46, 63]
```

## Positions and bounds

1. What does each print? `marks[0]`, `marks[3]`, `marks[-1]`,
   `len(marks)`.
2. What happens when you run `print(marks[4])`, and why is `4` a
   reasonable-looking mistake?
3. Starting from the original list each time, give the list after
   `marks.append(70)`, then after `marks.insert(1, 55)`, then after
   `marks.remove(46)` — applied one after the other.

## Loops over lists

4. Write the loop that totals the marks and prints the average to one
   decimal place.
5. Write a linear search that reports the position of
   `"Fifteen Dogs"` in
   `titles = ["Birdie", "Fifteen Dogs", "Indian Horse"]`, and prints
   `-1` when the title is not there.
6. Count how many of `weights = [6.5, 3.0, 11.2, 7.0]` are above
   `6.0`.
7. Find the largest value in `weights` without using `max()`.
8. **Challenge.** Build a *new* list holding only the passing marks
   (50 or more) from `marks`, then print how many there are and what
   they are.

## Answers

> [!success]- Answer 1
> `78`, `63`, `63`, `4`. Positions run 0 to 3, so `marks[3]` and
> `marks[-1]` are the same element reached from opposite ends, and
> `len` counts elements rather than naming the last position.

> [!success]- Answer 2
> ```
> IndexError: list index out of range
> ```
> Four elements, positions 0 to 3. `4` looks right because the list has
> four marks in it — but counting from zero means the last position is
> always `len` minus one.

> [!success]- Answer 3
> `[78, 91, 46, 63, 70]`, then `[78, 55, 91, 46, 63, 70]`, then
> `[78, 55, 91, 63, 70]`. `append` adds to the end, `insert` puts the
> value at the position given and shifts everything after it along, and
> `remove` deletes the first matching *value* — not a position.

> [!success]- Answer 4
> ```python
> total = 0
> for mark in marks:
>     total = total + mark
> print(f"Average: {total / len(marks):.1f}")
> ```
> For the original four marks that prints `Average: 69.5`. Dividing by
> `len(marks)` rather than by `4` means the code still works when the
> list changes, which it always does.

> [!success]- Answer 5
> ```python run
> titles = ["Birdie", "Fifteen Dogs", "Indian Horse"]
> target = "Fifteen Dogs"
> position = -1
>
> for index in range(len(titles)):
>     if titles[index] == target:
>         position = index
>
> print(position)
> ```
> This prints `1`. Looping over `range(len(titles))` gives you
> positions rather than values, which is what a search has to report.
> Starting at `-1` is the convention for "not found", so the answer is
> still meaningful when nothing matches.

> [!success]- Answer 6
> ```python run
> weights = [6.5, 3.0, 11.2, 7.0]
> above = 0
> for weight in weights:
>     if weight > 6.0:
>         above = above + 1
> print(above)
> ```
> `3`. A counter is an accumulator that grows by one instead of by the
> value — same skeleton, different update.

> [!success]- Answer 7
> ```python
> highest = weights[0]
> for weight in weights:
>     if weight > highest:
>         highest = weight
> print(highest)
> ```
> `11.2`. Starting from `weights[0]` rather than from `0` is the part
> that matters: a list of negative numbers would defeat a starting
> value of zero, and the program would report a maximum that is not in
> the list.

> [!success]- Answer 8
> ```python
> passing = []
> for mark in marks:
>     if mark >= 50:
>         passing.append(mark)
> print(f"{len(passing)} passing: {passing}")
> ```
> ```
> 3 passing: [78, 91, 63]
> ```
> Building a second list leaves the original untouched, which is
> usually what you want — the caller may still need the full set, and a
> function that quietly destroys its input is a hard bug to find later.
