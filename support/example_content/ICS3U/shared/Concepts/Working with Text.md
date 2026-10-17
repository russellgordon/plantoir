---
title: Working with Text
publish: true
codeRunner: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
The sign-in program worked in testing and failed in the corridor. The
name checked out fine when you typed it, and failed for the student who
typed `  Priya  ` with the space bar still under her thumb. To a
person, that is the same name. To Python, `"  Priya  "` and `"Priya"`
are two different values, and `==` says so.

Text is data, and data that comes from people is messy. Cleaning it up
is a normal, expected part of the job.

## A string is a sequence

A string is characters in order, indexed exactly like a list:

```python run readonly
name = "Priya"
print(len(name))    # 5
print(name[0])      # P
print(name[-1])     # a
print(name[0:2])    # Pr — from 0 up to but not including 2
```

Each character is itself stored as a number — Unicode gives `P` the
number 80, which `ord("P")` will confirm and `chr(80)` will reverse.
That is not trivia: it is why sorting text puts `"Zebra"` before
`"apple"`, since every capital letter has a lower number than every
lower-case one.

Joining is `+` between two strings, and only between two strings:
`"You are " + 16` raises
`TypeError: can only concatenate str (not "int") to str`. An f-string
sidesteps the whole problem, which is why this course prefers them:
`f"You are {age}"` converts the number for you.

## Methods somebody already wrote

A method is a subprogram that belongs to a value; you call it by
writing the value, a dot, and the name. You will never write these
yourself — reaching for the ones that exist is a skill in its own
right.

| Method | Example | Result |
| --- | --- | --- |
| `.strip()` | `"  Priya  ".strip()` | `"Priya"` |
| `.lower()` | `"PRIYA".lower()` | `"priya"` |
| `.upper()` | `"Priya".upper()` | `"PRIYA"` |
| `.replace(a, b)` | `"Fifteen Dogs".replace("Dogs", "Cats")` | `"Fifteen Cats"` |
| `.split(sep)` | `"Fifteen Dogs\|14".split("\|")` | `["Fifteen Dogs", "14"]` |
| `.isdigit()` | `"14".isdigit()` | `True` |
| `.startswith(s)` | `"Fifteen Dogs".startswith("Fifteen")` | `True` |

Two of them fix the corridor bug in one line. Type a name in the input
box — try two spaces, then PRIYA, then a space — then press Run:

```python run readonly
typed = input("Name: ")
name = typed.strip()

if name.lower() == "priya":
    print("Signed in.")
```

Comparing lower-case to lower-case means `PRIYA`, `priya`, and `Priya`
all match. Watch the trap in the table, though: `"3.5".isdigit()` is
`False`, and so is `"-2".isdigit()`. It answers "is every character a
digit", not "is this a number".

`.split()` is the one that unlocks files. A line saved as
`Fifteen Dogs|14` comes back as a list of two strings, ready to be used
separately — that is the whole trick behind
[[Reading and Writing Files]].

## Strings never change

```python
name = "priya"
name[0] = "P"
```

```
TypeError: 'str' object does not support item assignment
```

Strings are immutable: every method above *returns a new string* and
leaves the original alone. So `typed.strip()` on its own line does
nothing useful unless you keep the result — `name = typed.strip()`.
This catches everybody once, and once is usually enough.

Practise the cleaning and searching in [[Text Practice]], and bring a
messy real-world example to [[The Bad Input Hunt]] — human-typed text
is where programs meet the actual world.

%%curriculum-start%%
## Curriculum connection

![[A1.2]]

![[A1.3]]

![[A3.1]]
%%curriculum-end%%
