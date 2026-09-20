---
title: Reading a Traceback in Someone Else's Code
publish: true
created: __CREATED__
tags:
  - tutorials
enableToc: true
---
Last year a traceback was three lines long and pointed at a file you
had written twenty minutes earlier. This year it is fifteen lines
long, names four files, and only one of them is yours. The panic that
causes is entirely about length. The structure has not changed at
all, and once you can read it, a long traceback tells you more than a
short one — it hands you the whole chain of calls that led to the
failure.

## The anatomy

Here is a real one. A program prints a weekly summary; the summary is
computed by a helper module; the helper does the arithmetic.

```text
Traceback (most recent call last):
  File "/home/student/main.py", line 4, in <module>
    weekly_summary(weeks_sessions)
  File "/home/student/report.py", line 6, in weekly_summary
    average = average_attendance(sessions)
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/student/attendance.py", line 6, in average_attendance
    return total / len(sessions)
           ~~~~~~^~~~~~~~~~~~~~~
ZeroDivisionError: division by zero
```

Five things are in there, and each has a job:

1. **"most recent call last".** Python means it literally. The
   frames are in the order they were called, so the *last* one is
   where the program actually died and the *first* one is where the
   whole chain began.
2. **The frames.** Each is a file, a line number, and the name of the
   function that line is inside. `<module>` means the line was not
   inside any function — it was at the top level of that file.
3. **The source lines.** Python prints the line itself so you do not
   have to open the file to know roughly what happened.
4. **The markers.** `^^^^` underlines the part of the line that was
   being evaluated when things went wrong; `~~~~` marks the
   surrounding expression. On `total / len(sessions)` the marks point
   straight at the division, which is a real narrowing when a line
   contains four operations.
5. **The last line.** The error type and its message. This is the
   only line that says what went wrong. Read it first.

## The method

> [!important] Read the bottom, then find your code
> Two moves, in this order. **What** went wrong is on the last line.
> **Where you can do something about it** is the lowest frame in a
> file you are able to change. Those are usually different frames,
> and that is the single most useful thing to know about long
> tracebacks.

In the example: what went wrong is a division by zero. The lowest
frame is `attendance.py`, which you did not write. So walk upward
until you reach a file you own — `main.py`, line 4 — and look at what
it passed in. `weeks_sessions` is an empty list. That is the cause,
sitting two frames above the crash, on a line that never appeared in
the error message at all.

## Four questions that finish the diagnosis

| Question | How you answer it |
| --- | --- |
| What went wrong? | The last line of the traceback, in your own words |
| Where did it die? | The lowest frame — file, line, function |
| What did that code receive? | Walk up one frame at a time; each shows the call that led downward, though not the values it passed |
| Which frame can I change? | The lowest one in code you own. Start there, not at the crash |

That third row is where most of the work happens, and there is a
shortcut for it. Add a `print()` in the frame just above the crash,
showing the values being handed down. In the example,
`print(len(sessions))` in `weekly_summary` says `0` immediately, and
the diagnosis is finished.

## When the crash is genuinely in their code

Sometimes you walk all the way up and every frame is in a module you
did not write and are not supposed to edit. That is still useful
information, and there are only two possibilities:

- **You called it wrongly.** Far more likely. Read the function's
  docstring and its parameters, and check what you passed against
  what it expects.
- **It really is a bug in their code.** It happens. What you owe
  everyone next is a *small* reproduction — the shortest program that
  triggers it — because "it crashes somewhere in the report module"
  cannot be acted on and eight lines that fail every time can. That
  is the same standard as a good bug report in [[Getting Help]].

Either way the code stays; you do not silently patch somebody else's
module to make your error go away. If it needs changing, it needs a
commit with a message, and a person who agrees — see
[[Using Version Control]].

## The other half: what the traceback cannot tell you

A traceback only appears when the program *crashes*. The bugs that do
real damage often produce no traceback at all — a wrong answer,
delivered confidently, in the right format. Nothing on this page will
catch those. That is what [[Writing Tests]] is for, and it is why
"it ran" is never the same claim as "it works".

Drill the reading itself in [[Name That Error]]; the wider skill of
finding your way around a program you did not write is
[[Reading Somebody Else's Code]].

%%curriculum-start%%
## Curriculum connection

![[A2.3]]

![[A4.1]]
%%curriculum-end%%
