---
name: plantoir-runnable-code
description: Use when a Plantoir course page should let students RUN code in the browser - "make this example runnable", "make this Swift example runnable", "let students try it", an interactive or editable Python example, a Swift program students run with their own input, a program that reads input (input() or readLine()), a practice exercise students edit and run, "runnable", "live code", "try it yourself". Covers Python (editable) and Swift (read-only, students change the input). Says how to opt the page in, how to write a runnable block and its flags, how input works, what each language can and cannot do, how it prints, and how to check it.
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

Two languages can run: **Python** (students edit the code and run it) and
**Swift** (students run it with their own input; the code itself is
read-only). The opt-in is the same for both; each has its section below.

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
  without a connection until a program is stopped, another block runs, its
  output reaches the limit, or the page changes - then it needs the connection again (a few small checks
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

## Swift

A ` ```swift run ` block runs too - read-only: students see the code,
type into the input box, and press **Run** (and **Stop**). They cannot
change the code, and a short note under each block says so. Plantoir
compiles each Swift block when the site is previewed, so the program a
student runs is ready before they open the page. Use Swift blocks for
programs worth running with different input; use plain ` ```swift ` blocks
for code to read.

### 1. Opt in and write the block

The page needs `codeRunner: true` (Python's section 1, exactly the same).
Then add `run` after `swift`, lowercase:

````markdown
```swift run
print("What is your name?")
let name = readLine() ?? ""
print("Hello, \(name)!")
```
````

` ```Swift run ` (capital S) is NOT runnable. Swift takes two flags after
`run`: `stdin` (always show the input box) and `autorun` (run once when the
block scrolls into view). `readonly` is not needed - every Swift block is
read-only already.

### 2. Programs that read input

`readLine()` reads the input box, **one line for each `readLine()` call**,
in order; each line read is shown after its prompt in the output, even a
prompt printed with `print("Name? ", terminator: "")`. Past the last line,
`readLine()` returns `nil` - so write `readLine() ?? ""`, or
`while let line = readLine() { ... }` to read every line. Tell students in
the page's text what to type, one value per line, and remind them that
changing the input and pressing Run again is the whole point:

````markdown
Type your name on the first line of the input box and your age on the
second, then press Run. Try a different age and run it again.

```swift run
print("What is your name?")
let name = readLine() ?? ""
print("How old are you?")
let age = Int(readLine() ?? "") ?? 0
print("\(name) will be \(age + 1) next year.")
```
````

The input box appears by itself when the code calls `readLine(`.

### 3. What Swift can and cannot do here

It is Swift 6.4 in Swift 5 language mode, compiled to a small program for
the browser:

- **Works**: variables, `if`/`switch`/loops, functions, optionals, arrays,
  dictionaries, sets, strings (including `lowercased()`, `split`,
  `contains`, accented letters), structs, classes and inheritance, enums
  with associated values, protocols, closures, errors with `do`/`catch`,
  `Int.random(in:)`, `Double` maths, and printing any of these with
  `print(...)` or `"\(...)"`.
- **Bigger, still works**: a block that prints an array, an optional, a
  struct or an error inside a string, or uses `String.contains` with a
  string, is compiled with Swift's full library - about 1 MB for a student's
  browser to fetch on its first Run, instead of about 50-100 KB. If a page
  has many such blocks, that adds up on an iPad on school Wi-Fi; a loop that
  prints each item is smaller than `print(array)`.
- **Does not work**: anything needing an app or a screen (SwiftUI, UIKit),
  files on the student's computer, the network, the time of day, or a
  package from outside Swift itself. `import Foundation` compiles but makes
  the program over 40 MB - do not use it.
- A program that **crashes** (an index past the end of an array,
  unwrapping a `nil` with `!`) stops with its `Fatal error: ...` line and
  "The program stopped because of an error." - which is often worth
  showing students on purpose.
- Deep **recursion** stops early: Safari allows only about 2,000 nested
  calls (Chrome about 5,000), and a program past that just crashes, with
  no Fatal error line. Keep recursive examples well under 1,000 calls deep.
- A list that grows for ever stops at 256 MB; Swift then says, misleadingly,
  "Unexpectedly found nil while unwrapping an Optional value".
- `exit(n)` from WASILibc shows "The program ended with exit code n."

### 4. When a block does not compile

A Swift block with an error is not a broken site: the preview still opens,
the block shows its code with Run turned off ("This program isn't ready to
run yet."), and the build says where - on a line starting
`plantoir: error:` with the page, the block's number, the line in the page
and Swift's own first error message, and as a folder problem in Plantoir.
Fix the code and preview again. Check every Swift block you write compiles
(Swift 5 mode) before handing it over.

### 5. Things to know

- The first preview of a course with Swift on a Mac downloads about 1.3 GB
  and takes a few minutes, once, to get Swift ready; later previews compile
  only blocks that changed (a second or two each). Previewing while offline
  the first time leaves the blocks "not ready" until the next preview online.
- Plantoir on Windows cannot make Swift blocks runnable yet: they show "not
  ready". Preview the course on a Mac.
- `%%`, adding blocks after existing ones, printing and opening the site as
  files work exactly as for Python (sections 5-7 above).
- If a Swift block shows as plain code with no Run button and no "not
  ready", the build's `plantoir: error:` line names it: start its ```` ``` ````
  on a line of its own and indent every line of the block alike.

### 6. Check it

Ask the teacher to preview the section, open the page, type input and press
Run on each Swift block, then change the input and run it again.
