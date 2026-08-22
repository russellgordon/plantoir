---
title: Objects Working Together
publish: true
created: __CREATED__
tags:
  - concepts
---
The double-booking bug in the room sheet came back the week after we
fixed it, in a new disguise. This time the class was fine: `Booking`
knew its room, its purpose, its hour. What nobody owned was the
question "does this booking clash with one we already have?" — so it
was asked in three different places, in three slightly different ways,
and one of them forgot to check the hour.

One class models one thing. Real programs need several, and the
interesting design work is deciding **which object is responsible for
which question**.

## Give every fact and every question an owner

```python
class Booking:
    """One room booking at the community centre."""

    def __init__(self, room, purpose, people, hour):
        self.room = room
        self.purpose = purpose
        self.people = people
        self.hour = hour

    def clashes_with(self, other):
        """True when two bookings want the same room in the same hour."""
        return self.room == other.room and self.hour == other.hour

    def __str__(self):
        return f"{self.hour}:00 {self.room} - {self.purpose} ({self.people})"


class Schedule:
    """A day's bookings for the whole centre."""

    def __init__(self, day):
        self.day = day
        self.bookings = []

    def add(self, booking):
        """Add a booking unless it clashes with one already accepted."""
        for existing in self.bookings:
            if booking.clashes_with(existing):
                return False
        self.bookings.append(booking)
        return True
```

```python
tuesday = Schedule("Tuesday")
print(tuesday.add(Booking("Room 2", "math tutoring", 12, 16)))
print(tuesday.add(Booking("Hall", "community choir", 24, 19)))
print(tuesday.add(Booking("Room 2", "chess club", 8, 16)))
print(tuesday.add(Booking("Room 2", "chess club", 8, 18)))
print(tuesday)
```

```text
True
True
False
True
Tuesday: 3 bookings
```

Two classes, two responsibilities, and neither one duplicated. Whether
*two bookings* clash is a question about a booking, so `Booking`
answers it. Whether a *new booking is allowed today* is a question
about the whole day, so `Schedule` answers it — by asking each booking
in turn. The clash rule now exists once. Change it to include a
fifteen-minute changeover and every caller gets the new rule for free.

That handing-off has a name: **delegation**. `Schedule.add` does not
compare rooms and hours itself. It asks the objects that know.

## CRC cards: three questions per class

Before writing any of that, professionals sketch one index card per
class — Class, Responsibilities, Collaborators. It takes ten minutes
and saves an afternoon:

```text
+--------------------------------------------------+
| Booking                                          |
+---------------------------+----------------------+
| knows room, purpose,      | Collaborators:       |
|   people, hour            |   (none)             |
| says whether it clashes   |                      |
|   with another booking    |                      |
+---------------------------+----------------------+

+--------------------------------------------------+
| Schedule                                         |
+---------------------------+----------------------+
| holds one day's bookings  | Collaborators:       |
| accepts or refuses a new  |   Booking            |
|   booking                 |                      |
| reports the busiest hour  |                      |
+---------------------------+----------------------+
```

Cards make a bad design visible early. If one card fills up and the
others are blank, you have written a program with a single god-class
and some decoration. If two cards both claim the same responsibility,
you have found your next bug before writing it. A UML class diagram
says the same thing more formally, and
[[C1.1|the design expectation]] accepts either.

## Has-a, not just knows-about

`Schedule` **has** bookings: the list is inside it, and if the
schedule is discarded, so are they. This is composition, and it is the
most common relationship you will build.

The other shape is a link in both directions, which is what
[[A Program with Two Classes]] shows: a `Tool` holds a reference to
the `Borrower` who has it, and that `Borrower` holds the `Tool` in a
list. Powerful and dangerous in equal measure — if one side is updated
and the other is not, the program believes two contradictory things
and cheerfully prints both.

> [!important] Update both halves in one method, or you will not update both
> Whenever two objects point at each other, exactly one method should
> be allowed to change the relationship, and it must set both ends.
> In the tool library that method is `borrow`. The moment a second
> place in the program starts assigning `tool.held_by` directly, the
> halves will disagree — usually on a Saturday, in front of somebody
> who drove across town for a drill.

Objects that collaborate are also objects you can test separately: a
`Booking` can be checked without any `Schedule` in sight, which is
half of what makes [[Testing and Regression]] practical.

Build the two-class version in [[A Program with Two Classes]], read
the ideas underneath it in [[Objects and Classes]], and practise in
[[Classes and Objects Practice]]. When you inherit somebody else's
multi-class program — as in [[The Inherited Program]] — the fastest
way in is to draw its CRC cards from the code, and
[[Reading Somebody Else's Code]] explains why that works.

%%curriculum-start%%
## Curriculum connection

![[C1.1]]

![[A2.1]]

![[C1.4]]
%%curriculum-end%%
