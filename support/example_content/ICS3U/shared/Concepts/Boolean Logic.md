---
title: Boolean Logic
publish: true
codeRunner: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
The eligibility rule sounded simple when the coach said it: a player
can travel if they are on the roster *and* the form is in. Written with
nested `if` statements it took six lines and still had a case nobody
had thought about. Conditions that combine deserve an operator, not a
staircase.

```python
if on_roster and form_returned:
    print("Cleared to travel.")
```

## The three operators

- `and` — `True` only when both sides are `True`.
- `or` — `True` when at least one side is `True`. This is not the
  everyday "or" that means one *or* the other but not both.
- `not` — flips the value.

| A | B | `A and B` | `A or B` | `not A` |
| --- | --- | --- | --- | --- |
| `True` | `True` | `True` | `True` | `False` |
| `True` | `False` | `False` | `True` | `False` |
| `False` | `True` | `False` | `True` | `True` |
| `False` | `False` | `False` | `False` | `True` |

Two lines of that table earn their keep constantly. Row 2 is why an
`and` with one missing form clears nobody. Row 3 is why an `or` written
where you meant `and` lets everybody through, and looks fine doing it.

## A Boolean is a value like any other

`True` and `False` are values with a type — `bool` — and comparisons
*produce* them. You can store one:

```python run readonly
days_late = 4
is_overdue = days_late > 0
print(is_overdue)
```

```
True
```

That is often the clearest thing you can do to a complicated condition:
give it a name. `if is_overdue and not renewed_recently:` reads like
the sentence the librarian actually said, and the names are checkable
by the person who said it.

Two more things worth knowing:

- `=` assigns, `==` compares. `if mark = 80:` is a syntax error, which
  is Python doing you a favour.
- `and` stops as soon as it meets a `False`. That is why
  `if sessions > 0 and minutes / sessions > 30:` is safe: when
  `sessions` is `0`, Python never evaluates the division, and the
  `ZeroDivisionError` never happens.

## The trap that reads perfectly

```python run readonly
day = "Mon"

if day == "Sat" or "Sun":
    print("Weekend!")
```

That prints `Weekend!` on a Monday. Python reads it as
`(day == "Sat") or ("Sun")`, and a non-empty string counts as `True`,
so the whole condition is always `True`. English collapses the repeated
"day is"; Python does not. Write it as:

```python
if day == "Sat" or day == "Sun":
```

Every comparison needs both of its sides, every time. This bug is a
regular guest in [[Spot the Bug]] because it survives a casual reading
so well.

## Untangling a negative

`not (on_roster and form_returned)` and
`(not on_roster) or (not form_returned)` are the same condition — "one
of the two is missing". Given the choice, write the version a human can
say out loud, and use brackets whenever the reader might have to think.
Nobody has ever complained about a condition being too clear.

Drill the combinations in [[Boolean Logic Practice]], and try defending
one of these operators in [[Which One Doesn't Belong]]. The third
"change it" in [[Branching Programs]] is the first place a compound
condition does real work for somebody.

%%curriculum-start%%
## Curriculum connection

![[A1.1]]

![[A1.4]]

![[A2.2]]
%%curriculum-end%%
