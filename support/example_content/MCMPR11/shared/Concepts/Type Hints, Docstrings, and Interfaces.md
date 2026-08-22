---
title: Type Hints, Docstrings, and Interfaces
publish: true
created: __CREATED__
tags:
  - concept
enableToc: true
---
You open a Python file you wrote three weeks ago for a wind-chill
calculator and find this function, with no memory of writing it:

```python
def calc(t, w):
    return 13.12 + 0.6215 * t - 11.37 * w**0.16 + 0.3965 * t * w**0.16
```

What is `t`? A temperature — but in Celsius or Fahrenheit? What is `w` —
wind speed in km/h, m/s, knots? Does this return a number, and in what
unit? Nothing in the function tells you, and you're the person who wrote
it. A teammate opening this file for the first time has no chance at all.

## A signature is a promise

Every function has an **interface** — the part someone calling it needs
to know, without reading a single line inside it: its name, what it
expects as input, and what it hands back. Right now, `calc(t, w)` makes
almost no promise at all. Two small additions fix that.

**Type hints** annotate each parameter and the return value with the kind
of data expected:

```python
def calc(t: float, w: float) -> float:
```

This tells a reader — and tools like your editor — that `t` and `w`
should be numbers with decimal places, and the function hands back one
too. Python doesn't enforce this at runtime; you could still call
`calc("cold", "windy")` and get a crash somewhere inside.[^1] The hint is
documentation with a precise, checkable shape, not a guardrail.

[^1]: A separate tool called a static type checker — `mypy` is the most
      common one — can read your type hints and warn you about a mismatch
      like that *before* you ever run the program. It's worth knowing
      such tools exist, even if this course doesn't require one.

**Docstrings** fill in what a type hint can't: what the parameters *mean*
and what units they're in. A docstring is a string literal, in triple
quotes, right after the `def` line:

```python
def calculate_wind_chill(temp_celsius: float, wind_kmh: float) -> float:
    """Estimate wind chill using Environment Canada's formula.

    Args:
        temp_celsius: Air temperature in degrees Celsius.
        wind_kmh: Wind speed in kilometres per hour.

    Returns:
        The estimated wind chill, in degrees Celsius.
    """
    return (
        13.12
        + 0.6215 * temp_celsius
        - 11.37 * wind_kmh**0.16
        + 0.3965 * temp_celsius * wind_kmh**0.16
    )
```

## Before and after

| | Undocumented | Typed and documented |
| --- | --- | --- |
| Parameter names | `t`, `w` | `temp_celsius`, `wind_kmh` |
| Units | Unknown — guess or dig through call sites | Stated in the docstring |
| Expected type | Unknown | `float`, right in the signature |
| Return meaning | Unknown | "wind chill, in degrees Celsius" |
| Calling it correctly | Trial and error | Read the signature once |

Nothing about *what the function computes* changed between the two
versions. What changed is how much a reader has to reconstruct before
they can trust it.

## Reading someone else's interface first

This matters most exactly when you're not the one who wrote the code —
a partner's function during a pair programming session, or your own work
from weeks ago, which by then is functionally a stranger's. Before you
call a function you didn't just write, read its signature and docstring
first, rather than opening its body and tracing through the logic line by
line. A well-typed, well-documented function lets you use it correctly
without ever reading how it works inside — which is the entire point of
decomposing a program into functions in the first place.

Writing the hints and the docstring costs you thirty seconds now. Skipping
them costs whoever reads it next — often you — much longer, later, when
the context is gone.

%%curriculum-start%%
## Curriculum connection

![[D7.3]]

![[K1.14]]

![[K1.9]]
%%curriculum-end%%
