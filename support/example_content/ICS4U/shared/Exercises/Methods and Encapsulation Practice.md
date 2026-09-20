---
title: Methods and Encapsulation Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Attributes and Methods]] and
[[Encapsulation]]. A method is where a rule lives; encapsulation is
the practice of making that the *only* place it lives, and of being
honest about how much Python will help you.

> [!warning] Python does not enforce privacy
> Several answers below depend on this being said plainly: a single
> leading underscore is a convention, and a double underscore is name
> mangling. Neither one stops anybody. If an answer here claims
> otherwise, it is wrong.

## Reading and fixing

1. In `card.use()`, what is `self`? Explain what Python does with the
   object between the dot and the parenthesis.
2. **Predict the output**, all three lines.
   ```python
   class Shift:
       def __init__(self, volunteer, hours):
           self.volunteer = volunteer
           self.hours = hours

       def extend(self, extra):
           hours = self.hours + extra

       def describe(self):
           print(f"{self.volunteer}: {self.hours} h")

   s = Shift("Nadia", 2)
   s.extend(1.5)
   s.describe()
   print(s.describe())
   ```
3. Rewrite `describe` so that it can be used in a report, an email,
   and a test — and say why that is better than printing.
4. This line appears in a teammate's file: `card._visits_left = 99`.
   The code runs. Explain what the underscore means, what Python does
   about it, and what you would write in the review.

## Writing

5. Write a `PunchCard` class for the drop-in gym: an `owner`, a
   private-by-convention `_visits_left`, a `top_up(visits)` that
   refuses zero or negative amounts, a `use()` that returns `False`
   on an empty card, and a `visits_left()` reader. Show it running out
   and being topped up.
6. Here is a class with a rule that can be bypassed. Encapsulate it,
   and show the refused change:
   ```python
   class Booking:
       def __init__(self, room, people):
           self.room = room
           self.people = people   # must be 1 to 30
   ```
7. **Extend somebody else's code.** You did not write this class and
   may not change what is already there. Add `is_long()`, which is
   true for shifts of three hours or more, and `split()`, which
   returns two shifts of half the length.
   ```python
   class Shift:
       """One volunteer shift at the homework club."""

       def __init__(self, volunteer, hours):
           self.volunteer = volunteer
           self.hours = hours

       def __str__(self):
           return f"{self.volunteer}: {self.hours} h"
   ```
8. What does a double leading underscore actually do? Demonstrate it,
   including the way around it.
9. **Judgement.** For a `Member` class holding `name`,
   `_visits_left`, `_emergency_contact`, and `joined_on`, say which
   attributes deserve the underscore and why. Then say which one you
   would argue for not storing at all.

## Answers

> [!success]- Answer 1
> `self` is the `PunchCard` object that `card` refers to. Python turns
> `card.use()` into `use(card)`, so every `self.something` inside the
> method reads or writes *that* card's attributes. It is an ordinary
> parameter with a conventional name, not a keyword — which is why
> forgetting it produces a `TypeError` about argument counts rather
> than a mysterious failure.

> [!success]- Answer 2
> ```text
> Nadia: 2 h
> Nadia: 2 h
> None
> ```
> `extend` computes `self.hours + extra` and stores it in a **local**
> variable called `hours`, which disappears when the method ends. The
> object is untouched. The fix is `self.hours = self.hours + extra`.
> The third line is `None` because `describe` prints and returns
> nothing, so `print(s.describe())` prints the description and then
> prints the absence of a return value.

> [!success]- Answer 3
> ```python
> def describe(self):
>     """Return a one-line description of this shift."""
>     return f"{self.volunteer}: {self.hours} h"
> ```
> A method that returns can be printed, written to a file, put in an
> email, or compared in a test:
> `self.assertEqual(s.describe(), "Nadia: 3.5 h")`. A method that
> prints can only ever do the one thing, and cannot be tested without
> capturing output. Better still, write it as `__str__` so that
> `print(s)` works and the class has one printable form.

> [!success]- Answer 4
> The underscore is a message from the author of the class: *this is
> internal, do not touch it, I may rename it tomorrow*. Python does
> nothing at all about it — the assignment runs, the card now claims
> 99 visits, and every rule in `top_up` and `use` has been bypassed.
> A useful review comment names the rule rather than the person:
> "This writes to `PunchCard._visits_left` directly, which skips the
> checks in `top_up`. Can we add a `top_up(99)` call, or a method for
> whatever case this is?" See [[Read the Diff]] for the rest of that
> conversation.

> [!success]- Answer 5
> ```python
> class PunchCard:
>     """A prepaid card for the community centre's drop-in gym."""
>
>     def __init__(self, owner, visits):
>         self.owner = owner
>         self._visits_left = 0
>         self.top_up(visits)
>
>     def top_up(self, visits):
>         """Add visits to the card. Refuse zero or negative top-ups."""
>         if visits <= 0:
>             return False
>         self._visits_left = self._visits_left + visits
>         return True
>
>     def use(self):
>         """Use one visit. Return False when the card is empty."""
>         if self._visits_left == 0:
>             return False
>         self._visits_left = self._visits_left - 1
>         return True
>
>     def visits_left(self):
>         """How many visits remain on this card."""
>         return self._visits_left
>
>     def __str__(self):
>         return f"{self.owner}: {self._visits_left} visits left"
>
>
> card = PunchCard("Bea", 3)
> print(card)
> print(card.use(), card.use(), card.use(), card.use())
> print(card)
> print(card.top_up(-5))
> print(card.top_up(5))
> print(card)
> ```
> ```text
> Bea: 3 visits left
> True True True False
> Bea: 0 visits left
> False
> True
> Bea: 5 visits left
> ```
> `__init__` calls `top_up` rather than assigning directly, so there
> is exactly one gate and even the constructor goes through it.

> [!success]- Answer 6
> ```python
> class Booking:
>     """One room booking at the community centre."""
>
>     def __init__(self, room, people):
>         self.room = room
>         self._people = 0
>         self.set_people(people)
>
>     def set_people(self, people):
>         """Set the group size. Refuse anything outside 1 to 30."""
>         if people < 1 or people > 30:
>             return False
>         self._people = people
>         return True
>
>     def people(self):
>         """How many people this booking is for."""
>         return self._people
>
>
> b = Booking("Hall", 24)
> print(b.people(), b.set_people(40), b.people())
> ```
> ```text
> 24 False 24
> ```
> The refused change leaves the booking exactly as it was — no
> half-applied update, no clamping to 30, no silent invention of a
> number nobody asked for.

> [!success]- Answer 7
> ```python
>     def is_long(self):
>         """True when this shift ran for three hours or more."""
>         return self.hours >= 3
>
>     def split(self):
>         """Return two shifts of half the length each."""
>         half = self.hours / 2
>         return Shift(self.volunteer, half), Shift(self.volunteer, half)
> ```
> ```text
> True
> Ali: 2.5 h | Ali: 2.5 h
> ```
> Two things make this a good extension of code you did not write. It
> uses the existing `__init__` to build the new shifts rather than
> assembling them by hand, so any future rule in the constructor
> applies to them. And it changes nothing that was already there, so
> every existing caller behaves exactly as before — which is what
> [[Testing and Regression]] would check first.

> [!success]- Answer 8
> Two leading underscores trigger **name mangling**: inside the class
> the attribute is renamed to `_ClassName__attribute`.
> ```python
> class Card:
>     def __init__(self):
>         self.__pin = 1234
>
>
> c = Card()
> print(c._Card__pin)
> ```
> ```text
> 1234
> ```
> Asking for `c.__pin` instead raises
> `AttributeError: 'Card' object has no attribute '__pin'`, which
> looks like privacy and is not: the value is one predictable name
> away. Mangling exists so that a subclass cannot accidentally reuse
> a name the parent class is relying on. Use it for that; do not
> claim it hides anything.

> [!success]- Answer 9
> `name` and `joined_on` are ordinary facts the rest of the program
> legitimately reads, so no underscore. `_visits_left` has rules
> attached — it must never go negative, and it changes only through
> `use` and `top_up` — so it earns one. `_emergency_contact` earns one
> for a different reason: it should be reachable only through a method
> you could put a check in, and every access is a place a mistake
> becomes a harm.
>
> The one to argue about is `_emergency_contact` itself. A drop-in gym
> card does not need it; a residential outdoor-education program
> plainly does. If the centre cannot say what it would do with the
> field, the safest version of that data is the version you never
> collected — the argument in
> [[Ethics, Security, and the Profession]].

%%curriculum-start%%
## Curriculum connection

![[A2.2]]

![[A4.3]]

![[C1.2]]

![[C1.4]]
%%curriculum-end%%

