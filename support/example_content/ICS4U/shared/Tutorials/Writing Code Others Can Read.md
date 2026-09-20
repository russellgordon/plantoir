---
title: Writing Code Others Can Read
publish: true
created: __CREATED__
tags:
  - tutorials
enableToc: true
---
Last year the argument for readable code was that you would come back
in three weeks having forgotten everything. It was true and it was
abstract. This year it is not abstract: three other people are
reading your code *this week*, and somebody who has never met you
will still have it in a year. Readability has stopped being a
courtesy and become the property that decides whether your work
survives.

The Grade 11 habits still hold — real names, comments that explain
why rather than what, a docstring on every function, error messages
written for a person, credit named where you borrowed. This page is
what comes after them.

## Name the thing, not the data about the thing

A class is a claim about what exists in the problem. Name it after
the thing:

```python
class D:
    def __init__(self, n, c, b):
        self.n = n
        self.c = c
        self.b = b
```

Nobody can review that. Here is the same class saying what it is:

```python
class Session:
    """One bookable session: a day, a capacity, and who has booked."""

    def __init__(self, day, capacity):
        self.day = day
        self.capacity = capacity
        self.booked = []

    def spaces_left(self):
        """Return how many spaces remain, never fewer than zero."""
        remaining = self.capacity - len(self.booked)
        if remaining < 0:
            remaining = 0
        return remaining
```

The machine cannot tell the difference. A reviewer can read the
second one aloud, and — this is the part that matters — can now
*disagree* with it. "Should a session know who booked it, or should
the roster know that?" is a design conversation the first version
made impossible to have.

## The docstring is a promise

For a function that only you call, a docstring is a description. For
a function your teammates call, it is a **contract**: what goes in,
what comes back, and what happens at the edges. Write the edges down,
because the edges are what people get wrong.

```python
def find_member(names, wanted):
    """Return the position of wanted in names, or -1 if absent.

    names must be sorted; this uses a binary search and will
    silently return -1 on an unsorted list.
    """
```

That second paragraph is the entire difference between a change
somebody can safely use and the quiet failure in [[Read the Diff]].
If your function has a condition, state it where the caller will look
— which is here, not in a comment halfway down the body.

## One authoritative place for anything that can change

Every number typed into more than one place is a future bug wearing a
disguise. When the rule changes, somebody updates three of the four:

```python
if minutes >= 20:
    sessions_counted = sessions_counted + 1
...
if minutes >= 20:
    total_credited = total_credited + 1
```

Give it a name, at the top of the file, in capitals so everyone can
see it is a setting rather than a calculation:

```python
# A practice counts only if it ran this long; anything shorter was a
# warm-up before a cancelled session. The coach set this figure.
MINIMUM_PRACTICE_MINUTES = 20
```

Now the rule has one home, a reason attached, and an owner. When your
community partner says "we changed it to fifteen", the maintainer
finds it in five seconds instead of grepping the project and hoping.

## Keep the public surface small

Everything a teammate can call, they will call — and once they have,
you cannot change it without breaking their code. So be deliberate
about what you offer. A class with three well-named methods and its
working parts kept private is far easier to review, test, and change
later than one that exposes everything and hopes.

This is [[Encapsulation]] seen from the maintainer's side. Its real
value is not secrecy; it is that a small, stated surface is a
promise you can actually keep.

## Delete the dead code

The commented-out block "in case we need it", the function nobody
calls, the variable set and never read — delete them. All of it is in
[[Version Control]] forever and can be recovered by anyone in ten
seconds. Leaving it in the file costs every future reader the time to
work out whether it matters, and they will all conclude, correctly,
that they cannot safely remove it either.

## Two audiences, two documents

The code is read by programmers. Your community partner reads
something else entirely, and it is not comments.

| Document | Reader | What it must contain |
| --- | --- | --- |
| Docstrings and comments | Whoever changes the code | What each part promises, and why the odd decisions are there |
| README | Whoever inherits the project | What it is, how to run it from nothing, what it will not do |
| Handover notes | The partner | Plain language, step by step, and who to ask |

Write the README before you need it, and then test it the only way
that works: hand it to somebody who has never run your program and
watch them, silently, without helping. Every place they hesitate is a
line you owe them. [[What Happens When You Leave]] is the argument
for why this is not optional, and [[Writing About Code]] is how to
write the words themselves.

> [!important] Your reader has no context and no patience
> Not because they are unkind — because they are busy, they are in
> the middle of something else, and your program is one of eleven
> things they touched today. Code that requires a good mood to
> understand will be rewritten by somebody who does not have one.

%%curriculum-start%%
## Curriculum connection

![[A2.2]]

![[A4.3]]

![[A4.4]]
%%curriculum-end%%
