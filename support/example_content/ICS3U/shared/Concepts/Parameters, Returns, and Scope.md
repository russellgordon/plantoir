---
title: Parameters, Returns, and Scope
publish: true
codeRunner: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
[[Functions]] gave the repeated chunk a name. The next hour produced
three complaints, all of them fair: the function needed *two* pieces of
information, not one; somebody wanted the answer stored rather than
printed; and a variable that clearly existed inside the function was
"not defined" the moment anyone tried to use it outside. Those three
complaints are this page.

## Handing information in

```python
def practice_summary(name, minutes, target=150):
    if minutes >= target:
        return f"{name}: {minutes} min — target met."
    short = target - minutes
    return f"{name}: {minutes} min — {short} short of target."
```

`name`, `minutes`, and `target` are **parameters** — names that exist
inside the function, filled in when somebody calls it. The values
supplied at the call are the **arguments**:

```python
print(practice_summary("Priya", 185))
print(practice_summary("Sam", 90))
print(practice_summary("Sam", 90, 60))
```

```
Priya: 185 min — target met.
Sam: 90 min — 60 short of target.
Sam: 90 min — target met.
```

Position decides which is which, so the order in the call must match
the order in the definition. `target=150` is a **default**: leave the
third argument out and the function supplies 150 itself, which is how
the same function serves a coach with one target and a club with
another. Leave out something with no default and Python says so
precisely:

```
TypeError: practice_summary() missing 1 required positional argument: 'minutes'
```

## Handing an answer back

`return` does two things at once: it hands a value to whoever called
the function, and it ends the function immediately. Both lines above
are `return` statements, and only one of them ever runs — the second
`return` is unreachable when the target is met.

That is the pattern called an **early return**, and it is usually
kinder to the reader than nesting the rest of the function inside an
`else`. A function stops at the first `return` it reaches, so put the
simple case first and let the rest of the body assume it is past.

## Where a variable lives

```python run readonly
def total_minutes(sessions):
    total = 0
    for value in sessions:
        total = total + value
    return total

total_minutes([45, 60])
print(total)
```

```
NameError: name 'total' is not defined
```

`total` is **local**: it is created when the function starts and gone
when it ends. That looks like an obstacle for about a day, and then it
turns into the reason functions are trustworthy. A local variable
cannot be quietly changed by another part of the program, and two
functions can both use a variable called `total` without ever colliding.
Anything the caller needs, the function `return`s.[^1]

## Functions built from functions

Once a function returns a value, other functions can use it — and that
is where a program starts to feel designed rather than typed:

```python run readonly
def as_hours_and_minutes(minutes):
    hours = minutes // 60
    rest = minutes % 60
    return f"{hours} h {rest} min"

def report(name, minutes):
    return f"{name} practised {as_hours_and_minutes(minutes)}."

print(report("Priya", 185))
```

```
Priya practised 3 h 5 min.
```

`as_hours_and_minutes` knows nothing about coaches, players, or
reports. That ignorance is the point: it is a piece you can lift into
the next program unchanged, which is what modularity actually buys you.

You are also standing on functions somebody else wrote — `len`, `abs`,
`round`, `max`, and, with an `import random` at the top,
`random.randint(1, 6)`. Before writing a helper, check whether Python
already has it; reading documentation to find out is a real skill, and
[[Getting Unstuck]] is where it gets practised.

Build the habit in [[Functions Practice]], read a complete program made
of three small functions in [[Writing Functions]], then use them to
carve up something bigger in [[Decomposition and Design]].

[^1]: Python does have a `global` keyword that lets a function reach
    out and change a variable defined outside it. It is legal, it is
    occasionally the right answer, and in this course it is almost
    never the right answer — a function that changes things nobody can
    see from the call is exactly the kind of code that is impossible
    to hand to somebody else.

%%curriculum-start%%
## Curriculum connection

![[A3.1]]

![[A3.2]]

![[B2.3]]
%%curriculum-end%%
