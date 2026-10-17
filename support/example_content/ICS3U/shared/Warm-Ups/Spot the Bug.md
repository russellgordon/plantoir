---
title: Spot the Bug
publish: true
codeRunner: true
created: __CREATED__
tags:
  - warm-ups
---
One short program on the board and a promise: it contains exactly one
bug. Your job is to find it by *reading* first — before you run
anything, and without changing things at random to see what happens.
Programs fail in a small number of predictable ways, and learning to
see those ways cold is what turns a panicky hour into the calm routine
of [[Getting Unstuck]].

## How to run it

1. Read the whole program before judging any line. Bugs love the line
   you skimmed.
2. Decide which kind of bug it is: does it crash, or does it run
   happily and quietly do the wrong thing?
3. Name the line, name the fault, and — if it crashes — predict the
   exact message.
4. Only then run it, and read the real output against your prediction.

> [!warning] The second kind is the dangerous kind
> A crash tells you something is wrong. A program that runs and lies
> to you does not, and somebody may act on its answer. Most of the
> bugs that reach real users are of the quiet sort.

## Try this one

```python run
names = ["Ali", "Bea", "Cy"]
for index in range(1, len(names)):
    print(names[index])
```

It never crashes. It prints two names and swallows the first one,
because `range(1, 3)` starts counting at 1 while [[Lists|list]]
positions start at 0. Nobody would notice on a list of three. On a
class list of thirty, one person is simply missing — the kind of
failure [[Who Is This For]] takes personally.

Fix it in the program above and press **Run**: all three names should
appear. **Reset** brings the bug back.

## One variation

Show a traceback with no program at all and work backwards: what must
the code have looked like to produce this message? That is the same
detective work as [[Name That Error]], run in reverse.
