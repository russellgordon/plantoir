---
title: Classes and Objects Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Objects and Classes]] and
[[Objects Working Together]]. A class describes a kind of thing; an
object is one actual thing; and the interesting work is deciding which
class is responsible for which fact.

## Reading

1. Name each part of this line, and say what it produces:
   `guide = Book("Exam Study Guide", "M. Okonjo", 1)`.
2. **Predict the output.**
   ```python
   class Locker:
       def __init__(self, number):
           self.number = number
           self.assigned_to = None

   a = Locker(101)
   b = Locker(101)
   print(a.number == b.number)
   print(a == b)
   a.assigned_to = "Nadia"
   print(b.assigned_to)
   ```
3. **Find the fault.** `t.is_available()` fails. Why, and what is the
   one-word fix?
   ```python
   class Tool:
       def __init__(self, name):
           self.name = name
           self.held_by = None

       def is_available():
           return self.held_by is None
   ```
4. **Find the fault.** `print(t.name)` fails on this class. What went
   wrong, and what does Python say?
   ```python
   class Tool:
       def __init__(self, name):
           name = name
   ```

## Writing

5. Write a `Book` class for the school library with `title`,
   `author`, and `copies`. Give it a `lend()` method that removes one
   copy and returns `True`, or returns `False` when none are left, and
   a `__str__` that prints like
   `Exam Study Guide by M. Okonjo (1 on the shelf)`.
6. Using this catalogue, write `titles_on_the_shelf(catalogue)` and
   `total_copies(catalogue)`:

   | Title | Author | Copies |
   | --- | --- | --- |
   | Exam Study Guide | M. Okonjo | 1 |
   | Short Stories | L. Tran | 4 |
   | Data Structures | R. Whyte | 0 |

7. Add a `Member` class with a `name` and a list of `borrowed` books,
   and a `borrow(book)` method that succeeds only if the book has a
   copy free. Show Rowan borrowing *Short Stories* and print both
   objects afterwards.
8. **Design, no code.** A community centre wants a program for its
   Saturday drop-in program: people sign in, join one activity, and
   sign out. Write CRC cards for the classes you would create — name,
   responsibilities, collaborators. Then defend one noun you decided
   *not* to make a class.

## Answers

> [!success]- Answer 1
> `Book` is the class; `Book(...)` calls the constructor, which builds
> a new object and runs `__init__` on it; `"Exam Study Guide"`,
> `"M. Okonjo"`, and `1` are arguments matched to the parameters
> `title`, `author`, and `copies`; and `guide` is a name now referring
> to that one object. Leave an argument out and Python is precise:
> ```text
> TypeError: Book.__init__() missing 1 required positional argument: 'copies'
> ```

> [!success]- Answer 2
> ```text
> True
> False
> None
> ```
> `a` and `b` have equal `number` attributes, so the first line is
> `True`. They are still two separate objects, and `==` without a
> `__eq__` method compares identity, so the second is `False`.
> Assigning to `a.assigned_to` changes only `a` — which is exactly the
> separation you wanted when you chose a class. Two lockers can share
> a number and still be different lockers.

> [!success]- Answer 3
> The method is missing `self`. Every method's first parameter is the
> object it was called on, and Python passes it in whether or not you
> declared it:
> ```text
> TypeError: Tool.is_available() takes 0 positional arguments but 1 was given
> ```
> Read that message carefully — "1 was given" is the object itself.
> Fix:
> ```python
> def is_available(self):
>     return self.held_by is None
> ```

> [!success]- Answer 4
> `name = name` assigns a local parameter to itself and then throws it
> away when `__init__` ends. Nothing is ever stored on the object:
> ```text
> AttributeError: 'Tool' object has no attribute 'name'
> ```
> The missing three characters are `self.`:
> ```python
> def __init__(self, name):
>     self.name = name
> ```
> An attribute exists only once something has been assigned to
> `self.something`.

> [!success]- Answer 5
> ```python
> class Book:
>     """One book in the school library's catalogue."""
>
>     def __init__(self, title, author, copies):
>         self.title = title
>         self.author = author
>         self.copies = copies
>
>     def lend(self):
>         """Lend one copy. Return False if none are on the shelf."""
>         if self.copies == 0:
>             return False
>         self.copies = self.copies - 1
>         return True
>
>     def __str__(self):
>         return f"{self.title} by {self.author} ({self.copies} on the shelf)"
>
>
> guide = Book("Exam Study Guide", "M. Okonjo", 1)
> print(guide)
> print(guide.lend())
> print(guide.lend())
> print(guide)
> ```
> ```text
> Exam Study Guide by M. Okonjo (1 on the shelf)
> True
> False
> Exam Study Guide by M. Okonjo (0 on the shelf)
> ```
> `lend` checks before it subtracts, so the count can never go
> negative. The rule now lives inside the class, where every caller
> gets it.

> [!success]- Answer 6
> ```python
> catalogue = [
>     Book("Exam Study Guide", "M. Okonjo", 1),
>     Book("Short Stories", "L. Tran", 4),
>     Book("Data Structures", "R. Whyte", 0),
> ]
>
>
> def titles_on_the_shelf(catalogue):
>     """Return the titles of every book with at least one copy left."""
>     available = []
>     for book in catalogue:
>         if book.copies > 0:
>             available.append(book.title)
>     return available
>
>
> def total_copies(catalogue):
>     """Return how many copies the library holds in all."""
>     total = 0
>     for book in catalogue:
>         total = total + book.copies
>     return total
>
>
> print(titles_on_the_shelf(catalogue))
> print(total_copies(catalogue))
> ```
> ```text
> ['Exam Study Guide', 'Short Stories']
> 5
> ```
> Both functions take the catalogue as a parameter rather than reading
> a global, so either can be tested on a list you invent.

> [!success]- Answer 7
> ```python
> class Member:
>     """One member of the school library."""
>
>     def __init__(self, name):
>         self.name = name
>         self.borrowed = []
>
>     def borrow(self, book):
>         """Borrow a book if a copy is free. Return True if it worked."""
>         if not book.lend():
>             return False
>         self.borrowed.append(book)
>         return True
>
>     def __str__(self):
>         return f"{self.name} has {len(self.borrowed)} book(s)"
>
>
> rowan = Member("Rowan")
> stories = catalogue[1]
> print(rowan.borrow(stories))
> print(rowan)
> print(stories)
> ```
> ```text
> True
> Rowan has 1 book(s)
> Short Stories by L. Tran (3 on the shelf)
> ```
> `borrow` delegates the "is a copy free?" question to the book, which
> is the class that owns the count. One rule, one home — and the
> member's list and the book's count can never disagree, because a
> single method changes both.

> [!success]- Answer 8
> A defensible set of cards:
> ```text
> Attendee    | knows name, contact for emergencies
>             | signs in and out
>             | collaborates with: Activity
>
> Activity    | knows name, capacity, leader
>             | accepts or refuses an attendee
>             | collaborates with: Attendee
>
> DropInDay   | knows the date and its activities
>             | reports who is present right now
>             | collaborates with: Activity, Attendee
> ```
> "Sign-in" is the noun most people want to make a class and usually
> should not: it is an *event*, better modelled as a method on
> `Attendee` plus a time stored somewhere. Making it a class is
> defensible if the centre needs the history of every sign-in — which
> is a question for the partner, not for you. Notice that the
> emergency contact appears on exactly one card, which is where the
> conversation about what you actually need to store belongs.

%%curriculum-start%%
## Curriculum connection

![[A1.5]]

![[A2.2]]

![[A4.3]]

![[C1.1]]

![[C1.4]]
%%curriculum-end%%

