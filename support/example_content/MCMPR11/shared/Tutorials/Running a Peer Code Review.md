---
title: Running a Peer Code Review
publish: true
created: __CREATED__
tags:
  - tutorials
enableToc: true
---
This is the course's standing protocol for reviewing a classmate's code.
You'll come back to this page many times across all four units, whenever
a class day asks you to review a partner's work — it's written to run
without a teacher walking you through it live, so read it once carefully
now and you can move fast every time after.

## The two roles

Every review has an **author** and a **reviewer**, and you'll be both,
usually in the same class.

- The **author** hands over working code — something that runs, even if
  it doesn't handle every case yet — and says what they'd specifically
  like feedback on, if anything.
- The **reviewer** reads the code, runs it if they can, and gives
  feedback using the rubric and sentence starters below. The reviewer's
  job is not to find fault — it's to notice what a fresh pair of eyes can
  see that the author, three hours into their own code, no longer can.

## The rubric

Read down this list while you review. You don't need to comment on every
row for every piece of code, but check all four before you call a review
finished.

| Check | Ask yourself |
| --- | --- |
| **Correctness** | Does it actually do what it's supposed to? Run it, don't just read it. |
| **Readability** | Could you understand this without the author explaining it out loud? |
| **Handles bad input** | What happens with an empty list, a zero, a blank string? Does it crash, or handle it? |
| **One genuine compliment** | What's actually good here? Name it specifically — this one is required, not optional. |

That last row is not a courtesy add-on. A review that only lists problems
teaches an author to dread reviews; naming something that's genuinely
well done is part of the feedback, because it tells the author what to
keep doing, not only what to fix.

## Giving feedback that's specific and kind

Vague feedback ("this is confusing") gives the author nothing to act on.
Feedback aimed at the person rather than the code ("you always forget
this") isn't useful either, and it isn't kind. These sentence starters
push you toward feedback that's both:

- **"I noticed..."** — describe what you actually saw, not your
  interpretation of it. *"I noticed this function is 40 lines long"*
  rather than *"this function is a mess."*
- **"What happens if..."** — ask about a case rather than declaring it
  broken. *"What happens if the list passed in is empty?"* invites the
  author to check, rather than putting them on the defensive.
- **"Have you considered..."** — offer an alternative without demanding
  it. *"Have you considered a dictionary here instead of nested lists?"*
  leaves the decision with the author, who knows the rest of their
  program better than you do.

> [!warning] What to avoid
> "This is wrong" states a conclusion with no path forward. "Why would
> you do it this way" reads as a challenge, not a question. Both shut a
> conversation down instead of opening one. If you catch yourself about
> to write either, rewrite it as an "I noticed" or a "what happens if"
> instead — the specific problem underneath is usually still worth
> raising, just not that way.

## Running the review

1. **Author shares the code** and says what, if anything, they'd like a
   second opinion on. (2 minutes)
2. **Reviewer reads silently first**, then runs it if possible, working
   down the rubric. (5 minutes)
3. **Reviewer talks through their notes out loud**, using the sentence
   starters — author listens and asks clarifying questions rather than
   defending each line as it comes up. (5 minutes)
4. **Author decides what to change.** Feedback is information, not an
   order — the author owns their own code and chooses what to act on
   before the next class.

Budget about **10 minutes per review**. If you're reviewing more than one
piece of code in a class, that's roughly how many rounds will fit in a
single period — plan accordingly rather than rushing the last one.

## Building on what the author already has

The rubric above is mostly about noticing. The most valuable part of a
review is usually the next step after noticing: **offering a possibility
the author had not considered**, without taking the decision away from
them.

The move is to add to their idea rather than replace it. "You could use
a dictionary here" replaces. "Your list works, and if the lookup ever
runs inside the loop, a dictionary keyed on the station name would let
you skip the search — worth it only if that loop gets long" adds
something to what they built and hands back the judgement about whether
it is worth doing.

Where two reviewers suggest different things, put both on the author's
list rather than arguing about which is right in front of them. A review
that produces three possibilities is more useful than one that produces a
verdict, because the author knows things about their own program that
neither of you do.

## What the author does with it

Feedback that changes nothing was a conversation, not a review. Before
the period ends, the author writes a short list — on paper or in the
issue tracker, it does not matter — with every suggestion raised, and
one of three decisions beside each:

| Decision | When it is the right call | What to write |
| --- | --- | --- |
| **Doing it now** | It is a correctness problem, or it is cheap and clearly better | The commit that will carry it |
| **Doing it later** | It is a real improvement but not on the path to the next milestone | What would have to be true for it to move up the list |
| **Not doing it** | You considered it and the trade-off does not suit your program | The reason — this is the most valuable entry of the three |

**Prioritising is the skill here, not agreeing.** You will finish a
review with more good ideas than you have periods left, and a list where
everything is important is a list you will ignore. Rank by what breaks
if you skip it: a case that produces a wrong answer outranks a structure
that offends a reviewer's taste, every time.

Carry that list into your next working period and into
[[Learning Journey Log]] — "changed X because Y raised Z" is exactly the
kind of entry that shows your design responding to evidence rather than
to preference. And when you decline a suggestion in writing, with a
reason, you have done something better than taking it: you have shown
you understood it.

## For the author, receiving feedback

Listen for the specific observation underneath the comment, rather than
the tone it arrived in. "What happens if the list is empty?" is not an
accusation — it's a genuine question, and "I don't know, let me check" is
a completely fine answer in the moment. You decide what to change; a
reviewer's job ends at raising the question, not at controlling your
code.

%%curriculum-start%%
## Curriculum connection

![[D3.2]]

![[D3.4]]

![[D5.3]]

![[D5.1]]

![[D7.5]]
%%curriculum-end%%
