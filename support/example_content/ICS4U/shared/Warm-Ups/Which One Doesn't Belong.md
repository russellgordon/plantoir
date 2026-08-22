---
title: Which One Doesn't Belong
publish: true
created: __CREATED__
tags:
  - warm-ups
---
Four things go up in a two-by-two grid and the question is always the
same: which one doesn't belong? There is no answer key. Every corner
can be defended, and the defence is the point. In Grade 11 the grids
compared values, and the vocabulary you needed was *type*. This year
they compare **choices** — four containers, four algorithms — and the
vocabulary you need is the one you will use to justify a design
decision to a teammate who wanted to do it the other way.

## Grid one: four things you can do to a collection

| | |
| --- | --- |
| `names.append("Cy")` | `hours["Tuesday"]` |
| `waiting.pop(0)` | `undo.pop()` |

Only one puts something in. Only one takes nothing out, and finds
what it wants by ==name rather than position==. Only one removes from
the front, and pays for it — every remaining item shuffles down a
place, so the cost grows with the size of the collection. Only one
removes the item added most recently, which is the entire personality
of a stack.

Four corners, four defensible claims, and four ideas from
[[Choosing a Data Structure]] that are about to decide how your team
stores its data.

## Grid two: four sorts

| | |
| --- | --- |
| Bubble sort | Insertion sort |
| Selection sort | Merge sort |

Only one is normally written as a function that calls itself, and it
is also the only one that needs a second list to work in rather than
shuffling the original in place — on a very large list, that is not a
detail. Only one keeps a finished region at the front and slides each
new item back into place, exactly the way people sort a hand of
cards. Only one moves each item at most once, making the same small
number of swaps whatever the data looks like. And only one can notice
it is already finished and stop after a single pass.

Watch for the corner nobody picks. If the whole room says merge sort
because it is the odd one on speed, push back: what makes bubble sort
odd? What makes selection sort odd? An argument you can only make one
way is not an argument yet.

## How to run it

1. Show the grid. One quiet minute, and everyone picks a corner.
2. Hands up by corner. Every corner should have takers; if one is
   empty, somebody argues it anyway.
3. Defenders speak. The rule: name the ==property==, not the vibe.
   "It is the only one whose cost grows with the length of the list"
   beats "it feels slower".
4. Close by collecting on the board the vocabulary the defences used.
   That list is your justification language for
   [[The Structure Study]].

## One variation

Students build the grids. A good grid needs four properties that
overlap three ways each, which is much harder than solving one — and
building a single grid teaches more than defending ten. The best
student grids this year tend to come from real disagreements inside a
team about which container to use.

> [!tip] Argue the corner you did not pick
> Once your own corner is safe, take a different one and defend it
> just as hard. This is rehearsal: in [[The Code Review]] you will
> have to state the case for a design you would not have chosen, and
> do it well enough that its author agrees you understood it.

%%curriculum-start%%
## Curriculum connection

![[C1.1]]

![[C1.4]]
%%curriculum-end%%
