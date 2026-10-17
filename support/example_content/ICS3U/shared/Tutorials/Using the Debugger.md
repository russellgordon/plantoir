---
title: Using the Debugger
publish: true
codeRunner: true
created: __CREATED__
tags:
  - tutorials
enableToc: true
---
A program that crashes tells you where it stopped. A program that runs
and returns the wrong answer tells you nothing at all — and that is
the situation a debugger is built for. A debugger runs your program
slowly, in front of you, and lets you look at the values as they
change.

## Start with print, honestly

Adding `print()` calls is the oldest debugging tool there is, and
professionals still use it daily. It costs nothing and it works
everywhere. Here is a program that runs perfectly and gives the wrong
answer:

```python run
total = 0
for score in [8, 9, 10]:
    total = score
print(f"Total: {total}")
```

It prints `Total: 10`. You expected 27. Put one `print(total)` inside
the loop and the values arrive as `8`, `9`, `10` — never accumulating.
Now the bug is obvious: `total = score` replaces where it should add.
The gap between what you *believed* was in the variable and what
actually printed is where every bug of this kind lives.

The limits of print debugging are real, though. You have to guess in
advance which values matter, you edit the program to inspect it, and
you must remember to remove the prints afterwards.

## What a debugger adds

A debugger lets you inspect a running program without changing it.
Editors present this differently — buttons, a side panel, keyboard
shortcuts — but the five ideas are the same in every one of them, and
they are worth knowing by name.

| Idea | What it does |
| --- | --- |
| Breakpoint | Marks a line where the program should pause, before running |
| Step over | Run the next line, then pause again |
| Step into | If the next line calls a function, go inside it and pause there |
| Watch | Keep a variable's current value visible while you step |
| Call stack | The list of functions currently in progress, innermost first |

The workflow never changes: set a breakpoint just before the part you
suspect, run, then step forward one line at a time while watching one
or two variables. You are doing by machine exactly what
[[Trace It]] has you do by hand — which is why the paper version comes
first.

## A debugger you already have

Python includes one, so this works without any particular editor.
Insert this line where you want the program to pause:

```python
breakpoint()
```

Run the program normally. It stops at that line and gives you a
`(Pdb)` prompt, where a handful of single letters do the work:

| Command | Meaning |
| --- | --- |
| `n` | Next line — step over |
| `s` | Step into the function being called |
| `p total` | Print the current value of `total` |
| `w` | Where am I — show the call stack |
| `c` | Continue until the next breakpoint or the end |
| `q` | Quit |

Remove the `breakpoint()` line before you hand anything in, exactly as
you would remove leftover prints.

## Reading a call stack

You have already seen a call stack, in every traceback you have read.
This program:

```python run
def total_minutes(sessions):
    total = 0
    for minutes in sessions:
        total = total + minutes
    return total

def average_minutes(sessions):
    return total_minutes(sessions) / len(sessions)

print(average_minutes([]))
```

fails like this:

```
Traceback (most recent call last):
  File "/home/student/sleep.py", line 10, in <module>
    print(average_minutes([]))
          ~~~~~~~~~~~~~~~^^^^
  File "/home/student/sleep.py", line 8, in average_minutes
    return total_minutes(sessions) / len(sessions)
           ~~~~~~~~~~~~~~~~~~~~~~~~^~~~~~~~~~~~~~~
ZeroDivisionError: division by zero
```

Read it from the bottom: the division failed, inside
`average_minutes`, which was called from line 10 with an empty list.
Two frames, one story. The bug is not in the arithmetic — it is that
nobody decided what the average of nothing should be, which is the
sort of question [[The Bad Input Hunt]] exists to raise before your
users find it for you.

The debugger is not a separate program you install. It is part of the
development environment you are already in — alongside the editor, the
run button, the output pane, and the place errors appear. Knowing which
part of that environment answers which question is most of what
"knowing your tools" means, and it is why the same bug takes ten
minutes for one person and an afternoon for another.

%%curriculum-start%%
## Curriculum connection

![[B4.5]]

![[C3.1]]
%%curriculum-end%%
