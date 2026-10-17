---
title: Input and Output
publish: true
codeRunner: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
A program with its numbers typed into the source code has exactly one
user: the person willing to edit the source code. The moment you hand
your chair-counting script to Mr. Diaz and he asks "how do I change it
to ten rows?", the program needs a mouth and an ear.

## Asking a question

```python
answer = input("How many rows of chairs? ")
rows = int(answer)
```

`input()` prints the prompt, waits for the person to type something and
press return, and hands back what they typed — always as text, never as
a number. The `int()` on the second line is not decoration. Skip it and
`rows * 12` will either fail or, worse, succeed strangely: `"8" * 12`
is a perfectly legal Python expression that produces `8` repeated
twelve times.

Do the conversion on its own line while you are learning. Writing
`rows = int(input("How many rows? "))` is common and correct, but the
one-line version hides which half broke when it breaks.

## Showing the answer

```python run readonly
name = "Priya"
minutes = 185
hours = minutes / 60

print(f"Thanks, {name}.")
print(f"You practised {minutes} minutes — that is {hours:.1f} hours.")
```

```
Thanks, Priya.
You practised 185 minutes — that is 3.1 hours.
```

An **f-string** is a string with an `f` in front, and anything inside
`{ }` gets replaced by its value. The `:.1f` is a format instruction:
one digit after the decimal point. Without it that line reads "that is
3.0833333333333335 hours", which is true, useless, and slightly rude.
`print()` on its own prints a blank line — cheap and effective when
output is getting crowded.

## The prompt is the interface

For most of this course, your prompts *are* your user interface. Two
versions of the same question:

```python
days = input("Days? ")
```

```python
days = input("Days past the due date (0 if on time): ")
```

The second one answers three questions the person would otherwise have
to guess: days of what, measured from when, and what to type when
nothing is late. A prompt that needs explaining out loud is a prompt
that needs rewriting — and you will not notice that yourself, which is
the entire argument of [[Who Is This For]].

## When the answer is not a number

People type `seven`. People type nothing at all and press return.
`int()` refuses, loudly, and the program stops:

```
ValueError: invalid literal for int() with base 10: 'seven'
```

You can catch that instead of crashing:

```python run readonly
answer = input("Minutes practised: ")

try:
    minutes = int(answer)
except ValueError:
    print(f"I could not read '{answer}' as a number of minutes.")
    minutes = 0
```

Python attempts the indented block after `try:`. If a `ValueError`
happens anywhere in it, the `except ValueError:` block runs instead of
the program stopping. Notice the second decision hiding in there:
recording zero is a choice, and not obviously the right one. Deciding
what a program should do about a person's mistake is design work, not
error handling — which is what [[The Bad Input Hunt]] is for.

> [!question]- Self-check: what does this print if the user types 3.5?
> (click to expand)
> ```python run readonly
> count = int(input("How many? "))
> print(count)
> ```
> Nothing. It crashes with
> `ValueError: invalid literal for int() with base 10: '3.5'`. `int()`
> converts text that spells a *whole* number and nothing else — not
> `3.5`, not `3 dogs`, not an empty line. Use `float()` when a decimal
> answer is legitimate.

Practise the mechanics in [[Variables and Types Practice]], then read a
complete program that asks, converts, and answers in
[[Talking to the User]].

%%curriculum-start%%
## Curriculum connection

![[A2.1]]

![[B1.3]]

![[B2.5]]
%%curriculum-end%%
