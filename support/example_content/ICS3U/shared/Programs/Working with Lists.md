---
title: Working with Lists
publish: true
codeRunner: true
created: __CREATED__
tags:
  - programs
---
Mr. Ferreira teaches two Grade 11 classes and has a fixed habit before
reports go home: he reads down the mark list looking for the students
he should talk to first. It takes twenty minutes per class and he
sometimes misses one. This program does the reading; he still does the
talking.

## The program

```python run readonly
# Mark check-in helper for Mr. Ferreira. It works with marks only —
# no names, no student numbers. He matches the numbers to people
# himself, from his own class list.

marks = [78, 91, 46, 63, 88, 52, 39, 70, 84, 59]
check_in_below = 60

total = 0
highest = marks[0]
lowest = marks[0]

for mark in marks:
    total = total + mark
    if mark > highest:
        highest = mark
    if mark < lowest:
        lowest = mark

average = total / len(marks)

low_marks = []
for mark in marks:
    if mark < check_in_below:
        low_marks.append(mark)

print(f"Marks entered: {len(marks)}")
print(f"Average:       {average:.1f}")
print(f"Highest:       {highest}")
print(f"Lowest:        {lowest}")
print(f"Below {check_in_below}:      {len(low_marks)} of them: {low_marks}")
```

```
Marks entered: 10
Average:       67.0
Highest:       91
Lowest:        39
Below 60:      4 of them: [46, 52, 39, 59]
```

## How it works

One list holds ten values under one name, so the program can ask
questions of all of them at once. `len(marks)` is how many there are —
which means nothing breaks when Mr. Ferreira pastes in a class of
twenty-eight.

The first loop does three jobs in one pass: it accumulates `total`, and
it keeps `highest` and `lowest` up to date. Both records start at
`marks[0]` rather than at `0`, because a starting value of zero could
never be beaten by a low mark, and the program would confidently report
a lowest of `0` that nobody earned.

The second loop **builds a new list**. `low_marks` starts empty and
`append` adds to it, so after the loop it holds exactly the marks below
the threshold — and printing a list prints its brackets and commas for
free.

Two loops rather than one is a deliberate choice here. You *could* do
both jobs in a single pass, and it would run imperceptibly faster; two
short loops that each do one nameable thing are easier to read, to
test, and to explain to Mr. Ferreira. Speed matters when it matters;
clarity matters every day.

> [!note] Why there are no names in this program
> A file of marks with names attached is a file that must never be
> emailed, left on a shared drive, or copied to a memory stick — and
> the moment it exists, somebody will do one of those things. Marks
> alone are not personal information, so the program was designed
> without names on purpose. That is the smallest-data question from
> [[Files and Persistence]], answered before a line was written.

## Change it

1. **One line.** Set `check_in_below` to `70`. The last line becomes
   `Below 70:      5 of them: [46, 63, 52, 39, 59]` — the threshold
   appears in the output because it was a variable, not a number typed
   into a `print`.
2. **A few lines.** Add a count of marks at 80 or above, using the same
   pattern as `low_marks` but with a counter instead of a list. For
   this data the answer is `3`.
3. **A real change.** Replace the hard-coded list with typed entry: an
   empty `marks = []`, then a `while` loop that asks for a mark, adds
   it with `marks.append(int(entry))` while `entry.isdigit()`, and
   stops when the user types `done`. Everything below the list keeps
   working untouched — which is the clearest evidence you will get that
   the rest of the program was written against `marks`, not against
   those particular ten numbers.

Practise the patterns in [[Lists Practice]], and read the ideas in
[[Lists]].

%%curriculum-start%%
## Curriculum connection

![[A1.5]]

![[A1.6]]

![[A2.3]]
%%curriculum-end%%
