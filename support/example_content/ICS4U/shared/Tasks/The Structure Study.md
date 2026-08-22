---
title: The Structure Study
publish: true
created: __CREATED__
tags:
  - tasks
enableToc: true
---
> [!abstract] At a glance
> Individual · launched Unit 2, Day 10 and due Unit 2, Day 16 · four
> working periods · one problem solved three ways, timed and measured,
> with a written judgement about which container actually fits

## What you are making

**One problem. Three solutions. One defensible answer.**

You choose a small problem that involves storing things and getting
them back out again. You then solve it three times:

1. with a **list**,
2. with a **dictionary**,
3. with a **stack or a queue** — whichever the problem can be honestly
   bent to fit.

Then you write the study: what each version cost you to write, what
each one costs to run, what each one makes easy, what each one makes
dangerous, and which one you would actually ship. The three programs
are the evidence. The judgement is the task.

## Choosing your problem

Small, real, and with more than one plausible shape. Good examples from
previous classes:

- the sign-out sheet for the equipment cupboard;
- a print queue for the shared printer in the library;
- the undo history in a drawing tool;
- who is next on the rota to lock up;
- a lookup of room numbers by teacher name;
- the order that tickets get served at the office window.

Notice that some of those *sound* like a queue and some sound like a
lookup. Picking a problem where the answer is obvious wastes the task.
Pick one where at least two of the three are genuinely arguable.

## The work

For each of the three versions:

- **Write it and make it correct.** All three must actually run and
  produce the same answers on the same input. If they disagree, the
  study is about a bug, not about containers.
- **State the operations honestly.** For each version, list the
  operations your problem needs — add one, find one, remove one, show
  all, take the next — and say what each one costs. Count comparisons
  where you can; time it where counting is impractical, using
  [[Profiling and Timing Code]].
- **Break it on purpose.** Find the input that makes this version
  embarrassing. Every container has one. A study that reports no
  weakness for a version has not looked hard enough.
- **State the precondition.** What must be true before your code runs
  for it to be correct — sorted, non-empty, no duplicate keys? Say it
  in prose and enforce it or document it.

## What you hand in

1. **Three working programs**, in one file each, with docstrings.
2. **One shared test input** that all three run on, including at least
   one awkward case: a duplicate, an empty structure, a removal from
   the middle.
3. **The study**, about a page and a half:
   - a table of the operations against the three containers;
   - the input that embarrasses each version;
   - your recommendation, with the size of data at which you would
     change your mind;
   - one paragraph on what you would lose by choosing your
     recommendation — every choice costs something.

## Milestones

- [ ] **Unit 2, Day 10 — problem chosen**, with the reason at least
      two containers are arguable for it.
- [ ] **Unit 2, Day 12 — the operation list, costed.** Every
      operation your problem needs, with what it costs under each of
      the three containers, and every one of those costs worked out
      rather than remembered.
- [ ] **Unit 2, Day 13 — the shared test input written**, awkward
      cases included: a duplicate, an empty structure, a removal from
      the middle.
- [ ] **Unit 2, Day 14 — judged against the criteria table** by you,
      with your weakest row named and the fix booked into Day 15. The
      routine is [[Judging Your Own Work]], and the row you cannot
      defend is the thing to bring to that day's conference.
- [ ] **Unit 2, Day 16 — submitted.** Three versions, one shared test
      input, and the study with a recommendation you can say out loud.

## How this is assessed

Per [[How Marks Work]], the judgement carries more weight than the
code, and an honest recommendation for a container you personally find
less elegant scores higher than a tidy defence of the fashionable one.

Your [[Code Journal]] carries the thinking: an entry when you chose the
problem, and — the important one — an entry from the moment one of your
three versions turned out worse than you predicted. Being wrong in
writing, with the measurement beside it, is exactly the evidence this
task is looking for.

The concepts behind it are [[Dictionaries]], [[Stacks and Queues]], and
above all [[Choosing a Data Structure]]. If your problem is naturally
self-similar, [[Recursion]] may be the honest shape of one version —
say so, and mind the base case.

## Success criteria

| Quality | What it looks like in your study |
| --- | --- |
| A genuinely arguable problem | At least two containers plausibly fit |
| Three correct versions | Same input, same answers, all three run |
| Operations costed | Comparisons counted or run times measured |
| Weaknesses found | Each version has a named embarrassing input |
| Preconditions stated | What must be true before the code is correct |
| A real recommendation | One choice, defended, with a change-my-mind size |
| Honest about the cost | What your recommendation gives up, in prose |

## Reflect

In your journal: which version did you want to win before you started,
and did the measurements agree with you? Then the question that matters
for next unit — if this were your community partner's data, and it grew
by a hundred times over three years, would your recommendation still be
the same?

> [!question]- If all three versions feel forced
> Then your problem is too simple, and forcing it is teaching you the
> wrong lesson. A problem that only ever adds to the end and reads from
> the front is a queue, and no amount of writing will make the
> dictionary version interesting. Swap to a problem with at least two
> different questions asked of the same data — "who is next?" *and*
> "how many times has this person been served?" — and all three
> containers suddenly have something to say. Ask me in the working
> period rather than spending an evening defending a foregone
> conclusion.

%%curriculum-start%%
## Curriculum connection

![[C1.1]]

![[A3.3]]

![[C2.1]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

OBSERVE — Unit 2, Day 12, the working period where each operation
gets a cost written beside it
  Watch for: where the cost comes from. A student who works out that a
  removal from the middle has to shift everything after it is doing
  something entirely different from a student writing down the number
  they remember belongs there, and by the end of the period the two
  tables are indistinguishable. The finished study reports the costs;
  it cannot report whether they were derived or recalled.
  Going well: a small example on scrap paper with the steps counted,
  or a sentence out loud that begins "it has to walk the whole".
  Stuck: costs appearing at the speed of handwriting, or the same
  three verdicts — fast, slow, slow — copied down the column with no
  step counted anywhere.
  Record: two columns on the day plan — worked it out, wrote it down.
  Initials only; one pass of the room.
  That is A3.3 — creating the subprograms that insert and delete
  elements — met at the point where a student either understands what
  those operations actually do to a structure or does not, which is
  invisible once the code runs and the table is typed up.

TALK — Unit 2, Day 14, at the conference already on that agenda
  That agenda tells them the conference is about the operation they
  are least sure of, so they will arrive with that prepared. Start
  somewhere else.
  Ask: "After your remove-one operation has run, what is true of the
  structure that was not true before it? And is that answer the same
  for all three of your versions?"
  Then: "Which of the three would you have to warn somebody about
  before they could use it safely, and what is the sentence you would
  say?"
  A strong answer describes an ending state rather than restating what
  the operation does, and can say where the three versions differ.
  That is C2.1 — analysing a precondition and a postcondition — and
  the written study asks for preconditions in prose, so a student can
  meet it on paper without ever having thought about what the code
  leaves behind. This is where you find out.
  Record: one line each on the conference sheet.

The product evidence is the three programs and the study handed in on
Day 16.
%%
