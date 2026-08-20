---
title: Final Examination
publish: true
created: __CREATED__
tags:
  - tasks
  - final-evaluation
enableToc: true
---
> [!abstract] At a glance
> Written on paper, alone, with no machine · three hours in the
> examination period · reaches across all four units, and asks for the
> reasoning as often as for the code

## What it is for

Everything else in this semester was built with time, help, a
repository, and at least one person to ask. That is what professional
work is like and it is why the course is shaped that way. This is the
one afternoon where the only thing on the desk is what you carry in
your head — not to catch anybody out, but because a course that never
asks that question cannot honestly claim to know what you can do
alone.

It is also the only piece of evidence in the course that no team can
carry and no team can sink.

## What the paper contains

| Part | About | What you do in it |
| --- | --- | --- |
| A. Reading it cold | 20% | Trace objects and recursive calls by hand and state exactly what comes out |
| B. Design on paper | 25% | Turn a described problem into classes, and choose containers with reasons |
| C. Algorithms and analysis | 30% | Write searches, sorts and recursive routines; state and compare their costs |
| D. Practice and consequences | 25% | Short answers on testing, version control, documentation, ethics, footprint, and emerging technology |

Part C is the largest because judging an algorithm — not merely
producing one — is what separates this course from last year's. Part B
is next because everything in Unit 3 and Unit 4 rested on decisions
made in Unit 1.

## What to expect, precisely

- **Tracing.** Two programs of twenty to forty lines. One builds a
  list of objects and walks it, asking what each object holds by the
  end; one is recursive and asks for the call stack drawn as it grows
  and unwinds. Tables are provided; use them. The technique is exactly
  [[Trace It]].
- **Arithmetic that is not decimal.** Integer division and remainders,
  in at least two questions: one where the answer turns on which of
  the two a division gives you, and one that only comes out if you use
  the remainder for something.
- **Values changing type, and values being compared.** A number
  arriving as text and needed as a number, and the reverse; and an
  ordering question about things that are not numbers, where the point
  is that sorted text puts "10" before "9" and a person would not.
  Expect one short program where the conversion is where the bug is.
- **Where the representation runs out.** One question about the edges
  of how a machine stores numbers — the comparison that should be true
  and is not, or the total that drifts. Say what you would do instead,
  and why it works.
- **Design.** A paragraph describing somebody's real problem — the
  kind [[The Model]] sent you into the building to find. Name the
  classes, their attributes and their methods, say which rule must
  never be broken and where you would enforce it, and name one thing
  you would refuse to model and why.
- **Splitting the work up.** One long routine printed in full, and the
  question of where you would cut it into subprograms — what each
  piece is handed and what it hands back. Marks are in the seams, not
  in the number of pieces.
- **Reuse.** A short question about something you already built: which
  part of the class you wrote in Unit 1 would you bring into this
  problem unchanged, which part would need changing, and what makes
  the difference.
- **Containers.** A stated problem with its operations listed. Choose
  between a list, a dictionary, and a stack or queue; give the cost of
  each operation under your choice; and name the input at which you
  would change your mind. A defended second-best answer scores above
  an undefended best one.
- **Algorithms.** Write a linear or binary search and one sort from a
  description rather than from memorised code, state the precondition
  each depends on, and compare two algorithms by counting comparisons
  rather than by asserting which is faster. Expect at least one
  question that walks a grid row by row, and at least one recursive
  routine where the marks are in the base case.
- **Short answers.** Four or five, a paragraph each. What a
  regression test is for and what it costs you to skip it; what a
  commit history is evidence of; what belongs in documentation a
  stranger will read; two elements of a published code of ethics and
  why a profession needs one written down; one emerging technology,
  who gains and who carries the cost; one honest measure that reduces
  computing's footprint, and its limit.

## How to prepare

1. **Re-derive, do not re-read.** Take a class you wrote in Unit 1
   and rebuild it from your own defence document without opening the
   file. Reading a page you already understand will not tell you what
   you could rebuild without it.
2. **Count, do not time.** The examination has no machine on it, so
   practise the comparison counts by hand — a linear search and a
   binary search over the same twenty items, on paper, until the
   difference is something you can see rather than recite.
3. **Work the practice sets you skipped.** [[Recursion Practice]],
   [[Searching Practice]], [[Sorting Practice]] and
   [[Efficiency Practice]] were written for exactly this, and the
   questions you left undone are the ones worth doing now.
4. **Read your own journal.** The entries written on the days
   something broke are the densest revision material you own, exactly
   because you wrote them while the understanding was arriving rather
   than afterwards.
5. **Bring questions to Unit 4, Days 22 to 24.** Those three classes
   are review, and they run on what the room asks. This page is the
   full statement of what is on the examination; the review classes
   are for the parts of it you cannot yet do.

> [!tip] Writing code with a pen
> Indent as if the interpreter were watching, because a marker is.
> If an exact method name escapes you, write what you mean, name it
> clearly and carry on — a routine with one imperfect line and a
> structure a reader can follow earns nearly everything. A blank
> space earns nothing at all, and a paragraph explaining what you
> would have written earns more than the blank space.

## Success criteria

| Quality | What it looks like on the paper |
| --- | --- |
| Traces are worked, not guessed | A table with a row per step, filled in as you go |
| Designs are defensible | Every attribute answers a question somebody would ask |
| Choices carry reasons | The container and the algorithm are argued, with costs |
| Preconditions stated | What must be true before your code is correct, written down |
| Costs are counted | Comparisons counted or growth stated, not asserted |
| Recursion terminates | A base case, and every call moving towards it |
| Short answers are specific | A named example, not a general opinion |

## How this is assessed

On exactly the expectations this course has been working towards since
September. Per [[How Marks Work]], this paper and [[The Handover]] together
make up the thirty per cent that is not the semester's tasks, and the
bigger share of it sits here. The other seventy is the semester's six
tasks and the milestone entries in your journal,
[[The Software Project]] included.

%%curriculum-start%%
## Curriculum connection

![[A1.1]]

![[A1.2]]

![[A1.3]]

![[A1.4]]

![[A1.5]]

![[A2.2]]

![[A3.2]]

![[A3.4]]

![[A3.5]]

![[A3.6]]

![[C1.1]]

![[C1.2]]

![[C1.3]]

![[C1.4]]

![[C2.1]]

![[C2.2]]

![[C2.3]]

![[C2.4]]

![[D1.1]]

![[D2.2]]

![[D3.1]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

Say the awkward thing first: an examination is product evidence and
nothing else. There is no observing and no conversing in an
examination room, and attempting either is a different problem
entirely. So the observation and conversation evidence for these
expectations has to come from the three review classes that lead into
it, while it can still change how somebody prepares.

OBSERVE — Unit 4, Day 23, review part two, writing a search and a
sort from descriptions
  Watch for: whether the precondition gets written down before the
  loop or reconstructed afterwards, once the complexity has to be
  defended. Both students leave the review class with working code and
  the right complexity beside it, so the page they take away does not
  separate them; only the order they worked in does, and that is
  C2.1 — the starting state an algorithm depends on — seen rather than
  claimed.
  Going well: a line of prose above the function saying what must be
  true of the data, written first.
  Stuck: binary search coded straight out, sortedness mentioned only
  when you ask where the log n came from.
  Record: three columns on the day plan — stated first, stated after,
  not stated. It takes one pass of the room.

TALK — Unit 4, Day 25, at the individual conferences already on that
agenda
  That agenda promises a conversation about where each student stands
  and what they want next, so they will arrive with that one prepared.
  Open somewhere else. Put two sort routines on the desk, one
  quadratic and one merge, both correct, and ask: "Which of these
  would you put in front of a partner's data, and what would you need
  to know about the data before you decided?"
  Then: "You counted comparisons for both of these in Unit 3. Which
  number surprised you, and what had you expected instead?"
  A strong answer names a property of the data — nearly sorted, mostly
  duplicates, arriving a few at a time — and follows it to a choice,
  rather than reciting two complexities. That is C2.3, comparing the
  efficiency of sorting algorithms, heard rather than written. A
  student who freezes on paper can be fluent here, and this is the
  last chance in the course to find that out.
  Record: one line each on the conference sheet, and the property they
  named.

The product evidence is the examination paper itself, which arrives
without any help from you.
%%
