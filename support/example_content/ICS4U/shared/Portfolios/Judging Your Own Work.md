---
title: Judging Your Own Work
publish: true
created: __CREATED__
tags:
  - portfolio
---
You already know how to do this. [[The Code Review]] taught the room a
protocol for looking at work without arguing about the person who made
it, and every one of its moves survives being pointed inward. That is
the whole idea of this page: **review your own submission before I
do**, using the criteria table on the task page as the thing you are
reviewing against.

The first time, we run it together on a finished piece of work that
belongs to nobody in the room, so that the move is not new to you on
the day it is your own program in front of you.

## The protocol, pointed inward

The review protocol has an author and a reviewer, and today they are
both you. Take the reviewer's chair first, and do not let the author
speak until step four.

```text
1. State what your work does, in your own words, without looking at
   what you meant it to do. If you cannot, that is finding number one.
2. Find the criteria row you meet best and say WHY, naming the file,
   the function, the commit or the paragraph. Practising the evidence
   on an easy row is what makes it possible on a hard one.
3. Go down every remaining row and put yes, partly, or not yet beside
   it, each with the same kind of evidence. A yes with nothing under
   it is a wish, and you will believe it.
4. Now the author answers: what you were solving, what you already
   knew, what the reader cannot see.
5. Name the smallest change that would move one row. One thing, not a
   rewrite.
6. Write the decision down, with a period beside it: which change,
   which class, done.
```

Step three is the work. Everything else is bookkeeping around it.

## The row you would not approve

There will be one — your **weakest row**, which is the name the task
pages give it. In a real review it is the row where you would say
"not yet" to somebody else and hope nobody says it to you — and the
temptation is to fix the cheapest row instead, because the cheap fix
feels like progress and takes eleven minutes.

Do the opposite. Name the row you would refuse to approve, then decide
whether it can be moved in the time left. Sometimes it cannot, and the
honest outcome is a sentence in your [[Code Journal]] saying so, and
why, and what you would need. That sentence is worth more to both of
us than a tidied margin.

> [!example]- What one row looks like when it is done properly
> From [[The Structure Study]]: *"Weaknesses found — each version has
> a named embarrassing input."*
>
> **Partly.** The list version breaks on a removal from the middle
> and that is written up. Against the dictionary version I put "no
> real weakness found", which is not true — I never tried duplicate
> keys, because I knew roughly what would happen and did not fancy
> explaining it. This is the row I would refuse to approve.
> **Smallest change:** run all three on duplicate keys next period
> and write up what the dictionary quietly does with them.
>
> Seven rows marked yes would have taken less time and told me
> nothing.

## Two things the criteria table cannot see

This course puts two kinds of evidence in front of you that no task
page can print a row for, and both are worth the same treatment.

- **Your history.** Read your own commits as a stranger would: do the
  messages say what changed and why, and is the work spread through
  the weeks or bunched into two evenings? A document can be improved
  the night before. A log cannot — only from today forward, which is
  precisely why looking at it early is worth anything at all.
- **Your reviews.** Read back what you wrote on a teammate's change.
  An observation with the input that produces it is contribution; an
  opinion about the code is decoration. You will be able to tell which
  you wrote.

## Why none of this reaches your mark

It cannot, and that is deliberate rather than a technicality:
[[How Marks Work]] keeps your verdict on your own work, and a
classmate's verdict on it, out of the percentage entirely. Since
nothing you write here can cost you anything, there is no reason left
to be generous with yourself — which is the only condition under which
a self-check is worth running.

What it changes is the work. Most of you end the semester doing some
version of this without being asked, in the last ten minutes before
anything is submitted, and that habit outlasts every mark it rescues.

> [!tip] Put the verdict in the journal, not in your head
> A self-check written into your [[Code Journal]] gets a date on it,
> and a dated verdict is the only kind [[Showing Growth]] can use in
> June. It is also the fastest way to find out whether you act on
> your own findings — the entry that says "not yet" in October and
> the entry that says "fixed it, and here is the commit" in November
> are the same claim, three weeks apart, with proof in between.
