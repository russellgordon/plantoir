---
title: Choosing a Data Structure
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
By the middle of Unit 2 the room had four containers and a bad habit:
whichever one we had learned most recently was the one everybody
reached for. [[The Structure Study]] exists to break that habit — one
problem, solved three ways, and a written defence of which solution
you would actually hand over.

There is no best container. There is only the question the program
asks most often, and the container that answers it cheaply.

## Four questions, asked in this order

- [ ] **How is it looked up?** By position (`roster[3]`), by name
      (`hours["Rowan"]`), or only ever in order, one at a time?
- [ ] **Does order matter, and whose order?** Arrival order, sorted
      order, or none at all?
- [ ] **What changes, and where?** Adding at the end is cheap in a
      list; adding at the front is not. Deleting by key is cheap in a
      dictionary; finding the largest value is not.
- [ ] **What must be impossible?** If nobody may jump the queue, use a
      structure that offers no way to — see [[Stacks and Queues]].

Answer those four out loud and the container usually picks itself. Two
of the four are about *people*, not data: whose order, and what must
be impossible.

## What each one is good at

| Container | Good at | Bad at | Reach for it when |
| --- | --- | --- | --- |
| List | Order, position, appending, looping | Finding by name; inserting at the front | The data has a natural sequence |
| Dictionary | Lookup by key; tallying | Order by value; duplicate keys | The question is "which one is X's?" |
| Stack | Undo, backtracking, nesting | Anything needing fairness | The most recent item matters most |
| Queue | Fair service, buffering | Reaching the middle | First come, first served |
| List of objects | Modelling records that travel together | Nothing much, at classroom sizes | Each item has several fields |

That last row is the workhorse of this course. A list of `Volunteer`
objects, as in [[Objects in a List]], keeps a whole record together
*and* keeps the records in order — and when you also need lookup by
name, the answer is usually both: a list for order, and a dictionary
from name to object for speed.

## The cost, measured

We asked the same question of a list and a dictionary — *is this
member in there?* — for a name that was not present, which is the
worst case for a list:

```text
   size    list (s)    dict (s)
   1000  0.00000498  0.00000001
  10000  0.00005147  0.00000001
 100000  0.00052145  0.00000002
```

The list column multiplies by ten when the data does, because `in` on
a list is a linear search. The dictionary column does not move,
because a dictionary computes where the key would be instead of
looking for it. Those are $O(n)$ and average $O(1)$ — the vocabulary
is in [[Efficiency and Big-O]].

> [!warning] What that table is not
> One machine, one afternoon, one Python. Your absolute numbers will
> differ; the *shape* will not. And "average $O(1)$" is an honest
> average, not a guarantee — a dictionary can do worse when keys
> collide, and it uses more memory than a list to buy that speed.
> There is always a trade; the professional habit is to name it rather
> than to pretend it is free.

Two structures you will not build this year but should recognise when
somebody else's program has them: a **set**, which is a dictionary
with keys and no values and answers "have I seen this before?" fast;
and a **tree**, which keeps things in sorted order while still
allowing fast insertion. Naming them is enough for now.

## Say why, in writing

The mark in [[The Structure Study]] is not for the code — all three
versions will work. It is for the paragraph that says *this one, for
this reason, at this size, with this trade-off accepted*. That
paragraph is also what your teammates read when they inherit your half
of [[The Software Project]], and what saves them from replacing a
deliberate choice with a "simpler" one that breaks later in the course.

> [!tip] Two containers is a legitimate answer
> Keeping a list *and* a dictionary that point at the same objects is
> normal and often correct: the list preserves order, the dictionary
> makes lookup instant, and both refer to the same `Volunteer` objects
> so nothing is duplicated. The cost is that both must be updated
> together — which means exactly one method may be allowed to do it.

Practise the reasoning in [[Dictionaries Practice]] and
[[Stacks and Queues Practice]], and see the moment the wrong container
becomes obvious in [[The Wrong Container]].

%%curriculum-start%%
## Curriculum connection

![[C1.1]]

![[A1.5]]

![[A3.3]]
%%curriculum-end%%
