---
title: Writing Code Others Can Read
publish: true
codeRunner: true
created: __CREATED__
tags:
  - tutorials
enableToc: true
---
Code is read far more often than it is written, and one of the people
reading yours will be you, three weeks from now, having forgotten
everything. Readable code is not politeness. It is the difference
between a program somebody can pick up and one that gets thrown away
the moment you leave.

## Names carry the meaning

Same program, twice. The first is what a rushed twenty minutes
produces:

```python
def m(l):
    t = 0
    for i in l:
        t = t + i
    return t / len(l)
```

The second says what it is for:

```python
def average_mark(marks):
    """Return the average of a list of marks."""
    total = 0
    for mark in marks:
        total = total + mark
    return total / len(marks)
```

Nothing about the logic changed and the machine cannot tell the
difference. But the second version can be read aloud, its bugs are
visible, and a stranger could reuse it without asking you anything —
which is the entire argument of [[Functions]] taken one step further.

Name things after what they hold or do: `marks`, not `l`;
`average_mark`, not `calc`. Loop variables get real names too, since
`for mark in marks` reads like English and `for i in l` reads like
noise.

## Comments explain why, not what

The code already says what it does. A comment repeating it is noise:

```python
# add one to sessions counted
sessions_counted = sessions_counted + 1
```

The *reason* lives nowhere else, so that is what a comment is for:

```python
# The coach counts a practice only if it ran 20 minutes or more —
# anything shorter was a warm-up before a cancelled session.
if minutes >= 20:
    sessions_counted = sessions_counted + 1
```

The second version lets a reader disagree with you, which is exactly
what you want when the reader is your client checking that the rule
matches what they meant.

## Docstrings are the public face

Every function you write gets a docstring: one sentence in triple
quotes, first line inside the function, saying what it does and what
it hands back.

```python
def eligible_for_award(sessions_attended, sessions_total):
    """Return True when a player attended at least 75 percent."""
    return sessions_attended >= sessions_total * 0.75
```

Editors and tools display docstrings automatically, so this sentence
is what a future reader sees before any of your code. Write it for a
stranger.

## Output is part of the code

Everything above is for programmers. The person using your program
reads something else entirely — your prompts and your messages:

```python run
hours = input("How many hours did you work? ")
if hours.isdigit():
    pay = int(hours) * 17.20
    print(f"That comes to {pay:.2f} dollars.")
else:
    print("Please type the number of hours using digits, like 12.")
```

`ENTER VAL:` and `INVALID INPUT` would run identically and would tell
the user nothing. Write the words a person needs, not the words that
were quickest to type — see [[When Code Hurts]] for how much that
choice can matter.

## Credit belongs in the code

[[Our Classroom Norms]] says borrowed help is fine when it is named,
and a comment is where the naming happens:

```python
# Loop structure adapted from an AI assistant's example;
# I rewrote the condition and tested the edge cases myself.
```

A classmate's idea, a forum answer, an AI suggestion — same pattern.
Name the source, then say which part of the thinking is yours. That is
how professionals document borrowed code, and it turns "did you write
this?" into a question your comment has already answered. The wider
version of the argument is [[Sharing What You Build]].
