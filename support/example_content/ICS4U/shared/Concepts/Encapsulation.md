---
title: Encapsulation
publish: true
created: __CREATED__
tags:
  - concepts
---
The booking program had one rule: a room holds between one and thirty
people. The rule was written, tested, and correct. Then a second file
needed to fix a typo in a group size, wrote
`tutoring.people = -4` because that was quickest, and the front desk
printed a booking for minus four people.

The rule was never broken. It was *bypassed* — and a rule that can be
bypassed by anybody who knows the attribute name is not really a rule
at all. Encapsulation is the practice of putting the data and the
rules that protect it in the same place, and then asking everybody to
go through the front door.

## Put the rule where the data is

```python
class Booking:
    """One room booking at the community centre."""

    def __init__(self, room, purpose, people):
        self.room = room
        self.purpose = purpose
        self._people = 0
        self.set_people(people)

    def set_people(self, people):
        """Set the group size. Refuse anything the room cannot hold."""
        if people < 1:
            return False
        if people > 30:
            return False
        self._people = people
        return True

    def people(self):
        """How many people this booking is for."""
        return self._people

    def __str__(self):
        return f"{self.room}: {self.purpose}, {self._people} people"
```

```python
tutoring = Booking("Room 2", "math tutoring", 12)
print(tutoring)
print(tutoring.set_people(18))
print(tutoring.set_people(-4))
print(tutoring)
```

```text
Room 2: math tutoring, 12 people
True
False
Room 2: math tutoring, 18 people
```

The change to 18 succeeds and reports `True`; the change to `-4` is
refused and reports `False`, and the booking is untouched. Notice that
`__init__` calls `set_people` rather than assigning directly. There is
one gate, and even the constructor goes through it.

## Python has no `private` — say so out loud

This is where a lot of textbooks quietly lie. In Java or C# you would
write `private int people;` and the compiler would refuse to let
anybody outside the class touch it. **Python has no such keyword and
no such enforcement.** Add one more line to the program above:

```python
tutoring._people = -4
print(tutoring)
```

```text
Room 2: math tutoring, -4 people
```

It runs. No error, no warning, no protection. The single leading
underscore in `_people` is a **convention**, not a mechanism: it means
"this is internal to the class; if you touch it, you are on your own
and I may rename it tomorrow". Every Python programmer knows that
convention, and tools that generate documentation and autocomplete
lists respect it. Python's own standard library relies on it
throughout.

> [!warning] What the double underscore actually does
> `self.__people` is sometimes taught as "real private". It is not.
> Two leading underscores trigger **name mangling**: inside the class
> the attribute is silently renamed to `_Booking__people`. So
> `booking.__people` raises
> `AttributeError: 'Booking' object has no attribute '__people'` —
> but `booking._Booking__people` reads and writes it perfectly well.
> Name mangling exists to stop a subclass from *accidentally* reusing
> a name, not to stop anybody from getting in. Use it if you have that
> specific problem; do not claim it makes an attribute private.

## A promise, not a padlock

So if Python will not stop anybody, why bother? Because the point was
never to defeat an attacker who has your source code. It is to make
the correct path the obvious one, for people who mean well and are in
a hurry — including you, later in the course, at 11 p.m.

- **The class can be trusted.** If every change to `_people` goes
  through `set_people`, then "no booking ever has a bad size" is a
  sentence you can defend, and a test can check.
- **The internals can change.** Store `_people` as an integer today
  and as a list of registered names next month; anybody using
  `people()` and `set_people()` never notices. Reach in directly and
  every one of those files breaks the day you improve the class.
- **The rule has one home.** When the fire code changes the maximum to
  25, you edit one line, not every file that ever set a size.
- **Reviewers can see it.** A diff that writes to somebody else's
  `_attribute` is a visible smell, and [[Read the Diff]] is where the
  room learns to notice.

> [!question]- Self-check: is `set_people` returning `False` good enough?
> (click to expand)
> It depends on what a bad size *means*. Returning `False` suits a
> front desk that must stay open — the caller can show a message and
> carry on. Raising `ValueError("group size must be 1 to 30")` suits a
> program where a bad size means the data is already corrupt and
> continuing would make it worse. Both are defensible; silently
> clamping the value to 30 is not, because it invents a fact nobody
> supplied. What matters is that you choose deliberately and write the
> choice in the docstring — that is the precondition, recorded.

Encapsulation is also where privacy gets decided. An attribute that
does not exist cannot be leaked, mishandled, or subpoenaed, which is
why the volunteer programs in this course store a first name and hours
and nothing else. That argument continues in
[[Ethics, Security, and the Profession]].

See it working in [[A Stack and a Queue]], where `_items` is exactly
this convention protecting a promise about order, and practise in
[[Methods and Encapsulation Practice]].

%%curriculum-start%%
## Curriculum connection

![[C1.2]]

![[A2.2]]

![[C1.4]]
%%curriculum-end%%
