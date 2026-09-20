---
title: Attributes and Methods
publish: true
created: __CREATED__
tags:
  - concepts
---
Somebody asked a fair question in class this week: if
`add_hours(volunteer, 2)` works perfectly well as a plain function,
why go to the trouble of writing `volunteer.log_shift(2)` inside the
class? Both change the same number. Both are one line.

The answer arrives about three weeks later, when a second file needs
to add hours, and a third file needs to add hours differently, and
nobody can find all the places that touch `volunteer.hours`. A method
is a promise about where the rules live.

## Attributes: what one object knows

Attributes are the variables that belong to an object. They are
created with `self.` inside the class — usually in `__init__`, so that
every object of the class starts life with the same set of them.

```python
class Booking:
    """One room booking at the community centre."""

    def __init__(self, room, purpose, people):
        self.room = room
        self.purpose = purpose
        self.people = people
        self.confirmed = False
```

`confirmed` is not a parameter. Nobody books a room already confirmed,
so the constructor decides it for everybody — that is what a
constructor is for. Any rule that holds for *every* object of the
class belongs there, written once.

## Methods: what one object can do

A method is a function defined inside a class, whose first parameter
is `self`.

```python
    def confirm(self):
        """Confirm this booking. Returns False if it was already confirmed."""
        if self.confirmed:
            return False
        self.confirmed = True
        return True

    def size_note(self):
        """Describe the group size in words the front desk uses."""
        if self.people <= 6:
            return "small group"
        if self.people <= 20:
            return "standard"
        return "large group - needs the hall"
```

`self` is not magic and it is not a keyword; it is a parameter, and
Python fills it in for you. When you write `choir.confirm()`, Python
calls `confirm(choir)`. Everything the method touches through `self`
belongs to that one object, which is why confirming the choir does not
confirm the tutoring session.

| In the class | At the call site | What Python does |
| --- | --- | --- |
| `def confirm(self):` | `choir.confirm()` | Passes `choir` in as `self` |
| `self.people` | — | Reads *this* booking's size |
| `return True` | `if choir.confirm():` | Hands the answer to the caller |
| `def __init__(self, ...)` | `Booking("Hall", ...)` | Builds, then initialises |
| `def __str__(self):` | `print(choir)` | Supplies the printable form |

## Why the behaviour goes inside

The rule "more than twenty people needs the hall" is a fact about
bookings. Put it in `size_note` and there is exactly one place to
change it when the centre reopens the gym. Put it in four `if`
statements across three files and you have the parallel-lists problem
again, one level up.

Two habits that keep methods honest:

- **Methods return; the program prints.** A method that prints can
  only ever be used one way. A method that returns can be printed,
  stored, tested, or sent to a web page. The one exception is a method
  written *to* display something, and it should say so in its name.
- **Docstrings, not guesswork.** The triple-quoted line under `def`
  is what `help(Booking.confirm)` shows and what your teammate reads
  at 11 p.m. Say what it returns and when it refuses — that is
  [[A4.3|the documentation expectation]], and it costs eight seconds.

> [!question]- Self-check: what does this print, and why?
> ```python
> tutoring = Booking("Room 2", "math tutoring", 12)
> choir = Booking("Hall", "community choir", 24)
> print(tutoring.confirm(), tutoring.confirm())
> print(choir.confirmed)
> ```
> `True False`, then `False`. The first call flips `tutoring`'s own
> `confirmed` to `True` and reports success; the second finds it
> already confirmed and refuses. `choir` was never touched, because
> `self` was `tutoring` both times. Two objects, two independent sets
> of attributes — that separation is the entire reason to use a class.

Write your first methods in [[Your First Class]], see two classes call
each other's methods in [[A Program with Two Classes]], and drill the
mechanics in [[Methods and Encapsulation Practice]]. When somebody
else's method does something you did not expect, [[Trace It]] is the
routine that finds out what `self` really was.

%%curriculum-start%%
## Curriculum connection

![[C1.1]]

![[C1.3]]

![[A4.3]]
%%curriculum-end%%
