---
title: Data in Programs
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
[[Mad Libs]] and [[The Dice Roller]] look like cousins, but under the
hood they handle opposite kinds of cargo — one stitches text
together, the other does arithmetic on numbers. Programs care about
that difference far more than people do.

## Three kinds of data

| Kind       | Python name    | Example      | Built for                     |
| ---------- | -------------- | ------------ | ----------------------------- |
| Numbers    | `int`, `float` | `17`, `9.75` | arithmetic and comparing      |
| Text       | `str`          | `"hello"`    | joining, printing, replacing  |
| True/false | `bool`         | `True`       | decisions in [[Conditionals]] |

`17` and `"17"` look almost identical on screen. To Python they are
as different as a number and a photograph of a number — only one of
them can do math.

## Why the type matters

`input()` always hands you text, no matter what the user typed. That
one fact is the source of a whole family of beginner bugs:

```python
guests = input("How many guests? ")   # user types 4
print(guests * 2)        # prints 44 — text gets repeated
print(int(guests) * 2)   # prints 8 — convert, then do math
```

The fix is one honest question: *what kind of data is this, really?*
Half the mysteries in [[Spot the Bug]] dissolve the moment you ask
it.

## Expressions and order of operations

When writing expressions that combine numbers, text, or comparisons,
Python evaluates operators in a strict order of operations:

1. **Parentheses `()`** — evaluate innermost brackets first.
2. **Exponents `**`** — powers calculated next.
3. **Multiplication `*`, Division `/`, Floor Division `//`, Modulo `%`** —
   evaluated left to right.
4. **Addition `+`, Subtraction `-`** — evaluated left to right (`+` also
   concatenates strings).
5. **Comparisons (`<`, `<=`, `>`, `>=`, `==`, `!=`)** — produce boolean
   `True` or `False`.
6. **Logical operators (`not`, `and`, `or`)** — evaluate boolean logic.

Understanding precedence prevents subtle logic errors, such as calculating
an average `(a + b) / 2` versus `a + b / 2`. [[Operators Practice]] drills
these evaluation rules.

## Where data comes from

Programs rarely invent their data. It arrives from a person typing at
`input()`, from chance — `random.randint` rolling for
[[The Dice Roller]] — from files you saved earlier, or from another
program entirely. Wherever it comes from, the first job is always the
same: know its type, convert it if needed, and only then put it to
work. [[Variables and Expressions Practice]] drills exactly that
routine until it is reflex.

%%curriculum-start%%
## Curriculum connection

![[C1.3]]

![[C1.4]]

![[C2.2]]
%%curriculum-end%%
