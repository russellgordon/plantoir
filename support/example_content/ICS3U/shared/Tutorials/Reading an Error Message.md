---
title: Reading an Error Message
publish: true
codeRunner: true
created: __CREATED__
tags:
  - tutorials
enableToc: true
---
An error message is not the computer refusing to help. It is the
computer telling you, as precisely as it can, what it was doing when
things stopped making sense. Learning to read one is a ten-minute
skill that saves you hours every week for the rest of your
programming life.

## A crash, in full

The program, saved as `hours.py`:

```python run
answer = input("How many hours did you work? ")
count = int(answer)
print(f"That is {count * 60} minutes.")
```

Run it and type `abc` at the question. Python prints this:

```
Traceback (most recent call last):
  File "/home/student/hours.py", line 2, in <module>
    count = int(answer)
ValueError: invalid literal for int() with base 10: 'abc'
```

## The anatomy

Four parts, and each one answers a different question.

| Part | What it says |
| --- | --- |
| `Traceback (most recent call last)` | A crash happened; what follows is the path to it |
| `File ".../hours.py", line 2` | Which file, and which line was running |
| `count = int(answer)` | The line itself, quoted back to you |
| `ValueError: ...` | The kind of problem, and the specific detail |

The path is simply wherever your file lives, so yours will look
different. The part that matters is the line number and the last line.

## Read it in the right order

1. **Last line first.** `ValueError` names the family: the value was
   the problem. The text after the colon is the detail — `int()` was
   handed `'abc'`, which is not a number in any base-10 sense.
2. **Then the line number.** Line 2 is where Python gave up.
3. **Then look one line earlier.** The *cause* is usually just above
   the crash. Line 1 accepted whatever the user typed, and nothing
   checked it. That is the bug; line 2 is only where it surfaced.
4. **Then decide what should happen instead.** Refuse non-numbers
   politely, or convert only after checking. What you must not do is
   let the program die in front of the person using it — see
   [[When Code Hurts]] for why that lands harder than you think.

## Two families of error

**Before the program runs**, Python may fail to understand the file at
all: `SyntaxError` and `IndentationError`. Nothing executes, so no
output appears first. A message reading
`IndentationError: expected an indented block after 'if' statement on line 2`
means a line ending in `:` promised indented lines that never arrived.

**While the program runs**, Python understood everything but met a
value it could not work with: `NameError`, `TypeError`, `ValueError`,
`IndexError`, and their relatives. Output usually appears before the
crash, which is itself a clue about how far it got.

## When the line number lies

It rarely lies, but it can point one line late. An unclosed bracket is
the classic case: Python keeps reading, hoping the bracket closes, and
only complains when the next line cannot possibly make sense. Newer
versions of Python are good about this and report
`SyntaxError: '(' was never closed` at the opening bracket; older ones
simply say `SyntaxError: invalid syntax` and point at the following
line. Either way, when a syntax error accuses an innocent-looking
line, suspect the line above it.

> [!tip] Messages get better with every Python version
> Recent versions underline the failing part of the line with `~` and
> `^` marks, and will even suggest a spelling — a misspelled `total`
> earns `Did you mean: 'total'?` on the end of the `NameError`. Older
> versions print the same diagnosis with less decoration. The
> vocabulary is identical everywhere; only the helpfulness varies.

Drill the vocabulary in [[Name That Error]], and when the message
alone is not enough, keep going with [[Using the Debugger]] and
[[Getting Unstuck]].
