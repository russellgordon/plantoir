---
title: Predict the Output
publish: true
codeRunner: true
created: __CREATED__
tags:
  - warm-ups
---
A short Python program goes on the board. Before anyone touches a
keyboard, you commit to a prediction — the exact output, in ink. Then
we run it. Being wrong costs nothing; refusing to commit costs
everything, because the gap between what you predicted and what Python
did is the only place today's learning can happen.

## How to run it

1. Read the program twice, silently. No talking yet.
2. Write the exact output you expect, character for character —
   including spacing, quotation marks, and how many lines.
3. Compare with a neighbour. The code settles disputes, not volume.
4. Run it. Surprised? The line that fooled you is today's lesson.

> [!example]- Two lines, three defensible readings
> ```python run
> mark = "84"
> print(mark * 2)
> ```
> `168` — eighty-four doubled. `8484` — the quotation marks make
> `mark` text, and multiplying text repeats it. A crash — surely you
> cannot multiply words. Only one of those is what Python does, and
> the quotation marks decide it. Python prints `8484`.

## One variation

Reverse it. Show only the output and let pairs write a program that
would produce it. There is never one right answer, which is the point:
several different programs can wear the same face.

> [!tip] Commit before you run
> A prediction you never wrote down cannot surprise you, and code that
> never surprises you never teaches you anything. This is the same
> habit [[Testing and Debugging]] later calls "expected versus
> actual" — the whole of debugging in three words.
