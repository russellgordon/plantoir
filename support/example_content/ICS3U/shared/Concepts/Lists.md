---
title: Lists
publish: true
codeRunner: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
In [[The Data Pile]] the numbers arrived on paper: a month of recycling
weights, and a request for one sentence about them. Every group started
with `day1 = `, `day2 = `, `day3 = `, and every group gave up. Twenty
variables cannot be looped over, cannot be counted, and cannot be
totalled without twenty lines of arithmetic. Data that arrives together
should live together.

## Many values, one name

```python
minutes = [45, 0, 60, 30, 0, 90, 25]
```

That is one variable holding seven values in a definite order. In the
curriculum's vocabulary it is a one-dimensional array; in Python it is
a `list`. The values inside are its **elements**, and the position of
each one is its **index**.

## Positions start at zero

```python
print(minutes[0])    # 45 — the first element
print(minutes[6])    # 25 — the seventh and last
print(minutes[-1])   # 25 — the last, counted backwards
print(len(minutes))  # 7 — how many elements there are
```

The **bounds** of this list are 0 and 6. Ask for anything outside them
and Python stops:

```
IndexError: list index out of range
```

`minutes[7]` is the classic version of that error, because seven
elements feels like it should end at seven. It ends at six. Say
"`len` minus one" out loud a few times and it stops catching you.

## Growing and changing a list

Lists are not fixed once created — which is the main thing that makes
them worth using.

```python
minutes[1] = 20        # replace the element at position 1
minutes.append(15)     # add a new element to the end
```

```python run readonly
sorted_marks = [46, 63, 78, 91]
sorted_marks.insert(2, 70)   # put 70 at position 2, shifting the rest
sorted_marks.remove(63)      # delete the first 63 found
print(sorted_marks)
```

```
[46, 70, 78, 91]
```

`insert` into a sorted list and `remove` from the middle are two of the
small algorithms the course expects you to be able to design and
explain — including the awkward cases. What should `remove` do when the
value is not there? (It raises `ValueError`.) Where does a new value go
when it ties with one already in the list? Decide on purpose, and write
the decision down.

## Walking the list to find something

Two ways to loop, and the difference matters:

```python
for value in minutes:      # gives you each element
    print(value)

for index in range(len(minutes)):   # gives you each position
    print(f"Day {index + 1}: {minutes[index]} minutes")
```

Use the first when you only care about the values. Use the second when
you need to know *where* you are — which is exactly what a search
needs:

```python run readonly
marks = [78, 91, 46, 63]
target = 46
position = -1

for index in range(len(marks)):
    if marks[index] == target:
        position = index

print(position)
```

```
2
```

That is a **linear search**: check every element, remember where the
match was. Starting `position` at `-1` is a convention meaning "not
found yet", so the answer is still meaningful when nothing matches.

> [!example]- A hand trace of the "highest so far" pattern
> ```python
> highest = minutes[0]
> for value in minutes:
>     if value > highest:
>         highest = value
> ```
> With `minutes = [45, 0, 60, 30, 0, 90, 25]`:
>
> | Pass | `value` | Is it bigger? | `highest` after |
> | --- | --- | --- | --- |
> | start | — | — | 45 |
> | 1 | 45 | no | 45 |
> | 2 | 0 | no | 45 |
> | 3 | 60 | yes | 60 |
> | 4 | 30 | no | 60 |
> | 5 | 0 | no | 60 |
> | 6 | 90 | yes | 90 |
> | 7 | 25 | no | 90 |
>
> Starting from `minutes[0]` rather than from `0` matters: a list of
> negative numbers would beat a starting value of zero every time and
> report `0` as the highest — a bug that only shows up on data you did
> not test with.

Practise all of it in [[Lists Practice]], then read a complete program
that turns a list of marks into something a teacher can act on in
[[Working with Lists]].

%%curriculum-start%%
## Curriculum connection

![[A1.5]]

![[A1.6]]

![[A2.3]]

![[B3.1]]
%%curriculum-end%%
