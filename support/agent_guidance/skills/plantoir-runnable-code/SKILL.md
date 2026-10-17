---
name: plantoir-runnable-code
description: Use when a Plantoir course page should let students RUN code in the browser - "make this example runnable", "let students try it", an interactive or editable Python example, a program that reads input, a practice exercise students edit and run, "runnable", "live code", "try it yourself". Says how to opt the page in, how to write a runnable block and its flags, how input() works, what the standard library can and cannot do, how it prints, and how to check it.
---

# Runnable code on a Plantoir page

This working folder holds courses for Plantoir, which turns each course
(`courses/<CODE>/`, an Obsidian vault of Markdown pages) into a class
website. A code block on a page can become a small program students edit
and **run in their own browser** - on a laptop, a Chromebook or an iPad,
with nothing to install and no account. They see the code in an editor, an
input box when the program reads input, **Run**, **Stop** and **Reset**
buttons, and the program's output underneath. Their edits are kept in their
browser for next time; Reset brings back the teacher's code.

This file is managed by Plantoir and is replaced when Plantoir updates; do
not edit it.

## Python

### 1. Opt the page in

Add `codeRunner: true` to the settings block at the top of the page:

```markdown
---
codeRunner: true
---
```

Write it exactly like that - `true`, not `"true"` or `1`. Leave the page's
other settings (`publish`, `printable`, dates, tags) as they are. A page
without it shows every block as ordinary code, whatever the block says.

### 2. Write a runnable block

Add the word `run` after `python` on the block's first line - lowercase,
separated by a space:

````markdown
```python run
total = 0
for n in range(1, 11):
    total += n
print("The sum of 1 to 10 is", total)
```
````

Only blocks marked `run` become runnable; a plain ` ```python ` block on the
same page stays ordinary code, so a page can mix examples to read and
programs to try. ` ```Python run ` (capital P) and ` ```py run ` are NOT
runnable. In Obsidian the block still looks like an ordinary Python block.

Flags go after `run`, separated by spaces, all lowercase:

| Flag | What it does |
|---|---|
| `readonly` | Students can run it but not edit it: the code stays highlighted, with Run and Stop only. For a demonstration whose code should not change. |
| `stdin` | Always shows the input box, even when the code does not visibly call `input()`. |
| `autorun` | Runs once by itself when the block scrolls into view. Use sparingly - at most one per page, for output students should see at once. |

````markdown
```python run readonly
print("This one runs but cannot be edited.")
```
````

A title or line highlighting can sit beside `run` (` ```python title="loop.py" run `).
A title must not CONTAIN the word ` run ` on its own, and `run` must be its
own word - `run,stdin` or `run.py` do not count.

### 3. Programs that read input

`input()` reads from the input box under the editor, **one line of the box
for each `input()` call**, in order. Each line read is shown after its
prompt in the output, as a terminal would. Past the last line, `input()`
raises `EOFError` ("EOF when reading a line"), as at the end of a file. So
whenever a program reads input, tell students in the page's text what to
type in the box, one value per line:

````markdown
Type your name on the first line of the input box and your age on the
second, then press Run.

```python run
name = input("Name? ")
age = int(input("Age? "))
print(f"{name} will be {age + 1} next year.")
```
````

The input box appears by itself when the code calls `input(`; add `stdin`
only if the call is hidden (for example in a function another block defines).

### 4. What Python can and cannot do here

It is CPython 3.14 running in the browser, with the **standard library
only**:

- **Works** (measured): `math`, `random`, `string`, `datetime`, `time`
  (including `time.sleep`, which pauses the output), `collections`,
  `itertools`, `functools`, `re`, `json`, `csv`, `decimal`, `fractions`,
  `statistics`, `sqlite3`, `zoneinfo`, `hashlib`, `ssl`, `lzma`, `asyncio`,
  `threading`, and classes, recursion, exceptions and f-strings as usual.
- **Does not work**: `turtle`, `tkinter`, `curses`, `readline`, `venv`,
  `ensurepip`, `pip`, and any package that is not part of Python itself -
  no numpy, pandas, matplotlib or requests. There is no network and no
  `pip install`.
- **Files** a program writes exist only for that one run (each Run starts
  in a fresh, empty folder). A program cannot read a file from the course.
- One program runs on a page at a time; pressing Run on a second block stops
  the first. Each Run starts with fresh variables; changes a program makes to
  Python's own modules carry over until the program is stopped (Stop, then
  Run, starts clean).
- A program that prints more than 100,000 characters is stopped. Stop ends
  any program, including one stuck in a loop.

Tracebacks look exactly like CPython's, and their line numbers are the lines
in the editor.

### 5. Things to avoid

- Never write `%%` anywhere in a block: the site removes everything between
  two `%%` (Obsidian's comment marker), even inside code, so
  `print("100%%")` changes on the site. Write `%` once.
- On a page students already use, add new runnable blocks **after** the
  existing ones, never above them: each block's saved edits are kept by its
  position on the page, so a block inserted above would hide students' work
  on every block below it (it is set aside, not offered back).
- Do not start a block's ```` ``` ```` after two list markers or after a
  list marker and a `>` on the same line (`- - ```python run`): such a block
  stays plain code. Put the fence on its own line, or one list marker in
  front of it at most.
- Do not use a runnable block for code students should only read (a long
  listing, pseudocode, another language): use a plain ` ```python ` block.

### 6. Where it works

- From the site's web address (Plantoir's preview, Netlify, Cloudflare, a
  school web server), in Safari and iPadOS 15 or later, Chrome 80 or later,
  Firefox 114 or later. The first Run on a page loads Python (about 13 MB,
  once; about a second on a Mac on a good connection, longer on an iPad on
  school Wi-Fi); later Runs start at once. Once loaded it keeps working
  without a connection until a program is stopped, another block runs, or
  the page changes - then it needs the connection again (a few small checks
  with the site, not the whole download).
- NOT from a site opened as files on a computer (a folder publish
  double-clicked): browsers run none of the page's scripts that way, so the
  blocks show as ordinary code with no Run button.

### 7. Printing

A runnable block prints as code and nothing else - no buttons, input box or
output: the teacher's code, or the student's own if they changed it. It
works on a `printable: true` page (the `plantoir-printing` skill) like any
other code block.

### 8. Check it

Ask the teacher to preview the section in Plantoir, open the page and press
Run on each block. If a block shows as ordinary code with no Run button,
check that the page says `codeRunner: true` and the block's first line is
` ```python run `. When the site is built, a block it could not set up is
named on a line that starts `plantoir: error:`, with the page, the block's
number and what to change.
