---
title: Setting Up Python
publish: true
codeRunner: true
created: __CREATED__
tags:
  - tutorials
enableToc: true
---
You need two things to program in this course: Python 3 itself, and
somewhere to type code. The lab machines already have both. This page
is for getting the same setup at home, and for understanding what the
pieces are — because "it works in class but not on my laptop" is a
problem you can now diagnose rather than suffer.

## Check what you already have

Open a terminal — Terminal on macOS or Linux, PowerShell or Command
Prompt on Windows — and type:

```
python3 --version
```

If Python is installed you get a line naming the version, such as
`Python 3.12.4`. Anything from 3.10 upward is fine for everything we
do. On Windows the command is often just `python --version`; try both
before concluding it is missing. A "command not found" or "not
recognised" message means either Python is not installed or the
terminal does not know where to find it.

## Install it if you need to

Python comes from **python.org**, whose Downloads page offers the
right installer for whatever machine you are on. Take the current
version and accept the default options, with one exception worth
watching for: on Windows the installer offers a checkbox about adding
Python to your PATH. Tick it. That checkbox is what makes the terminal
command above work, and skipping it is the single most common cause of
"I installed it and nothing happened."

## The REPL: a place to try one line

Typing `python3` on its own — no file name — starts an interactive
session. The `>>>` prompt means Python is waiting; it reads what you
type, evaluates it, prints the result, and loops, which is why it is
called a REPL:

```
>>> 2 + 2
4
>>> name = "Ada"
>>> print(f"Hello, {name}")
Hello, Ada
>>> exit()
```

The REPL is perfect for settling an argument about what one line does,
and useless for writing a program — nothing you type there is saved.
Programs live in files whose names end in `.py`.

## An editor for the files

Any program that saves plain text can write Python, but a code editor
makes life much easier: it colours the code, helps with indentation,
and runs the file without a trip to the terminal. Two common choices
are **Thonny**, which is built for people learning and ships with
Python included, and **Visual Studio Code**, which is what a great
many professionals use. Either is fine, and so is anything else your
family already has installed. Use whatever is on the lab machines when
you are in class; the code is identical everywhere.

To run a saved file from a terminal, move to the folder it is in and
type the file name after the command:

```
python3 hello.py
```

## First program checklist

Type this — do not paste it — into a file called `hello.py`, then run
it. To try it here first, type your name and your hours of sleep on two
lines of the input box under it, then press Run:

```python run
name = input("What is your name? ")
hours = float(input("How many hours did you sleep last night? "))
print(f"Thanks, {name} — that is {hours * 60:.0f} minutes.")
```

- [ ] It asks both questions and answers with a number
- [ ] Change the wording, run again, and see your change appear
- [ ] Answer the second question with `eight` instead of `8`, and read
      the crash: Python reports
      `ValueError: could not convert string to float: 'eight'`,
      which is it telling you exactly what happened — not a punishment
- [ ] Add a third question and a third line of output, by yourself

If it crashes for a different reason: capital letters matter
(`print`, not `Print`), and every opening quote and bracket needs its
closing twin. Read the message before retyping anything —
[[Reading an Error Message]] shows how — and know that crashing your
first program is the traditional welcome to programming. You are now
set up for [[Your First Python Program]].
