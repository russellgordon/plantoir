---
title: Text Practice
publish: true
codeRunner: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Working with Text]]. Text typed by a person is
never as tidy as text typed by you, and every question here is a small
version of a bug that has genuinely broken somebody's program.

## Reading text

1. With `title = "Fifteen Dogs"`, what does each print? `len(title)`,
   `title[0]`, `title[-1]`, `title[0:7]`.
2. Why is `"  Priya  " == "Priya"` `False`, and what one method call
   fixes it?
3. What do each of these produce: `"14".isdigit()`, `"3.5".isdigit()`,
   `" 14".isdigit()`, `"".isdigit()`? What does `.isdigit()` actually
   test?
4. **Find the fault.**
   ```python
   name = "priya"
   name[0] = "P"
   ```

## Working with text

5. A saved line looks like `Fifteen Dogs|14`. Split it into the title
   and the number of days, and print the number of days plus one.
6. A sign-in check should accept `PRIYA`, `priya`, and `  Priya  `.
   Write the condition.
7. Given `full = "Priya Nair"`, print the initials `PN`.
8. **Challenge.** Count the vowels in `"Fifteen Dogs"`, ignoring case.

## Answers

> [!success]- Answer 1
> `12`, `F`, `s`, `Fifteen`. The space counts as a character, and the
> slice `[0:7]` runs from position 0 up to but *not including*
> position 7 — the same "up to but not including" rule as `range`.

> [!success]- Answer 2
> The spaces are characters, so the two strings are genuinely
> different values. `.strip()` removes whitespace from both ends:
> ```python run
> typed = "  Priya  "
> print(typed.strip() == "Priya")
> ```
> That prints `True`. Strip anything that came from `input()` before
> comparing it — always.

> [!success]- Answer 3
> `True`, `False`, `False`, `False`. It tests whether *every*
> character is a digit and there is at least one — so a decimal point,
> a leading space, a minus sign, or an empty line all make it `False`.
> That is exactly why it is useful as a guard before `int()`.

> [!success]- Answer 4
> Strings are immutable — you cannot change one character in place:
> ```
> TypeError: 'str' object does not support item assignment
> ```
> Build a new string instead:
> ```python run
> name = "priya"
> name = name[0].upper() + name[1:]
> print(name)
> ```
> That prints `Priya`. Every string method returns a *new* string; the
> original is never edited.

> [!success]- Answer 5
> ```python run
> line = "Fifteen Dogs|14"
> fields = line.split("|")
> title = fields[0]
> days = int(fields[1])
> print(days + 1)
> ```
> ```
> 15
> ```
> `.split("|")` returns a list of strings — including `"14"`, which is
> still text until `int()` converts it. This is exactly how a line read
> back from a file becomes usable data.

> [!success]- Answer 6
> ```python run
> typed = input("Name: ")
> name = typed.strip().lower()
>
> if name == "priya":
>     print("Signed in.")
> ```
> Clean first, compare second. Comparing lower-case to lower-case
> handles the capitals; the `.strip()` handles the space bar. Note that
> the *stored* comparison value is written in lower case too — mixing
> that up is a fifteen-minute bug.

> [!success]- Answer 7
> ```python run
> full = "Priya Nair"
> parts = full.split(" ")
> initials = parts[0][0] + parts[1][0]
> print(initials)
> ```
> ```
> PN
> ```
> `parts[0][0]` reads as "first word, first character". This version
> assumes exactly two words — which is a real assumption about people's
> names, and a bad one to leave unexamined; see the accessibility
> section of [[Computers and Society]].

> [!success]- Answer 8
> ```python run
> count = 0
> for letter in "Fifteen Dogs".lower():
>     if letter in "aeiou":
>         count = count + 1
> print(count)
> ```
> ```
> 4
> ```
> A `for` loop over a string gives you one character at a time, and
> `in` asks whether that character appears in the vowel string. The
> `.lower()` means a capital `I` or `O` is counted too.
