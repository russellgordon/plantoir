---
title: Testing and Debugging
publish: true
codeRunner: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
Nobody in this course will write a program that works the first time,
and after a few weeks nobody expects to. The difference between a
frustrating hour and a productive one is not talent — it is having a
method instead of a mood. Debugging is a procedure you can follow when
you are tired.

## Three kinds of wrong

| Kind | When it shows up | Example | How Python behaves |
| --- | --- | --- | --- |
| Syntax error | before anything runs | a missing `:` after `if` | refuses to start, points at the line |
| Run-time error | part-way through | `int("seven")` | stops there, prints a traceback |
| Logic error | never | `<` where you meant `<=` | runs happily, answers wrongly |

Only the third one is genuinely dangerous, because the program looks
fine and the wrong number goes home in somebody's report. Syntax and
run-time errors announce themselves; logic errors have to be hunted.

## Read the traceback from the bottom

```
Traceback (most recent call last):
  File "/home/student/tally.py", line 2, in <module>
    count = int(answer)
ValueError: invalid literal for int() with base 10: 'seven'
```

Bottom line: *what* went wrong. Above it: *where*. The cause is often
one line earlier than the crash — here, an `input()` whose result
nobody checked. Error messages use a small, learnable vocabulary, and
[[Reading an Error Message]] takes a traceback apart piece by piece;
[[Name That Error]] is the drill that makes it fast.

## Trace it by hand

When there is no error message, become the computer. Write the
variables across the top of a page and fill in a row per pass.

```python run
marks = [46, 52, 78]

for mark in marks:
    below = 0
    if mark < 60:
        below = below + 1

print(below)
```

Two of those marks are below 60, and the program prints `0`.

| Pass | `mark` | `below` at start of pass | `below` at end |
| --- | --- | --- | --- |
| 1 | 46 | 0 | 1 |
| 2 | 52 | 0 | 1 |
| 3 | 78 | 0 | 0 |

The table exposes it: `below = 0` is *inside* the loop, so every pass
throws away the previous count. Move that line above the `for` and the
program prints `2`. Tracing found it in three rows; guessing could have
cost the afternoon.

Two tools do the same job faster once the habit is there: temporary
`print` statements showing the state of a variable each pass, and the
step-through debugger in [[Using the Debugger]], which shows you every
variable without your having to ask.

## A test plan is a table

Testing is not "I ran it and it seemed fine". It is a written list of
scenarios chosen so that every branch of the program gets used at least
once — including the ugly inputs. Here is the plan that was run against
an early version of the library return-desk helper in
[[Branching Programs]]:

| Scenario | Input | Expected | Actual | Pass? |
| --- | --- | --- | --- | --- |
| On time | `0` | on-time message | on-time message | pass |
| Boundary of "week" | `7` | under-a-week message | under-a-week message | pass |
| Just past it | `8` | reminder message | reminder message | pass |
| Over a month | `45` | speak-in-person message | speak-in-person message | pass |
| Not a number | `soon` | a clear complaint, no crash | crash | fail |

One row failed, which is the plan doing its job: the `try`/`except`
block in the finished program exists because of that row, not because
somebody remembered a rule.

Pick the boundaries on purpose: the values *at* each cutoff and one on
either side, the empty case, the impossible case, and whatever a real
person might plausibly type by mistake. Write the expected column
*before* running the program — otherwise you will find yourself
agreeing with whatever it prints, which is not a test.

## When you are stuck

1. Read the error message out loud. All of it.
2. Find the smallest input that still fails.
3. Comment out half the program. Still broken? The bug is in the other
   half.
4. Explain the code, line by line, to a person or an object. This works
   embarrassingly often.
5. Take the break. Ten minutes away has solved more bugs than an hour
   of staring.

None of this is a sign that something has gone wrong with you — bugs
are information about the difference between what you said and what you
meant. That is the argument in [[Mistakes Are Data]], and the practical
version is in [[Getting Unstuck]]. Sharpen the reading half in
[[Spot the Bug]] and [[Predict the Output]].

%%curriculum-start%%
## Curriculum connection

![[A4.1]]

![[A4.3]]

![[A4.4]]

![[A4.5]]
%%curriculum-end%%
