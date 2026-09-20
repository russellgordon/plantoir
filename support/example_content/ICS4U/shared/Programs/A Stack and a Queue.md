---
title: A Stack and a Queue
publish: true
created: __CREATED__
tags:
  - programs
---
The library has one copy of the exam study guide and, later in the course, a
waiting list for it. It also has a front desk where somebody types
fast and occasionally types wrong, and wants the last thing they did
taken back.

Both are lists. Neither is a *list*, in the sense that matters: what
each one needs is not "store these items" but a promise about which
item comes out next. The hold list must give the guide to whoever
asked first, and everybody can see whether it did. The undo history
must give back the most recent action, because that is the one that
was a mistake.

## The program

```python
# The library front desk. Two containers, two different promises.
#
# The hold list for the one copy of the exam study guide is a QUEUE:
# whoever asked first is served first, and everybody can see that.
# The desk's undo history is a STACK: the mistake you want to take
# back is nearly always the thing you just did.

class Stack:
    """Last in, first out."""

    def __init__(self):
        # Internal storage. Other code should use the methods below,
        # not reach in here.
        self._items = []

    def push(self, item):
        """Put an item on the top of the stack."""
        self._items.append(item)

    def pop(self):
        """Remove and return the top item. Precondition: not empty."""
        if self.is_empty():
            return None
        return self._items.pop()

    def peek(self):
        """Return the top item without removing it, or None if empty."""
        if self.is_empty():
            return None
        return self._items[-1]

    def is_empty(self):
        """True when there is nothing on the stack."""
        return len(self._items) == 0

    def size(self):
        """How many items are on the stack."""
        return len(self._items)


class Queue:
    """First in, first out."""

    def __init__(self):
        self._items = []

    def enqueue(self, item):
        """Join the back of the line."""
        self._items.append(item)

    def dequeue(self):
        """Remove and return the front item. Precondition: not empty."""
        if self.is_empty():
            return None
        return self._items.pop(0)

    def front(self):
        """Return the front item without removing it, or None if empty."""
        if self.is_empty():
            return None
        return self._items[0]

    def is_empty(self):
        """True when nobody is waiting."""
        return len(self._items) == 0

    def size(self):
        """How many are waiting."""
        return len(self._items)


holds = Queue()
undo = Stack()

print("Three people ask for the study guide, in this order.")
for name in ["Nadia", "Rowan", "Bea"]:
    holds.enqueue(name)
    undo.push(f"added {name} to the hold list")
    print(f"  waiting: {holds.size()}, next up: {holds.front()}")

print()
print("The copy comes back in. Who gets it?")
print(f"  {holds.dequeue()} gets the study guide")
print(f"  still waiting: {holds.size()}, next up: {holds.front()}")
undo.push("issued the study guide to Nadia")

print()
print("The clerk realises the last action was a mistake.")
print(f"  undoing: {undo.pop()}")
print(f"  the action before that was: {undo.peek()}")
print(f"  undo history remaining: {undo.size()}")

print()
print("Clearing the rest of the hold list, in order:")
while not holds.is_empty():
    print(f"  {holds.dequeue()}")
print(f"  empty now? {holds.is_empty()}")
print(f"  asking an empty queue for its front gives {holds.front()}")
```

```text
Three people ask for the study guide, in this order.
  waiting: 1, next up: Nadia
  waiting: 2, next up: Nadia
  waiting: 3, next up: Nadia

The copy comes back in. Who gets it?
  Nadia gets the study guide
  still waiting: 2, next up: Rowan

The clerk realises the last action was a mistake.
  undoing: issued the study guide to Nadia
  the action before that was: added Bea to the hold list
  undo history remaining: 3

Clearing the rest of the hold list, in order:
  Rowan
  Bea
  empty now? True
  asking an empty queue for its front gives None
```

## How it works

Both classes store their items in an ordinary Python list. That is not
a shortcut — it is the point. A stack is not a *kind of storage*, it
is a *set of promises about access*, and the promises are kept by
which methods exist.

> [!abstract] Two containers, one difference
> A **stack** adds and removes at the same end: `append` and `pop()`.
> The last thing in is the first thing out, which is why it models
> undo, browser history, and the pile of frames Python keeps while
> [[Recursion]] runs.
> A **queue** adds at one end and removes at the other: `append` and
> `pop(0)`. The first thing in is the first thing out, which is why it
> models hold lists, print jobs, and every fair line-up in the world.

Look at what the classes do **not** provide. There is no `insert`, no
`get(index)`, no way to jump the queue. Somebody who has your `Queue`
object cannot move Bea to the front by accident, because the class
does not offer a way to do it. Restricting the operations is how a
container makes a promise it can keep — and in this program, the
promise is *fairness*, which is not a technical property at all.

The leading underscore in `self._items` is a message to other
programmers: this is internal, do not touch it. Python will not stop
anybody — `holds._items.insert(0, "Sam")` runs perfectly well and
quietly ruins the hold list. The convention matters anyway, and
[[Encapsulation]] is where that argument gets made properly.

Every method that removes something checks `is_empty()` first, so
`dequeue` on an empty queue returns `None` instead of crashing. That
is a design decision, not the only correct one: `self._items.pop(0)`
on an empty list raises `IndexError: pop from empty list`, which is
louder and, in some programs, better. Returning `None` suits a front
desk that must stay open; raising suits a program where an empty queue
means something has already gone badly wrong. Choose, then say which
you chose in the docstring — that is the precondition, written down.

## Change it

1. **One line.** Change `undo.pop()` to `undo.peek()` in the "mistake"
   section. The line still prints
   `undoing: issued the study guide to Nadia`, but the history no
   longer shrinks: the next line now reports that same action as "the
   action before that", and `undo history remaining` becomes `4`.
   Removing and looking are different operations, and mixing them up
   is the most common stack bug there is.
2. **A few lines.** Add a method to `Queue` that answers the question
   every person on a hold list asks:
   ```python
   def position_of(self, item):
       """Return how many people are ahead of item, or -1 if absent."""
       for index in range(len(self._items)):
           if self._items[index] == item:
               return index
       return -1
   ```
   With all three waiting, `holds.position_of("Bea")` is `2` and
   `holds.position_of("Priya")` is `-1`. After Nadia is served, Bea's
   answer is `1`. Note that this method is allowed to read `_items`
   directly — it is *inside* the class, which is where the underscore
   rule does not apply.
3. **A real change.** Put objects in the queue instead of strings.
   Reuse the `Volunteer` class from [[Objects in a List]], or write a
   small `Hold` class holding a name and the date the hold was placed,
   and give it a `__str__`. Nothing in `Queue` changes — not one line
   — because the class never asked what its items were. That is
   reusability you can point at, and it is what
   [[Choosing a Data Structure]] means by an abstract data type.

The ideas are in [[Stacks and Queues]]; the drill is in
[[Stacks and Queues Practice]]. If you have not yet met a program that
needed one of these, [[The Wrong Container]] is where the need shows
up in person.

%%curriculum-start%%
## Curriculum connection

![[C1.1]]

![[C1.2]]

![[C2.1]]
%%curriculum-end%%
