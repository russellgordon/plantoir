---
title: Spot the Bug
publish: true
created: __CREATED__
tags:
  - warm-ups
---
One short program on the board and a promise: it contains exactly one
bug. Find it by *reading*. No running, no changing things at random.
The Grade 11 version of this drill used programs written for the
drill. This year's are the two faults that actually ruin real
software: the **off-by-one**, where a boundary is wrong by exactly
one step, and the **alias**, where two names turn out to point at one
object.

## How to run it

1. Read the whole program before judging any line. Bugs love the line
   you skimmed.
2. Decide which kind of bug it is: does it crash, or does it run
   happily and quietly return the wrong answer?
3. Name the line, name the fault, and — if it crashes — predict the
   exact message and which frame it will name.
4. Only then run it, and read the real output against your
   prediction.

> [!warning] The second kind is the dangerous kind
> A crash tells you something is wrong. A program that runs and lies
> to you does not, and somebody will act on its answer. Every bug
> that ever reached a real user got past somebody who was only
> checking that the program ran.

## The loud one

```python
def binary_search(values, target):
    low = 0
    high = len(values)
    while low <= high:
        middle = (low + high) // 2
        if values[middle] == target:
            return middle
        elif values[middle] < target:
            low = middle + 1
        else:
            high = middle - 1
    return -1


marks = [52, 61, 74, 80, 95]
print(binary_search(marks, 74))
print(binary_search(marks, 99))
```

It prints `2` and then dies:

```text
Traceback (most recent call last):
  File "/home/student/search.py", line 17, in <module>
    print(binary_search(marks, 99))
          ^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/student/search.py", line 6, in binary_search
    if values[middle] == target:
       ~~~~~~^^^^^^^^
IndexError: list index out of range
```

Line 3 is the fault. `high = len(values)` sets the upper bound to 5
on a list whose last valid position is 4, so a target larger than
everything in the list eventually walks `middle` onto position 5. The
fix is one character of arithmetic: `high = len(values) - 1`.[^bloch]

Notice what the search for 74 did — it worked. An off-by-one is
usually invisible on the inputs you happen to try first, which is
exactly why [[Testing and Regression]] insists on testing the ends of
the range and not the middle.

## The quiet one

```python
class Student:
    def __init__(self, name, marks=[]):
        self.name = name
        self.marks = marks


first = Student("Nadia")
second = Student("Ali")
first.marks.append(88)
print(second.marks)
```

This prints `[88]`. Ali now has Nadia's mark, and nothing crashed,
and nothing warned anybody. The default value `[]` is created **once**
when Python reads the `def` line, so every `Student` made without an
explicit list shares that one list forever. Write
`def __init__(self, name, marks=None)` and build a fresh list inside
the method when `marks` is `None`.

## One variation

Show the traceback with no program at all and work backwards: what
must the code have looked like to produce this? That is the detective
work of [[Name That Error]] run in reverse, and it is the fastest way
to build the habit that [[Reading a Traceback in Someone Else's Code]]
turns into a method.

%%curriculum-start%%
## Curriculum connection

![[A2.3]]

![[A4.1]]
%%curriculum-end%%

[^bloch]: The same off-by-one has a famous relative. For decades, a
    standard binary search in several major languages computed the
    midpoint as `(low + high) / 2`, which overflows when the two
    numbers are large enough — a bug that sat in widely used library
    code for around twenty years before anyone published it. Python's
    integers grow as large as they need to, so that particular version
    cannot bite you here. The lesson survives the language: boundary
    arithmetic is where careful people still get caught.
