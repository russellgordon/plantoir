---
title: Your First Class
publish: true
created: __CREATED__
tags:
  - programs
---
The homework club at the community centre keeps its volunteer list in
three columns on a clipboard: names down one side, grades down the
next, hours down the third. Somebody crossed a name out in the middle
of the sheet last term and did not cross out the matching hours. For
six weeks the coordinator was thanking the wrong student.

Three lists that must be kept in step are a bug waiting for a busy
afternoon. One class fixes it: a volunteer's name, grade, and hours
become one thing that moves together.

## The program

```python
# Volunteer records for the homework club that runs at the community
# centre on Tuesdays. The club needs a first name, a grade, and hours
# served. It does not need addresses, birthdates, or student numbers,
# so this program does not store them.

class Volunteer:
    """One person who has signed up to help at the homework club."""

    def __init__(self, name, grade):
        """Start a new volunteer with no hours served yet."""
        self.name = name
        self.grade = grade
        self.hours = 0

    def log_shift(self, length):
        """Add one completed shift, in hours, to this volunteer."""
        self.hours = self.hours + length

    def __str__(self):
        """Describe this volunteer in one line, for printing."""
        return f"{self.name} (Grade {self.grade}): {self.hours} h"


nadia = Volunteer("Nadia", 12)
rowan = Volunteer("Rowan", 11)

nadia.log_shift(2.5)
nadia.log_shift(2)
rowan.log_shift(1.5)

print(nadia)
print(rowan)
print(f"Nadia has served {nadia.hours} hours so far.")
print(f"Rowan is in grade {rowan.grade}.")
```

```text wrap
Nadia (Grade 12): 4.5 h
Rowan (Grade 11): 1.5 h
Nadia has served 4.5 hours so far.
Rowan is in grade 11.
```

## How it works

`class Volunteer:` does not create a volunteer. It describes what
every volunteer will be — the blueprint. The volunteers themselves
arrive on the two lines near the bottom, and there are two of them,
each with their own name, grade, and hours.

| In the program | What it is called | What it does |
| --- | --- | --- |
| `class Volunteer:` | The class | Describes the kind of thing |
| `nadia`, `rowan` | Objects, or instances | Two actual volunteers |
| `self.name`, `self.hours` | Attributes | What one volunteer knows |
| `log_shift` | A method | What one volunteer can do |
| `__init__` | The constructor | Runs once, when the object is made |
| `self` | The object itself | "This particular volunteer" |

`__init__` runs automatically. `Volunteer("Nadia", 12)` builds a fresh
object, hands it to `__init__` as `self`, and sets its three
attributes. Notice that `hours` is not a parameter: nobody starts with
hours already served, so the constructor decides that for everybody.
Rules that hold for every object of the class belong in the
constructor.

`nadia.log_shift(2.5)` reads as a sentence: this volunteer, log a
shift of 2.5 hours. Python passes `nadia` in as `self`, so
`self.hours = self.hours + length` changes *her* total and nothing
else. Call it on `rowan` and only Rowan's total moves. That separation
is the entire point of objects, and it is what three parallel lists
could never guarantee.

`__str__` is the method Python looks for when you `print` an object.
Delete it and `print(nadia)` produces something like
`<__main__.Volunteer object at 0x104a2d130>` — accurate, useless.
Writing `__str__` is a small kindness to whoever reads your output at
4 p.m. on a Friday.

> [!note] Why this program has no last names
> The club needs to know who is coming and how long they stayed. It
> does not need a birthdate, an address, or a student number, so those
> fields do not exist here and cannot leak from here. Deciding what
> *not* to store is a design decision you make on purpose, once, at
> the start — see [[Encapsulation]] and
> [[Ethics, Security, and the Profession]].

## Change it

1. **One line.** In `__str__`, change `{self.hours} h` to
   `{self.hours:.1f} h`. The output becomes `Nadia (Grade 12): 4.5 h`
   and `Rowan (Grade 11): 1.5 h` — and a volunteer with exactly two
   hours now reads `2.0 h` instead of `2 h`. Formatting belongs at the
   point of display, never in the stored value.
2. **A few lines.** Add a method that answers a question the
   coordinator actually asks:
   ```python
   def has_earned_reference(self):
       """True once this volunteer has served four hours or more."""
       return self.hours >= 4
   ```
   Then `print(nadia.has_earned_reference())` prints `True` and
   `print(rowan.has_earned_reference())` prints `False`. The rule now
   lives in one place; when the club raises the threshold to six
   hours, one line changes.
3. **A real change.** Give each volunteer a `self.shifts = []` in the
   constructor and have `log_shift` append the length as well as
   adding it to the total. `nadia.shifts` then holds `[2.5, 2]`, and
   `max(nadia.shifts)` gives `2.5`. An object can hold a list as
   easily as a number — which is exactly what [[Objects in a List]]
   turns around.

Read the idea in [[Objects and Classes]] and [[Attributes and Methods]],
then make it dependable in [[Classes and Objects Practice]].

%%curriculum-start%%
## Curriculum connection

![[C1.1]]

![[C1.2]]

![[A4.3]]
%%curriculum-end%%
