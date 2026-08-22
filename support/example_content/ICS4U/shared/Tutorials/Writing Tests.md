---
title: Writing Tests
publish: true
created: __CREATED__
tags:
  - tutorials
enableToc: true
---
"I ran it and it worked" is a claim about one input, on one machine,
at one moment, made by the person least able to be objective about
it. A test is the same claim written down so that a machine can check
it, so that a stranger can see what you actually promised, and so
that it can be checked again next week after somebody else changes
something.

That last part is the reason tests exist. You are on a team now.
Somebody will edit your function.

## Start with `assert`

The simplest test in Python is a sentence that must be true. Here is
a function from a booking program, exactly as it was inherited:

```python
def spaces_left(capacity, booked):
    """Return how many spaces remain in a session."""
    return capacity - booked
```

And here are three claims about it, in a separate file:

```python
from bookings import spaces_left

assert spaces_left(10, 3) == 7
assert spaces_left(10, 10) == 0
assert spaces_left(10, 12) == 0
print("All checks passed.")
```

Run it. The third claim is a lie:

```text
Traceback (most recent call last):
  File "/home/student/check_bookings.py", line 5, in <module>
    assert spaces_left(10, 12) == 0
           ^^^^^^^^^^^^^^^^^^^^^^^^
AssertionError
```

An `assert` that holds does nothing at all — silence is a pass. An
`assert` that fails stops the program and names the line. Two lines
of setup, and you have found a real bug: an overbooked session
reports a negative number of free spaces, which will eventually be
printed to somebody as "-2 spaces available".

> [!note] What `assert` will not tell you
> `AssertionError` on its own does not say what the value *was*. For
> quick checks that is fine. The moment you want the actual number in
> the message, move to `unittest`.

## `unittest`, for tests you keep

Once tests are worth keeping, they need names, and they need to all
run even when one fails. Python's standard library has that built in.
Save this as `test_bookings.py`:

```python
import unittest

from bookings import spaces_left


class TestSpacesLeft(unittest.TestCase):

    def test_ordinary_session(self):
        self.assertEqual(spaces_left(10, 3), 7)

    def test_exactly_full(self):
        self.assertEqual(spaces_left(10, 10), 0)

    def test_overbooked_never_goes_negative(self):
        self.assertEqual(spaces_left(10, 12), 0)


if __name__ == "__main__":
    unittest.main()
```

Three rules and you can write these: the file name starts with
`test_`, the class inherits from `unittest.TestCase`, and every
method whose name starts with `test_` is a separate test. Run it
with `python3 -m unittest test_bookings -v`:

```text
test_exactly_full (test_bookings.TestSpacesLeft.test_exactly_full) ... ok
test_ordinary_session (test_bookings.TestSpacesLeft.test_ordinary_session) ... ok
test_overbooked_never_goes_negative (test_bookings.TestSpacesLeft.test_overbooked_never_goes_negative) ... FAIL

======================================================================
FAIL: test_overbooked_never_goes_negative (test_bookings.TestSpacesLeft.test_overbooked_never_goes_negative)
----------------------------------------------------------------------
Traceback (most recent call last):
  File "/home/student/test_bookings.py", line 15, in test_overbooked_never_goes_negative
    self.assertEqual(spaces_left(10, 12), 0)
AssertionError: -2 != 0

----------------------------------------------------------------------
Ran 3 tests in 0.001s

FAILED (failures=1)
```

Look at the difference `unittest` bought. The two good tests still
ran. The failure has a *name* that says what was expected, and the
message is `-2 != 0` — the actual value, not just "something was
false". You now know the bug without opening the program.

## The fix, and the proof

```python
def spaces_left(capacity, booked):
    """Return how many spaces remain, never fewer than zero."""
    remaining = capacity - booked
    if remaining < 0:
        remaining = 0
    return remaining
```

Run the same tests again, unchanged:

```text
...
----------------------------------------------------------------------
Ran 3 tests in 0.000s

OK
```

Three dots, one per test, and `OK`. Notice the order of operations:
the test failed *first*, then the code changed, then the test passed.
A test you write after the fix, and that has never once failed, has
proved nothing — it might be testing nothing at all. Watch every new
test fail at least once.

## Regression testing, honestly

A **regression** is something that used to work and stopped. The test
you just wrote is now permanent: every time anyone on your team
changes `bookings.py`, that overbooked case gets checked again for
free, forever, without anyone remembering it exists. That is the
entire deal, and it is why the tests are worth more than the hour
they cost.

Be honest about the limits, though:

- **Passing tests do not mean the program is correct.** They mean the
  cases you thought of behave as you expected. Testing can show the
  presence of bugs, never their absence.
- **The bugs that survive are the ones nobody imagined.** Which is
  why the most productive thing you can do is have a *teammate* write
  tests for your function. They will try things you consider absurd,
  and one of them will fail.
- **A test that is wrong is worse than no test.** It gives false
  confidence and eventually gets "fixed" by changing the code to
  match. Read a failing test carefully before assuming the code is
  the guilty party.
- **Tests are code**, so they need to be readable and they need
  maintaining. `test_overbooked_never_goes_negative` says what it
  protects; `test_3` says nothing to the person who inherits it.

## What to test, when you have ten minutes

Not everything. Start here, in this order:

1. **The ordinary case**, so you know the function works at all.
2. **The boundaries** — zero, empty, one item, exactly full, the last
   position in the list. Almost every off-by-one in
   [[Spot the Bug]] dies here.
3. **The case that already broke once.** Every bug you fix earns a
   test, on the day you fix it. That is the cheapest test you will
   ever write and the one most likely to save you.
4. **What you promised in the docstring.** If it says "never fewer
   than zero", there should be a test with that name.

> [!tip] Write the test the bug reporter would have written
> When your community partner says "it did something strange when the
> session was full", the first move is not to open the code. It is to
> write a failing test that reproduces what they described. Now the
> complaint is a fact, the fix has a finish line, and the thing they
> noticed can never quietly come back.

The idea behind all of this, including what regression means for a
project after you have gone, is [[Testing and Regression]]. When a
test tells you something is wrong but not why, the next page is
[[Reading a Traceback in Someone Else's Code]].

%%curriculum-start%%
## Curriculum connection

![[A2.3]]

![[A4.2]]

![[C2.1]]
%%curriculum-end%%
