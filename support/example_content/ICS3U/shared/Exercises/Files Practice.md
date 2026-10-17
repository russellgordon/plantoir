---
title: Files Practice
publish: true
codeRunner: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Files and Persistence]]. Work in a folder you
can afford to make a mess in — several of these questions create files,
and one of them is about destroying one.

## Reading and writing

1. What do the three modes `"r"`, `"a"`, and `"w"` do? Which one can
   lose data, and how?
2. What is in `notes.txt` after this runs, exactly?
   ```python
   with open("notes.txt", "w") as file:
       file.write("first")
       file.write("second")
   ```
3. Rewrite question 2 so the file contains two separate lines, then
   read the file back and print each line without a blank line between
   them.
4. What does this print the very first time it is run in a new folder,
   and why is that not an unusual case?
   ```python
   with open("weights.txt", "r") as file:
       print(file.read())
   ```

## Doing something useful

5. Handle the situation in question 4 so the program says something a
   person can act on and carries on with an empty list.
6. A file holds one number per line. Read it, total the numbers, and
   print how many entries there were.
7. A line is saved as `Fifteen Dogs|14`. Read the file and print each
   reminder as `Fifteen Dogs — back in 14 days`.
8. **Challenge.** Why is `FILE_NAME = "reminders.txt"` at the top of a
   program better than writing `"reminders.txt"` in four places? Give
   two reasons, one of them about a shared drive.

## Answers

> [!success]- Answer 1
> `"r"` reads an existing file. `"a"` appends to the end, creating the
> file if it does not exist. `"w"` writes — and empties the file first,
> which is how data gets lost: one letter's difference between adding a
> record and deleting every record, with no warning and no undo.

> [!success]- Answer 2
> One line: `firstsecond`. `write` adds exactly what you give it and
> nothing else, so without `\n` the two calls run together. Reading it
> back gives `'firstsecond'`.

> [!success]- Answer 3
> ```python run
> with open("notes.txt", "w") as file:
>     file.write("first\n")
>     file.write("second\n")
>
> with open("notes.txt", "r") as file:
>     for line in file:
>         print(line.strip())
> ```
> ```
> first
> second
> ```
> Without `.strip()` each printed line keeps its own newline and
> `print` adds another, so the output comes out double-spaced.

> [!success]- Answer 4
> It stops with
> `FileNotFoundError: [Errno 2] No such file or directory: 'weights.txt'`.
> That is guaranteed to happen once for every person who ever uses your
> program, because the first run always predates the file. It is a
> certainty to design for, not an edge case.

> [!success]- Answer 5
> ```python run
> try:
>     with open("weights.txt", "r") as file:
>         lines = file.readlines()
> except FileNotFoundError:
>     print("No entries yet — starting a new list.")
>     lines = []
>
> print(len(lines))
> ```
> On a first run that prints the message and then `0`. Setting
> `lines = []` in the `except` block matters: the rest of the program
> can then carry on without a special case, because "no file" and "an
> empty file" now look the same to it.

> [!success]- Answer 6
> ```python
> total = 0.0
> count = 0
>
> with open("weights.txt", "r") as file:
>     for line in file:
>         total = total + float(line.strip())
>         count = count + 1
>
> print(f"{count} entries, {total:.1f} kg")
> ```
> With `6.5`, `3.0`, and `11.2` in the file, that prints
> `3 entries, 20.7 kg`. `float()` rather than `int()`, because weights
> have decimals — and `.strip()` first, because the newline is part of
> what was read.

> [!success]- Answer 7
> ```python
> with open("reminders.txt", "r") as file:
>     for line in file:
>         title, days = line.strip().split("|")
>         print(f"{title} — back in {days} days")
> ```
> `.split("|")` returns two strings and the two names on the left take
> one each. `days` stays as text here because it is only being printed;
> the moment you want to compare it to a number, `int(days)` is
> needed.

> [!success]- Answer 8
> First, one place to change: when the file moves — into a `data`
> folder, or onto a shared drive where the whole department can reach
> it — you edit one line rather than hunting four. Second, four copies
> of a string is four chances at a typo, and a mistyped name in `"a"`
> mode does not fail loudly: it quietly creates a *second* file and
> writes there, so the data is not lost but it is not where anyone is
> looking either.
