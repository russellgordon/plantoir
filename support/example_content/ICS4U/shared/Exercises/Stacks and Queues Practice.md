---
title: Stacks and Queues Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Stacks and Queues]]. Both containers hold
things in order; they differ only in which one is allowed out next,
and that difference is usually a promise to a person.

## Reading and choosing

1. **Predict all four printed lines.**
   ```python
   line = []
   line.append("Nadia")
   line.append("Rowan")
   line.append("Bea")
   print(line.pop())
   print(line.pop(0))
   print(line)
   print(len(line) == 0)
   ```
2. For each job, name the structure and say what would go wrong with
   the other one: (a) the library's hold list for one copy; (b) undo
   in an editor; (c) print jobs sent to one printer; (d) checking that
   every opening bracket is closed; (e) students waiting to speak in a
   class discussion.
3. **Find the fault.** The hold list serves the wrong person. What is
   the single-character change?
   ```python
   def next_hold(holds):
       """Return the person who has been waiting longest."""
       return holds.pop()
   ```

## Writing

4. Write a `Stack` class with `push`, `pop`, `peek`, `is_empty`, and
   `size`, storing its items in `_items`. Show what happens when you
   pop one more time than you pushed.
5. Write `is_balanced(text)` using a stack: `True` when every `(` is
   closed by a `)` in the right order. Test it on `"(a + (b * c))"`,
   `"(a + b))"`, `"((a + b)"`, and `"no brackets"`.
6. Write `reversed_text(text)` using a stack — push every character,
   then pop them all back off.
7. Write a `BoundedStack` that keeps only the most recent `limit`
   items, dropping the oldest when it overflows. Push four actions
   with a limit of three and show what survives.
8. Add `position_of(item)` to a `Queue` class, returning how many
   people are ahead of somebody, or `-1` if they are not waiting.
   Show a whole hold list being served in order.
9. **Judgement.** Your `Queue` uses `self._items.pop(0)`. A teammate
   says this is "inefficient and should be fixed". Under what
   circumstances are they right, under what circumstances does it not
   matter, and what would you need to measure before changing it?

## Answers

> [!success]- Answer 1
> ```text
> Bea
> Nadia
> ['Rowan']
> False
> ```
> `pop()` takes from the end — stack behaviour. `pop(0)` takes from
> the front — queue behaviour. One list, two completely different
> promises, distinguished by one argument, which is exactly why a bare
> list is a poor choice for either job.

> [!success]- Answer 2
> (a) **Queue** — a stack would serve the most recent request first,
> and the person who waited three weeks would watch somebody else get
> the book. (b) **Stack** — the mistake you want undone is the last
> thing you did; a queue would undo your first action of the morning.
> (c) **Queue**, for the same fairness reason as (a). (d) **Stack** —
> the bracket that must close next is the most recently opened one.
> (e) **Queue**, and note that this one is not a technical
> requirement at all: it is what the room means by taking turns.

> [!success]- Answer 3
> `pop()` removes the *last* person to join — the newest hold, not the
> oldest. The person who has waited longest is at the front:
> ```python
> def next_hold(holds):
>     """Return the person who has been waiting longest."""
>     return holds.pop(0)
> ```
> One character, and the difference between a fair hold list and a
> program that quietly punishes patience. It would also pass any test
> that only ever put one person in the list.

> [!success]- Answer 4
> ```python
> class Stack:
>     """Last in, first out."""
>
>     def __init__(self):
>         self._items = []
>
>     def push(self, item):
>         """Put an item on top."""
>         self._items.append(item)
>
>     def pop(self):
>         """Remove and return the top item, or None if empty."""
>         if self.is_empty():
>             return None
>         return self._items.pop()
>
>     def peek(self):
>         """Return the top item without removing it, or None if empty."""
>         if self.is_empty():
>             return None
>         return self._items[-1]
>
>     def is_empty(self):
>         """True when nothing is on the stack."""
>         return len(self._items) == 0
>
>     def size(self):
>         """How many items are on the stack."""
>         return len(self._items)
>
>
> undo = Stack()
> undo.push("added Sam")
> undo.push("deleted Bea")
> print(undo.peek(), undo.size())
> print(undo.pop(), undo.pop(), undo.pop())
> print(undo.is_empty())
> ```
> ```text
> deleted Bea 2
> deleted Bea added Sam None
> True
> ```
> The third `pop` returns `None` rather than crashing, because the
> class checks first. Raising an exception instead would also be
> defensible — what is not defensible is leaving it undocumented, so
> the docstring says which one you chose.

> [!success]- Answer 5
> ```python
> def is_balanced(text):
>     """True when every ( in text is closed by a ) in the right order."""
>     open_brackets = []
>     for character in text:
>         if character == "(":
>             open_brackets.append(character)
>         elif character == ")":
>             if len(open_brackets) == 0:
>                 return False
>             open_brackets.pop()
>     return len(open_brackets) == 0
> ```
> ```text
> '(a + (b * c))': True
> '(a + b))': False
> '((a + b)': False
> 'no brackets': True
> ```
> Two different failures, caught in two different places: a `)` with
> nothing open fails immediately, and leftovers on the stack fail at
> the last line. Text with no brackets at all is balanced — an edge
> case worth having a test for.

> [!success]- Answer 6
> ```python
> def reversed_text(text):
>     """Return text backwards, using a stack."""
>     letters = []
>     for character in text:
>         letters.append(character)
>     result = ""
>     while len(letters) > 0:
>         result = result + letters.pop()
>     return result
>
>
> print(reversed_text("holds"))
> ```
> ```text
> sdloh
> ```
> Reversal is what a stack *is*: things come out in the opposite order
> to the way they went in. Python has shorter ways to reverse a
> string; the point here is to see the structure doing the work.

> [!success]- Answer 7
> ```python
> class BoundedStack:
>     """A stack that remembers only the most recent limit items."""
>
>     def __init__(self, limit):
>         self._items = []
>         self._limit = limit
>
>     def push(self, item):
>         """Add an item, dropping the oldest if the stack is full."""
>         self._items.append(item)
>         if len(self._items) > self._limit:
>             self._items.pop(0)
>
>     def pop(self):
>         """Remove and return the newest item, or None if empty."""
>         if len(self._items) == 0:
>             return None
>         return self._items.pop()
>
>     def size(self):
>         """How many items are held."""
>         return len(self._items)
>
>
> history = BoundedStack(3)
> for action in ["one", "two", "three", "four"]:
>     history.push(action)
> print(history.size(), history.pop(), history.pop(), history.pop(),
>       history.pop())
> ```
> ```text
> 3 four three two None
> ```
> `"one"` is gone: a bounded undo history forgets its oldest entry,
> which is what every editor you have used actually does. Notice that
> this class adds at one end and *discards* at the other — it is a
> stack for its users and a queue internally, which is a good sign
> that these are promises about access, not layouts.

> [!success]- Answer 8
> ```python
>     def position_of(self, item):
>         """How many are ahead of item, or -1 if it is not waiting."""
>         for index in range(len(self._items)):
>             if self._items[index] == item:
>                 return index
>         return -1
>
>
> holds = Queue()
> for name in ["Nadia", "Rowan", "Bea", "Ali"]:
>     holds.enqueue(name)
> print(holds.position_of("Bea"), holds.position_of("Priya"))
>
> served = []
> while not holds.is_empty():
>     served.append(holds.dequeue())
> print(served)
> ```
> ```text
> 2 -1
> ['Nadia', 'Rowan', 'Bea', 'Ali']
> ```
> The method may read `_items` directly because it is *inside* the
> class — that is where the underscore convention does not apply. The
> service order is exactly the arrival order, which is the promise the
> class exists to keep.

> [!success]- Answer 9
> They are right when the queue is long and dequeued constantly:
> `pop(0)` shifts every remaining item down one place, so each dequeue
> costs $O(n)$ and clearing a queue of $n$ items costs $O(n^2)$. At a
> million print jobs that is the difference between working and not.
>
> It does not matter for a hold list of thirty students, or any queue
> that is short or rarely emptied — and the simple version is easier
> to read and to hand over.
>
> Before changing anything, measure: how long is the queue in the real
> data, how often is `dequeue` called, and what fraction of the
> program's time is spent there? [[Profiling and Timing Code]] has the
> method. "Optimising" a queue that was never the slow part costs
> readability and buys nothing, which is the argument in
> [[Efficiency and Big-O]].

%%curriculum-start%%
## Curriculum connection

![[A1.5]]

![[A3.3]]

![[C1.1]]

![[C1.2]]

![[C2.1]]
%%curriculum-end%%

