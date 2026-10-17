---
title: Reading and Writing Files
publish: true
codeRunner: true
created: __CREATED__
tags:
  - programs
---
Mr. Whitfield keeps a sticky note on the library desk: books promised
to somebody, and roughly when they should be back on the shelf. Sticky
notes fall off. This program keeps the same list in a file, so it is
still there tomorrow, next week, and after the computer is restarted.

## The program

To run it, type a title and a number of days on two lines of the input
box — `Fifteen Dogs` and `14`, say — then press Run.

```python run readonly
# Shelf-reminder list for Mr. Whitfield. The file holds TITLES and a
# number of days — never who borrowed what. That is a decision, taken
# with him, and it is written here so nobody "improves" it by adding
# names later.

FILE_NAME = "reminders.txt"


def add_reminder(title, days):
    with open(FILE_NAME, "a") as file:
        file.write(f"{title}|{days}\n")


def show_reminders():
    try:
        with open(FILE_NAME, "r") as file:
            lines = file.readlines()
    except FileNotFoundError:
        print("No reminders saved yet — this will be the first.")
        return

    print()
    print(f"Reminders on file ({len(lines)}):")
    for line in lines:
        title, days = line.strip().split("|")
        print(f"  {title} — back in {days} days")


show_reminders()
title = input("Title to add: ")
days = input("Back in how many days? ")
add_reminder(title, days)
show_reminders()
```

Here each Run starts with no saved file, so the site always shows the
first run. On your own computer, run it twice and the list is still
there.

The second time it is run, with one reminder already saved:

```
Reminders on file (1):
  Fifteen Dogs — back in 14 days
Title to add: Birdie
Back in how many days? 7

Reminders on file (2):
  Fifteen Dogs — back in 14 days
  Birdie — back in 7 days
```

## How it works

`open` needs a mode. `"a"` **appends** — it adds to the end and creates
the file if it is not there, which is why nothing is ever lost when a
reminder is added. `"r"` **reads**. The `with` block closes the file
properly when it ends, even if something goes wrong inside it, and that
matters: data written to a file that is never closed can quietly fail
to arrive.

Each reminder is stored as one line, with `|` separating the two
fields, and `\n` ending it. Reading it back reverses those two
decisions exactly: `.strip()` removes the newline, and `.split("|")`
turns `Fifteen Dogs|14` into two strings that unpack straight into
`title` and `days`. A file format is a promise between the part that
writes and the part that reads, and here the promise is four
characters long.

The first run of any program like this hits a file that does not exist.
`FileNotFoundError` is not an edge case, it is a certainty, so
`show_reminders` catches it, says something a human can act on, and
`return`s early instead of pushing on with data it does not have.

`FILE_NAME` in capitals is the convention for a value that is not meant
to change while the program runs. It also means the file is named in
exactly one place — worth having when you decide the data belongs in a
different folder on the shared drive.

> [!warning] The one-letter mistake that deletes everything
> Change `"a"` to `"w"` in `add_reminder` and run the program twice.
> The file now contains only the most recent reminder: `"w"` empties
> the file before writing. Nothing warns you, and there is no undo.
>
> This is why a program that owns somebody's data needs a backup habit
> attached to it — a dated copy of `reminders.txt` before you change
> the code that writes it. Assume the loss will happen once, because
> for most people it does.

## Change it

1. **One line.** Do the `"a"` to `"w"` experiment above deliberately,
   on a file you do not mind losing, then change it back. Seeing the
   damage once is worth more than being told about it twice.
2. **A few lines.** Add a count of reminders due within a week: loop
   over `lines`, split each one, and compare `int(days) <= 7`. With the
   two reminders above the answer is `1`.
3. **A real change.** Record *when* each reminder was added. Put
   `from datetime import date` at the top, and write three fields
   instead of two: `f"{title}|{days}|{date.today().isoformat()}\n"`.
   Then update the reading loop to unpack three values instead of two —
   and notice that every line saved by the old version now breaks it.
   Deciding what to do about old data is called migration, and it is a
   real part of maintaining software people use.

The ideas are in [[Files and Persistence]], the practice is in
[[Files Practice]], and the reason this file holds no names is worth
re-reading in [[Should It Exist]] before your own project stores its
first row.

%%curriculum-start%%
## Curriculum connection

![[B3.3]]

![[C2.1]]

![[C2.3]]
%%curriculum-end%%
