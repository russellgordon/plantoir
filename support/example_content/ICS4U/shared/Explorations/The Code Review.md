---
title: The Code Review
publish: true
created: __CREATED__
tags:
  - explorations
enableToc: true
---
Somebody on your team wrote this yesterday. It runs. It has a
docstring. It was written by a person who is sitting in this room and
who is going to hear everything you say about it.

```python
class Booking:

    def __init__(self, name, cancelled):
        self.name = name
        self.cancelled = cancelled


def drop_cancelled(bookings):
    """Remove every cancelled booking from the list."""
    for booking in bookings:
        if booking.cancelled:
            bookings.remove(booking)
    return bookings


monday = [
    Booking("Priya", False),
    Booking("Devon", True),
    Booking("Sam", True),
    Booking("Ren", False),
]

for booking in drop_cancelled(monday):
    print(booking.name, booking.cancelled)
```

Read it before you run it. Decide whether you would approve it.

Then run it. Sam cancelled. Sam is still on Monday's list, printed
right there with `True` beside the name, and nothing crashed, nothing
warned, and no test failed — because nobody wrote one.

## The protocol

The protocol is the point of this class. It is what keeps a review
about the code and not about the person, and every team runs it the
same way so that nobody has to guess whether today is a harsh day.

```text wrap
1. The author says nothing for the first three minutes. Nothing.
2. The reviewer states what the code does, in their own words.
   If they cannot, that is the first finding, and it is about the
   code.
3. The reviewer names one thing that is genuinely good, specifically.
   Not "looks fine" — which line, and why it helped.
4. The reviewer states each concern as an observation about the
   program, with the input that shows it:
   "with two adjacent cancelled bookings, Sam survives."
5. The reviewer asks for the smallest change that would earn an
   approval. One thing, not a rewrite.
6. NOW the author speaks: what they were solving, what they already
   knew, what constraint the reviewer cannot see.
7. The reviewer states a decision out loud: approve; approve once the
   small change lands; or not yet, and what would change that.
8. Both write down what was agreed. The agreement goes in the
   history, not in anybody's memory.
```

## The task

**Round one — the planted code above.** Every pair reviews it using
the protocol, timed, with the three minutes of author silence played by
somebody pretending to be the author. Write your review out.

**Round two — real code, real author.** Now review a piece of your own
team's project, written this week by a teammate who is present. Same
protocol, same timings, same silence. Fifteen minutes each way, so
everybody is reviewed and everybody reviews.

**Round three — the agreement.** Each pair commits the agreed change,
with a message naming what the review found. Then the reviewer checks
the change and says, out loud, "approved" — or does not.

## The count

1. In round one, how many pairs approved it before running it? What did
   the docstring do to your confidence?
2. Who found the failure by reading, and who found it by running? Which
   of the two is easier to teach?
3. In round two, what was the hardest thing to say, and what was the
   hardest thing to hear? Different people, usually.
4. Step five asks for the *smallest* change that earns approval. Did
   anybody's review turn into a rewrite of somebody else's work? What
   did that cost the team?

> [!note]- Facilitation notes
> **The planted code first, always.** Nobody's feelings are on the line
> in round one, so the room can learn the protocol on code with no
> author in it. Do not skip to real project code; teams that review
> without a rehearsed protocol default to either flattery or attack.
>
> **Timing in a 70-minute period.** Fifteen minutes on round one.
> Fifteen each way for round two, strictly timed on a visible clock —
> the timer is what makes the silence survivable. Ten on round three.
> Ten on the count.
>
> **The three minutes of silence is non-negotiable and it is hard.**
> Authors interrupt to explain, and every interruption converts a
> review of the code into a defence of the person. Enforce it visibly
> the first two times and the room will enforce it themselves after
> that.
>
> **Why this particular bug.** Removing from a list while iterating
> over it skips elements. It is not exotic, it is not a typo, and no
> amount of careful reading of the docstring reveals it — the docstring
> is accurate about the *intention*. It fails only on adjacent
> cancelled bookings, which is exactly the kind of input a two-line
> test list never contains. It is the perfect argument for
> [[Testing and Regression]], made by a program that looks fine.
>
> **Model one review yourself, badly, then well.** Do thirty seconds of
> "you didn't think this through", let the room feel it, then do the
> same review properly. The contrast teaches more than the rules do.
>
> **Watch for the strongest programmer in the room.** They are usually
> the one who turns step five into a rewrite. Name it privately and
> kindly: a review that ends with your code replacing theirs has taught
> nobody anything and has cost you a teammate.
>
> **Record the agreements.** Reviews that live only in conversation
> evaporate. The commit message is the record, and in
> [[The Software Project]] it is part of the evidence of individual
> contribution.

## What tends to surface

The first surface is uncomfortable: a docstring increased everybody's
confidence and decreased nobody's error rate. The comment said what the
author meant. The code did something else. Reviewers who trusted the
prose approved a bug.

The second is that "I would have written it differently" is not a
finding. It becomes one only when it is attached to an input and a
consequence. The habit of turning taste into evidence — *this input,
this output, this is why it matters* — is most of what separates a
useful reviewer from an annoying one.

The third belongs to the author's side of the table. Being reviewed
well is a skill: staying quiet, hearing the finding rather than the
tone, and asking "what would you need to approve this?" instead of
explaining why it is fine. Half the room finds that harder than the
reviewing.

## Where this goes next

The daily, five-minute version of this is the warm-up [[Read the Diff]].
The standard your reviewers will hold you to is
[[Writing Code Others Can Read]], and the reason the planted bug
survived is the argument of [[Testing and Regression]] and the practice
of [[Writing Tests]].

Review is not an event in [[The Software Project]]; it is how code gets
onto the shared branch at all. And the last review of the semester,
where the reader is the person inheriting the work, is
[[The Handover]].

> [!note] The answer is not on this page
> The fix for `drop_cancelled` is not printed here, and there is more
> than one defensible fix. Your review is not finished when you know
> what is wrong; it is finished when you have asked for the smallest
> change you would approve, and the author has agreed to it in writing.

%%curriculum-start%%
## Curriculum connection

![[A4.3]]

![[B2.1]]
%%curriculum-end%%
