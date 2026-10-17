---
title: Your First Python Program
publish: true
codeRunner: true
created: __CREATED__
tags:
  - programs
---
Mr. Diaz runs the winter concert. Every December he counts chairs
twice — once to work out how many the room needs, and once because he
does not trust the first count at ten o'clock at night. This program
counts them once, correctly, and prints something he can read while
carrying a stack.

## The program

```python run readonly
# Chair setup for Mr. Diaz, who runs the winter concert.
# Change the four numbers at the top; everything else follows.

rows = 8
chairs_per_row = 12
ensemble_chairs = 6
chairs_in_storage = 120

audience_chairs = rows * chairs_per_row
total_needed = audience_chairs + ensemble_chairs
chairs_left_over = chairs_in_storage - total_needed

print("Concert chair setup")
print("-------------------")
print(f"Audience: {rows} rows of {chairs_per_row} = {audience_chairs} chairs")
print(f"Ensemble: {ensemble_chairs} chairs")
print(f"Needed:   {total_needed} chairs")
print(f"Storage:  {chairs_in_storage} chairs")
print(f"Spare:    {chairs_left_over} chairs")
```

Save it as `chairs.py` and run it. You should see exactly this:

```
Concert chair setup
-------------------
Audience: 8 rows of 12 = 96 chairs
Ensemble: 6 chairs
Needed:   102 chairs
Storage:  120 chairs
Spare:    18 chairs
```

## How it works

Python starts at the top and runs one line at a time to the bottom. It
never jumps around and never guesses.

The first block gives names to the four numbers that might change. The
second block does the arithmetic, and each line uses the names created
above it — `total_needed` can use `audience_chairs` because that line
has already run. The third block prints. Splitting a program into
"facts, working out, output" like this is the input-process-output
shape from [[What a Program Is]], with the input hard-coded for now.

Three details worth naming:

- The lines starting with `#` are **comments**. Python ignores them
  completely; they are for the next person to open the file, which is
  usually you in three weeks.
- `f"..."` is an **f-string**: anything inside `{ }` is replaced by its
  value when the line runs.
- The names are long on purpose. `chairs_per_row` costs a second to
  type and saves a minute to read — see
  [[Writing Code Others Can Read]].

> [!tip] Running it, the boring reliable way
> Save the file, then in a terminal opened in the same folder type
> `python3 chairs.py` and press return. If you get
> `can't open file ... No such file or directory`, you are in a
> different folder from the file — that is the most common first-day
> problem, and [[Setting Up Python]] walks through it.
>
> The editor you type in and the terminal you run from are your
> development environment. An IDE bundles them together and adds a
> debugger, which you will meet in [[Using the Debugger]]; nothing in
> this course needs more than an editor, a terminal, and Python
> itself.

## Change it

1. **One line.** Mr. Diaz wants wider rows: change `chairs_per_row` to
   `14`. The audience line becomes 112, the total 118, and the spare
   drops to 2 — three printed numbers changed, and you edited one.
2. **A few lines.** The chairs travel on trolleys that hold eight.
   Work out `total_needed // 8` and `total_needed % 8`, and print
   `Trolley loads: 12 stacks of 8, plus 6 loose chairs`. `//` divides
   and throws away the remainder; `%` keeps only the remainder.
3. **A real change.** Set `chairs_in_storage` to `100` and run it. The
   program cheerfully reports a spare of `-2` chairs, which is not a
   thing. You cannot fix that yet — a program that reacts differently
   to different numbers needs [[Making Decisions]] — but write down
   what it *should* say, because that sentence is a specification, and
   you just wrote your first one.

%%curriculum-start%%
## Curriculum connection

![[A1.3]]

![[A4.2]]

![[C3.1]]
%%curriculum-end%%
