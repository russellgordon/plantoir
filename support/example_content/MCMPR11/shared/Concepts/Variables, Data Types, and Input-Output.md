---
title: Variables, Data Types, and Input-Output
publish: true
created: __CREATED__
tags:
  - concept
enableToc: true
---
Imagine you're writing the check-in screen for a self-serve kiosk at a BC
Parks campground. It should ask a camper their name and their age, then
print a greeting and tell them how old they'll be next year. A brand-new
Python programmer might write this:

```python
name = input("What's your name? ")
age = input("How old are you? ")

print("Welcome, " + name + "!")
print("Next year you'll be " + age + 1)
```

Run it, type `Sundance` and `21`, and Python refuses to cooperate:

```
TypeError: can only concatenate str (not "int") to str
```

That error is not random noise. It is Python telling you something true
about how it stores information — and once you can read it, it stops
being mysterious.

## What a variable actually holds

A **variable** is a name that points at a value stored in memory. Writing
`age = 21` does not create a box labelled `age` that magically understands
numbers; it makes the name `age` point at the value `21`. What matters is
that `21` itself belongs to a **type** — a category that decides what
operations make sense.

Python decides a value's type automatically when it's created, based on
how you write it:

- `21` is an **`int`** — a whole number.
- `21.5` is a **`float`** — a number with a decimal point.
- `"21"` is a **`str`** — text, marked out by quotes, even if it looks
  like a number.
- `True` and `False` are **`bool`** — exactly two values, used for yes/no
  questions.

`21` and `"21"` look almost identical on the page, but they behave
completely differently. `21 + 1` is arithmetic and gives `22`. `"21" + 1`
asks Python to glue text and a number together, which it refuses to do
automatically — that refusal is the exact error above.

## `input()` always hands you a string

Here's the part that trips almost everyone up at least once: no matter
what a person types at the keyboard, `input()` always returns a `str`.
Type `21`, type `twenty-one`, type nothing at all — Python doesn't look at
the characters and decide "that's a number." It just hands you back
whatever was typed, as text, every time.

That's why `age` in the broken kiosk program was a string even though a
human reading it would call `21` a number. To get an actual `int` you have
to convert it explicitly, by wrapping the call in `int()`:

```python
name = input("What's your name? ")
age = int(input("How old are you? "))

print("Welcome, " + name + "!")
print(f"Next year you'll be {age + 1}.")
```

Now `age` is a real integer, `age + 1` is real arithmetic, and the kiosk
works. If the camper types something that isn't a whole number — `"soon"`
or `"21.5"` — `int()` raises a `ValueError` rather than guessing, which is
Python being honest about a genuine problem with the input.

## `print()` and f-strings

`print()` sends text to the screen. Gluing pieces together with `+` works,
but it gets clumsy fast, and it breaks the instant you forget to convert a
number to a string first. An **f-string** — a string with an `f` right
before the opening quote — lets you drop any Python expression straight
into curly braces, and Python converts it for you:

```python
name = "Sundance"
age = 21
sites_available = 6

print(f"Welcome, {name}! You are {age}, and there are {sites_available} sites open tonight.")
```

No manual conversion, no counting `+` signs. Prefer f-strings over `+`
concatenation for anything with more than one value in it.

## Naming variables well

A variable's name is the only documentation it gets by default, so make it
count:

- Use `snake_case`: lowercase words joined by underscores — `camper_age`,
  not `CamperAge` or `camperage`.
- Name it after what it **holds**, not how it was produced —
  `nights_booked`, not `result` or `temp`.
- Avoid single letters except for short-lived loop counters like `i`, and
  avoid the letters `l`, `O`, and `I` on their own — they're easy to
  misread as `1` or `0`.
- Never reuse a built-in name like `str`, `list`, or `input` as a
  variable — doing so hides the real one for the rest of your program.

## Self-check: predict before you run

> [!question]- Predict the output (click to expand)
> What does each of these print? Decide before you look.
>
> ```python
> a = "5"
> b = 5
> print(a + a)
> print(b + b)
> print(a * 3)
> print(str(b) + a)
> ```
>
> **Answer:** `"55"`, `10`, `"555"`, `"55"`. Adding two strings glues their
> characters together rather than doing arithmetic — `"5" + "5"` is
> `"55"`, not `10`. Multiplying a string by an integer repeats it, so
> `"5" * 3` is `"555"`. The last line converts `b` to a string first with
> `str()`, so it also glues rather than adds.

%%curriculum-start%%
## Curriculum connection

![[K1.9]]

![[K1.11]]
%%curriculum-end%%
