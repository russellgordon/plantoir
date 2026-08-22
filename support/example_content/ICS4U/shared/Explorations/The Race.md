---
title: The Race
publish: true
created: __CREATED__
tags:
  - explorations
enableToc: true
---
Two programs. Same input, same output, same answer, every time. One of
them finishes before you have let go of the Enter key. The other one
you can watch.

You are handed both, already written. You are not asked to fix
anything. You are asked to explain the gap.

## Program A

```python
import random
import time

random.seed(4)
catalogue = []
for number in range(40000):
    catalogue.append(f"BK-{number:05d}")

requests = []
for count in range(3000):
    requests.append(f"BK-{random.randint(0, 59999):05d}")

start = time.perf_counter()

found = 0
for wanted in requests:
    for title in catalogue:
        if title == wanted:
            found = found + 1
            break

elapsed = time.perf_counter() - start
print(f"found {found} of {len(requests)}")
print(f"took {elapsed:.3f} seconds")
```

## Program B

```python
import random
import time

random.seed(4)
catalogue = []
for number in range(40000):
    catalogue.append(f"BK-{number:05d}")

requests = []
for count in range(3000):
    requests.append(f"BK-{random.randint(0, 59999):05d}")

start = time.perf_counter()

on_shelf = {}
for title in catalogue:
    on_shelf[title] = True

found = 0
for wanted in requests:
    if wanted in on_shelf:
        found = found + 1

elapsed = time.perf_counter() - start
print(f"found {found} of {len(requests)}")
print(f"took {elapsed:.3f} seconds")
```

Both programs answer the same question: of the 3,000 requested titles,
how many are in the catalogue of 40,000? Both print the same count.
On the machine these pages were written on, A took about 1.9 seconds
and B took about 0.002 seconds. Your numbers will differ. The ratio
will not differ much.

## The task

**Job one — predict.** Before running anything, write down which is
faster and by how much. Commit to a number: twice? ten times? a
thousand times? Nearly everybody underestimates.

**Job two — run both, three times each.** Record all six timings.
Three runs, because one run is an anecdote. Use
[[Profiling and Timing Code]] for the honest way to do this.

**Job three — change the size, not the code.** Run both again with the
catalogue at 10,000 and then at 80,000, leaving the requests at 3,000.
Make a table. Four rows, two columns of times.

**Job four — the sentence.** In your group, finish this: *"When the
catalogue doubles, program A takes … and program B takes …"*. That
sentence is the finding. It is worth more than either timing.

## The count

On the board, all together:

1. Whose prediction was closest, and what did they use to guess?
2. What happened to A's time when the catalogue doubled? What happened
   to B's?
3. Program B does *extra* work that A never does — it builds a whole
   second container before it starts counting. How can doing more work
   be faster?
4. Is there a catalogue size at which A wins? Argue it, then test it.

> [!note]- Facilitation notes
> **Do not say the words.** Not "linear", not "quadratic", not "order
> n", not "Big-O", not "hash". None of it, for the whole period. The
> vocabulary arrives in Unit 3, Day 8, and it arrives as a *name for a
> table the room already made*. Saying it today costs you the whole
> arc.
>
> **Timing in a 70-minute period.** Five minutes on predictions,
> collected in writing so nobody quietly revises. Fifteen on jobs two
> and three. Fifteen building the shared table on the board — every
> group's numbers, not a summary. Twenty on the count. Ten to write the
> journal entry while the table is still up.
>
> **The table is the artefact.** Keep the doubling table. On Unit 3,
> Day 8 you will point at it and say "this row has a name", and Big-O
> will be a
> description of something the room measured rather than a definition
> they were handed.
>
> **The honest wrinkle, if the room is strong.** Question four is real.
> For a catalogue of ten items, A is faster, because B pays to build a
> container that is never worth building. Let a group find the
> crossover experimentally. "It depends on the size" is a more
> sophisticated conclusion than "B is better", and it is true.
>
> **Machines will disagree.** Older machines, shared machines, and
> machines with something else running will all give different
> absolute numbers, and this bothers students more than you expect.
> Point at the ratios. The ratio survives the hardware; that is exactly
> why the field ended up talking about growth rather than seconds.
>
> **Seeded on purpose.** `random.seed(4)` makes every group's data
> identical, so the counts match across the room and only the timings
> vary. If a group deletes the seed line, their count will differ, and
> that is a five-minute lesson in reproducibility worth having.

## What tends to surface

The room's first explanation is almost always "B is faster because
dictionaries are fast", which explains nothing and stops the thinking.
Push once: *why* is it faster, in terms of what each program does 3,000
times? A searches the catalogue for each request. B asks one question
per request. The difference is not the speed of an operation; it is the
number of operations.

The second surface is that the machine's speed is the least interesting
variable in the room. A faster laptop moves every number down and
changes nothing about the shape of the table. What the students have
actually measured is a property of the *algorithm*, not of the hardware
it ran on, and that is a genuinely new idea for most of them.

The third is uncomfortable and worth sitting with: program A is
perfectly correct. It will never give a wrong answer. It is simply
unusable at a size that a real library reaches in a year.

## Where this goes next

The measuring habit is [[Profiling and Timing Code]]. The specific case
of finding one thing in many is [[Searching]], measured properly in
[[Searching and Timing It]]. Then order comes into it in [[Sorting]],
and finally the room's doubling table gets its name in
[[Efficiency and Big-O]].

By [[The Software Project]] this is no longer academic: you will choose
an algorithm for a partner's real data and be asked, out loud, why.

> [!note] The answer is not on this page
> The explanation for the gap is not written here, and neither is the
> vocabulary for it. Your room's board table *is* the explanation, in
> its rawest and most convincing form. Photograph it. You will be shown
> it again in three classes, when somebody finally gives it a name.

%%curriculum-start%%
## Curriculum connection

![[C2.2]]
%%curriculum-end%%
