---
title: Testing and Regression
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
The hold list had a bug: the front desk could add the same person
twice. Somebody fixed it in four minutes, ran the program, watched it
refuse a duplicate, and pushed the change. Two days later the library
noticed that holds were coming out in the wrong order. The fix was
correct. It had also quietly broken something nobody thought to check,
because "I ran it and it looked fine" tests exactly one path through
the program — the one you were already thinking about.

A test is that check, written down once and run for ever after, by
anybody, including people who have never heard of the bug you were
fixing.

## A test is a claim about behaviour

Here is a small module worth protecting:

```python
def next_in_line(holds):
    """Return the name at the front of the hold list, or None if empty."""
    if len(holds) == 0:
        return None
    return holds[0]


def add_hold(holds, name):
    """Add a name to the back of the hold list. Refuse duplicates."""
    if name in holds:
        return False
    holds.append(name)
    return True
```

And its tests, using `unittest` from the standard library:

```python
import unittest

from holds import next_in_line, add_hold


class TestHolds(unittest.TestCase):

    def test_front_of_a_normal_list(self):
        self.assertEqual(next_in_line(["Nadia", "Rowan"]), "Nadia")

    def test_empty_list_has_nobody(self):
        self.assertIsNone(next_in_line([]))

    def test_adding_returns_true(self):
        holds = ["Nadia"]
        self.assertTrue(add_hold(holds, "Rowan"))
        self.assertEqual(holds, ["Nadia", "Rowan"])

    def test_duplicate_is_refused(self):
        holds = ["Nadia"]
        self.assertFalse(add_hold(holds, "Nadia"))
        self.assertEqual(holds, ["Nadia"])


if __name__ == "__main__":
    unittest.main()
```

```text
....
----------------------------------------------------------------------
Ran 4 tests in 0.000s

OK
```

Four dots, four claims, no drama. Each test name is a sentence about
what the code promises: the front of a normal list is the first name;
an empty list has nobody; adding returns `True` and puts the name at
the back; a duplicate is refused *and leaves the list alone*. That
last assertion is the one beginners omit and the one that catches real
bugs.

Notice what the tests are checking: the **postconditions** from each
docstring. Writing the docstring properly and writing the test are
nearly the same act, done twice — which is why
[[C2.1|the pre- and postcondition expectation]] and
[[A4.2|the testing expectation]] tend to be earned together.

## What a failure looks like

Suppose somebody "tidies" `add_hold` to use `holds.insert(0, name)`.
The program still runs. The tests do not:

```text
F...
======================================================================
FAIL: test_adding_returns_true (__main__.TestHolds.test_adding_returns_true)
----------------------------------------------------------------------
Traceback (most recent call last):
  File ".../test_holds.py", line 17, in test_adding_returns_true
    self.assertEqual(holds, ["Nadia", "Rowan"])
    ~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^
AssertionError: Lists differ: ['Rowan', 'Nadia'] != ['Nadia', 'Rowan']

First differing element 0:
'Rowan'
'Nadia'

- ['Rowan', 'Nadia']
+ ['Nadia', 'Rowan']

----------------------------------------------------------------------
Ran 4 tests in 0.000s

FAILED (failures=1)
```

The `F` is the failing test, the dots are the three that still pass,
and the report names the file, the line, the expectation, and the
actual value. Nine seconds, and you know precisely what you broke.
Without the tests, that bug reaches the library and is reported by a
student later in the course as "the list is weird".

## Regression: the tests that stop bugs coming back

A **regression** is an old bug that returns, or a working feature that
a new change quietly breaks. The habit that prevents it is a rule, not
a tool:

> [!important] Every bug becomes a test, before it is fixed
> When somebody reports a bug, write the failing test first. Watch it
> fail — that proves the test can detect the problem. Then fix the
> code and watch it pass. The test stays in the suite for ever, and
> that particular bug can never return without somebody being told
> immediately.

Run the whole suite, not just the new test, every time. That is what
makes it a regression suite: the four tests you wrote weeks ago are
what tell you a year from now that today's improvement was safe.

## A testing plan you can actually hand in

[[A4.2|The formal testing plan expectation]] asks for three kinds of
test, and your project needs all three:

- [ ] **Unit tests** — one function or method, in isolation. Normal
      input, edge cases (empty, one item, the boundary), and the case
      that should be refused.
- [ ] **Integration tests** — two or more parts together. Does the
      front desk still work when `Queue` and `Hold` are combined?
- [ ] **Regression tests** — one per bug ever found, kept for ever.
- [ ] **A record of what you ran and what happened**, dated. A plan
      nobody executed is a wish.

Choosing cases is where the thinking is. For a hold list: empty, one
name, a duplicate, a name with different capitalisation, a very long
name, a name that is not a string at all. Ask "what would a tired
person at a front desk actually type?" — the answers are your test
cases, and they are more imaginative than anything you would invent
from the code alone.

> [!tip] Testing code you did not write is the fastest way to read it
> When you inherit a program, write tests for what you *think* it
> does. The ones that fail have just taught you what it really does —
> and the suite you built is the safety net that makes changing it
> possible. That is the whole method behind
> [[The Maintenance Sprint]], and it is why
> [[Reading Somebody Else's Code]] tells you to run it before you read
> it.

The mechanics of writing and running a suite are in
[[Writing Tests]]; the drill on edge cases lives in
[[Spot the Bug]].

%%curriculum-start%%
## Curriculum connection

![[A4.2]]

![[C2.1]]

![[A2.3]]
%%curriculum-end%%
