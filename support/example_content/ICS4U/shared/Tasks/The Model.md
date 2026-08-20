---
title: The Model
publish: true
created: __CREATED__
tags:
  - tasks
enableToc: true
---
> [!abstract] At a glance
> Individual · launched Unit 1, Day 10 and due Unit 1, Day 15 · four
> working periods · one class that models something real, plus the
> written defence of what you put in it and what you deliberately left
> out

## What you are making

A single class that models **one real thing that somebody in this
building actually deals with**. Not a `Car` with a `colour`. Not an
`Animal` that `makes_sound()`. A thing with a person attached to it: a
practice session, an equipment loan, a shift on a rota, a bus route, a
plant in the greenhouse, a repair ticket, a scoring run at a meet.

The code is the smaller half. The assessed half is the defence: why
these attributes and not the twenty others, why these methods, and what
you refused to model.

Here is the shape, so nobody wastes a period on syntax:

```python
class PracticeSession:
    """One logged practice session for one student."""

    def __init__(self, instrument, minutes, focus):
        self.instrument = instrument
        self.minutes = minutes
        self.focus = focus

    def is_long_enough(self):
        """A session counts toward the weekly goal at 20 minutes or more."""
        return self.minutes >= 20

    def summary(self):
        """Return one line a student could paste into their log."""
        return f"{self.instrument}: {self.minutes} min on {self.focus}"
```

That is the shape, not the standard. Yours needs more than three
attributes, at least three methods that do real work, and a reason for
every one of them.

## Choosing your thing

Go and look at it. Genuinely — walk to the music room, the equipment
cupboard, the greenhouse, the front office, the rink. Ask the person
who deals with it what they need to know about one of them, and write
their answers down in their words.

You are looking for the **nouns** in how that person talks. A noun they
say repeatedly is usually a class. A fact they always mention about it
is usually an attribute. A question they keep asking about one of them
— *is it overdue? is it full? does it count?* — is usually a method.

If the person says something you cannot model honestly, that is not a
failure. Write it on your rejected list; it may be the most
interesting thing in your submission.

## What you hand in

1. **The class**, in one file, with a docstring on the class and on
   every method, per [[Writing Code Others Can Read]].
2. **A short program below it** that creates at least three objects and
   uses every method at least once, so the file runs and shows what it
   does.
3. **The defence**, about one page:
   - the person you spoke to and what they said they need to know;
   - each attribute, with the question it lets you answer;
   - each method, with the question it answers *about one object*;
   - **the rejected list**: at least five things you considered
     modelling and did not, each with a reason. Vagueness here is the
     easiest way to lose marks on this task.
4. **One invariant**, stated plainly: a rule that must always be true
   of your object — no negative minutes, no shift ending before it
   starts — and where in the code you enforce it.

## Milestones

- [ ] **Unit 1, Day 10 — thing chosen.** The real thing, the person
      you will ask, and three attributes you already suspect are wrong.
- [ ] **Unit 1, Day 10, before you leave** — three rejected
      attributes, written down with reasons.
- [ ] **Unit 1, Day 13 — judged against the criteria table**, by you,
      with your weakest row named and the fix booked into Day 14. The
      routine is [[Judging Your Own Work]].
- [ ] **Unit 1, Day 15 — submitted.** The file runs, the defence is
      attached, and the invariant is named.

## How this is assessed

Per [[How Marks Work]], the defence carries as much weight as the code.
A perfect class with a thin defence is a partial submission; a modest
class with a sharp, honest defence is a strong one.

Your [[Code Journal]] is where the thinking lives. I expect an entry
from the day you went and looked at the real thing, and one from the
moment you cut an attribute you had been attached to. Journal entries
written after the fact read like it, every time.

The technical standard is [[Encapsulation]] — nothing outside the class
should be able to put your object into an impossible state — and the
design language is [[Objects and Classes]] and
[[Attributes and Methods]].

## Success criteria

| Quality | What it looks like in your submission |
| --- | --- |
| A real thing | Somebody deals with it; you went and looked |
| Attributes earn their place | Each answers a question the person asked |
| Behaviour lives with data | Methods, not loose functions taking your object |
| The rejected list | Five or more, each with a defensible reason |
| An enforced invariant | Named in prose, enforced in one place in code |
| Documented | Class and method docstrings a stranger could act on |
| It runs | The file executes and demonstrates every method |

## Reflect

In your journal, answer two questions. First: which attribute did you
keep only because it was easy to store, rather than because anybody
needed it? Second: your class is a claim about what matters in the
thing you modelled. Who would disagree with that claim — and would the
person you interviewed be one of them?

> [!question]- If you cannot decide what to model
> You are looking for something impressive. Stop. The best submissions
> this task produces are almost always boring objects with sharp
> defences: one loan, one shift, one delivery, one lane in one heat.
> Pick the least glamorous thing that a real person tracks on paper
> within a hundred metres of this room, and put your effort into the
> rejected list instead. If you are still stuck at the end of the
> launch class, come and see me before you leave — I keep a list of
> people in this building who are happy to be asked.

%%curriculum-start%%
## Curriculum connection

![[C1.1]]

![[C1.2]]

![[A2.2]]

![[A4.3]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

OBSERVE — Unit 1, Day 11, the working period where nouns become
classes on paper
  Watch for: what a student does when their interview notes contain a
  noun that will not sit inside the class they have drawn. Splitting
  it, folding it in, or writing it onto the rejected list are three
  different design judgements, and the submitted file shows only
  whichever one survived. The rejected list corroborates it; watching
  is how you find out whether the list is a record of thinking or a
  document assembled afterwards to fill a requirement.
  Going well: the paper gets a second box drawn on it, or a line
  crossed out with a reason written beside it.
  Stuck: every noun from the notes becomes an attribute and the
  drawing keeps growing.
  Record: three columns on the day plan — split it, folded it in, kept
  everything. Initials only; one pass of the room does it.
  That is C1.1, decomposing a problem into classes using an
  object-oriented design method, seen while it is still a decision.

TALK — Unit 1, Day 11, at the conference already on that agenda
  The agenda announces that the conference is about which of your
  classes is really two, so open past it — they will have that one
  ready.
  Ask: "Name a rule about your thing that is true out there in the
  real world and that you have decided not to enforce in code. Why
  that one?"
  Then: "Somebody else's code gets hold of one of your objects. What
  is the worst thing it could do to it without your class noticing?"
  The submission names one invariant and where it is enforced. Neither
  of these questions is that: the first asks what was deliberately
  left outside the boundary, the second asks what the boundary is
  actually holding back. A strong answer names a specific caller
  rather than "anything could, I suppose". That is C1.2, encapsulation
  applied in design, heard while the design can still change.
  Record: one line each on the conference sheet, naming the rule they
  chose to leave unenforced.

The product evidence is the file and the defence handed in on Day 15.
That one arrives on its own.
%%
