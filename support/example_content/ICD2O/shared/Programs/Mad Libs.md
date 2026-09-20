---
title: Mad Libs
publish: true
created: __CREATED__
tags:
  - programs
---
Five answers from the user, poured into a story that was written with
holes in it. Nothing here but [[Data in Programs|variables and strings]]
— and the `+` operator doing all the heavy lifting.

## The program

```python
print("The story machine needs five words. Choose recklessly.")

name = input("A friend's name: ")
animal = input("An animal: ")
adjective = input("A describing word: ")
food = input("A food: ")
number = input("A number: ")

story = name + " woke up to find a " + adjective + " " + animal
story = story + " in the kitchen. It had already eaten " + number
story = story + " plates of " + food + " and showed no sign of stopping."

print()
print("--- YOUR STORY ---")
print(story)
print("The end. Run me again for a different disaster.")
```

## Read it before you run it

Predict in writing first — then run the program and grade yourself.

- Count the variables. Which lines *create* them, and which lines
  *use* them?
- The story is built in three steps. Say out loud what `story` holds
  after the second of the three `story =` lines.
- `number` is never converted with `int()`. Why does this program get
  away with that, when the guessing game could not?

## Make it yours

1. **One line.** Extend the story with one more sentence that reuses
   a word the user already gave.
2. **A few lines.** Ask for a sixth word — a place, perhaps — and
   weave it into the story.
3. **A real change.** Write two different endings, then let
   `random.randint(1, 2)` and an `if` choose between them. The same
   words now tell different stories on different runs.

%%curriculum-start%%
## Curriculum connection

![[C1.3]]

![[C2.1]]

![[C3.1]]
%%curriculum-end%%
