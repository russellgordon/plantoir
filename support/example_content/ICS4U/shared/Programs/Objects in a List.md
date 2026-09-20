---
title: Objects in a List
publish: true
created: __CREATED__
tags:
  - programs
---
One `Volunteer` object is tidy. The homework club has fourteen, and
the coordinator's questions are always about all of them at once: how
many are we, how many hours in total, who has done the most, and can
you take Ali off the list because he graduated at the end of the course.

A list of objects answers all four. Each item in the list is a whole
volunteer — name, grade, and hours travelling together — and the
functions below never touch an attribute they were not asked about.

## The program

```python
# Roster for the homework club. One list holds every volunteer, and
# each volunteer is an object, so the whole club can be counted,
# searched, added to, and printed with a few short functions.

class Volunteer:
    """One person who has signed up to help at the homework club."""

    def __init__(self, name, grade):
        self.name = name
        self.grade = grade
        self.hours = 0

    def log_shift(self, length):
        """Add one completed shift, in hours, to this volunteer."""
        self.hours = self.hours + length

    def __str__(self):
        return f"{self.name} (Grade {self.grade}): {self.hours} h"


def find_volunteer(roster, name):
    """Return the Volunteer with this name, or None if nobody matches."""
    for volunteer in roster:
        if volunteer.name == name:
            return volunteer
    return None


def add_volunteer(roster, name, grade):
    """Add a new volunteer to the end of the roster and return them."""
    newcomer = Volunteer(name, grade)
    roster.append(newcomer)
    return newcomer


def remove_volunteer(roster, name):
    """Remove the named volunteer. Return True if somebody was removed."""
    leaving = find_volunteer(roster, name)
    if leaving is None:
        return False
    roster.remove(leaving)
    return True


def total_hours(roster):
    """Return the hours served by everybody on the roster."""
    total = 0
    for volunteer in roster:
        total = total + volunteer.hours
    return total


def busiest(roster):
    """Return the volunteer with the most hours, or None on an empty roster."""
    if len(roster) == 0:
        return None
    leader = roster[0]
    for volunteer in roster:
        if volunteer.hours > leader.hours:
            leader = volunteer
    return leader


def show(roster):
    """Print the whole roster, one volunteer per line."""
    for volunteer in roster:
        print(f"  {volunteer}")


roster = []
add_volunteer(roster, "Nadia", 12)
add_volunteer(roster, "Rowan", 11)
add_volunteer(roster, "Ali", 12)
add_volunteer(roster, "Bea", 10)

find_volunteer(roster, "Nadia").log_shift(4.5)
find_volunteer(roster, "Rowan").log_shift(1.5)
find_volunteer(roster, "Ali").log_shift(6)
find_volunteer(roster, "Bea").log_shift(2)

print("Homework club roster")
show(roster)
print(f"Volunteers: {len(roster)}")
print(f"Total hours: {total_hours(roster)}")
print(f"Most hours: {busiest(roster).name}")

print()
print("Ali has graduated and asked to be taken off the list.")
print(f"Removed: {remove_volunteer(roster, 'Ali')}")
print(f"Removed again: {remove_volunteer(roster, 'Ali')}")
show(roster)
print(f"Total hours: {total_hours(roster)}")
```

```text
Homework club roster
  Nadia (Grade 12): 4.5 h
  Rowan (Grade 11): 1.5 h
  Ali (Grade 12): 6 h
  Bea (Grade 10): 2 h
Volunteers: 4
Total hours: 14.0
Most hours: Ali

Ali has graduated and asked to be taken off the list.
Removed: True
Removed again: False
  Nadia (Grade 12): 4.5 h
  Rowan (Grade 11): 1.5 h
  Bea (Grade 10): 2 h
Total hours: 8.0
```

## How it works

`roster` is an ordinary list. What is new is that every item in it is
an object, so `volunteer.hours` works inside any loop over the list —
one name, one dot, and the right person's total.

`find_volunteer` is the pattern everything else is built on. It walks
the list, compares names, and returns the **object** rather than a
position. That is why the four `log_shift` lines read the way they do:
`find_volunteer(roster, "Nadia").log_shift(4.5)` finds Nadia and
immediately tells her to log a shift. Returning `None` when nobody
matches is a deliberate choice — a caller can test for it, which a
crash does not allow.

`add_volunteer` and `remove_volunteer` are the insert and delete pair
that any list of records needs. `remove_volunteer` reuses
`find_volunteer` instead of writing a second search, and reports
`True` or `False` so the caller knows whether anything happened. The
second call returns `False` because Ali is already gone: removing
somebody twice is not an error, it is just a no-op, and saying so
plainly beats crashing on a coordinator's double-click.

`busiest` starts its record at `roster[0]`, not at `0` hours. Starting
at zero would be fine here, but on a roster where everybody has
negative or missing values it would report a leader nobody is — the
same trap as tracking a minimum. Start comparisons at a value that is
actually in the data.

> [!question]- Self-check: why is the first total `14.0` and not `14`?
> (click to expand)
> Ali's shift was logged as `6` — an integer — while Nadia's was
> `4.5`. Add an integer to a float in Python and the answer is a
> float, so `total` becomes `14.0` as soon as a decimal joins in. It
> is not wrong, but it is a mixed-type total, and the way to control
> how it *looks* is to format at the point of printing:
> `f"{total_hours(roster):.1f}"`.

## Change it

1. **One line.** Add `add_volunteer(roster, "Sam", 11)` after Bea.
   `Volunteers:` becomes `5` while `Total hours:` stays `14.0` — Sam
   has not worked a shift yet, and nothing else in the program needed
   changing to accommodate him.
2. **A few lines.** Write `average_hours(roster)` that reuses
   `total_hours` and guards against an empty roster:
   ```python
   def average_hours(roster):
       """Return the mean hours served, or 0.0 for an empty roster."""
       if len(roster) == 0:
           return 0.0
       return total_hours(roster) / len(roster)
   ```
   With Sam added, `f"{average_hours(roster):.1f}"` prints `2.8`.
   Without the guard, an empty roster gives
   `ZeroDivisionError: division by zero` — on the first Tuesday of
   the year, in front of the coordinator.
3. **A real change.** Make the roster survive being closed. Write
   `save_roster(roster, filename)` that writes one line per volunteer
   as `name,grade,hours`, and a matching `load_roster(filename)` that
   builds `Volunteer` objects back out of those lines. Saving the
   roster above produces exactly:
   ```text
   Nadia,12,4.5
   Rowan,11,1.5
   Ali,12,6
   Bea,10,2
   Sam,11,0
   ```
   Loading is the harder half, because every field arrives as text and
   `grade` and `hours` have to be converted back. That conversion
   problem is the whole subject of [[Using a Dictionary]].

The idea behind this program is in [[Objects and Classes]]; the
practice is in [[Classes and Objects Practice]]. When your loop over
the roster does the wrong thing, [[Trace It]] is the routine that
finds out where.

%%curriculum-start%%
## Curriculum connection

![[A1.5]]

![[A3.3]]

![[C1.1]]
%%curriculum-end%%
