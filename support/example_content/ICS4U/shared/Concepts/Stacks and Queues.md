---
title: Stacks and Queues
publish: true
created: __CREATED__
tags:
  - concepts
---
Two requests arrived from the library in the same week. The front desk
wanted an undo button, because somebody keeps deleting the wrong hold.
And the students waiting for the one copy of the exam study guide
wanted to know that the list was fair — that asking first meant
getting it first.

Both are "keep a bunch of things in order". They are not the same
container, and the difference is not how the items are stored. It is
which item is allowed out next.

## A promise about which one comes out next

```text
STACK - last in, first out          QUEUE - first in, first out

   push        pop                    enqueue              dequeue
      \       /                          \                    /
       v     v                            v                  v
     +---------+                     +---------------------------+
     | deleted |  <- top             | Nadia | Rowan | Bea |       |
     +---------+                     +---------------------------+
     | added   |                       ^ front            ^ back
     +---------+
     | opened  |  <- bottom
     +---------+
```

A **stack** adds and removes at the same end. The last thing in is the
first thing out, which is exactly what undo needs: the mistake you
want to take back is the thing you just did.

A **queue** adds at one end and removes at the other. The first thing
in is the first thing out, which is exactly what a hold list needs,
because that is what fairness means to the person waiting.

In Python, both can be built on an ordinary list:

```python
history = []
history.append("opened the roster")   # push
history.append("added Sam")
history.append("deleted Bea")
print(history.pop())                  # pop - takes the last one
```

```text
deleted Bea
```

```python
line = []
line.append("Nadia")                  # enqueue
line.append("Rowan")
line.append("Bea")
print(line.pop(0))                    # dequeue - takes the first one
```

```text
Nadia
```

One character of difference — `pop()` against `pop(0)` — and a
completely different promise. That is precisely why neither should be
left as a bare list in a real program.

## Wrap it in a class, so the promise cannot be broken

If the hold list is just a list, then any line of code anywhere can
call `line.insert(0, "Sam")` and put somebody at the front. Nothing
stops it, nothing records it, and nobody notices until a student who
waited three weeks watches somebody else walk off with the book.

Wrap it in a `Queue` class that offers `enqueue`, `dequeue`, `front`,
and `is_empty` — and *nothing else* — and queue-jumping is no longer
possible by accident, because the class does not provide a way to do
it. That is what an **abstract data type** is: not a storage layout,
but a named set of operations with promised behaviour, whose insides
are nobody else's business. [[Encapsulation]] is the mechanism;
[[A Stack and a Queue]] is the working code.

| | Stack | Queue |
| --- | --- | --- |
| Add | `push` | `enqueue` |
| Remove | `pop` | `dequeue` |
| Look without removing | `peek` | `front` |
| Order | Last in, first out | First in, first out |
| Models | undo, history, backtracking | hold lists, print jobs, fairness |

## You are already using a stack

Every time your program calls a function, Python pushes a frame onto
its **call stack** — a note saying where to come back to. When the
function returns, that frame is popped. It is the same structure, and
you have already seen it printed out: a traceback is the call stack,
listed from the outside in.

```python
def is_balanced(text):
    """True when every ( in text is closed by a ) in the right order."""
    open_brackets = []
    for character in text:
        if character == "(":
            open_brackets.append(character)
        elif character == ")":
            if len(open_brackets) == 0:
                return False
            open_brackets.pop()
    return len(open_brackets) == 0
```

```text
'(a + (b * c))': True
'(a + b))': False
'((a + b)': False
```

Bracket matching is the classic stack problem, and it is not a toy:
some version of it runs in the editor you are typing in. Notice the
two ways it can fail — a `)` with nothing open, caught immediately,
and leftovers on the stack at the end, caught by the last line.

> [!tip] `pop(0)` is fine for a class list, and wrong for a big one
> Removing from the front of a Python list shifts every remaining item
> down one place, so a dequeue costs more as the queue grows. For a
> hold list of thirty students that is invisible. For a queue of a
> million jobs it matters, and real systems use a structure built for
> it. Say which one you have: knowing when a simple choice stops being
> good enough is what [[Efficiency and Big-O]] is for.

The other place a stack turns up whether you asked for it or not is
[[Recursion]] — that is what "maximum recursion depth" is counting.
Practise both containers in [[Stacks and Queues Practice]], decide
between them and everything else in [[Choosing a Data Structure]], and
revisit [[The Wrong Container]], where the hold list first refused to
behave like a list.

%%curriculum-start%%
## Curriculum connection

![[C1.1]]

![[C1.2]]

![[C2.1]]
%%curriculum-end%%
