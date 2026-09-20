---
title: Predict the Output
publish: true
created: __CREATED__
tags:
  - warm-ups
---
A short Python program goes on the board. Before anyone touches a
keyboard you commit to a prediction — the exact output, in ink. Then
we run it. That much is unchanged from Grade 11. What changed is the
programs: they now contain objects, and objects can be *shared*. The
question is no longer only "what will print" but "how many things are
actually here".

## How to run it

1. Read the program twice, silently. No talking yet.
2. Before predicting the output, sketch the objects. How many lists
   exist? How many of them does each object hold?
3. Write the exact output you expect, character for character —
   brackets, quotation marks, spacing, number of lines.
4. Compare with a neighbour. The code settles disputes, not volume.
5. Run it. The gap between your prediction and Python's answer is
   today's lesson.

## Today's board

```python
class Team:
    def __init__(self, name, members):
        self.name = name
        self.members = members


roster = ["Ali", "Bea"]
seniors = Team("Seniors", roster)
juniors = Team("Juniors", roster)
seniors.members.append("Cy")
print(juniors.members)
```

Most rooms split three ways. `['Ali', 'Bea']`, because nothing was
appended to the juniors. `['Ali', 'Bea', 'Cy']`, because something
sneaky is going on. A crash, because surely you cannot do that.

> [!success]- What Python actually prints
> ```text
> ['Ali', 'Bea', 'Cy']
> ```
>
> There is only **one list** in this program. `roster` names it,
> `seniors.members` names it, and `juniors.members` names it — three
> names, one object. Appending through any of those names changes the
> thing all three refer to. Ask Python directly and it agrees:
>
> ```python
> print(seniors.members is juniors.members)
> ```
>
> That prints `True`. The word `is` asks "same object?", not merely
> "equal contents?".
>
> The fix is to give each team its own list, by copying at the door:
> `self.members = list(members)`. Now there are two lists and the
> surprise is gone.

## One variation

Reverse it. Show only the output and let pairs write a program that
produces it. At this level the interesting version is: produce
`['Ali', 'Bea', 'Cy']` twice from two different objects — once
because they genuinely share a list, once because they hold separate
lists that happen to match. The two programs behave identically today
and diverge the moment somebody appends. That difference is the whole
point of [[Objects and Classes]].

> [!tip] Predict the state, not just the printout
> A printed line is one frame of a film. The prediction worth writing
> down is what every object *holds* after the program has run. Half
> the bugs in [[The Software Project]] will be a value that two
> objects were quietly sharing, and the print statement that finally
> revealed it will look exactly like this warm-up.

%%curriculum-start%%
## Curriculum connection

![[A1.1]]

![[A1.2]]

![[A1.3]]
%%curriculum-end%%
