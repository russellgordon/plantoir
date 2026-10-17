---
title: Check Your Loops
publish: true
tags:
  - exercises
---
Four quick questions on [[Repetition]]. Answer each one, press **Check**,
and read why. Your score is at the bottom of the page; press **Start
again** there and see whether you can get every one right first time.

## Questions

> [!quiz] What does this program print?
> ```python
> for count in range(3):
>     print(count)
> ```
> - [ ] 1, 2 and 3, one to a line
> - [x] 0, 1 and 2, one to a line
> - [ ] 0, 1, 2 and 3, one to a line
> - [ ] Nothing: `range(3)` is empty
>
> > [!explain]- Why
> > `range(3)` starts at 0 and stops *before* 3, so the loop runs three
> > times, with `count` set to 0, then 1, then 2.

> [!quiz] Which of these loops run exactly five times?
> - [x] `for i in range(5):`
> - [x] `for i in range(1, 6):`
> - [ ] `for i in range(0, 5, 2):`
> - [ ] `for i in range(5, 0):`
>
> > [!explain]- Why
> > `range(1, 6)` counts 1 to 5. Counting by twos from 0 gives 0, 2 and 4,
> > and `range(5, 0)` is empty: it would need a negative step to count down.

> [!quiz] In `range(10, 0, step)`, the step that counts down by twos is `____`.
> > [!answer]-
> > -2

> [!quiz] How many times does `for letter in "loop":` run its block?
> > [!answer]-
> > 4 | four
